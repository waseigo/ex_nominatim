# SPDX-FileCopyrightText: 2026 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.CircuitBreakerTest do
  use ExUnit.Case, async: true

  setup do
    ExNominatim.CircuitBreaker.clear()
    :ok
  end

  @base_url "https://example.com/api"
  @config_opts [circuit_breaker: [threshold: 3, reset_ms: 50]]

  describe "check/2 with circuit_breaker disabled" do
    test "always returns :ok when disabled" do
      assert :ok = ExNominatim.CircuitBreaker.check(@base_url, [])
      assert :ok = ExNominatim.CircuitBreaker.check(@base_url, circuit_breaker: false)
    end
  end

  describe "check/2 and record_failure/2" do
    test "returns :ok when closed" do
      assert :ok = ExNominatim.CircuitBreaker.check(@base_url, @config_opts)
    end

    test "opens after threshold failures" do
      # 3 failures → open
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)

      assert {:error, %{code: :circuit_open}} =
               ExNominatim.CircuitBreaker.check(@base_url, @config_opts)
    end

    test "allows requests before threshold" do
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)

      assert :ok = ExNominatim.CircuitBreaker.check(@base_url, @config_opts)
    end
  end

  describe "half-open probe" do
    test "transitions to half-open after reset window elapses, success closes it" do
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)

      # Open
      assert {:error, %{code: :circuit_open}} =
               ExNominatim.CircuitBreaker.check(@base_url, @config_opts)

      # Wait for reset window
      :timer.sleep(60)

      # Should be half-open now → allow probe
      assert :ok = ExNominatim.CircuitBreaker.check(@base_url, @config_opts)

      # Record success → should close
      ExNominatim.CircuitBreaker.record_success(@base_url)

      # Now closed again
      assert {:ok, %{state: :closed}} = ExNominatim.CircuitBreaker.state(@base_url)
    end

    test "half-open probe failure reopens the breaker" do
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)

      # Wait for reset
      :timer.sleep(60)

      # Half-open probe allowed
      assert :ok = ExNominatim.CircuitBreaker.check(@base_url, @config_opts)

      # Probe fails
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)

      # Back to open
      assert {:error, %{code: :circuit_open}} =
               ExNominatim.CircuitBreaker.check(@base_url, @config_opts)
    end
  end

  describe "record_success/1" do
    test "always resets to closed regardless of current state" do
      # Record a failure to initialize state
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)
      ExNominatim.CircuitBreaker.record_success(@base_url)
      assert {:ok, %{state: :closed, failures: 0}} = ExNominatim.CircuitBreaker.state(@base_url)
    end
  end

  describe "state/1" do
    test "returns uninitialized for unknown base_url" do
      assert {:ok, %{state: :uninitialized, failures: 0}} =
               ExNominatim.CircuitBreaker.state("https://unknown.com")
    end

    test "returns closed after successful check" do
      ExNominatim.CircuitBreaker.check(@base_url, @config_opts)
      assert {:ok, %{state: :closed, failures: 0}} = ExNominatim.CircuitBreaker.state(@base_url)
    end

    test "returns open state after threshold" do
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)

      assert {:ok, %{state: {:open, 3, _}}} = ExNominatim.CircuitBreaker.state(@base_url)
    end
  end

  describe "config parsing" do
    test "circuit_breaker: true uses defaults (threshold: 5)" do
      # With default threshold 5, 4 failures should still be closed
      Enum.each(1..4, fn _ ->
        ExNominatim.CircuitBreaker.record_failure(@base_url, circuit_breaker: true)
      end)

      assert :ok = ExNominatim.CircuitBreaker.check(@base_url, circuit_breaker: true)

      # 5th failure opens
      ExNominatim.CircuitBreaker.record_failure(@base_url, circuit_breaker: true)
      assert {:error, %{code: :circuit_open}} =
               ExNominatim.CircuitBreaker.check(@base_url, circuit_breaker: true)
    end

    test "respects custom threshold and reset_ms" do
      cfg = [circuit_breaker: [threshold: 1, reset_ms: 5000]]
      ExNominatim.CircuitBreaker.record_failure(@base_url, cfg)
      assert {:error, %{code: :circuit_open}} = ExNominatim.CircuitBreaker.check(@base_url, cfg)
    end
  end

  describe "clear/0" do
    test "clears all state" do
      ExNominatim.CircuitBreaker.record_failure(@base_url, @config_opts)
      ExNominatim.CircuitBreaker.clear()
      assert {:ok, %{state: :uninitialized}} = ExNominatim.CircuitBreaker.state(@base_url)
    end
  end
end
