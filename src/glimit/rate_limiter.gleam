//// This module contains the implementation of a single rate limiter actor.
////

import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import glimit/utils

const call_timeout = 1000

type State {
  State(
    /// The maximum number of tokens.
    ///
    max_token_count: Int,
    /// The rate of token generation per second.
    ///
    token_rate: Int,
    /// The number of tokens available.
    ///
    token_count: Float,
    /// Epoch timestamp (milliseconds) of the last time the rate limiter was updated.
    ///
    last_update: Option(Int),
    /// Timestamp (milliseconds) that overrides the current time for testing purposes.
    ///
    now: Option(Int),
  )
}

/// Updates the state to reflect the passage of time.
///
fn refill_bucket(state: State) -> State {
  let now = case state.now {
    None -> utils.now()
    Some(now) -> now
  }
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

  State(..state, token_count: token_count, last_update: last_update)
}

/// Updates the state to remove a token.
///
fn remove_token(state: State) -> State {
  State(..state, token_count: state.token_count -. 1.0)
}

/// The message type for the rate limiter actor.
///
pub type Message {
  /// Stop the actor.
  ///
  Shutdown

  /// Mark a hit.
  ///
  /// The actor will reply with the result of the hit.
  ///
  Hit(reply_with: Subject(Result(Nil, Nil)))

  /// Returns True if the token bucket is full.
  ///
  HasFullBucket(reply_with: Subject(Bool))

  /// Set the current time for testing purposes.
  ///
  SetNow(now: Int)
}

/// Error type returned by `hit`.
///
pub type HitError {
  /// The rate limit has been exceeded.
  RateLimited
  /// The rate limiter actor is unavailable (e.g. it has stopped).
  Unavailable
}

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Shutdown -> actor.stop()

    Hit(client) -> {
      let state = refill_bucket(state)
      let #(result, state) = case state.token_count >=. 1.0 {
        False -> #(Error(Nil), state)
        True -> #(Ok(Nil), remove_token(state))
      }

      actor.send(client, result)
      actor.continue(state)
    }

    HasFullBucket(client) -> {
      let state = refill_bucket(state)
      let result = state.token_count >=. int.to_float(state.max_token_count)

      actor.send(client, result)
      actor.continue(state)
    }

    SetNow(now) -> actor.continue(State(..state, now: Some(now)))
  }
}

/// Create a new rate limiter actor.
///
/// Returns Error(Nil) if max_token_count or token_rate are not positive.
///
pub fn new(
  max_token_count: Int,
  token_rate: Int,
) -> Result(Subject(Message), Nil) {
  case max_token_count > 0 && token_rate > 0 {
    False -> Error(Nil)
    True -> {
      let state =
        State(
          max_token_count: max_token_count,
          token_rate: token_rate,
          token_count: int.to_float(max_token_count),
          last_update: None,
          now: None,
        )
      actor.new(state)
      |> actor.on_message(handle_message)
      |> actor.start
      |> result.map(fn(started) { started.data })
      |> result.map_error(fn(_) { Nil })
    }
  }
}

/// Stop the rate limiter actor.
///
pub fn shutdown(rate_limiter: Subject(Message)) -> Nil {
  actor.send(rate_limiter, Shutdown)
}

/// Mark a hit on the rate limiter actor.
///
pub fn hit(rate_limiter: Subject(Message)) -> Result(Nil, HitError) {
  case utils.safe_call(rate_limiter, Hit, call_timeout) {
    Ok(Ok(Nil)) -> Ok(Nil)
    Ok(Error(Nil)) -> Error(RateLimited)
    Error(Nil) -> Error(Unavailable)
  }
}

/// Returns True if the token bucket is full.
///
pub fn has_full_bucket(rate_limiter: Subject(Message)) -> Bool {
  utils.safe_call(rate_limiter, HasFullBucket, call_timeout)
  |> result.unwrap(False)
}

/// Set the current time for testing purposes.
/// The `now` value must be in epoch milliseconds.
///
pub fn set_now(rate_limiter: Subject(Message), now: Int) -> Nil {
  actor.send(rate_limiter, SetNow(now))
}
