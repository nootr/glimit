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
    per_second: Option(fn(id) -> Int),
    burst_limit: Option(fn(id) -> Int),
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

/// Set the rate of new available tokens per second.
///
/// Note that this is not the maximum number of requests that can be made in a single
/// second, but the rate at which tokens are added to the bucket. Think of this as the
/// steady state rate limit, while the `burst_limit` function sets the maximum number of
/// available tokens (or the burst rate limit).
///
/// This value is also used as the default value for the `burst_limit` function.
///
/// # Example
///
/// ```gleam
/// import glimit
///
/// let limiter =
///   glimit.new()
///   |> glimit.per_second(10)
/// ```
///
pub fn per_second(
  limiter: RateLimiterBuilder(a, b, id),
  limit: Int,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, per_second: Some(fn(_) { limit }))
}

/// Set the rate limit per second, based on the identifier.
///
/// # Example
///
/// ```gleam
/// import glimit
///
/// let limiter =
///   glimit.new()
///   |> glimit.identifier(fn(request) { request.user_id })
///   |> glimit.per_second_fn(fn(user_id) {
///     db.get_rate_limit(user_id)
///   })
/// ```
///
pub fn per_second_fn(
  limiter: RateLimiterBuilder(a, b, id),
  limit_fn: fn(id) -> Int,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, per_second: Some(limit_fn))
}

/// Set the maximum number of available tokens.
///
/// The maximum number of available tokens is the maximum number of requests that can be
/// made in a single second. The default value is the same as the rate limit per second.
///
/// # Example
///
/// ```gleam
/// import glimit
///
/// let limiter =
///   glimit.new()
///   |> glimit.per_second(10)
///   |> glimit.burst_limit(100)
/// ```
///
pub fn burst_limit(
  limiter: RateLimiterBuilder(a, b, id),
  burst_limit: Int,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, burst_limit: Some(fn(_) { burst_limit }))
}

/// Set the maximum number of available tokens, based on the identifier.
///
/// # Example
///
/// ```gleam
/// import glimit
///
/// let limiter =
///   glimit.new()
///   |> glimit.identifier(fn(request) { request.user_id })
///   |> glimit.per_second(10)
///   |> glimit.burst_limit_fn(fn(user_id) {
///     db.get_burst_limit(user_id)
///   })
/// ```
///
pub fn burst_limit_fn(
  limiter: RateLimiterBuilder(a, b, id),
  burst_limit_fn: fn(id) -> Int,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, burst_limit: Some(burst_limit_fn))
}

/// Set the handler to be called when the rate limit is reached.
///
/// # Example
///
/// ```gleam
/// import glimit
///
/// let limiter =
///   glimit.new()
///   |> glimit.per_second(10)
///   |> glimit.on_limit_exceeded(fn(_request) { "Rate limit reached" })
/// ```
///
pub fn on_limit_exceeded(
  limiter: RateLimiterBuilder(a, b, id),
  on_limit_exceeded: fn(a) -> b,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, on_limit_exceeded: Some(on_limit_exceeded))
}

/// Set the identifier function to be used to identify the rate limit.
///
/// # Example
///
/// ```gleam
/// import glimit
///
/// let limiter =
///   glimit.new()
///   |> glimit.identifier(fn(request) { request.ip })
/// ```
///
pub fn identifier(
  limiter: RateLimiterBuilder(a, b, id),
  identifier: fn(a) -> id,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, identifier: Some(identifier))
}

/// Build the rate limiter.
///
/// Note that using `apply` will already build the rate limiter, so this function is
/// only useful if you want to build the rate limiter manually and apply it to multiple
/// functions.
///
/// To apply the resulting rate limiter to a function or handler, use the `apply_built`
/// function.
///
pub fn build(
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
/// Panics if the rate limiter registry cannot be started or if the `identifier`
/// function or `on_limit_exceeded` function is missing.
///
pub fn apply(
  func: fn(a) -> b,
  config: RateLimiterBuilder(a, b, id),
) -> fn(a) -> b {
  let limiter = case build(config) {
    Ok(limiter) -> limiter
    Error(message) -> panic as message
  }
  apply_built(func, limiter)
}

/// Apply the rate limiter to a request handler or function.
///
/// This function is useful if you want to build the rate limiter manually using the
/// `build` function.
///
pub fn apply_built(
  func: fn(a) -> b,
  limiter: RateLimiter(a, b, id),
) -> fn(a) -> b {
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
