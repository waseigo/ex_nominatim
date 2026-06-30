# Telemetry

ExNominatim emits structured telemetry events for observability in production.
All events use the `[:ex_nominatim, ...]` prefix and can be consumed via
`:telemetry.attach/4` or integrated into your metrics pipeline (e.g. `TelemetryMetrics`, `Appsignal`, `Datadog`).

## Events

### `[:ex_nominatim, :request, :stop]`

Emitted when a request completes successfully.

| Field | Type | Description |
|---|---|---|
| **Measurement** | | |
| `duration` | `integer` | Request duration in native time |
| **Metadata** | | |
| `endpoint` | `atom` | One of `:search`, `:reverse`, `:lookup`, `:details`, `:status` |
| `base_url` | `String.t()` | The Nominatim server URL |
| `status` | `integer` | HTTP response status code |

### `[:ex_nominatim, :request, :exception]`

Emitted when a request fails (transport error, API error, etc.).

| Field | Type | Description |
|---|---|---|
| **Measurement** | | |
| `duration` | `integer` | Request duration in native time |
| **Metadata** | | |
| `endpoint` | `atom` | One of `:search`, `:reverse`, `:lookup`, `:details`, `:status` |
| `base_url` | `String.t()` | The Nominatim server URL |
| `error` | `term()` | The error reason |

### `[:ex_nominatim, :request, :retry]`

Emitted before each network-level retry attempt (exponential backoff).

| Field | Type | Description |
|---|---|---|
| **Measurement** | `%{}` | Empty |
| **Metadata** | | |
| `endpoint` | `atom` | One of `:search`, `:reverse`, `:lookup`, `:details`, `:status` |
| `base_url` | `String.t()` | The Nominatim server URL |
| `attempt` | `integer` | Current retry attempt number (1-based) |
| `error` | `term()` | The error that triggered the retry |

### `[:ex_nominatim, :cache, :hit]`

Emitted when a cached response is returned (no HTTP request made).

| Field | Type | Description |
|---|---|---|
| **Measurement** | `%{}` | Empty |
| **Metadata** | | |
| `endpoint` | `atom` | One of `:search`, `:reverse`, `:lookup`, `:details`, `:status` |

### `[:ex_nominatim, :cache, :miss]`

Emitted when no cached response is found (HTTP request proceeds).

| Field | Type | Description |
|---|---|---|
| **Measurement** | `%{}` | Empty |
| **Metadata** | | |
| `endpoint` | `atom` | One of `:search`, `:reverse`, `:lookup`, `:details`, `:status` |

### `[:ex_nominatim, :rate_limit, :deny]`

Emitted when a request is rejected by the rate limiter.

| Field | Type | Description |
|---|---|---|
| **Measurement** | `%{}` | Empty |
| **Metadata** | | |
| `endpoint` | `atom` | One of `:search`, `:reverse`, `:lookup`, `:details`, `:status` |
| `base_url` | `String.t()` | The server URL that was rate-limited |
| `retry_after_ms` | `integer` | Milliseconds until the next allowed request |

### `[:ex_nominatim, :circuit_breaker, :state_change]`

Emitted when the circuit breaker transitions between states.

| Field | Type | Description |
|---|---|---|
| **Measurement** | `%{}` | Empty |
| **Metadata** | | |
| `base_url` | `String.t()` | The server URL the breaker is tracking |
| `from` | `atom` | Previous state (`:closed`, `:open`, `:half_open`) |
| `to` | `atom` | New state |
| `reason` | `atom` | Transition cause (`:failure_count`, `:reset_timeout`, `:probe_success`, etc.) |

## Usage Examples

### Attach a Logger handler

```elixir
:telemetry.attach(
  "ex-nominatim-request-logger",
  [:ex_nominatim, :request, :stop],
  fn event, measurements, metadata, _config ->
    Logger.info("[ExNominatim] #{metadata.endpoint} " <>
      "-> #{metadata.status} in #{measurements.duration}")
  end,
  nil
)
```

### Track request duration with TelemetryMetrics

```elixir
# In your application
children = [
  {:telemetry_metrics_statsd, metrics: metrics()}
]

defp metrics do
  [
    summary("ex_nominatim.request.stop.duration",
      tags: [:endpoint, :status],
      unit: {:native, :millisecond}
    ),
    counter("ex_nominatim.cache.hit",
      tags: [:endpoint]
    ),
    counter("ex_nominatim.cache.miss",
      tags: [:endpoint]
    ),
    counter("ex_nominatim.rate_limit.deny",
      tags: [:endpoint, :base_url]
    ),
    counter("ex_nominatim.circuit_breaker.state_change",
      tags: [:base_url, :from, :to]
    )
  ]
end
```

### Count cache hit/miss ratio

```elixir
defmodule ExNominatim.CacheMonitor do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{hits: 0, misses: 0}, name: __MODULE__)
  end

  def init(state) do
    :telemetry.attach_many(
      "ex-nominatim-cache-monitor",
      [
        [:ex_nominatim, :cache, :hit],
        [:ex_nominatim, :cache, :miss]
      ],
      &handle_event/4,
      nil
    )
    {:ok, state}
  end

  defp handle_event([:ex_nominatim, :cache, :hit], _measurements, _metadata, _config) do
    GenServer.cast(__MODULE__, :hit)
  end

  defp handle_event([:ex_nominatim, :cache, :miss], _measurements, _metadata, _config) do
    GenServer.cast(__MODULE__, :miss)
  end

  def handle_cast(:hit, state), do: {:noreply, %{state | hits: state.hits + 1}}
  def handle_cast(:miss, state), do: {:noreply, %{state | misses: state.misses + 1}}
end
```

### Monitor circuit breaker state changes

```elixir
:telemetry.attach(
  "ex-nominatim-circuit-breaker",
  [:ex_nominatim, :circuit_breaker, :state_change],
  fn _event, _measurements, metadata, _config ->
    if metadata.to == :open do
      Logger.warning("[ExNominatim] Circuit opened for #{metadata.base_url} " <>
        "(reason: #{metadata.reason})")
    end
  end,
  nil
)
```

## Event Reference

| Event | Measurement | Metadata | Emitted By |
|---|---|---|---|
| `[:ex_nominatim, :request, :stop]` | `duration` | `endpoint`, `base_url`, `status` | `Client` |
| `[:ex_nominatim, :request, :exception]` | `duration` | `endpoint`, `base_url`, `error` | `Client` |
| `[:ex_nominatim, :request, :retry]` | — | `endpoint`, `base_url`, `attempt`, `error` | `ExNominatim.Telemetry` |
| `[:ex_nominatim, :cache, :hit]` | — | `endpoint` | `ExNominatim.Telemetry` |
| `[:ex_nominatim, :cache, :miss]` | — | `endpoint` | `ExNominatim.Telemetry` |
| `[:ex_nominatim, :rate_limit, :deny]` | — | `endpoint`, `base_url`, `retry_after_ms` | `ExNominatim.Telemetry` |
| `[:ex_nominatim, :circuit_breaker, :state_change]` | — | `base_url`, `from`, `to`, `reason` | `CircuitBreaker` |

## See Also

- `ExNominatim.Telemetry` — module documentation with event type specs
- [Telemetry project](https://hex.pm/packages/telemetry) — official telemetry package
- [TelemetryMetrics](https://hex.pm/packages/telemetry_metrics) — metrics aggregation
