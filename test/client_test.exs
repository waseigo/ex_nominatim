# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.ClientTest do
  use ExUnit.Case, async: true

  alias ExNominatim.Client
  alias ExNominatim.Client.{DetailsParams, LookupParams, ReverseParams, SearchParams, StatusParams}

  describe "struct construction via new/3" do
    test "SearchParams accepts keyword list with q" do
      assert {:ok, %SearchParams{q: "Athens"}} = SearchParams.new(q: "Athens")
    end

    test "SearchParams accepts keyword list with structured fields" do
      assert {:ok, %SearchParams{city: "Athens"}} = SearchParams.new(city: "Athens")
    end

    test "ReverseParams requires lat and lon" do
      assert {:ok, %ReverseParams{lat: 37.98, lon: 23.72}} = ReverseParams.new(lat: 37.98, lon: 23.72)
      assert {:error, %{code: :validation, missing: [:lat, :lon]}} = ReverseParams.new(lat: 37.98)
      assert {:error, %{code: :validation, missing: [:lat, :lon]}} = ReverseParams.new([])
    end

    test "LookupParams requires osm_ids" do
      assert {:ok, %LookupParams{osm_ids: "N123"}} = LookupParams.new(osm_ids: "N123")
      assert {:error, %{code: :validation, missing: [:osm_ids]}} = LookupParams.new([])
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
      assert {:error, %{code: :validation, extraneous_fields: [:unknown_field]}} =
               Client.search(unknown_field: "value")
    end

    test "ReverseParams rejects extraneous fields" do
      assert {:error, %{code: :validation, extraneous_fields: [:bogus]}} =
               Client.reverse(lat: 37.98, lon: 23.72, bogus: "x")
    end

    test "LookupParams rejects extraneous fields" do
      assert {:error, %{code: :validation, extraneous_fields: [:extra]}} =
               Client.lookup(osm_ids: "N123", extra: "y")
    end

    test "DetailsParams rejects extraneous fields" do
      assert {:error, %{code: :validation, extraneous_fields: [:nope]}} =
               Client.details(nope: "z")
    end

    test "StatusParams rejects extraneous fields" do
      assert {:error, %{code: :validation, extraneous_fields: [:wrong]}} =
               Client.status(wrong: "v")
    end
  end

  describe "prepare/3" do
    test "builds a valid Req.Request for search" do
      assert {:ok, %Req.Request{}} = Client.prepare(:search, %{q: "Athens"}, "https://nominatim.openstreetmap.org")
    end

    test "rejects empty params" do
      assert {:error, %{code: :validation, descr: "Params must not be empty"}} = Client.prepare(:search, %{}, "https://example.com")
    end

    test "rejects non-map params" do
      assert {:error, %{code: :validation, descr: "Params must be a map"}} = Client.prepare(:search, "not_a_map", "https://example.com")
    end

    test "rejects URL without scheme" do
      assert {:error, %{code: :validation, descr: "URL missing scheme"}} = Client.prepare(:search, %{q: "x"}, "nominatim.org")
    end

    test "rejects URL without host" do
      assert {:error, %{code: :validation, descr: "URL missing host"}} = Client.prepare(:search, %{q: "x"}, "https://")
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

  describe "caching via TestCache" do
    setup do
      # Clear TestCache before each test
      Agent.update(ExNominatim.TestCache, fn _ -> %{} end)
      :ok
    end

    test "caches successful results" do
      Req.Test.stub(:nominatim, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{place_id: 123, display_name: "Athens"}]))
      end)

      opts = [
        q: "Athens",
        limit: 1,
        format: "json",
        cache: ExNominatim.TestCache,
        test_adapter: {Req.Test, :nominatim}
      ]

      assert {:ok, result} = Client.search(opts)
      # Second call should hit cache, same result
      assert {:ok, ^result} = Client.search(opts)
    end

    test "does not cache errors" do
      Req.Test.stub(:nominatim_err, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(400, Jason.encode!(%{"error" => "Bad request"}))
      end)

      opts = [
        q: "Athens",
        format: "json",
        cache: ExNominatim.TestCache,
        test_adapter: {Req.Test, :nominatim_err},
        rate_limit: false
      ]

      assert {:error, _} = Client.search(opts)

      # Error should not be cached — changing stub should return new result
      Req.Test.stub(:nominatim_err, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{place_id: 999}]))
      end)

      assert {:ok, %{body: [%{place_id: 999}]}} = Client.search(opts)
    end

    test "misses cache when cache option is not given" do
      Req.Test.stub(:no_cache, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{counter: "1"}]))
      end)

      opts = [
        q: "Athens",
        limit: 1,
        format: "json",
        test_adapter: {Req.Test, :no_cache},
        rate_limit: false
      ]

      assert {:ok, _} = Client.search(opts)
      # Without cache, each call goes to the adapter
      assert {:ok, _} = Client.search(opts)
    end
  end

  describe "Req.Test stub integration" do
    test "uses test_adapter for isolated HTTP stubbing" do
      Req.Test.stub(:my_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{result: "stubbed"}]))
      end)

      assert {:ok, result} =
               Client.search(q: "test", format: "json", test_adapter: {Req.Test, :my_stub}, rate_limit: false)

      assert %{status: 200, body: [%{result: "stubbed"}]} = result
    end

    test "works with reverse endpoint" do
      Req.Test.stub(:reverse_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"type" => "FeatureCollection"}))
      end)

      assert {:ok, result} =
               Client.reverse(
                 lat: 37.98,
                 lon: 23.72,
                 format: "geocodejson",
                 test_adapter: {Req.Test, :reverse_stub},
                 rate_limit: false
               )

      assert %{status: 200, body: %{type: "FeatureCollection"}} = result
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

  describe "rate limiting via RateLimiter" do
    setup do
      ExNominatim.RateLimiter.clear()
      :ok
    end

    test "allows first request immediately" do
      assert :ok = ExNominatim.RateLimiter.check("https://example.com", 1000)
    end

    test "blocks second request within interval" do
      url = "https://example.com"
      assert :ok = ExNominatim.RateLimiter.check(url, 1000)
      assert {:error, %{code: :rate_limited, retry_after_ms: retry_after}} = ExNominatim.RateLimiter.check(url, 1000)
      assert is_integer(retry_after) and retry_after > 0
    end

    test "allows request after interval has elapsed" do
      url = "https://example.com"
      assert :ok = ExNominatim.RateLimiter.check(url, 5)
      :timer.sleep(10)
      assert :ok = ExNominatim.RateLimiter.check(url, 5)
    end

    test "tracks different URLs independently" do
      assert :ok = ExNominatim.RateLimiter.check("https://server-a.com", 1000)
      assert :ok = ExNominatim.RateLimiter.check("https://server-b.com", 1000)
    end

    test "public_server? detects Nominatim public API" do
      assert ExNominatim.RateLimiter.public_server?("https://nominatim.openstreetmap.org")
      assert ExNominatim.RateLimiter.public_server?("https://nominatim.openstreetmap.org/search")
      refute ExNominatim.RateLimiter.public_server?("http://localhost:8080")
      refute ExNominatim.RateLimiter.public_server?("https://custom.server.com")
    end
  end

  describe "rate limiting integration in Client" do
    setup do
      ExNominatim.RateLimiter.clear()
      :ok
    end

    @tag :rate_limit
    test "passes through with rate_limit: false" do
      Req.Test.stub(:rl_false, fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!([%{q: "ok"}]))
      end)

      assert {:ok, _} =
               Client.search(q: "test", limit: 1, format: "json",
                 test_adapter: {Req.Test, :rl_false},
                 rate_limit: false)
    end

    @tag :rate_limit
    test "passes through for custom base_url with :auto" do
      Req.Test.stub(:rl_auto, fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!([%{q: "ok"}]))
      end)

      assert {:ok, _} =
               Client.search(q: "test", limit: 1, format: "json",
                 test_adapter: {Req.Test, :rl_auto},
                 base_url: "http://localhost:8080",
                 rate_limit: :auto)
    end

    @tag :rate_limit
    test "allows burst up to integer RPS limit" do
      url = "https://my-server.com"

      # 100 rps → 10ms interval
      assert :ok = ExNominatim.RateLimiter.check(url, 10)
      assert {:error, %{code: :rate_limited}} = ExNominatim.RateLimiter.check(url, 10)
      :timer.sleep(12)
      assert :ok = ExNominatim.RateLimiter.check(url, 10)
    end

    @tag :rate_limit
    test "rejects zero or negative rps as :ok (treated as off)" do
      Req.Test.stub(:rl_zero, fn conn ->
        Plug.Conn.resp(conn, 200, Jason.encode!([%{q: "ok"}]))
      end)

      # Negative RPS falls through — use false instead
      assert {:ok, _} =
               Client.search(q: "test", limit: 1, format: "json",
                 test_adapter: {Req.Test, :rl_zero},
                 base_url: "https://nominatim.openstreetmap.org",
                 rate_limit: -1)
    end
  end

  describe "telemetry events" do
    setup do
      ExNominatim.RateLimiter.clear()
      Agent.update(ExNominatim.TestCache, fn _ -> %{} end)
      :ok
    end

    test "emits cache hit and miss events" do
      _ref = :telemetry.attach("test-cache", [:ex_nominatim, :cache, :hit],
        fn name, measurements, metadata, _config ->
          send(self(), {name, measurements, metadata})
        end, nil)

      :telemetry.attach("test-cache-miss", [:ex_nominatim, :cache, :miss],
        fn name, measurements, metadata, _config ->
          send(self(), {name, measurements, metadata})
        end, nil)

      Req.Test.stub(:tel, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{q: "ok"}]))
      end)

      opts = [q: "test", limit: 1, format: "json",
        test_adapter: {Req.Test, :tel},
        cache: ExNominatim.TestCache,
        rate_limit: false]

      assert {:ok, _} = Client.search(opts)
      assert_received {[:ex_nominatim, :cache, :miss], %{}, %{endpoint: :search}}

      assert {:ok, _} = Client.search(opts)
      assert_received {[:ex_nominatim, :cache, :hit], %{}, %{endpoint: :search}}

      :telemetry.detach("test-cache")
      :telemetry.detach("test-cache-miss")
    end

    test "emits request stop event on success" do
      _ref = :telemetry.attach("test-req", [:ex_nominatim, :request, :stop],
        fn name, measurements, metadata, _config ->
          send(self(), {name, measurements, metadata})
        end, nil)

      Req.Test.stub(:tel2, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{q: "ok"}]))
      end)

      assert {:ok, _} = Client.search(q: "test", format: "json",
        test_adapter: {Req.Test, :tel2}, rate_limit: false)

      assert_received {[:ex_nominatim, :request, :stop], %{duration: _}, %{endpoint: :search}}

      :telemetry.detach("test-req")
    end

    test "emits rate limit deny event" do
      ExNominatim.RateLimiter.clear()
      url = "https://nominatim.openstreetmap.org"
      ExNominatim.RateLimiter.check(url, 1000)

      _ref = :telemetry.attach("test-rl", [:ex_nominatim, :rate_limit, :deny],
        fn name, measurements, metadata, _config ->
          send(self(), {name, measurements, metadata})
        end, nil)

      Req.Test.stub(:tel3, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{q: "ok"}]))
      end)

      assert {:error, %{code: :rate_limited}} = Client.search(q: "test", format: "json",
        test_adapter: {Req.Test, :tel3}, rate_limit: true)

      assert_received {[:ex_nominatim, :rate_limit, :deny], %{},
        %{endpoint: :search, retry_after_ms: _}}

      :telemetry.detach("test-rl")
    end
  end

  describe "search_one" do
    setup do
      ExNominatim.RateLimiter.clear()
      :ok
    end

    test "returns single result from list" do
      ExNominatim.RateLimiter.clear()
      Req.Test.stub(:so1, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{place_id: 1}]))
      end)

      assert {:ok, %{place_id: 1}} = ExNominatim.search_one(q: "test", format: "json",
        test_adapter: {Req.Test, :so1}, rate_limit: false)
    end

    test "returns :not_found on empty list" do
      ExNominatim.RateLimiter.clear()
      Req.Test.stub(:so2, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([]))
      end)

      assert {:error, %{code: :not_found}} = ExNominatim.search_one(q: "test", format: "json",
        test_adapter: {Req.Test, :so2}, rate_limit: false)
    end

    test "returns multiple_results error" do
      ExNominatim.RateLimiter.clear()
      Req.Test.stub(:so3, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{place_id: 1}, %{place_id: 2}]))
      end)

      assert {:error, %{code: :multiple_results, count: 2}} = ExNominatim.search_one(q: "test", format: "json",
        test_adapter: {Req.Test, :so3}, rate_limit: false)
    end

    test "search_one! returns result or raises" do
      ExNominatim.RateLimiter.clear()
      Req.Test.stub(:so4, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{place_id: 1}]))
      end)

      assert %{place_id: 1} = ExNominatim.search_one!(q: "test", format: "json",
        test_adapter: {Req.Test, :so4}, rate_limit: false)
    end
  end

  describe "custom req_opts" do
    setup do
      ExNominatim.RateLimiter.clear()
      :ok
    end

    test "passes through custom req_opts without error" do
      Req.Test.stub(:ropts, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{q: "ok"}]))
      end)

      assert {:ok, _} = Client.search(q: "test", format: "json",
        test_adapter: {Req.Test, :ropts},
        rate_limit: false,
        req_opts: [headers: [accept: "application/json"]])
    end
  end

  describe "geohash" do
    setup do
      ExNominatim.RateLimiter.clear()
      :ok
    end

    test "adds geohash to results with lat/lon" do
      Req.Test.stub(:ghash, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{lat: "38.0", lon: "23.7", place_id: 1}]))
      end)

      assert {:ok, %{body: [result]}} = Client.search(q: "test", limit: 1, format: "json",
        test_adapter: {Req.Test, :ghash},
        rate_limit: false,
        geohash: true)

      assert is_binary(result.geohash)
      assert String.length(result.geohash) == 12
    end

    test "skips geohash when geohash: false" do
      Req.Test.stub(:ghash2, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{lat: "38.0", lon: "23.7", place_id: 1}]))
      end)

      assert {:ok, %{body: [result]}} = Client.search(q: "test", limit: 1, format: "json",
        test_adapter: {Req.Test, :ghash2},
        rate_limit: false,
        geohash: false)

      refute Map.has_key?(result, :geohash)
    end
  end

  describe "rate_limit_retry" do
    setup do
      ExNominatim.RateLimiter.clear()
      :ok
    end

    test "retries after rate limit" do
      url = "https://nominatim.openstreetmap.org"
      # Saturate the rate limiter with a 5ms interval
      assert :ok = ExNominatim.RateLimiter.check(url, 5)

      Req.Test.stub(:retry_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{q: "ok"}]))
      end)

      # rate_limit: 200 → 5ms interval, should trigger then retry
      assert {:ok, _} = Client.search(q: "test", limit: 1, format: "json",
        test_adapter: {Req.Test, :retry_stub},
        rate_limit: 200,
        rate_limit_retry: true)
    end
  end

  describe "network-level retry (transport / 5xx)" do
    setup do
      ExNominatim.RateLimiter.clear()
      ExNominatim.CircuitBreaker.clear()
      ExNominatim.Concurrency.clear()
      :ok
    end

    test "retries on 5xx response" do
      attempts = :atomics.new(1, [])

      Req.Test.stub(:retry_5xx, fn conn ->
        :atomics.add(attempts, 1, 1)
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/plain")
        |> Plug.Conn.resp(500, "Internal Server Error")
      end)

      opts = [q: "test", format: "json",
        test_adapter: {Req.Test, :retry_5xx},
        rate_limit: false,
        retry: [max_retries: 2, base_delay: 1]]

      Client.search(opts)

      assert :atomics.get(attempts, 1) == 3  # original + 2 retries
    end

    test "retries on 429 response from server" do
      attempts = :atomics.new(1, [])

      Req.Test.stub(:retry_429, fn conn ->
        :atomics.add(attempts, 1, 1)
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/plain")
        |> Plug.Conn.resp(429, "Too Many Requests")
      end)

      opts = [q: "test", format: "json",
        test_adapter: {Req.Test, :retry_429},
        rate_limit: false,
        retry: [max_retries: 1, base_delay: 1]]

      Client.search(opts)

      assert :atomics.get(attempts, 1) == 2
    end

    test "does not retry on 4xx response" do
      attempts = :atomics.new(1, [])

      Req.Test.stub(:retry_4xx, fn conn ->
        :atomics.add(attempts, 1, 1)
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/plain")
        |> Plug.Conn.resp(400, "Bad Request")
      end)

      opts = [q: "test", format: "json",
        test_adapter: {Req.Test, :retry_4xx},
        rate_limit: false,
        retry: [max_retries: 3, base_delay: 1]]

      Client.search(opts)

      assert :atomics.get(attempts, 1) == 1  # no retry on 4xx
    end

    test "succeeds on retry after initial 5xx" do
      counter = :atomics.new(1, [])

      Req.Test.stub(:retry_then_ok, fn conn ->
        :atomics.add(counter, 1, 1)
        # OTP 27+: add/3 returns :ok, so we use get/2 to read the new value
        call_n = :atomics.get(counter, 1)
        if call_n == 1 do
          conn
          |> Plug.Conn.put_resp_header("content-type", "text/plain")
          |> Plug.Conn.resp(500, "Retry")
        else
          conn
          |> Plug.Conn.put_resp_header("content-type", "application/json")
          |> Plug.Conn.resp(200, Jason.encode!([%{q: "ok"}]))
        end
      end)

      opts = [q: "test", limit: 1, format: "json",
        test_adapter: {Req.Test, :retry_then_ok},
        rate_limit: false,
        retry: [max_retries: 1, base_delay: 1]]

      result = Client.search(opts)
      assert {:ok, %{body: [%{q: "ok"}]}} = result
      assert :atomics.get(counter, 1) == 2
    end

    test "emits telemetry on retry" do
      Req.Test.stub(:retry_tel, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/plain")
        |> Plug.Conn.resp(500, "Error")
      end)

      :telemetry.attach("test-retry", [:ex_nominatim, :request, :retry],
        fn _name, _measurements, metadata, _config ->
          send(self(), {:retry_event, metadata})
        end, nil)

      opts = [q: "test", format: "json",
        test_adapter: {Req.Test, :retry_tel},
        rate_limit: false,
        retry: [max_retries: 1, base_delay: 1]]

      Client.search(opts)

      assert_received {:retry_event, %{endpoint: :search, attempt: 1}}

      :telemetry.detach("test-retry")
    end

    test "retry: true defaults to 3 retries" do
      attempts = :atomics.new(1, [])

      Req.Test.stub(:retry_true, fn conn ->
        :atomics.add(attempts, 1, 1)
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/plain")
        |> Plug.Conn.resp(500, "Error")
      end)

      opts = [q: "test", format: "json",
        test_adapter: {Req.Test, :retry_true},
        rate_limit: false,
        retry: true]

      Client.search(opts)

      # original + 3 retries = 4
      assert :atomics.get(attempts, 1) == 4
    end
  end

  describe "timeout config" do
    test "applies timeout through req_opts" do
      Req.Test.stub(:timeout_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{q: "ok"}]))
      end)

      assert {:ok, _} = Client.search(q: "test", limit: 1, format: "json",
        test_adapter: {Req.Test, :timeout_stub},
        rate_limit: false,
        timeout: 10_000)
    end
  end

  describe "user_agent config" do
    test "allows custom user_agent" do
      Req.Test.stub(:ua_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{q: "ok"}]))
      end)

      assert {:ok, _} = Client.search(q: "test", limit: 1, format: "json",
        test_adapter: {Req.Test, :ua_stub},
        rate_limit: false,
        user_agent: "MyApp/1.0")
    end
  end

  describe "circuit breaker integration" do
    setup do
      ExNominatim.RateLimiter.clear()
      ExNominatim.CircuitBreaker.clear()
      :ok
    end

    test "opens after threshold failures and rejects subsequent requests" do
      attempts = :atomics.new(1, [])

      Req.Test.stub(:cb_stub, fn conn ->
        :atomics.add(attempts, 1, 1)
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/plain")
        |> Plug.Conn.resp(500, "Error")
      end)

      # threshold: 2 → after 2 failures, circuit opens
      opts = [q: "test", format: "json",
        test_adapter: {Req.Test, :cb_stub},
        rate_limit: false,
        circuit_breaker: [threshold: 2, reset_ms: 5000],
        retry: false]

      # First failure
      Client.search(opts)
      # Second failure — opens the circuit
      Client.search(opts)
      # Third attempt should be rejected by the breaker, not hit the stub
      assert {:error, %{code: :circuit_open}} = Client.search(opts)

      # Stub should have been called only twice
      assert :atomics.get(attempts, 1) == 2
    end
  end

  describe "error caching" do
    setup do
      ExNominatim.RateLimiter.clear()
      Agent.update(ExNominatim.TestCache, fn _ -> %{} end)
      :ok
    end

    test "caches api_error when cache_errors: true" do
      Req.Test.stub(:ec_stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(400, Jason.encode!(%{"error" => "Bad request"}))
      end)

      opts = [q: "test", format: "json",
        test_adapter: {Req.Test, :ec_stub},
        cache: ExNominatim.TestCache,
        rate_limit: false,
        cache_errors: true]

      assert {:error, %{code: :api_error}} = Client.search(opts)

      # Second call should return cached error, not call the stub
      Req.Test.stub(:ec_stub2, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!([%{q: "should_not_reach"}]))
      end)

      assert {:error, %{code: :api_error}} = Client.search(opts)
    end

    test "does not cache errors by default" do
      attempts = :atomics.new(1, [])

      Req.Test.stub(:ec_stub3, fn conn ->
        :atomics.add(attempts, 1, 1)
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(400, Jason.encode!(%{"error" => "Bad"}))
      end)

      opts = [q: "test", format: "json",
        test_adapter: {Req.Test, :ec_stub3},
        cache: ExNominatim.TestCache,
        rate_limit: false]

      Client.search(opts)
      Client.search(opts)
      assert :atomics.get(attempts, 1) == 2
    end
  end

  describe "healthy?" do
    setup do
      ExNominatim.RateLimiter.clear()
      :ok
    end

    test "returns {:ok, true} when status returns 200 with OK body" do
      Req.Test.stub(:h1, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/plain")
        |> Plug.Conn.resp(200, "OK")
      end)

      assert {:ok, true} = ExNominatim.healthy?(
        test_adapter: {Req.Test, :h1}, rate_limit: false, format: "text")
    end

    test "returns {:ok, false} when status returns 200 with non-OK body" do
      Req.Test.stub(:h2, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/plain")
        |> Plug.Conn.resp(200, "Maintenance")
      end)

      assert {:ok, false} = ExNominatim.healthy?(
        test_adapter: {Req.Test, :h2}, rate_limit: false, format: "text")
    end

    test "returns {:ok, false} when status returns error" do
      Req.Test.stub(:h3, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "text/plain")
        |> Plug.Conn.resp(500, "Error")
      end)

      assert {:ok, false} = ExNominatim.healthy?(
        test_adapter: {Req.Test, :h3}, rate_limit: false)
    end
  end
end
