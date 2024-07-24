defmodule ExNominatim.Client.LookupParams do
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
    format: "jsonv2",
    valid?: nil,
    errors: []
  ]

  @required [:osm_ids]

  def new(p), do: ExNominatim.Client.new(p, @required, __MODULE__)
end
