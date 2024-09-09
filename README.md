# glimit

[![Package Version](https://img.shields.io/hexpm/v/glimit)](https://hex.pm/packages/glimit)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glimit/)
[![test](https://github.com/nootr/glimit/actions/workflows/test.yml/badge.svg)](https://github.com/nootr/glimit/actions/workflows/test.yml)

A simple, framework-agnostic, in-memory rate limiter for Gleam. 💫

> ⚠️  This library is still in development, use at your own risk.


## Features

* ✨ Simple and easy to use.
* 📏 Rate limits based on any key (e.g. IP address, or user ID).
* 🪣 Uses a distributed Token Bucket algorithm to rate limit requests.
* 🗄️ No back-end service needed; stores rate limit stats in-memory.


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

More practical examples can be found in the `examples/` directory, such as Wisp and Mist server examples.


## Constraints

While the in-memory rate limiter is simple and easy to use, it does have an important constraint: it is scoped to the BEAM VM cluster it runs in. This means that if your application is running across multiple BEAM VM clusters, the rate limiter will not be shared between them.

There are plans to add support for a centralized data store using Redis in the future.


## Documentation

Further documentation can be found at <https://hexdocs.pm/glimit/glimit.html>.


## Contributing

Contributions like PR's, bug reports or suggestions are more than welcome! ♥️
