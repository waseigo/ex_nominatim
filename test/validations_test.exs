# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.ValidationsTest do
  use ExUnit.Case, async: true

  alias ExNominatim.Client.{
    DetailsParams,
    LookupParams,
    ReverseParams,
    SearchParams,
    StatusParams
  }

  alias ExNominatim.Validations

  describe "validate/1 for SearchParams" do
    test "accepts a valid freeform query" do
      assert {:ok, params} = SearchParams.new(q: "Athens")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "accepts a valid structured query" do
      assert {:ok, params} = SearchParams.new(city: "Athens", country: "gr")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "rejects both freeform and structured query (confusing intent)" do
      assert {:ok, params} = SearchParams.new(q: "Athens", city: "Athens")
      assert {:error, %{code: :validation, errors: errors}} = Validations.validate(params)
      assert errors != []
      assert Enum.any?(errors, &match?({:confusing_intent, _}, &1))
    end

    test "rejects neither freeform nor structured query" do
      assert {:ok, params} = SearchParams.new(format: "json")
      assert {:error, %{code: :validation, errors: errors}} = Validations.validate(params)
      assert errors != []
      assert Enum.any?(errors, &match?({:missing_query_params, _}, &1))
    end

    test "accepts partial structured query with only one field" do
      assert {:ok, params} = SearchParams.new(city: "Athens")
      assert {:ok, %{valid?: true}} = Validations.validate(params)
    end

    test "rejects invalid format for search" do
      assert {:ok, params} = SearchParams.new(q: "Athens", format: "txt")
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end

    test "accepts all valid formats" do
      for format <- ~w|xml json jsonv2 geojson geocodejson| do
        assert {:ok, params} = SearchParams.new(q: "Athens", format: format)
        assert {:ok, %{valid?: true}} = Validations.validate(params)
      end
    end

    test "rejects limit out of range" do
      assert {:ok, params} = SearchParams.new(q: "Athens", limit: 0)
      assert       {:error, %{code: :validation}} = Validations.validate(params)

      assert {:ok, params2} = SearchParams.new(q: "Athens", limit: 41)
      assert       {:error, %{code: :validation}} = Validations.validate(params2)
    end

    test "accepts limit at boundaries" do
      assert {:ok, params1} = SearchParams.new(q: "Athens", limit: 1)
      assert {:ok, %{valid?: true}} = Validations.validate(params1)

      assert {:ok, params40} = SearchParams.new(q: "Athens", limit: 40)
      assert {:ok, %{valid?: true}} = Validations.validate(params40)
    end

    test "rejects invalid country codes" do
      assert {:ok, params} = SearchParams.new(q: "Athens", countrycodes: "XX,ZZ")
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end

    test "accepts valid country codes" do
      assert {:ok, params} = SearchParams.new(q: "Athens", countrycodes: "gr,de")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "rejects invalid language codes" do
      assert {:ok, params} = SearchParams.new(q: "Athens", accept_language: "xx,yy")
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end

    test "accepts valid language codes" do
      assert {:ok, params} = SearchParams.new(q: "Athens", accept_language: "en,el")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "rejects invalid layer values" do
      assert {:ok, params} = SearchParams.new(q: "Athens", layer: "invalid_layer")
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end

    test "accepts valid layer values" do
      assert {:ok, params} = SearchParams.new(q: "Athens", layer: "address,poi")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "rejects invalid viewbox" do
      assert {:ok, params} = SearchParams.new(q: "Athens", viewbox: "1,2,3")
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end

    test "accepts valid viewbox" do
      assert {:ok, params} = SearchParams.new(q: "Athens", viewbox: "23.0,37.0,24.0,38.0")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "rejects invalid email" do
      assert {:ok, params} = SearchParams.new(q: "Athens", email: "not-an-email")
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end

    test "accepts valid email" do
      assert {:ok, params} = SearchParams.new(q: "Athens", email: "test@example.com")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "rejects invalid featureType" do
      assert {:ok, params} = SearchParams.new(q: "Athens", featureType: "village")
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end

    test "accepts valid featureType" do
      assert {:ok, params} = SearchParams.new(q: "Athens", featureType: "city")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "rejects invalid zoom" do
      assert {:ok, params} = SearchParams.new(q: "Athens", zoom: 4)
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end

    test "accepts valid zoom values" do
      for z <- [3, 5, 8, 10, 12, 15, 18] do
        assert {:ok, params} = SearchParams.new(q: "Athens", zoom: z)
        assert {:ok, %{valid?: true}} = Validations.validate(params)
      end
    end

    test "rejects zero_or_one fields with invalid values" do
      assert {:ok, params} = SearchParams.new(q: "Athens", addressdetails: 2)
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end

    test "accepts zero_or_one fields with boolean values" do
      assert {:ok, params} = SearchParams.new(q: "Athens", extratags: true)
      assert {:ok, %{valid?: true}} = Validations.validate(params)
    end

    test "accepts zero_or_one fields with string values" do
      assert {:ok, params} = SearchParams.new(q: "Athens", namedetails: "1")
      assert {:ok, %{valid?: true}} = Validations.validate(params)
    end
  end

  describe "validate/1 for ReverseParams" do
    test "accepts valid reverse params" do
      assert {:ok, params} = ReverseParams.new(lat: 37.9838, lon: 23.7275)
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "accepts string coordinates" do
      assert {:ok, params} = ReverseParams.new(lat: "37.9838", lon: "23.7275")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "rejects missing lat" do
      assert {:ok, base} = ReverseParams.new(lat: 37.9838, lon: 23.7275)
      params = %{base | lat: nil}
      assert {:error, %{code: :validation, errors: errors}} = Validations.validate(params)
      assert Enum.any?(errors, &match?({:missing_query_params, _}, &1))
    end

    test "rejects missing lon" do
      assert {:ok, base} = ReverseParams.new(lat: 37.9838, lon: 23.7275)
      params = %{base | lon: nil}
      assert {:error, %{code: :validation, errors: errors}} = Validations.validate(params)
      assert Enum.any?(errors, &match?({:missing_query_params, _}, &1))
    end

    test "rejects both missing" do
      assert {:ok, base} = ReverseParams.new(lat: 37.9838, lon: 23.7275)
      params = %{base | lat: nil, lon: nil}
      assert {:error, %{code: :validation, errors: errors}} = Validations.validate(params)
      assert Enum.any?(errors, &match?({:missing_query_params, _}, &1))
    end

    test "rejects lat out of range" do
      assert {:ok, params} = ReverseParams.new(lat: 91.0, lon: 23.7275)
      assert       {:error, %{code: :validation}} = Validations.validate(params)

      assert {:ok, params2} = ReverseParams.new(lat: -91.0, lon: 23.7275)
      assert       {:error, %{code: :validation}} = Validations.validate(params2)
    end

    test "rejects lon out of range" do
      assert {:ok, params} = ReverseParams.new(lat: 37.9838, lon: 180.0)
      assert       {:error, %{code: :validation}} = Validations.validate(params)

      assert {:ok, params2} = ReverseParams.new(lat: 37.9838, lon: -181.0)
      assert       {:error, %{code: :validation}} = Validations.validate(params2)
    end

    test "accepts boundary coordinates" do
      assert {:ok, params} = ReverseParams.new(lat: 90.0, lon: 179.999)
      assert {:ok, %{valid?: true}} = Validations.validate(params)

      assert {:ok, params2} = ReverseParams.new(lat: -90.0, lon: -180.0)
      assert {:ok, %{valid?: true}} = Validations.validate(params2)
    end

    test "rejects invalid format for reverse" do
      assert {:ok, params} = ReverseParams.new(lat: 37.9838, lon: 23.7275, format: "html")
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end
  end

  describe "validate/1 for LookupParams" do
    test "accepts valid osm_ids" do
      assert {:ok, params} = LookupParams.new(osm_ids: "N96954428")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "accepts multiple osm_ids" do
      assert {:ok, params} = LookupParams.new(osm_ids: "N96954428,W12345,R99")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "rejects missing osm_ids" do
      assert {:ok, base} = LookupParams.new(osm_ids: "N96954428")
      params = %{base | osm_ids: nil}
      assert {:error, %{code: :validation, errors: errors}} = Validations.validate(params)
      assert Enum.any?(errors, &match?({:missing_query_params, _}, &1))
    end

    test "rejects invalid osm_id format" do
      assert {:ok, params} = LookupParams.new(osm_ids: "12345")
      assert       {:error, %{code: :validation}} = Validations.validate(params)

      assert {:ok, params2} = LookupParams.new(osm_ids: "X12345")
      assert       {:error, %{code: :validation}} = Validations.validate(params2)
    end
  end

  describe "validate/1 for DetailsParams" do
    test "accepts place_id query" do
      assert {:ok, params} = DetailsParams.new(place_id: 12_345)
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "accepts osmtype + osmid query" do
      assert {:ok, params} = DetailsParams.new(osmtype: "N", osmid: 96_954_428)
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "rejects both place_id and osmtype+osmid" do
      assert {:ok, params} = DetailsParams.new(place_id: 12_345, osmtype: "N", osmid: 96_954_428)
      assert {:error, %{code: :validation, errors: errors}} = Validations.validate(params)
      assert Enum.any?(errors, &match?({:confusing_intent, _}, &1))
    end

    test "rejects neither place_id nor osmtype+osmid" do
      assert {:ok, base} = DetailsParams.new(place_id: 12_345)
      params = %{base | place_id: nil}
      assert {:error, %{code: :validation, errors: errors}} = Validations.validate(params)
      assert Enum.any?(errors, &match?({:missing_query_params, _}, &1))
    end

    test "rejects invalid osmtype" do
      assert {:ok, params} = DetailsParams.new(osmtype: "X", osmid: 123)
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end

    test "rejects non-string osmtype" do
      assert {:ok, params} = DetailsParams.new(osmtype: 123, osmid: 456)
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end

    test "rejects non-numeric osmid" do
      assert {:ok, params} = DetailsParams.new(osmtype: "N", osmid: "abc")
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end

    test "rejects format other than json for details" do
      assert {:ok, params} = DetailsParams.new(place_id: 123, format: "xml")
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end
  end

  describe "validate/1 for StatusParams" do
    test "accepts empty status params" do
      assert {:ok, params} = StatusParams.new([])
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "accepts json format" do
      assert {:ok, params} = StatusParams.new(format: "json")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "accepts text format" do
      assert {:ok, params} = StatusParams.new(format: "text")
      assert {:ok, %{valid?: true, errors: []}} = Validations.validate(params)
    end

    test "rejects invalid format for status" do
      assert {:ok, params} = StatusParams.new(format: "xml")
      assert       {:error, %{code: :validation}} = Validations.validate(params)
    end
  end

  describe "sanitize_comma_separated_strings/1" do
    test "collapses spaces in comma-separated values" do
      assert {:ok, params} = SearchParams.new(q: "Athens", countrycodes: "gr, de , fr")
      result = Validations.sanitize_comma_separated_strings(params)
      assert result.countrycodes == "gr,de,fr"
    end

    test "trims leading and trailing commas" do
      assert {:ok, params} = SearchParams.new(q: "Athens", exclude_place_ids: ",1,2,3,")
      result = Validations.sanitize_comma_separated_strings(params)
      assert result.exclude_place_ids == "1,2,3"
    end

    test "does not modify non-target fields" do
      assert {:ok, params} = SearchParams.new(q: "Athens", limit: 10)
      result = Validations.sanitize_comma_separated_strings(params)
      assert result.limit == 10
      assert result.q == "Athens"
    end
  end

  describe "explain_fields/0" do
    test "returns a map of all field explanations" do
      fields = Validations.explain_fields()
      assert is_map(fields)
      assert Map.has_key?(fields, :q)
      assert Map.has_key?(fields, :lat)
      assert Map.has_key?(fields, :format)
      assert Map.has_key?(fields, :osm_ids)
    end
  end

  describe "explain_fields/1 for structs" do
    test "returns explanations for the struct's permitted keys" do
      fields = Validations.explain_fields(%SearchParams{})
      assert Map.has_key?(fields, :q)
      refute Map.has_key?(fields, :lat)
    end
  end

  describe "explain_fields/1 for atoms" do
    test "returns explanations for an endpoint atom" do
      fields = Validations.explain_fields(:search)
      assert Map.has_key?(fields, :q)
      assert Map.has_key?(fields, :viewbox)
    end

    test "returns explanation for a single field atom" do
      msg = Validations.explain_fields(:lat)
      assert is_binary(msg)
    end
  end
end
