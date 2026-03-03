import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleeunit/should
import glimit/utils

pub fn now_returns_milliseconds_test() {
  let t1 = utils.now()
  // Should be a reasonable epoch milliseconds value (after 2024-01-01)
  let assert True = t1 > 1_704_067_200_000
  // Two calls should be monotonically non-decreasing
  let t2 = utils.now()
  let assert True = t2 >= t1
}

type TimeoutMsg {
  Ping(reply_with: Subject(Nil))
}

pub fn rescue_returns_ok_on_success_test() {
  utils.rescue(fn() { 42 })
  |> should.equal(Ok(42))
}

pub fn rescue_returns_error_on_crash_test() {
  utils.rescue(fn() { panic as "boom" })
  |> should.equal(Error(Nil))
}

pub fn safe_call_timeout_test() {
  // Start an actor that ignores all messages (never replies)
  let assert Ok(started) =
    actor.new(Nil)
    |> actor.on_message(fn(state: Nil, _msg: TimeoutMsg) {
      actor.continue(state)
    })
    |> actor.start
  let subject = started.data
  utils.safe_call(subject, Ping, 50)
  |> should.be_error
}
