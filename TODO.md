# Production Hardening TODO

## Critical — Can crash production callers

- [x] **Extract `safe_call` and use in all public call sites** — `rate_limiter.hit`, `registry.get_or_create`, `get_all`, `remove`, and `sweep` all use `actor.call` which panics on dead/timed-out actors. Extract `safe_call` to a shared module and use it everywhere.
- [x] **Fix `remove` to shut down the removed actor** — `dict.delete` orphans the process. Call `rate_limiter.shutdown` before removing.

## High — Degrades reliability

- [x] **Add input validation for `per_second` and `burst_limit`** — Zero, negative, or absurd values are silently accepted. Validate in `rate_limiter.new` and/or `build`.
- [x] **Clamp `time_diff` to non-negative** — Clock adjustments (NTP) can make `time_diff` negative, draining all tokens instantly. Use `int.max(0, time_diff)`.
- [ ] **Unbounded registry growth** — Each unique identifier spawns an actor. Add a max registry size or expose size for monitoring.
- [ ] **Sweep blocks registry for O(n)** — Synchronous `safe_call` per entry. Consider async status reporting, batched sweeps, or a lower sweep-specific timeout.

## Medium — Operational quality

- [ ] **Add observability** — Registry size function, sweep statistics, request counters.
- [ ] **Switch to millisecond time resolution** — Current second-resolution causes lumpy refills and prevents sub-second rate limiting.
- [ ] **Add graceful shutdown** — No way to stop the registry and all child actors cleanly.
- [x] **Fix `token_count` match to use `> 0`** — The `_` pattern in `hit` matches negative numbers, allowing hits when `token_count < 0`.
- [ ] **Remove unused `_interval_secs` param** on `sweep` — Dead parameter that confuses users.
