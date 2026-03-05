import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option
import gleam/otp/actor
import gleeunit
import gleeunit/should
import glimit
import glimit/bucket
import glimit/memory_store

pub fn main() {
  gleeunit.main()
}

pub fn single_argument_function_per_second_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(_) { "OK" }
    |> glimit.apply(limiter)

  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")
}

pub fn single_argument_function_different_ids_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(_) { "OK" }
    |> glimit.apply(limiter)

  func("a") |> should.equal("OK")
  func("b") |> should.equal("OK")
  func("b") |> should.equal("OK")
  func("b") |> should.equal("Stop!")
  func("a") |> should.equal("OK")
  func("a") |> should.equal("Stop!")
}

pub fn burst_limit_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 3000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 6000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 13_000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn dynamic_per_second_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "id" -> 2
        _ -> 1
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(_) { "OK" }
    |> glimit.apply(limiter)

  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  func("other") |> should.equal("OK")
  func("other") |> should.equal("Stop!")
  func("other") |> should.equal("Stop!")
}

pub fn dynamic_per_second_static_burst_limit_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "id" -> 2
        _ -> 1
      }
    })
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.equal(Error(glimit.RateLimited))
}

pub fn static_per_second_dynamic_burst_limit_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit_fn(fn(id) {
      case id {
        "id" -> 3
        _ -> 2
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.equal(Error(glimit.RateLimited))
}

pub fn dynamic_per_second_dynamic_burst_limit_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "id" -> 2
        _ -> 1
      }
    })
    |> glimit.burst_limit_fn(fn(id) {
      case id {
        "id" -> 4
        _ -> 3
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.equal(Error(glimit.RateLimited))
}

pub fn sweep_preserves_active_limiters_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  // Hit "user_a" once — active, not full
  glimit.hit(limiter, "user_a") |> should.be_ok
  glimit.hit(limiter, "user_b") |> should.be_ok
  glimit.hit(limiter, "user_b") |> should.be_ok

  let assert Ok(Nil) = memory_store.sweep(ms, 0, option.Some(60_000))

  // Both are active (not full) → both kept
  memory_store.get_count(ms) |> should.equal(2)

  // user_a still has 1 token left
  glimit.hit(limiter, "user_a") |> should.be_ok
  glimit.hit(limiter, "user_a") |> should.equal(Error(glimit.RateLimited))
}

pub fn integration_many_identifiers_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(3)
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  let ids = [
    "id_0", "id_1", "id_2", "id_3", "id_4", "id_5", "id_6", "id_7", "id_8",
    "id_9",
  ]

  // Hit each ID i times (id_0: 0 hits, id_1: 1 hit, etc.)
  list.index_map(ids, fn(id, i) {
    list.repeat(Nil, i)
    |> list.each(fn(_) { glimit.hit(limiter, id) |> ignore })
  })

  // id_0 was never hit so doesn't exist
  // id_1..id_9 were hit at least once
  let count_before = memory_store.get_count(ms)
  count_before |> should.equal(9)

  let assert Ok(Nil) = memory_store.sweep(ms, 0, option.Some(60_000))

  // At t=0, none have had time to refill — all kept
  let count_after = memory_store.get_count(ms)
  count_after |> should.equal(9)
}

pub fn integration_sweep_then_reuse_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  // Exhaust "user_a" (all tokens used)
  glimit.hit(limiter, "user_a") |> should.be_ok
  glimit.hit(limiter, "user_a") |> should.be_ok
  glimit.hit(limiter, "user_a") |> should.equal(Error(glimit.RateLimited))

  // Hit "user_b" once
  glimit.hit(limiter, "user_b") |> should.be_ok

  let assert Ok(Nil) = memory_store.sweep(ms, 0, option.Some(60_000))

  // At t=0, user_a has 0 tokens (not full), user_b has 1 token (not full) → both kept
  memory_store.get_count(ms) |> should.equal(2)

  // "user_a" is still rate-limited at t=0
  glimit.hit(limiter, "user_a") |> should.equal(Error(glimit.RateLimited))

  // Advance time so user_a gets tokens back
  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "user_a") |> should.be_ok
  glimit.hit(limiter, "user_a") |> should.be_ok
  glimit.hit(limiter, "user_a") |> should.equal(Error(glimit.RateLimited))
}

