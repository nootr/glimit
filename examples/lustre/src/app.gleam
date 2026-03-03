import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/result
import gleam/string
import glimit
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import mist.{
  type Connection, type ConnectionInfo, type ResponseData, get_client_info,
}

fn layout(
  title title: String,
  styles styles: String,
  content content: List(Element(Nil)),
) -> Element(Nil) {
  html.html([attribute.lang("en")], [
    html.head([], [
      html.meta([attribute.charset("utf-8")]),
      html.title([], title),
      html.style([], styles),
    ]),
    html.body([], content),
  ])
}

fn html_response(
  status status: Int,
  body body: Element(Nil),
) -> Response(ResponseData) {
  let html_string = element.to_document_string(body)
  response.new(status)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(html_string)))
}

fn index_page() -> Response(ResponseData) {
  let styles =
    "
    body { font-family: system-ui, sans-serif; max-width: 40rem; margin: 2rem auto; padding: 0 1rem; }
    h1 { color: #ffaff3; }
    code { background: #f0f0f0; padding: 0.15rem 0.3rem; border-radius: 3px; }
    "

  let content = [
    html.h1([], [element.text("glimit + Lustre")]),
    html.p([], [
      element.text("This page is rate-limited to "),
      html.code([], [element.text("1 request/second")]),
      element.text(" with a burst of "),
      html.code([], [element.text("5")]),
      element.text(". Refresh rapidly to see the 429 page."),
    ]),
  ]

  html_response(status: 200, body: layout(
    title: "glimit + Lustre",
    styles: styles,
    content: content,
  ))
}

fn rate_limited_page() -> Response(ResponseData) {
  let styles =
    "
    body { font-family: system-ui, sans-serif; max-width: 40rem; margin: 2rem auto; padding: 0 1rem; }
    h1 { color: #e74c3c; }
    "

  let content = [
    html.h1([], [element.text("429 — Too Many Requests")]),
    html.p([], [
      element.text("You've exceeded the rate limit. Wait a moment and try again."),
    ]),
  ]

  html_response(status: 429, body: layout(
    title: "Rate Limited",
    styles: styles,
    content: content,
  ))
}

fn not_found_page() -> Response(ResponseData) {
  let styles =
    "
    body { font-family: system-ui, sans-serif; max-width: 40rem; margin: 2rem auto; padding: 0 1rem; }
    h1 { color: #999; }
    "

  let content = [
    html.h1([], [element.text("404 — Not Found")]),
    html.p([], [element.text("The page you requested does not exist.")]),
  ]

  html_response(status: 404, body: layout(
    title: "Not Found",
    styles: styles,
    content: content,
  ))
}

fn handle_request(req: Request(Connection)) -> Response(ResponseData) {
  case request.path_segments(req) {
    [] -> index_page()
    _ -> not_found_page()
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
  let limiter =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(5)
    |> glimit.identifier(get_ip_address)
    |> glimit.on_limit_exceeded(fn(_req) { rate_limited_page() })

  let assert Ok(_) =
    handle_request
    |> glimit.apply(limiter)
    |> mist.new
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}
