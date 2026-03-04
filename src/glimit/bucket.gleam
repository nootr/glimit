//// This module contains pure token-bucket functions used by the rate limiter actor.
////

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

const key_token_count = "tc"

const key_last_update = "lu"

const key_max_tokens = "mt"

const key_token_rate = "tr"

/// A pluggable storage backend for distributed rate limiting.
///
/// All token bucket logic is handled by glimit — store adapters only need to
/// implement simple get/set/lock/unlock operations on string-keyed bucket state.
///
/// - `get`: Retrieve bucket state by key. Return `Ok(None)` for a new/missing key.
/// - `set`: Persist bucket state with a TTL in seconds for automatic expiry.
/// - `lock`: Acquire an exclusive lock for the key. Return `Error(Nil)` if unavailable.
/// - `unlock`: Release the lock for the key.
///
/// When a lock or get fails, the rate limiter **fails open** (allows the request).
///
pub type Store {
  Store(
    get: fn(String) -> Result(Option(BucketState), Nil),
    set: fn(String, BucketState, Int) -> Result(Nil, Nil),
    lock: fn(String) -> Result(Nil, Nil),
    unlock: fn(String) -> Result(Nil, Nil),
  )
}

/// The state of a single token bucket.
///
pub type BucketState {
  BucketState(
    /// The maximum number of tokens.
    ///
    max_token_count: Int,
    /// The rate of token generation per second.
    ///
    token_rate: Int,
    /// The number of tokens available.
    ///
    token_count: Float,
    /// Monotonic timestamp (milliseconds) of the last time the bucket was updated.
    ///
    last_update: Option(Int),
  )
}

/// Create a new bucket state.
///
/// Returns Error(Nil) if max_token_count or token_rate are not positive.
///
pub fn new(max_token_count: Int, token_rate: Int) -> Result(BucketState, Nil) {
  case max_token_count > 0 && token_rate > 0 {
    False -> Error(Nil)
    True ->
      Ok(BucketState(
        max_token_count: max_token_count,
        token_rate: token_rate,
        token_count: int.to_float(max_token_count),
        last_update: None,
      ))
  }
}

/// Refill the bucket based on elapsed time.
///
pub fn refill(state: BucketState, now: Int) -> BucketState {
  let time_diff = case state.last_update {
    None -> 0
    Some(last_update) -> int.max(0, now - last_update)
  }
  let tokens_to_add = int.to_float(state.token_rate * time_diff) /. 1000.0
  let token_count =
    { state.token_count +. tokens_to_add }
    |> float.min(int.to_float(state.max_token_count))
    |> float.max(0.0)
  let last_update = case time_diff > 0 {
    True -> Some(now)
    False ->
      case state.last_update {
        None -> Some(now)
        Some(_) -> state.last_update
      }
  }

  BucketState(..state, token_count: token_count, last_update: last_update)
}

/// Hit the bucket: refill, then try to consume one token.
///
/// Returns `#(Ok(Nil), new_state)` on success,
/// `#(Error(Nil), new_state)` when rate-limited.
///
pub fn hit(state: BucketState, now: Int) -> #(Result(Nil, Nil), BucketState) {
  let state = refill(state, now)
  case state.token_count >=. 1.0 {
    True -> #(
      Ok(Nil),
      BucketState(..state, token_count: state.token_count -. 1.0),
    )
    False -> #(Error(Nil), state)
  }
}

/// Convert a BucketState to a list of string key-value pairs.
///
/// Useful for serializing bucket state into external stores (e.g. Redis HSET).
/// Keys: `"tc"` (token count), `"lu"` (last update), `"mt"` (max tokens), `"tr"` (token rate).
///
pub fn to_pairs(state: BucketState) -> List(#(String, String)) {
  let lu = case state.last_update {
    Some(v) -> int.to_string(v)
    None -> ""
  }
  [
    #(key_token_count, float.to_string(state.token_count)),
    #(key_last_update, lu),
    #(key_max_tokens, int.to_string(state.max_token_count)),
    #(key_token_rate, int.to_string(state.token_rate)),
  ]
}

/// Parse a BucketState from a list of string key-value pairs.
///
/// This is the inverse of `to_pairs`. Returns `Error(Nil)` if any required
/// field is missing or cannot be parsed.
///
pub fn from_pairs(pairs: List(#(String, String))) -> Result(BucketState, Nil) {
  use tc_str <- result.try(list.key_find(pairs, key_token_count))
  use lu_str <- result.try(list.key_find(pairs, key_last_update))
  use mt_str <- result.try(list.key_find(pairs, key_max_tokens))
  use tr_str <- result.try(list.key_find(pairs, key_token_rate))
  use tc <- result.try(float.parse(tc_str))
  use mt <- result.try(int.parse(mt_str))
  use tr <- result.try(int.parse(tr_str))
  let lu = case lu_str {
    "" -> None
    s ->
      case int.parse(s) {
        Ok(v) -> Some(v)
        Error(_) -> None
      }
  }
  Ok(BucketState(
    token_count: tc,
    last_update: lu,
    max_token_count: mt,
    token_rate: tr,
  ))
}

/// Returns True if the bucket is full after refilling.
///
pub fn is_full(state: BucketState, now: Int) -> Bool {
  let state = refill(state, now)
  state.token_count >=. int.to_float(state.max_token_count)
}
