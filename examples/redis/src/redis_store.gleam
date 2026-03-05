import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import glimit/bucket
import valkyrie
import valkyrie/resp

pub const default_timeout = 1000

fn lock_key(key: String) -> String {
  key <> ":lock"
}

fn resp_to_string(value: resp.Value) -> Result(String, Nil) {
  case value {
    resp.SimpleString(s) | resp.BulkString(s) -> Ok(s)
    _ -> Error(Nil)
  }
}

fn lock(conn: valkyrie.Connection, key: String) -> Result(Nil, Nil) {
  let opts =
    valkyrie.SetOptions(
      existence_condition: Some(valkyrie.IfNotExists),
      return_old: False,
      expiry_option: Some(valkyrie.ExpirySeconds(5)),
    )
  case valkyrie.set(conn, lock_key(key), "1", Some(opts), default_timeout) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(Nil)
  }
}

fn get(
  conn: valkyrie.Connection,
  key: String,
) -> Result(Option(bucket.BucketState), Nil) {
  case valkyrie.hgetall(conn, key, default_timeout) {
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

fn unlock(conn: valkyrie.Connection, key: String) -> Result(Nil, Nil) {
  let _ = valkyrie.del(conn, [lock_key(key)], default_timeout)
  Ok(Nil)
}

fn lock_and_get(
  conn: valkyrie.Connection,
  key: String,
) -> Result(Option(bucket.BucketState), Nil) {
  use _ <- result.try(lock(conn, key))
  case get(conn, key) {
    Ok(result) -> Ok(result)
    Error(_) -> {
      let _ = unlock(conn, key)
      Error(Nil)
    }
  }
}

fn set_and_unlock(
  conn: valkyrie.Connection,
  key: String,
  state: bucket.BucketState,
  ttl: Int,
) -> Result(Nil, Nil) {
  let result = case
    valkyrie.hset(
      conn,
      key,
      bucket.to_pairs(state) |> dict.from_list,
      default_timeout,
    )
  {
    Ok(_) -> {
      let _ = valkyrie.expire(conn, key, ttl, None, default_timeout)
      Ok(Nil)
    }
    Error(_) -> Error(Nil)
  }
  let _ = unlock(conn, key)
  result
}

pub fn new(conn: valkyrie.Connection) -> bucket.Store {
  bucket.Store(
    lock_and_get: fn(key) { lock_and_get(conn, key) },
    set_and_unlock: fn(key, state, ttl) {
      set_and_unlock(conn, key, state, ttl)
    },
    unlock: fn(key) { unlock(conn, key) },
  )
}
