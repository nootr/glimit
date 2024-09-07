//// This module provides a distributed rate limiter that can be used to limit the
//// number of requests or function calls per second for a given identifier.
////
//// A single actor is used to assign one rate limiter actor per identifier. The
//// rate limiter actor then uses a Token Bucket algorithm to determine if a
//// request or function call should be allowed to proceed. A separate process is
//// polling the rate limiters to remove full buckets to reduce unnecessary memory
//// usage.
////
//// The rate limits are configured using the following two options:
////
//// - `per_second`: The rate of new available tokens per second. Think of this
////   as the steady state rate limit.
//// - `burst_limit`: The maximum number of available tokens. Think of this as
////   the burst rate limit. The default value is the `per_second` rate limit.
////
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
////   |> glimit.burst_limit(100)
////   |> glimit.identifier(fn(request) { request.ip })
////   |> glimit.on_limit_exceeded(fn(_request) { "Rate limit reached" })
////   |> glimit.build()
////
//// let handler =
////   fn(_request) { "Hello, world!" }
////   |> glimit.apply(limiter)
//// ```
////

import gleam/option.{type Option, None, Some}
import gleam/result
import glimit/rate_limiter
import glimit/registry.{type RateLimiterRegistryActor}

/// A rate limiter.
///
pub type RateLimiter(a, b, id) {
  RateLimiter(
    rate_limiter_registry: RateLimiterRegistryActor(id),
    on_limit_exceeded: fn(a) -> b,
    identifier: fn(a) -> id,
  )
}

/// A builder for configuring the rate limiter.
///
pub type RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(
    per_second: Option(Int),
    burst_limit: Option(Int),
    identifier: Option(fn(a) -> id),
    on_limit_exceeded: Option(fn(a) -> b),
  )
}

/// Create a new rate limiter builder.
///
pub fn new() -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(
    per_second: None,
    burst_limit: None,
    identifier: None,
    on_limit_exceeded: None,
  )
}

/// Set the rate limit per second.
///
/// The value is not only used for the rate at which tokens are added to the bucket, but
/// also for the maximum number of available tokens. To set a different value fo the
/// maximum number of available tokens, use the `burst_limit` function.
///
pub fn per_second(
  limiter: RateLimiterBuilder(a, b, id),
  limit: Int,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, per_second: Some(limit))
}

/// Set the maximum number of available tokens.
///
/// The maximum number of available tokens is the maximum number of requests that can be
/// made in a single second. The default value is the same as the rate limit per second.
///
pub fn burst_limit(
  limiter: RateLimiterBuilder(a, b, id),
  burst_limit: Int,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, burst_limit: Some(burst_limit))
}

/// Set the handler to be called when the rate limit is reached.
///
pub fn on_limit_exceeded(
  limiter: RateLimiterBuilder(a, b, id),
  on_limit_exceeded: fn(a) -> b,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, on_limit_exceeded: Some(on_limit_exceeded))
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
/// Panics if the rate limiter registry cannot be started or if the `identifier`
/// function or `on_limit_exceeded` function is missing.
///
/// To handle errors instead of panicking, use `try_build`.
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
  use per_second <- result.try(case config.per_second {
    Some(per_second) -> Ok(per_second)
    None -> Error("`per_second` rate limit is required")
  })
  let burst_limit = case config.burst_limit {
    Some(burst_limit) -> burst_limit
    None -> per_second
  }
  use rate_limiter_registry <- result.try(
    registry.new(per_second, burst_limit)
    |> result.map_error(fn(_) { "Failed to start rate limiter registry" }),
  )
  use identifier <- result.try(case config.identifier {
    Some(identifier) -> Ok(identifier)
    None -> Error("`identifier` function is required")
  })
  use on_limit_exceeded <- result.try(case config.on_limit_exceeded {
    Some(on_limit_exceeded) -> Ok(on_limit_exceeded)
    None -> Error("`on_limit_exceeded` function is required")
  })

  Ok(RateLimiter(
    rate_limiter_registry: rate_limiter_registry,
    on_limit_exceeded: on_limit_exceeded,
    identifier: identifier,
  ))
}

/// Apply the rate limiter to a request handler or function.
///
pub fn apply(func: fn(a) -> b, limiter: RateLimiter(a, b, id)) -> fn(a) -> b {
  fn(input: a) -> b {
    let identifier = limiter.identifier(input)
    case limiter.rate_limiter_registry |> registry.get_or_create(identifier) {
      Ok(rate_limiter) -> {
        case rate_limiter |> rate_limiter.hit {
          Ok(Nil) -> func(input)
          Error(Nil) -> limiter.on_limit_exceeded(input)
        }
      }
      Error(_) -> panic as "Failed to get rate limiter"
    }
  }
}
