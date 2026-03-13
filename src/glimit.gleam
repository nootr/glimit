//// This module provides a rate limiter that can be used to limit the number of
//// requests or function calls per second for a given identifier.
////
//// In-memory mode: each hit sends two messages to an OTP actor (get + set).
//// A periodic sweep removes full or idle buckets to reduce memory usage. The
//// idle threshold defaults to 60 seconds and can be configured via `max_idle`.
////
//// External store mode: each hit calls the store's lock_and_get/set_and_unlock
//// interface directly, with no actor overhead.
////
//// The rate limiter fails open — if the store is unavailable, requests are
//// allowed through.
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
//// # Multi-argument functions
////
//// `apply` wraps a single-argument function `fn(a) -> b`. To rate-limit a
//// function with multiple arguments, use `apply2`, `apply3`, or `apply4`:
////
//// ```gleam
//// let limiter =
////   glimit.new()
////   |> glimit.per_second(10)
////   |> glimit.identifier(fn(args: #(String, String)) { args.0 })
////   |> glimit.on_limit_exceeded(fn(_args) { too_many_requests() })
////
//// let limited_handle =
////   handle
////   |> glimit.apply2(limiter)
////
//// limited_handle("user_123", "upload")
//// ```
////
//// # Pluggable store backend
////
//// By default, rate limit state is stored in-memory using an OTP actor. For
//// distributed rate limiting (e.g. across multiple nodes), you can provide a
//// custom `Store` that persists bucket state externally (Redis, Postgres, etc.).
////
//// All token bucket logic stays in glimit — adapters only implement
//// `lock_and_get` / `set_and_unlock` / `unlock` operations. The `glimit/bucket`
//// module is public and provides `to_pairs`/`from_pairs` helpers for
//// serialization.
////
//// See `examples/redis/` for a complete Redis adapter using
//// [valkyrie](https://hexdocs.pm/valkyrie/).
////

import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import glimit/bucket
import glimit/ets_store
import glimit/memory_store.{type MemoryStore}
import glimit/utils

const store_key_prefix = "glimit:"

/// A pluggable storage backend for distributed rate limiting.
/// See `glimit/bucket.Store` for full documentation.
///
pub type Store =
  bucket.Store

/// Error type returned when a rate limit check fails.
///
pub type HitError {
  /// The rate limit has been exceeded.
  RateLimited
  /// The rate limiter is unavailable.
  Unavailable
  /// The store lock could not be acquired (fails open).
  StoreLockFailed
}

