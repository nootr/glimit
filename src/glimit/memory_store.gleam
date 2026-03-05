//// Internal in-memory store adapter backed by an OTP actor.
//// This module is not part of the public API.
////

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import glimit/bucket.{type BucketState}
import glimit/utils

const call_timeout = 1000

/// Opaque handle to the in-memory store actor.
/// Provides get/set/sweep/count/remove operations for in-memory rate limiting.
///
pub opaque type MemoryStore {
  MemoryStore(subject: Subject(Msg))
}

type State {
  State(
    data: Dict(String, BucketState),
    max_idle_ms: Option(Int),
    sweep_interval_ms: Int,
    self_subject: Subject(Msg),
  )
}

type Msg {
  Get(key: String, reply: Subject(Option(BucketState)))
  Set(key: String, state: BucketState, reply: Subject(Nil))
  Sweep(now: Int, max_idle_ms: Option(Int), reply: Subject(Nil))
  SweepTimer
  GetCount(reply: Subject(Int))
  Remove(key: String, reply: Subject(Nil))
}

/// Create a new in-memory store.
///
/// `max_idle_ms` is the idle eviction threshold, or `None` to disable.
/// `sweep_interval_ms` is the interval between automatic sweeps.
///
pub fn new(
  max_idle_ms: Option(Int),
  sweep_interval_ms: Int,
) -> Result(MemoryStore, Nil) {
  let start_result =
    actor.new_with_initialiser(call_timeout, fn(self_subject) {
      let state =
        State(
          data: dict.new(),
          max_idle_ms: max_idle_ms,
          sweep_interval_ms: sweep_interval_ms,
          self_subject: self_subject,
        )

      schedule_sweep(state)

      Ok(
        actor.initialised(state)
        |> actor.returning(self_subject),
      )
    })
    |> actor.on_message(handle_message)
    |> actor.start

  case start_result {
    Ok(started) -> Ok(MemoryStore(subject: started.data))
    Error(_) -> Error(Nil)
  }
}

/// Create a `bucket.Store` backed by this in-memory actor.
///
/// Lock and unlock are no-ops since the OTP actor serializes messages.
///
pub fn make_store(store: MemoryStore) -> bucket.Store {
  bucket.Store(
    lock_and_get: fn(key) {
      utils.safe_call(store.subject, Get(key, _), call_timeout)
    },
    set_and_unlock: fn(key, state, _ttl) {
      utils.safe_call(store.subject, Set(key, state, _), call_timeout)
    },
    unlock: fn(_key) { Ok(Nil) },
  )
}

fn handle_message(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Get(key, reply) -> {
      actor.send(reply, dict.get(state.data, key) |> option.from_result)
      actor.continue(state)
    }

    Set(key, bucket_state, reply) -> {
      let data = dict.insert(state.data, key, bucket_state)
      actor.send(reply, Nil)
      actor.continue(State(..state, data: data))
    }

    Sweep(now, max_idle_ms, reply) -> {
      let data = do_sweep(state.data, now, max_idle_ms)
      actor.send(reply, Nil)
      actor.continue(State(..state, data: data))
    }

    SweepTimer -> {
      let now = utils.now()
      let data = do_sweep(state.data, now, state.max_idle_ms)
      schedule_sweep(state)
      actor.continue(State(..state, data: data))
    }

    GetCount(reply) -> {
      actor.send(reply, dict.size(state.data))
      actor.continue(state)
    }

    Remove(key, reply) -> {
      let data = dict.delete(state.data, key)
      actor.send(reply, Nil)
      actor.continue(State(..state, data: data))
    }
  }
}

fn do_sweep(
  data: Dict(String, BucketState),
  now: Int,
  max_idle_ms: Option(Int),
) -> Dict(String, BucketState) {
  data
  |> dict.filter(fn(_key, b) {
    !bucket.is_full(b, now) && !is_idle(b, now, max_idle_ms)
  })
}

fn is_idle(b: BucketState, now: Int, max_idle_ms: Option(Int)) -> Bool {
  case max_idle_ms {
    None -> False
    Some(threshold) ->
      case b.last_update {
        None -> True
        Some(last_update) -> now - last_update > threshold
      }
  }
}

fn schedule_sweep(state: State) -> Nil {
  let _ =
    process.send_after(state.self_subject, state.sweep_interval_ms, SweepTimer)
  Nil
}

/// Return the pid of the memory store actor.
///
pub fn pid(store: MemoryStore) -> Result(process.Pid, Nil) {
  process.subject_owner(store.subject)
}

/// Return the number of tracked identifiers.
///
pub fn get_count(store: MemoryStore) -> Int {
  utils.safe_call(store.subject, GetCount, call_timeout)
  |> result.unwrap(0)
}

/// Remove an identifier from the store.
///
pub fn remove(store: MemoryStore, key: String) -> Result(Nil, Nil) {
  utils.safe_call(store.subject, Remove(key, _), call_timeout)
}

/// Sweep full or idle buckets synchronously.
///
pub fn sweep(
  store: MemoryStore,
  now: Int,
  max_idle_ms: Option(Int),
) -> Result(Nil, Nil) {
  utils.safe_call(store.subject, Sweep(now, max_idle_ms, _), call_timeout)
}
