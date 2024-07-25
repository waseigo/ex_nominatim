# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Client.LookupParams do
  @moduledoc """
  The struct for a request to the `/lookup` API endpoint.
  """
  @moduledoc since: "1.0.0"

  defstruct [
    :osm_ids,
    :addressdetails,
    :extratags,
    :namedetails,
    :accept_language,
    :polygon_geojson,
    :polygon_kml,
    :polygon_svg,
    :polygon_text,
    :polygon_threshold,
    :email,
    :debug,
    :format,
    valid?: nil,
    errors: []
  ]

  @required [:osm_ids]

  @doc """
  Construct a new `%LookupParams{}` struct from the content of the keyword list `opts`, while taking into account the required field (`:osm_ids`) for a request to the `/lookup` API endpoint.
  """
  def new(opts), do: ExNominatim.Client.new(opts, @required, __MODULE__)
end
