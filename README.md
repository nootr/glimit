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
  |> glimit.build

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

A more practical example would be to use `glimit` to rate limit requests to a mist HTTP server:

```gleam
import glimit


fn handle_request(req: Request(Connection)) -> Response(ResponseData) {
  let index =
    response.new(200)
    |> response.set_body(mist.Bytes(bytes_builder.new()))
  let not_found =
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_builder.new()))

  case request.path_segments(req) {
    [] -> index
    _ -> not_found
  }
}

fn get_identifier(req: Request(Connection)) -> Result(String, String) {
  req.body
  |> get_client_info
  |> result.map(fn(client_info: ConnectionInfo) {
    client_info.ip_address |> string.inspect
  })
  |> result.unwrap("unknown IP address")
}

pub fn main() {
  let rate_limit_reached = fn(_req) -> {
    response.new(429)
    |> response.set_body(mist.Bytes(bytes_builder.new()))
  }

  let limiter =
    glimit.new()
    |> glimit.per_second(10)
    |> glimit.burst_limit(100)
    |> glimit.identifier(get_identifier)
    |> glimit.on_limit_exceeded(rate_limit_reached)
    |> glimit.build

  let assert Ok(_) =
    handle_request
    |> glimit.apply(limiter)
    |> mist.new
    |> mist.port(8080)
    |> mist.start_http

  process.sleep_forever()
}
```


## Constraints

While the in-memory rate limiter is simple and easy to use, it does have an important constraint: it is scoped to the BEAM VM cluster it runs in. This means that if your application is running across multiple BEAM VM clusters, the rate limiter will not be shared between them.

There are plans to add support for a centralized data store using Redis in the future.


## Documentation

Further documentation can be found at <https://hexdocs.pm/glimit/glimit.html>.


## Contributing

Contributions like PR's, bug reports or suggestions are more than welcome! ♥️
