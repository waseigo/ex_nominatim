# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Client.Request do
  @moduledoc false

  @doc """
  Build a base Req request with the given URL.
  """
  def base(url) do
    case validate_url(url) do
      {:ok, url} ->
        {:ok,
         Req.new(
           base_url: url,
           method: :get,
           headers: %{
             user_agent: default_user_agent()
           },
           cache: true
         )}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_user_agent do
    client =
      ExNominatim.Client
      |> Module.split()
      |> hd()

    version =
      client
      |> Macro.underscore()
      |> String.to_atom()
      |> Application.spec(:vsn)

    List.to_string([client, "/", version])
  end

  # Adapted from https://gist.github.com/atomkirk/74b39b5b09c7d0f21763dd55b877f998
  defp validate_url(url) do
    case URI.parse(url) do
      %URI{scheme: nil} -> {:error, %{code: :validation, descr: "URL missing scheme"}}
      %URI{host: nil} -> {:error, %{code: :validation, descr: "URL missing host"}}
      %URI{host: ""} -> {:error, %{code: :validation, descr: "URL missing host"}}
      %URI{host: host} when is_binary(host) -> {:ok, url}
    end
  end

  @doc """
  Apply user-provided Req options.
  """
  def apply_req_opts(req, config_opts) do
    case Keyword.get(config_opts, :req_opts) do
      nil -> req
      opts when is_list(opts) -> Req.merge(req, opts)
    end
  end

  @doc """
  Apply timeout and user-agent HTTP options.
  """
  def apply_http_options(req, config_opts) do
    req
    |> apply_timeout(config_opts)
    |> apply_user_agent(config_opts)
  end

  defp apply_timeout(req, config_opts) do
    case Keyword.get(config_opts, :timeout) do
      nil -> req
      ms when is_integer(ms) and ms > 0 ->
        Req.merge(req, connect_options: [timeout: ms], receive_timeout: ms)
    end
  end

  defp apply_user_agent(req, config_opts) do
    case Keyword.get(config_opts, :user_agent) do
      nil -> req
      ua when is_binary(ua) -> Req.merge(req, headers: %{user_agent: ua})
    end
  end
end
