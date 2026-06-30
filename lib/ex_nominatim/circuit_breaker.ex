# SPDX-FileCopyrightText: 2026 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.CircuitBreaker do
  @moduledoc """
  Per-server circuit breaker backed by ETS.

  Isolates a failing Nominatim server by short-circuiting requests after a
  configurable failure threshold. Uses a lazy half-open transition — no timers,
  no GenServer. The `reset_ms` window is checked synchronously when an open
  breaker is probed.

  ## States

    * `:closed` — normal operation, requests pass through.
    * `:open` — failures have exceeded `threshold`; requests are rejected until
      `reset_ms` elapses.
    * `:half_open` — the reset window has elapsed; the next request is let
      through as a probe. On success → `:closed`, on failure → `:open`.

  ## Configuration

  Set `circuit_breaker` to configure per-server protection:

      # Enable with defaults (threshold: 5, reset_ms: 30_000)
      circuit_breaker: true

      # Full control
      circuit_breaker: [threshold: 3, reset_ms: 60_000]

      # Disabled (default)
      circuit_breaker: false

  Failures counted: transport errors, 5xx responses, and retry exhaustion.

  ## Telemetry

  Emits `[:ex_nominatim, :circuit_breaker, :state_change]` on every state
  transition with metadata `%{base_url: String.t(), from: atom, to: atom,
  reason: atom}`.
  """

  @table :ex_nominatim_circuit_breaker

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

  Returns `:ok` when the breaker is:
    * `:closed` — normal operation.
    * `:half_open` — probe request allowed.

  Returns `{:error, %{code: :circuit_open, descr: _, retry_after_ms: _}}` when
  the breaker is `:open` and the reset window has not elapsed.
  """
  def check(base_url, config_opts) do
    case Keyword.get(config_opts, :circuit_breaker, false) do
      false -> :ok
      opts when is_list(opts) -> do_check(base_url, opts)
      true -> do_check(base_url, [])
    end
  end

  defp do_check(base_url, opts) do
    init()
    reset_ms = Keyword.get(opts, :reset_ms, 30_000)

    case :ets.lookup(@table, base_url) do
      [{^base_url, state, _count, _time}] ->
        on_state(base_url, state, reset_ms)

      [] ->
        :ets.insert(@table, {base_url, :closed, 0, 0})
        :ok
    end
  end

  defp on_state(_base_url, :closed, _reset_ms), do: :ok
  defp on_state(_base_url, :half_open, _reset_ms), do: :ok

  defp on_state(base_url, {:open, _count, last_failure_time}, reset_ms) do
    elapsed = System.monotonic_time(:millisecond) - last_failure_time

    if elapsed >= reset_ms do
      :ets.insert(@table, {base_url, :half_open, 0, System.monotonic_time(:millisecond)})
      :telemetry.execute([:ex_nominatim, :circuit_breaker, :state_change], %{}, %{
        base_url: base_url, from: :open, to: :half_open, reason: :reset_window_elapsed
      })
      :ok
    else
      {:error,
       %{
         code: :circuit_open,
         descr: "Circuit breaker is open for #{base_url}",
         retry_after_ms: reset_ms - elapsed
       }}
    end
  end

  @doc """
  Record a successful request to `base_url`.

  Resets the breaker to `:closed` with zero failure count.  Idempotent —
  safe to call unconditionally after every successful response.
  """
  def record_success(base_url) do
    init()

    case :ets.lookup(@table, base_url) do
      [{^base_url, :half_open, _, _}] ->
        :ets.insert(@table, {base_url, :closed, 0, 0})
        :telemetry.execute([:ex_nominatim, :circuit_breaker, :state_change], %{}, %{
          base_url: base_url, from: :half_open, to: :closed, reason: :probe_succeeded
        })

      _ ->
        :ets.insert(@table, {base_url, :closed, 0, 0})
    end

    :ok
  end

  @doc """
  Record a failed request to `base_url`.

  Increments the failure counter and may transition the breaker from
  `:closed` → `:open` if the threshold is exceeded, or from `:half_open` →
  `:open` (probe failure).

  Respects the `circuit_breaker` config option to determine threshold.
  Safe to call for every failed response / transport error.
  """
  def record_failure(base_url, config_opts) do
    init()

    case Keyword.get(config_opts, :circuit_breaker, false) do
      false -> :ok
      opts when is_list(opts) -> do_record_failure(base_url, opts)
      true -> do_record_failure(base_url, [])
    end
  end

  defp do_record_failure(base_url, opts) do
    threshold = Keyword.get(opts, :threshold, 5)
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, base_url) do
      [{^base_url, :closed, count, _last_time}] when count + 1 >= threshold ->
        :ets.insert(@table, {base_url, {:open, count + 1, now}, 0, 0})
        :telemetry.execute([:ex_nominatim, :circuit_breaker, :state_change], %{}, %{
          base_url: base_url, from: :closed, to: :open, reason: :threshold_exceeded
        })

      [{^base_url, :closed, count, _last_time}] ->
        :ets.insert(@table, {base_url, :closed, count + 1, now})

      [{^base_url, {:open, _count, _last_time}, _, _}] ->
        # Already open — update timestamp
        :ets.insert(@table, {base_url, {:open, threshold + 1, now}, 0, 0})

      [{^base_url, :half_open, _, _}] ->
        # Probe failed, back to open
        :ets.insert(@table, {base_url, {:open, 1, now}, 0, 0})
        :telemetry.execute([:ex_nominatim, :circuit_breaker, :state_change], %{}, %{
          base_url: base_url, from: :half_open, to: :open, reason: :probe_failed
        })

      [] ->
        if 1 >= threshold do
          :ets.insert(@table, {base_url, {:open, 1, now}, 0, 0})
          :telemetry.execute([:ex_nominatim, :circuit_breaker, :state_change], %{}, %{
            base_url: base_url, from: :closed, to: :open, reason: :threshold_exceeded
          })
        else
          :ets.insert(@table, {base_url, :closed, 1, now})
        end
    end

    :ok
  end

  @doc false
  def state(base_url) do
    init()

    case :ets.lookup(@table, base_url) do
      [{^base_url, state, count, _time}] -> {:ok, %{state: state, failures: count}}
      [] -> {:ok, %{state: :uninitialized, failures: 0}}
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
