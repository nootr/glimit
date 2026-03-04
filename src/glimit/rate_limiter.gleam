//// This module contains a rate limiter actor that delegates to a pluggable Store.
////

import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import glimit/bucket.{type BucketState}
import glimit/utils

const call_timeout = 1000

const store_key_prefix = "glimit:"

/// Error type returned by `hit`.
///
pub type HitError {
  /// The rate limit has been exceeded.
  RateLimited
  /// The rate limiter is unavailable.
  Unavailable
  /// The store lock could not be acquired (fails open).
  StoreLockFailed
}

pub type RateLimiterActor(id) =
  Subject(Message(id))

/// The rate limiter state.
///
type State(id) {
  State(
    /// The maximum number of tokens.
    ///
    max_token_count: fn(id) -> Int,
    /// The rate of token generation per second.
    ///
    token_rate: fn(id) -> Int,
    /// The store backend.
    ///
    store: bucket.Store,
    /// Test time override.
    ///
    now: Option(Int),
  )
}

pub type Message(id) {
  /// Hit the rate limiter for the given id.
  ///
  Hit(identifier: id, reply_with: Subject(Result(Nil, HitError)))
  /// Set the current time for testing purposes.
  ///
  SetNow(now: Int, reply_with: Subject(Nil))
}

fn get_now(state: State(id)) -> Int {
  case state.now {
    Some(now) -> now
    None -> utils.now()
  }
}

fn handle_store_hit(state: State(id), identifier: id) -> Result(Nil, HitError) {
  let key = string_key(identifier)
  // 1. Lock
  case state.store.lock(key) {
    Error(_) -> Error(StoreLockFailed)
    Ok(_) -> {
      // 2. Get existing state or create new bucket
      let bucket_result = case state.store.get(key) {
        Ok(Some(b)) -> Ok(b)
        Ok(None) -> {
          use max <- result.try(
            utils.rescue(fn() { state.max_token_count(identifier) }),
          )
          use rate <- result.try(
            utils.rescue(fn() { state.token_rate(identifier) }),
          )
          bucket.new(max, rate)
        }
        Error(_) -> {
          let _ = state.store.unlock(key)
          Error(Nil)
        }
      }
      case bucket_result {
        Error(_) -> {
          let _ = state.store.unlock(key)
          Error(Unavailable)
        }
        Ok(b) -> {
          // 3. Refill + consume
          let now = get_now(state)
          let #(hit_result, new_b) = bucket.hit(b, now)
          // 4. Persist
          let ttl = compute_ttl(new_b)
          let _ = state.store.set(key, new_b, ttl)
          // 5. Unlock
          let _ = state.store.unlock(key)
          case hit_result {
            Ok(Nil) -> Ok(Nil)
            Error(Nil) -> Error(RateLimited)
          }
        }
      }
    }
  }
}

fn string_key(identifier: id) -> String {
  store_key_prefix <> string.inspect(identifier)
}

fn compute_ttl(b: BucketState) -> Int {
  case b.token_rate > 0 {
    True -> {
      // Time to fully refill from empty, plus a buffer
      let refill_seconds =
        { b.max_token_count + b.token_rate - 1 } / b.token_rate
      int.max(refill_seconds * 2, 60)
    }
    False -> 60
  }
}

fn handle_message(
  state: State(id),
  message: Message(id),
) -> actor.Next(State(id), Message(id)) {
  case message {
    Hit(identifier, client) -> {
      let result = handle_store_hit(state, identifier)
      actor.send(client, result)
      actor.continue(state)
    }

    SetNow(now, client) -> {
      actor.send(client, Nil)
      actor.continue(State(..state, now: Some(now)))
    }
  }
}

/// Create a new rate limiter.
///
pub fn new(
  per_second: fn(id) -> Int,
  burst_limit: fn(id) -> Int,
  store: bucket.Store,
) -> Result(RateLimiterActor(id), Nil) {
  actor.new_with_initialiser(call_timeout, fn(self_subject) {
    let state =
      State(
        max_token_count: burst_limit,
        token_rate: per_second,
        store: store,
        now: None,
      )

    Ok(
      actor.initialised(state)
      |> actor.returning(self_subject),
    )
  })
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.map_error(fn(_) { Nil })
}

/// Hit the rate limiter for the given identifier.
///
pub fn hit(
  rate_limiter: RateLimiterActor(id),
  identifier: id,
) -> Result(Nil, HitError) {
  case utils.safe_call(rate_limiter, Hit(identifier, _), call_timeout) {
    Ok(Ok(Nil)) -> Ok(Nil)
    Ok(Error(err)) -> Error(err)
    Error(Nil) -> Error(Unavailable)
  }
}

/// Set the current time for testing purposes.
/// The `now` value is in milliseconds.
///
pub fn set_now(rate_limiter: RateLimiterActor(id), now: Int) -> Nil {
  let _ = utils.safe_call(rate_limiter, SetNow(now, _), call_timeout)
  Nil
}
