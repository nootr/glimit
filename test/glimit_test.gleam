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
import glimit/rate_limiter

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

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 1000)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 3000)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 6000)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 13_000)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")
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

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 1000)
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)
  func("other") |> should.equal("OK")
  func("other") |> should.equal("OK")
  func("other") |> should.equal("OK")
  func("other") |> should.equal("Stop!")
  func("other") |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 1000)
  func("other") |> should.equal("OK")
  func("other") |> should.equal("Stop!")
  func("other") |> should.equal("Stop!")
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

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 1000)
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)
  func("other") |> should.equal("OK")
  func("other") |> should.equal("OK")
  func("other") |> should.equal("Stop!")
  func("other") |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 1000)
  func("other") |> should.equal("OK")
  func("other") |> should.equal("Stop!")
  func("other") |> should.equal("Stop!")
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

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 1000)
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)
  func("other") |> should.equal("OK")
  func("other") |> should.equal("OK")
  func("other") |> should.equal("OK")
  func("other") |> should.equal("Stop!")
  func("other") |> should.equal("Stop!")

  rate_limiter.set_now(limiter.rate_limiter_actor, 1000)
  func("other") |> should.equal("OK")
  func("other") |> should.equal("Stop!")
  func("other") |> should.equal("Stop!")
}

pub fn sweep_preserves_active_limiters_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  let assert option.Some(ms) = limiter.memory_store

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)

  // Hit "user_a" once — active, not full
  func("user_a") |> should.equal("OK")
  func("user_b") |> should.equal("OK")
  func("user_b") |> should.equal("OK")

  let assert Ok(Nil) = memory_store.sweep(ms, 0, option.Some(60_000))

  // Both are active (not full) → both kept
  memory_store.get_count(ms) |> should.equal(2)

  // user_a still has 1 token left
  func("user_a") |> should.equal("OK")
  func("user_a") |> should.equal("Stop!")
}

pub fn integration_many_identifiers_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(3)
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  let assert option.Some(ms) = limiter.memory_store

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)

  let ids = [
    "id_0", "id_1", "id_2", "id_3", "id_4", "id_5", "id_6", "id_7", "id_8",
    "id_9",
  ]

  // Hit each ID i times (id_0: 0 hits, id_1: 1 hit, etc.)
  list.index_map(ids, fn(id, i) {
    list.repeat(Nil, i)
    |> list.each(fn(_) { func(id) |> ignore })
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

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  let assert option.Some(ms) = limiter.memory_store

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)

  // Exhaust "user_a" (all tokens used)
  func("user_a") |> should.equal("OK")
  func("user_a") |> should.equal("OK")
  func("user_a") |> should.equal("Stop!")

  // Hit "user_b" once
  func("user_b") |> should.equal("OK")

  let assert Ok(Nil) = memory_store.sweep(ms, 0, option.Some(60_000))

  // At t=0, user_a has 0 tokens (not full), user_b has 1 token (not full) → both kept
  memory_store.get_count(ms) |> should.equal(2)

  // "user_a" is still rate-limited at t=0
  func("user_a") |> should.equal("Stop!")

  // Advance time so user_a gets tokens back
  rate_limiter.set_now(limiter.rate_limiter_actor, 1000)
  func("user_a") |> should.equal("OK")
  func("user_a") |> should.equal("OK")
  func("user_a") |> should.equal("Stop!")
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

  let reg = limiter.rate_limiter_actor

  // Consume all 10 tokens at t=0
  rate_limiter.set_now(reg, 0)
  list.repeat(Nil, 10)
  |> list.each(fn(_) { rate_limiter.hit(reg, "id") |> ignore })
  rate_limiter.hit(reg, "id") |> should.equal(Error(rate_limiter.RateLimited))

  // 400ms: tc = 0.0 + 2.0 * 400 / 1000 = 0.8 < 1.0 — still rate limited
  rate_limiter.set_now(reg, 400)
  rate_limiter.hit(reg, "id") |> should.equal(Error(rate_limiter.RateLimited))

  // 500ms: tc = 0.8 + 2.0 * 100 / 1000 = 1.0 >= 1.0 — succeeds
  rate_limiter.set_now(reg, 500)
  rate_limiter.hit(reg, "id") |> should.be_ok
  rate_limiter.hit(reg, "id") |> should.equal(Error(rate_limiter.RateLimited))

  // 900ms: tc = 0.0 + 2.0 * 400 / 1000 = 0.8 < 1.0
  rate_limiter.set_now(reg, 900)
  rate_limiter.hit(reg, "id") |> should.equal(Error(rate_limiter.RateLimited))

  // 1000ms: tc = 0.8 + 2.0 * 100 / 1000 = 1.0 >= 1.0
  rate_limiter.set_now(reg, 1000)
  rate_limiter.hit(reg, "id") |> should.be_ok
  rate_limiter.hit(reg, "id") |> should.equal(Error(rate_limiter.RateLimited))

  // 2500ms: tc = 0.0 + 2.0 * 1500 / 1000 = 3.0 — 3 tokens
  rate_limiter.set_now(reg, 2500)
  rate_limiter.hit(reg, "id") |> should.be_ok
  rate_limiter.hit(reg, "id") |> should.be_ok
  rate_limiter.hit(reg, "id") |> should.be_ok
  rate_limiter.hit(reg, "id") |> should.equal(Error(rate_limiter.RateLimited))
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

  let reg = limiter.rate_limiter_actor

  // Drain all 5 tokens at t=0
  rate_limiter.set_now(reg, 0)
  list.repeat(Nil, 5)
  |> list.each(fn(_) { rate_limiter.hit(reg, "id") |> ignore })
  rate_limiter.hit(reg, "id") |> should.equal(Error(rate_limiter.RateLimited))

  // 333ms: tc = 0.0 + 3.0 * 333 / 1000 = 0.999 < 1.0
  rate_limiter.set_now(reg, 333)
  rate_limiter.hit(reg, "id") |> should.equal(Error(rate_limiter.RateLimited))

  // 334ms: tc = 0.999 + 3.0 * 1 / 1000 = 1.002 >= 1.0 — succeeds
  rate_limiter.set_now(reg, 334)
  rate_limiter.hit(reg, "id") |> should.be_ok
  rate_limiter.hit(reg, "id") |> should.equal(Error(rate_limiter.RateLimited))

  // 666ms: tc = 0.002 + 3.0 * 332 / 1000 = 0.998 < 1.0
  rate_limiter.set_now(reg, 666)
  rate_limiter.hit(reg, "id") |> should.equal(Error(rate_limiter.RateLimited))

  // 667ms: tc = 0.998 + 3.0 * 1 / 1000 = 1.001 >= 1.0 — succeeds
  rate_limiter.set_now(reg, 667)
  rate_limiter.hit(reg, "id") |> should.be_ok
  rate_limiter.hit(reg, "id") |> should.equal(Error(rate_limiter.RateLimited))

  // 3000ms: tc = 0.001 + 3.0 * 2333 / 1000 = 7.0, capped at burst limit 5
  rate_limiter.set_now(reg, 3000)
  rate_limiter.hit(reg, "id") |> should.be_ok
  rate_limiter.hit(reg, "id") |> should.be_ok
  rate_limiter.hit(reg, "id") |> should.be_ok
  rate_limiter.hit(reg, "id") |> should.be_ok
  rate_limiter.hit(reg, "id") |> should.be_ok
  rate_limiter.hit(reg, "id") |> should.equal(Error(rate_limiter.RateLimited))
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

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)
  // burst_limit=2: two hits succeed, third is limited
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  // on_limit_exceeded returns "Stop!" (not "wrong")
  func(Nil) |> should.equal("Stop!")

  // Advance 1 second — per_second=1 so only 1 token refilled (not 999)
  rate_limiter.set_now(limiter.rate_limiter_actor, 1000)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
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

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  let assert option.Some(ms) = limiter.memory_store

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)

  // Exhaust all 100 tokens
  list.repeat(Nil, 100)
  |> list.each(fn(_) { func(Nil) |> ignore })

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

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  let assert option.Some(ms) = limiter.memory_store

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)

  // Exhaust all 100 tokens
  list.repeat(Nil, 100)
  |> list.each(fn(_) { func(Nil) |> ignore })

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

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  let assert option.Some(ms) = limiter.memory_store

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)

  list.repeat(Nil, 100)
  |> list.each(fn(_) { func(Nil) |> ignore })

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

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  let assert option.Some(ms) = limiter.memory_store

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)
  list.repeat(Nil, 100)
  |> list.each(fn(_) { func(Nil) |> ignore })

  // At t=61_000: idle 61s, but max_idle is 120s (last set value) — kept
  let assert Ok(Nil) = memory_store.sweep(ms, 61_000, option.Some(120_000))
  memory_store.get_count(ms) |> should.equal(1)

  // At t=121_000: idle 121s > 120s — evicted
  let assert Ok(Nil) = memory_store.sweep(ms, 121_000, option.Some(120_000))
  memory_store.get_count(ms) |> should.equal(0)
}

