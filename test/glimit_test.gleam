import gleam/list
import gleam/option.{None}
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

  rate_limiter |> rate_limiter.set_now(1)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(3)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(6)
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")

  rate_limiter |> rate_limiter.set_now(13)
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

  rate_limiter |> rate_limiter.set_now(1)
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

  rate_limiter |> rate_limiter.set_now(1)
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

  rate_limiter |> rate_limiter.set_now(1)
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

  rate_limiter |> rate_limiter.set_now(1)
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

  rate_limiter |> rate_limiter.set_now(1)
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

  rate_limiter |> rate_limiter.set_now(1)
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

  registry.sweep(limiter.rate_limiter_registry, None)

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

  // Get actors before sweep
  let before =
    ids
    |> list.map(fn(id) {
      let assert Ok(rl) =
        limiter.rate_limiter_registry |> registry.get_or_create(id)
      #(id, rl)
    })

  registry.sweep(limiter.rate_limiter_registry, None)

  // Get actors after sweep
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

  registry.sweep(limiter.rate_limiter_registry, None)

  // "user_b" was full → swept → fresh limiter
  func("user_b") |> should.equal("OK")
  func("user_b") |> should.equal("OK")
  func("user_b") |> should.equal("Stop!")

  // "user_a" was not full (0 tokens) → not swept → still rate-limited
  func("user_a") |> should.equal("Stop!")
}

fn ignore(_value: a) -> Nil {
  Nil
}
