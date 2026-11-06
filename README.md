# glimit

[![Package Version](https://img.shields.io/hexpm/v/glimit)](https://hex.pm/packages/glimit)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glimit/glimit.html)
[![test](https://github.com/nootr/glimit/actions/workflows/test.yml/badge.svg)](https://github.com/nootr/glimit/actions/workflows/test.yml)

A simple, framework-agnostic rate limiter for Gleam with pluggable storage. 💫


## Features

* ✨ Simple and easy to use.
* 📏 Rate limits based on any key (e.g. IP address, or user ID).
* 🪣 Uses a Token Bucket algorithm to rate limit requests.
* ⚡ ETS-backed by default for low-latency rate limiting; no separate back-end service needed.
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

Rates can also be set per minute or per hour, which suits budgets such as
"20 requests per hour per IP address". Tokens refill continuously, so
`per_hour(20)` allows a burst of 20 and then one more request every three
minutes:

```gleam
import glimit

let limiter =
  glimit.new()
  |> glimit.per_hour(20)
  |> glimit.identifier(fn(request) { request.ip })
  |> glimit.on_limit_exceeded(fn(_) { "Hourly limit reached" })
```

Rates of different periods can be combined. A request must then pass all of
them, and only spends tokens if it does. Setting a rate for a period that
already has one replaces it:

```gleam
import glimit

let limiter =
  glimit.new()
  |> glimit.per_second(10)
  |> glimit.per_hour(1000)
  |> glimit.identifier(fn(request) { request.ip })
  |> glimit.on_limit_exceeded(fn(_) { "Rate limit reached" })
```

`burst_limit` is always the maximum number of requests in a single burst: it
sets the bucket size of the shortest period. Buckets of longer periods hold at
least their own rate, so a small burst limit does not shrink them.

More practical examples can be found in the `examples/` directory, such as Wisp or Mist servers, or a Redis backend.


## Pluggable Store Backend

By default, rate limit state is stored in ETS (Erlang Term Storage). For distributed rate limiting across multiple nodes, you can provide a custom `Store` that persists bucket state in an external service like Redis or Postgres.

All token bucket logic stays in glimit — adapters only implement `lock_and_get` / `set_and_unlock` / `unlock` operations. The `glimit/bucket` module provides `to_pairs`/`from_pairs` helpers for serialization.

Requests run concurrently, so an adapter must be safe to call from multiple processes, for example by using a connection pool. `lock_and_get` should wait briefly for a held lock: if it fails, the limiter fails open and the request is not counted.

Rate limiters that share a store, identifier and period share a bucket. Use `glimit.key_prefix` to keep them apart:

```gleam
let limiter =
  glimit.new()
  |> glimit.per_second(10)
  |> glimit.store(my_redis_store)
  |> glimit.key_prefix("uploads")
  |> glimit.identifier(fn(request) { request.ip })
  |> glimit.on_limit_exceeded(fn(_) { "Rate limit reached" })
```

See [`examples/redis/`](https://github.com/nootr/glimit/tree/main/examples/redis) for a complete Redis adapter using [valkyrie](https://hexdocs.pm/valkyrie/).


## Performance

Every hit goes through the pluggable `Store` interface (`lock_and_get` / `set_and_unlock`), once per rate.

* **Default (ETS)**: Direct table operations per hit. No actor overhead.
* **Fail-open**: If the store is unavailable or a lock cannot be acquired, the request is allowed through rather than rejected. With multiple rates, a rate that cannot be checked is skipped and the other rates still apply.
* **Sweep**: Buckets that have refilled to full are automatically swept every 10 seconds. A partly used bucket is kept until it refills, so waiting does not reset a client's limit early.


## Documentation

Further documentation can be found at <https://hexdocs.pm/glimit/glimit.html>.


## Contributing

Contributions like PR's, bug reports or suggestions are more than welcome! ♥️
