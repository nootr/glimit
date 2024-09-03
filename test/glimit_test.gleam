import gleeunit
import gleeunit/should
import glimit

pub fn main() {
  gleeunit.main()
}

pub fn single_argument_function_different_ids_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.handler(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_x) { "OK" }
    |> glimit.apply(limiter)

  func("a") |> should.equal("OK")
  func("b") |> should.equal("OK")
  func("b") |> should.equal("OK")
  func("b") |> should.equal("Stop!")
  func("a") |> should.equal("OK")
  func("a") |> should.equal("Stop!")
}

pub fn single_argument_function_per_second_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.handler(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_x) { "OK" }
    |> glimit.apply(limiter)

  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")
}

pub fn single_argument_function_per_minute_test() {
  let limiter =
    glimit.new()
    |> glimit.per_minute(2)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.handler(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_x) { "OK" }
    |> glimit.apply(limiter)

  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")
}

pub fn single_argument_function_per_hour_test() {
  let limiter =
    glimit.new()
    |> glimit.per_hour(2)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.handler(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_x) { "OK" }
    |> glimit.apply(limiter)

  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")
}
