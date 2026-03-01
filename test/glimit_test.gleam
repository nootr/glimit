import gleam/erlang/process
import gleam/list
import gleeunit
import gleeunit/should
import glimit
import glimit/rate_limiter
import glimit/registry

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

  func("🚀") |> should.equal("OK")
  func("💫") |> should.equal("OK")
  func("💫") |> should.equal("OK")
  func("💫") |> should.equal("Stop!")
  func("🚀") |> should.equal("OK")
  func("🚀") |> should.equal("Stop!")
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

  let assert Ok(rate_limiter) =
    limiter.rate_limiter_registry
    |> registry.get_or_create("id")

  rate_limiter |> rate_limiter.set_now(0)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(1000)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(3000)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(6000)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(13_000)
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

  let assert Ok(rate_limiter) =
    limiter.rate_limiter_registry
    |> registry.get_or_create("id")

  rate_limiter |> rate_limiter.set_now(0)
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(1000)
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  let assert Ok(rate_limiter) =
    limiter.rate_limiter_registry
    |> registry.get_or_create("other")

  rate_limiter |> rate_limiter.set_now(0)
  func("other") |> should.equal("OK")
  func("other") |> should.equal("OK")
  func("other") |> should.equal("OK")
  func("other") |> should.equal("Stop!")
  func("other") |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(1000)
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

  let assert Ok(rate_limiter) =
    limiter.rate_limiter_registry
    |> registry.get_or_create("id")

  rate_limiter |> rate_limiter.set_now(0)
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(1000)
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  let assert Ok(rate_limiter) =
    limiter.rate_limiter_registry
    |> registry.get_or_create("other")

  rate_limiter |> rate_limiter.set_now(0)
  func("other") |> should.equal("OK")
  func("other") |> should.equal("OK")
  func("other") |> should.equal("Stop!")
  func("other") |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(1000)
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

  let assert Ok(rate_limiter) =
    limiter.rate_limiter_registry
    |> registry.get_or_create("id")

  rate_limiter |> rate_limiter.set_now(0)
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(1000)
  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  let assert Ok(rate_limiter) =
    limiter.rate_limiter_registry
    |> registry.get_or_create("other")

  rate_limiter |> rate_limiter.set_now(0)
  func("other") |> should.equal("OK")
  func("other") |> should.equal("OK")
  func("other") |> should.equal("OK")
  func("other") |> should.equal("Stop!")
  func("other") |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(1000)
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

  // Hit "user_a" once — active, not full
  func("user_a") |> should.equal("OK")
  // Don't touch "user_b" — stays full (idle)

  // Force-create "user_b" so it exists in the registry
  let assert Ok(_) =
    limiter.rate_limiter_registry |> registry.get_or_create("user_b")

  registry.sweep(limiter.rate_limiter_registry)

  // "user_a" was active → kept, still has 1 token left
  func("user_a") |> should.equal("OK")
  func("user_a") |> should.equal("Stop!")

  // "user_b" was full → swept → fresh limiter with 2 tokens
  func("user_b") |> should.equal("OK")
  func("user_b") |> should.equal("OK")
  func("user_b") |> should.equal("Stop!")
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

  // Create 10 IDs with varying hit counts
  let ids = [
    "id_0", "id_1", "id_2", "id_3", "id_4", "id_5", "id_6", "id_7", "id_8",
    "id_9",
  ]

  // Hit each ID i times (id_0: 0 hits, id_1: 1 hit, etc.)
  list.index_map(ids, fn(id, i) {
    list.repeat(Nil, i)
    |> list.each(fn(_) { func(id) |> ignore })
  })

  let before =
    ids
    |> list.map(fn(id) {
      let assert Ok(rl) =
        limiter.rate_limiter_registry |> registry.get_or_create(id)
      #(id, rl)
    })

  registry.sweep(limiter.rate_limiter_registry)

  let after =
    ids
    |> list.map(fn(id) {
      let assert Ok(rl) =
        limiter.rate_limiter_registry |> registry.get_or_create(id)
      #(id, rl)
    })

  // "Full bucket" means all tokens present (idle), not "fully consumed".
  // id_0 had 0 hits → full bucket (idle) → swept (new actor)
  let assert Ok(#(_, before_0)) = list.first(before)
  let assert Ok(#(_, after_0)) = list.first(after)
  before_0 |> should.not_equal(after_0)

  // id_1 through id_9 had hits → kept (same actor)
  list.zip(list.drop(before, 1), list.drop(after, 1))
  |> list.each(fn(pair) {
    let #(#(_, b), #(_, a)) = pair
    b |> should.equal(a)
  })
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

  // Exhaust "user_a" (all tokens used)
  func("user_a") |> should.equal("OK")
  func("user_a") |> should.equal("OK")
  func("user_a") |> should.equal("Stop!")

  // Leave "user_b" idle (full bucket)
  let assert Ok(_) =
    limiter.rate_limiter_registry |> registry.get_or_create("user_b")

  registry.sweep(limiter.rate_limiter_registry)

  // "user_b" was full → swept → fresh limiter
  func("user_b") |> should.equal("OK")
  func("user_b") |> should.equal("OK")
  func("user_b") |> should.equal("Stop!")

  // "user_a" was not full (0 tokens) → not swept → still rate-limited
  func("user_a") |> should.equal("Stop!")
}

pub fn dead_rate_limiter_does_not_crash_caller_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  func("user") |> should.equal("OK")

  let assert Ok(rl) =
    limiter.rate_limiter_registry |> registry.get_or_create("user")
  let assert Ok(pid) = process.subject_owner(rl)
  let monitor = process.monitor(pid)
  rate_limiter.shutdown(rl)
  let _ =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 1000)

  // Should not panic — get_or_create replaces dead subject
  func("user") |> should.equal("OK")
}

