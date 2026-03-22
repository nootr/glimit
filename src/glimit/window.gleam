//// Fixed-window counter rate limiting with layered windows.
////
//// Unlike the token bucket algorithm (which smoothly refills tokens over time),
//// fixed-window counters divide time into discrete windows and count requests
//// within each window. This is ideal for scenarios like:
////
//// - Login/verification attempt limiting (e.g. 5 attempts per 15 minutes)
//// - API rate limiting with clear reset boundaries
//// - Layered limits (e.g. 1/min + 3/15min + 10/hour + 20/day)
////
//// Uses ETS with atomic `update_counter` for lock-free, concurrent operation.
//// Individual window checks are atomic, but layered window checks (multiple
//// windows) are not fully atomic across windows. Under very high concurrency
//// on the same key, a request may occasionally be over- or under-counted by
//// one. For login/verification limiting this is negligible.
////

/// Opaque handle to a window-based rate limiter backed by ETS.
///
pub opaque type WindowLimiter {
  WindowLimiter(table: WindowTable)
}

type WindowTable

/// A rate limit window configuration.
///
/// Each window defines a time period and the maximum number of requests
/// allowed within that period.
///
pub type Window {
  Window(
    /// Duration of the window in seconds.
    window_seconds: Int,
    /// Maximum number of requests allowed in the window.
    max_count: Int,
  )
}

/// Result of a rate limit check that was denied.
///
pub type Denied {
  /// The request was denied. `retry_after` is the number of seconds
  /// until the current window resets.
  Denied(retry_after: Int)
}

/// Create a new window-based rate limiter.
///
pub fn new() -> WindowLimiter {
  WindowLimiter(table: window_new())
}

/// Check if a request is allowed under all configured windows.
///
/// Returns `Ok(Nil)` if the request is allowed under all windows,
/// or `Error(Denied(retry_after))` if any window's limit is exceeded.
/// The `retry_after` value is the number of seconds until the most
/// restrictive window resets.
///
/// Each window is checked independently — a request that exceeds a
/// per-minute limit will be denied even if the per-hour limit has room.
///
/// # Example
///
/// ```gleam
/// let limiter = window.new()
/// let windows = [
///   window.Window(window_seconds: 60, max_count: 5),
///   window.Window(window_seconds: 900, max_count: 15),
/// ]
///
/// case window.check(limiter, "user@example.com", windows, now_seconds) {
///   Ok(Nil) -> // allowed
///   Error(window.Denied(retry_after)) -> // denied, retry after N seconds
/// }
/// ```
///
pub fn check(
  limiter: WindowLimiter,
  key: String,
  windows: List(Window),
  now: Int,
) -> Result(Nil, Denied) {
  check_windows(limiter, key, windows, now, [])
}

/// Remove all entries for a given key across all window sizes.
///
/// This is useful when you want to reset rate limits for a specific
/// identifier (e.g. after successful authentication).
///
pub fn reset(limiter: WindowLimiter, key: String) -> Nil {
  window_reset(limiter.table, key)
}

/// Remove expired window entries from the table.
///
/// Call this periodically (e.g. every 60 seconds) to prevent unbounded
/// memory growth. Entries whose window has fully elapsed are removed.
///
pub fn cleanup(limiter: WindowLimiter, now: Int) -> Nil {
  window_cleanup(limiter.table, now)
}

/// Return the number of entries in the table.
///
pub fn get_count(limiter: WindowLimiter) -> Int {
  window_size(limiter.table)
}

fn check_windows(
  limiter: WindowLimiter,
  key: String,
  windows: List(Window),
  now: Int,
  incremented: List(Window),
) -> Result(Nil, Denied) {
  case windows {
    [] -> Ok(Nil)
    [window, ..rest] -> {
      case
        window_check(
          limiter.table,
          key,
          window.max_count,
          window.window_seconds,
          now,
        )
      {
        Ok(_count) ->
          check_windows(limiter, key, rest, now, [window, ..incremented])
        Error(retry_after) -> {
          rollback(limiter, key, incremented, now)
          Error(Denied(retry_after: retry_after))
        }
      }
    }
  }
}

fn rollback(
  limiter: WindowLimiter,
  key: String,
  incremented: List(Window),
  now: Int,
) -> Nil {
  case incremented {
    [] -> Nil
    [window, ..rest] -> {
      window_decrement(limiter.table, key, window.window_seconds, now)
      rollback(limiter, key, rest, now)
    }
  }
}

// --- Erlang FFI ---

@external(erlang, "window_ffi", "new")
fn window_new() -> WindowTable

@external(erlang, "window_ffi", "check")
fn window_check(
  table: WindowTable,
  key: String,
  max_count: Int,
  window_seconds: Int,
  now: Int,
) -> Result(Int, Int)

@external(erlang, "window_ffi", "decrement")
fn window_decrement(
  table: WindowTable,
  key: String,
  window_seconds: Int,
  now: Int,
) -> Nil

@external(erlang, "window_ffi", "reset")
fn window_reset(table: WindowTable, key: String) -> Nil

@external(erlang, "window_ffi", "cleanup")
fn window_cleanup(table: WindowTable, now: Int) -> Nil

@external(erlang, "window_ffi", "size")
fn window_size(table: WindowTable) -> Int
