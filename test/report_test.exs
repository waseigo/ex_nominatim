# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.ReportTest do
  use ExUnit.Case, async: true

  alias ExNominatim.Report

  defmodule TestErrorStruct do
    defstruct [:errors]
  end

  describe "atomize/1" do
    test "converts bitstring map keys to atoms" do
      result = Report.atomize(%{"foo" => "bar", "baz" => 1})
      assert %{foo: "bar", baz: 1} = result
    end

    test "replaces dashes with underscores in keys" do
      result = Report.atomize(%{"content-type" => "application/json"})
      assert %{content_type: "application/json"} = result
    end

    test "recursively converts nested maps" do
      result = Report.atomize(%{"outer" => %{"inner-key" => "value"}})
      assert %{outer: %{inner_key: "value"}} = result
    end

    test "recursively converts maps inside lists" do
      result = Report.atomize([%{"a-b" => 1}, %{"c-d" => 2}])
      assert [%{a_b: 1}, %{c_d: 2}] = result
    end

    test "converts structs to atoms while preserving struct type" do
      alias ExNominatim.Client.SearchParams
      params = %SearchParams{q: "test", format: "json"}
      result = Report.atomize(params)
      assert %SearchParams{format: "json"} = result
    end

    test "returns nil for nil input" do
      assert Report.atomize(nil) == nil
    end

    test "passes through non-map non-list values" do
      assert "hello" = Report.atomize("hello")
      assert 42 = Report.atomize(42)
      assert :atom = Report.atomize(:atom)
    end

    test "handles empty map" do
      assert %{} = Report.atomize(%{})
    end

    test "handles empty list" do
      assert [] = Report.atomize([])
    end
  end

  describe "process/1" do
    test "returns ok for 200 response with no error in body" do
      resp = %Req.Response{status: 200, body: %{"result" => "ok"}}
      assert {:ok, %{status: 200, body: %{"result" => "ok"}}} = Report.process({:ok, resp})
    end

    test "returns error for 200 response with error key in body" do
      resp = %Req.Response{status: 200, body: %{"error" => "Something went wrong"}}
      assert {:error, result} = Report.process({:ok, resp})
      assert result.status == 200
      assert result.body == nil
      assert {:api, "Something went wrong"} in result.errors
    end

    test "returns error for non-200 response with XML error body" do
      resp = %Req.Response{status: 500, body: "<error>Service unavailable</error>"}
      assert {:error, result} = Report.process({:ok, resp})
      assert result.status == 500
      assert result.body == nil
      assert {:api, "Service unavailable"} in result.errors
    end

    test "returns error for non-200 response with map error body" do
      resp = %Req.Response{status: 404, body: %{"error" => "Not found", "code" => 404}}
      assert {:error, result} = Report.process({:ok, resp})
      assert result.status == 404
      assert result.body == nil
      assert {:api, "Not found"} in result.errors
    end

    test "extracts error from XML error response" do
      xml_body = "<error>Bad request</error>"
      resp = %Req.Response{status: 200, body: xml_body}
      assert {:error, result} = Report.process({:ok, resp})
      assert result.body == nil
      assert {:api, "Bad request"} in result.errors
    end

    test "passes through error tuples with tuple payload" do
      assert {:error, {:custom, :reason}} = Report.process({:error, {:custom, :reason}})
    end

    test "handles error struct with errors field" do
      err_struct = %TestErrorStruct{errors: [validation: "failed"]}
      assert {:error, result} = Report.process({:error, err_struct})
      assert result.errors == [validation: "failed"]
      assert result.body == nil
    end

    test "handles error map with body containing error" do
      err_map = %{body: %{"error" => "Not found"}, status: 404}
      assert {:error, result} = Report.process({:error, err_map})
      assert result.status == 404
      assert {:api, "Not found"} in result.errors
    end

    test "handles list body as success" do
      resp = %Req.Response{status: 200, body: [%{"place_id" => 1}]}
      assert {:ok, %{status: 200, body: _}} = Report.process({:ok, resp})
    end

    test "handles string body without error tag as success" do
      resp = %Req.Response{status: 200, body: "OK"}
      assert {:ok, %{status: 200, body: "OK"}} = Report.process({:ok, resp})
    end
  end
end
