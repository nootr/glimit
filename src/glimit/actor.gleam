//// The rate limiter actor.
////

import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import glimit/utils

/// The messages that the actor can receive.
///
pub type Message(id) {
  /// Stop the actor.
  Shutdown

  /// Mark a hit for a given identifier.
  Hit(identifier: id, reply_with: Subject(Result(Nil, Nil)))
}

/// The actor state.
///
type State(a, b, id) {
  RateLimiterState(
    hit_log: dict.Dict(id, List(Int)),
    per_second: Option(Int),
    per_minute: Option(Int),
    per_hour: Option(Int),
  )
}

fn handle_message(
  message: Message(id),
  state: State(a, b, id),
) -> actor.Next(Message(id), State(a, b, id)) {
  case message {
    Shutdown -> actor.Stop(process.Normal)
    Hit(identifier, client) -> {
      // Update hit log
      let timestamp = utils.now()
      let hits =
        state.hit_log
        |> dict.get(identifier)
        |> result.unwrap([])
        |> list.filter(fn(hit) { hit >= timestamp - 60 * 60 })
        |> list.append([timestamp])
      let hit_log =
        state.hit_log
        |> dict.insert(identifier, hits)
      let state = RateLimiterState(..state, hit_log: hit_log)

      // Check rate limits
      // TODO: optimize into a single loop
      let hits_last_hour = hits |> list.length()

      let hits_last_minute =
        hits
        |> list.filter(fn(hit) { hit >= timestamp - 60 })
        |> list.length()

      let hits_last_second =
        hits
        |> list.filter(fn(hit) { hit >= timestamp - 1 })
        |> list.length()

      let limit_reached = {
        case state.per_hour {
          Some(limit) -> hits_last_hour > limit
          None -> False
        }
        || case state.per_minute {
          Some(limit) -> hits_last_minute > limit
          None -> False
        }
        || case state.per_second {
          Some(limit) -> hits_last_second > limit
          None -> False
        }
      }

      case limit_reached {
        True -> process.send(client, Error(Nil))
        False -> process.send(client, Ok(Nil))
      }

      actor.continue(state)
    }
  }
}

/// Create a new rate limiter actor.
///
pub fn new(
  per_second: Option(Int),
  per_minute: Option(Int),
  per_hour: Option(Int),
) -> Result(Subject(Message(id)), Nil) {
  let state =
    RateLimiterState(
      hit_log: dict.new(),
      per_second: per_second,
      per_minute: per_minute,
      per_hour: per_hour,
    )
  actor.start(state, handle_message)
  |> result.nil_error
}

/// Log a hit for a given identifier.
///
pub fn hit(subject: Subject(Message(id)), identifier: id) -> Result(Nil, Nil) {
  actor.call(subject, Hit(identifier, _), 10)
}

/// Stop the actor.
///
pub fn stop(subject: Subject(Message(id))) {
  actor.send(subject, Shutdown)
}
