import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/string
import gleeunit
import gleeunit/should
import glimit
import glimit/bucket

pub fn main() {
  gleeunit.main()
}

pub fn single_argument_function_per_second_test() {
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
  func(Nil) |> should.equal("Stop!")
}

pub fn single_argument_function_different_ids_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(_) { "OK" }
    |> glimit.apply(limiter)

  func("a") |> should.equal("OK")
  func("b") |> should.equal("OK")
  func("b") |> should.equal("OK")
  func("b") |> should.equal("Stop!")
  func("a") |> should.equal("OK")
  func("a") |> should.equal("Stop!")
}

pub fn burst_limit_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 3000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 6000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 13_000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn dynamic_per_second_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "id" -> 2
        _ -> 1
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(_) { "OK" }
    |> glimit.apply(limiter)

  func("id") |> should.equal("OK")
  func("id") |> should.equal("OK")
  func("id") |> should.equal("Stop!")
  func("id") |> should.equal("Stop!")

  func("other") |> should.equal("OK")
  func("other") |> should.equal("Stop!")
  func("other") |> should.equal("Stop!")
}

pub fn dynamic_per_second_static_burst_limit_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "id" -> 2
        _ -> 1
      }
    })
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.equal(Error(glimit.RateLimited))
}

pub fn static_per_second_dynamic_burst_limit_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit_fn(fn(id) {
      case id {
        "id" -> 3
        _ -> 2
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.equal(Error(glimit.RateLimited))
}

pub fn dynamic_per_second_dynamic_burst_limit_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "id" -> 2
        _ -> 1
      }
    })
    |> glimit.burst_limit_fn(fn(id) {
      case id {
        "id" -> 4
        _ -> 3
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "other") |> should.be_ok
  glimit.hit(limiter, "other") |> should.equal(Error(glimit.RateLimited))
}

pub fn sub_second_remainder_preservation_test() {
  // 2 tokens/sec, burst 10 — one token every 500ms
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(10)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  // Consume all 10 tokens at t=0
  let limiter = set_now(limiter, 0)
  list.repeat(Nil, 10)
  |> list.each(fn(_) { glimit.hit(limiter, "id") |> ignore })
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 400ms: tc = 0.0 + 2.0 * 400 / 1000 = 0.8 < 1.0 — still rate limited
  let limiter = set_now(limiter, 400)
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 500ms: tc = 0.8 + 2.0 * 100 / 1000 = 1.0 >= 1.0 — succeeds
  let limiter = set_now(limiter, 500)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 900ms: tc = 0.0 + 2.0 * 400 / 1000 = 0.8 < 1.0
  let limiter = set_now(limiter, 900)
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 1000ms: tc = 0.8 + 2.0 * 100 / 1000 = 1.0 >= 1.0
  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 2500ms: tc = 0.0 + 2.0 * 1500 / 1000 = 3.0 — 3 tokens
  let limiter = set_now(limiter, 2500)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn sub_second_remainder_non_divisible_rate_test() {
  // 3 tokens/sec, burst 5 — one token every ~333.3ms.
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(3)
    |> glimit.burst_limit(5)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  // Drain all 5 tokens at t=0
  let limiter = set_now(limiter, 0)
  list.repeat(Nil, 5)
  |> list.each(fn(_) { glimit.hit(limiter, "id") |> ignore })
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 333ms: tc = 0.0 + 3.0 * 333 / 1000 = 0.999 < 1.0
  let limiter = set_now(limiter, 333)
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 334ms: tc = 0.999 + 3.0 * 1 / 1000 = 1.002 >= 1.0 — succeeds
  let limiter = set_now(limiter, 334)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 666ms: tc = 0.002 + 3.0 * 332 / 1000 = 0.998 < 1.0
  let limiter = set_now(limiter, 666)
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 667ms: tc = 0.998 + 3.0 * 1 / 1000 = 1.001 >= 1.0 — succeeds
  let limiter = set_now(limiter, 667)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // 3000ms: tc = 0.001 + 3.0 * 2333 / 1000 = 7.0, capped at burst limit 5
  let limiter = set_now(limiter, 3000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn build_missing_per_second_test() {
  glimit.new()
  |> glimit.build
  |> should.equal(Error(
    "a rate limit (`per_second`, `per_minute` or `per_hour`) is required",
  ))
}

pub fn build_missing_identifier_test() {
  glimit.new()
  |> glimit.per_second(1)
  |> glimit.build
  |> should.equal(Error("`identifier` function is required"))
}

pub fn build_missing_on_limit_exceeded_test() {
  glimit.new()
  |> glimit.per_second(1)
  |> glimit.identifier(fn(_) { "id" })
  |> glimit.build
  |> should.equal(Error("`on_limit_exceeded` function is required"))
}

pub fn builder_overwrite_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(999)
    |> glimit.per_second(1)
    |> glimit.burst_limit(999)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(_) { "wrong" })
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "wrong" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  // burst_limit=2: two hits succeed, third is limited
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // Advance 1 second — per_second=1 so only 1 token refilled (not 999)
  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn apply2_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.identifier(fn(args: #(String, Int)) { args.0 })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(name: String, _count: Int) { "OK: " <> name }
    |> glimit.apply2(limiter)

  func("alice", 1) |> should.equal("OK: alice")
  func("alice", 2) |> should.equal("OK: alice")
  func("alice", 3) |> should.equal("Stop!")
  func("bob", 1) |> should.equal("OK: bob")
}

pub fn apply3_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.identifier(fn(args: #(String, Int, Bool)) { args.0 })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(name: String, _count: Int, _flag: Bool) { "OK: " <> name }
    |> glimit.apply3(limiter)

  func("alice", 1, True) |> should.equal("OK: alice")
  func("alice", 2, False) |> should.equal("Stop!")
}

pub fn apply4_test() {
  let limiter =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.identifier(fn(args: #(String, Int, Bool, String)) { args.0 })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(name: String, _a: Int, _b: Bool, _c: String) { "OK: " <> name }
    |> glimit.apply4(limiter)

  func("alice", 1, True, "x") |> should.equal("OK: alice")
  func("alice", 2, False, "y") |> should.equal("Stop!")
}

pub fn per_second_zero_fails_open_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(0)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  // Invalid config causes Unavailable → fails open
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
}

pub fn per_second_negative_fails_open_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(-1)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
}

pub fn hit_returns_ok_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
}

pub fn hit_rate_limited_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.equal(Error(glimit.RateLimited))
}

pub fn hit_different_ids_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(1)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.equal(Error(glimit.RateLimited))
  glimit.hit(limiter, "b") |> should.be_ok
  glimit.hit(limiter, "b") |> should.equal(Error(glimit.RateLimited))
}

pub fn get_count_empty_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.get_count(limiter) |> should.equal(0)
}

pub fn get_count_after_hits_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "b") |> should.be_ok
  glimit.get_count(limiter) |> should.equal(2)
}

