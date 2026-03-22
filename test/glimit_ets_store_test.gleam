import gleam/list
import gleam/option
import gleeunit/should
import glimit
import glimit/ets_store

pub fn ets_store_basic_rate_limiting_test() {
  let es = ets_store.new()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.store(ets_store.make_store(es))
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")
}

pub fn ets_store_different_ids_test() {
  let es = ets_store.new()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.store(ets_store.make_store(es))
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  func("a") |> should.equal("OK")
  func("b") |> should.equal("OK")
  func("b") |> should.equal("OK")
  func("b") |> should.equal("Stop!")
  func("a") |> should.equal("OK")
  func("a") |> should.equal("Stop!")
}

pub fn ets_store_burst_limit_test() {
  let es = ets_store.new()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(3)
    |> glimit.store(ets_store.make_store(es))
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_error

  // After 1 second, 1 token refills
  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_error
}

pub fn ets_store_get_count_test() {
  let es = ets_store.new()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.store(ets_store.make_store(es))
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  ets_store.get_count(es) |> should.equal(0)

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "b") |> should.be_ok
  ets_store.get_count(es) |> should.equal(2)

  // Same id doesn't increase count
  glimit.hit(limiter, "a") |> should.be_ok
  ets_store.get_count(es) |> should.equal(2)
}

pub fn ets_store_remove_test() {
  let es = ets_store.new()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.store(ets_store.make_store(es))
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
  ets_store.get_count(es) |> should.equal(1)

  ets_store.remove(es, "glimit:\"a\"") |> should.equal(Ok(Nil))
  ets_store.get_count(es) |> should.equal(0)
}

pub fn ets_store_sweep_full_bucket_test() {
  let es = ets_store.new()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.store(ets_store.make_store(es))
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "a") |> should.be_ok

  // After a long time, bucket refills to full — sweep removes it
  ets_store.sweep(store: es, now: 1_000_000, max_idle_ms: option.Some(60_000))
  |> should.equal(1)
  ets_store.get_count(es) |> should.equal(0)
}

pub fn ets_store_sweep_keeps_active_test() {
  let es = ets_store.new()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.store(ets_store.make_store(es))
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "a") |> should.be_ok

  // At t=0, bucket is not full and not idle — kept
  ets_store.sweep(store: es, now: 0, max_idle_ms: option.Some(60_000))
  |> should.equal(0)
  ets_store.get_count(es) |> should.equal(1)
}

pub fn ets_store_sweep_idle_bucket_test() {
  let es = ets_store.new()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(100)
    |> glimit.store(ets_store.make_store(es))
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)

  // Exhaust all 100 tokens
  list.repeat(Nil, 100)
  |> list.each(fn(_) {
    let _ = glimit.hit(limiter, "a")
    Nil
  })

  // At t=61_000: not full (only ~61 tokens refilled), but idle > 60s — swept
  ets_store.sweep(store: es, now: 61_000, max_idle_ms: option.Some(60_000))
  |> should.equal(1)
  ets_store.get_count(es) |> should.equal(0)
}

pub fn ets_store_sweep_mixed_buckets_test() {
  let es = ets_store.new()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.store(ets_store.make_store(es))
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "b") |> should.be_ok
  glimit.hit(limiter, "c") |> should.be_ok
  glimit.hit(limiter, "c") |> should.be_ok

  ets_store.get_count(es) |> should.equal(3)

  // After a long time, all buckets are full — all swept
  ets_store.sweep(store: es, now: 1_000_000, max_idle_ms: option.Some(60_000))
  |> should.equal(3)
  ets_store.get_count(es) |> should.equal(0)
}

pub fn ets_store_default_test() {
  // ETS is the default — no explicit store configuration needed
  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(_) { "OK" }
    |> glimit.apply(limiter)

  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
}

fn set_now(
  limiter: glimit.RateLimiter(a, b, id),
  now: Int,
) -> glimit.RateLimiter(a, b, id) {
  glimit.RateLimiter(..limiter, now: fn() { now })
}
