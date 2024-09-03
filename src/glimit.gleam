//// A framework-agnostic rate limiter for Gleam. 💫
////
//// This module provides a rate limiter that can be used to limit the number of
//// requests that can be made to a given function or handler within a given
//// time frame.
////
//// The rate limiter is implemented as an actor that keeps track of the number
//// of hits for a given identifier within the last second, minute, and hour.
//// When a hit is received, the actor checks the rate limits and either allows
//// the hit to pass or rejects it.
////
//// The rate limiter can be configured with rate limits per second, minute, and
//// hour, and a handler function that is called when the rate limit is reached.
//// The rate limiter can be applied to a function or handler using the `apply`
//// function, which returns a new function that checks the rate limit before
//// calling the original function.
////
//// # Example
////
//// ```gleam
//// import glimit
////
//// let limiter =
////   glimit.new()
////   |> glimit.per_second(10)
////   |> glimit.per_minute(100)
////   |> glimit.per_hour(1000)
////   |> glimit.identifier(fn(request) { request.ip })
////   |> glimit.handler(fn(_request) { "Rate limit reached" })
////   |> glimit.build()
////
//// let handler =
////   fn(_request) { "Hello, world!" }
////   |> glimit.apply(limiter)
//// ```
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
pub type Message(id) {
  /// Stop the actor.
  Shutdown

  /// Mark a hit for a given identifier.
  Hit(identifier: id, reply_with: Subject(Result(Nil, Nil)))
}

/// The rate limiter's public interface.
///
pub type RateLimiter(a, b, id) {
  RateLimiter(
    subject: Subject(Message(id)),
    handler: fn(a) -> b,
    identifier: fn(a) -> id,
  )
}

/// A rate limiter.
///
pub type RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(
    per_second: Option(Int),
    per_minute: Option(Int),
    per_hour: Option(Int),
    identifier: Option(fn(a) -> id),
    handler: Option(fn(a) -> b),
  )
}

/// The actor state.
///
type State(a, b, id) {
  RateLimiterState(
    hit_log: dict.Dict(id, List(Int)),
    per_second: Option(Int),
    per_minute: Option(Int),
    per_hour: Option(Int),
  )
}

fn handle_message(
  message: Message(id),
  state: State(a, b, id),
) -> actor.Next(Message(id), State(a, b, id)) {
  case message {
    Shutdown -> actor.Stop(process.Normal)
    Hit(identifier, client) -> {
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
pub fn new() -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(
    per_second: None,
    per_minute: None,
    per_hour: None,
    identifier: None,
    handler: None,
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
  RateLimiterBuilder(..limiter, handler: Some(handler))
}

/// Set the identifier function to be used to identify the rate limit.
///
pub fn identifier(
  limiter: RateLimiterBuilder(a, b, id),
  identifier: fn(a) -> id,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, identifier: Some(identifier))
}

/// Build the rate limiter.
///
/// Panics if the rate limiter actor cannot be started or if the identifier
/// function or handler function is missing.
///
pub fn build(config: RateLimiterBuilder(a, b, id)) -> RateLimiter(a, b, id) {
  let state =
    RateLimiterState(
      hit_log: dict.new(),
      per_second: config.per_second,
      per_minute: config.per_minute,
      per_hour: config.per_hour,
    )

  RateLimiter(
    subject: case actor.start(state, handle_message) {
      Ok(subject) -> subject
      Error(_) -> panic as "Failed to start rate limiter actor"
    },
    identifier: case config.identifier {
      Some(identifier) -> identifier
      None -> panic as "Identifier function is required"
    },
    handler: case config.handler {
      Some(handler) -> handler
      None -> panic as "Handler function is required"
    },
  )
}

/// Apply the rate limiter to a request handler or function.
///
pub fn apply(func: fn(a) -> b, limiter: RateLimiter(a, b, id)) -> fn(a) -> b {
  fn(input: a) -> b {
    let identifier = limiter.identifier(input)
    case actor.call(limiter.subject, Hit(identifier, _), 10) {
      Ok(Nil) -> func(input)
      Error(Nil) -> limiter.handler(input)
    }
  }
}

/// Stop the rate limiter agent.
///
pub fn stop(limiter: RateLimiter(a, b, id)) {
  actor.send(limiter.subject, Shutdown)
}