pub fn sub_second_remainder_preservation_test() {
  // 2 tokens/sec, burst 10 — one token every 500ms
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(10)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  // Consume all 10 tokens at t=0
  let limiter = set_now(limiter, 0)
  list.repeat(Nil, 10)
  |> list.each(fn(_) { glimit.hit(limiter, "id") |> ignore })
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 400ms: tc = 0.0 + 2.0 * 400 / 1000 = 0.8 < 1.0 — still rate limited
  let limiter = set_now(limiter, 400)
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 500ms: tc = 0.8 + 2.0 * 100 / 1000 = 1.0 >= 1.0 — succeeds
  let limiter = set_now(limiter, 500)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 900ms: tc = 0.0 + 2.0 * 400 / 1000 = 0.8 < 1.0
  let limiter = set_now(limiter, 900)
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 1000ms: tc = 0.8 + 2.0 * 100 / 1000 = 1.0 >= 1.0
  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 2500ms: tc = 0.0 + 2.0 * 1500 / 1000 = 3.0 — 3 tokens
  let limiter = set_now(limiter, 2500)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn sub_second_remainder_non_divisible_rate_test() {
  // 3 tokens/sec, burst 5 — one token every ~333.3ms.
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(3)
    |> glimit.burst_limit(5)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  // Drain all 5 tokens at t=0
  let limiter = set_now(limiter, 0)
  list.repeat(Nil, 5)
  |> list.each(fn(_) { glimit.hit(limiter, "id") |> ignore })
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 333ms: tc = 0.0 + 3.0 * 333 / 1000 = 0.999 < 1.0
  let limiter = set_now(limiter, 333)
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 334ms: tc = 0.999 + 3.0 * 1 / 1000 = 1.002 >= 1.0 — succeeds
  let limiter = set_now(limiter, 334)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 666ms: tc = 0.002 + 3.0 * 332 / 1000 = 0.998 < 1.0
  let limiter = set_now(limiter, 666)
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 667ms: tc = 0.998 + 3.0 * 1 / 1000 = 1.001 >= 1.0 — succeeds
  let limiter = set_now(limiter, 667)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 3000ms: tc = 0.001 + 3.0 * 2333 / 1000 = 7.0, capped at burst limit 5
  let limiter = set_now(limiter, 3000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn build_missing_per_second_test() {
  glimit.new()
  |> glimit.build
  |> should.equal(Error("`per_second` rate limit is required"))
}

pub fn build_missing_identifier_test() {
  glimit.new()
  |> glimit.per_second(1)
  |> glimit.build
  |> should.equal(Error("`identifier` function is required"))
}

pub fn build_missing_on_limit_exceeded_test() {
  glimit.new()
  |> glimit.per_second(1)
  |> glimit.identifier(fn(_) { "id" })
  |> glimit.build
  |> should.equal(Error("`on_limit_exceeded` function is required"))
}

pub fn builder_overwrite_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(999)
    |> glimit.per_second(1)
    |> glimit.burst_limit(999)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(_) { "wrong" })
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "wrong" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  // burst_limit=2: two hits succeed, third is limited
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // Advance 1 second — per_second=1 so only 1 token refilled (not 999)
  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn apply2_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(args: #(String, Int)) { args.0 })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(name: String, _count: Int) { "OK: " <> name }
    |> glimit.apply2(limiter)

  func("alice", 1) |> should.equal("OK: alice")
  func("alice", 2) |> should.equal("OK: alice")
  func("alice", 3) |> should.equal("Stop!")
  func("bob", 1) |> should.equal("OK: bob")
}

pub fn apply3_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.identifier(fn(args: #(String, Int, Bool)) { args.0 })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(name: String, _count: Int, _flag: Bool) { "OK: " <> name }
    |> glimit.apply3(limiter)

  func("alice", 1, True) |> should.equal("OK: alice")
  func("alice", 2, False) |> should.equal("Stop!")
}

pub fn apply4_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.identifier(fn(args: #(String, Int, Bool, String)) { args.0 })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(name: String, _a: Int, _b: Bool, _c: String) { "OK: " <> name }
    |> glimit.apply4(limiter)

  func("alice", 1, True, "x") |> should.equal("OK: alice")
  func("alice", 2, False, "y") |> should.equal("Stop!")
}

pub fn custom_max_idle_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(100)
    |> glimit.max_idle(120)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  // Exhaust all 100 tokens
  list.repeat(Nil, 100)
  |> list.each(fn(_) { glimit.hit(limiter, "id") |> ignore })

  memory_store.get_count(ms) |> should.equal(1)

  // At t=61_000: would be evicted with default 60s, but max_idle is 120s
  let assert Ok(Nil) = memory_store.sweep(ms, 61_000, option.Some(120_000))
  memory_store.get_count(ms) |> should.equal(1)

  // At t=121_000: now idle for 121s > 120s — evicted
  let assert Ok(Nil) = memory_store.sweep(ms, 121_000, option.Some(120_000))
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn disabled_idle_eviction_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(100)
    |> glimit.max_idle(0)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  // Exhaust all 100 tokens
  list.repeat(Nil, 100)
  |> list.each(fn(_) { glimit.hit(limiter, "id") |> ignore })

  // At t=61_000: bucket has 61 tokens (not full) and has been idle for >60s.
  // With default idle eviction this would be swept, but max_idle(0) disables it.
  let assert Ok(Nil) = memory_store.sweep(ms, 61_000, option.None)
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn negative_max_idle_disables_eviction_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(100)
    |> glimit.max_idle(-5)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  list.repeat(Nil, 100)
  |> list.each(fn(_) { glimit.hit(limiter, "id") |> ignore })

  // At t=61_000: idle for >60s but eviction is disabled
  let assert Ok(Nil) = memory_store.sweep(ms, 61_000, option.None)
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn max_idle_overwrite_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(100)
    |> glimit.max_idle(999)
    |> glimit.max_idle(120)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  list.repeat(Nil, 100)
  |> list.each(fn(_) { glimit.hit(limiter, "id") |> ignore })

  // At t=61_000: idle 61s, but max_idle is 120s (last set value) — kept
  let assert Ok(Nil) = memory_store.sweep(ms, 61_000, option.Some(120_000))
  memory_store.get_count(ms) |> should.equal(1)

  // At t=121_000: idle 121s > 120s — evicted
  let assert Ok(Nil) = memory_store.sweep(ms, 121_000, option.Some(120_000))
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn dead_memory_store_fails_open_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  // Verify normal operation first
  func("user") |> should.equal("OK")

  // Trap exits so the kill signal doesn't crash the test process
  let _trapped = process.trap_exits(True)

  // Kill the memory store actor
  let assert option.Some(ms) = limiter.memory_store
  let assert Ok(pid) = memory_store.pid(ms)
  process.kill(pid)
  process.sleep(10)

  // Should fail open — function still executes, not crash or rate limit
  func("user") |> should.equal("OK")
}

pub fn per_second_zero_fails_open_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(0)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  // Invalid config causes Unavailable → fails open
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
}

pub fn per_second_negative_fails_open_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(-1)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
}

// Tests merged from glimit_rate_limiter_test

pub fn hit_returns_ok_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
}

