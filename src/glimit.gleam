//// A framework-agnostic rate limiter.
////

import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import glimit/utils

/// The messages that the actor can receive.
///
pub type Message(a) {
  /// Stop the actor.
  Shutdown

  /// Mark a hit for a given identifier.
  Hit(input: a, reply_with: Subject(Result(Nil, Nil)))
}

/// The rate limiter's public interface.
///
pub type RateLimiter(a, b) {
  RateLimiter(subject: Subject(Message(a)), handler: fn(a) -> b)
}

/// A rate limiter.
///
pub type RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(
    per_second: Option(Int),
    per_minute: Option(Int),
    per_hour: Option(Int),
    identifier: fn(a) -> id,
    handler: fn(a) -> b,
  )
}

/// The actor state of the actor.
///
/// The state is a dictionary where the key is the identifier and the value is a list of epoch timestamps.
///
pub type State(a, b, id) {
  RateLimiterState(
    hit_log: dict.Dict(id, List(Int)),
    per_second: Option(Int),
    per_minute: Option(Int),
    per_hour: Option(Int),
    identifier: fn(a) -> id,
    handler: fn(a) -> b,
  )
}

fn handle_message(
  message: Message(a),
  state: State(a, b, id),
) -> actor.Next(Message(a), State(a, b, id)) {
  case message {
    Shutdown -> actor.Stop(process.Normal)
    Hit(input, client) -> {
      let identifier = state.identifier(input)

      // Update hit log
      let timestamp = utils.now()
      let hits =
        state.hit_log
        |> dict.get(identifier)
        |> result.unwrap([])
        |> list.filter(fn(hit) { hit >= timestamp - 60 * 60 })
        |> list.append([timestamp])
      let hit_log =
        state.hit_log
        |> dict.insert(identifier, hits)
      let state = RateLimiterState(..state, hit_log: hit_log)

      // Check rate limits
      // TODO: optimize into a single loop
      let hits_last_hour = hits |> list.length()

      let hits_last_minute =
        hits
        |> list.filter(fn(hit) { hit >= timestamp - 60 })
        |> list.length()

      let hits_last_second =
        hits
        |> list.filter(fn(hit) { hit >= timestamp - 1 })
        |> list.length()

      let limit_reached = {
        case state.per_hour {
          Some(limit) -> hits_last_hour > limit
          None -> False
        }
        || case state.per_minute {
          Some(limit) -> hits_last_minute > limit
          None -> False
        }
        || case state.per_second {
          Some(limit) -> hits_last_second > limit
          None -> False
        }
      }

      case limit_reached {
        True -> process.send(client, Error(Nil))
        False -> process.send(client, Ok(Nil))
      }

      actor.continue(state)
    }
  }
}

/// Create a new rate limiter builder.
///
/// Panics when the rate limit hit counter cannot be created.
///
pub fn new() -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(
    per_second: None,
    per_minute: None,
    per_hour: None,
    identifier: fn(_) { panic as "No identifier configured" },
    handler: fn(_) { panic as "Rate limit reached" },
  )
}

/// Set the rate limit per second.
///
pub fn per_second(
  limiter: RateLimiterBuilder(a, b, id),
  limit: Int,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, per_second: Some(limit))
}

/// Set the rate limit per minute.
///
pub fn per_minute(
  limiter: RateLimiterBuilder(a, b, id),
  limit: Int,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, per_minute: Some(limit))
}

/// Set the rate limit per hour.
///
pub fn per_hour(
  limiter: RateLimiterBuilder(a, b, id),
  limit: Int,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, per_hour: Some(limit))
}

/// Set the handler to be called when the rate limit is reached.
///
pub fn handler(
  limiter: RateLimiterBuilder(a, b, id),
  handler: fn(a) -> b,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, handler: handler)
}

/// Set the identifier function to be used to identify the rate limit.
///
pub fn identifier(
  limiter: RateLimiterBuilder(a, b, id),
  identifier: fn(a) -> id,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, identifier: identifier)
}

/// Build the rate limiter.
///
pub fn build(config: RateLimiterBuilder(a, b, id)) -> RateLimiter(a, b) {
  let state =
    RateLimiterState(
      hit_log: dict.new(),
      per_second: config.per_second,
      per_minute: config.per_minute,
      per_hour: config.per_hour,
      identifier: config.identifier,
      handler: config.handler,
    )
  let subject = case actor.start(state, handle_message) {
    Ok(actor) -> actor
    Error(_) -> panic as "Failed to start rate limiter actor"
  }
  RateLimiter(subject: subject, handler: config.handler)
}

/// Apply the rate limiter to a request handler or function.
///
pub fn apply(func: fn(a) -> b, limiter: RateLimiter(a, b)) -> fn(a) -> b {
  fn(input: a) -> b {
    case actor.call(limiter.subject, Hit(input, _), 10) {
      Ok(Nil) -> func(input)
      Error(Nil) -> limiter.handler(input)
    }
  }
}

/// Stop the rate limiter agent.
///
pub fn stop(limiter: RateLimiter(a, b)) {
  actor.send(limiter.subject, Shutdown)
}
