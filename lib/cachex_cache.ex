# SPDX-FileCopyrightText: 2026 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.CachexCache do
  @moduledoc """
  Cache adapter for ExNominatim backed by Cachex v4.x.

  ## Usage

  Add `cachex` to your dependencies:

      {:cachex, "~> 4.1"}

  Start a Cachex instance in your supervision tree:

      children = [
        {Cachex, name: :ex_nominatim, limit: 10_000},
        ...
      ]

  Then pass the adapter to your endpoint calls:

      ExNominatim.search([q: "Athens", cache: ExNominatim.CachexCache])

  ## Configuration

      config :ex_nominatim, :cache_name, :ex_nominatim   # Cachex cache name (default: :ex_nominatim)
      config :ex_nominatim, :cache_ttl, 86_400_000        # TTL in ms (default: 24 hours)

  ## Behaviour

  - Only successful results are cached. Errors never cache.
  - If Cachex is not started or not in the dependency list, the `:cache` option
    is silently ignored.
  - Cache keys are based on endpoint and normalized query parameters.
  - This module is only compiled when Cachex is available at runtime.
  """

  @doc false
  def get(key) do
    cache_name = Application.get_env(:ex_nominatim, :cache_name, :ex_nominatim)

    case Cachex.get(cache_name, key) do
      {:ok, nil} -> :miss
      {:ok, value} -> {:ok, value}
      {:error, _} -> :miss
    end
  end

  @doc false
  def put(key, value, _opts) do
    cache_name = Application.get_env(:ex_nominatim, :cache_name, :ex_nominatim)
    ttl = Application.get_env(:ex_nominatim, :cache_ttl, 86_400_000)
    Cachex.put(cache_name, key, value, ttl: ttl)
  end
end
