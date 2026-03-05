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
import mist.{type Connection, type ResponseData}
import valkyrie
import valkyrie/resp

const redis_timeout = 1000

fn resp_to_string(value: resp.Value) -> Result(String, Nil) {
  case value {
    resp.SimpleString(s) | resp.BulkString(s) -> Ok(s)
    _ -> Error(Nil)
  }
}

fn redis_store(conn: valkyrie.Connection) -> glimit.Store {
  let lock = fn(key) {
    let opts =
      valkyrie.SetOptions(
        existence_condition: Some(valkyrie.IfNotExists),
        return_old: False,
        expiry_option: Some(valkyrie.ExpirySeconds(5)),
      )
    case valkyrie.set(conn, key <> ":lock", "1", Some(opts), redis_timeout) {
      Ok(_) -> Ok(Nil)
      Error(_) -> Error(Nil)
    }
  }

  let get = fn(key) {
    case valkyrie.hgetall(conn, key, redis_timeout) {
      Ok(fields) -> {
        let pairs =
          dict.to_list(fields)
          |> list.filter_map(fn(p) {
            use k <- result.try(resp_to_string(p.0))
            use v <- result.try(resp_to_string(p.1))
            Ok(#(k, v))
          })
        case bucket.from_pairs(pairs) {
          Ok(state) -> Ok(Some(state))
          _ -> Ok(None)
        }
      }
      Error(_) -> Error(Nil)
    }
  }

  let unlock = fn(key) {
    let _ = valkyrie.del(conn, [key <> ":lock"], redis_timeout)
    Ok(Nil)
  }

  bucket.Store(
    lock_and_get: fn(key) {
      use _ <- result.try(lock(key))
      case get(key) {
        Ok(result) -> Ok(result)
        Error(_) -> {
          let _ = unlock(key)
          Error(Nil)
        }
      }
    },
    set_and_unlock: fn(key, state, ttl) {
      let fields = bucket.to_pairs(state) |> dict.from_list
      let result = case valkyrie.hset(conn, key, fields, redis_timeout) {
        Ok(_) -> {
          let _ = valkyrie.expire(conn, key, ttl, None, redis_timeout)
          Ok(Nil)
        }
        Error(_) -> Error(Nil)
      }
      let _ = unlock(key)
      result
    },
    unlock: unlock,
  )
}

fn get_ip(req: Request(Connection)) -> String {
  req.body
  |> mist.get_client_info
  |> result.map(fn(ci) { ci.ip_address |> string.inspect })
  |> result.unwrap("unknown")
}

pub fn main() {
  let assert Ok(conn) =
    valkyrie.default_config()
    |> valkyrie.create_connection(redis_timeout)

  let limiter =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(5)
    |> glimit.store(redis_store(conn))
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
