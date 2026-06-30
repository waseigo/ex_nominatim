# SPDX-FileCopyrightText: 2026 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.ConcurrencyTest do
  use ExUnit.Case, async: true

  setup do
    ExNominatim.Concurrency.clear()
    :ok
  end

  @base_url "https://example.com/api"

  describe "acquire/2 with max_concurrency: :infinity" do
    test "always allows" do
      assert :ok = ExNominatim.Concurrency.acquire(@base_url, max_concurrency: :infinity)
      assert :ok = ExNominatim.Concurrency.acquire(@base_url, max_concurrency: :infinity)
    end
  end

  describe "acquire/2 with finite limit" do
    test "allows up to max" do
      cfg = [max_concurrency: 2]

      assert :ok = ExNominatim.Concurrency.acquire(@base_url, cfg)
      assert :ok = ExNominatim.Concurrency.acquire(@base_url, cfg)

      assert {:error, %{code: :max_concurrency_reached}} =
               ExNominatim.Concurrency.acquire(@base_url, cfg)
    end

    test "allows after release" do
      cfg = [max_concurrency: 1]

      assert :ok = ExNominatim.Concurrency.acquire(@base_url, cfg)
      ExNominatim.Concurrency.release(@base_url)
      assert :ok = ExNominatim.Concurrency.acquire(@base_url, cfg)
    end

    test "tracks different URLs independently" do
      cfg = [max_concurrency: 1]

      assert :ok = ExNominatim.Concurrency.acquire(@base_url, cfg)
      assert :ok = ExNominatim.Concurrency.acquire("https://other.com", cfg)

      # original URL is at capacity
      assert {:error, %{code: :max_concurrency_reached}} =
               ExNominatim.Concurrency.acquire(@base_url, cfg)
    end
  end

  describe "current_count/1" do
    test "returns 0 for unknown URL" do
      assert 0 == ExNominatim.Concurrency.current_count(@base_url)
    end

    test "returns current in-flight count" do
      cfg = [max_concurrency: 5]
      ExNominatim.Concurrency.acquire(@base_url, cfg)
      ExNominatim.Concurrency.acquire(@base_url, cfg)

      assert 2 == ExNominatim.Concurrency.current_count(@base_url)
    end

    test "decrements on release" do
      cfg = [max_concurrency: 5]
      ExNominatim.Concurrency.acquire(@base_url, cfg)
      ExNominatim.Concurrency.acquire(@base_url, cfg)
      ExNominatim.Concurrency.release(@base_url)

      assert 1 == ExNominatim.Concurrency.current_count(@base_url)
    end
  end

  describe "clear/0" do
    test "resets all counters" do
      ExNominatim.Concurrency.acquire(@base_url, max_concurrency: 5)
      ExNominatim.Concurrency.clear()
      assert 0 == ExNominatim.Concurrency.current_count(@base_url)
    end
  end
end
