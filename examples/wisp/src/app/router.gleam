import wisp.{type Request, type Response}

/// The HTTP request handler- your application!
///
pub fn handle_request(_req: Request) -> Response {
  wisp.html_response("<h1>👋 Hi!</h1>", 200)
}
