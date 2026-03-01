import gleam/erlang/process
import gleam/option.{None}
import gleeunit/should
import glimit/rate_limiter
import glimit/registry

pub fn same_id_same_actor_test() {
  let assert Ok(registry) = registry.new(fn(_) { 2 }, fn(_) { 2 })
  let assert Ok(rate_limiter) = registry |> registry.get_or_create("🚀")
  let assert Ok(same_rate_limiter) = registry |> registry.get_or_create("🚀")

  rate_limiter
  |> should.equal(same_rate_limiter)
}

pub fn other_id_other_actor_test() {
  let assert Ok(registry) = registry.new(fn(_) { 2 }, fn(_) { 2 })
  let assert Ok(rate_limiter) = registry |> registry.get_or_create("🚀")
  let assert Ok(same_rate_limiter) = registry |> registry.get_or_create("💫")

  rate_limiter
  |> should.not_equal(same_rate_limiter)
}

pub fn sweep_full_bucket_test() {
  let assert Ok(registry) = registry.new(fn(_) { 2 }, fn(_) { 2 })
  let assert Ok(rate_limiter) = registry |> registry.get_or_create("🚀")

  registry |> registry.sweep(None)

  let assert Ok(new_rate_limiter) = registry |> registry.get_or_create("🚀")

  rate_limiter
  |> should.not_equal(new_rate_limiter)
}

pub fn sweep_not_full_bucket_test() {
  let assert Ok(registry) = registry.new(fn(_) { 2 }, fn(_) { 2 })
  let assert Ok(rate_limiter) = registry |> registry.get_or_create("🚀")

  let _ = rate_limiter |> rate_limiter.hit
  registry |> registry.sweep(None)

  let assert Ok(new_rate_limiter) = registry |> registry.get_or_create("🚀")

  rate_limiter
  |> should.equal(new_rate_limiter)
}

pub fn sweep_after_long_time_test() {
  let assert Ok(registry) = registry.new(fn(_) { 2 }, fn(_) { 2 })
  let assert Ok(rate_limiter) = registry |> registry.get_or_create("🚀")

  rate_limiter |> rate_limiter.set_now(0)
  let _ = rate_limiter |> rate_limiter.hit
  let _ = rate_limiter |> rate_limiter.hit
  let _ = rate_limiter |> rate_limiter.hit
  rate_limiter |> rate_limiter.set_now(1000)

  registry |> registry.sweep(None)

  let assert Ok(new_rate_limiter) = registry |> registry.get_or_create("🚀")

  rate_limiter
  |> should.not_equal(new_rate_limiter)
}

pub fn sweep_empty_registry_test() {
  let assert Ok(registry) = registry.new(fn(_) { 2 }, fn(_) { 2 })
  // Sweep with no entries should not crash
  registry |> registry.sweep(None)
}

pub fn sweep_mixed_buckets_test() {
  let assert Ok(registry) = registry.new(fn(_) { 2 }, fn(_) { 2 })
  let assert Ok(rl_a) = registry |> registry.get_or_create("a")
  let assert Ok(rl_b) = registry |> registry.get_or_create("b")
  let assert Ok(rl_c) = registry |> registry.get_or_create("c")

  // Hit "b" so it's not full
  let _ = rl_b |> rate_limiter.hit

  registry |> registry.sweep(None)

  let assert Ok(new_a) = registry |> registry.get_or_create("a")
  let assert Ok(new_b) = registry |> registry.get_or_create("b")
  let assert Ok(new_c) = registry |> registry.get_or_create("c")

  // "a" and "c" were full → swept → new actors
  rl_a |> should.not_equal(new_a)
  rl_c |> should.not_equal(new_c)
  // "b" was active → kept
  rl_b |> should.equal(new_b)
}

pub fn sweep_dead_rate_limiter_test() {
  let assert Ok(registry) = registry.new(fn(_) { 2 }, fn(_) { 2 })
  let assert Ok(rl) = registry |> registry.get_or_create("dead")

  // Shut down the rate limiter process and wait for confirmed death
  let assert Ok(pid) = process.subject_owner(rl)
  let monitor = process.monitor(pid)
  rate_limiter.shutdown(rl)
  let _ =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 1000)

  // Sweep should remove the dead entry via safe_call error path
  registry |> registry.sweep(None)

  let assert Ok(new_rl) = registry |> registry.get_or_create("dead")
  rl |> should.not_equal(new_rl)
}

pub fn sweep_all_active_test() {
  let assert Ok(registry) = registry.new(fn(_) { 2 }, fn(_) { 2 })
  let assert Ok(rl_a) = registry |> registry.get_or_create("a")
  let assert Ok(rl_b) = registry |> registry.get_or_create("b")
  let assert Ok(rl_c) = registry |> registry.get_or_create("c")

  // Hit all so none are full
  let _ = rl_a |> rate_limiter.hit
  let _ = rl_b |> rate_limiter.hit
  let _ = rl_c |> rate_limiter.hit

  registry |> registry.sweep(None)

  let assert Ok(new_a) = registry |> registry.get_or_create("a")
  let assert Ok(new_b) = registry |> registry.get_or_create("b")
  let assert Ok(new_c) = registry |> registry.get_or_create("c")

  // All were active → all kept
  rl_a |> should.equal(new_a)
  rl_b |> should.equal(new_b)
  rl_c |> should.equal(new_c)
}

pub fn sweep_get_or_create_after_sweep_test() {
  let assert Ok(registry) = registry.new(fn(_) { 2 }, fn(_) { 2 })
  let assert Ok(rl_keep) = registry |> registry.get_or_create("keep")
  let assert Ok(rl_remove) = registry |> registry.get_or_create("remove")

  // Hit "keep" so it's active
  let _ = rl_keep |> rate_limiter.hit

  registry |> registry.sweep(None)

  // "remove" was full → swept
  let assert Ok(new_remove) = registry |> registry.get_or_create("remove")
  rl_remove |> should.not_equal(new_remove)
  // "keep" was active → kept
  let assert Ok(new_keep) = registry |> registry.get_or_create("keep")
  rl_keep |> should.equal(new_keep)

  // New "remove" limiter has fresh tokens → hit should succeed
  let assert Ok(Nil) = new_remove |> rate_limiter.hit
  let assert Ok(Nil) = new_remove |> rate_limiter.hit
}
