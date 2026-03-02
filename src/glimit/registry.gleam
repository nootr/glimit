//// This module contains a registry which maps hit identifiers to rate limiter actors.
////

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import glimit/rate_limiter
import glimit/utils

const call_timeout = 1000

const sweep_call_timeout = 10

const sweep_batch_size = 50

pub type RateLimiterRegistryActor(id) =
  Subject(Message(id))

/// The rate limiter registry state.
///
type State(id) {
  State(
    /// The maximum number of tokens.
    ///
    max_token_count: fn(id) -> Int,
    /// The rate of token generation per second.
    ///
    token_rate: fn(id) -> Int,
    /// The registry of rate limiters.
    ///
    registry: Dict(id, Subject(rate_limiter.Message)),
    /// The interval in milliseconds between sweeps.
    ///
    sweep_interval_ms: Option(Int),
    /// The actor's own subject for self-messaging.
    ///
    self_subject: Subject(Message(id)),
  )
}

pub type Message(id) {
  /// Get the rate limiter for the given id or create a new one if missing.
  ///
  GetOrCreate(
    identifier: id,
    reply_with: Subject(Result(Subject(rate_limiter.Message), Nil)),
  )
  /// Return a list of rate limiters.
  ///
  GetAll(reply_with: Subject(List(#(id, Subject(rate_limiter.Message)))))
  /// Remove a rate limiter from the registry.
  ///
  Remove(identifier: id, reply_with: Subject(Nil))
  /// Fire-and-forget sweep, used by send_after for periodic scheduling.
  ///
  Sweep
  /// Synchronous sweep variant for tests.
  ///
  SweepSync(reply_with: Subject(Nil))
  /// Internal: continue processing remaining entries of a chunked sweep.
  ///
  SweepBatch(entries: List(#(id, Subject(rate_limiter.Message))))
}

fn handle_get_or_create(
  identifier,
  state: State(id),
) -> Result(Subject(rate_limiter.Message), Nil) {
  case state.registry |> dict.get(identifier) {
    Ok(existing) -> {
      let is_alive = case process.subject_owner(existing) {
        Ok(pid) -> process.is_alive(pid)
        Error(_) -> False
      }
      case is_alive {
        True -> Ok(existing)
        // Dead process — create a replacement
        False -> {
          use rl <- result.try(rate_limiter.new(
            state.max_token_count(identifier),
            state.token_rate(identifier),
          ))
          Ok(rl)
        }
      }
    }
    Error(_) -> {
      use rate_limiter <- result.try(rate_limiter.new(
        state.max_token_count(identifier),
        state.token_rate(identifier),
      ))
      Ok(rate_limiter)
    }
  }
}

/// Sweep a batch of entries, shutting down full/dead limiters and removing them
/// from the registry.
///
fn do_sweep(
  entries: List(#(id, Subject(rate_limiter.Message))),
  state: State(id),
) -> State(id) {
  let #(to_remove, _to_keep) =
    entries
    |> list.partition(fn(pair) {
      let #(_, rl) = pair
      // Remove unresponsive or dead rate limiters (unwrap to True)
      utils.safe_call(rl, rate_limiter.HasFullBucket, sweep_call_timeout)
      |> result.unwrap(True)
    })

  list.each(to_remove, fn(pair) {
    let #(_, rl) = pair
    rate_limiter.shutdown(rl)
  })

  let registry =
    state.registry
    |> dict.drop(list.map(to_remove, fn(pair) { pair.0 }))

  State(..state, registry: registry)
}

fn schedule_sweep(state: State(id)) -> Nil {
  case state.sweep_interval_ms {
    Some(ms) -> {
      let _ = process.send_after(state.self_subject, ms, Sweep)
      Nil
    }
    None -> Nil
  }
}

fn handle_message(
  state: State(id),
  message: Message(id),
) -> actor.Next(State(id), Message(id)) {
  case message {
    GetOrCreate(identifier, client) -> {
      case handle_get_or_create(identifier, state) {
        Ok(rate_limiter) -> {
          let registry = state.registry |> dict.insert(identifier, rate_limiter)
          let state = State(..state, registry: registry)
          actor.send(client, Ok(rate_limiter))
          actor.continue(state)
        }
        Error(_) -> {
          actor.send(client, Error(Nil))
          actor.continue(state)
        }
      }
    }

    GetAll(client) -> {
      let rate_limiters =
        state.registry
        |> dict.to_list

      actor.send(client, rate_limiters)
      actor.continue(state)
    }

    Remove(identifier, client) -> {
      case state.registry |> dict.get(identifier) {
        Ok(rl) -> rate_limiter.shutdown(rl)
        Error(_) -> Nil
      }
      let registry = state.registry |> dict.delete(identifier)
      let state = State(..state, registry: registry)
      actor.send(client, Nil)
      actor.continue(state)
    }

    Sweep -> {
      let entries = state.registry |> dict.to_list
      actor.send(state.self_subject, SweepBatch(entries))
      actor.continue(state)
    }

    SweepSync(client) -> {
      let entries = state.registry |> dict.to_list
      let state = do_sweep(entries, state)
      actor.send(client, Nil)
      actor.continue(state)
    }

    SweepBatch(entries) -> {
      let #(batch, remaining) = list.split(entries, sweep_batch_size)
      let state = do_sweep(batch, state)
      case remaining {
        [] -> {
          schedule_sweep(state)
          actor.continue(state)
        }
        _ -> {
          actor.send(state.self_subject, SweepBatch(remaining))
          actor.continue(state)
        }
      }
    }
  }
}

/// Create a new rate limiter registry.
///
pub fn new(
  per_second: fn(id) -> Int,
  burst_limit: fn(id) -> Int,
) -> Result(RateLimiterRegistryActor(id), Nil) {
  let sweep_interval_ms = Some(10_000)

  actor.new_with_initialiser(call_timeout, fn(self_subject) {
    let state =
      State(
        max_token_count: burst_limit,
        token_rate: per_second,
        registry: dict.new(),
        sweep_interval_ms: sweep_interval_ms,
        self_subject: self_subject,
      )

    schedule_sweep(state)

    Ok(
      actor.initialised(state)
      |> actor.returning(self_subject),
    )
  })
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.map_error(fn(_) { Nil })
}

/// Get the rate limiter for the given id or create a new one if missing.
///
pub fn get_or_create(
  registry: RateLimiterRegistryActor(id),
  identifier: id,
) -> Result(Subject(rate_limiter.Message), Nil) {
  utils.safe_call(registry, GetOrCreate(identifier, _), call_timeout)
  |> result.flatten
}

/// Return a list of rate limiters.
///
pub fn get_all(
  registry: RateLimiterRegistryActor(id),
) -> List(#(id, Subject(rate_limiter.Message))) {
  utils.safe_call(registry, GetAll, call_timeout)
  |> result.unwrap([])
}

/// Remove a rate limiter from the registry.
///
pub fn remove(
  registry: RateLimiterRegistryActor(id),
  identifier: id,
) -> Result(Nil, Nil) {
  utils.safe_call(registry, Remove(identifier, _), call_timeout)
}

/// Remove full buckets from the registry.
///
pub fn sweep(registry: RateLimiterRegistryActor(id)) -> Result(Nil, Nil) {
  utils.safe_call(registry, SweepSync, call_timeout)
}
