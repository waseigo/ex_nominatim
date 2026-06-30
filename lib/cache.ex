# SPDX-FileCopyrightText: 2026 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defprotocol ExNominatim.Cache do
  @moduledoc """
  Protocol for cache adapters used by ExNominatim.

  Implement this protocol to provide custom caching backends. The built-in
  `ExNominatim.CachexCache` adapter caches via Cachex v4.x.

  When a cache module implements `get/1` and `put/3` functions, the
  `ExNominatim.Cache` protocol is automatically dispatched via the
  `defimpl for: Atom` fallback — no explicit `defimpl` needed.
  """

  @doc """
  Retrieve a cached value by key.
  Returns `{:ok, value}` on hit, `:miss` on miss.
  """
  def get(cache, key)

  @doc """
  Store a value in the cache with the given TTL options.
  """
  def put(cache, key, value, opts)
end

defimpl ExNominatim.Cache, for: Atom do
  def get(cache, key), do: cache.get(key)
  def put(cache, key, value, opts), do: cache.put(key, value, opts)
end
