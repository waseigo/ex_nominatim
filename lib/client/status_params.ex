# SPDX-FileCopyrightText: 2024 Isaak Tsalicoglou <isaak@overbring.com>
# SPDX-License-Identifier: Apache-2.0

defmodule ExNominatim.Client.StatusParams do
  @moduledoc """
  The struct for a request to the `/status` API endpoint.
  """
  @moduledoc since: "1.0.0"

  defstruct format: "text",
            valid?: nil,
            errors: []

  @required []

  @doc """
  Construct a new `%StatusParams{}` struct from the content of the keyword list `opts`.
  """
  def new(opts), do: ExNominatim.Client.new(opts, @required, __MODULE__)
end
