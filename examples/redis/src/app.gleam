import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/result
import gleam/string
import glimit
import mist.{type Connection, type ResponseData}
import redis_store
import valkyrie

fn get_ip(req: Request(Connection)) -> String {
  req.body
  |> mist.get_client_info
  |> result.map(fn(ci) { ci.ip_address |> string.inspect })
  |> result.unwrap("unknown")
}

pub fn main() {
  let assert Ok(conn) =
    valkyrie.default_config()
    |> valkyrie.create_connection(redis_store.default_timeout)

  let limiter =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(5)
    |> glimit.store(redis_store.new(conn))
    |> glimit.identifier(get_ip)
    |> glimit.on_limit_exceeded(fn(_) {
      response.new(429)
      |> response.set_body(
        mist.Bytes(bytes_tree.from_string("Too many requests")),
      )
    })

  let handler = fn(req: Request(Connection)) -> Response(ResponseData) {
    case request.path_segments(req) {
      [] ->
        response.new(200)
        |> response.set_body(
          mist.Bytes(bytes_tree.from_string("Hello, world!")),
        )
      _ ->
        response.new(404)
        |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))
    }
  }

  let assert Ok(_) =
    handler
    |> glimit.apply(limiter)
    |> mist.new
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}
