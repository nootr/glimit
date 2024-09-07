//// This module contains a registry which maps hit identifiers to rate limiter actors.
////

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/otp/task
import gleam/result
import glimit/rate_limiter

pub type RateLimiterRegistryActor(id) =
  Subject(Message(id))

/// The rate limiter registry state.
///
type State(id) {
  State(
    /// The maximum number of tokens.
    ///
    max_token_count: Int,
    /// The rate of token generation per second.
    ///
    token_rate: Int,
    /// The registry of rate limiters.
    ///
    registry: Dict(id, Subject(rate_limiter.Message)),
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
}

fn handle_get_or_create(
  identifier,
  state: State(id),
) -> Result(Subject(rate_limiter.Message), Nil) {
  case state.registry |> dict.get(identifier) {
    Ok(rate_limiter) -> {
      Ok(rate_limiter)
    }
    Error(_) -> {
      use rate_limiter <- result.try(rate_limiter.new(
        state.max_token_count,
        state.token_rate,
      ))
      Ok(rate_limiter)
    }
  }
}

fn handle_message(
  message: Message(id),
  state: State(id),
) -> actor.Next(Message(id), State(id)) {
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
  }
}

/// Create a new rate limiter registry.
///
pub fn new(
  per_second: Int,
  burst_limit: Int,
) -> Result(RateLimiterRegistryActor(id), Nil) {
  let state =
    State(
      max_token_count: burst_limit,
      token_rate: per_second,
      registry: dict.new(),
    )
  use registry <- result.try(
    actor.start(state, handle_message)
    |> result.nil_error,
  )

  task.async(fn() { sweep_loop(registry, 10) })

  Ok(registry)
}

/// Get the rate limiter for the given id or create a new one if missing.
///
pub fn get_or_create(
  registry: RateLimiterRegistryActor(id),
  identifier: id,
) -> Result(Subject(rate_limiter.Message), Nil) {
  actor.call(registry, GetOrCreate(identifier, _), 10)
}

/// Return a list of rate limiters.
///
pub fn get_all(
  registry: RateLimiterRegistryActor(id),
) -> List(#(id, Subject(rate_limiter.Message))) {
  actor.call(registry, GetAll, 10)
}

/// Remove a rate limiter from the registry.
///
pub fn remove(
  registry: RateLimiterRegistryActor(id),
  identifier: id,
) -> Result(Nil, Nil) {
  actor.call(registry, Remove(identifier, _), 10)
  Ok(Nil)
}

/// Remove full buckets from the registry.
///
/// It does so in four steps:
///
/// 1. Fetch a list of all rate limiters.
/// 2. Check which rate limiters have a full bucket.
/// 3. Remove the rate limiters with a full bucket from the registry.
/// 4. Send a shutdown message to the rate limiters with a full bucket.
///
/// This function is repeated periodically.
///
fn sweep_loop(registry: RateLimiterRegistryActor(id), interval_secs: Int) {
  process.sleep(interval_secs * 1000)

  get_all(registry)
  |> list.filter(fn(pair) {
    let #(_, rate_limiter) = pair
    rate_limiter
    |> rate_limiter.has_full_bucket
  })
  |> list.map(fn(pair) {
    let #(identifier, rate_limiter) = pair
    let _ = remove(registry, identifier)
    rate_limiter |> rate_limiter.shutdown
    identifier
  })

  sweep_loop(registry, interval_secs)
}
