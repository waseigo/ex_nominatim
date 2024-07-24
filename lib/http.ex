# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.HTTP do
  @endpoints [:search, :reverse, :lookup, :status, :details]

  @moduledoc """
  Functions that prepare an HTTP request, including validating the base URL of the target Nominatim API server setting the User-Agent header automatically, and selecting all the non-nil request parameters.
  """
  @moduledoc since: "1.0.0"

  @doc """
  Prepares an HTTP request to the `endpoint` at `base_url` with the `params` map containing request parameters.

  * `endpoint` is one of `:search`, `:reverse`, `:lookup`, `:status`, `:details`.
  * `params` is a map (not a keyword list!) with the request parameters.
  * `base_url` is the the base URL of the target Nominatim API server.

  You can use this function directly if you want to bypass the more user-friendly delegate functions in the main ExNominatim module and define the `params` map directly. This function does not perform any validation of the validity of the keys in `params` for the selected endpoint, or of their respective values vs. the API endpoint's specification.
  """

  def prepare(endpoint, params, base_url)
      when endpoint in @endpoints and is_map(params) and params != %{} and is_bitstring(base_url) do
    with {:ok, %Req.Request{} = req} <- base(base_url) do
      params = keep_query_params(params)

      {:ok,
       req
       |> Req.merge(url: endpoint_url(endpoint))
       |> Req.merge(params: params)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def prepare(endpoint, _, _) when not is_atom(endpoint) and endpoint not in @endpoints do
    {:error, :invalid_endpoint}
  end

  def prepare(_, params, _) when params == %{} do
    {:error, :empty_params}
  end

  def prepare(_, params, _) when not is_map(params) do
    {:error, :invalid_params}
  end

  defp base(url) do
    with {:ok, url} <- validate_url(url) do
      {:ok,
       Req.new(
         base_url: url,
         method: :get,
         headers: %{
           user_agent: user_agent()
         },
         cache: true
       )}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp user_agent do
    client =
      __MODULE__
      |> Module.split()
      |> hd()

    version =
      client
      |> Macro.underscore()
      |> String.to_atom()
      |> Application.spec(:vsn)

    List.to_string([client, " v", version])
  end

  # Adapted from https://gist.github.com/atomkirk/74b39b5b09c7d0f21763dd55b877f998
  defp validate_url(url) do
    case URI.parse(url) do
      %URI{scheme: nil} -> {:error, :missing_scheme}
      %URI{host: nil} -> {:error, :missing_host}
      %URI{host: ""} -> {:error, :missing_host}
      %URI{host: host} when is_bitstring(host) -> {:ok, url}
    end
  end

  defp endpoint_url(endpoint) when is_atom(endpoint), do: to_string(endpoint)

  defp keep_query_params(m) when is_struct(m) do
    m |> Map.from_struct() |> keep_query_params()
  end

  defp keep_query_params(m) when is_map(m) do
    Map.filter(m, fn {k, v} -> not (is_nil(v) or k in [:errors, :valid?]) end)
  end
end
