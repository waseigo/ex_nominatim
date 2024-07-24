# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Client do
  alias ExNominatim.{HTTP, Validations}
  @default_base_url "http://localhost:8080"
  @implemented_endpoints [:search, :reverse, :status, :lookup, :details]

  @moduledoc """
  Functions used for creating a validated request and dispatching it to the requested endpoint.
  """
  @moduledoc since: "1.0.0"

  @doc """
  Use the `/search` API endpoint. Delegated to from `ExNominatim.search/1`, which is documented.
  """
  def search(params), do: generic(:search, params)

  @doc """
  Use the `/reverse` API endpoint. Delegated to from `ExNominatim.reverse/1`, which is documented.
  """
  def reverse(params), do: generic(:reverse, params)

  @doc """
  Use the `/lookup` API endpoint. Delegated to from `ExNominatim.lookup/1`, which is documented.
  """
  def lookup(params), do: generic(:lookup, params)

  @doc """
  Use the `/details` API endpoint. Delegated to from `ExNominatim.details/1`, which is documented.
  """
  def details(params), do: generic(:details, params)

  @doc """
  Use the `/status` API endpoint. Delegated to from `ExNominatim.status/1`, which is documented.
  """
  def status(params \\ [format: "text"]), do: generic(:status, params)

  defp generic(action, params) when is_list(params) and action in @implemented_endpoints do
    with {:keyword?, true} <- {:keyword?, Keyword.keyword?(params)},
         {:new, {:ok, m}} when is_struct(m) <- {:new, make_new_struct(params, action)} do
      generic_request(action, m, Keyword.take(params, [:base_url, :force]))
    else
      {:keyword?, false} -> {:error, :improper_list}
      {:new, {:error, reason}} -> {:error, reason}
    end
  end

  defp make_new_struct(params, action) do
    provided = Keyword.keys(params)
    module = get_module(action)

    {:ok, blank_struct} = apply(module, :new, [[]])

    extraneous = provided -- permitted_keys(blank_struct)

    if extraneous != [] do
      {:error, {:extraneous_fields, extraneous}}
    else
      apply(module, :new, [params])
    end
  end

  defp permitted_keys(m) when is_struct(m) do
    m |> Map.from_struct() |> Map.keys() |> Kernel.--([:valid?, :errors])
  end

  defp generic_request(action, params_struct, opts)
       when action in @implemented_endpoints and is_struct(params_struct) and is_list(opts) do
    s = get_module(action)

    base_url = Keyword.get(opts, :base_url) || @default_base_url
    force? = Keyword.get(opts, :force) || false

    # skip validation if force: true in opts
    maybe_validated =
      if force?, do: {:ok, params_struct}, else: Validations.validate(params_struct)

    with {:ok, %^s{} = maybe_valid_params} <- maybe_validated,
         {:ok, %Req.Request{} = req} <- HTTP.prepare(action, maybe_valid_params, base_url),
         {:ok, %Req.Response{} = resp} <- Req.request(req) do
      {:ok, resp}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_module(action) when action in @implemented_endpoints do
    [
      __MODULE__,
      action |> to_string |> Kernel.<>("_params") |> Macro.camelize() |> String.to_atom()
    ]
    |> Module.safe_concat()
  end

  # unused
  # defp get_action(module) when is_atom(module) do
  #   module
  #   |> Module.split()
  #   |> List.last()
  #   |> Macro.underscore()
  #   |> String.split()
  #   |> hd()
  #   |> String.to_atom()
  # end

  @doc """
  Create a new request params struct from the provided keyword list `p`, taking into account any required fields listed as atoms in the `required` list. Delegated to from the `new/1` function of the modules of `SearchParams`, `ReverseParams`, etc. (the `module`).
  """
  def new(p, required, module) when is_list(p) and is_list(required) and is_atom(module) do
    with {:keyword?, true} <- {:keyword?, Keyword.keyword?(p)},
         {:required, ^required} <-
           {:required, p |> Keyword.take(required) |> Keyword.keys()} do
      new(Map.new(p), module)
    else
      {:keyword?, false} -> {:error, {:improper_list, p}}
      {:required, _} -> {:error, {:missing_query_params, required}}
    end
  end

  defp new(p, module) when is_map(p) and is_atom(module) do
    {:ok, module |> struct() |> Map.merge(p)}
  end
end
