import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import glimit/bucket
import valkyrie
import valkyrie/resp

pub const default_timeout = 1000

const retry_interval_ms = 5

const max_attempts = 100

fn lock_key(key: String) -> String {
  key <> ":lock"
}

fn resp_to_string(value: resp.Value) -> Result(String, Nil) {
  case value {
    resp.SimpleString(s) | resp.BulkString(s) -> Ok(s)
    _ -> Error(Nil)
  }
}

/// Run a command, retrying while every connection in the pool is in use.
/// Without this, a failed unlock would leave the lock held until it expires.
///
fn when_connected(
  tries: Int,
  command: fn() -> Result(a, valkyrie.Error),
) -> Result(a, valkyrie.Error) {
  case command() {
    Error(valkyrie.PoolError(valkyrie.NoResourcesAvailable)) if tries > 1 -> {
      process.sleep(retry_interval_ms)
      when_connected(tries - 1, command)
    }
    result -> result
  }
}

/// Wait for a held lock. The rate limiter fails open if this returns an error,
/// so failing straight away would let concurrent requests skip the limit.
///
fn lock_with_attempts(
  conn: valkyrie.Connection,
  key: String,
  attempts: Int,
) -> Result(Nil, Nil) {
  let opts =
    valkyrie.SetOptions(
      existence_condition: Some(valkyrie.IfNotExists),
      return_old: False,
      expiry_option: Some(valkyrie.ExpirySeconds(5)),
    )
  let result =
    when_connected(max_attempts, fn() {
      valkyrie.set(conn, lock_key(key), "1", Some(opts), default_timeout)
    })
  case result {
    Ok(_) -> Ok(Nil)
    // Redis returns null when the key already exists, so the lock is held
    Error(valkyrie.NotFound) if attempts > 1 -> {
      process.sleep(retry_interval_ms)
      lock_with_attempts(conn, key, attempts - 1)
    }
    Error(_) -> Error(Nil)
  }
}

fn lock(conn: valkyrie.Connection, key: String) -> Result(Nil, Nil) {
  lock_with_attempts(conn, key, max_attempts)
}

fn get(
  conn: valkyrie.Connection,
  key: String,
) -> Result(Option(bucket.BucketState), Nil) {
  case
    when_connected(max_attempts, fn() {
      valkyrie.hgetall(conn, key, default_timeout)
    })
  {
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
  let _ =
    when_connected(max_attempts, fn() {
      valkyrie.del(conn, [lock_key(key)], default_timeout)
    })
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
    when_connected(max_attempts, fn() {
      valkyrie.hset(
        conn,
        key,
        bucket.to_pairs(state) |> dict.from_list,
        default_timeout,
      )
    })
  {
    Ok(_) -> {
      let _ =
        when_connected(max_attempts, fn() {
          valkyrie.expire(conn, key, ttl, None, default_timeout)
        })
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
