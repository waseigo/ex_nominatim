# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.RateLimiter do
  @moduledoc """
  Best-effort per-server rate limiter backed by ETS.

  Tracks the last request timestamp per `base_url` and rejects requests that
  arrive before `min_interval_ms` has elapsed. Uses an ETS named table with
  `write_concurrency: true` so concurrent calls do not serialise through a
  single GenServer.

  ## Behaviour

    * `{:ok, _}` responses are stored and subsequent identical requests return
      the cached result without hitting the rate limit.
    * Only **cache misses** are subject to rate limiting — the rate limiter is
      checked between the cache lookup and the HTTP dispatch.
    * The ETS table is created lazily on first use — no supervision tree or
      application callback required.
    * Errors return `{:error, %{code: :rate_limited, descr: _, retry_after_ms: _}}`.
  """

  @table :ex_nominatim_rate_limiter

  @doc false
  def init do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Check whether a request to `base_url` is allowed.

  Returns `:ok` if the minimum interval has elapsed since the last request, or
  `{:error, %{code: :rate_limited, descr: "Rate limit exceeded", retry_after_ms: retry_after_ms}}`
  if the interval has not elapsed.

  ## Parameters

    * `base_url` — the server URL string (e.g. `"https://nominatim.openstreetmap.org"`).
    * `min_interval_ms` — minimum time in milliseconds between requests.

  """
  def check(base_url, min_interval_ms) do
    init()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, base_url) do
      [{^base_url, last}] ->
        elapsed = now - last

        if elapsed >= min_interval_ms do
          :ets.insert(@table, {base_url, now})
          :ok
        else
          {:error, %{code: :rate_limited, descr: "Rate limit exceeded", retry_after_ms: min_interval_ms - elapsed}}
        end

      [] ->
        :ets.insert(@table, {base_url, now})
        :ok
    end
  end

  @doc false
  def clear do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  @doc false
  def public_server?(base_url) do
    String.contains?(base_url, "nominatim.openstreetmap.org")
  end
end
