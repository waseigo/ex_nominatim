# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Client.ReverseParams do
  @moduledoc """
  The struct for a request to the `/reverse` API endpoint.
  """
  @moduledoc since: "1.0.0"

  defstruct [
    :lat,
    :lon,
    :addressdetails,
    :extratags,
    :namedetails,
    :accept_language,
    :zoom,
    :layer,
    :polygon_geojson,
    :polygon_kml,
    :polygon_svg,
    :polygon_text,
    :polygon_threshold,
    :email,
    :debug,
    format: "jsonv2",
    valid?: nil,
    errors: []
  ]

  @required [:lat, :lon]

  @doc """
  Construct a new `%ReverseParams{}` struct from the content of the keyword list `opts`, while taking into account the required fields (`:lat` and `:lon`) for a request to the `/reverse` API endpoint.
  """
  def new(opts), do: ExNominatim.Client.new(opts, @required, __MODULE__)
end
