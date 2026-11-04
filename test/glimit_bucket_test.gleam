import gleeunit/should
import glimit/bucket

pub fn new_valid_test() {
  bucket.new(2, 2) |> should.be_ok
}

pub fn new_invalid_max_token_count_test() {
  bucket.new(0, 2) |> should.be_error
  bucket.new(-1, 2) |> should.be_error
}

pub fn new_invalid_token_rate_test() {
  bucket.new(2, 0) |> should.be_error
  bucket.new(2, -1) |> should.be_error
}

pub fn hit_test() {
  let assert Ok(b) = bucket.new(2, 2)

  let #(result, b) = bucket.hit(b, 0)
  result |> should.be_ok

  let #(result, b) = bucket.hit(b, 0)
  result |> should.be_ok

  let #(result, _b) = bucket.hit(b, 0)
  result |> should.be_error
}

pub fn hit_refill_test() {
  let assert Ok(b) = bucket.new(2, 2)

  let #(_, b) = bucket.hit(b, 0)
  let #(_, b) = bucket.hit(b, 0)
  let #(result, b) = bucket.hit(b, 0)
  result |> should.be_error

  // After 1 second, 2 tokens refill
  let #(result, b) = bucket.hit(b, 1000)
  result |> should.be_ok
  let #(result, _) = bucket.hit(b, 1000)
  result |> should.be_ok
}

pub fn is_full_test() {
  let assert Ok(b) = bucket.new(2, 2)
  bucket.is_full(b, 0) |> should.be_true

  let #(_, b) = bucket.hit(b, 0)
  bucket.is_full(b, 0) |> should.be_false
}

pub fn backward_time_test() {
  let assert Ok(b) = bucket.new(2, 1)

  let #(_, b) = bucket.hit(b, 1000)
  // Go backwards — time_diff clamped to 0, no tokens added
  let #(result, b) = bucket.hit(b, 500)
  result |> should.be_ok
  let #(result, _) = bucket.hit(b, 500)
  result |> should.be_error
}

pub fn new_with_period_invalid_period_test() {
  bucket.new_with_period(2, 2, 0) |> should.be_error
  bucket.new_with_period(2, 2, -1) |> should.be_error
}

pub fn new_is_per_second_test() {
  let assert Ok(b) = bucket.new(2, 2)
  b.refill_period_ms |> should.equal(1000)
}

pub fn hit_refill_per_hour_test() {
  // 20 tokens per hour: one token every 180 seconds
  let assert Ok(b) = bucket.new_with_period(20, 20, 3_600_000)

  let b = drain(b, 0, 20)
  let #(result, b) = bucket.hit(b, 0)
  result |> should.be_error

  let #(result, b) = bucket.hit(b, 179_999)
  result |> should.be_error

  let #(result, b) = bucket.hit(b, 180_000)
  result |> should.be_ok
  let #(result, _) = bucket.hit(b, 180_000)
  result |> should.be_error
}

pub fn compute_ttl_per_second_test() {
  let assert Ok(b) = bucket.new(10, 5)
  bucket.compute_ttl(b) |> should.equal(60)

  let assert Ok(b) = bucket.new(1000, 1)
  bucket.compute_ttl(b) |> should.equal(2000)
}

pub fn compute_ttl_per_hour_test() {
  // Refilling 20 tokens at 20 per hour takes an hour; TTL is twice that
  let assert Ok(b) = bucket.new_with_period(20, 20, 3_600_000)
  bucket.compute_ttl(b) |> should.equal(7200)
}

pub fn to_pairs_from_pairs_roundtrip_per_hour_test() {
  let assert Ok(b) = bucket.new_with_period(20, 20, 3_600_000)
  let #(_, b) = bucket.hit(b, 5000)
  let assert Ok(restored) = bucket.from_pairs(bucket.to_pairs(b))
  restored |> should.equal(b)
}

pub fn from_pairs_without_period_is_per_second_test() {
  // Buckets serialized before refill periods existed have no "rp" field
  let pairs = [#("tc", "5.0"), #("lu", "1000"), #("mt", "10"), #("tr", "5")]
  let assert Ok(restored) = bucket.from_pairs(pairs)
  restored.refill_period_ms |> should.equal(1000)
  restored.token_rate |> should.equal(5)
}

fn drain(b: bucket.BucketState, now: Int, count: Int) -> bucket.BucketState {
  case count {
    0 -> b
    _ -> {
      let #(result, b) = bucket.hit(b, now)
      result |> should.be_ok
      drain(b, now, count - 1)
    }
  }
}
