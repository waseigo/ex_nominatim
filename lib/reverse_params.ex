defmodule ExNominatim.ReverseParams do
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
    format: "jsonv2"
  ]

  @required_fields [:lat, :lon]

  def new(p) when is_list(p) do
    with {:keyword?, true} <- {:keyword?, Keyword.keyword?(p)},
         {:coords, [:lat, :lon]} <-
           {:coords, p |> Keyword.take(@required_fields) |> Keyword.keys()} do
      new(Map.new(p))
    else
      {:keyword?, false} -> {:error, :improper_list}
      {:coords, _} -> {:error, :missing_coords}
    end
  end

  def new(p) when is_map(p) do
    {:ok, Map.merge(%__MODULE__{}, p)}
  end
end
