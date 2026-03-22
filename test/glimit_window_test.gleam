import gleeunit/should
import glimit/window

pub fn single_window_allows_within_limit_test() {
  let limiter = window.new()
  let windows = [window.Window(window_seconds: 60, max_count: 3)]

  window.check(limiter, "user", windows, 100) |> should.be_ok
  window.check(limiter, "user", windows, 100) |> should.be_ok
  window.check(limiter, "user", windows, 100) |> should.be_ok
}

pub fn single_window_denies_over_limit_test() {
  let limiter = window.new()
  let windows = [window.Window(window_seconds: 60, max_count: 2)]

  window.check(limiter, "user", windows, 100) |> should.be_ok
  window.check(limiter, "user", windows, 100) |> should.be_ok
  window.check(limiter, "user", windows, 100)
  |> should.be_error
}

pub fn denied_returns_retry_after_test() {
  let limiter = window.new()
  let windows = [window.Window(window_seconds: 60, max_count: 1)]

  window.check(limiter, "user", windows, 100) |> should.be_ok
  let assert Error(denied) = window.check(limiter, "user", windows, 100)
  // At now=100, window_id = 100/60 = 1, retry_after = 60 - (100 % 60) = 20
  denied.retry_after |> should.equal(20)
}

pub fn different_keys_are_independent_test() {
  let limiter = window.new()
  let windows = [window.Window(window_seconds: 60, max_count: 1)]

  window.check(limiter, "alice", windows, 100) |> should.be_ok
  window.check(limiter, "alice", windows, 100) |> should.be_error
  window.check(limiter, "bob", windows, 100) |> should.be_ok
  window.check(limiter, "bob", windows, 100) |> should.be_error
}

pub fn new_window_resets_count_test() {
  let limiter = window.new()
  let windows = [window.Window(window_seconds: 60, max_count: 2)]

  // Fill up in window 1 (now=60..119)
  window.check(limiter, "user", windows, 60) |> should.be_ok
  window.check(limiter, "user", windows, 60) |> should.be_ok
  window.check(limiter, "user", windows, 60) |> should.be_error

  // Move to window 2 (now=120..179)
  window.check(limiter, "user", windows, 120) |> should.be_ok
  window.check(limiter, "user", windows, 120) |> should.be_ok
  window.check(limiter, "user", windows, 120) |> should.be_error
}

pub fn layered_windows_test() {
  let limiter = window.new()
  let windows = [
    window.Window(window_seconds: 60, max_count: 1),
    window.Window(window_seconds: 900, max_count: 3),
  ]

  // First request: allowed by both windows
  window.check(limiter, "user", windows, 0) |> should.be_ok

  // Second request same minute: denied by per-minute window
  window.check(limiter, "user", windows, 0) |> should.be_error

  // Move to next minute: per-minute allows, per-15-min still has room
  window.check(limiter, "user", windows, 60) |> should.be_ok

  // Next minute again
  window.check(limiter, "user", windows, 120) |> should.be_ok

  // Now at 3/3 for per-15-min window — denied even though per-minute has room
  window.check(limiter, "user", windows, 180) |> should.be_error
}

pub fn reset_clears_all_windows_test() {
  let limiter = window.new()
  let windows = [
    window.Window(window_seconds: 60, max_count: 1),
    window.Window(window_seconds: 900, max_count: 2),
  ]

  window.check(limiter, "user", windows, 0) |> should.be_ok
  window.check(limiter, "user", windows, 60) |> should.be_ok

  // Now 2/2 for per-15-min — denied
  window.check(limiter, "user", windows, 120) |> should.be_error

  // Reset clears everything
  window.reset(limiter, "user")

  // Can make requests again
  window.check(limiter, "user", windows, 120) |> should.be_ok
}

pub fn cleanup_removes_expired_entries_test() {
  let limiter = window.new()
  let windows = [window.Window(window_seconds: 60, max_count: 2)]

  window.check(limiter, "user", windows, 0) |> should.be_ok
  window.get_count(limiter) |> should.equal(1)

  // Cleanup at now=120: window 0 (covers 0..59) expired
  window.cleanup(limiter, 120)
  window.get_count(limiter) |> should.equal(0)
}

pub fn cleanup_keeps_current_entries_test() {
  let limiter = window.new()
  let windows = [window.Window(window_seconds: 60, max_count: 2)]

  window.check(limiter, "user", windows, 100) |> should.be_ok
  window.get_count(limiter) |> should.equal(1)

  // Cleanup at now=100: window 1 (covers 60..119) still active
  window.cleanup(limiter, 100)
  window.get_count(limiter) |> should.equal(1)
}

pub fn get_count_test() {
  let limiter = window.new()
  let windows = [window.Window(window_seconds: 60, max_count: 5)]

  window.get_count(limiter) |> should.equal(0)

  window.check(limiter, "alice", windows, 0) |> should.be_ok
  window.get_count(limiter) |> should.equal(1)

  // Same key same window — still 1 entry
  window.check(limiter, "alice", windows, 0) |> should.be_ok
  window.get_count(limiter) |> should.equal(1)

  // Different key — 2 entries
  window.check(limiter, "bob", windows, 0) |> should.be_ok
  window.get_count(limiter) |> should.equal(2)
}

pub fn denied_request_does_not_increment_earlier_windows_test() {
  let limiter = window.new()
  let windows = [
    window.Window(window_seconds: 60, max_count: 1),
    window.Window(window_seconds: 900, max_count: 3),
  ]

  // Use up all 3 requests in the 15-min window across different minutes
  window.check(limiter, "user", windows, 0) |> should.be_ok
  window.check(limiter, "user", windows, 60) |> should.be_ok
  window.check(limiter, "user", windows, 120) |> should.be_ok

  // This should be denied by the 15-min window.
  // The per-minute window (at now=180) has not been used yet.
  window.check(limiter, "user", windows, 180) |> should.be_error

  // After the 15-min window resets (at 900), the per-minute window at
  // now=180 should still be clean (no phantom count from the denied request).
  // We verify by checking with only the per-minute window.
  let minute_only = [window.Window(window_seconds: 60, max_count: 1)]
  window.check(limiter, "user", minute_only, 180) |> should.be_ok
}

pub fn empty_windows_always_allows_test() {
  let limiter = window.new()
  window.check(limiter, "user", [], 100) |> should.be_ok
}
