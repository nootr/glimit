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
* 🔌 Pluggable store backend for distributed rate limiting (e.g. Redis, Postgres).


## Usage

A very minimalistic example of how to use `glimit` would be the following snippet:

```gleam
import glimit

let limiter =
  glimit.new()
  |> glimit.per_second(2)
  |> glimit.identifier(fn(x) { x })
  |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

let func =
  fn(_) { "OK" }
  |> glimit.apply(limiter)

func("🚀") // "OK"
func("💫") // "OK"
func("💫") // "OK"
func("💫") // "Stop!"
func("🚀") // "OK"
func("🚀") // "Stop!"
```

More practical examples can be found in the `examples/` directory, such as Wisp or Mist servers, or a Redis backend.


## Pluggable Store Backend

By default, rate limit state is stored in-memory using an OTP actor. For distributed rate limiting across multiple nodes, you can provide a custom `Store` that persists bucket state in an external service like Redis or Postgres.

All token bucket logic stays in glimit — adapters only implement simple get/set/lock/unlock operations. The `glimit/bucket` module provides `to_pairs`/`from_pairs` helpers for serialization.

See `examples/redis/` for a complete Redis adapter using [valkyrie](https://hexdocs.pm/valkyrie/).


## In-memory Mode

When no store is configured, the rate limiter uses the default in-memory backend. This is simple and fast, but scoped to the BEAM VM cluster it runs in. If your application runs across multiple BEAM VM clusters, rate limits will not be shared between them.


## Performance

All rate limiter state is held in a single OTP actor. Each hit is one message to this actor, which performs the token bucket calculation inline.

* **Memory** (in-memory mode): One dict entry per unique identifier. Idle identifiers (full token buckets) are automatically swept every 10 seconds.
* **Fail-open**: If the rate limiter actor is unavailable or a store lock fails, the request is allowed through rather than rejected.


## Documentation

Further documentation can be found at <https://hexdocs.pm/glimit/glimit.html>.


## Contributing

Contributions like PR's, bug reports or suggestions are more than welcome! ♥️
