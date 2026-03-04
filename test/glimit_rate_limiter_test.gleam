import gleam/erlang/process
import gleam/list
import gleam/option.{Some}
import gleeunit/should
import glimit/memory_store
import glimit/rate_limiter

fn new_rl(
  per_second: fn(String) -> Int,
  burst_limit: fn(String) -> Int,
  max_idle_ms: option.Option(Int),
) -> #(rate_limiter.RateLimiterActor(String), memory_store.MemoryStore) {
  let assert Ok(#(store, ms)) = memory_store.new(max_idle_ms, 10_000)
  let assert Ok(rl) = rate_limiter.new(per_second, burst_limit, store)
  #(rl, ms)
}

pub fn hit_returns_ok_test() {
  let #(rl, _ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  rate_limiter.hit(rl, "a") |> should.be_ok
}

pub fn hit_rate_limited_test() {
  let #(rl, _ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.equal(Error(rate_limiter.RateLimited))
}

pub fn hit_different_ids_test() {
  let #(rl, _ms) = new_rl(fn(_) { 1 }, fn(_) { 1 }, Some(60_000))
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.equal(Error(rate_limiter.RateLimited))
  rate_limiter.hit(rl, "b") |> should.be_ok
  rate_limiter.hit(rl, "b") |> should.equal(Error(rate_limiter.RateLimited))
}

pub fn get_count_empty_test() {
  let #(_rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn get_count_after_hits_test() {
  let #(rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "b") |> should.be_ok
  memory_store.get_count(ms) |> should.equal(2)
}

