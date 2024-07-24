defmodule ExNominatim do
  defdelegate search(params), to: ExNominatim.Client
  defdelegate reverse(params), to: ExNominatim.Client
  defdelegate lookup(params), to: ExNominatim.Client
  defdelegate details(params), to: ExNominatim.Client
  defdelegate status(params \\ [format: "text"]), to: ExNominatim.Client
end