pub fn same_id_same_count_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.get_count(limiter) |> should.equal(1)
}

pub fn set_now_and_hit_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1000)
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.equal(Error(glimit.RateLimited))
}

pub fn dynamic_config_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "fast" -> 10
        _ -> 1
      }
    })
    |> glimit.burst_limit_fn(fn(id) {
      case id {
        "fast" -> 10
        _ -> 1
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "fast") |> should.be_ok
  glimit.hit(limiter, "fast") |> should.be_ok
  glimit.hit(limiter, "slow") |> should.be_ok
  glimit.hit(limiter, "slow") |> should.equal(Error(glimit.RateLimited))
}

pub fn invalid_config_returns_unavailable_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "bad" -> 0
        _ -> 2
      }
    })
    |> glimit.burst_limit_fn(fn(id) {
      case id {
        "bad" -> 0
        _ -> 2
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  // Valid identifier works
  glimit.hit(limiter, "good") |> should.be_ok

  // Invalid config fails open with Unavailable
  glimit.hit(limiter, "bad") |> should.equal(Error(glimit.Unavailable))

  // Invalid identifier is not stored
  glimit.get_count(limiter) |> should.equal(1)
}

pub fn crashing_callback_returns_unavailable_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "crash" -> panic as "boom"
        _ -> 2
      }
    })
    |> glimit.burst_limit_fn(fn(id) {
      case id {
        "crash" -> panic as "boom"
        _ -> 2
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  // Crashing callback should return Unavailable
  glimit.hit(limiter, "crash") |> should.equal(Error(glimit.Unavailable))

  // Still serving other identifiers
  glimit.hit(limiter, "good") |> should.be_ok
}

pub fn crashing_single_callback_returns_unavailable_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "crash" -> panic as "boom"
        _ -> 2
      }
    })
    |> glimit.burst_limit(2)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "crash") |> should.equal(Error(glimit.Unavailable))

  glimit.hit(limiter, "good") |> should.be_ok
}

