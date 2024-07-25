# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Client.DetailsParams do
  @moduledoc """
  The struct for a request to the `/details` API endpoint.
  """
  @moduledoc since: "1.0.0"

  defstruct [
    :osmtype,
    :osmid,
    :class,
    :place_id,
    :pretty,
    :addressdetails,
    :keywords,
    :linkedplaces,
    :hierarchy,
    :group_hierarchy,
    :polygon_geojson,
    :accept_language,
    :format,
    valid?: nil,
    errors: []
  ]

  @required []

  @doc """
  Construct a new `%DetailsParams{}` struct from the content of the keyword list `opts`.
  """
  def new(opts), do: ExNominatim.Client.new(opts, @required, __MODULE__)
end
