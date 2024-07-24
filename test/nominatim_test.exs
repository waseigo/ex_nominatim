defmodule ExNominatimTest do
  use ExUnit.Case, async: true
  alias ExNominatim.Validations

  doctest ExNominatim

  test "to_guard" do
    assert Validations.to_guard(:integer) == :is_integer
    assert Validations.to_guard(:float) == :is_float
  end

  test "to_module" do
    assert Validations.to_module(:integer) == Integer
    assert Validations.to_module(:float) == Float
  end

  test "validate_osm_id_single" do
    assert Validations.validate_osm_id_single("N87143") == true
    assert Validations.validate_osm_id_single("W34329") == true
    assert Validations.validate_osm_id_single("R90452") == true
    assert Validations.validate_osm_id_single("W 34329") == false
    assert Validations.validate_osm_id_single("W 34329R") == false
  end

  test "number_or_its_string" do
    # integer
    t = :rand.uniform(10)
    assert Validations.number_or_its_string(t, :integer) == true
    assert Validations.number_or_its_string(t, :float) == false

    # integer as string
    ts = to_string(t)
    assert Validations.number_or_its_string(ts, :integer) == true
    assert Validations.number_or_its_string(ts, :float) == false

    # float
    t = :rand.uniform()
    assert Validations.number_or_its_string(t, :float) == true
    assert Validations.number_or_its_string(t, :integer) == false

    # float as string
    ts = to_string(t)
    assert Validations.number_or_its_string(ts, :float) == true
    assert Validations.number_or_its_string(ts, :integer) == false
  end
end
