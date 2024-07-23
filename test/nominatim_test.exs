defmodule NominatimTest do
  use ExUnit.Case
  doctest Nominatim

  test "greets the world" do
    assert Nominatim.hello() == :world
  end
end
