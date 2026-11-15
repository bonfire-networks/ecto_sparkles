defmodule EctoSparkles.JSONSerdeDataTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias EctoSparkles.JSONSerdeData

  # an existing struct module, so only the (unseen) field names can tell if a refused marker created an atom
  @existing_module Atom.to_string(URI)

  defp unseen_name(prefix), do: "#{prefix}#{System.unique_integer([:positive])}_never_seen"

  defp atom_exists?(name) do
    String.to_existing_atom(name)
    true
  rescue
    ArgumentError -> false
  end

  defp dumped(data) do
    {:ok, json} = JSONSerdeData.dump(data)
    Jason.decode!(json)
  end

  test "a part that cannot be decoded safely is dropped and logged in full, the rest loads" do
    key = unseen_name("bad_key_")
    bad = %{"__data_type__" => "tuple", "values" => "not a list"}
    row = %{"a" => %{"b" => 1}, key => bad}

    {{:ok, loaded}, log} = with_log(fn -> JSONSerdeData.safe_load(row) end)

    assert loaded == %{"a" => %{"b" => 1}}
    assert log =~ "Dropped"
    assert log =~ key
    assert log =~ ~s("values":"not a list")
  end

  test "an unknown atom, module and field name are not created by a refused marker" do
    atom_name = unseen_name("never_seen_atom_")
    module_name = unseen_name("Elixir.NeverSeenModule")
    field_name = unseen_name("never_seen_field_")

    row = %{
      "keep" => 1,
      "atom" => %{"__data_type__" => "atom", "value" => atom_name},
      "module" => %{"__data_type__" => module_name, "a" => 1},
      "fields" => %{"__data_type__" => @existing_module, field_name => 1}
    }

    {{:ok, loaded}, _log} = with_log(fn -> JSONSerdeData.safe_load(row) end)

    assert loaded == %{"keep" => 1}

    for name <- [atom_name, module_name, field_name] do
      refute atom_exists?(name), "#{name} was created as an atom"
    end
  end

  test "a marker nested in a map_set, a tuple or a list drops the whole node" do
    module_name = unseen_name("Elixir.NeverSeenNested")
    inner = %{"__data_type__" => module_name}

    row = %{
      "keep" => 1,
      "set" => %{"__data_type__" => "map_set", "values" => [inner]},
      "tuple" => %{"__data_type__" => "tuple", "values" => [1, inner]},
      "list" => [1, inner]
    }

    {{:ok, loaded}, _log} = with_log(fn -> JSONSerdeData.safe_load(row) end)

    assert loaded == %{"keep" => 1}
    refute atom_exists?(module_name)
  end

  test "an invalid built-in value is dropped" do
    row = %{"keep" => 1, "day" => %{"__data_type__" => "date", "value" => "not a date"}}

    {{:ok, loaded}, _log} = with_log(fn -> JSONSerdeData.safe_load(row) end)

    assert loaded == %{"keep" => 1}
  end

  test "a refused part in a row that is not a plain map is an error" do
    bad = [%{"__data_type__" => unseen_name("Elixir.NeverSeenTop")}]

    assert {:error, {:refused, _}} = JSONSerdeData.safe_load(bad)
  end

  test "keys: :existing_atoms never turns stored data into a struct" do
    row = %{
      "some_key" => %{"__struct__" => @existing_module, "host" => "x"},
      "list" => [%{"__struct__" => @existing_module}]
    }

    assert {:ok, loaded} = JSONSerdeData.safe_load(row, keys: :existing_atoms)

    # the keys may or may not be existing atoms, so look at the values
    [one, [two]] = Enum.sort_by(Map.values(loaded), &is_list/1)

    for value <- [one, two] do
      refute is_struct(value)
      refute Map.has_key?(value, :__struct__)
      refute Map.has_key?(value, "__struct__")
    end

    assert one[:host] == "x"
  end

  test "control: valid markers decode and round trip" do
    data = %{
      "date" => ~D[2020-01-02],
      "set" => MapSet.new(["a", "b"]),
      "pair" => {:ok, 1}
    }

    assert {:ok, ^data} = data |> dumped() |> JSONSerdeData.safe_load()
    assert {:error, _} = JSONSerdeData.safe_load("{not json")
  end
end
