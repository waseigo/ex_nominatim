<!-- <img src="./etc/assets/ex_nominatim_logo.png" height="100"> -->

# ExNominatim

**ExNominatim** is a full-featured client for the [OpenStreetMap](https://www.openstreetmap.org) [Nominatim API V1](https://nominatim.org/release-docs/latest/api/Overview/), with extensive request validation, robust error-handling and reporting, and user guidance with helpful validation messages.

## Goals

- Prevent unnecessary calls to the Nominatim API server by validating intended requests and preventing them if the request parameters are invalid.
- Solid error-handling for robustness in production.
- Provide helpful validation messages to the user when a request is deemed invalid.

## Features

- Covers the `/search`, `/reverse`, `/lookup`, `/status` and `/details` endpoints.
- Utilizes request parameter structs with the appropriate fields (except for `json_callback`) for each endpoint.
- Configurable for your application with overridable defaults using Elixir's `Config` module to set any default values, including the `:base_url` option for use with self-hosted Nominatim API instances.
- Validates parameter values prior to the request (possible to override this with the `force: true` option).
- Provides helpful return tuples `{:ok, ...}`, `{:error, reason}` and `{:error, {specific_error, other_info}}` across the board.
- Collects all detected field validation errors in an `:errors` field, and provides a `:valid?` field in each request params struct.
- Automatically sets the `User-Agent` header to "ExNominatim/{version}" to comply with the [Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/).

## Installation

The package can be installed [from Hex](https://hex.pm/package/ex_nominatim) by adding `ex_nominatim` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_nominatim, "~> 1.1.2"}
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

In the more likely scenario where you use ExNominatim in your own application (e.g., in a Phoenix application) called `MyApp`, you can override all defaults across all endpoints and then even for each endpoint through your application's configuration, e.g. in the `config/config.exs` file of a Phoenix app. For example:

```elixir
config :my_app, MyApp.ExNominatim,
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
- The responses from all endpoints will be processed automatically using `ExNominatim.Report.process/1`, and any maps and contents thereof (or map contents of structs's keys) will be converted from bitstring keys to atom keys using `ExNominatim.Report.atomize/1`.

Refer to [the documentation of the main `ExNominatim` module](https://hexdocs.pm/ex_nominatim/ExNominatim.html) for more information.

## Ideas and someday/maybe features

- Build [Cachex](https://hexdocs.pm/cachex/Cachex.html) in (see [Reactive Warming](https://hexdocs.pm/cachex/reactive-warming.html)) and provide the option to automatically throttle requests to the public API to the "absolute maximum of 1 request per second" as requested by the [Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/).
- Implement a test suite.

## Who made this?

Copyright 2024, made by [Isaak Tsalicoglou](https://linkedin.com/in/tisaak), [OVERBRING](https://overbring.com) in [Athens](https://www.openstreetmap.org/#map=11/37.9909/23.7387), [Attica](https://www.openstreetmap.org/#map=8/37.061/23.456), [Greece](https://www.openstreetmap.org/#map=6/38.310/24.489).

Many thanks to all the volunteers and contributors of [OpenStreetMap](https://www.openstreetmap.org/) and [Nominatim](https://nominatim.org/).
