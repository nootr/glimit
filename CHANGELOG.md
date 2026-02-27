# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]


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
