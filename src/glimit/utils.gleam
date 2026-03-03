//// A module containing utility functions.
////

import gleam/erlang/process.{type Subject}
import gleam/result

@external(erlang, "glimit_ffi", "monotonic_now_ms")
fn monotonic_now_ms() -> Int

/// Get the current monotonic time in milliseconds.
/// Monotonic time is immune to wall-clock adjustments (NTP, manual changes)
/// and is suitable for measuring elapsed intervals.
pub fn now() -> Int {
  monotonic_now_ms()
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
