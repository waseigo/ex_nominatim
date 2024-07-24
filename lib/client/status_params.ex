defmodule ExNominatim.Client.StatusParams do
  defstruct format: "text",
            valid?: nil,
            errors: []

  @required []

  def new(p), do: ExNominatim.Client.new(p, @required, __MODULE__)
end
