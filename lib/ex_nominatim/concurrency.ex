# SPDX-FileCopyrightText: 2026 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Concurrency do
  @moduledoc """
  Per-server concurrency limiter backed by ETS.

  Tracks the number of in-flight requests per `base_url` using an atomic ETS
  counter (`:ets.update_counter/3`). When the limit is reached subsequent
  requests are rejected immediately — no blocking, no queue.

  ## Configuration

  Set `max_concurrency` per request or globally:

      # Limit to 5 concurrent requests (non-blocking)
      max_concurrency: 5

      # No limit (default)
      max_concurrency: :infinity

  ## Behaviour

    * The limiter is checked **before** the HTTP dispatch.
    * `acquire/2` atomically increments the counter and returns `:ok` if the
      slot is available, or `{:error, %{code: :max_concurrency_reached}}`.
    * `release/1` decrements the counter after the request completes
      (success or failure).
    * ETS table is created lazily on first use — no supervision tree.
  """

  @table :ex_nominatim_concurrency

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
  Acquire a concurrency slot for `base_url`.

  Returns `:ok` when the current in-flight count is below `max_concurrency`,
  or `{:error, %{code: :max_concurrency_reached, descr: _}}` when at capacity.
  """
  def acquire(base_url, config_opts) do
    case Keyword.get(config_opts, :max_concurrency, :infinity) do
      :infinity ->
        :ok

      max when is_integer(max) and max > 0 ->
        do_acquire(base_url, max)

      _ ->
        :ok
    end
  end

  defp do_acquire(base_url, max) do
    init()

    # Ensure entry exists
    :ets.insert_new(@table, {base_url, 0})

    current = :ets.update_counter(@table, base_url, {2, 1})

    if current > max do
      # Roll back the increment
      :ets.update_counter(@table, base_url, {2, -1})
      {:error,
       %{
         code: :max_concurrency_reached,
         descr: "Max concurrency of #{max} reached for #{base_url}"
       }}
    else
      :ok
    end
  end

  @doc """
  Release a concurrency slot for `base_url`.

  Decrements the in-flight counter. Safe to call even after the limiter has
  been disabled or if the table is empty.
  """
  def release(base_url) do
    if :ets.whereis(@table) != :undefined and :ets.member(@table, base_url) do
      :ets.update_counter(@table, base_url, {2, -1, 0, 0})
    end

    :ok
  end

  @doc """
  Get the current in-flight count for `base_url`.
  """
  def current_count(base_url) do
    init()

    case :ets.lookup(@table, base_url) do
      [{^base_url, count}] -> count
      [] -> 0
    end
  end

  @doc false
  def clear do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end
end
