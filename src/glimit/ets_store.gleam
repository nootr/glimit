//// ETS-backed storage backend for rate limiting.
////
//// Uses a public ETS table with atomic operations, avoiding the overhead
//// of OTP actor messages. Suitable for single-node deployments where
//// low latency is important.
////
//// Unlike the default in-memory store (which serializes through an actor),
//// ETS operations are lock-free and concurrent. The trade-off is that
//// lock/unlock semantics are no-ops — ETS provides atomicity at the
//// single-operation level, which is sufficient for token bucket updates.
////

import gleam/option.{type Option, None, Some}
import glimit/bucket.{type BucketState}
import glimit/utils

/// Opaque handle to an ETS-backed store.
///
pub opaque type EtsStore {
  EtsStore(table: EtsTable)
}

type EtsTable

/// Create a new ETS-backed store.
///
pub fn new() -> EtsStore {
  EtsStore(table: ets_new())
}

/// Create a new ETS-backed store with automatic periodic sweeping.
///
/// Full and idle buckets are removed every `sweep_interval_ms` milliseconds.
/// Set `max_idle_ms` to `None` to disable idle eviction.
///
pub fn new_with_sweep(
  max_idle_ms max_idle_ms: Option(Int),
  sweep_interval_ms sweep_interval_ms: Int,
) -> EtsStore {
  let store = new()
  start_sweep_timer(store, max_idle_ms, sweep_interval_ms)
  store
}

/// Create a `bucket.Store` backed by this ETS table.
///
/// Lock and unlock are no-ops since ETS provides per-key atomicity.
///
pub fn make_store(store: EtsStore) -> bucket.Store {
  bucket.Store(
    lock_and_get: fn(key) {
      case ets_get(store.table, key) {
        Ok(state) -> Ok(Some(state))
        Error(_) -> Ok(None)
      }
    },
    set_and_unlock: fn(key, state, _ttl) {
      ets_set(store.table, key, state)
    },
    unlock: fn(_key) { Ok(Nil) },
  )
}

/// Sweep full and idle buckets from the store.
///
pub fn sweep(
  store store: EtsStore,
  now now: Int,
  max_idle_ms max_idle_ms: Option(Int),
) -> Int {
  ets_sweep(store.table, fn(_key, state) {
    bucket.is_full(state, now) || is_idle(state, now, max_idle_ms)
  })
}

/// Return the number of tracked identifiers.
///
pub fn get_count(store: EtsStore) -> Int {
  ets_size(store.table)
}

/// Remove an identifier from the store.
///
pub fn remove(store: EtsStore, key: String) -> Result(Nil, Nil) {
  ets_delete(store.table, key)
}

fn is_idle(
  state: BucketState,
  now: Int,
  max_idle_ms: Option(Int),
) -> Bool {
  case max_idle_ms {
    None -> False
    Some(threshold) ->
      case state.last_update {
        None -> True
        Some(last_update) -> now - last_update > threshold
      }
  }
}

fn start_sweep_timer(
  store: EtsStore,
  max_idle_ms: Option(Int),
  sweep_interval_ms: Int,
) -> Nil {
  let store_ref = store
  ets_set_interval(sweep_interval_ms, fn() {
    let now = utils.now()
    sweep(store: store_ref, now: now, max_idle_ms: max_idle_ms)
    Nil
  })
}

// --- Erlang FFI ---

@external(erlang, "ets_store_ffi", "new")
fn ets_new() -> EtsTable

@external(erlang, "ets_store_ffi", "get")
fn ets_get(table: EtsTable, key: String) -> Result(BucketState, Nil)

@external(erlang, "ets_store_ffi", "set")
fn ets_set(
  table: EtsTable,
  key: String,
  state: BucketState,
) -> Result(Nil, Nil)

@external(erlang, "ets_store_ffi", "delete")
fn ets_delete(table: EtsTable, key: String) -> Result(Nil, Nil)

@external(erlang, "ets_store_ffi", "sweep")
fn ets_sweep(
  table: EtsTable,
  predicate: fn(String, BucketState) -> Bool,
) -> Int

@external(erlang, "ets_store_ffi", "size")
fn ets_size(table: EtsTable) -> Int

@external(erlang, "ets_store_ffi", "set_interval")
fn ets_set_interval(interval_ms: Int, callback: fn() -> Nil) -> Nil