fn ignore(_value: a) -> Nil {
  Nil
}

fn set_now(
  limiter: glimit.RateLimiter(a, b, id),
  now: Int,
) -> glimit.RateLimiter(a, b, id) {
  glimit.RateLimiter(..limiter, now: fn() { now })
}

// ---------------------------------------------------------------------------
// In-memory store for testing the pluggable store backend
// ---------------------------------------------------------------------------

type StoreMsg {
  StoreLockAndGet(key: String, reply: Subject(Result(bucket.BucketState, Nil)))
  StoreSetAndUnlock(
    key: String,
    state: bucket.BucketState,
    ttl: Int,
    reply: Subject(Nil),
  )
  StoreUnlock(key: String, reply: Subject(Nil))
}

type StoreState {
  StoreState(
    data: dict.Dict(String, bucket.BucketState),
    locks: dict.Dict(String, Bool),
  )
}

fn new_test_store() -> glimit.Store {
  let assert Ok(started) =
    actor.new_with_initialiser(1000, fn(self_subject) {
      Ok(
        actor.initialised(StoreState(data: dict.new(), locks: dict.new()))
        |> actor.returning(self_subject),
      )
    })
    |> actor.on_message(fn(state: StoreState, msg: StoreMsg) {
      case msg {
        StoreLockAndGet(key, reply) -> {
          case dict.get(state.locks, key) {
            Ok(True) -> {
              actor.send(reply, Error(Nil))
              actor.continue(state)
            }
            _ -> {
              let locks = dict.insert(state.locks, key, True)
              case dict.get(state.data, key) {
                Ok(v) -> actor.send(reply, Ok(v))
                Error(_) -> actor.send(reply, Error(Nil))
              }
              actor.continue(StoreState(..state, locks: locks))
            }
          }
        }
        StoreSetAndUnlock(key, bucket_state, _ttl, reply) -> {
          let data = dict.insert(state.data, key, bucket_state)
          let locks = dict.delete(state.locks, key)
          actor.send(reply, Nil)
          actor.continue(StoreState(data: data, locks: locks))
        }
        StoreUnlock(key, reply) -> {
          let locks = dict.delete(state.locks, key)
          actor.send(reply, Nil)
          actor.continue(StoreState(..state, locks: locks))
        }
      }
    })
    |> actor.start

  let store_subject = started.data

  bucket.Store(
    lock_and_get: fn(key) {
      let reply: Subject(Result(bucket.BucketState, Nil)) =
        process.new_subject()
      process.send(store_subject, StoreLockAndGet(key, reply))
      case process.receive(reply, 1000) {
        Ok(Ok(v)) -> Ok(option.Some(v))
        Ok(Error(_)) -> Ok(option.None)
        Error(_) -> Error(Nil)
      }
    },
    set_and_unlock: fn(key, state, ttl) {
      let reply = process.new_subject()
      process.send(store_subject, StoreSetAndUnlock(key, state, ttl, reply))
      case process.receive(reply, 1000) {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error(Nil)
      }
    },
    unlock: fn(key) {
      let reply = process.new_subject()
      process.send(store_subject, StoreUnlock(key, reply))
      case process.receive(reply, 1000) {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error(Nil)
      }
    },
  )
}

pub fn store_basic_rate_limiting_test() {
  let test_store = new_test_store()

  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(_) { "OK" }
    |> glimit.apply(limiter)

  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
  func(Nil) |> should.equal("Stop!")
}

