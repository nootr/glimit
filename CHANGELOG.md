# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]


## 1.2.0 - 2026-03-03

### Added

- `max_idle(seconds)` builder function to configure the idle eviction threshold (default 60s). Pass `0` to disable idle eviction. Useful when `burst_limit` is much larger than `per_second` — e.g., `burst_limit=1000, per_second=1` needs ~1000s to refill, so the default 60s idle eviction would discard partially-refilled buckets prematurely.
- Idle eviction for periodic sweep: buckets inactive for longer than the idle threshold are now removed even if not full, preventing unbounded memory growth from high-cardinality identifier spaces.
- Security warning about `X-Forwarded-For` spoofability in wisp example.

### Fixed

- Fixed `burst_limit` doc comment incorrectly describing it as "per second" instead of "per burst".
- Documented that `per_second_fn` and `burst_limit_fn` are evaluated once at bucket creation, not on every hit.


## 1.1.1 - 2026-03-03

### Fixed

- Protected rate limiter actor from crashing user-provided callbacks. A panicking `per_second` or `burst_limit` callback now returns `Unavailable` instead of killing the actor for all identifiers.
- Switched from wall-clock time (`os:timestamp()`) to monotonic time (`erlang:monotonic_time/1`). Prevents NTP clock jumps from bypassing rate limits and eliminates backward clock jump bucket freezes.


## 1.1.0 - 2026-03-03

### Changed

- Consolidated per-identifier OTP actors into a single rate limiter actor. Each hit is now one message instead of two, reducing overhead.
- Renamed internal modules: `registry` → `rate_limiter`, `rate_limiter` → `bucket`.
- Invalid rate limit config now returns `Unavailable` instead of creating a zombie bucket.
- `set_now` (test helper) is now synchronous.

### Fixed

- Fixed stale documentation references to "distributed" architecture and "registry" naming.


## 1.0.0 - 2026-03-02

### Added

- `apply2`, `apply3`, `apply4` to rate-limit multi-argument functions directly.
- Performance section in README documenting memory usage and fail-open behavior.


## 0.4.1 - 2026-03-02

### Fixed

- Eliminated all panic paths — public APIs (`hit`, `has_full_bucket`, `get_or_create`, `get_all`, `remove`, `sweep`) return `Result` instead of panicking on dead/timed-out actors.
- `apply_built` now fails open when a rate limiter actor dies mid-request.
- `remove` shuts down the actor process before deleting from the registry, preventing orphaned processes.
- Fixed operator precedence bug where `token_count` could exceed `max_token_count` after refill.
- Fixed sub-second remainder loss in `last_update` by advancing by consumed time rather than jumping to `now`.
- `refill_bucket` clamps `time_diff` to non-negative to handle NTP clock adjustments.
- `rate_limiter.new` validates `per_second > 0` and `burst_limit > 0`.

### Changed

- Sweep processes entries in batches of 50 with self-messaging between batches, allowing other registry operations to interleave.
- Reduced sweep per-call timeout from 100ms to 10ms.
- Switched internal time from seconds to milliseconds for smooth sub-second rate limiting.
- Updated examples for mist 5.x and wisp 2.x.


## 0.4.0 - 2026-02-27

### Breaking changes

- Updated `gleam_otp` to 1.x and `gleam_erlang` to 1.x.
- Updated minimum `gleam_stdlib` to 0.60.0.
- Requires Gleam >= 1.14.0.

### Changed

- Migrated actor code to the new builder API (`actor.new` / `actor.on_message` / `actor.start`).
- Replaced `gleam/otp/task` with `process.spawn`.
- Updated CI to Gleam 1.14.0 and OTP 27.

Thanks to [@tylerbutler](https://github.com/tylerbutler) for the contribution!


## 0.3.0 - 2024-09-09

### Breaking changes

- Removed the need for `glimit.build()` and `glimit.try_build()` functions. Now, the `glimit.apply()` function can be used directly with the limiter configuration.

### Added

- Added the `per_second_fn` and `burst_limit_fn` functions to dynamically set limits based on the identifier.
- Added examples to the `examples/` directory.
- Added examples to the documentation.


## 0.2.0 - 2024-09-07

### Breaking changes

- Refactored the code to use a Token Bucket algorithm instead of a Sliding Window algorithm. This has removed some of the library features/API, such as `glimit.applyX` to apply a rate limiter on a function with multiple arguments.

### Added

- Added a `burst_limit` setting to the limiter configuration. This setting allows the user to set the maximum number of tokens that the bucket can hold.


## 0.1.3 - 2024-09-04

### Added

- Added `apply2`, `apply3` and `apply4` functions to apply a limiter to a function with 2, 3 and 4 arguments respectively.
- Added `try_build` function which returns a `Result` instead of panicking.
- Added this `CHANGELOG.md` file!
