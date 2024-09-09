import gleam/bytes_builder
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/result
import gleam/string
import glimit
import mist.{
  type Connection, type ConnectionInfo, type ResponseData, get_client_info,
}

fn handle_request(req: Request(Connection)) -> Response(ResponseData) {
  let index =
    response.new(200)
    |> response.set_body(mist.Bytes(bytes_builder.from_string("Hello, world!")))
  let not_found =
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_builder.from_string("Not found")))

  case request.path_segments(req) {
    [] -> index
    _ -> not_found
  }
}

fn get_ip_address(req: Request(Connection)) -> String {
  req.body
  |> get_client_info
  |> result.map(fn(client_info: ConnectionInfo) {
    client_info.ip_address |> string.inspect
  })
  |> result.unwrap("unknown IP address")
}

pub fn main() {
  let rate_limit_reached = fn(_req) {
    response.new(429)
    |> response.set_body(
      mist.Bytes(bytes_builder.from_string("Too many requests")),
    )
  }

  let limiter =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(5)
    |> glimit.identifier(get_ip_address)
    |> glimit.on_limit_exceeded(rate_limit_reached)

  let assert Ok(_) =
    handle_request
    |> glimit.apply(limiter)
    |> mist.new
    |> mist.port(8000)
    |> mist.start_http

  process.sleep_forever()
}
