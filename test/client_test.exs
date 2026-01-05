defmodule ExNominatim.ClientTest do
  use ExUnit.Case, async: true
  alias ExNominatim.Client

  describe "prepare/4" do
    test "supports `req_cache` opts for disabling req caching" do
      assert {:ok, req} =
               Client.prepare(:search, %{"key" => "value"}, "http://localhost:1234",
                 req_cache: false
               )

      assert req.options[:cache] == false

      # Defaults to true when not specified
      assert {:ok, req} =
               Client.prepare(:search, %{"key" => "value"}, "http://localhost:1234")

      assert req.options[:cache] == true
    end
  end
end
