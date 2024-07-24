defmodule ExNominatim.Client.LookupParams do
  defstruct [
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

  @required_fields [:osm_ids]

  def new(p) when is_list(p) do
    with {:keyword?, true} <- {:keyword?, Keyword.keyword?(p)},
         {:required, @required_fields} <-
           {:required, p |> Keyword.take(@required_fields) |> Keyword.keys()} do
      new(Map.new(p))
    else
      {:keyword?, false} -> {:error, :improper_list}
      {:required, _} -> {:error, :missing_query_params}
    end
  end

  def new(p) when is_map(p) do
    {:ok, Map.merge(%__MODULE__{}, p)}
  end
end
