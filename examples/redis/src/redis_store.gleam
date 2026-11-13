//// A `glimit` store backed by Redis or Valkey.
////
//// Each bucket is a hash, guarded by a lock key holding a random token. Each
//// step runs as one Lua script, so it is atomic and needs a single round trip:
////
//// - `lock_and_get` sets the lock if it is free and reads the bucket.
//// - `set_and_unlock` writes the bucket and releases the lock, but only while
////   the lock still holds our token. A holder whose lock has expired and been
////   taken over cannot overwrite the new holder's state or release its lock.
//// - `unlock` releases the lock only if it still holds our token.
////
//// Every reply has to contain our token, so a reply meant for another command
//// is never mistaken for our own.
////
//// The bucket and lock keys must live on the same node, so this store does not
//// support Redis Cluster.
////

import gleam/bit_array
import gleam/crypto
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import glimit/bucket
import valkyrie
import valkyrie/resp

pub const default_timeout = 1000

/// How long a lock lives if its holder never releases it, for example because
/// it crashed. It must be longer than a hit takes, including the rate and burst
/// limit functions. If a hit takes longer, its state is not saved and it
/// returns `Unavailable`.
///
const lock_ttl_ms = 5000

const max_wait_ms = 500

const min_retry_delay_ms = 2

const max_retry_delay_ms = 50

/// KEYS: bucket, lock. ARGV: token, lock TTL in ms.
/// Returns `{token, fields}` if the lock was acquired, or `0` if it is held.
///
const lock_and_get_script = "
if redis.call('SET', KEYS[2], ARGV[1], 'NX', 'PX', ARGV[2]) then
  return {ARGV[1], redis.call('HGETALL', KEYS[1])}
end
return 0
"

/// KEYS: bucket, lock. ARGV: token, TTL in seconds, field, value, ...
/// Returns the token if the state was saved, or `0` if the lock was lost.
///
const set_and_unlock_script = "
if redis.call('GET', KEYS[2]) ~= ARGV[1] then
  return 0
end
redis.call('HSET', KEYS[1], unpack(ARGV, 3))
redis.call('EXPIRE', KEYS[1], ARGV[2])
redis.call('DEL', KEYS[2])
return ARGV[1]
"

/// KEYS: lock. ARGV: token. Returns the token.
///
const unlock_script = "
if redis.call('GET', KEYS[1]) == ARGV[1] then
  redis.call('DEL', KEYS[1])
end
return ARGV[1]
"

type Failure {
  /// Another request holds the lock.
  LockHeld
  /// The request failed. The command may or may not have run.
  CommandFailed(valkyrie.Error)
  /// Redis replied with something else than expected, such as a reply meant
  /// for another command.
  UnexpectedReply
}

@external(erlang, "redis_store_ffi", "put_token")
fn put_token(key: String, token: String) -> Nil

@external(erlang, "redis_store_ffi", "take_token")
fn take_token(key: String) -> Result(String, Nil)

fn lock_key(key: String) -> String {
  key <> ":lock"
}

fn new_token() -> String {
  crypto.strong_random_bytes(16) |> bit_array.base16_encode
}

fn eval(
  conn: valkyrie.Connection,
  script: String,
  keys: List(String),
  args: List(String),
) -> Result(resp.Value, Failure) {
  let command =
    list.flatten([
      ["EVAL", script, int.to_string(list.length(keys))],
      keys,
      args,
    ])
  case valkyrie.custom(conn, command, default_timeout) {
    Ok([reply]) -> Ok(reply)
    Ok(_) -> Error(UnexpectedReply)
    Error(error) -> Error(CommandFailed(error))
  }
}

fn pool_is_busy(failure: Failure) -> Bool {
  case failure {
    CommandFailed(valkyrie.PoolError(valkyrie.NoResourcesAvailable)) -> True
    _ -> False
  }
}

