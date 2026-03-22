# glimit

[![Package Version](https://img.shields.io/hexpm/v/glimit)](https://hex.pm/packages/glimit)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glimit/glimit.html)
[![test](https://github.com/nootr/glimit/actions/workflows/test.yml/badge.svg)](https://github.com/nootr/glimit/actions/workflows/test.yml)

A simple, framework-agnostic rate limiter for Gleam with pluggable storage. 💫


## Features

* ✨ Simple and easy to use.
* 📏 Rate limits based on any key (e.g. IP address, or user ID).
* 🪣 Token Bucket algorithm for smooth rate limiting.
* 🪟 Fixed-window counters with layered windows for attempt-based limiting.
* ⚡ ETS-backed by default for low-latency rate limiting; no separate back-end service needed.
* 🔌 Pluggable store backend for distributed rate limiting (e.g. Redis, Postgres).


## Rate Limiting Strategies

glimit supports two rate limiting strategies, both using the same builder pattern:

### Token Bucket (smooth rate limiting)

Use `glimit.new()` for smooth, token-based rate limiting. Tokens refill at a steady rate, allowing bursts up to the bucket size.

```gleam
import glimit

let limiter =
  glimit.new()
  |> glimit.per_second(2)
  |> glimit.burst_limit(10)
  |> glimit.identifier(fn(x) { x })
  |> glimit.on_limit_exceeded(fn(_req) { "Too many requests" })

let handler =
  fn(_req) { "Hello, world!" }
  |> glimit.apply(limiter)

handler("user_a") // "Hello, world!"
handler("user_a") // "Hello, world!"
handler("user_a") // "Too many requests"
```

### Fixed-Window Counters (attempt-based limiting)

Use `glimit.new_window()` for discrete attempt counting with clear reset boundaries. Multiple windows can be layered so that all must pass for a request to be allowed.

```gleam
import glimit

let limiter =
  glimit.new_window()
  |> glimit.window(seconds: 60, max: 1)
  |> glimit.window(seconds: 900, max: 3)
  |> glimit.window(seconds: 3600, max: 10)
  |> glimit.identifier(fn(req) { req.email })
  |> glimit.on_limit_exceeded(fn(_) { "Too many attempts" })

let handler =
  fn(_req) { "Code sent!" }
  |> glimit.apply(limiter)
```

This is useful for:

- Login/verification attempt limiting
- API rate limiting with clear reset boundaries
- Layered limits (e.g. per-minute + per-hour + per-day)

### Compile-time Safety

The builder uses phantom types to prevent invalid combinations. Calling `per_second` on a window builder or `window` on a token bucket builder is a compile error.


## Direct Checks

Both strategies support `glimit.build` and `glimit.hit` for direct rate limit checks without wrapping a function:

```gleam
import glimit

let assert Ok(limiter) =
  glimit.new()
  |> glimit.per_second(10)
  |> glimit.identifier(fn(x) { x })
  |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
  |> glimit.build

case glimit.hit(limiter, "user_123") {
  Ok(Nil) -> // allowed
  Error(glimit.RateLimited(retry_after)) -> // rejected, retry after N seconds
  Error(_) -> // store unavailable, fails open
}
```

Both strategies return `RateLimited(retry_after: Int)` with the number of seconds until the limit resets.

More practical examples can be found in the `examples/` directory, such as Wisp or Mist servers, or a Redis backend.


## Pluggable Store Backend

By default, rate limit state is stored in ETS (Erlang Term Storage). For distributed rate limiting across multiple nodes, you can provide a custom `Store` that persists bucket state in an external service like Redis or Postgres.

Pluggable stores are only available for token bucket rate limiters. Fixed-window counters use ETS directly for atomic counter operations.

All token bucket logic stays in glimit. Adapters only implement `lock_and_get` / `set_and_unlock` / `unlock` operations. The `glimit/bucket` module provides `to_pairs`/`from_pairs` helpers for serialization.

See [`examples/redis/`](https://github.com/nootr/glimit/tree/main/examples/redis) for a complete Redis adapter using [valkyrie](https://hexdocs.pm/valkyrie/).


## Standalone Window API

The `glimit/window` module also provides a standalone API for cases where you need direct control over keys and timestamps:

```gleam
import glimit/window

let limiter = window.new()

let windows = [
  window.Window(window_seconds: 60, max_count: 1),
  window.Window(window_seconds: 900, max_count: 3),
]

case window.check(limiter, email, windows, now_seconds) {
  Ok(Nil) -> // allowed
  Error(window.Denied(retry_after)) -> // denied, retry after N seconds
}
```


## Performance

* **Default (ETS)**: Direct table operations per hit. No actor overhead.
* **Fail-open**: If the store is unavailable or a lock cannot be acquired, the request is allowed through rather than rejected.
* **Sweep**: Full and idle token buckets are automatically swept every 10 seconds.


## Documentation

Further documentation can be found at <https://hexdocs.pm/glimit/glimit.html>.


## Contributing

Contributions like PR's, bug reports or suggestions are more than welcome! ♥️
