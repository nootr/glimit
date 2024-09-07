import gleeunit/should
import glimit/rate_limiter

pub fn rate_limiter_test() {
  let assert Ok(limiter) = rate_limiter.new(2, 2)

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
