//// This module contains pure token-bucket functions used by the rate limiter actor.
////

import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}

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

/// Returns True if the bucket is full after refilling.
///
pub fn is_full(state: BucketState, now: Int) -> Bool {
  let state = refill(state, now)
  state.token_count >=. int.to_float(state.max_token_count)
}
