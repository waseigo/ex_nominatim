# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Client.Geohash do
  @moduledoc false

  @doc """
  Enrich a search result with geohash data when the `:geohash` option is set.
  """
  def add(result, config_opts) do
    case Keyword.get(config_opts, :geohash, false) do
      false ->
        result

      precision when is_integer(precision) ->
        if Code.ensure_loaded?(Geohash), do: do_add(result, precision), else: result

      true ->
        if Code.ensure_loaded?(Geohash), do: do_add(result, 12), else: result
    end
  end

  defp do_add({:ok, %{body: body} = result}, precision) when is_list(body) do
    {:ok, %{result | body: Enum.map(body, &geohash_item(&1, precision))}}
  end

  defp do_add(other, _precision), do: other

  defp geohash_item(item, precision) do
    lat = parse_float(item[:lat] || item["lat"])
    lon = parse_float(item[:lon] || item["lon"])

    if lat && lon do
      Map.put(item, :geohash, Geohash.encode(lat, lon, precision))
    else
      item
    end
  end

  defp parse_float(v) when is_float(v), do: v
  defp parse_float(v) when is_binary(v), do: v |> Float.parse() |> elem(0)
  defp parse_float(_), do: nil
end
