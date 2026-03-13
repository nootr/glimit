# glimit

[![Package Version](https://img.shields.io/hexpm/v/glimit)](https://hex.pm/packages/glimit)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glimit/glimit.html)
[![test](https://github.com/nootr/glimit/actions/workflows/test.yml/badge.svg)](https://github.com/nootr/glimit/actions/workflows/test.yml)

A simple, framework-agnostic rate limiter for Gleam with pluggable storage. 💫


## Features

* ✨ Simple and easy to use.
* 📏 Rate limits based on any key (e.g. IP address, or user ID).
* 🪣 Uses a Token Bucket algorithm to rate limit requests.
* 🗄️ Works out of the box with in-memory storage; no back-end service needed.
* ⚡ Optional ETS backend for lower-latency, lock-free rate limiting.
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

By default, rate limit state is stored in-memory using an OTP actor. For distributed rate limiting across multiple nodes, you can provide a custom `Store` that persists bucket state in an external service like Redis or Postgres.

All token bucket logic stays in glimit — adapters only implement `lock_and_get` / `set_and_unlock` / `unlock` operations. The `glimit/bucket` module provides `to_pairs`/`from_pairs` helpers for serialization.

See [`examples/redis/`](https://github.com/nootr/glimit/tree/main/examples/redis) for a complete Redis adapter using [valkyrie](https://hexdocs.pm/valkyrie/).


## In-memory Mode

When no store is configured, the rate limiter uses the default in-memory backend backed by an OTP actor. This is simple and fast, but each hit serializes through two actor messages (`lock_and_get` + `set_and_unlock`).


## ETS Mode

For lower-latency rate limiting on a single node, use the built-in ETS backend:

```gleam
import glimit

let limiter =
  glimit.new()
  |> glimit.per_second(10)
  |> glimit.ets_store()
  |> glimit.identifier(fn(request) { request.ip })
  |> glimit.on_limit_exceeded(fn(_request) { "Rate limit reached" })
```

ETS operations are lock-free and concurrent — no actor messages are needed. Full and idle buckets are automatically swept every 10 seconds. This is the recommended backend for single-node deployments where low latency matters.

Both in-memory and ETS modes are scoped to the BEAM VM they run in. For distributed rate limiting across multiple nodes, use a custom `Store` (e.g. Redis).


## Performance

Every hit goes through the pluggable `Store` interface (`lock_and_get` / `set_and_unlock`).

* **In-memory mode**: Two OTP actor messages per hit. One dict entry per unique identifier.
* **ETS mode**: Direct atomic table operations per hit. No actor overhead.
* **Fail-open**: If the store is unavailable or a lock cannot be acquired, the request is allowed through rather than rejected.
* **Sweep**: Full and idle buckets are automatically swept every 10 seconds in both in-memory and ETS modes.


## Documentation

Further documentation can be found at <https://hexdocs.pm/glimit/glimit.html>.


## Contributing

Contributions like PR's, bug reports or suggestions are more than welcome! ♥️