pub fn sub_second_remainder_preservation_test() {
  // 2 tokens/sec, burst 10 — one token every 500ms
  let assert Ok(rl) = rate_limiter.new(10, 2)

  // Consume all 10 tokens at t=0
  rl |> rate_limiter.set_now(0)
  list.repeat(Nil, 10) |> list.each(fn(_) { rl |> rate_limiter.hit |> ignore })
  rl |> rate_limiter.hit |> should.be_error

  // 400ms: 2 * 400 / 1000 = 0 tokens — still rate limited
  rl |> rate_limiter.set_now(400)
  rl |> rate_limiter.hit |> should.be_error

  // 500ms: 2 * 500 / 1000 = 1 token — should succeed
  rl |> rate_limiter.set_now(500)
  rl |> rate_limiter.hit |> should.equal(Ok(Nil))
  rl |> rate_limiter.hit |> should.be_error

  // 900ms: only 400ms since last token at 500ms — 0 tokens
  rl |> rate_limiter.set_now(900)
  rl |> rate_limiter.hit |> should.be_error

  // 1000ms: 500ms since last token — 1 more token
  rl |> rate_limiter.set_now(1000)
  rl |> rate_limiter.hit |> should.equal(Ok(Nil))
  rl |> rate_limiter.hit |> should.be_error

  // 2500ms: 1500ms since last token at 1000ms — 3 tokens
  rl |> rate_limiter.set_now(2500)
  rl |> rate_limiter.hit |> should.equal(Ok(Nil))
  rl |> rate_limiter.hit |> should.equal(Ok(Nil))
  rl |> rate_limiter.hit |> should.equal(Ok(Nil))
  rl |> rate_limiter.hit |> should.be_error
}

pub fn sub_second_remainder_non_divisible_rate_test() {
  // 3 tokens/sec, burst 5 — one token every ~333ms
  // Exercises double integer division rounding: tokens_to_add * 1000 / 3
  // produces a 1ms gap per token (333ms vs 333.3ms), which must not
  // accumulate into lost tokens over many refill cycles.
  let assert Ok(rl) = rate_limiter.new(5, 3)

  // Drain all 5 tokens at t=0
  rl |> rate_limiter.set_now(0)
  list.repeat(Nil, 5) |> list.each(fn(_) { rl |> rate_limiter.hit |> ignore })
  rl |> rate_limiter.hit |> should.be_error

  // 333ms: 3 * 333 / 1000 = 0 tokens (999 / 1000 = 0)
  rl |> rate_limiter.set_now(333)
  rl |> rate_limiter.hit |> should.be_error

  // 334ms: 3 * 334 / 1000 = 1 token (1002 / 1000 = 1)
  // last_update advances by 1 * 1000 / 3 = 333ms → last_update = 333
  rl |> rate_limiter.set_now(334)
  rl |> rate_limiter.hit |> should.equal(Ok(Nil))
  rl |> rate_limiter.hit |> should.be_error

  // 666ms: time_diff = 666 - 333 = 333ms, 3 * 333 / 1000 = 0
  rl |> rate_limiter.set_now(666)
  rl |> rate_limiter.hit |> should.be_error

  // 667ms: time_diff = 667 - 333 = 334ms, 3 * 334 / 1000 = 1
  // last_update = 333 + 333 = 666
  rl |> rate_limiter.set_now(667)
  rl |> rate_limiter.hit |> should.equal(Ok(Nil))
  rl |> rate_limiter.hit |> should.be_error

  // 3000ms: time_diff = 3000 - 666 = 2334ms, 3 * 2334 / 1000 = 7
  // Capped at burst limit 5
  rl |> rate_limiter.set_now(3000)
  rl |> rate_limiter.hit |> should.equal(Ok(Nil))
  rl |> rate_limiter.hit |> should.equal(Ok(Nil))
  rl |> rate_limiter.hit |> should.equal(Ok(Nil))
  rl |> rate_limiter.hit |> should.equal(Ok(Nil))
  rl |> rate_limiter.hit |> should.equal(Ok(Nil))
  rl |> rate_limiter.hit |> should.be_error
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

  let assert Ok(rl) =
    limiter.rate_limiter_registry
    |> registry.get_or_create("id")

  rl |> rate_limiter.set_now(0)
  // burst_limit=2: two hits succeed, third is limited
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  // on_limit_exceeded returns "Stop!" (not "wrong")
  func(Nil) |> should.equal("Stop!")

  // Advance 1 second — per_second=1 so only 1 token refilled (not 999)
  rl |> rate_limiter.set_now(1000)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
}

fn ignore(_value: a) -> Nil {
  Nil
}
