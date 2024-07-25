# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Client do
  alias ExNominatim.{Validations, Report}

  @config ExNominatim.get_config()
  @config_specific_keys [:base_url, :force, :process, :atomize]
  @endpoints [:search, :reverse, :status, :lookup, :details]

  @moduledoc """
  Functions for preparing an HTTP request, including validating the base URL of the target Nominatim API server setting the User-Agent header automatically, selecting all the non-nil request parameters, creating a validated request, and dispatching it to the requested endpoint.

  The `opts` keyword list of the endpoint request functions can optionally include the following:
  * `:base_url` with a string value setting the base URL of the target Nominatim API server (it defaults to the public server).
  * `:force` with a boolean value, where `true` means that validation errors will be ignored and the HTTP GET request to the API will run regardless.

  """
  @moduledoc since: "1.0.0"

  @doc """
  Use the `/search` API endpoint. Delegated to from `ExNominatim.search/1`, which is documented.
  """
  def search(opts), do: generic(:search, opts)

  @doc """
  Use the `/reverse` API endpoint. Delegated to from `ExNominatim.reverse/1`, which is documented.
  """
  def reverse(opts), do: generic(:reverse, opts)

  @doc """
  Use the `/lookup` API endpoint. Delegated to from `ExNominatim.lookup/1`, which is documented.
  """
  def lookup(opts), do: generic(:lookup, opts)

  @doc """
  Use the `/details` API endpoint. Delegated to from `ExNominatim.details/1`, which is documented.
  """
  def details(opts), do: generic(:details, opts)

  @doc """
  Use the `/status` API endpoint. Delegated to from `ExNominatim.status/1`, which is documented.
  """
  def status(opts), do: generic(:status, opts)

  @doc """
  Use the `/status` API endpoint without setting any request parameters. Delegated to from `ExNominatim.status/0`, which is documented.
  """
  def status(), do: generic(:status, [])

  defp generic(action, opts) when is_list(opts) and action in @endpoints do
    with {:keyword?, true} <- {:keyword?, Keyword.keyword?(opts)},
         {:new, {:ok, {m, config_opts}}} when is_struct(m) <-
           {:new, make_new_struct(opts, action)} do
      generic_request(action, m, config_opts)
    else
      {:keyword?, false} -> {:error, :improper_list}
      {:new, {:error, reason}} -> {:error, reason}
    end
  end

  defp make_new_struct(opts, action) do
    provided = Keyword.keys(opts) -- @config_specific_keys
    module = get_module(action)

    extraneous = provided -- permitted_keys(struct(module))

    if extraneous != [] do
      {:error, {:extraneous_fields, extraneous}}
    else
      opts_new =
        @config[:all]
        |> Keyword.merge(@config[action])
        |> Keyword.merge(opts)

      config_opts = Keyword.take(opts_new, @config_specific_keys)

      case apply(module, :new, [opts_new]) do
        {:ok, m} when is_struct(m) ->
          {:ok, {m, config_opts}}

        {:error, v} ->
          {:error, v}
          # {:error, {:apply_failed, opts_new}}
      end
    end
  end

  defp permitted_keys(m) when is_struct(m) do
    m |> Map.from_struct() |> Map.keys() |> Kernel.--([:valid?, :errors])
  end

  defp generic_request(action, params_struct, config_opts)
       when action in @endpoints and is_struct(params_struct) and is_list(config_opts) do
    s = get_module(action)

    force? = Keyword.get(config_opts, :force)
    base_url = Keyword.get(config_opts, :base_url)
    process? = Keyword.get(config_opts, :process)
    atomize? = Keyword.get(config_opts, :atomize)

    # skip validation if force: true in config_opts
    maybe_validated =
      if force?, do: {:ok, params_struct}, else: Validations.validate(params_struct)

    with {:ok, %^s{} = maybe_valid_params} <- maybe_validated,
         {:ok, %Req.Request{} = req} <- prepare(action, maybe_valid_params, base_url),
         {:ok, %Req.Response{} = resp} <- Req.request(req) do
      output = {:ok, resp}

      case {process?, atomize?} do
        {true, true} ->
          {status, processed} = Report.process(output)
          {status, Report.atomize(processed)}

        {true, false} ->
          Report.process(output)

        {false, true} ->
          {status, unprocessed} = output
          {status, Report.atomize(unprocessed)}

        {false, false} ->
          output
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_module(action) when action in @endpoints do
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
  Create a new request params struct from the provided keyword list `opts`, taking into account any required fields listed as atoms in the `required` list. Delegated to from the `new/1` function of the modules of `SearchParams`, `ReverseParams`, etc. (the `module`).
  """
  def new(opts, required, module) when is_list(opts) and is_list(required) and is_atom(module) do
    with {:keyword?, true} <- {:keyword?, Keyword.keyword?(opts)},
         {:required, ^required} <-
           {:required, opts |> Keyword.take(required) |> Keyword.keys()} do
      new(Map.new(opts), module)
    else
      {:keyword?, false} -> {:error, {:improper_list, opts}}
      {:required, _} -> {:error, {:missing_query_params, required}}
    end
  end

  defp new(params, module) when is_map(params) and is_atom(module) do
    {:ok, module |> struct() |> Map.merge(params)}
  end

  # HTTP request preparation

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

    List.to_string([client, "/", version])
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
