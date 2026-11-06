//// This module provides a rate limiter that can be used to limit the number of
//// requests or function calls per second, minute or hour for a given
//// identifier.
////
//// By default, rate limit state is stored in an ETS table with lock-free
//// atomic operations. A periodic sweep removes buckets that have refilled to
//// full to reduce memory usage.
////
//// For distributed rate limiting, you can provide a custom `Store` that
//// persists bucket state externally (Redis, Postgres, etc.).
////
//// The rate limiter fails open — if the store is unavailable, requests are
//// allowed through.
////
//// The rate limits are configured using the following two options:
////
//// - `per_second`, `per_minute` or `per_hour`: The rate of new available
////   tokens per second, minute or hour. Think of this as the steady state rate
////   limit. Rates of different periods can be combined; a request must then
////   pass all of them.
//// - `burst_limit`: The maximum number of available tokens. Think of this as
////   the burst rate limit. The default value is the number of tokens per
////   second, minute or hour set by the rate limit.
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
//// # Combining rates
////
//// Rates of different periods apply together, in any order. Setting a rate for
//// a period that already has one replaces it. Each period has its own bucket,
//// and a request only spends tokens if every bucket has one available.
////
//// ```gleam
//// let limiter =
////   glimit.new()
////   |> glimit.per_second(10)
////   |> glimit.per_hour(1000)
////   |> glimit.identifier(fn(request) { request.ip })
////   |> glimit.on_limit_exceeded(fn(_request) { "Rate limit reached" })
//// ```
////
//// `burst_limit` is always the maximum number of requests in a single burst: it
//// sets the bucket size of the shortest period. Buckets of longer periods hold
//// at least their own rate, so a small burst limit does not shrink them.
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
//// By default, rate limit state is stored in-memory using ETS. For
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

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import glimit/bucket
import glimit/ets_store.{type EtsStore}
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

/// A number of tokens generated per refill period.
///
pub type Rate(id) {
  Rate(token_rate: fn(id) -> Int, refill_period_ms: Int)
}

/// A rate limiter.
///
pub type RateLimiter(a, b, id) {
  RateLimiter(
    on_limit_exceeded: fn(a) -> b,
    identifier: fn(a) -> id,
    /// The rates to enforce, shortest period first.
    ///
    rates: List(Rate(id)),
    burst_limit: Option(fn(id) -> Int),
    store: Store,
    ets_store: Option(EtsStore),
    now: fn() -> Int,
  )
}

type BucketConfig {
  BucketConfig(
    key: String,
    max_token_count: Int,
    token_rate: Int,
    refill_period_ms: Int,
  )
}

/// A builder for configuring the rate limiter.
///
pub type RateLimiterBuilder(a, b, id) {
  RateLimiterBuilder(
    rates: List(Rate(id)),
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
    rates: [],
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
/// Setting `per_second` again replaces the earlier per-second rate. A `per_minute`
/// or `per_hour` rate is kept, and a request must pass all of them.
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
  per_second_fn(limiter, fn(_) { limit })
}

/// Set the rate limit per second, based on the identifier.
///
/// This replaces an earlier per-second rate. A `per_minute` or `per_hour` rate is
/// kept, and a request must pass all of them.
///
/// Note: this function is evaluated once when a bucket is first created for an
/// identifier. If the function returns a different value later, existing buckets
/// are not affected until they are swept (once they have refilled to full) and
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
  rate_fn(limiter, limit_fn, 1000)
}

/// Set the rate of new available tokens per minute.
///
/// Tokens are added continuously: `per_minute(30)` adds one token every two
/// seconds. This value is also used as the default value for the
/// `burst_limit` function. Setting `per_minute` again replaces the earlier
/// per-minute rate. A `per_second` or `per_hour` rate is kept, and a request
/// must pass all of them.
///
/// # Example
///
/// ```gleam
/// import glimit
///
/// let limiter =
///   glimit.new()
///   |> glimit.per_minute(30)
/// ```
///
pub fn per_minute(
  limiter: RateLimiterBuilder(a, b, id),
  limit: Int,
) -> RateLimiterBuilder(a, b, id) {
  per_minute_fn(limiter, fn(_) { limit })
}

