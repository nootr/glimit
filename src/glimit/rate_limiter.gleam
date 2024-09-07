//// This module contains the implementation of a single rate limiter actor.
////

import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import glimit/utils

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
    token_count: Int,
    /// Epoch timestamp of the last time the rate limiter was updated.
    ///
    last_update: Option(Int),
    /// Timestamp that overrides the current time for testing purposes.
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
    Some(last_update) -> now - last_update
  }
  let token_count =
    state.token_count + state.token_rate * time_diff
    |> int.min(state.max_token_count)
    |> int.max(0)

  State(..state, token_count: token_count, last_update: Some(now))
}

/// Updates the state to remove a token.
///
fn remove_token(state: State) -> State {
  State(..state, token_count: state.token_count - 1)
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

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    Shutdown -> actor.Stop(process.Normal)

    Hit(client) -> {
      let state = refill_bucket(state)
      let #(result, state) = case state.token_count {
        0 -> #(Error(Nil), state)
        _ -> #(Ok(Nil), remove_token(state))
      }

      actor.send(client, result)
      actor.continue(state)
    }

    HasFullBucket(client) -> {
      let state = refill_bucket(state)
      let result = state.token_count == state.max_token_count

      actor.send(client, result)
      actor.continue(state)
    }

    SetNow(now) -> actor.continue(State(..state, now: Some(now)))
  }
}

/// Create a new rate limiter actor.
///
pub fn new(
  max_token_count: Int,
  token_rate: Int,
) -> Result(Subject(Message), Nil) {
  let state =
    State(
      max_token_count: max_token_count,
      token_rate: token_rate,
      token_count: max_token_count,
      last_update: None,
      now: None,
    )
  actor.start(state, handle_message)
  |> result.nil_error
}

/// Stop the rate limiter actor.
///
pub fn shutdown(rate_limiter: Subject(Message)) -> Nil {
  actor.send(rate_limiter, Shutdown)
}

/// Mark a hit on the rate limiter actor.
///
pub fn hit(rate_limiter: Subject(Message)) -> Result(Nil, Nil) {
  actor.call(rate_limiter, Hit, 10)
}

/// Returns True if the token bucket is full.
///
pub fn has_full_bucket(rate_limiter: Subject(Message)) -> Bool {
  actor.call(rate_limiter, HasFullBucket, 10)
}

/// Set the current time for testing purposes.
///
pub fn set_now(rate_limiter: Subject(Message), now: Int) -> Nil {
  actor.send(rate_limiter, SetNow(now))
}
