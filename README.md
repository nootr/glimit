# glimit

[![Package Version](https://img.shields.io/hexpm/v/glimit)](https://hex.pm/packages/glimit)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glimit/)
[![test](https://github.com/nootr/glimit/actions/workflows/test.yml/badge.svg)](https://github.com/nootr/glimit/actions/workflows/test.yml)

A framework-agnostic rate limiter for Gleam. 💫

> ⚠️  This library is still in development, use at your own risk.


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
    |> glimit.per_minute(100)
    |> glimit.per_hour(1000)
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


## How it works

Once v1.0 is reached, `glimit` will use a distributed Token Bucket algorithm to rate limit requests. It will support multiple backend storage systems, such as Redis and in-memory storage.

However, at the moment, `glimit` uses a simple Sliding Window algorithm with in-memory storage. This means that the rate limiter is not memory efficient and is not ready for production use.


## Documentation

Further documentation can be found at <https://hexdocs.pm/glimit>.


## Contributing

Contributions like PR's, bug reports or suggestions are more than welcome! ♥️