/// Set the rate limit per minute, based on the identifier.
///
/// This replaces an earlier per-minute rate. A `per_second` or `per_hour` rate is
/// kept, and a request must pass all of them.
///
/// Note: this function is evaluated once when a bucket is first created for an
/// identifier. If the function returns a different value later, existing buckets
/// are not affected until they are swept (once they have refilled to full) and
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
///   |> glimit.per_minute_fn(fn(user_id) {
///     db.get_rate_limit(user_id)
///   })
/// ```
///
pub fn per_minute_fn(
  limiter: RateLimiterBuilder(a, b, id),
  limit_fn: fn(id) -> Int,
) -> RateLimiterBuilder(a, b, id) {
  rate_fn(limiter, limit_fn, 60_000)
}

/// Set the rate of new available tokens per hour.
///
/// Tokens are added continuously: `per_hour(20)` adds one token every three
/// minutes. This value is also used as the default value for the
/// `burst_limit` function. Setting `per_hour` again replaces the earlier
/// per-hour rate. A `per_second` or `per_minute` rate is kept, and a request
/// must pass all of them.
///
/// # Example
///
/// ```gleam
/// import glimit
///
/// let limiter =
///   glimit.new()
///   |> glimit.per_hour(20)
/// ```
///
pub fn per_hour(
  limiter: RateLimiterBuilder(a, b, id),
  limit: Int,
) -> RateLimiterBuilder(a, b, id) {
  per_hour_fn(limiter, fn(_) { limit })
}

/// Set the rate limit per hour, based on the identifier.
///
/// This replaces an earlier per-hour rate. A `per_second` or `per_minute` rate is
/// kept, and a request must pass all of them.
///
/// Note: this function is evaluated once when a bucket is first created for an
/// identifier. If the function returns a different value later, existing buckets
/// are not affected until they are swept (once they have refilled to full) and
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
///   |> glimit.per_hour_fn(fn(user_id) {
///     db.get_hourly_rate_limit(user_id)
///   })
/// ```
///
pub fn per_hour_fn(
  limiter: RateLimiterBuilder(a, b, id),
  limit_fn: fn(id) -> Int,
) -> RateLimiterBuilder(a, b, id) {
  rate_fn(limiter, limit_fn, 3_600_000)
}

fn rate_fn(
  limiter: RateLimiterBuilder(a, b, id),
  limit_fn: fn(id) -> Int,
  refill_period_ms: Int,
) -> RateLimiterBuilder(a, b, id) {
  let rate = Rate(token_rate: limit_fn, refill_period_ms: refill_period_ms)
  let rates =
    [
      rate,
      ..list.filter(limiter.rates, fn(existing) {
        existing.refill_period_ms != refill_period_ms
      })
    ]
    |> list.sort(by: fn(a, b) {
      int.compare(a.refill_period_ms, b.refill_period_ms)
    })
  RateLimiterBuilder(..limiter, rates: rates)
}

/// Set the maximum number of available tokens.
///
/// The maximum number of available tokens is the maximum number of requests that can be
/// made in a single burst when the bucket is full. The default value is the same as the
/// rate limit per second, minute or hour.
///
/// With multiple rates, this sets the bucket size of the shortest period, so it is
/// still the maximum number of requests in a single burst. Buckets of longer periods
/// hold at least their own rate, so a small burst limit does not shrink them. Without
/// a burst limit, each bucket holds its own rate.
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
/// are not affected until they are swept (once they have refilled to full) and
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

/// This setting has no effect.
///
/// It used to remove buckets that had not been hit for this many seconds.
/// Removing a bucket before it has refilled gives the client a full burst
/// back, so buckets are now kept until they have refilled and are then
/// removed by the periodic sweep.
///
@deprecated("Buckets are kept until they have refilled; this setting has no effect")
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
/// store on each hit instead of using the default ETS backend.
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

/// The shortest period keeps the plain key, so adding a longer rate to an
/// existing limiter keeps its buckets.
///
fn bucket_key(identifier: id, rate_index: Int, rate: Rate(id)) -> String {
  case rate_index {
    0 -> string_key(identifier)
    _ -> string_key(identifier) <> ":" <> int.to_string(rate.refill_period_ms)
  }
}

fn max_token_count(burst: Option(Int), token_rate: Int, index: Int) -> Int {
  case burst, index {
    None, _ -> token_rate
    Some(burst), 0 -> burst
    Some(burst), _ -> int.max(burst, token_rate)
  }
}

fn bucket_configs(
  limiter: RateLimiter(a, b, id),
  identifier: id,
) -> Result(List(BucketConfig), Nil) {
  use burst <- result.try(case limiter.burst_limit {
    Some(burst_limit) ->
      utils.rescue(fn() { burst_limit(identifier) })
      |> result.map(Some)
    None -> Ok(None)
  })
  limiter.rates
  |> list.index_map(fn(rate, index) {
    use token_rate <- result.map(
      utils.rescue(fn() { rate.token_rate(identifier) }),
    )
    BucketConfig(
      key: bucket_key(identifier, index, rate),
      max_token_count: max_token_count(burst, token_rate, index),
      token_rate: token_rate,
      refill_period_ms: rate.refill_period_ms,
    )
  })
  |> result.all
}

