# SPDX-FileCopyrightText: 2026 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.StreamMany do
  @moduledoc """
  Concurrent batch dispatching across multiple query option sets.

  Takes a list of keyword-list option sets and fans them out as concurrent
  search requests, yielding results as a lazy `Stream` in completion order.

  ## Usage

      opts_list = [
        [q: "Athens", limit: 1],
        [q: "Paris",  limit: 1],
        [q: "London", limit: 1]
      ]

      ExNominatim.stream_many(opts_list, max_concurrency: 5)
      |> Enum.each(fn result -> IO.inspect(result) end)

  Each element in the returned stream is the full return value of
  `Client.search/1` — either `{:ok, %{status: _, body: _}}` or
  `{:error, %{code: _, descr: _}}`.

  ## Options

    * `:max_concurrency` — maximum number of in-flight HTTP requests (default `5`).

  All other keyword keys are forwarded as base options merged into each query set,
  allowing shared config like `base_url:`, `format:`, `process:`, etc.
  """

  @doc """
  Stream results for a list of query option sets concurrently.

  Accepts `list_of_opts` (a list of keyword lists, each being the options for
  a single search request) and `runner_opts` (keyword list of streaming
  parameters plus base options to merge into every query).
  """
  def stream(list_of_opts, runner_opts \\ []) when is_list(list_of_opts) and is_list(runner_opts) do
    {stream_opts, base_opts} = split_opts(runner_opts)
    max_concurrency = Keyword.get(stream_opts, :max_concurrency, 5)

    list_of_opts
    |> Task.async_stream(
      fn single_opts ->
        merged = Keyword.merge(base_opts, single_opts)
        ExNominatim.Client.search(merged)
      end,
      max_concurrency: max_concurrency,
      ordered: false,
      timeout: :infinity
    )
    |> Stream.map(&unwrap/1)
  end

  # Options consumed by stream_many itself, everything else is a base option
  @stream_keys [:max_concurrency]

  defp split_opts(runner_opts) do
    {Keyword.take(runner_opts, @stream_keys), Keyword.drop(runner_opts, @stream_keys)}
  end

  defp unwrap({:ok, result}), do: result
  defp unwrap({:exit, reason}), do: {:error, %{code: :task_failed, descr: inspect(reason)}}
end
