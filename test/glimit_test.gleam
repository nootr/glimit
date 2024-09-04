import gleeunit
import gleeunit/should
import glimit

pub fn main() {
  gleeunit.main()
}

pub fn single_argument_function_per_second_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.handler(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
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
    fn(_) { "OK" }
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
    |> glimit.handler(fn(_) { "Stop!" })
    |> glimit.build

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

pub fn two_arguments_function_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.identifier(fn(i: #(String, String)) {
      let #(a, _) = i
      a
    })
    |> glimit.handler(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(x, y) { x <> y }
    |> glimit.apply2(limiter)

  func("O", "K") |> should.equal("OK")
  func(":", ")") |> should.equal(":)")
  func("O", "K") |> should.equal("OK")
  func("O", "K") |> should.equal("Stop!")
}

pub fn three_arguments_function_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.handler(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(x, y, z) { x <> y <> z }
    |> glimit.apply3(limiter)

  func("O", "K", "!") |> should.equal("OK!")
  func("O", "K", "!") |> should.equal("OK!")
  func("O", "K", "!") |> should.equal("Stop!")
}

pub fn four_arguments_function_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.handler(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(x, y, z, p) { x <> y <> z <> p }
    |> glimit.apply4(limiter)

  func("O", "K", "?", "!") |> should.equal("OK?!")
  func("O", "K", "?", "!") |> should.equal("OK?!")
  func("O", "K", "?", "!") |> should.equal("Stop!")
}

pub fn try_build_ok_test() {
  glimit.new()
  |> glimit.per_second(2)
  |> glimit.identifier(fn(x) { x })
  |> glimit.handler(fn(x) { x })
  |> glimit.try_build
  |> should.be_ok()
}

pub fn try_build_identifier_missing_test() {
  glimit.new()
  |> glimit.per_second(2)
  |> glimit.handler(fn(x) { x })
  |> glimit.try_build
  |> should.equal(Error("Identifier function is required"))
}

pub fn try_build_handler_missing_test() {
  glimit.new()
  |> glimit.per_second(2)
  |> glimit.identifier(fn(x) { x })
  |> glimit.try_build
  |> should.equal(Error("Handler function is required"))
}
