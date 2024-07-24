defmodule ExNominatim.Client.SearchParams do
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

  def new(p), do: ExNominatim.Client.new(p, @required, __MODULE__)
end
