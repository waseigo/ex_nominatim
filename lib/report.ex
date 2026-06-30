# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Report do
  @moduledoc """
  Functions for reporting processed responses from the Nominatim API.
  """
  @moduledoc since: "1.1.0"

  @doc """
  Convert the output of any of the endpoint functions to a more usable map.
  """
  def process({:ok, %Req.Response{body: body} = resp}) do
    if resp.status == 200 and not detect_error_in_body(body) do
      {:ok, %{status: resp.status, body: resp.body}}
    else
      msg = extract_error_from_body(body) || "Unknown API error"
      {:error, %{code: :api_error, descr: msg, status: resp.status}}
    end
  end

  def process({:error, %Req.Response{body: body} = resp}) do
    msg = extract_error_from_body(body) || "HTTP #{resp.status}"
    {:error, %{code: :api_error, descr: msg, status: resp.status}}
  end

  def process({:error, s}) when is_struct(s) do
    {:error, %{code: :validation, descr: "Field validation failed", errors: s.errors}}
  end

  def process({:error, %{body: body} = s}) do
    msg = extract_error_from_body(body) || "Unknown error"
    {:error, %{code: :api_error, descr: msg, status: s[:status]}}
  end

  def process({:error, t} = v) when is_tuple(t), do: v

  defp detect_error_in_body(body) do
    cond do
      is_list(body) -> false
      is_map(body) -> "error" in Map.keys(body)
      is_binary(body) -> String.contains?(body, "<error>")
    end
  end

  defp extract_error_from_body(body) do
    cond do
      is_binary(body) -> extract_error_from_xml(body)
      is_map(body) -> Map.get(body, "error")
    end
  end

  defp extract_error_from_xml(xml) when is_binary(xml) do
    r = ~r/<error>(.*)<\/error>/

    case Regex.run(r, xml) do
      [_match, content] -> content
      _ -> nil
    end
  end

  @doc """
  Given a map, a list of maps, or a struct, convert all keys from binaries to atoms. binary keys including dashes will have all their dashes replaced with underscores.
  """
  def atomize(nil), do: nil

  def atomize(s) when is_struct(s) do
    s
    |> Map.from_struct()
    |> atomize()
    |> then(&struct(s.__struct__, &1))
  end

  def atomize(m) when is_map(m) do
    m
    |> Enum.map(fn {k, v} ->
      {to_atom(k), atomize(v)}
    end)
    |> Map.new()
  end

  def atomize([h | t]), do: [atomize(h) | atomize(t)]

  def atomize(x) when not is_struct(x) and not is_map(x), do: x

  @doc """
  Safely convert a binary string to an atom, replacing dashes with underscores. Passes through existing atoms unchanged.
  """
  def to_atom(s) when is_binary(s) do
    s
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  def to_atom(s) when is_atom(s), do: s
end