pub fn store_different_ids_test() {
  let test_store = new_test_store()

  let limiter =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })

  let func =
    fn(_) { "OK" }
    |> glimit.apply(limiter)

  func("a") |> should.equal("OK")
  func("b") |> should.equal("OK")
  func("b") |> should.equal("OK")
  func("b") |> should.equal("Stop!")
  func("a") |> should.equal("OK")
  func("a") |> should.equal("Stop!")
}

pub fn store_burst_limit_test() {
  let test_store = new_test_store()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(3)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)

  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("OK")
  func(Nil) |> should.equal("Stop!")
}

pub fn bucket_to_pairs_from_pairs_roundtrip_test() {
  let assert Ok(state) = bucket.new(10, 5)
  let pairs = bucket.to_pairs(state)
  let assert Ok(restored) = bucket.from_pairs(pairs)
  restored.max_token_count |> should.equal(state.max_token_count)
  restored.token_rate |> should.equal(state.token_rate)
  restored.refill_period_ms |> should.equal(state.refill_period_ms)
}

pub fn bucket_from_pairs_missing_field_test() {
  let pairs = [#("tc", "5.0"), #("lu", ""), #("mt", "10")]
  // Missing "tr" field
  bucket.from_pairs(pairs) |> should.be_error
}

pub fn per_hour_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_hour(20)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  // The default burst is the hourly budget
  let limiter = set_now(limiter, 0)
  list.repeat(Nil, 20)
  |> list.each(fn(_) { glimit.hit(limiter, "id") |> should.be_ok })
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  // One token refills every 180 seconds
  let limiter = set_now(limiter, 179_999)
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 180_000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn per_hour_fn_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_hour_fn(fn(id) {
      case id {
        "a" -> 2
        _ -> 1
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.equal(Error(glimit.RateLimited))
  glimit.hit(limiter, "b") |> should.be_ok
  glimit.hit(limiter, "b") |> should.equal(Error(glimit.RateLimited))

  // "a" refills every 30 minutes, "b" every hour
  let limiter = set_now(limiter, 1_800_000)
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "b") |> should.equal(Error(glimit.RateLimited))
}

pub fn per_minute_matches_per_second_test() {
  let assert Ok(per_minute) =
    glimit.new()
    |> glimit.per_minute(60)
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build
  let assert Ok(per_second) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let times = [0, 0, 0, 0, 500, 999, 1000, 1000, 2500, 2500, 2500, 9000]
  let per_second_hits = hits_at(per_second, times)
  hits_at(per_minute, times) |> should.equal(per_second_hits)
  per_second_hits
  |> should.equal([
    True, True, True, False, False, False, True, False, True, False, False, True,
  ])
}

pub fn per_minute_fn_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_minute_fn(fn(_) { 2 })
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 30_000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn combined_rates_stricter_rate_applies_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(10)
    |> glimit.per_hour(1)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  let limiter = set_now(limiter, 10_000)
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn per_hour_store_test() {
  let test_store = new_test_store()
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_hour(2)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))

  let limiter = set_now(limiter, 1_800_000)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn combined_rates_enforce_both_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.per_hour(3)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  hits_at(limiter, [0, 0, 0, 1000, 1000, 2000, 1_201_000, 1_201_000])
  |> should.equal([True, True, False, True, False, False, True, False])
}

pub fn combined_rates_order_does_not_matter_test() {
  let assert Ok(seconds_first) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.per_hour(3)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build
  let assert Ok(hours_first) =
    glimit.new()
    |> glimit.per_hour(3)
    |> glimit.per_second(2)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let times = [0, 0, 0, 1000, 1000, 2000, 1_201_000, 1_201_000]
  hits_at(hours_first, times) |> should.equal(hits_at(seconds_first, times))
}

pub fn combined_rates_three_periods_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_hour(3)
    |> glimit.per_second(1)
    |> glimit.per_minute(2)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  hits_at(limiter, [0, 0, 1000, 2000, 31_000, 32_000, 62_000])
  |> should.equal([True, False, True, False, True, False, False])
}

pub fn combined_rates_same_period_replaces_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_hour(1)
    |> glimit.per_second(2)
    |> glimit.per_hour(100)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  hits_at(limiter, [0, 0, 0])
  |> should.equal([True, True, False])
}

