# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim do
  alias ExNominatim.{Client, Validations}

  @moduledoc """
  Main user-friendly functions for interacting with the endpoints of a Nominatim API.
  """
  @moduledoc since: "1.0.0"

  @doc """
  Purpose: search OpenStreetMap objects by name or type using the `/search` API endpoint.

  Note: You can set an alternative server as the value of the `:base_url` keyword and ignore any validation errors by setting the `:force` keyword's value to `true`.

  Given a keyword list of request parameters as `params`, transform this to a `%SearchParams{}` struct, validate it and its values using the `ExNominatim.Validations` module's functions and, if valid (or if `params` contains `force: true` to ignore any validation errors), prepare and make an HTTP request to the `/search` endpoint using the functions in the `ExNominatim.HTTP` module.


  """
  defdelegate search(params), to: Client

  @doc """
  Purpose: search OpenStreetMap objects by their location using the `/reverse` API endpoint.

  Note: You can set an alternative server as the value of the `:base_url` keyword and ignore any validation errors by setting the `:force` keyword's value to `true`.

  Given a keyword list of request parameters as `params`, transform this to a `%ReverseParams{}` struct, validate it and its values using the `ExNominatim.Validations` module's functions and, if valid (or if `params` contains `force: true` to ignore any validation errors), prepare and make an HTTP request to the `/reverse` endpoint using the functions in the `ExNominatim.HTTP` module.
  """
  defdelegate reverse(params), to: Client

  @doc """
  Purpose: look up address details for OpenStreetMap objects by their ID using the `/lookup` API endpoint.

  Note: You can set an alternative server as the value of the `:base_url` keyword and ignore any validation errors by setting the `:force` keyword's value to `true`.

  Given a keyword list of request parameters as `params`, transform this to a `%LookupParams{}` struct, validate it and its values using the `ExNominatim.Validations` module's functions and, if valid (or if `params` contains `force: true` to ignore any validation errors), prepare and make an HTTP request to the `/lookup` endpoint using the functions in the `ExNominatim.HTTP` module.
  """
  defdelegate lookup(params), to: Client

  @doc """
  Purpose: show internal details for an OpenStreetMap object (for debugging only) using the `/details` API endpoint.

  Note: You can set an alternative server as the value of the `:base_url` keyword and ignore any validation errors by setting the `:force` keyword's value to `true`.

  Given a keyword list of request parameters as `params`, transform this to a `%DetailsParams{}` struct, validate it and its values using the `ExNominatim.Validations` module's functions and, if valid (or if `params` contains `force: true` to ignore any validation errors), prepare and make an HTTP request to the `/details` endpoint using the functions in the `ExNominatim.HTTP` module.
  """
  defdelegate details(params), to: Client

  @doc """
  Purpose: query the status of the server at `base_url` using the `/status` API endpoint.

  Note: You can set an alternative server as the value of the `:base_url` keyword and ignore any validation errors by setting the `:force` keyword's value to `true`.

  Given a keyword list of request parameters as `params`, transform this to a `%StatusParams{}` struct, validate it and its values using the `ExNominatim.Validations` module's functions and, if valid (or if `params` contains `force: true` to ignore any validation errors), prepare and make an HTTP request to the `/status` endpoint using the functions in the `ExNominatim.HTTP` module.
  """
  defdelegate status(params \\ [format: "text"]), to: Client

  @doc """
  Given a request params struct (`%ReverseParams{}`, `%SearchParams{}`, etc.) explain its fields, their default values (if any) and their values' limits (if applicable).

  The content shown is adapted from the [Nominatim API Reference](https://nominatim.org/release-docs/latest/api/Overview/) page of the endpoint corresponding to the request params struct.

  The result is a map, so that you can pluck out any values if you intend to reuse them for user guidance and error reporting in your own application.
  """
  defdelegate explain_fields(params), to: Validations
end