fn lock_bucket(
  store: Store,
  config: BucketConfig,
) -> Result(bucket.BucketState, HitError) {
  use maybe_bucket <- result.try(
    store.lock_and_get(config.key) |> result.replace_error(StoreLockFailed),
  )
  case maybe_bucket {
    Some(state) -> Ok(state)
    None ->
      case
        bucket.new_with_period(
          config.max_token_count,
          config.token_rate,
          config.refill_period_ms,
        )
      {
        Ok(state) -> Ok(state)
        Error(_) -> {
          let _ = store.unlock(config.key)
          Error(Unavailable)
        }
      }
  }
}

/// Lock every bucket, in the order given. If a bucket cannot be locked, the
/// buckets locked so far are released.
///
fn lock_buckets(
  store: Store,
  configs: List(BucketConfig),
  locked: List(#(String, bucket.BucketState)),
) -> Result(List(#(String, bucket.BucketState)), HitError) {
  case configs {
    [] -> Ok(locked)
    [config, ..rest] ->
      case lock_bucket(store, config) {
        Ok(state) -> lock_buckets(store, rest, [#(config.key, state), ..locked])
        Error(error) -> {
          list.each(locked, fn(entry) { store.unlock(entry.0) })
          Error(error)
        }
      }
  }
}

fn store_hit(
  store: Store,
  now: fn() -> Int,
  configs: List(BucketConfig),
) -> Result(Nil, HitError) {
  use locked <- result.try(lock_buckets(store, configs, []))
  let #(keys, states) = list.unzip(locked)
  let #(hit_result, new_states) = bucket.hit_all(states, now())
  list.map2(keys, new_states, fn(key, state) {
    store.set_and_unlock(key, state, bucket.compute_ttl(state))
  })
  case hit_result {
    Ok(Nil) -> Ok(Nil)
    Error(Nil) -> Error(RateLimited)
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
  use rates <- result.try(case config.rates {
    [] ->
      Error(
        "a rate limit (`per_second`, `per_minute` or `per_hour`) is required",
      )
    rates -> Ok(rates)
  })
  use identifier <- result.try(case config.identifier {
    Some(identifier) -> Ok(identifier)
    None -> Error("`identifier` function is required")
  })
  use on_limit_exceeded <- result.try(case config.on_limit_exceeded {
    Some(on_limit_exceeded) -> Ok(on_limit_exceeded)
    None -> Error("`on_limit_exceeded` function is required")
  })

  let #(store, es) = case config.store {
    Some(ext_store) -> #(ext_store, None)
    None -> {
      let es =
        ets_store.new_with_sweep(
          max_idle_ms: config.max_idle_ms,
          sweep_interval_ms: 10_000,
        )
      #(ets_store.make_store(es), Some(es))
    }
  }

  Ok(RateLimiter(
    on_limit_exceeded: on_limit_exceeded,
    identifier: identifier,
    rates: rates,
    burst_limit: config.burst_limit,
    store: store,
    ets_store: es,
    now: utils.now,
  ))
}

/// Hit the rate limiter for the given identifier directly.
///
pub fn hit(
  limiter: RateLimiter(a, b, id),
  identifier: id,
) -> Result(Nil, HitError) {
  case bucket_configs(limiter, identifier) {
    Error(_) -> Error(Unavailable)
    Ok(configs) -> store_hit(limiter.store, limiter.now, configs)
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

/// Return the number of tracked buckets in the ETS store.
///
/// An identifier has one bucket per rate, until a bucket is swept. Returns 0 if the rate limiter uses an external store.
///
pub fn get_count(limiter: RateLimiter(a, b, id)) -> Int {
  case limiter.ets_store {
    Some(es) -> ets_store.get_count(es)
    None -> 0
  }
}

/// Remove an identifier from the ETS store.
///
/// No-op if the rate limiter uses an external store.
///
pub fn remove(limiter: RateLimiter(a, b, id), identifier: id) -> Nil {
  case limiter.ets_store {
    Some(es) ->
      limiter.rates
      |> list.index_map(fn(rate, index) { bucket_key(identifier, index, rate) })
      |> list.each(ets_store.remove(es, _))
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
