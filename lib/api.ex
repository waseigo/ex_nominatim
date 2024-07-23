defmodule ExNominatim.API do
  alias ExNominatim.{HTTP, SearchParams, ReverseParams, Validations}
  @default_base_url "http://localhost:8080"

  def generic(params) when is_list(params) do
    with {:keyword?, true} <- {:keyword?, Keyword.keyword?(params)},
         {:new, {:ok, m}} when is_struct(m) <- {:new, SearchParams.new(params)} do
      base_url = Keyword.get(params, :base_url) || @default_base_url
      search(m, base_url)
    else
      {:keyword?, false} -> {:error, :improper_list}
      {:new, {:error, reason}} -> {:error, reason}
    end
  end

  def search(%SearchParams{} = params, base_url \\ @default_base_url) do
    with {:ok, %SearchParams{} = valid_params} <- Validations.validate(params),
         {:ok, %Req.Request{} = req} <- HTTP.prepare(:search, valid_params, base_url),
         {:ok, %Req.Response{} = resp} <- Req.request(req) do
      {:ok, resp}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def reverse(%ReverseParams{} = params, base_url \\ @default_base_url) do
    with {:ok, %ReverseParams{} = valid_params} <- Validations.validate(params),
         {:ok, %Req.Request{} = req} <- HTTP.prepare(:reverse, valid_params, base_url),
         {:ok, %Req.Response{} = resp} <- Req.request(req) do
      {:ok, resp}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
