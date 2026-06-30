<!-- <img src="./etc/assets/ex_nominatim_logo.png" height="100"> -->

# ExNominatim

[![Hex pm](https://img.shields.io/hexpm/v/ex_nominatim.svg?style=flat)](https://hex.pm/packages/ex_nominatim)
[![Hexdocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ex_nominatim/)

**ExNominatim** is a full-featured client for the [OpenStreetMap](https://www.openstreetmap.org) [Nominatim API V1](https://nominatim.org/release-docs/latest/api/Overview/), with extensive request validation, robust error-handling and reporting, and user guidance with helpful validation messages.

## Goals

- Prevent unnecessary calls to the Nominatim API server by validating intended requests and preventing them if the request parameters are invalid.
- Solid error-handling for robustness in production.
- Provide helpful validation messages to the user when a request is deemed invalid.

## Features

- Covers the `/search`, `/reverse`, `/lookup`, `/status` and `/details` endpoints.
- `search_one/1` convenience for single-result lookups.
- Utilizes request parameter structs with the appropriate fields (except for `json_callback`) for each endpoint.
- Configurable for your application with overridable defaults using Elixir's `Config` module to set any default values, including the `:base_url` option for use with self-hosted Nominatim API instances.
- Validates parameter values prior to the request (possible to override this with the `force: true` option).
- Provides helpful return tuples `{:ok, ...}`, `{:error, reason}` and `{:error, {specific_error, other_info}}` across the board.
- Collects all detected field validation errors in an `:errors` field, and provides a `:valid?` field in each request params struct.
- Automatically sets the `User-Agent` header to "ExNominatim/{version}" to comply with the [Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/).
- Optional caching via Cachex (`:cache` option).
- Built-in rate limiting with `:auto` mode for the public server.
- Telemetry events for production observability.
- Optional geohash computation on results with lat/lon.

## Installation

The package can be installed [from Hex](https://hex.pm/packages/ex_nominatim) by adding `ex_nominatim` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_nominatim, "~> 3.0"}
  ]
end
```

The code can be found on [Github/waseigo/ex_nominatim](https://github.com/waseigo/ex_nominatim).

Documentation has been published on [HexDocs](https://hexdocs.pm/ex_nominatim).

There is also a thread open on the Elixir Programming Language Forum: [ExNominatim - A full-featured client for the OpenStreetMap Nominatim API V1](https://elixirforum.com/t/exnominatim-a-full-featured-client-for-the-openstreetmap-nominatim-api-v1/65120/1).

## Usage

By calling the endpoint functions of the `ExNominatim` module you will be hitting the public Nominatim API server with each endpoint's default options as described in the API documentation; i.e., all requests use <https://nominatim.openstreetmap.org> as the value of `:base_url` in `opts` and the default parameters for each endpoint are handled by the API according to its documentation.

**Please respect the [Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/) when using the public server.**

## Optional configuration and default parameters

In the more likely scenario where you use ExNominatim in your own application (e.g., in a Phoenix application), you can override all defaults across all endpoints and then even for each endpoint through your application's configuration, e.g. in the `config/config.exs` file of a Phoenix app. For example:

```elixir
  config :ex_nominatim, ExNominatim,
    all: [
      base_url: "http://localhost:8080",
      force: true,
      format: "json",
      process: true,
      atomize: true
    ],
    search: [format: "geocodejson", force: false],
    reverse: [namedetails: 1],
    lookup: [],
    details: [],
    status: [format: "json"]
```

The configuration above has the following effects:

- Requests to all endpoints will use the self-hosted Nominatim API instance at port 8080 of `localhost`, accessible over HTTP.
- Request parameter validation errors (`valid?: false` in the request parameters struct) will be ignored for requests to all endpoints, except for requests to the `/search` endpoint.
- Unless requested otherwise in `opts`, requests to the `/search` endpoint will return data in GeocodeJSON format (instead of the default `jsonv2`).
- Requests to the `/reverse` endpoint will set `:namedetails` to 1 (unless otherwise set in `opts`).
- Requests to the `/status` endpoint will return JSON instead of the [default text](https://nominatim.org/release-docs/develop/api/Status/#output) (HTTP status code 200 and text `OK` or HTTP status 500 and a detailed error mesage).
- The responses from all endpoints will be processed automatically using `ExNominatim.Report.process/1`, and any maps and contents thereof (or map contents of structs's keys) will be converted from binary keys to atom keys using `ExNominatim.Report.atomize/1`.

Refer to [the documentation of the main `ExNominatim` module](https://hexdocs.pm/ex_nominatim/ExNominatim.html) for more information.

## Rate Limiting

Built-in rate limiting (zero dependencies) that enforces 1 req/s for the public Nominatim server by default.

| Config value | Behavior |
|---|---|
| `:auto` (default) | 1 req/s for `nominatim.openstreetmap.org`, no limit for other servers |
| `true` | 1 req/s for all servers |
| `false` | Disabled |
| integer (e.g. `5`) | N req/s for all servers |

```elixir
# Disable for self-hosted servers
config :ex_nominatim, ExNominatim,
  all: [rate_limit: false]

# Or explicitly enable for all servers
config :ex_nominatim, ExNominatim,
  all: [rate_limit: true]

# Or set a custom rate (e.g. 5 req/s)
config :ex_nominatim, ExNominatim,
  all: [rate_limit: 5]
```

The rate limiter uses an ETS table (no GenServer, no bottleneck) and is checked **after** cache lookup but **before** HTTP dispatch — cached results bypass it entirely. Errors return `{:error, {:rate_limited, retry_after_ms}}`. Set `rate_limit_retry: true` to automatically sleep and retry up to 3 times.

## Telemetry

ExNominatim emits the following Telemetry events:

| Event | Measurements | Metadata |
|---|---|---|
| `[:ex_nominatim, :request, :stop]` | `duration` | `endpoint`, `base_url`, `status` |
| `[:ex_nominatim, :request, :exception]` | `duration` | `endpoint`, `base_url`, `error` |
| `[:ex_nominatim, :cache, :hit]` | — | `endpoint` |
| `[:ex_nominatim, :cache, :miss]` | — | `endpoint` |
| `[:ex_nominatim, :rate_limit, :deny]` | — | `endpoint`, `base_url`, `retry_after_ms` |

Attach handlers via `:telemetry.attach/4` to build dashboards, alert on errors, or log cache hit rates.

## Geohash

Pass `geohash: true` (or an integer precision) to append a `:geohash` key to each result that has lat/lon fields:

```elixir
{:ok, %{body: [%{lat: "38.0", lon: "23.7", geohash: "sryj481k2m4d", ...}]}} =
  ExNominatim.search(q: "Athens", geohash: true)
```

Requires the optional `geohash` hex package in your deps:
```elixir
{:geohash, "~> 1.0"}
```

## Custom Req options

Pass any Req option via `:req_opts` — useful for custom headers, timeouts, or connection options:

```elixir
ExNominatim.search(q: "Athens", req_opts: [
  headers: [authorization: "Bearer xyz"],
  receive_timeout: 5000
])
```

## Caching

Optionally cache successful Nominatim responses via [Cachex](https://hexdocs.pm/cachex/Cachex.html):

```elixir
# mix.exs
{:cachex, "~> 4.0"}

# config/config.exs
config :ex_nominatim, :cache_name, :ex_nominatim   # default
config :ex_nominatim, :cache_ttl, 86_400_000        # 24 hours
```

Pass `cache: ExNominatim.CachexCache` to any endpoint:

```elixir
ExNominatim.search(q: "Athens", cache: ExNominatim.CachexCache)
```

Only successful results are cached. Errors never cache. When `cache: nil` (default), caching is disabled with zero overhead.

You can implement custom cache backends via the `ExNominatim.Cache` protocol.

## Ideas and someday/maybe features

- none at the moment

## Who made this?

Copyright 2024, made by [Isaak Tsalicoglou](https://linkedin.com/in/tisaak), Managing Director of [OVERBRING Labs](https://overbring.com) in [Athens](https://www.openstreetmap.org/#map=11/37.9909/23.7387), [Attica](https://www.openstreetmap.org/#map=8/37.061/23.456), [Greece](https://www.openstreetmap.org/#map=6/38.310/24.489).

Many thanks to all the volunteers and contributors of [OpenStreetMap](https://www.openstreetmap.org/) and [Nominatim](https://nominatim.org/).
