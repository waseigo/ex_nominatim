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
┌─────────────────────────────────────────────────────────────────────┐
│  Consumer (ExNominatim.search/1, .reverse/1, ...)                   │
│    opts = [q: "Athens", limit: 5]                                   │
└──────────────────────────┬──────────────────────────────────────────┘
                           │ delegate
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│  ExNominatim.Client.generic/2                                       │
│    1. make_new_struct/2  → merge config layers, build struct        │
│    2. Validations.validate/1 → per-field + intent checks            │
│    3. Client.prepare/3   → build Req.Request (URL, UA, params)      │
│    4. Req.request/1      → HTTP GET                                 │
│    5. Report.process/1   → detect errors, normalize body            │
│    6. Report.atomize/1   → binary keys → atom keys                  │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
     ┌───────────┐  ┌────────────┐  ┌──────────┐
     │  Params   │  │ Validations│  │  Report  │
     │ Structs   │  │            │  │          │
     │ (5 mod.)  │  │            │  │          │
     └───────────┘  └────────────┘  └──────────┘
```

## Module Responsibilities

### ExNominatim (`lib/ex_nominatim.ex`)

The public API surface. Delegates all calls to `ExNominatim.Client` and provides `get_config/0` to inspect merged configuration. Holds the default config (public server URL, `force: false`, `process: true`, `atomize: true`, per-endpoint format overrides). Documents the configuration precedence: `default < :all < endpoint-specific < opts`.

### ExNominatim.Client (`lib/client.ex`)

The pipeline orchestrator. Contains `generic/2` which sequences the full request lifecycle: struct creation → validation → HTTP preparation → dispatch → report processing. Also houses `prepare/3` (builds `Req.Request` with User-Agent header, URL validation, query param filtering) and `new/3` (validates required fields, constructs struct from merged opts). The `get_module/1` helper resolves endpoint atoms to params modules via `Module.safe_concat/1`.

### ExNominatim.Validations (`lib/validations.ex`)

The validation engine. Every field has a `valid?/2` clause that checks type, range, format, and membership against API specs. Cross-field intent validation (`verify_intent/1`) enforces mutually exclusive modes (e.g., freeform `:q` vs. structured search fields; `:place_id` vs. `:osmtype`/`:osmid`). Errors accumulate in `%{valid?: false, errors: [{key, message}]}`. Also provides `explain_fields/0` and `sanitize_comma_separated_strings/1`.

### ExNominatim.Report (`lib/report.ex`)

Response normalization. `process/1` pattern-matches on `Req.Response` to detect HTTP-level and API-level errors (embedded `"error"` key in JSON or `<error>` in XML). `atomize/1` recursively converts binary map keys to atoms (with dash→underscore normalization), handling nested maps, lists, and structs.

### Params Structs (`lib/client/*_params.ex`)

Five modules — `SearchParams`, `ReverseParams`, `LookupParams`, `DetailsParams`, `StatusParams` — each defining a `defstruct` with endpoint-specific fields plus the shared `valid?` and `errors` validation accumulator. Each declares `@required` fields and delegates `new/1` to `Client.new/3`.

## Data Flow

```
Input:  opts = [q: "Athens", limit: 5]

Step 1 — Config merge (Client.make_new_struct/2)
  default_config()
  |> merge app_config[:all]
  |> merge app_config[:search]
  |> merge opts
  → %{q: "Athens", limit: 5, format: "geocodejson", base_url: "...", ...}

Step 2 — Struct construction (Client.new/3)
  SearchParams.new(merged_opts)
  → {:ok, %SearchParams{q: "Athens", limit: 5, valid?: nil, errors: []}}

Step 3 — Validation (Validations.validate/1)
  validate_all_fields/1  → each field checked by valid?/2
  validate_format/1      → format allowed for endpoint?
  verify_intent/1         → q XOR structured fields
  sanitize_comma_separated_strings/1
  → {:ok, %SearchParams{valid?: true, errors: []}}

Step 4 — HTTP preparation (Client.prepare/3)
  validate_url(base_url)  → :ok
  Req.new(base_url:, method: :get, headers: %{user_agent: "ExNominatim/2.2.0"}, cache: true)
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
```

**Short-circuit points:**

- Step 1: returns `{:error, :improper_list}` if opts is not a keyword list
- Step 1: returns `{:error, {:extraneous_fields, [...]}}` if unknown keys for endpoint
- Step 2: returns `{:error, {:missing_query_params, [...]}}` if required fields absent
- Step 3: returns `{:error, %SearchParams{valid?: false, errors: [...]}}` on validation failure
- Step 4: returns `{:error, :missing_scheme}` / `:missing_host` / `:empty_params` / `:invalid_params`
- Step 5: returns `{:error, reason}` on HTTP failure (transport error, non-200, API error in body)

## Error Handling Strategy

Errors propagate as `{:error, reason}` tuples. The `reason` varies by pipeline stage:

| Stage             | Error Shape                                                              | Example                                          |
| ----------------- | ------------------------------------------------------------------------ | ------------------------------------------------ |
| Input validation  | `{:error, :improper_list}`                                               | Non-keyword-list passed                          |
| Struct creation   | `{:error, {:extraneous_fields, [:foo]}}`                                 | Unknown field for endpoint                       |
| Struct creation   | `{:error, {:missing_query_params, [:lat, :lon]}}`                        | Required field absent                            |
| Field validation  | `{:error, %Struct{valid?: false, errors: [{:lat, "..."}]}}`              | Value out of range                               |
| Intent validation | `{:error, %Struct{valid?: false, errors: [{:confusing_intent, "..."}]}}` | Both `:q` and `:city` set                        |
| URL validation    | `{:error, :missing_scheme}`                                              | URL without scheme                               |
| HTTP dispatch     | `{:error, reason}`                                                       | Network error, non-200 status                    |
| API error body    | `{:error, %{errors: [{:api, "..."}]}}`                                   | Nominatim returned `<error>` or `{"error": ...}` |

Validation errors accumulate in the struct's `:errors` list as `{key, message}` tuples. The `:valid?` flag is set to `false` on the first invalid field and subsequent checks continue (all errors are collected, not short-circuiting on first failure).

## Key Design Decisions

1. **Stateless, not GenServer** — No application-internal state. Configuration is read from `Application.get_env` at call time via `get_config/0`, making the library safe for concurrent use without process dictionaries or ETS.

2. **Struct-per-endpoint** — Each endpoint has its own params struct with exactly the fields the API accepts. This provides compile-time guarantees and clear documentation, and allows per-endpoint validation rules (e.g., `/details` only accepts `json` format).

3. **Config precedence layers** — Defaults → `:all` → endpoint-specific → per-call `opts`. This lets consumers set global defaults (e.g., self-hosted base URL) while still overriding per-endpoint (e.g., `/search` in geocodejson but `/status` in text).

4. **Force bypass** — `force: true` skips validation entirely. This is an explicit escape hatch for consumers who need to send parameters the library doesn't yet validate, with a warning in the docs.

5. **User-Agent compliance** — The library automatically sets `User-Agent: ExNominatim/{version}` on every request to comply with the Nominatim Usage Policy requirement.

6. **Post-processing pipeline** — `process/1` and `atomize/1` are opt-in via config (`:process`, `:atomize`). This lets consumers get raw `%Req.Response{}` if they prefer, or fully atomized maps for easier pattern matching.

7. **Module-safe endpoint resolution** — `get_module/1` uses `Module.safe_concat/1` to resolve `:search` → `ExNominatim.Client.SearchParams`, avoiding atom injection risks from user input.

8. **SPDX headers** — All source files include SPDX copyright and license identifiers (Apache-2.0).

## Dependencies

| Dependency         | Purpose                                             | Runtime?           |
| ------------------ | --------------------------------------------------- | ------------------ |
| `req ~> 0.6.2`     | HTTP client (Req.new/2, Req.request/1, Req.merge/2) | Yes                |
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
mix test
```

1 test file (`test/nominatim_test.exs`), currently running `doctest ExNominatim` only. No unit tests for individual modules, no integration tests against live or mock Nominatim services. No external test dependencies.

## Version History

- **v2.2.0** (current): Relaxed Req dependency to `~> 0.6.2`.
- **v2.1.0**: Imported upstream PR (Ko-Fi link removal, sponsor link removal).
- **v2.0.0**: Introduced `Config`-based application configuration with layered precedence.
- **v1.1.4**: Relaxed Req dependency to `0.5+`.
- **v1.1.3**: Fixed bug where config-specific keys leaked into GET params.
- **v1.1.2**: Fixed application config application bug.
- **v1.1.1**: Reverted default API URL to public server.
- **v1.1.0**: Added `Report` module for response processing and atomization; introduced config system.
- **v1.0.0**: Initial release with all 5 endpoints, struct-based params, validation pipeline.
