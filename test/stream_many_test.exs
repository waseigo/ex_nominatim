# SPDX-FileCopyrightText: 2026 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.StreamManyTest do
  use ExUnit.Case, async: true

  setup do
    # Initialize ETS tables from the test process so they are NOT owned by
    # ephemeral Task.async_stream processes (which would delete the tables
    # on exit, racing with sibling tasks still in flight).
    ExNominatim.CircuitBreaker.init()
    ExNominatim.Concurrency.init()
    ExNominatim.RateLimiter.init()
    :ok
  end

  describe "stream_many/2" do
    test "returns empty stream for empty list" do
      assert [] == ExNominatim.stream_many([]) |> Enum.to_list()
    end

    test "returns results for multiple queries using a plug module adapter" do
      results =
        [[q: "a", test_adapter: ExNominatim.StreamManyTest.SearchOK, rate_limit: false],
         [q: "b", test_adapter: ExNominatim.StreamManyTest.SearchOK, rate_limit: false]]
        |> ExNominatim.stream_many(rate_limit: false)
        |> Enum.to_list()

      assert length(results) == 2
      assert {:ok, %{body: [%{q: "ok"}]}} = hd(results)
    end

    test "merges runner_opts into each query" do
      results =
        [[q: "test_a"], [q: "test_b"]]
        |> ExNominatim.stream_many(
          format: "json",
          test_adapter: ExNominatim.StreamManyTest.SearchOK,
          rate_limit: false
        )
        |> Enum.to_list()

      assert length(results) == 2
    end

    test "runs all queries and returns results" do
      results =
        [1, 2, 3]
        |> Enum.map(fn n ->
          [q: "test_#{n}", test_adapter: ExNominatim.StreamManyTest.SearchOK,
           rate_limit: false]
        end)
        |> ExNominatim.stream_many(max_concurrency: 3, rate_limit: false)
        |> Enum.to_list()

      assert length(results) == 3
    end

    test "returns error results when queries fail" do
      results =
        [[q: "fail", test_adapter: ExNominatim.StreamManyTest.Search500,
          rate_limit: false]]
        |> ExNominatim.stream_many(rate_limit: false)
        |> Enum.to_list()

      assert length(results) == 1
      assert {:error, %{code: :api_error}} = hd(results)
    end
  end

  # Module-level plug adapters — available in every process, no process-dict needed.
  # These are used by Task.async_stream which spawns tasks in separate processes.

  defmodule SearchOK do
    use Plug.Router

    plug :match
    plug :dispatch

    get "/search" do
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!([%{q: "ok"}]))
    end

    match _ do
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/plain")
      |> Plug.Conn.send_resp(404, "not found")
    end
  end

  defmodule Search500 do
    use Plug.Router

    plug :match
    plug :dispatch

    match _ do
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/plain")
      |> Plug.Conn.send_resp(500, "Error")
    end
  end
end
