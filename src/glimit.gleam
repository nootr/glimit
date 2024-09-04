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

import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/result
import glimit/actor

/// A rate limiter.
///
pub type RateLimiter(a, b, id) {
  RateLimiter(
    subject: Subject(actor.Message(id)),
    handler: fn(a) -> b,
    identifier: fn(a) -> id,
  )
}

/// A builder for configuring the rate limiter.
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
  case try_build(config) {
    Ok(limiter) -> limiter
    Error(message) -> panic as message
  }
}

/// Build the rate limiter, but return an error instead of panicking.
///
pub fn try_build(
  config: RateLimiterBuilder(a, b, id),
) -> Result(RateLimiter(a, b, id), String) {
  use subject <- result.try(
    actor.new(config.per_second, config.per_minute, config.per_hour)
    |> result.map_error(fn(_) { "Failed to start rate limiter actor" }),
  )
  use identifier <- result.try(case config.identifier {
    Some(identifier) -> Ok(identifier)
    None -> Error("Identifier function is required")
  })
  use handler <- result.try(case config.handler {
    Some(handler) -> Ok(handler)
    None -> Error("Handler function is required")
  })

  Ok(RateLimiter(subject: subject, handler: handler, identifier: identifier))
}

/// Apply the rate limiter to a request handler or function.
///
pub fn apply(func: fn(a) -> b, limiter: RateLimiter(a, b, id)) -> fn(a) -> b {
  fn(input: a) -> b {
    let identifier = limiter.identifier(input)
    case actor.hit(limiter.subject, identifier) {
      Ok(Nil) -> func(input)
      Error(Nil) -> limiter.handler(input)
    }
  }
}

/// Apply the rate limiter to a request handler or function with two arguments.
///
/// Note: this function folds the two arguments into a tuple before passing them to the
/// identifier or handler functions.
///
pub fn apply2(
  func: fn(a, b) -> c,
  limiter: RateLimiter(#(a, b), c, id),
) -> fn(a, b) -> c {
  fn(a: a, b: b) -> c {
    let identifier = limiter.identifier(#(a, b))
    case actor.hit(limiter.subject, identifier) {
      Ok(Nil) -> func(a, b)
      Error(Nil) -> limiter.handler(#(a, b))
    }
  }
}

/// Apply the rate limiter to a request handler or function with three arguments.
///
/// Note: this function folds the three arguments into a tuple before passing them to the
/// identifier or handler functions.
///
pub fn apply3(
  func: fn(a, b, c) -> d,
  limiter: RateLimiter(#(a, b, c), d, id),
) -> fn(a, b, c) -> d {
  fn(a: a, b: b, c: c) -> d {
    let identifier = limiter.identifier(#(a, b, c))
    case actor.hit(limiter.subject, identifier) {
      Ok(Nil) -> func(a, b, c)
      Error(Nil) -> limiter.handler(#(a, b, c))
    }
  }
}

/// Apply the rate limiter to a request handler or function with four arguments.
///
/// Note: this function folds the four arguments into a tuple before passing them to the
/// identifier or handler functions.
///
pub fn apply4(
  func: fn(a, b, c, d) -> e,
  limiter: RateLimiter(#(a, b, c, d), e, id),
) -> fn(a, b, c, d) -> e {
  fn(a: a, b: b, c: c, d: d) -> e {
    let identifier = limiter.identifier(#(a, b, c, d))
    case actor.hit(limiter.subject, identifier) {
      Ok(Nil) -> func(a, b, c, d)
      Error(Nil) -> limiter.handler(#(a, b, c, d))
    }
  }
}
