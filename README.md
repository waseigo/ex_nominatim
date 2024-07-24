<img src="./etc/assets/logo.png" width="100" height="100">

# ExNominatim

ExNominatim is a full-featured client for the [OpenStreetMap](https://www.openstreetmap.org) [Nominatim API V1](https://nominatim.org/release-docs/latest/api/Overview/), with extensive request validation, robust error-handling and reporting, and user guidance with helpful validation messages.

## Goals

* Prevent unnecessary calls to the Nominatim API server by validating intended requests and preventing them if the request parameters are invalid.
* Solid error-handling for robustness in production.
* Provide helpful validation messages to the user when a request is deemed invalid.

## Features

* Covers the `/search`, `/reverse`, `/lookup`, `/status` and `/details` endpoints.
* Utilizes request parameter structs with the appropriate fields (except for `json_callback`) for each endpoint.
* Validates parameter values prior to the request (possible to override this with the `force: true` option).
* Provides helpful return tuples `{:ok, ...}`, `{:error, reason}` and `{:error, {specific_error, other_info}}` across the board.
* Collects all detected field validation errors in an `:errors` field, and provides a `:valid?` field in each request params struct.
* Can be used with self-hosted Nominatim API instances by setting the `:base_url` option of the enpoint-related functions in the `ExNominatim` module.
* Automatically sets the `User-Agent` header to "ExNominatim" (plus the version) to comply with the [Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/).

## Ideas

* Build [Cachex](https://hexdocs.pm/cachex/Cachex.html) in (see [Reactive Warming](https://hexdocs.pm/cachex/reactive-warming.html)) and provide the option to automatically throttle requests to the public API to the "absolute maximum of 1 request per second" as requested by the [Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/).
* Implement a test suite.

## Installation

The package can be installed [from Hex](https://hex.pm/package/ex_nominatim) by adding `ex_nominatim` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_nominatim, "~> 1.0.0"}
  ]
end
```

Documentation has been published on [HexDocs](https://hexdocs.pm/ex_nominatim).

