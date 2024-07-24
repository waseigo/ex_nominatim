defmodule ExNominatim.Client.ReverseParams do
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

  def new(p), do: ExNominatim.Client.new(p, @required, __MODULE__)
end
