defmodule ExNominatim do
  @moduledoc """
  Documentation for `ExNominatim`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> ExNominatim.hello()
      :world

  """
  defdelegate search(params), to: ExNominatim.Client

  defdelegate reverse(params), to: ExNominatim.Client

  defdelegate lookup(params), to: ExNominatim.Client

  defdelegate status(params \\ [format: "text"]), to: ExNominatim.Client
end
