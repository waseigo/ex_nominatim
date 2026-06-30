# SPDX-FileCopyrightText: 2026 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.TestCache do
  @moduledoc false

  use Agent

  @doc false
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc false
  def get(key) do
    Agent.get(__MODULE__, &Map.get(&1, key, :miss))
  end

  @doc false
  def put(key, value, _opts) do
    Agent.update(__MODULE__, &Map.put(&1, key, value))
  end
end
