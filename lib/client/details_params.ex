defmodule ExNominatim.Client.DetailsParams do
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
    format: "json",
    valid?: nil,
    errors: []
  ]

  @required []

  def new(p), do: ExNominatim.Client.new(p, @required, __MODULE__)
end
