import gleam/string_builder
import wisp.{type Request, type Response}

/// The HTTP request handler- your application!
/// 
pub fn handle_request(_req: Request) -> Response {
  let body = string_builder.from_string("<h1>👋 Hi!</h1>")
  wisp.html_response(body, 200)
}