pub fn combined_rates_same_period_fn_replaces_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_minute(1)
    |> glimit.per_minute_fn(fn(_) { 2 })
    |> glimit.per_hour(100)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  hits_at(limiter, [0, 0, 0])
  |> should.equal([True, True, False])
}

pub fn combined_rates_rejection_keeps_longer_period_tokens_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.per_hour(2)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  // Requests rejected by the per-second rate must not spend the hourly budget
  hits_at(limiter, [0, 0, 0, 0, 1000, 2000])
  |> should.equal([True, False, False, False, True, False])
}

pub fn combined_rates_rejection_keeps_shorter_period_tokens_test() {
  let test_store = new_test_store()
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_minute(10)
    |> glimit.per_hour(1)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  hits_at(limiter, [0, 0, 0])
  |> should.equal([True, False, False])

  let key = "glimit:\"id\":60000"
  let assert Ok(option.Some(state)) = test_store.lock_and_get(key)
  state.token_count |> should.equal(9.0)
}

pub fn combined_rates_burst_below_shortest_rate_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(100)
    |> glimit.per_hour(1000)
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  hits_at(limiter, [0, 0, 0, 0])
  |> should.equal([True, True, True, False])
}

pub fn combined_rates_burst_does_not_shrink_longer_period_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.per_hour(5)
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  hits_at(limiter, [0, 0, 0, 0, 2000, 2000, 2000])
  |> should.equal([True, True, True, False, True, True, False])
}

pub fn combined_rates_burst_above_longest_rate_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.per_hour(2)
    |> glimit.burst_limit(3)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  hits_at(limiter, [0, 0, 0, 0])
  |> should.equal([True, True, True, False])
}

pub fn combined_rates_dynamic_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      case id {
        "premium" -> 3
        _ -> 1
      }
    })
    |> glimit.per_hour_fn(fn(id) {
      case id {
        "premium" -> 2
        _ -> 100
      }
    })
    |> glimit.burst_limit_fn(fn(id) {
      case id {
        "premium" -> 3
        _ -> 2
      }
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "premium") |> should.be_ok
  glimit.hit(limiter, "premium") |> should.be_ok
  glimit.hit(limiter, "premium") |> should.be_ok
  glimit.hit(limiter, "premium") |> should.equal(Error(glimit.RateLimited))
  glimit.hit(limiter, "free") |> should.be_ok
  glimit.hit(limiter, "free") |> should.be_ok
  glimit.hit(limiter, "free") |> should.equal(Error(glimit.RateLimited))
}

pub fn combined_rates_invalid_rate_keeps_other_rates_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.per_hour(0)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn combined_rates_invalid_shortest_rate_keeps_other_rates_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(0)
    |> glimit.per_hour(1)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn combined_rates_panicking_rate_keeps_other_rates_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.per_hour_fn(fn(_) { panic as "boom" })
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn combined_rates_all_invalid_fails_open_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(0)
    |> glimit.per_hour_fn(fn(_) { panic as "boom" })
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "id") |> should.equal(Error(glimit.Unavailable))
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.Unavailable))
}

pub fn combined_rates_store_keys_test() {
  let test_store = new_test_store()
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.per_hour(3)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "id") |> should.be_ok

  let assert Ok(option.Some(seconds)) =
    test_store.lock_and_get("glimit:\"id\":1000")
  seconds.refill_period_ms |> should.equal(1000)
  seconds.max_token_count |> should.equal(2)

  let assert Ok(option.Some(hours)) =
    test_store.lock_and_get("glimit:\"id\":3600000")
  hours.refill_period_ms |> should.equal(3_600_000)
  hours.max_token_count |> should.equal(3)
}