pub fn same_id_same_count_test() {
  let #(rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.be_ok
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn sweep_full_bucket_test() {
  let #(rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  rate_limiter.set_now(rl, 0)
  // Hit then let it refill to full
  rate_limiter.hit(rl, "a") |> should.be_ok
  let assert Ok(Nil) = memory_store.sweep(ms, 1_000_000, Some(60_000))
  // Full bucket should be swept
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn sweep_not_full_bucket_test() {
  let #(rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  rate_limiter.set_now(rl, 0)
  rate_limiter.hit(rl, "a") |> should.be_ok
  let assert Ok(Nil) = memory_store.sweep(ms, 0, Some(60_000))
  // Not full — should be kept
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn sweep_after_long_time_test() {
  let #(rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  rate_limiter.set_now(rl, 0)
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a")
  |> should.equal(Error(rate_limiter.RateLimited))

  // After a long time, bucket refills to full
  let assert Ok(Nil) = memory_store.sweep(ms, 1_000_000, Some(60_000))
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn sweep_empty_test() {
  let #(_rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  let assert Ok(Nil) = memory_store.sweep(ms, 0, Some(60_000))
}

pub fn sweep_mixed_buckets_test() {
  let #(rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  rate_limiter.set_now(rl, 0)

  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "b") |> should.be_ok
  rate_limiter.hit(rl, "c") |> should.be_ok
  rate_limiter.hit(rl, "c") |> should.be_ok

  // After long time, all refill to full
  let assert Ok(Nil) = memory_store.sweep(ms, 1_000_000, Some(60_000))
  // All refilled to full → all swept
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn sweep_keeps_active_test() {
  let #(rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  rate_limiter.set_now(rl, 0)
  rate_limiter.hit(rl, "a") |> should.be_ok
  let assert Ok(Nil) = memory_store.sweep(ms, 0, Some(60_000))
  // "a" has 1 token at t=0, not full → kept
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn sweep_all_active_test() {
  let #(rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  rate_limiter.set_now(rl, 0)
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "b") |> should.be_ok
  rate_limiter.hit(rl, "c") |> should.be_ok
  let assert Ok(Nil) = memory_store.sweep(ms, 0, Some(60_000))
  // All have 1 token, not full → all kept
  memory_store.get_count(ms) |> should.equal(3)
}

pub fn remove_test() {
  let #(rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  rate_limiter.hit(rl, "a") |> should.be_ok
  memory_store.get_count(ms) |> should.equal(1)
  let assert Ok(Nil) = memory_store.remove(ms, "glimit:\"a\"")
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn remove_nonexistent_test() {
  let #(_rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  memory_store.remove(ms, "glimit:\"nonexistent\"") |> should.equal(Ok(Nil))
}

pub fn set_now_and_hit_test() {
  let #(rl, _ms) = new_rl(fn(_) { 1 }, fn(_) { 3 }, Some(60_000))
  rate_limiter.set_now(rl, 0)

  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a")
  |> should.equal(Error(rate_limiter.RateLimited))

  rate_limiter.set_now(rl, 1000)
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a")
  |> should.equal(Error(rate_limiter.RateLimited))
}

pub fn sweep_get_count_after_sweep_test() {
  let #(rl, ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))
  rate_limiter.set_now(rl, 0)

  // Hit "keep" so it's active
  rate_limiter.hit(rl, "keep") |> should.be_ok
  // Hit "remove" and exhaust
  rate_limiter.hit(rl, "remove") |> should.be_ok
  rate_limiter.hit(rl, "remove") |> should.be_ok

  // At t=1_000_000, both refill to full
  let assert Ok(Nil) = memory_store.sweep(ms, 1_000_000, Some(60_000))

  // Both full → both swept
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn dynamic_config_test() {
  let assert Ok(#(store, _ms)) = memory_store.new(Some(60_000), 10_000)
  let assert Ok(rl) =
    rate_limiter.new(
      fn(id) {
        case id {
          "fast" -> 10
          _ -> 1
        }
      },
      fn(id) {
        case id {
          "fast" -> 10
          _ -> 1
        }
      },
      store,
    )

  rate_limiter.hit(rl, "fast") |> should.be_ok
  rate_limiter.hit(rl, "fast") |> should.be_ok
  rate_limiter.hit(rl, "slow") |> should.be_ok
  rate_limiter.hit(rl, "slow")
  |> should.equal(Error(rate_limiter.RateLimited))
}

pub fn invalid_config_returns_unavailable_test() {
  let assert Ok(#(store, ms)) = memory_store.new(Some(60_000), 10_000)
  let assert Ok(rl) =
    rate_limiter.new(
      fn(id) {
        case id {
          "bad" -> 0
          _ -> 2
        }
      },
      fn(id) {
        case id {
          "bad" -> 0
          _ -> 2
        }
      },
      store,
    )

  // Valid identifier works
  rate_limiter.hit(rl, "good") |> should.be_ok

  // Invalid config fails open with Unavailable
  rate_limiter.hit(rl, "bad")
  |> should.equal(Error(rate_limiter.Unavailable))

  // Invalid identifier is not stored
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn crashing_callback_returns_unavailable_test() {
  let assert Ok(#(store, _ms)) = memory_store.new(Some(60_000), 10_000)
  let assert Ok(rl) =
    rate_limiter.new(
      fn(id) {
        case id {
          "crash" -> panic as "boom"
          _ -> 2
        }
      },
      fn(id) {
        case id {
          "crash" -> panic as "boom"
          _ -> 2
        }
      },
      store,
    )

  // Crashing callback should return Unavailable, not kill the actor
  rate_limiter.hit(rl, "crash")
  |> should.equal(Error(rate_limiter.Unavailable))

  // Actor is still alive and serving other identifiers
  rate_limiter.hit(rl, "good") |> should.be_ok
}

pub fn crashing_single_callback_returns_unavailable_test() {
  let assert Ok(#(store, _ms)) = memory_store.new(Some(60_000), 10_000)
  let assert Ok(rl) =
    rate_limiter.new(
      fn(id) {
        case id {
          "crash" -> panic as "boom"
          _ -> 2
        }
      },
      fn(_) { 2 },
      store,
    )

  rate_limiter.hit(rl, "crash")
  |> should.equal(Error(rate_limiter.Unavailable))

  rate_limiter.hit(rl, "good") |> should.be_ok
}

pub fn sweep_idle_bucket_test() {
  let #(rl, ms) = new_rl(fn(_) { 1 }, fn(_) { 100 }, Some(60_000))
  rate_limiter.set_now(rl, 0)

  // Exhaust all 100 tokens
  list.repeat(Nil, 100)
  |> list.each(fn(_) {
    let _ = rate_limiter.hit(rl, "a")
    Nil
  })

  memory_store.get_count(ms) |> should.equal(1)

  // At t=61_000: tokens = 0 + 61 = 61 < 100, not full
  // But idle for 61s > 60s threshold — should be swept
  let assert Ok(Nil) = memory_store.sweep(ms, 61_000, Some(60_000))

  memory_store.get_count(ms) |> should.equal(0)
}

pub fn sweep_idle_exact_boundary_test() {
  let #(rl, ms) = new_rl(fn(_) { 1 }, fn(_) { 100 }, Some(60_000))
  rate_limiter.set_now(rl, 0)

  list.repeat(Nil, 100)
  |> list.each(fn(_) {
    let _ = rate_limiter.hit(rl, "a")
    Nil
  })

  // 60_000 - 0 = 60_000, which is NOT > 60_000 — kept
  let assert Ok(Nil) = memory_store.sweep(ms, 60_000, Some(60_000))
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn sweep_idle_preserves_recent_bucket_test() {
  let #(rl, ms) = new_rl(fn(_) { 1 }, fn(_) { 100 }, Some(60_000))
  rate_limiter.set_now(rl, 0)

  list.repeat(Nil, 100)
  |> list.each(fn(_) {
    let _ = rate_limiter.hit(rl, "a")
    Nil
  })

  // At t=59_000: tokens = 59 < 100 (not full), idle for 59s < 60s (not idle)
  let assert Ok(Nil) = memory_store.sweep(ms, 59_000, Some(60_000))

  // Should be kept — not full and not idle
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn dead_rate_limiter_returns_unavailable_test() {
  let #(rl, _ms) = new_rl(fn(_) { 2 }, fn(_) { 2 }, Some(60_000))

  // Trap exits so the kill signal doesn't crash the test process
  let _trapped = process.trap_exits(True)

  // Kill the actor
  let assert Ok(pid) = process.subject_owner(rl)
  process.kill(pid)
  process.sleep(10)

  // Hit should return Unavailable, not crash
  rate_limiter.hit(rl, "a")
  |> should.equal(Error(rate_limiter.Unavailable))
}
