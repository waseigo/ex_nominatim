defmodule ExNominatim.Client do
  alias ExNominatim.{HTTP, Validations}
  @default_base_url "http://localhost:8080"
  @implemented_endpoints [:search, :reverse, :status, :lookup]

  def search(params), do: generic(:search, params)
  def reverse(params), do: generic(:reverse, params)
  def lookup(params), do: generic(:lookup, params)
  def status(params \\ [format: "text"]), do: generic(:status, params)

  defp generic(action, params) when is_list(params) and action in @implemented_endpoints do
    s = get_module(action)

    with {:keyword?, true} <- {:keyword?, Keyword.keyword?(params)},
         {:new, {:ok, m}} when is_struct(m) <- {:new, apply(s, :new, [params])} do
      generic_request(action, m, Keyword.take(params, [:base_url, :force]))
    else
      {:keyword?, false} -> {:error, :improper_list}
      {:new, {:error, reason}} -> {:error, reason}
    end
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

  def get_action(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.split()
    |> hd()
    |> String.to_atom()
  end

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
