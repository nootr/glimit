//// This module contains a registry which maps hit identifiers to rate limiter actors.
////

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import glimit/rate_limiter

const call_timeout = 1000

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

/// Like process.call but returns Result instead of panicking on timeout or
/// callee death.
///
fn safe_call(
  subject: Subject(message),
  make_request: fn(Subject(reply)) -> message,
  timeout: Int,
) -> Result(reply, Nil) {
  case process.subject_owner(subject) {
    Error(_) -> Error(Nil)
    Ok(callee) -> {
      let reply_subject = process.new_subject()
      let monitor = process.monitor(callee)
      process.send(subject, make_request(reply_subject))

      let result =
        process.new_selector()
        |> process.select_map(reply_subject, fn(reply) { Ok(reply) })
        |> process.select_specific_monitor(monitor, fn(_down) { Error(Nil) })
        |> process.selector_receive(within: timeout)

      process.demonitor_process(monitor)

      case result {
        Ok(Ok(reply)) -> Ok(reply)
        Ok(Error(Nil)) -> Error(Nil)
        Error(Nil) -> Error(Nil)
      }
    }
  }
}

/// Atomically sweep full buckets from the registry within the actor.
///
fn do_sweep(state: State(id)) -> State(id) {
  let #(to_remove, to_keep) =
    state.registry
    |> dict.to_list
    |> list.partition(fn(pair) {
      let #(_, rl) = pair
      case safe_call(rl, rate_limiter.HasFullBucket, call_timeout) {
        Ok(is_full) -> is_full
        // Remove unresponsive or dead rate limiters
        Error(_) -> True
      }
    })

  list.each(to_remove, fn(pair) {
    let #(_, rl) = pair
    rate_limiter.shutdown(rl)
  })

  State(..state, registry: dict.from_list(to_keep))
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
      let registry = state.registry |> dict.delete(identifier)
      let state = State(..state, registry: registry)
      actor.send(client, Nil)
      actor.continue(state)
    }

    Sweep -> {
      let state = do_sweep(state)
      schedule_sweep(state)
      actor.continue(state)
    }

    SweepSync(client) -> {
      let state = do_sweep(state)
      actor.send(client, Nil)
      actor.continue(state)
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
  actor.call(registry, waiting: call_timeout, sending: GetOrCreate(
    identifier,
    _,
  ))
}

/// Return a list of rate limiters.
///
pub fn get_all(
  registry: RateLimiterRegistryActor(id),
) -> List(#(id, Subject(rate_limiter.Message))) {
  actor.call(registry, waiting: call_timeout, sending: GetAll)
}

/// Remove a rate limiter from the registry.
///
pub fn remove(
  registry: RateLimiterRegistryActor(id),
  identifier: id,
) -> Result(Nil, Nil) {
  actor.call(registry, waiting: call_timeout, sending: Remove(identifier, _))
  Ok(Nil)
}

/// Remove full buckets from the registry.
///
pub fn sweep(
  registry: RateLimiterRegistryActor(id),
  _interval_secs: Option(Int),
) {
  actor.call(registry, waiting: call_timeout, sending: SweepSync)
}
