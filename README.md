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
* ⚡ ETS-backed by default for low-latency, lock-free rate limiting.
* 🔌 Pluggable store backend for distributed rate limiting (e.g. Redis, Postgres).


## Usage

A very minimalistic example of how to use `glimit` would be the following snippet:

```gleam
import glimit

let limiter =
  glimit.new()
  |> glimit.per_second(2)
  |> glimit.identifier(fn(x) { x })
  |> glimit.on_limit_exceeded(fn(_req) { "Too many requests" })

let handler =
  fn(_req) { "Hello, world!" }
  |> glimit.apply(limiter)

handler("🚀") // "Hello, world!"
handler("💫") // "Hello, world!"
handler("💫") // "Hello, world!"
handler("💫") // "Too many requests"
handler("🚀") // "Hello, world!"
handler("🚀") // "Too many requests"
```

You can also use `glimit.build` and `glimit.hit` for direct rate limit checks
without wrapping a function:

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
  Error(glimit.RateLimited) -> // rejected
  Error(_) -> // store unavailable, fails open
}
```

More practical examples can be found in the `examples/` directory, such as Wisp or Mist servers, or a Redis backend.


## Pluggable Store Backend

By default, rate limit state is stored in ETS (Erlang Term Storage) using lock-free atomic operations. For distributed rate limiting across multiple nodes, you can provide a custom `Store` that persists bucket state in an external service like Redis or Postgres.

All token bucket logic stays in glimit — adapters only implement `lock_and_get` / `set_and_unlock` / `unlock` operations. The `glimit/bucket` module provides `to_pairs`/`from_pairs` helpers for serialization.

See [`examples/redis/`](https://github.com/nootr/glimit/tree/main/examples/redis) for a complete Redis adapter using [valkyrie](https://hexdocs.pm/valkyrie/).


## Fixed-Window Counters

For scenarios where you need discrete attempt counting with clear reset boundaries (e.g. login attempts, verification codes), use the `glimit/window` module:

```gleam
import glimit/window

let limiter = window.new()

// Define layered windows — all must pass for a request to be allowed
let windows = [
  window.Window(window_seconds: 60, max_count: 1),     // 1 per minute
  window.Window(window_seconds: 900, max_count: 3),    // 3 per 15 minutes
  window.Window(window_seconds: 3600, max_count: 10),  // 10 per hour
  window.Window(window_seconds: 86_400, max_count: 20), // 20 per day
]

case window.check(limiter, email, windows, now_seconds) {
  Ok(Nil) -> // allowed
  Error(window.Denied(retry_after)) -> // denied, retry after N seconds
}
```

Unlike the token bucket algorithm (which smoothly refills tokens), fixed-window counters divide time into discrete windows and count requests within each. This is useful for:

- Login/verification attempt limiting
- API rate limiting with clear reset boundaries
- Layered limits (e.g. per-minute + per-hour + per-day)

Uses ETS with atomic `update_counter` for lock-free, concurrent operation. Call `window.cleanup(limiter, now)` periodically to remove expired entries.


## Performance

Every hit goes through the pluggable `Store` interface (`lock_and_get` / `set_and_unlock`).

* **Default (ETS)**: Direct atomic table operations per hit. No actor overhead. Lock-free and concurrent.
* **Fail-open**: If the store is unavailable or a lock cannot be acquired, the request is allowed through rather than rejected.
* **Sweep**: Full and idle buckets are automatically swept every 10 seconds.


## Documentation

Further documentation can be found at <https://hexdocs.pm/glimit/glimit.html>.


## Contributing

Contributions like PR's, bug reports or suggestions are more than welcome! ♥️