pub fn combined_rates_lock_failure_keeps_other_rates_test() {
  let test_store = new_test_store()
  let failing_store =
    bucket.Store(..test_store, lock_and_get: fn(key) {
      case string.ends_with(key, ":3600000") {
        True -> Error(Nil)
        False -> test_store.lock_and_get(key)
      }
    })

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.per_hour(3)
    |> glimit.store(failing_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn combined_rates_all_locks_failing_fails_open_test() {
  let failing_store =
    bucket.Store(
      lock_and_get: fn(_) { Error(Nil) },
      set_and_unlock: fn(_, _, _) { Ok(Nil) },
      unlock: fn(_) { Ok(Nil) },
    )

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.per_hour(3)
    |> glimit.store(failing_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "id") |> should.equal(Error(glimit.StoreLockFailed))
}

pub fn combined_rates_invalid_rate_releases_its_lock_test() {
  let unlocked = process.new_subject()
  let store =
    bucket.Store(
      lock_and_get: fn(_) { Ok(option.None) },
      set_and_unlock: fn(_, _, _) { Ok(Nil) },
      unlock: fn(key) {
        process.send(unlocked, key)
        Ok(Nil)
      },
    )

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(2)
    |> glimit.per_hour(0)
    |> glimit.store(store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "id") |> should.be_ok
  process.receive(unlocked, 100)
  |> should.equal(Ok("glimit:\"id\":3600000"))
}

pub fn adding_a_shorter_rate_does_not_reuse_longer_bucket_test() {
  let test_store = new_test_store()
  let assert Ok(hourly) =
    glimit.new()
    |> glimit.per_hour(1000)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build
  let assert Ok(combined) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.per_hour(1000)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(set_now(hourly, 0), "id") |> should.be_ok

  hits_at(combined, [0, 0])
  |> should.equal([True, False])
}

pub fn rate_functions_only_run_for_new_buckets_test() {
  let rate_calls = process.new_subject()
  let burst_calls = process.new_subject()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second_fn(fn(id) {
      process.send(rate_calls, id)
      2
    })
    |> glimit.burst_limit_fn(fn(id) {
      process.send(burst_calls, id)
      2
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.be_ok
  glimit.hit(limiter, "a") |> should.equal(Error(glimit.RateLimited))

  process.receive(rate_calls, 100) |> should.equal(Ok("a"))
  process.receive(rate_calls, 0) |> should.be_error
  process.receive(burst_calls, 100) |> should.equal(Ok("a"))
  process.receive(burst_calls, 0) |> should.be_error
}

pub fn rate_function_panic_does_not_affect_existing_bucket_test() {
  let test_store = new_test_store()
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build
  let assert Ok(panicking) =
    glimit.new()
    |> glimit.per_second_fn(fn(_) { panic as "boom" })
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(set_now(limiter, 0), "id") |> should.be_ok
  glimit.hit(set_now(panicking, 0), "id")
  |> should.equal(Error(glimit.RateLimited))
}

pub fn panicking_burst_function_keeps_existing_buckets_test() {
  let test_store = new_test_store()
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.per_hour(100)
    |> glimit.burst_limit_fn(fn(_) { panic as "boom" })
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  let assert Ok(existing) = bucket.new_with_period(1, 1, 1000)
  let assert Ok(_) = test_store.lock_and_get("glimit:\"id\":1000")
  let assert Ok(_) =
    test_store.set_and_unlock("glimit:\"id\":1000", existing, 60)

  let limiter = set_now(limiter, 0)
  glimit.hit(limiter, "id") |> should.be_ok
  glimit.hit(limiter, "id") |> should.equal(Error(glimit.RateLimited))
}

pub fn failed_save_returns_unavailable_without_second_unlock_test() {
  let unlocked = process.new_subject()
  let store =
    bucket.Store(
      lock_and_get: fn(_) { Ok(option.None) },
      set_and_unlock: fn(_, _, _) { Error(Nil) },
      unlock: fn(key) {
        process.send(unlocked, key)
        Ok(Nil)
      },
    )

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.store(store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "id") |> should.equal(Error(glimit.Unavailable))
  // `set_and_unlock` releases the lock, which another request may hold by now
  process.receive(unlocked, 0) |> should.be_error

  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)
  func("request") |> should.equal("OK")
}

pub fn panicking_lock_fails_open_test() {
  let store =
    bucket.Store(
      lock_and_get: fn(_) { panic as "pool timeout" },
      set_and_unlock: fn(_, _, _) { Ok(Nil) },
      unlock: fn(_) { Ok(Nil) },
    )

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.store(store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "id") |> should.equal(Error(glimit.StoreLockFailed))
  let func =
    fn(_) { "OK" }
    |> glimit.apply_built(limiter)
  func("request") |> should.equal("OK")
}

pub fn panicking_save_unlocks_and_fails_open_test() {
  let unlocked = process.new_subject()
  let store =
    bucket.Store(
      lock_and_get: fn(_) { Ok(option.None) },
      set_and_unlock: fn(_, _, _) { panic as "pool timeout" },
      unlock: fn(key) {
        process.send(unlocked, key)
        panic as "pool timeout"
      },
    )

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.store(store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "id") |> should.equal(Error(glimit.Unavailable))
  process.receive(unlocked, 100)
  |> should.equal(Ok("glimit:\"id\":1000"))
}

pub fn burst_function_runs_once_per_hit_test() {
  let burst_calls = process.new_subject()

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.per_minute(2)
    |> glimit.per_hour(3)
    |> glimit.burst_limit_fn(fn(id) {
      process.send(burst_calls, id)
      2
    })
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
  process.receive(burst_calls, 100) |> should.equal(Ok("a"))
  process.receive(burst_calls, 0) |> should.be_error
}

pub fn partly_failed_save_returns_unavailable_test() {
  let test_store = new_test_store()
  let failing_store =
    bucket.Store(..test_store, set_and_unlock: fn(key, state, ttl) {
      case string.ends_with(key, ":3600000") {
        True -> Error(Nil)
        False -> test_store.set_and_unlock(key, state, ttl)
      }
    })

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.per_hour(3)
    |> glimit.store(failing_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(set_now(limiter, 0), "id")
  |> should.equal(Error(glimit.Unavailable))
}

pub fn failed_save_keeps_rejection_test() {
  let empty_bucket =
    bucket.BucketState(
      max_token_count: 1,
      token_rate: 1,
      token_count: 0.0,
      last_update: option.Some(0),
      refill_period_ms: 1000,
    )
  let store =
    bucket.Store(
      lock_and_get: fn(_) { Ok(option.Some(empty_bucket)) },
      set_and_unlock: fn(_, _, _) { Error(Nil) },
      unlock: fn(_) { Ok(Nil) },
    )

  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.store(store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(set_now(limiter, 0), "id")
  |> should.equal(Error(glimit.RateLimited))
}

pub fn limiters_without_key_prefix_share_a_bucket_test() {
  let test_store = new_test_store()
  let builder =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
  let assert Ok(first) = glimit.build(builder)
  let assert Ok(second) = glimit.build(builder)

  glimit.hit(set_now(first, 0), "id") |> should.be_ok
  glimit.hit(set_now(second, 0), "id")
  |> should.equal(Error(glimit.RateLimited))
}

pub fn key_prefix_separates_limiters_test() {
  let test_store = new_test_store()
  let builder =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.store(test_store)
    |> glimit.identifier(fn(_) { "id" })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
  let assert Ok(uploads) =
    builder |> glimit.key_prefix("uploads") |> glimit.build
  let assert Ok(downloads) =
    builder |> glimit.key_prefix("downloads") |> glimit.build

  glimit.hit(set_now(uploads, 0), "id") |> should.be_ok
  glimit.hit(set_now(downloads, 0), "id") |> should.be_ok
  glimit.hit(set_now(uploads, 0), "id")
  |> should.equal(Error(glimit.RateLimited))

  let assert Ok(option.Some(_)) =
    test_store.lock_and_get("glimit:uploads:\"id\":1000")
}

pub fn key_prefix_remove_test() {
  let assert Ok(limiter) =
    glimit.new()
    |> glimit.per_second(1)
    |> glimit.per_hour(2)
    |> glimit.key_prefix("uploads")
    |> glimit.identifier(fn(x) { x })
    |> glimit.on_limit_exceeded(fn(_) { "Stop!" })
    |> glimit.build

  glimit.hit(limiter, "a") |> should.be_ok
  glimit.get_count(limiter) |> should.equal(2)
  glimit.remove(limiter, "a")
  glimit.get_count(limiter) |> should.equal(0)
}

fn hits_at(limiter: glimit.RateLimiter(a, b, String), times: List(Int)) {
  list.map(times, fn(now) {
    case glimit.hit(set_now(limiter, now), "id") {
      Ok(Nil) -> True
      Error(_) -> False
    }
  })
}
