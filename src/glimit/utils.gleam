//// A module containing utility functions.
////

@external(erlang, "os", "timestamp")
fn now_erlang() -> #(Int, Int, Int)

/// Get the current time in epoch seconds.
pub fn now() -> Int {
  let #(megaseconds, seconds, _) = now_erlang()
  megaseconds * 1_000_000 + seconds
}