pub fn hit_rate_limited_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.equal(Error(glimit.RateLimited))
}

pub fn hit_different_ids_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(1)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.equal(Error(glimit.RateLimited))
  glimit.hit(limiter, "b") |> should.be_ok
  glimit.hit(limiter, "b") |> should.equal(Error(glimit.RateLimited))
}

pub fn get_count_empty_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.get_count(limiter) |> should.equal(0)
}

pub fn get_count_after_hits_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "b") |> should.be_ok
  glimit.get_count(limiter) |> should.equal(2)
}

pub fn same_id_same_count_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.get_count(limiter) |> should.equal(1)
}

pub fn sweep_full_bucket_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "a") |> should.be_ok
  let assert Ok(Nil) = memory_store.sweep(ms, 1_000_000, option.Some(60_000))
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn sweep_not_full_bucket_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "a") |> should.be_ok
  let assert Ok(Nil) = memory_store.sweep(ms, 0, option.Some(60_000))
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn sweep_after_long_time_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.equal(Error(glimit.RateLimited))

  let assert Ok(Nil) = memory_store.sweep(ms, 1_000_000, option.Some(60_000))
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn sweep_empty_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let assert Ok(Nil) = memory_store.sweep(ms, 0, option.Some(60_000))
}

pub fn sweep_mixed_buckets_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "b") |> should.be_ok
  glimit.hit(limiter, "c") |> should.be_ok
  glimit.hit(limiter, "c") |> should.be_ok

  let assert Ok(Nil) = memory_store.sweep(ms, 1_000_000, option.Some(60_000))
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn sweep_keeps_active_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "a") |> should.be_ok
  let assert Ok(Nil) = memory_store.sweep(ms, 0, option.Some(60_000))
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn sweep_all_active_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "b") |> should.be_ok
  glimit.hit(limiter, "c") |> should.be_ok
  let assert Ok(Nil) = memory_store.sweep(ms, 0, option.Some(60_000))
  memory_store.get_count(ms) |> should.equal(3)
}

