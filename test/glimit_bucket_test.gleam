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
