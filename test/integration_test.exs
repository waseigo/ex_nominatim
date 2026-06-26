# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.IntegrationTest do
  use ExUnit.Case, async: false

  @base_url "https://nominatim.rent21.gr"
  @moduletag :integration

  alias ExNominatim.Client

  setup_all do
    Application.put_env(:ex_nominatim, ExNominatim,
      all: [base_url: @base_url, process: true, atomize: true]
    )

    on_exit(fn ->
      Application.delete_env(:ex_nominatim, ExNominatim)
    end)

    :ok
  end

  describe "search endpoint" do
    test "returns results for a freeform query" do
      assert {:ok, result} = Client.search(q: "Athens, Greece", limit: 2)
      assert %{status: 200, body: body} = result
      assert is_list(body)
      assert length(body) > 0
      assert [%{lat: _, lon: _, display_name: _} | _] = body
    end

    test "returns results for a structured query" do
      assert {:ok, result} = Client.search(city: "Athens", country: "gr", limit: 1)
      assert %{status: 200, body: body} = result
      assert is_list(body)
      assert length(body) > 0
    end

    test "respects limit parameter" do
      assert {:ok, result} = Client.search(q: "Athens", limit: 1)
      assert %{body: body} = result
      assert length(body) == 1
    end

    test "returns empty for nonexistent queries" do
      assert {:ok, result} = Client.search(q: "xyzzyplughnotreal12345")
      assert %{status: 200, body: []} = result
    end
  end

  describe "reverse endpoint" do
    test "returns address for coordinates" do
      assert {:ok, result} = Client.reverse(lat: 37.9838, lon: 23.7275)
      assert %{status: 200, body: body} = result
      assert %{type: "FeatureCollection"} = body
      assert %{features: features} = body
      assert is_list(features)
      assert length(features) > 0
    end

    test "returns geocodejson by default" do
      assert {:ok, result} = Client.reverse(lat: 37.9838, lon: 23.7275, format: "geocodejson")
      assert %{body: body} = result
      assert %{type: "FeatureCollection"} = body
    end
  end

  describe "lookup endpoint" do
    test "returns details for osm_ids" do
      assert {:ok, result} = Client.lookup(osm_ids: "N441183")
      assert %{status: 200, body: body} = result
      assert is_list(body)
      assert length(body) > 0
      assert [%{place_id: _, display_name: _} | _] = body
    end
  end

  describe "status endpoint" do
    test "returns server status" do
      assert {:ok, result} = Client.status()
      assert %{status: 200, body: body} = result
      assert %{status: 0, message: "OK"} = body
    end

    test "returns json format by default" do
      assert {:ok, result} = Client.status(format: "json")
      assert %{body: body} = result
      assert is_map(body)
      assert Map.has_key?(body, :status)
    end
  end

  describe "details endpoint" do
    test "returns details by osmtype and osmid" do
      assert {:ok, result} = Client.details(osmtype: "N", osmid: 441183)
      assert %{status: 200, body: body} = result
      assert is_map(body)
    end
  end

  describe "format negotiation" do
    test "search returns geocodejson" do
      assert {:ok, result} = Client.search(q: "Athens", format: "geocodejson")
      assert %{body: body} = result
      assert %{type: "FeatureCollection"} = body
    end

    test "search returns json" do
      assert {:ok, result} = Client.search(q: "Athens", format: "json")
      assert %{body: body} = result
      assert is_list(body)
    end

    test "search returns jsonv2" do
      assert {:ok, result} = Client.search(q: "Athens", format: "jsonv2")
      assert %{body: body} = result
      assert is_list(body)
    end

    test "search returns geojson" do
      assert {:ok, result} = Client.search(q: "Athens", format: "geojson")
      assert %{body: body} = result
      assert %{type: "FeatureCollection"} = body
    end

    test "status returns text format" do
      assert {:ok, result} = Client.status(format: "text")
      assert %{body: body} = result
      assert is_binary(body)
    end
  end

  describe "force bypass" do
    test "sends request with invalid params when force is true" do
      assert {:error, result} = Client.search(q: "Athens", force: true, format: "invalid_format")
      assert %{status: 400, errors: [{:api, _}]} = result
    end
  end

  describe "atomize flag" do
    test "returns atom keys when atomize is true" do
      assert {:ok, %Req.Response{body: body}} = Client.search(q: "Athens", atomize: true, process: false)
      assert is_list(body)
      assert [%{lat: _} | _] = body
    end

    test "returns bitstring keys when atomize is false" do
      assert {:ok, %Req.Response{body: body}} = Client.search(q: "Athens", atomize: false, process: false)
      assert is_list(body)
      assert [%{"lat" => _} | _] = body
    end
  end

  describe "process flag" do
    test "returns processed map when process is true" do
      assert {:ok, result} = Client.search(q: "Athens", process: true, atomize: false)
      assert %{status: 200, body: _} = result
    end

    test "returns raw Req.Response when process is false" do
      assert {:ok, result} = Client.search(q: "Athens", process: false, atomize: false)
      assert %Req.Response{} = result
    end
  end

  describe "User-Agent header" do
    test "includes ExNominatim version in User-Agent" do
      assert {:ok, req} = Client.prepare(:search, %{q: "Athens"}, @base_url)
      assert %Req.Request{headers: headers} = req
      assert ["ExNominatim/" <> _] = headers["user-agent"]
    end
  end

  describe "error handling" do
    test "returns error for missing required fields" do
      assert {:error, _} = Client.reverse(format: "json")
    end

    test "returns error for invalid base_url" do
      assert {:error, _} = Client.search(q: "Athens", base_url: "not-a-url")
    end

    test "returns error for extraneous fields" do
      assert {:error, _} = Client.search(bogus_field: "value")
    end
  end
end
