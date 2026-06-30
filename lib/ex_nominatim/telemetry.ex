# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Telemetry do
  @moduledoc """
  Telemetry events emitted by ExNominatim.

  ## Events

  ### `[:ex_nominatim, :request, :stop]`
  Emitted when a request completes successfully.

  * Measurement: `%{duration: integer}` (native time)
  * Metadata: `%{endpoint: atom, base_url: String.t(), status: integer}`

  ### `[:ex_nominatim, :request, :exception]`
  Emitted when a request fails with an error (API error, transport error, etc.).

  * Measurement: `%{duration: integer}` (native time)
  * Metadata: `%{endpoint: atom, base_url: String.t(), error: term}`

  ### `[:ex_nominatim, :request, :retry]`
  Emitted when a failed request is retried with network-level backoff.

  * Measurement: `%{}`
  * Metadata: `%{endpoint: atom, base_url: String.t(), attempt: integer, error: term}`

  ### `[:ex_nominatim, :cache, :hit]`
  Emitted when a cached response is returned.

  * Measurement: `%{}`
  * Metadata: `%{endpoint: atom}`

  ### `[:ex_nominatim, :cache, :miss]`
  Emitted when no cached response is found.

  * Measurement: `%{}`
  * Metadata: `%{endpoint: atom}`

  ### `[:ex_nominatim, :rate_limit, :deny]`
  Emitted when a request is rate-limited.

  * Measurement: `%{}`
  * Metadata: `%{endpoint: atom, base_url: String.t(), retry_after_ms: integer}`

  ### `[:ex_nominatim, :circuit_breaker, :state_change]`
  Emitted when the circuit breaker transitions to a new state.

  * Measurement: `%{}`
  * Metadata: `%{base_url: String.t(), from: atom, to: atom, reason: atom}`
  """

  @doc false
  def cache_hit(endpoint) do
    :telemetry.execute([:ex_nominatim, :cache, :hit], %{}, %{endpoint: endpoint})
  end

  @doc false
  def cache_miss(endpoint) do
    :telemetry.execute([:ex_nominatim, :cache, :miss], %{}, %{endpoint: endpoint})
  end

  @doc false
  def rate_limit_deny(endpoint, base_url, retry_after_ms) do
    :telemetry.execute([:ex_nominatim, :rate_limit, :deny], %{}, %{
      endpoint: endpoint,
      base_url: base_url,
      retry_after_ms: retry_after_ms
    })
  end

  @doc false
  def retry_attempt(endpoint, base_url, attempt, error) do
    :telemetry.execute([:ex_nominatim, :request, :retry], %{}, %{
      endpoint: endpoint,
      base_url: base_url,
      attempt: attempt,
      error: error
    })
  end
end
