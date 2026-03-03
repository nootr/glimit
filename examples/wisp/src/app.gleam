import app/router
import gleam/erlang/process
import gleam/http/request
import gleam/result
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
    // NOTE: X-Forwarded-For is trivially spoofable by clients. Only trust
    // this header when running behind a trusted reverse proxy. In production,
    // extract only the first or last IP depending on your proxy configuration.
    |> glimit.identifier(fn(req: Request) {
      req
      |> request.get_header("X-Forwarded-For")
      |> result.unwrap("anonymous")
    })
    |> glimit.on_limit_exceeded(fn(_) {
      wisp.html_response("<h1>Too many requests</h1>", 429)
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
    |> mist.start

  process.sleep_forever()
}
