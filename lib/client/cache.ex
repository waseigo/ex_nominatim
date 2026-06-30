# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Client.Cache do
  @moduledoc false

  @doc """
  Build a cache key string from an action and params struct.
  """
  def key(action, params, validation_keys \\ [:valid?, :errors]) when is_struct(params) do
    params
    |> Map.from_struct()
    |> Map.drop(validation_keys)
    |> Enum.filter(fn {_, v} -> not is_nil(v) end)
    |> Enum.sort()
    |> then(fn kvs -> "ex_nominatim:#{action}:#{inspect(kvs)}" end)
  end

  @doc """
  Look up a key in the cache. Returns `{:ok, data}`, `{:error, _}`, or `:miss`.
  """
  def get(nil, _key), do: :miss

  def get(cache, key) do
    case ExNominatim.Cache.get(cache, key) do
      {:ok, {:error, _} = error} -> error
      {:ok, _} = hit -> hit
      :miss -> :miss
      {:error, _} = direct_error -> direct_error
      data when not is_nil(data) -> {:ok, data}
      nil -> :miss
    end
  end

  @doc """
  Store a successful result in the cache.
  """
  def store(nil, _key, _result), do: :ok

  def store(cache, key, {:ok, data}) do
    ExNominatim.Cache.put(cache, key, data, [])
  end

  @doc """
  Optionally store an error result in the cache based on config.
  """
  def store_error(_cache, _key, _result, _config_opts)

  def store_error(nil, _key, _result, _config_opts), do: :ok

  def store_error(cache, key, {:error, %{code: :api_error}} = result, config_opts) do
    if Keyword.get(config_opts, :cache_errors, false) do
      ttl = Keyword.get(config_opts, :cache_error_ttl, 30_000)
      ExNominatim.Cache.put(cache, key, result, ttl: ttl)
    end

    :ok
  end

  def store_error(_cache, _key, _result, _config_opts), do: :ok
end
