# glimit

[![Package Version](https://img.shields.io/hexpm/v/glimit)](https://hex.pm/packages/glimit)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glimit/)

A framework-agnostic rate limiter for Gleam. 💫

> ⚠️  This library is still in development, use at your own risk.


## Installation

```sh
gleam add glimit
```


## Example usage

Glimit could be used to rate limit requests to a mist HTTP server:

```gleam
import glimit
import gleam/bytes_builder


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

pub fn main() {
  let limiter =
    glimit.new()
    |> glimit.per_second(10)
    |> glimit.per_minute(100)
    |> glimit.per_hour(1000)
    |> glimit.identifier(fn(req: Request(Connection)) {
      req.body
      |> get_client_info
      |> result.map(fn(client_info: ConnectionInfo) {
        client_info.ip_address |> string.inspect
      })
      |> result.unwrap("unknown IP address")
    })
    |> glimit.handler(fn(_req) {
      response.new(429)
      |> response.set_body(mist.Bytes(bytes_builder.new()))
    })
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

Further documentation can be found at <https://hexdocs.pm/glimit>.

## Development

```sh
gleam test  # Run the tests
```