fn lock_is_held_or_pool_is_busy(failure: Failure) -> Bool {
  failure == LockHeld || pool_is_busy(failure)
}

/// Run a command, retrying with a growing, randomised delay while `should_retry`
/// holds, until `wait_left_ms` is used up. The randomness stops waiting requests
/// from all polling Redis at the same moment.
///
fn with_retries(
  command: fn() -> Result(a, Failure),
  should_retry: fn(Failure) -> Bool,
  wait_left_ms: Int,
  delay_ms: Int,
) -> Result(a, Failure) {
  case command() {
    Error(failure) ->
      case should_retry(failure) && wait_left_ms > 0 {
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
        False -> Error(failure)
      }
    Ok(value) -> Ok(value)
  }
}

/// Run a command, waiting for a connection if the pool is busy. A busy pool
/// means the command was not sent, so it is safe to retry.
///
fn when_connected(command: fn() -> Result(a, Failure)) -> Result(a, Failure) {
  with_retries(command, pool_is_busy, max_wait_ms, min_retry_delay_ms)
}

fn parse_fields(fields: List(resp.Value)) -> Option(bucket.BucketState) {
  let pairs =
    fields
    |> list.sized_chunk(2)
    |> list.filter_map(fn(pair) {
      case pair {
        [resp.BulkString(k), resp.BulkString(v)] -> Ok(#(k, v))
        _ -> Error(Nil)
      }
    })
  bucket.from_pairs(pairs) |> option.from_result
}

fn release(conn: valkyrie.Connection, key: String, token: String) -> Nil {
  let _ =
    when_connected(fn() { eval(conn, unlock_script, [lock_key(key)], [token]) })
  Nil
}

/// Wait for a held lock. The rate limiter fails open if this returns an error,
/// so failing straight away would let concurrent requests skip the limit.
///
fn lock_and_get(
  conn: valkyrie.Connection,
  key: String,
) -> Result(Option(bucket.BucketState), Nil) {
  let token = new_token()
  let acquire = fn() {
    case
      eval(conn, lock_and_get_script, [key, lock_key(key)], [
        token,
        int.to_string(lock_ttl_ms),
      ])
    {
      Ok(resp.Array([resp.BulkString(reply_token), resp.Array(fields)]))
        if reply_token == token
      -> Ok(parse_fields(fields))
      Ok(resp.Integer(0)) -> Error(LockHeld)
      Ok(_) -> Error(UnexpectedReply)
      Error(failure) -> Error(failure)
    }
  }
  case
    with_retries(
      acquire,
      lock_is_held_or_pool_is_busy,
      max_wait_ms,
      min_retry_delay_ms,
    )
  {
    Ok(state) -> {
      put_token(key, token)
      Ok(state)
    }
    Error(failure) -> {
      // After a timeout or an unexpected reply the lock may still have been
      // acquired. Releasing it is safe, because only our own token is deleted.
      case lock_is_held_or_pool_is_busy(failure) {
        True -> Nil
        False -> release(conn, key, token)
      }
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
  use token <- result.try(take_token(key))
  let fields =
    bucket.to_pairs(state)
    |> list.flat_map(fn(pair) { [pair.0, pair.1] })
  let save = fn() {
    eval(conn, set_and_unlock_script, [key, lock_key(key)], [
      token,
      int.to_string(ttl),
      ..fields
    ])
  }
  case when_connected(save) {
    Ok(resp.BulkString(reply_token)) if reply_token == token -> Ok(Nil)
    // The lock expired and may now belong to another request
    Ok(resp.Integer(0)) -> Error(Nil)
    _ -> {
      release(conn, key, token)
      Error(Nil)
    }
  }
}

fn unlock(conn: valkyrie.Connection, key: String) -> Result(Nil, Nil) {
  case take_token(key) {
    Ok(token) -> release(conn, key, token)
    Error(Nil) -> Nil
  }
  Ok(Nil)
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
