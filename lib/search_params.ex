defmodule ExNominatim.SearchParams do
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
    :debug,
    format: "jsonv2"
  ]

  @structured_query_fields [:amenity, :street, :city, :county, :state, :country, :postalcode]

  def freeform(p) when is_bitstring(p) do
    {:ok, %__MODULE__{q: p}}
  end

  def freeform(p) when is_list(p) or is_map(p) do
    nilify_structured =
      @structured_query_fields
      |> Map.new(fn k -> {k, nil} end)

    {:ok,
     Map.merge(%__MODULE__{}, Map.new(p))
     |> Map.merge(nilify_structured)}
  end

  def structured(p) when is_list(p) or is_map(p) do
    x = extract_structured_field_values(p)

    case {all_bitstrings_or_nil?(x), all_empty?(x)} do
      {false, _} ->
        {:error, :invalid_values}

      {true, true} ->
        {:error, :all_empty}

      {true, false} ->
        {:ok,
         Map.merge(%__MODULE__{}, Map.new(p))
         |> Map.put(:q, nil)}
    end
  end

  def extract_structured_field_values(p) when is_list(p) or is_map(p) do
    cond do
      is_list(p) -> Keyword.take(p, @structured_query_fields) |> Keyword.values()
      is_map(p) -> Map.take(p, @structured_query_fields) |> Map.values()
    end
  end

  def all_bitstrings_or_nil?(list) when is_list(list) do
    list
    |> Enum.map(&(is_bitstring(&1) or is_nil(&1)))
    |> cumulative_and()
  end

  def all_empty?(list) when is_list(list) do
    if all_bitstrings_or_nil?(list) do
      list |> Enum.map(&nil_to_empty_string/1) |> List.to_string() |> Kernel.==("")
    else
      false
    end
  end

  def nil_to_empty_string(s) when is_nil(s), do: ""

  def nil_to_empty_string(s) when is_bitstring(s), do: s

  def cumulative_and(list) when is_list(list) do
    Enum.reduce(list, true, fn x, acc -> x and acc end)
  end
end
