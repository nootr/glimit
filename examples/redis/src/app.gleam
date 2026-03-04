import gleam/bytes_tree
import gleam/dict
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import glimit
import glimit/bucket
import mist.{
  type Connection, type ConnectionInfo, type ResponseData, get_client_info,
}
import valkyrie
import valkyrie/resp

const redis_timeout = 1000

fn handle_request(req: Request(Connection)) -> Response(ResponseData) {
  let index =
    response.new(200)
    |> response.set_body(mist.Bytes(bytes_tree.from_string("Hello, world!")))
  let not_found =
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))

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

fn redis_store(conn: valkyrie.Connection) -> glimit.Store {
  bucket.Store(
    get: fn(key) {
      case valkyrie.hgetall(conn, key, redis_timeout) {
        Ok(fields) -> {
          let pairs =
            fields
            |> dict.to_list
            |> list.filter_map(fn(pair) {
              case pair {
                #(resp.SimpleString(k), resp.SimpleString(v))
                | #(resp.BulkString(k), resp.BulkString(v))
                | #(resp.SimpleString(k), resp.BulkString(v))
                | #(resp.BulkString(k), resp.SimpleString(v)) -> Ok(#(k, v))
                _ -> Error(Nil)
              }
            })
          case pairs {
            [] -> Ok(None)
            _ ->
              case bucket.from_pairs(pairs) {
                Ok(state) -> Ok(Some(state))
                Error(_) -> Ok(None)
              }
          }
        }
        Error(_) -> Error(Nil)
      }
    },
    set: fn(key, state, ttl) {
      let fields =
        bucket.to_pairs(state)
        |> dict.from_list
      case valkyrie.hset(conn, key, fields, redis_timeout) {
        Ok(_) -> {
          let _ = valkyrie.expire(conn, key, ttl, None, redis_timeout)
          Ok(Nil)
        }
        Error(_) -> Error(Nil)
      }
    },
    lock: fn(key) {
      let lock_key = key <> ":lock"
      let opts =
        valkyrie.SetOptions(
          existence_condition: Some(valkyrie.IfNotExists),
          return_old: False,
          expiry_option: Some(valkyrie.ExpirySeconds(5)),
        )
      case valkyrie.set(conn, lock_key, "1", Some(opts), redis_timeout) {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error(Nil)
      }
    },
    unlock: fn(key) {
      let lock_key = key <> ":lock"
      let _ = valkyrie.del(conn, [lock_key], redis_timeout)
      Ok(Nil)
    },
  )
}

pub fn main() {
  // Connect to Redis (localhost:6379, no auth)
  let assert Ok(conn) =
    valkyrie.default_config()
    |> valkyrie.create_connection(redis_timeout)

  let rate_limit_reached = fn(_req) {
    response.new(429)
    |> response.set_body(
      mist.Bytes(bytes_tree.from_string("Too many requests")),
    )
  }

  let limiter =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(5)
    |> glimit.store(redis_store(conn))
    |> glimit.identifier(get_ip_address)
    |> glimit.on_limit_exceeded(rate_limit_reached)

  let assert Ok(_) =
    handle_request
    |> glimit.apply(limiter)
    |> mist.new
    |> mist.port(8000)
    |> mist.start

  process.sleep_forever()
}
