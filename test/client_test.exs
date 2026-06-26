# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.ClientTest do
  use ExUnit.Case, async: true

  alias ExNominatim.Client
  alias ExNominatim.Client.{SearchParams, ReverseParams, LookupParams, DetailsParams, StatusParams}

  describe "struct construction via new/3" do
    test "SearchParams accepts keyword list with q" do
      assert {:ok, %SearchParams{q: "Athens"}} = SearchParams.new(q: "Athens")
    end

    test "SearchParams accepts keyword list with structured fields" do
      assert {:ok, %SearchParams{city: "Athens"}} = SearchParams.new(city: "Athens")
    end

    test "ReverseParams requires lat and lon" do
      assert {:ok, %ReverseParams{lat: 37.98, lon: 23.72}} = ReverseParams.new(lat: 37.98, lon: 23.72)
      assert {:error, {:missing_query_params, [:lat, :lon]}} = ReverseParams.new(lat: 37.98)
      assert {:error, {:missing_query_params, [:lat, :lon]}} = ReverseParams.new([])
    end

    test "LookupParams requires osm_ids" do
      assert {:ok, %LookupParams{osm_ids: "N123"}} = LookupParams.new(osm_ids: "N123")
      assert {:error, {:missing_query_params, [:osm_ids]}} = LookupParams.new([])
    end

    test "DetailsParams accepts empty keyword list" do
      assert {:ok, %DetailsParams{}} = DetailsParams.new([])
    end

    test "StatusParams accepts empty keyword list" do
      assert {:ok, %StatusParams{}} = StatusParams.new([])
    end

    test "StatusParams accepts format" do
      assert {:ok, %StatusParams{format: "json"}} = StatusParams.new(format: "json")
    end
  end

  describe "extraneous field detection via generic/2" do
    test "SearchParams rejects extraneous fields" do
      assert {:error, {:extraneous_fields, [:unknown_field]}} =
               Client.search(unknown_field: "value")
    end

    test "ReverseParams rejects extraneous fields" do
      assert {:error, {:extraneous_fields, [:bogus]}} =
               Client.reverse(lat: 37.98, lon: 23.72, bogus: "x")
    end

    test "LookupParams rejects extraneous fields" do
      assert {:error, {:extraneous_fields, [:extra]}} =
               Client.lookup(osm_ids: "N123", extra: "y")
    end

    test "DetailsParams rejects extraneous fields" do
      assert {:error, {:extraneous_fields, [:nope]}} =
               Client.details(nope: "z")
    end

    test "StatusParams rejects extraneous fields" do
      assert {:error, {:extraneous_fields, [:wrong]}} =
               Client.status(wrong: "v")
    end
  end

  describe "prepare/3" do
    test "builds a valid Req.Request for search" do
      assert {:ok, %Req.Request{}} = Client.prepare(:search, %{q: "Athens"}, "https://nominatim.openstreetmap.org")
    end

    test "rejects empty params" do
      assert {:error, :empty_params} = Client.prepare(:search, %{}, "https://example.com")
    end

    test "rejects non-map params" do
      assert {:error, :invalid_params} = Client.prepare(:search, "not_a_map", "https://example.com")
    end

    test "rejects URL without scheme" do
      assert {:error, :missing_scheme} = Client.prepare(:search, %{q: "x"}, "nominatim.org")
    end

    test "rejects URL without host" do
      assert {:error, :missing_host} = Client.prepare(:search, %{q: "x"}, "https://")
    end
  end

  describe "URL validation" do
    test "accepts valid https URL" do
      assert {:ok, _} = Client.prepare(:status, %{format: "json"}, "https://nominatim.openstreetmap.org")
    end

    test "accepts valid http URL" do
      assert {:ok, _} = Client.prepare(:status, %{format: "json"}, "http://localhost:8080")
    end
  end

  describe "query param filtering" do
    test "filters out nil values from params" do
      assert {:ok, _} = Client.prepare(:search, %{q: "Athens", limit: nil}, "https://example.com")
    end

    test "filters out valid? and errors keys from params" do
      assert {:ok, _} =
               Client.prepare(:search, %{q: "Athens", valid?: true, errors: []}, "https://example.com")
    end

    test "filters out config-specific keys from params" do
      assert {:ok, _} =
               Client.prepare(:search, %{q: "Athens", base_url: "x", force: true, process: true, atomize: true},
                 "https://example.com")
    end
  end
end
