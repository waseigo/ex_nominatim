---
version: alpha
name: ExNominatim
description: A full-featured Elixir client for the OpenStreetMap Nominatim API V1 — stateless, validated at the boundary, with structured error reporting.
---

# ExNominatim — Design Document

## Overview

ExNominatim is a stateless Elixir client for the [Nominatim API V1](https://nominatim.org/release-docs/latest/api/Overview/) that wraps all five public endpoints (`/search`, `/reverse`, `/lookup`, `/details`, `/status`) in a validated, pipeline-based API. Its primary architectural characteristic is **validate-then-dispatch**: every request is parsed into a typed struct, validated against the API specification (including cross-field intent checks), and only then converted to an HTTP request. The library prevents invalid API calls at the boundary and returns structured `{:ok, map}` / `{:error, map}` tuples rather than raw HTTP responses.

## Architecture

```
┌───────────────────────────────────────────────────────────────────────┐
│  Consumer (ExNominatim.search/1, .reverse/1, ...)                     │
│    opts = [q: "Athens", limit: 5, cache: ExNominatim.CachexCache]     │
└──────────────────────────┬────────────────────────────────────────────┘
                           │ delegate
                           ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  ExNominatim.Client.generic/2                                              │
│    1. make_new_struct/2  → merge config layers, build struct               │
│    2. Validations.validate/1 → per-field + intent checks                   │
│    3. cache_get(cache, key) → {:ok, data} | :miss                         │
│       │  ← cache hit → return {:ok, data}                                 │
│       │  ← cache miss → continue                                          │
│    4. check_rate_limit(config_opts) → :ok | {:error, {:rate_limited, _}}  │
│       │  ← rate limited → return error                                    │
│       │  ← allowed → continue                                             │
│    5. Client.prepare/3   → build Req.Request (URL, UA, params)             │
│    6. Req.request/1      → HTTP GET                                        │
│    7. Report.process/1   → detect errors, normalize body                   │
│    8. Report.atomize/1   → binary keys → atom keys                         │
│    9. cache_store(cache, key, result) → only on success                   │
└──────────────────────────┬─────────────────────────────────────────────────┘
                           │
        ┌───────────────────┼──────────────┬──────────────┬──────────────────┐
        ▼                   ▼              ▼              ▼                  ▼
 ┌───────────┐     ┌────────────┐     ┌──────────┐   ┌───────────┐   ┌──────────────┐
 │  Params   │     │ Validations│     │  Report  │   │   Cache   │   │ RateLimiter  │
 │ Structs   │     │            │     │          │   │  Protocol │   │ (ETS-backed) │
 │ (5 mod.)  │     │            │     │          │   │ ┌───────┐ │   │              │
 └───────────┘     └────────────┘     └──────────┘   │ │Cachex │ │   └──────────────┘
                                                     │ │Adapter│ │
                                                     │ ├───────┤ │
                                                     │ │ Test  │ │
                                                     │ │Adapter│ │
                                                     │ └───────┘ │
                                                     └───────────┘
```

## Module Responsibilities

### ExNominatim (`lib/ex_nominatim.ex`)

The public API surface. Delegates all calls to `ExNominatim.Client` and provides `get_config/0` to inspect merged configuration. Holds the default config (public server URL, `force: false`, `process: true`, `atomize: true`, per-endpoint format overrides). Documents the configuration precedence: `default < :all < endpoint-specific < opts`.

### ExNominatim.Client (`lib/client.ex`)

The pipeline orchestrator. Contains `generic/2` which sequences the full request lifecycle: struct creation → validation → **cache lookup** → **rate limit check** → HTTP preparation → dispatch → report processing → **cache store**. The `cache_get/2` and `cache_store/2` helpers interact with any module implementing the `ExNominatim.Cache` protocol. The `check_rate_limit/1` helper delegates to `ExNominatim.RateLimiter` based on the `:rate_limit` config option. Also houses `prepare/3` (builds `Req.Request` with User-Agent header, URL validation, query param filtering) and `new/3` (validates required fields, constructs struct from merged opts). The `get_module/1` helper resolves endpoint atoms to params modules via `Module.safe_concat/1`.

### ExNominatim.Validations (`lib/validations.ex`)

The validation engine. Every field has a `valid?/2` clause that checks type, range, format, and membership against API specs. Cross-field intent validation (`verify_intent/1`) enforces mutually exclusive modes (e.g., freeform `:q` vs. structured search fields; `:place_id` vs. `:osmtype`/`:osmid`). Errors accumulate in `%{valid?: false, errors: [{key, message}]}`. Also provides `explain_fields/0` and `sanitize_comma_separated_strings/1`.

### ExNominatim.Report (`lib/report.ex`)

Response normalization. `process/1` pattern-matches on `Req.Response` to detect HTTP-level and API-level errors (embedded `"error"` key in JSON or `<error>` in XML). `atomize/1` recursively converts binary map keys to atoms (with dash→underscore normalization), handling nested maps, lists, and structs.

### ExNominatim.Cache Protocol (`lib/cache.ex`, `lib/cache_atom.ex`)

Defines the `get/2`, `put/3`, `del/2` protocol that any cache adapter must implement. Ships with two implementations:

- `ExNominatim.CachexCache` — wraps Cachex `Actions.get/3`, `Actions.put/4`, `Actions.del/2` for production use.
- `for: Atom` — delegates to a module's `get/1`, `put/3`, `del/2` via `apply/3` at runtime, enabling lightweight test adapters like `ExNominatim.TestCache`.

The protocol is designed so that `cache: nil` (default) skips all cache operations with `:miss` in `generic/2`, imposing zero overhead when caching is not configured.

### Params Structs (`lib/client/*_params.ex`)

Five modules — `SearchParams`, `ReverseParams`, `LookupParams`, `DetailsParams`, `StatusParams` — each defining a `defstruct` with endpoint-specific fields plus the shared `valid?` and `errors` validation accumulator. Each declares `@required` fields and delegates `new/1` to `Client.new/3`.

### ExNominatim.RateLimiter (`lib/rate_limiter.ex`)

Best-effort per-server rate limiter backed by an ETS named table with `write_concurrency: true`. Tracks the last request timestamp per `base_url` and rejects requests that arrive before the minimum interval (1000 ms) has elapsed. Created lazily on first use — no supervision tree or application callback required. Provides `check/2`, `clear/0` (for testing), and `public_server?/1` for the `:auto` detection logic.

## Data Flow

```
Input:  opts = [q: "Athens", limit: 5, cache: ExNominatim.CachexCache]

Step 1 — Config merge (Client.make_new_struct/2)
  default_config()
  |> merge app_config[:all]
  |> merge app_config[:search]
  |> merge opts
  → %{q: "Athens", limit: 5, format: "geocodejson", base_url: "...", cache: ExNominatim.CachexCache}

Step 2 — Struct construction (Client.new/3)
  SearchParams.new(merged_opts)
  → {:ok, %SearchParams{q: "Athens", limit: 5, valid?: nil, errors: []}}

Step 3 — Validation (Validations.validate/1)
  validate_all_fields/1  → each field checked by valid?/2
  validate_format/1      → format allowed for endpoint?
  verify_intent/1         → q XOR structured fields
  sanitize_comma_separated_strings/1
  → {:ok, %SearchParams{valid?: true, errors: []}}

Step 3b — Cache lookup (Client.cache_get/2)
  cache_key(action, struct)  → "ex_nominatim:search:q=Athens&limit=1&format=json"
  cache_get(cache, key)
  → :miss  (or {:ok, data} → return immediately, skip HTTP)

Step 3c — Rate limit check (Client.check_rate_limit/1)
  rate_limit = :auto, base_url = "https://nominatim.openstreetmap.org"
  → public_server? → true → RateLimiter.check(url, 1000) → :ok
  (or {:error, {:rate_limited, retry_after_ms}} → return error)

Step 4 — HTTP preparation (Client.prepare/3)
  validate_url(base_url)  → :ok
  Req.new(base_url:, method: :get, headers: %{user_agent: "ExNominatim/2.4.0"}, cache: :stub_only)
  |> Req.merge(url: "/search")
  |> Req.merge(params: filtered_params)  # drops nil, valid?, errors, config keys
  → {:ok, %Req.Request{}}

Step 5 — HTTP dispatch (Req.request/1)
  → {:ok, %Req.Response{status: 200, body: [%{...}]}}

Step 6 — Report processing
  Report.process({:ok, resp})
  → status 200 + no "error" key → {:ok, %{status: 200, body: [...]}}
  Report.atomize(result)  # if atomize: true
  → {:ok, %{status: 200, body: [%{"place_id" => 123} |> atomize ...]}}

Step 7 — Cache store (Client.cache_store/3)
  Only on {:ok, _} result.
  cache_store(cache, key, {:ok, data})
  → Cachex.put(:ex_nominatim, key, data, ttl: 86_400_000)
  Errors (non-200, API error, HTTP failure) are never cached.
```

**Short-circuit points:**

- Step 1: returns `{:error, :improper_list}` if opts is not a keyword list
- Step 1: returns `{:error, {:extraneous_fields, [...]}}` if unknown keys for endpoint
- Step 2: returns `{:error, {:missing_query_params, [...]}}` if required fields absent
- Step 3: returns `{:error, %SearchParams{valid?: false, errors: [...]}}` on validation failure
- Step 3b: cache hit → return immediately, no HTTP call (only when `cache` is set)
- Step 3c: rate limited → returns `{:error, {:rate_limited, retry_after_ms}}` (on cache miss only)
- Step 5: returns `{:error, :missing_scheme}` / `:missing_host` / `:empty_params` / `:invalid_params`
- Step 6: returns `{:error, reason}` on HTTP failure (transport error, non-200, API error in body)

## Error Handling Strategy

Errors propagate as `{:error, reason}` tuples. The `reason` varies by pipeline stage:

All errors follow a consistent `{:error, %{code: atom, descr: string}}` shape, with optional extra keys for context:

| Stage            | Error Shape                                                      | Example                                          |
| ---------------- | ---------------------------------------------------------------- | ------------------------------------------------ |
| Input validation | `{:error, %{code: :validation, descr: _, missing: _}}`           | Missing required struct params                   |
| Struct creation  | `{:error, %{code: :validation, descr: _, extraneous_fields: _}}` | Unknown field for endpoint                       |
| Field validation | `{:error, %{code: :validation, descr: _, errors: _}}`            | Value out of range                               |
| URL validation   | `{:error, %{code: :validation, descr: _}}`                       | URL without scheme or host                       |
| Rate limiting    | `{:error, %{code: :rate_limited, descr: _, retry_after_ms: _}}`  | Called <1s after previous request                |
| HTTP dispatch    | `{:error, %{code: :http_error, descr: _}}`                       | Transport error                                  |
| API error body   | `{:error, %{code: :api_error, descr: _, status: _}}`             | Nominatim returned `<error>` or `{"error": ...}` |
| search_one empty | `{:error, %{code: :not_found, descr: _}}`                        | No results                                       |
| search_one multi | `{:error, %{code: :multiple_results, descr: _, count: _}}`       | More than one result returned                    |

Validation errors accumulate in the struct's `:errors` list as `{key, message}` tuples. The `:valid?` flag is set to `false` on the first invalid field and subsequent checks continue (all errors are collected, not short-circuiting on first failure).

## Key Design Decisions

1. **Stateless, not GenServer** — No application-internal state. Configuration is read from `Application.get_env` at call time via `get_config/0`, making the library safe for concurrent use without process dictionaries or ETS.

2. **Struct-per-endpoint** — Each endpoint has its own params struct with exactly the fields the API accepts. This provides compile-time guarantees and clear documentation, and allows per-endpoint validation rules (e.g., `/details` only accepts `json` format).

3. **Config precedence layers** — Defaults → `:all` → endpoint-specific → per-call `opts`. This lets consumers set global defaults (e.g., self-hosted base URL) while still overriding per-endpoint (e.g., `/search` in geocodejson but `/status` in text).

4. **Force bypass** — `force: true` skips validation entirely. This is an explicit escape hatch for consumers who need to send parameters the library doesn't yet validate, with a warning in the docs.

5. **User-Agent compliance** — The library automatically sets `User-Agent: ExNominatim/{version}` on every request to comply with the Nominatim Usage Policy requirement.

6. **Post-processing pipeline** — `process/1` and `atomize/1` are opt-in via config (`:process`, `:atomize`). This lets consumers get raw `%Req.Response{}` if they prefer, or fully atomized maps for easier pattern matching.

7. **Module-safe endpoint resolution** — `get_module/1` uses `Module.safe_concat/1` to resolve `:search` → `ExNominatim.Client.SearchParams`, avoiding atom injection risks from user input.

8. **Cache protocol, not hard-wired Cachex** — Caching is abstracted behind the `ExNominatim.Cache` protocol with `get/2`, `put/3`, `del/2`. This lets consumers use a production Cachex-backed adapter (`ExNominatim.CachexCache`), a lightweight Agent-backed adapter for testing (`ExNominatim.TestCache`), or a custom adapter. When `cache: nil` (default), all cache operations short-circuit with `:miss` and zero overhead. Only successful results are cached; errors and HTTP failures never go into the cache.

## Dependencies

| Dependency         | Purpose                                             | Runtime?           |
| ------------------ | --------------------------------------------------- | ------------------ |
| `req ~> 0.5.18`    | HTTP client (Req.new/2, Req.request/1, Req.merge/2) | Yes                |
| `telemetry ~> 1.0` | Observability events                                | Yes                |
| `geohash ~> 1.0`   | Optional: geohash computation on lat/lon results    | Optional           |
| `cachex ~> 4.1`    | Optional: production caching backend                | Optional           |
| `credo ~> 1.7.19`  | Static analysis / linting                           | No (dev/test only) |
| `ex_doc ~> 0.40.3` | Hex documentation generation                        | No (dev only)      |

## Configuration

Runtime configuration is set via Elixir's `Config` module:

```elixir
config :ex_nominatim, ExNominatim,
  all: [base_url: "http://localhost:8080", force: false],
  search: [format: "geocodejson"],
  reverse: [namedetails: 1]
```

**Config precedence** (later wins):

1. Library defaults (`lib/ex_nominatim.ex:145-159`)
2. `:all` key from app config
3. Endpoint-specific key from app config
4. Per-call `opts` keyword list

**Notable defaults:**

- `base_url`: `"https://nominatim.openstreetmap.org"`
- `force`: `false`
- `process`: `true`
- `atomize`: `true`
- `/search` format: `"geocodejson"` (overrides API's `jsonv2`)
- `/reverse` format: `"geocodejson"` (overrides API's `xml`)
- `/lookup` format: `"jsonv2"` (overrides API's `xml`)
- `/status` format: `"json"` (overrides API's `text`)

## Testing

```sh
mix test                                       # unit tests (148, excluding integration)
mix test --exclude integration --cover          # with coverage (target: 80%)
mix test --include integration                  # full suite including live API calls
```

2 test files:

- `test/client_test.exs` — 124 unit tests covering struct construction, field validation, URL validation, caching, rate limiting, telemetry, search_one, custom req_opts, geohash, and Req.Test stub integration for all five endpoints.
- `test/nominatim_test.exs` — `doctest ExNominatim` only.

All unit tests use `Req.Test` stubs — no live Nominatim server required. Integration tests (tagged `@moduletag :integration`) hit a user-configured server and are excluded from the default `mix test` run.

Cache tests use `ExNominatim.TestCache` (Agent-backed, cleared per test via `setup`), verifying that successful results are cached, errors are never cached, and `cache: nil` disables caching with direct passthrough.

Rate limiting tests exercise the `ExNominatim.RateLimiter` module directly (verifying block/allow/independent URL tracking) and integrate via the Client pipeline (verifying `:auto` vs `false` vs custom base_url behavior). The ETS table is cleared between tests via `setup`.

Telemetry tests attach temporary handlers to verify cache hit/miss, request stop, and rate limit deny events are emitted. Geohash tests verify that results with lat/lon get a `:geohash` key. `search_one/1` tests cover single result, empty list, and multiple results. Custom `:req_opts` tests verify passthrough without error. Rate limit retry tests verify that saturated rate limiters trigger retry.

## Version History

- **v3.0.0** (current): Consistent `%{code:, descr:}` error shape (breaking), telemetry, rate-limit retry, `search_one/1`, custom Req opts, optional geohash, 148 tests.
- **v2.4.0**: Rate limiting via `ExNominatim.RateLimiter` (ETS-backed, zero deps), `:rate_limit` config option (`:auto`/`true`/`false`/integer), 113 unit tests.
- **v2.3.0**: Optional caching via Cachex protocol (`:cache` option), `ExNominatim.CachexCache` built-in adapter, `ExNominatim.TestCache` for tests, `:test_adapter` option for HTTP stubbing, 104 unit tests, coverage threshold 80%.
- **v2.1.0**: Imported upstream PR (Ko-Fi link removal, sponsor link removal).
- **v2.0.0**: Introduced `Config`-based application configuration with layered precedence.
- **v1.1.4**: Relaxed Req dependency to `0.5+`.
- **v1.1.3**: Fixed bug where config-specific keys leaked into GET params.
- **v1.1.2**: Fixed application config application bug.
- **v1.1.1**: Reverted default API URL to public server.
- **v1.1.0**: Added `Report` module for response processing and atomization; introduced config system.
- **v1.0.0**: Initial release with all 5 endpoints, struct-based params, validation pipeline.
