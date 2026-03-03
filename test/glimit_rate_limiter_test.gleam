import gleam/erlang/process
import gleeunit/should
import glimit/rate_limiter

pub fn hit_returns_ok_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.hit(rl, "a") |> should.be_ok
}

pub fn hit_rate_limited_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.equal(Error(rate_limiter.RateLimited))
}

pub fn hit_different_ids_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 1 }, fn(_) { 1 })
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.equal(Error(rate_limiter.RateLimited))
  rate_limiter.hit(rl, "b") |> should.be_ok
  rate_limiter.hit(rl, "b") |> should.equal(Error(rate_limiter.RateLimited))
}

pub fn get_count_empty_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.get_count(rl) |> should.equal(0)
}

pub fn get_count_after_hits_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "b") |> should.be_ok
  rate_limiter.get_count(rl) |> should.equal(2)
}

pub fn same_id_same_count_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.get_count(rl) |> should.equal(1)
}

pub fn sweep_full_bucket_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.set_now(rl, 0)
  // Hit then let it refill to full
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.set_now(rl, 1_000_000)
  let assert Ok(Nil) = rate_limiter.sweep(rl)
  // Full bucket should be swept
  rate_limiter.get_count(rl) |> should.equal(0)
}

pub fn sweep_not_full_bucket_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.set_now(rl, 0)
  rate_limiter.hit(rl, "a") |> should.be_ok
  let assert Ok(Nil) = rate_limiter.sweep(rl)
  // Not full — should be kept
  rate_limiter.get_count(rl) |> should.equal(1)
}

pub fn sweep_after_long_time_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.set_now(rl, 0)
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a")
  |> should.equal(Error(rate_limiter.RateLimited))

  // After a long time, bucket refills to full
  rate_limiter.set_now(rl, 1_000_000)
  let assert Ok(Nil) = rate_limiter.sweep(rl)
  rate_limiter.get_count(rl) |> should.equal(0)
}

pub fn sweep_empty_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  let assert Ok(Nil) = rate_limiter.sweep(rl)
}

pub fn sweep_mixed_buckets_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.set_now(rl, 0)

  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "b") |> should.be_ok
  rate_limiter.hit(rl, "c") |> should.be_ok
  rate_limiter.hit(rl, "c") |> should.be_ok

  // "a" and "c" are exhausted (0 tokens), "b" has 1 token
  // After long time, all refill to full
  rate_limiter.set_now(rl, 1_000_000)
  let assert Ok(Nil) = rate_limiter.sweep(rl)
  // All refilled to full → all swept
  rate_limiter.get_count(rl) |> should.equal(0)
}

pub fn sweep_keeps_active_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.set_now(rl, 0)
  rate_limiter.hit(rl, "a") |> should.be_ok
  let assert Ok(Nil) = rate_limiter.sweep(rl)
  // "a" has 1 token at t=0, not full → kept
  rate_limiter.get_count(rl) |> should.equal(1)
}

pub fn sweep_all_active_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.set_now(rl, 0)
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.hit(rl, "b") |> should.be_ok
  rate_limiter.hit(rl, "c") |> should.be_ok
  let assert Ok(Nil) = rate_limiter.sweep(rl)
  // All have 1 token, not full → all kept
  rate_limiter.get_count(rl) |> should.equal(3)
}

pub fn remove_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.hit(rl, "a") |> should.be_ok
  rate_limiter.get_count(rl) |> should.equal(1)
  let assert Ok(Nil) = rate_limiter.remove(rl, "a")
  rate_limiter.get_count(rl) |> should.equal(0)
}

pub fn remove_nonexistent_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.remove(rl, "nonexistent") |> should.equal(Ok(Nil))
}

pub fn set_now_and_hit_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 1 }, fn(_) { 3 })
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
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })
  rate_limiter.set_now(rl, 0)

  // Hit "keep" so it's active
  rate_limiter.hit(rl, "keep") |> should.be_ok
  // Hit "remove" and exhaust, then let it refill
  rate_limiter.hit(rl, "remove") |> should.be_ok
  rate_limiter.hit(rl, "remove") |> should.be_ok

  // At t=1_000_000, both refill to full
  rate_limiter.set_now(rl, 1_000_000)
  let assert Ok(Nil) = rate_limiter.sweep(rl)

  // "keep" had 1 token at t=0, after 1_000_000ms it will be full too
  rate_limiter.get_count(rl) |> should.equal(0)
}

pub fn dynamic_config_test() {
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
    )

  rate_limiter.hit(rl, "fast") |> should.be_ok
  rate_limiter.hit(rl, "fast") |> should.be_ok
  rate_limiter.hit(rl, "slow") |> should.be_ok
  rate_limiter.hit(rl, "slow")
  |> should.equal(Error(rate_limiter.RateLimited))
}

pub fn invalid_config_returns_unavailable_test() {
  // per_second returns 0 for "bad" — invalid config
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
    )

  // Valid identifier works
  rate_limiter.hit(rl, "good") |> should.be_ok

  // Invalid config fails open with Unavailable
  rate_limiter.hit(rl, "bad")
  |> should.equal(Error(rate_limiter.Unavailable))

  // Invalid identifier is not stored
  rate_limiter.get_count(rl) |> should.equal(1)
}

pub fn crashing_callback_returns_unavailable_test() {
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
    )

  // Crashing callback should return Unavailable, not kill the actor
  rate_limiter.hit(rl, "crash")
  |> should.equal(Error(rate_limiter.Unavailable))

  // Actor is still alive and serving other identifiers
  rate_limiter.hit(rl, "good") |> should.be_ok
}

pub fn crashing_single_callback_returns_unavailable_test() {
  // Only per_second crashes; burst_limit is fine
  let assert Ok(rl) =
    rate_limiter.new(
      fn(id) {
        case id {
          "crash" -> panic as "boom"
          _ -> 2
        }
      },
      fn(_) { 2 },
    )

  rate_limiter.hit(rl, "crash")
  |> should.equal(Error(rate_limiter.Unavailable))

  rate_limiter.hit(rl, "good") |> should.be_ok
}

pub fn dead_rate_limiter_returns_unavailable_test() {
  let assert Ok(rl) = rate_limiter.new(fn(_) { 2 }, fn(_) { 2 })

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
