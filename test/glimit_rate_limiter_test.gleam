import gleeunit/should
import glimit/rate_limiter

pub fn rate_limiter_test() {
  let limiter = case rate_limiter.new(2, 2) {
    Ok(limiter) -> limiter
    Error(_) -> panic as "Should be able to create rate limiter"
  }

  limiter
  |> rate_limiter.hit
  |> should.be_ok

  limiter
  |> rate_limiter.hit
  |> should.be_ok

  limiter
  |> rate_limiter.hit
  |> should.be_error
}
