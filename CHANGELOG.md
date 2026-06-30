# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-07-01

### Added

- Network-level retry with exponential backoff and jitter via `:retry` config option.
  Supports `false` (off), `true` (default 3 retries), or keyword `[max_retries: 3,
base_delay: 100, max_delay: 5000, jitter: true]`. Retries on transport errors,
  5xx, and 429 responses.
- Circuit breaker (`ExNominatim.CircuitBreaker`) — ETS-backed, per-server breaker
  with `:closed` / `:open` / `:half_open` states. Configurable via `:circuit_breaker`
  option (false, true with defaults, or keyword `[threshold: 5, reset_ms: 30_000]`).
  Emits `[:ex_nominatim, :circuit_breaker, :state_change]` telemetry on transitions.
- Concurrency limiter (`ExNominatim.Concurrency`) — ETS-backed semaphore per
  `base_url` via `:max_concurrency` config option (integer or `:infinity`).
- Rate limiting via `ExNominatim.RateLimiter` — zero-dependency, ETS-backed, best-effort.
  `:rate_limit` config option (`:auto` | `true` | `false` | integer).
  - `:auto` (default): 1 req/s enforced for `nominatim.openstreetmap.org`, disabled for other servers.
  - `true`: 1 req/s enforced for all servers.
  - `false`: rate limiting disabled entirely.
  - `integer`: N req/s enforced for all servers (e.g. `rate_limit: 5` for 5 req/s).
- Timeout config via `:timeout` option (integer ms, default 15_000) — maps to
  Req `receive_timeout` and `connect_options`.
- User-Agent config via `:user_agent` option (string, default `"ExNominatim/{version}"`).
- `ExNominatim.stream_many/2` — concurrent batch search via `Task.async_stream`
  with configurable `:max_concurrency`. Returns results as a lazy `Stream`.
- `ExNominatim.healthy?/1` — health check calling `/status`, returns `{:ok, boolean()}`.
- Error caching: `:cache_errors` (boolean, default false) and `:cache_error_ttl`
  (integer ms, default 30_000) for caching API error responses.
- Optional result caching via Cachex v4.x (`:cache` option on all endpoint functions).
  - `ExNominatim.Cache` protocol for custom cache adapters.
  - `ExNominatim.CachexCache` built-in adapter.
  - `ExNominatim.TestCache` for isolated cache testing.
  - Cache key based on endpoint and normalized query parameters.
  - Only successful results cached; errors never cache.
- Telemetry events: `[:ex_nominatim, :request, :stop]`, `[:ex_nominatim, :request, :exception]`,
  `[:ex_nominatim, :cache, :hit]`, `[:ex_nominatim, :cache, :miss]`,
  `[:ex_nominatim, :rate_limit, :deny]`,
  `[:ex_nominatim, :circuit_breaker, :state_change]`,
  `[:ex_nominatim, :request, :retry]`.
- Automatic retry on rate limit: `rate_limit_retry: true` (or integer N max retries).
  Sleeps for `retry_after_ms` and retries the full pipeline (cache check included).
- `ExNominatim.search_one/1` and `search_one!/1` — convenience wrappers returning
  a single result, `%{code: :not_found}`, or `%{code: :multiple_results, count: _}`.
- Custom Req opts via `:req_opts` option — pass any Req option (headers,
  connect_options, receive_timeout, etc.) through to the HTTP client.
- Optional geohash post-processing: `geohash: true` (or integer precision) to
  append a `:geohash` key to results with lat/lon.
- `test_adapter` support for plain plug modules (not just `{Req.Test, name}`),
  enabling cross-process HTTP stubbing for `Task.async_stream` tests.
- Depends on `telemetry ~> 1.0` and optionally `geohash ~> 1.0`.
- `llms.txt` at project root — self-contained AI summary of the library API surface.
- SPDX copyright header to `Report` module.
- Coverage threshold set to 80% in `mix.exs`.
- `config/config.exs` — documented cache configuration defaults.
- Updated `DESIGN.md` with rate limiting architecture, caching, and data flow documentation.

### Changed

- **Breaking**: All error returns now use a consistent shape: `{:error, %{code: atom, descr: string}}`.
  Previously mixed shapes (bare atoms, tagged tuples, structs) have been consolidated into
  a single map pattern. See DESIGN.md for the full mapping.
- **Breaking**: `ExNominatim.default_config/0` expanded with new keys: `:timeout`,
  `:user_agent`, `:retry`, `:circuit_breaker`, `:max_concurrency`, `:cache`,
  `:cache_errors`, `:cache_error_ttl`, `:rate_limit`.
- `Config`-specific keys updated: `:timeout`, `:user_agent`, `:retry`, `:circuit_breaker`,
  `:max_concurrency`, `:cache`, `:cache_errors`, `:cache_error_ttl`, `:rate_limit`,
  `:test_adapter` added to filter list.
- Relaxed Req dependency to `~> 0.5`.

### Testing

- Test suite expanded from 124 to 188 unit tests across 7 test files.
- New test files: `circuit_breaker_test.exs` (13 tests), `concurrency_test.exs`
  (8 tests), `stream_many_test.exs` (5 tests).
- Added `healthy?/1` tests in `client_test.exs`.
- All ETS tables pre-initialized in `setup` blocks where needed to avoid
  ownership races with concurrent task processes.

## [2.1.0] - 2025-05-20

### Changed

- Imported upstream PR (Ko-Fi link removal, sponsor link removal).

## [2.0.0] - 2025-02-21

### Added

- Introduced `Config`-based application configuration with layered precedence.

### Changed

- Overhauled configuration system.

## [1.1.4] - 2024-09-23

### Changed

- Relaxed Req dependency to `0.5+`.

## [1.1.3] - 2024-08-24

### Fixed

- Bug where config-specific keys leaked into GET params.

## [1.1.2] - 2024-08-23

### Fixed

- Application config merge bug.

## [1.1.1] - 2024-08-22

### Changed

- Reverted default API URL to public server.

## [1.1.0] - 2024-08-19

### Added

- `ExNominatim.Report` module for response processing and atomization.
- Configuration system (`ExNominatim.get_config/0`).

## [1.0.0] - 2024-08-15

### Added

- Initial release with all 5 endpoints.
- Struct-per-endpoint params (`SearchParams`, `ReverseParams`, `LookupParams`, `DetailsParams`, `StatusParams`).
- Comprehensive validation pipeline via `ExNominatim.Validations`.
- `ExNominatim.Client` for request preparation and dispatch.
- ExDelegated public API via `ExNominatim` module.

[Unreleased]: https://github.com/waseigo/ex_nominatim/compare/v3.0.0...HEAD
[3.0.0]: https://github.com/waseigo/ex_nominatim/compare/v2.1.0...v3.0.0
[2.1.0]: https://github.com/waseigo/ex_nominatim/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/waseigo/ex_nominatim/compare/v1.1.4...v2.0.0
[1.1.4]: https://github.com/waseigo/ex_nominatim/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/waseigo/ex_nominatim/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/waseigo/ex_nominatim/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/waseigo/ex_nominatim/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/waseigo/ex_nominatim/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/waseigo/ex_nominatim/releases/tag/v1.0.0