pub fn dead_rate_limiter_fails_open_test() {
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

  // Kill the rate limiter actor
  let assert Ok(pid) = process.subject_owner(limiter.rate_limiter_actor)
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

fn ignore(_value: a) -> Nil {
  Nil
}

// ---------------------------------------------------------------------------
// In-memory store for testing the pluggable store backend
// ---------------------------------------------------------------------------

type StoreMsg {
  StoreGet(key: String, reply: Subject(Result(bucket.BucketState, Nil)))
  StoreSet(
    key: String,
    state: bucket.BucketState,
    ttl: Int,
    reply: Subject(Nil),
  )
  StoreLock(key: String, reply: Subject(Bool))
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
        StoreGet(key, reply) -> {
          case dict.get(state.data, key) {
            Ok(v) -> actor.send(reply, Ok(v))
            Error(_) -> actor.send(reply, Error(Nil))
          }
          actor.continue(state)
        }
        StoreSet(key, bucket_state, _ttl, reply) -> {
          let data = dict.insert(state.data, key, bucket_state)
          actor.send(reply, Nil)
          actor.continue(StoreState(..state, data: data))
        }
        StoreLock(key, reply) -> {
          case dict.get(state.locks, key) {
            Ok(True) -> {
              actor.send(reply, False)
              actor.continue(state)
            }
            _ -> {
              let locks = dict.insert(state.locks, key, True)
              actor.send(reply, True)
              actor.continue(StoreState(..state, locks: locks))
            }
          }
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
    get: fn(key) {
      let reply: Subject(Result(bucket.BucketState, Nil)) =
        process.new_subject()
      process.send(store_subject, StoreGet(key, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(v)) -> Ok(option.Some(v))
        Ok(Error(_)) -> Ok(option.None)
        Error(_) -> Error(Nil)
      }
    },
    set: fn(key, state, ttl) {
      let reply = process.new_subject()
      process.send(store_subject, StoreSet(key, state, ttl, reply))
      case process.receive(reply, 1000) {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error(Nil)
      }
    },
    lock: fn(key) {
      let reply = process.new_subject()
      process.send(store_subject, StoreLock(key, reply))
      case process.receive(reply, 1000) {
        Ok(True) -> Ok(Nil)
        _ -> Error(Nil)
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

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")

  // After 1 second, 1 token refills
  rate_limiter.set_now(limiter.rate_limiter_actor, 1000)
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
