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