pub fn remove_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store

  glimit.hit(limiter, "a") |> should.be_ok
  memory_store.get_count(ms) |> should.equal(1)
  let assert Ok(Nil) = memory_store.remove(ms, "glimit:\"a\"")
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn remove_nonexistent_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  memory_store.remove(ms, "glimit:\"nonexistent\"") |> should.equal(Ok(Nil))
}

pub fn set_now_and_hit_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.equal(Error(glimit.RateLimited))
}

pub fn sweep_get_count_after_sweep_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "keep") |> should.be_ok
  glimit.hit(limiter, "remove") |> should.be_ok
  glimit.hit(limiter, "remove") |> should.be_ok

  let assert Ok(Nil) = memory_store.sweep(ms, 1_000_000, option.Some(60_000))
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn dynamic_config_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "fast" -> 10
        _ -> 1
      }
    })
    |> glimit.burst_limit_fn(fn(id) {
      case id {
        "fast" -> 10
        _ -> 1
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "fast") |> should.be_ok
  glimit.hit(limiter, "fast") |> should.be_ok
  glimit.hit(limiter, "slow") |> should.be_ok
  glimit.hit(limiter, "slow") |> should.equal(Error(glimit.RateLimited))
}

pub fn invalid_config_returns_unavailable_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "bad" -> 0
        _ -> 2
      }
    })
    |> glimit.burst_limit_fn(fn(id) {
      case id {
        "bad" -> 0
        _ -> 2
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store

  // Valid identifier works
  glimit.hit(limiter, "good") |> should.be_ok

  // Invalid config fails open with Unavailable
  glimit.hit(limiter, "bad") |> should.equal(Error(glimit.Unavailable))

  // Invalid identifier is not stored
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn crashing_callback_returns_unavailable_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "crash" -> panic as "boom"
        _ -> 2
      }
    })
    |> glimit.burst_limit_fn(fn(id) {
      case id {
        "crash" -> panic as "boom"
        _ -> 2
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  // Crashing callback should return Unavailable
  glimit.hit(limiter, "crash") |> should.equal(Error(glimit.Unavailable))

  // Still serving other identifiers
  glimit.hit(limiter, "good") |> should.be_ok
}

pub fn crashing_single_callback_returns_unavailable_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "crash" -> panic as "boom"
        _ -> 2
      }
    })
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "crash") |> should.equal(Error(glimit.Unavailable))

  glimit.hit(limiter, "good") |> should.be_ok
}

pub fn sweep_idle_bucket_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(100)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  // Exhaust all 100 tokens
  list.repeat(Nil, 100)
  |> list.each(fn(_) {
    let _ = glimit.hit(limiter, "a")
    Nil
  })

  memory_store.get_count(ms) |> should.equal(1)

  // At t=61_000: tokens = 0 + 61 = 61 < 100, not full
  // But idle for 61s > 60s threshold — should be swept
  let assert Ok(Nil) = memory_store.sweep(ms, 61_000, option.Some(60_000))

  memory_store.get_count(ms) |> should.equal(0)
}

pub fn sweep_idle_exact_boundary_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(100)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  list.repeat(Nil, 100)
  |> list.each(fn(_) {
    let _ = glimit.hit(limiter, "a")
    Nil
  })

  // 60_000 - 0 = 60_000, which is NOT > 60_000 — kept
  let assert Ok(Nil) = memory_store.sweep(ms, 60_000, option.Some(60_000))
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn sweep_idle_preserves_recent_bucket_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(100)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert option.Some(ms) = limiter.memory_store
  let limiter = set_now(limiter, 0)

  list.repeat(Nil, 100)
  |> list.each(fn(_) {
    let _ = glimit.hit(limiter, "a")
    Nil
  })

  // At t=59_000: tokens = 59 < 100 (not full), idle for 59s < 60s (not idle)
  let assert Ok(Nil) = memory_store.sweep(ms, 59_000, option.Some(60_000))

  // Should be kept — not full and not idle
  memory_store.get_count(ms) |> should.equal(1)
}

pub fn dead_memory_store_returns_unavailable_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  // Trap exits so the kill signal doesn't crash the test process
  let _trapped = process.trap_exits(True)

  // Kill the memory store actor
  let assert option.Some(ms) = limiter.memory_store
  let assert Ok(pid) = memory_store.pid(ms)
  process.kill(pid)
  process.sleep(10)

  // Hit should return StoreLockFailed (lock_and_get fails on dead actor), not crash
  glimit.hit(limiter, "a") |> should.equal(Error(glimit.StoreLockFailed))
}

