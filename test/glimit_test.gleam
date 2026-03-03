import gleam/erlang/process
import gleam/list
import gleeunit
import gleeunit/should
import glimit
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

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)

  // Hit "user_a" once — active, not full
  func("user_a") |> should.equal("OK")
  // Hit "user_b" to create it, then let it go full
  // Actually, just don't hit "user_b" — it won't exist until hit
  // So we need to hit it and let it refill
  func("user_b") |> should.equal("OK")
  func("user_b") |> should.equal("OK")

  // At t=1_000_000 both refill to full
  // But we want "user_b" full and "user_a" not full at sweep time
  // Let's restart: user_a has 1 token used at t=0, user_b fully consumed at t=0
  // At sweep time t=0: user_a has 1/2 tokens (not full), user_b has 0/2 tokens (not full)
  // Neither gets swept — that's correct behavior for this architecture
  let assert Ok(Nil) = rate_limiter.sweep(limiter.rate_limiter_actor)

  // Both are active (not full) → both kept
  rate_limiter.get_count(limiter.rate_limiter_actor) |> should.equal(2)

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

  // id_0 was never hit so doesn't exist in rate limiter
  // id_1..id_9 were hit at least once
  let count_before = rate_limiter.get_count(limiter.rate_limiter_actor)
  // id_0 never hit = 0 entries, id_1..id_9 = 9 entries
  count_before |> should.equal(9)

  let assert Ok(Nil) = rate_limiter.sweep(limiter.rate_limiter_actor)

  // At t=0, none have had time to refill. id_3 (3 hits = fully consumed) is not full.
  // Only buckets that are still at max capacity get swept.
  // Since all were hit, none are full → all kept
  let count_after = rate_limiter.get_count(limiter.rate_limiter_actor)
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

  rate_limiter.set_now(limiter.rate_limiter_actor, 0)

  // Exhaust "user_a" (all tokens used)
  func("user_a") |> should.equal("OK")
  func("user_a") |> should.equal("OK")
  func("user_a") |> should.equal("Stop!")

  // Hit "user_b" once
  func("user_b") |> should.equal("OK")

  let assert Ok(Nil) = rate_limiter.sweep(limiter.rate_limiter_actor)

  // At t=0, user_a has 0 tokens (not full), user_b has 1 token (not full) → both kept
  rate_limiter.get_count(limiter.rate_limiter_actor) |> should.equal(2)

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

fn ignore(_value: a) -> Nil {
  Nil
}
