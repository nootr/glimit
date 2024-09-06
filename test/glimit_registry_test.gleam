import gleeunit/should
import glimit/rate_limiter
import glimit/registry

pub fn same_id_same_actor_test() {
  let registry = case registry.new(2, 2) {
    Ok(registry) -> registry
    Error(_) -> {
      panic as "Should be able to create a new registry"
    }
  }

  let assert Ok(rate_limiter) = registry |> registry.get_or_create("🚀")
  let assert Ok(same_rate_limiter) = registry |> registry.get_or_create("🚀")

  rate_limiter
  |> should.equal(same_rate_limiter)
}

pub fn other_id_other_actor_test() {
  let registry = case registry.new(2, 2) {
    Ok(registry) -> registry
    Error(_) -> {
      panic as "Should be able to create a new registry"
    }
  }

  let assert Ok(rate_limiter) = registry |> registry.get_or_create("🚀")
  let assert Ok(same_rate_limiter) = registry |> registry.get_or_create("💫")

  rate_limiter
  |> should.not_equal(same_rate_limiter)
}

pub fn sweep_full_bucket_test() {
  let registry = case registry.new(2, 2) {
    Ok(registry) -> registry
    Error(_) -> {
      panic as "Should be able to create a new registry"
    }
  }

  let assert Ok(rate_limiter) = registry |> registry.get_or_create("🚀")
  registry |> registry.sweep
  let assert Ok(new_rate_limiter) = registry |> registry.get_or_create("🚀")

  rate_limiter
  |> should.not_equal(new_rate_limiter)
}

pub fn sweep_not_full_bucket_test() {
  let registry = case registry.new(2, 2) {
    Ok(registry) -> registry
    Error(_) -> {
      panic as "Should be able to create a new registry"
    }
  }

  let assert Ok(rate_limiter) = registry |> registry.get_or_create("🚀")

  let _ = rate_limiter |> rate_limiter.hit
  registry |> registry.sweep

  let assert Ok(new_rate_limiter) = registry |> registry.get_or_create("🚀")

  rate_limiter
  |> should.equal(new_rate_limiter)
}
