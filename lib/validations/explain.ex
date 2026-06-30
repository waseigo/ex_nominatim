# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Validations.Explain do
  @moduledoc false

  @doc """
  Show all fields and their explanations.
  """
  def fields do
    opt_sq = " (optional for structured query)"

    %{
      q: "Free-form query string to search for (mutually exclusive with structured query fields)",
      amenity: "Name and/or type of POI" <> opt_sq,
      street: "Housenumber and streetname" <> opt_sq,
      city: "City" <> opt_sq,
      county: "County" <> opt_sq,
      state: "State" <> opt_sq,
      country: "Country" <> opt_sq,
      postalcode: "Postal code" <> opt_sq,
      limit: "Limit the maximum number of returned results. Integer, 1 to 40" <> default(10),
      addressdetails: "Include a breakdown of the address into elements" <> default(0, :bool),
      extratags:
        "Include any additional information in the result that is available in the database" <>
          default(0, :bool),
      namedetails: "Include a full list of names for the result" <> default(0, :bool),
      accept_language:
        "Browser language string consisting of ISO 639-1 Set 1 codes" <>
          default("content of Accept-Language HTTP header"),
      countrycodes: "Comma-separated list of ISO 3166-1 alpha-2 country codes" <> default(),
      layer:
        "Comma-separated list of: address, poi, railway, natural, manmade" <>
          default() <> " (no restriction)",
      featureType: "One of: country, state, city, settlement" <> default(),
      exclude_place_ids: "Comma-separated list of place_id items to skip" <> default(),
      pretty: "Add indentation to the output to make it more human-readable" <> default(0, :bool),
      keywords:
        "Include a list of name keywords and address keywords in the result" <> default(0, :bool),
      linkedplaces:
        "Include details of places that are linked with this one" <> default(1, :bool),
      hierarchy: "Include details of places lower in the address hierarchy" <> default(0, :bool),
      group_hierarchy: "Group output of the address hierarchy by type" <> default(0, :bool),
      viewbox:
        "Boost parameter which focuses the search on the given area. <x1>,<y1>,<x2>,<y2> where x is longitude and y is latitude" <>
          default(),
      bounded: "Exclude any results outside the viewbox" <> zero_or_one() <> default(0),
      polygon_geojson: polygon_output_message("GeoJSON"),
      polygon_kml: polygon_output_message("KML"),
      polygon_svg: polygon_output_message("SVG"),
      polygon_text: polygon_output_message("text"),
      polygon_threshold:
        "Tolerance in degrees with which the simplified geometry may differ from the original geometry, floating-point number" <>
          default(0.0),
      email: "Valid email address (if making a large number of requests)" <> default(),
      dedupe: "Toggle the deduplication mechanism" <> default(1, :bool),
      debug: "Output assorted developer debug information in HTML" <> default(0, :bool),
      lat: "Floating-point number in range [-90, 90] (or its string representation)",
      lon: "Floating-point number in range [-180, 180) (or its string representation)",
      zoom: "Level of detail required for the address [3, 5, 8, 10, 12..18]" <> default(18),
      osmtype: "Type of OSM object, one of N (node), W (way), or R (relation)",
      osmid: "OSM ID of the object, integer",
      class:
        "Optional OSM tag to distinguish between entries, when the corresponding OSM object has more than one main tag",
      osm_ids:
        "Comma-separated list of up to 50 OSM ids each prefixed with its type, one of node(N), way(W) or relation(R).",
      format:
        "One of: xml, json, jsonv2, geojson, geocodejson, text (Default: jsonv2 for /search, xml for /reverse, text only for /status)"
    }
  end

  defp polygon_output_message(format) when is_binary(format) do
    "Polygon output in " <> format <> zero_or_one() <> default(0)
  end

  defp default, do: default("unset")

  defp default(v) when is_binary(v) do
    " (Default: " <> v <> ")"
  end

  defp default(v) when is_number(v), do: default(to_string(v))

  defp default(v, :bool) when v == 0 or v == 1 do
    zero_or_one() <> default(to_string(v) <> " or " <> int_to_bool(v))
  end

  defp int_to_bool(v) when v == 0 or v == 1 do
    to_string((v == 1 && true) || false)
  end

  defp zero_or_one, do: ", 0 or 1 (or boolean false/true)"
end
