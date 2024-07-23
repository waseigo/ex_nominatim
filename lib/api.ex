defmodule ExNominatim.API do
  alias ExNominatim.{HTTP, SearchParams, Validations}
  @default_base_url "http://localhost:8080"

  def search(params) when is_list(params) do
    base_url = Keyword.get(params, :base_url) || @default_base_url
  end

  def search(%SearchParams{} = params, base_url \\ @default_base_url) do
    with {:ok, %SearchParams{} = valid_params} <- Validations.validate(params),
         {:ok, %Req.Request{} = req} <- HTTP.prepare(:search, valid_params, base_url),
         {:ok, %Req.Response{} = resp} <- Req.request(req) do
      resp
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