/// A rate limiter.
///
pub type RateLimiter(a, b, id) {
  RateLimiter(
    on_limit_exceeded: fn(a) -> b,
    identifier: fn(a) -> id,
    per_second: fn(id) -> Int,
    burst_limit: fn(id) -> Int,
    store: Store,
    memory_store: Option(MemoryStore),
    now: fn() -> Int,
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
    max_idle_ms: Option(Int),
    store: Option(Store),
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
    max_idle_ms: Some(60_000),
    store: None,
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
/// Note: this function is evaluated once when a bucket is first created for an
/// identifier. If the function returns a different value later, existing buckets
/// are not affected until they are swept (due to idleness or being full) and
/// re-created on the next hit.
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
/// made in a single burst when the bucket is full. The default value is the same as the
/// rate limit per second.
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
/// Note: this function is evaluated once when a bucket is first created for an
/// identifier. If the function returns a different value later, existing buckets
/// are not affected until they are swept (due to idleness or being full) and
/// re-created on the next hit.
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

/// Set the idle eviction threshold in seconds.
///
/// Buckets that have not been hit for longer than this duration are removed
/// during periodic sweeps. The default is 60 seconds. Set to `0` to disable
/// idle eviction entirely.
///
/// For rate limiters with a high `burst_limit` relative to `per_second`, you
/// may want to increase this value so that partially-refilled buckets are not
/// evicted prematurely. A good rule of thumb is
/// `burst_limit / per_second` seconds.
///
/// # Example
///
/// ```gleam
/// import glimit
///
/// let limiter =
///   glimit.new()
///   |> glimit.per_second(1)
///   |> glimit.burst_limit(1000)
///   |> glimit.max_idle(1000)
/// ```
///
pub fn max_idle(
  limiter: RateLimiterBuilder(a, b, id),
  seconds: Int,
) -> RateLimiterBuilder(a, b, id) {
  case seconds {
    s if s <= 0 -> RateLimiterBuilder(..limiter, max_idle_ms: None)
    s -> RateLimiterBuilder(..limiter, max_idle_ms: Some(s * 1000))
  }
}

/// Set a pluggable store backend for distributed rate limiting.
///
/// When a store is configured, bucket state is read from and written to the
/// store on each hit instead of being kept in memory.
/// External stores handle expiry via TTL.
///
/// # Example
///
/// ```gleam
/// import glimit
///
/// let limiter =
///   glimit.new()
///   |> glimit.per_second(10)
///   |> glimit.store(my_redis_store)
///   |> glimit.identifier(fn(request) { request.ip })
///   |> glimit.on_limit_exceeded(fn(_request) { "Rate limit reached" })
/// ```
///
pub fn store(
  limiter: RateLimiterBuilder(a, b, id),
  store: Store,
) -> RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(..limiter, store: Some(store))
}

/// Use an ETS-backed store instead of the default OTP actor.
///
/// ETS provides lower-latency rate limiting by using atomic table operations
/// directly, avoiding the overhead of OTP actor messages. Suitable for
/// single-node deployments.
///
/// Full and idle buckets are swept every 10 seconds. Idle eviction uses
/// the `max_idle` setting (default 60 seconds).
///
/// # Example
///
/// ```gleam
/// import glimit
///
/// let limiter =
///   glimit.new()
///   |> glimit.per_second(10)
///   |> glimit.ets_store()
///   |> glimit.identifier(fn(request) { request.ip })
///   |> glimit.on_limit_exceeded(fn(_request) { "Rate limit reached" })
/// ```
///
pub fn ets_store(
  limiter: RateLimiterBuilder(a, b, id),
) -> RateLimiterBuilder(a, b, id) {
  let es = ets_store.new_with_sweep(
    max_idle_ms: limiter.max_idle_ms,
    sweep_interval_ms: 10_000,
  )
  RateLimiterBuilder(..limiter, store: Some(ets_store.make_store(es)))
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

fn string_key(identifier: id) -> String {
  store_key_prefix <> string.inspect(identifier)
}

fn store_hit(
  store: Store,
  now: fn() -> Int,
  key: String,
  max_token_count: Int,
  token_rate: Int,
) -> Result(Nil, HitError) {
  use maybe_bucket <- result.try(
    store.lock_and_get(key) |> result.replace_error(StoreLockFailed),
  )
  let b = case maybe_bucket {
    Some(b) -> Ok(b)
    None -> bucket.new(max_token_count, token_rate)
  }
  case b {
    Error(_) -> {
      let _ = store.unlock(key)
      Error(Unavailable)
    }
    Ok(b) -> {
      let #(hit_result, new_b) = bucket.hit(b, now())
      let ttl = bucket.compute_ttl(new_b)
      let _ = store.set_and_unlock(key, new_b, ttl)
      case hit_result {
        Ok(Nil) -> Ok(Nil)
        Error(Nil) -> Error(RateLimited)
      }
    }
  }
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
  use identifier <- result.try(case config.identifier {
    Some(identifier) -> Ok(identifier)
    None -> Error("`identifier` function is required")
  })
  use on_limit_exceeded <- result.try(case config.on_limit_exceeded {
    Some(on_limit_exceeded) -> Ok(on_limit_exceeded)
    None -> Error("`on_limit_exceeded` function is required")
  })

  use #(store, ms) <- result.try(case config.store {
    Some(ext_store) -> Ok(#(ext_store, None))
    None ->
      case memory_store.new(config.max_idle_ms, 10_000) {
        Ok(handle) -> Ok(#(memory_store.make_store(handle), Some(handle)))
        Error(_) -> Error("Failed to start memory store")
      }
  })

  Ok(RateLimiter(
    on_limit_exceeded: on_limit_exceeded,
    identifier: identifier,
    per_second: per_second,
    burst_limit: burst_limit,
    store: store,
    memory_store: ms,
    now: utils.now,
  ))
}

/// Hit the rate limiter for the given identifier directly.
///
pub fn hit(
  limiter: RateLimiter(a, b, id),
  identifier: id,
) -> Result(Nil, HitError) {
  let key = string_key(identifier)
  case utils.rescue(fn() { limiter.burst_limit(identifier) }) {
    Error(_) -> Error(Unavailable)
    Ok(max) ->
      case utils.rescue(fn() { limiter.per_second(identifier) }) {
        Error(_) -> Error(Unavailable)
        Ok(rate) -> store_hit(limiter.store, limiter.now, key, max, rate)
      }
  }
}

/// Apply the rate limiter to a request handler or function.
///
/// Panics if the rate limiter cannot be started or if the `identifier`
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
    case hit(limiter, identifier) {
      Ok(Nil) -> func(input)
      Error(RateLimited) -> limiter.on_limit_exceeded(input)
      Error(Unavailable) | Error(StoreLockFailed) -> func(input)
    }
  }
}

