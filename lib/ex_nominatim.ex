# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim do
  alias ExNominatim.{Client, Validations}

  @nominatim_public_api "https://nominatim.openstreetmap.org"
  # for testing purposes during development
  # @nominatim_public_api "http://localhost:8080"

  # If the following line is uncommented, it will point to a self-hosted Nominatim API server when ExNominatim or an overarching app that uses it is in the :dev or :test environment.
  # @nominatim_public_api (Mix.env() in [:dev, :test]) && "http://localhost:8080" || "https://nominatim.openstreetmap.org"

  @moduledoc """
  Main user-friendly functions for interacting with the endpoints of a Nominatim API server.

  The `opts` keyword list of the endpoint request functions can optionally include the following:
  * `:base_url` with a string value setting the base URL of the target Nominatim API server (it defaults to the public server).
  * `:force` with a boolean value, where `true` means that validation errors will be ignored and the HTTP GET request to the API will run regardless.

  > #### Warning {: .error}
  >
  > Please respect the [Nominatim Usage Policy](https://operations.osmfoundation.org/policies/nominatim/) when using the public server. To prevent useless requests, it is recommended to not disable request validation.

    **New since v2.0.0:** ExNominatim can be configured as defined using the `Config` module. You can define default values like so:

  ```elixir
  config :my_app, MyApp.ExNominatim,
  all: [
    base_url: "http://localhost:8080",
    force: true,
    format: "json",
    process: true,
    atomize: true,
    req_cache: true,
  ],
  search: [format: "geocodejson", force: false],
  reverse: [namedetails: 1],
  lookup: [],
  details: [],
  status: [format: "json"]
  ```

  The configuration above has the following effects:

  * Requests to all endpoints will use the self-hosted Nominatim API instance at port 8080 of `localhost`, accessible over HTTP.
  * Request parameter validation errors (`valid?: false` in the request parameters struct) will be ignored for requests to all endpoints, except for requests to the `/search` endpoint.
  * Unless requested otherwise in `opts`, requests to the `/search` endpoint will return data in GeocodeJSON format (instead of the default `jsonv2`).
  * Requests to the `/reverse` endpoint will set `:namedetails` to 1 (unless otherwise set in `opts`).
  * Requests to the `/status` endpoint will return JSON instead of the [default text](https://nominatim.org/release-docs/develop/api/Status/#output) (HTTP status code 200 and text `OK` or HTTP status 500 and a detailed error mesage).
  * The responses from all endpoints will be processed automatically using `ExNominatim.Report.process/1`, and any maps and contents thereof (or map contents of structs's keys) will be converted from bitstring keys to atom keys using `ExNominatim.Report.atomize/1`.

  Here's the preference order:

  * The default values for `:base_url` and `:force` across all endpoints are the public Nominatim API server's URL and `false`, respectively.
  * Any keyword-value pairs set in the `:all` list override these defaults and are applied automatically in requests to all endpoints.
  * Any keyword-value pairs set in the list of a specific endpoint override any values defined in the `:all` list and are applied automatically in requests to that endpoint.
  * Anything you set in `opts` overrides all the above.

  At any moment you can use `ExNominatim.get_config/0` to see the current configuration.

  The following things are set as default in ExNominatim's default settings (unless overriden through your own configuration or explicitly-set request parameter values):
  1. The `:format` value for the `/reverse` endpoint, which is switched to GeocodeJSON, instead of XML (the API endpoint's default).
  2. The `:format` value for the `/lookup` endpoint, which is switched to JSONv2, instead of XML (the API endpoint's default).
  3. The `:format` value for the `/status` endpoint, which is switch to JSON, instead of text (the API endpoint's default).
  """
  @moduledoc since: "1.0.0"

  @doc """
  Search OpenStreetMap objects by name or type using the `/search` API endpoint.

  Given a keyword list of request parameters as `params`, transform this to a `%SearchParams{}` struct, validate it and its values using the `ExNominatim.Validations` module's functions and, if valid (or if `params` contains `force: true` to ignore any validation errors), prepare and make an HTTP request to the `/search` endpoint.
  """
  defdelegate search(opts), to: Client

  @doc """
  Search OpenStreetMap objects by their location using the `/reverse` API endpoint.

  Note: You can set an alternative server as the value of the `:base_url` keyword and ignore any validation errors by setting the `:force` keyword's value to `true`.

  Given a keyword list of request parameters as `opts`, transform this to a `%ReverseParams{}` struct, validate it and its values using the `ExNominatim.Validations` module's functions and, if valid (or if `opts` contains `force: true` to ignore any validation errors), prepare and make an HTTP request to the `/reverse` endpoint.
  """
  defdelegate reverse(opts), to: Client

  @doc """
  Look up address details for OpenStreetMap objects by their "OSM ID" using the `/lookup` API endpoint.

  Note: You can set an alternative server as the value of the `:base_url` keyword and ignore any validation errors by setting the `:force` keyword's value to `true`.

  Given a keyword list of request parameters as `opts`, transform this to a `%LookupParams{}` struct, validate it and its values using the `ExNominatim.Validations` module's functions and, if valid (or if `opts` contains `force: true` to ignore any validation errors), prepare and make an HTTP request to the `/lookup` endpoint.
  """
  defdelegate lookup(opts), to: Client

  @doc """
  Show internal details for an OpenStreetMap object (for debugging only) using the `/details` API endpoint.

  Note: You can set an alternative server as the value of the `:base_url` keyword and ignore any validation errors by setting the `:force` keyword's value to `true`.

  Given a keyword list of request parameters as `opts`, transform this to a `%DetailsParams{}` struct, validate it and its values using the `ExNominatim.Validations` module's functions and, if valid (or if `opts` contains `force: true` to ignore any validation errors), prepare and make an HTTP request to the `/details` endpoint.
  """
  defdelegate details(opts), to: Client

  @doc """
  Query the status of the server at `base_url` using the `/status` API endpoint.

  Note: You can set an alternative server as the value of the `:base_url` keyword and ignore any validation errors by setting the `:force` keyword's value to `true`.

  Given a keyword list of request parameters as `opts`, transform this to a `%StatusParams{}` struct, validate it and its values using the `ExNominatim.Validations` module's functions and, if valid (or if `opts` contains `force: true` to ignore any validation errors), prepare and make an HTTP request to the `/status` endpoint.
  """
  defdelegate status(opts), to: Client

  @doc """
  Query the status of the server at `base_url` using the `/status` API endpoint without any keyword list options provided.
  """
  defdelegate status(), to: Client

  @doc """
  Given a request params struct (`%ReverseParams{}`, `%SearchParams{}`, etc.), a keyword list, or a list of atoms corresponding to keys, explain the fields, their default values (if any) and their values' limits (if applicable). It ignores any keyword list keys or atoms in the list that do not correspond to request parameters.

  Alternatively, provide the atom corresponding to an endpoint (e.g., `:search` for `/search`) to get the explanations of the parameters specific to that endpoint.

  The content shown is adapted from the [Nominatim API Reference](https://nominatim.org/release-docs/latest/api/Overview/) page of the endpoint corresponding to the request params struct.

  The result is a map, so that you can reuse the explanations for user guidance and error reporting in your own application.
  """
  defdelegate explain_fields(params_or_opts_or_list_or_atom), to: Validations

  @doc """
  Same as `ExNominatim.explain_fields/1`, but show all fields and their explanations.
  """
  defdelegate explain_fields(), to: Validations

  @doc """
  Show the current configuration defaults.
  """
  def get_config() do
    case Application.fetch_env(:ex_nominatim, ExNominatim) do
      {:ok, config} ->
        Keyword.merge(default_config(), config)

      :error ->
        default_config()
    end
  end

  defp default_config do
    [
      all: [
        base_url: @nominatim_public_api,
        force: false,
        process: true,
        atomize: true,
        req_cache: true
      ],
      search: [],
      reverse: [format: "geocodejson"],
      lookup: [format: "jsonv2"],
      details: [],
      status: [format: "json"]
    ]
  end
end
