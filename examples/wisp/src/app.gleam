import app/router
import gleam/erlang/process
import gleam/http/request
import gleam/result
import gleam/string_builder
import glimit
import mist
import wisp.{type Request}
import wisp/wisp_mist

pub fn main() {
  // Setup a rate limiter.
  let limiter =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(5)
    |> glimit.identifier(fn(req: Request) {
      req
      |> request.get_header("X-Forwarded-For")
      |> result.unwrap("anonymous")
    })
    |> glimit.on_limit_exceeded(fn(_) {
      let body = string_builder.from_string("<h1>Too many requests</h1>")
      wisp.html_response(body, 429)
    })

  wisp.configure_logger()

  let secret_key_base = wisp.random_string(64)

  // Start the Mist web server.
  let assert Ok(_) =
    wisp_mist.handler(
      router.handle_request
        |> glimit.apply(limiter),
      secret_key_base,
    )
    |> mist.new
    |> mist.port(8000)
    |> mist.start_http

  process.sleep_forever()
}
