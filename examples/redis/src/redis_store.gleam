import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import glimit/bucket
import valkyrie
import valkyrie/resp

pub const default_timeout = 1000

const max_wait_ms = 500

const min_retry_delay_ms = 2

const max_retry_delay_ms = 50

fn lock_key(key: String) -> String {
  key <> ":lock"
}

fn resp_to_string(value: resp.Value) -> Result(String, Nil) {
  case value {
    resp.SimpleString(s) | resp.BulkString(s) -> Ok(s)
    _ -> Error(Nil)
  }
}

fn pool_is_busy(error: valkyrie.Error) -> Bool {
  case error {
    valkyrie.PoolError(valkyrie.NoResourcesAvailable) -> True
    _ -> False
  }
}

fn lock_is_held_or_pool_is_busy(error: valkyrie.Error) -> Bool {
  case error {
    // Redis returns null when the key already exists, so the lock is held
    valkyrie.NotFound -> True
    _ -> pool_is_busy(error)
  }
}

/// Run a command, retrying with a growing, randomised delay while `should_retry`
/// holds, until `wait_left_ms` is used up. The randomness stops waiting requests
/// from all polling Redis at the same moment.
///
fn with_retries(
  command: fn() -> Result(a, valkyrie.Error),
  should_retry: fn(valkyrie.Error) -> Bool,
  wait_left_ms: Int,
  delay_ms: Int,
) -> Result(a, valkyrie.Error) {
  case command() {
    Error(error) ->
      case should_retry(error) && wait_left_ms > 0 {
        True -> {
          let wait_ms = int.min(1 + int.random(delay_ms), wait_left_ms)
          process.sleep(wait_ms)
          let next_delay_ms = int.min(delay_ms * 2, max_retry_delay_ms)
          with_retries(
            command,
            should_retry,
            wait_left_ms - wait_ms,
            next_delay_ms,
          )
        }
        False -> Error(error)
      }
    Ok(value) -> Ok(value)
  }
}

/// Run a command. Without the retries, a failed unlock would leave the lock held
/// until it expires.
///
fn when_connected(
  command: fn() -> Result(a, valkyrie.Error),
) -> Result(a, valkyrie.Error) {
  with_retries(command, pool_is_busy, max_wait_ms, min_retry_delay_ms)
}

/// Wait for a held lock. The rate limiter fails open if this returns an error,
/// so failing straight away would let concurrent requests skip the limit.
///
fn lock(conn: valkyrie.Connection, key: String) -> Result(Nil, Nil) {
  let opts =
    valkyrie.SetOptions(
      existence_condition: Some(valkyrie.IfNotExists),
      return_old: False,
      expiry_option: Some(valkyrie.ExpirySeconds(5)),
    )
  let acquire = fn() {
    valkyrie.set(conn, lock_key(key), "1", Some(opts), default_timeout)
  }
  with_retries(
    acquire,
    lock_is_held_or_pool_is_busy,
    max_wait_ms,
    min_retry_delay_ms,
  )
  |> result.replace(Nil)
  |> result.replace_error(Nil)
}

fn get(
  conn: valkyrie.Connection,
  key: String,
) -> Result(Option(bucket.BucketState), Nil) {
  case when_connected(fn() { valkyrie.hgetall(conn, key, default_timeout) }) {
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
  let release = fn() { valkyrie.del(conn, [lock_key(key)], default_timeout) }
  let _ = when_connected(release)
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
  let result = {
    use _ <- result.try(
      when_connected(fn() {
        valkyrie.hset(
          conn,
          key,
          bucket.to_pairs(state) |> dict.from_list,
          default_timeout,
        )
      }),
    )
    when_connected(fn() {
      valkyrie.expire(conn, key, ttl, None, default_timeout)
    })
  }
  let _ = unlock(conn, key)
  result
  |> result.replace(Nil)
  |> result.replace_error(Nil)
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