/// Return the number of tracked identifiers in the in-memory store.
///
/// Returns 0 if the rate limiter uses an external store.
///
pub fn get_count(limiter: RateLimiter(a, b, id)) -> Int {
  case limiter.memory_store {
    Some(ms) -> memory_store.get_count(ms)
    None -> 0
  }
}

/// Remove an identifier from the in-memory store.
///
/// No-op if the rate limiter uses an external store.
///
pub fn remove(limiter: RateLimiter(a, b, id), identifier: id) -> Nil {
  case limiter.memory_store {
    Some(ms) -> {
      let key = string_key(identifier)
      let _ = memory_store.remove(ms, key)
      Nil
    }
    None -> Nil
  }
}

/// Apply the rate limiter to a 2-argument function.
///
/// The config's `identifier` and `on_limit_exceeded` receive a `#(a, b)` tuple.
///
/// # Example
///
/// ```gleam
/// let limiter =
///   glimit.new()
///   |> glimit.per_second(10)
///   |> glimit.identifier(fn(args: #(String, String)) { args.0 })
///   |> glimit.on_limit_exceeded(fn(_) { "Rate limited" })
///
/// let limited =
///   handle
///   |> glimit.apply2(limiter)
///
/// limited("user_123", "upload")
/// ```
///
pub fn apply2(
  func: fn(a, b) -> c,
  config: RateLimiterBuilder(#(a, b), c, id),
) -> fn(a, b) -> c {
  let wrapped =
    fn(args: #(a, b)) -> c { func(args.0, args.1) }
    |> apply(config)
  fn(a: a, b: b) -> c { wrapped(#(a, b)) }
}

/// Apply the rate limiter to a 3-argument function.
///
/// The config's `identifier` and `on_limit_exceeded` receive a `#(a, b, c)` tuple.
///
/// # Example
///
/// ```gleam
/// let limiter =
///   glimit.new()
///   |> glimit.per_second(10)
///   |> glimit.identifier(fn(args: #(String, String, Int)) { args.0 })
///   |> glimit.on_limit_exceeded(fn(_) { "Rate limited" })
///
/// let limited =
///   handle
///   |> glimit.apply3(limiter)
///
/// limited("user_123", "upload", 42)
/// ```
///
pub fn apply3(
  func: fn(a, b, c) -> d,
  config: RateLimiterBuilder(#(a, b, c), d, id),
) -> fn(a, b, c) -> d {
  let wrapped =
    fn(args: #(a, b, c)) -> d { func(args.0, args.1, args.2) }
    |> apply(config)
  fn(a: a, b: b, c: c) -> d { wrapped(#(a, b, c)) }
}

/// Apply the rate limiter to a 4-argument function.
///
/// The config's `identifier` and `on_limit_exceeded` receive a `#(a, b, c, d)` tuple.
///
/// # Example
///
/// ```gleam
/// let limiter =
///   glimit.new()
///   |> glimit.per_second(10)
///   |> glimit.identifier(fn(args: #(String, String, Int, Bool)) { args.0 })
///   |> glimit.on_limit_exceeded(fn(_) { "Rate limited" })
///
/// let limited =
///   handle
///   |> glimit.apply4(limiter)
///
/// limited("user_123", "upload", 42, True)
/// ```
///
pub fn apply4(
  func: fn(a, b, c, d) -> e,
  config: RateLimiterBuilder(#(a, b, c, d), e, id),
) -> fn(a, b, c, d) -> e {
  let wrapped =
    fn(args: #(a, b, c, d)) -> e { func(args.0, args.1, args.2, args.3) }
    |> apply(config)
  fn(a: a, b: b, c: c, d: d) -> e { wrapped(#(a, b, c, d)) }
}
