//// This module contains a rate limiter actor that stores token-bucket state inline.
////

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import glimit/bucket.{type BucketState}
import glimit/utils

const call_timeout = 1000

const max_idle_ms = 60_000

/// Error type returned by `hit`.
///
pub type HitError {
  /// The rate limit has been exceeded.
  RateLimited
  /// The rate limiter is unavailable.
  Unavailable
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
    /// Inline bucket state per identifier.
    ///
    buckets: Dict(id, BucketState),
    /// The interval in milliseconds between sweeps.
    ///
    sweep_interval_ms: Option(Int),
    /// The actor's own subject for self-messaging.
    ///
    self_subject: Subject(Message(id)),
    /// Test time override.
    ///
    now: Option(Int),
  )
}

pub type Message(id) {
  /// Hit the rate limiter for the given id (creates bucket if missing).
  ///
  Hit(identifier: id, reply_with: Subject(Result(Nil, HitError)))
  /// Return the number of tracked identifiers.
  ///
  GetCount(reply_with: Subject(Int))
  /// Remove an identifier from the rate limiter.
  ///
  Remove(identifier: id, reply_with: Subject(Nil))
  /// Fire-and-forget sweep, used by send_after for periodic scheduling.
  ///
  Sweep
  /// Synchronous sweep variant for tests.
  ///
  SweepSync(reply_with: Subject(Nil))
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

fn ensure_bucket(
  state: State(id),
  identifier: id,
) -> Result(#(BucketState, State(id)), Nil) {
  case dict.get(state.buckets, identifier) {
    Ok(b) -> Ok(#(b, state))
    Error(_) -> {
      use max <- result.try(
        utils.rescue(fn() { state.max_token_count(identifier) }),
      )
      use rate <- result.try(
        utils.rescue(fn() { state.token_rate(identifier) }),
      )
      case bucket.new(max, rate) {
        Ok(b) -> {
          let buckets = dict.insert(state.buckets, identifier, b)
          Ok(#(b, State(..state, buckets: buckets)))
        }
        Error(_) -> Error(Nil)
      }
    }
  }
}

fn do_sweep(state: State(id)) -> State(id) {
  let now = get_now(state)
  let buckets =
    state.buckets
    |> dict.filter(fn(_id, b) {
      !bucket.is_full(b, now) && !is_idle(b, now)
    })
  State(..state, buckets: buckets)
}

fn is_idle(state: BucketState, now: Int) -> Bool {
  case state.last_update {
    None -> True
    Some(last_update) -> now - last_update > max_idle_ms
  }
}

fn schedule_sweep(state: State(id)) -> Nil {
  case state.sweep_interval_ms {
    Some(ms) -> {
      let _ = process.send_after(state.self_subject, ms, Sweep)
      Nil
    }
    None -> Nil
  }
}

fn handle_message(
  state: State(id),
  message: Message(id),
) -> actor.Next(State(id), Message(id)) {
  case message {
    Hit(identifier, client) -> {
      case ensure_bucket(state, identifier) {
        Ok(#(b, state)) -> {
          let now = get_now(state)
          let #(result, b) = bucket.hit(b, now)
          let buckets = dict.insert(state.buckets, identifier, b)
          let state = State(..state, buckets: buckets)
          case result {
            Ok(Nil) -> actor.send(client, Ok(Nil))
            Error(Nil) -> actor.send(client, Error(RateLimited))
          }
          actor.continue(state)
        }
        Error(_) -> {
          actor.send(client, Error(Unavailable))
          actor.continue(state)
        }
      }
    }

    GetCount(client) -> {
      actor.send(client, dict.size(state.buckets))
      actor.continue(state)
    }

    Remove(identifier, client) -> {
      let buckets = dict.delete(state.buckets, identifier)
      let state = State(..state, buckets: buckets)
      actor.send(client, Nil)
      actor.continue(state)
    }

    Sweep -> {
      let state = do_sweep(state)
      schedule_sweep(state)
      actor.continue(state)
    }

    SweepSync(client) -> {
      let state = do_sweep(state)
      actor.send(client, Nil)
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
) -> Result(RateLimiterActor(id), Nil) {
  let sweep_interval_ms = Some(10_000)

  actor.new_with_initialiser(call_timeout, fn(self_subject) {
    let state =
      State(
        max_token_count: burst_limit,
        token_rate: per_second,
        buckets: dict.new(),
        sweep_interval_ms: sweep_interval_ms,
        self_subject: self_subject,
        now: None,
      )

    schedule_sweep(state)

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

/// Return the number of tracked identifiers.
///
pub fn get_count(rate_limiter: RateLimiterActor(id)) -> Int {
  utils.safe_call(rate_limiter, GetCount, call_timeout)
  |> result.unwrap(0)
}

/// Remove an identifier from the rate limiter.
///
pub fn remove(
  rate_limiter: RateLimiterActor(id),
  identifier: id,
) -> Result(Nil, Nil) {
  utils.safe_call(rate_limiter, Remove(identifier, _), call_timeout)
}

/// Remove full buckets from the rate limiter synchronously.
/// Intended for testing — production uses the periodic `Sweep` timer.
///
pub fn sweep(rate_limiter: RateLimiterActor(id)) -> Result(Nil, Nil) {
  utils.safe_call(rate_limiter, SweepSync, call_timeout)
}

/// Set the current time for testing purposes.
/// The `now` value is in milliseconds.
///
pub fn set_now(rate_limiter: RateLimiterActor(id), now: Int) -> Nil {
  let _ = utils.safe_call(rate_limiter, SetNow(now, _), call_timeout)
  Nil
}
