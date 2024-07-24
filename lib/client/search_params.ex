# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Client.SearchParams do
  @moduledoc """
  The struct for a request to the `/search` API endpoint.
  """
  @moduledoc since: "1.0.0"

  defstruct [
    :q,
    :amenity,
    :street,
    :city,
    :county,
    :state,
    :country,
    :postalcode,
    :limit,
    :addressdetails,
    :extratags,
    :namedetails,
    :accept_language,
    :countrycodes,
    :layer,
    :featureType,
    :exclude_place_ids,
    :viewbox,
    :bounded,
    :polygon_geojson,
    :polygon_kml,
    :polygon_svg,
    :polygon_text,
    :polygon_threshold,
    :email,
    :dedupe,
    :debug,
    format: "jsonv2",
    valid?: nil,
    errors: []
  ]

  @required []

  @doc """
  Construct a new `%SearchParams{}` struct from the content of the keyword list `opts`, while taking into account that a request to the `/reverse` API endpoint requires either a free-form query with the keyword `:q` assigned a value _or_ a structured query with values defined for at least one of `:amenity`, `:street`, `:city`, `:county`, :state`, `:country` and `:postalcode`, but not both.
  """

  def new(opts), do: ExNominatim.Client.new(opts, @required, __MODULE__)
end