fn ignore(_value: a) -> Nil {
  Nil
}

fn set_now(
  limiter: glimit.RateLimiter(a, b, id),
  now: Int,
) -> glimit.RateLimiter(a, b, id) {
  glimit.RateLimiter(..limiter, now: fn() { now })
}

// ---------------------------------------------------------------------------
// In-memory store for testing the pluggable store backend
// ---------------------------------------------------------------------------

type StoreMsg {
  StoreLockAndGet(key: String, reply: Subject(Result(bucket.BucketState, Nil)))
  StoreSetAndUnlock(
    key: String,
    state: bucket.BucketState,
    ttl: Int,
    reply: Subject(Nil),
  )
  StoreUnlock(key: String, reply: Subject(Nil))
}

type StoreState {
  StoreState(
    data: dict.Dict(String, bucket.BucketState),
    locks: dict.Dict(String, Bool),
  )
}

fn new_test_store() -> glimit.Store {
  let assert Ok(started) =
    actor.new_with_initialiser(1000, fn(self_subject) {
      Ok(
        actor.initialised(StoreState(data: dict.new(), locks: dict.new()))
        |> actor.returning(self_subject),
      )
    })
    |> actor.on_message(fn(state: StoreState, msg: StoreMsg) {
      case msg {
        StoreLockAndGet(key, reply) -> {
          case dict.get(state.locks, key) {
            Ok(True) -> {
              actor.send(reply, Error(Nil))
              actor.continue(state)
            }
            _ -> {
              let locks = dict.insert(state.locks, key, True)
              case dict.get(state.data, key) {
                Ok(v) -> actor.send(reply, Ok(v))
                Error(_) -> actor.send(reply, Error(Nil))
              }
              actor.continue(StoreState(..state, locks: locks))
            }
          }
        }
        StoreSetAndUnlock(key, bucket_state, _ttl, reply) -> {
          let data = dict.insert(state.data, key, bucket_state)
          let locks = dict.delete(state.locks, key)
          actor.send(reply, Nil)
          actor.continue(StoreState(data: data, locks: locks))
        }
        StoreUnlock(key, reply) -> {
          let locks = dict.delete(state.locks, key)
          actor.send(reply, Nil)
          actor.continue(StoreState(..state, locks: locks))
        }
      }
    })
    |> actor.start

  let store_subject = started.data

  bucket.Store(
    lock_and_get: fn(key) {
      let reply: Subject(Result(bucket.BucketState, Nil)) =
        process.new_subject()
      process.send(store_subject, StoreLockAndGet(key, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(v)) -> Ok(option.Some(v))
        Ok(Error(_)) -> Ok(option.None)
        Error(_) -> Error(Nil)
      }
    },
    set_and_unlock: fn(key, state, ttl) {
      let reply = process.new_subject()
      process.send(store_subject, StoreSetAndUnlock(key, state, ttl, reply))
      case process.receive(reply, 1000) {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error(Nil)
      }
    },
    unlock: fn(key) {
      let reply = process.new_subject()
      process.send(store_subject, StoreUnlock(key, reply))
      case process.receive(reply, 1000) {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error(Nil)
      }
    },
  )
}

pub fn store_basic_rate_limiting_test() {
  let test_store = new_test_store()

  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(_) { "OK" }
    |> glimit.apply(limiter)

  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")
}

pub fn store_different_ids_test() {
  let test_store = new_test_store()

  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(_) { "OK" }
    |> glimit.apply(limiter)

  func("a") |> should.equal("OK")
  func("b") |> should.equal("OK")
  func("b") |> should.equal("OK")
  func("b") |> should.equal("Stop!")
  func("a") |> should.equal("OK")
  func("a") |> should.equal("Stop!")
}

pub fn store_burst_limit_test() {
  let test_store = new_test_store()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(3)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
}

pub fn bucket_to_pairs_from_pairs_roundtrip_test() {
  let assert Ok(state) = bucket.new(10, 5)
  let pairs = bucket.to_pairs(state)
  let assert Ok(restored) = bucket.from_pairs(pairs)
  restored.max_token_count |> should.equal(state.max_token_count)
  restored.token_rate |> should.equal(state.token_rate)
}

pub fn bucket_from_pairs_missing_field_test() {
  let pairs = [#("tc", "5.0"), #("lu", ""), #("mt", "10")]
  // Missing "tr" field
  bucket.from_pairs(pairs) |> should.be_error
}
