//// These tests need a Redis or Valkey server on localhost:6379.
////

import gleam/bit_array
import gleam/crypto
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import glimit
import glimit/bucket
import redis_store
import valkyrie
import valkyrie/resp

pub fn main() -> Nil {
  gleeunit.main()
}

fn connect() -> valkyrie.Connection {
  let assert Ok(conn) =
    valkyrie.start_pool(
      config: valkyrie.default_config(),
      size: 16,
      name: None,
      timeout: redis_store.default_timeout,
    )
  conn
}

fn unique_key() -> String {
  "glimit-test:" <> { crypto.strong_random_bytes(8) |> bit_array.base16_encode }
}

fn command(conn: valkyrie.Connection, parts: List(String)) -> resp.Value {
  let assert Ok([reply]) =
    valkyrie.custom(conn, parts, redis_store.default_timeout)
  reply
}

/// Run `f` in another process and wait for its result.
fn in_other_process(f: fn() -> a) -> a {
  let subject = process.new_subject()
  process.spawn(fn() { process.send(subject, f()) })
  let assert Ok(result) = process.receive(subject, 5000)
  result
}

pub fn round_trip_test() {
  let conn = connect()
  let store = redis_store.new(conn)
  let key = unique_key()
  let assert Ok(state) = bucket.new_with_period(5, 1, 1000)
  let state = bucket.BucketState(..state, token_count: 3.0)

  let assert Ok(None) = store.lock_and_get(key)
  let assert Ok(Nil) = store.set_and_unlock(key, state, 60)
  let assert resp.Integer(0) = command(conn, ["EXISTS", key <> ":lock"])

  let assert Ok(Some(loaded)) = store.lock_and_get(key)
  assert loaded == state
  let assert Ok(Nil) = store.unlock(key)
  let assert resp.Integer(0) = command(conn, ["EXISTS", key <> ":lock"])
}

pub fn held_lock_blocks_others_test() {
  let conn = connect()
  let store = redis_store.new(conn)
  let key = unique_key()

  let assert Ok(None) = store.lock_and_get(key)
  let assert Error(Nil) = in_other_process(fn() { store.lock_and_get(key) })
  let assert Ok(Nil) = store.unlock(key)
  let assert Ok(None) =
    in_other_process(fn() {
      let result = store.lock_and_get(key)
      let _ = store.unlock(key)
      result
    })
}

pub fn lost_lock_does_not_write_or_unlock_test() {
  let conn = connect()
  let store = redis_store.new(conn)
  let key = unique_key()
  let assert Ok(state) = bucket.new_with_period(5, 1, 1000)

  let assert Ok(None) = store.lock_and_get(key)
  // Our lock expires and another request takes it over
  let assert resp.SimpleString("OK") =
    command(conn, ["SET", key <> ":lock", "someone-else"])

  let assert Error(Nil) = store.set_and_unlock(key, state, 60)
  let assert resp.Integer(0) = command(conn, ["EXISTS", key])
  let assert resp.BulkString("someone-else") =
    command(conn, ["GET", key <> ":lock"])
}

pub fn unlock_keeps_foreign_lock_test() {
  let conn = connect()
  let store = redis_store.new(conn)
  let key = unique_key()

  let assert Ok(None) = store.lock_and_get(key)
  let assert resp.SimpleString("OK") =
    command(conn, ["SET", key <> ":lock", "someone-else"])

  let assert Ok(Nil) = store.unlock(key)
  let assert resp.BulkString("someone-else") =
    command(conn, ["GET", key <> ":lock"])
}

pub fn lock_expires_test() {
  let conn = connect()
  let key = unique_key()
  let assert Ok(None) = redis_store.new(conn).lock_and_get(key)
  let assert resp.Integer(ttl) = command(conn, ["PTTL", key <> ":lock"])
  assert ttl > 0 && ttl <= 5000
}

pub fn concurrent_hits_respect_limit_test() {
  let conn = connect()
  let id = unique_key()
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_hour(1)
    |> glimit.burst_limit(10)
    |> glimit.store(redis_store.new(conn))
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { Nil })
    |> glimit.build

  let subject = process.new_subject()
  list.repeat(Nil, 40)
  |> list.each(fn(_) {
    process.spawn(fn() { process.send(subject, glimit.hit(limiter, id)) })
  })
  let results =
    list.repeat(Nil, 40)
    |> list.map(fn(_) {
      let assert Ok(result) = process.receive(subject, 5000)
      result
    })

  assert list.count(results, fn(r) { r == Ok(Nil) }) == 10
  assert list.count(results, fn(r) { r == Error(glimit.RateLimited) }) == 30
}
