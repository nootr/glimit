//// A module containing utility functions.
////

import gleam/erlang/process.{type Subject}
import gleam/result

@external(erlang, "os", "timestamp")
fn now_erlang() -> #(Int, Int, Int)

/// Get the current time in epoch milliseconds.
pub fn now() -> Int {
  let #(megaseconds, seconds, microseconds) = now_erlang()
  megaseconds * 1_000_000_000 + seconds * 1000 + microseconds / 1000
}

/// Wrap a zero-arity function so that a crash returns `Error(Nil)`
/// instead of propagating.
///
@external(erlang, "glimit_ffi", "rescue")
pub fn rescue(f: fn() -> a) -> Result(a, Nil)

/// Like process.call but returns Result instead of panicking on timeout or
/// callee death.
///
pub fn safe_call(
  subject: Subject(message),
  make_request: fn(Subject(reply)) -> message,
  timeout: Int,
) -> Result(reply, Nil) {
  case process.subject_owner(subject) {
    Error(_) -> Error(Nil)
    Ok(callee) -> {
      let reply_subject = process.new_subject()
      let monitor = process.monitor(callee)
      process.send(subject, make_request(reply_subject))

      let result =
        process.new_selector()
        |> process.select_map(reply_subject, fn(reply) { Ok(reply) })
        |> process.select_specific_monitor(monitor, fn(_down) { Error(Nil) })
        |> process.selector_receive(within: timeout)

      process.demonitor_process(monitor)

      result
      |> result.flatten
    }
  }
}
