defmodule EctoSparkles.JSONSerdeData do
  @moduledoc """
  A custom Ecto type for handling the serialization of arbitrary data types stored as JSON data in the database. Requires the underlying DB field to be a map / JSONB field.

  Loading uses `safe_load/1`, which never creates a new atom, struct or module: names are only resolved to atoms and modules that already exist.
  """
  use Ecto.Type
  import Untangle

  @marker "__data_type__"
  @builtin_aliases ~w(date_time date map_set naive_date_time time)

  def type, do: :map

  @doc """
  Provides custom casting rules for params. Nothing changes here.
  We only need to handle deserialization.
  """
  def cast(:any, term), do: {:ok, term}
  def cast(term), do: {:ok, term}

  @doc """
  Convert the JSON value from the database back to the desired term, see `safe_load/1`.
  """
  def load(json), do: safe_load(json)

  @doc """
  Decodes stored JSON (a binary, or the already decoded JSON) with `JsonSerde`, never creating a new atom, struct or module: names are only resolved to atoms and modules that already exist.

  Before `JsonSerde` sees any stored data, every `"__data_type__"` marker in it is checked, and a marker is refused unless decoding it cannot create an atom, a struct or load a module:

  - `atom`: refused unless the atom already exists.
  - `tuple`, `map_set`: refused unless their values are a list (checked in turn).
  - `date`, `date_time`, `naive_date_time`, `time`: refused unless the value parses.
  - any other marker: refused unless it names an already existing, loaded struct module and every stored field name is already an existing atom (`JsonSerde` would call `String.to_atom/1` on them).

  The markers nested in the values of any of these (tuples, `map_set`, struct fields) are checked too, and a node is refused if anything inside it is.

  When nothing is refused, `JsonSerde` decodes the whole data as usual. Otherwise, the data is walked down through plain maps only, and the smallest node reached that holds a refused part (a marked node or a list, as these cannot be half decoded) is dropped. Each dropped node is logged as a warning with its path, the refused marker and its full raw JSON, so it can be restored by hand. `JsonSerde` then decodes the rest in one go, so every other stored key loads normally.

  Guarantee: `JsonSerde` only ever sees nodes that passed the check, so loading stored data never creates a new atom, struct or module: names are only resolved to atoms and modules that already exist. What an existing struct module's `new/1` does with the stored fields is up to that module.

  Options:

  - `keys: :existing_atoms`: after decoding, the keys of every map (at all levels, not the ones in structs) that name an already existing atom are converted to that atom (a name that is, or is without its `Elixir.` prefix, an existing module becomes that module), and all other keys stay strings. Atoms are never created, values are left alone, and only `"__struct__"` keys are dropped (a struct must only come from a marker that passed the check). Lists of `{atom, value}` pairs become maps.

  Returns `{:ok, data}`, or `{:error, reason}` if the JSON is invalid, the data is not a plain map holding the refused part, or decoding fails.
  """
  def safe_load(raw_json, opts \\ [])

  def safe_load(raw_json, opts) when is_binary(raw_json) do
    case Jason.decode(raw_json) do
      {:ok, decoded} -> safe_load(decoded, opts)
      error -> error
    end
  end

  def safe_load(json_data, opts) do
    case refusal(json_data) do
      :ok -> deserialize(json_data)
      {:refused, _} = refused -> load_cut(json_data, refused)
    end
    |> case do
      {:ok, data} -> {:ok, convert_keys(data, opts[:keys])}
      other -> other
    end
  rescue
    e -> {:error, e}
  end

  defp load_cut(%{} = json_data, _refused) when not is_map_key(json_data, @marker) do
    json_data |> cut([]) |> deserialize()
  end

  # there is no path of plain maps to the refused part
  defp load_cut(_json_data, refused), do: {:error, refused}

  defp convert_keys(data, :existing_atoms), do: atomize_keys(data)
  defp convert_keys(data, _), do: data

  defp atomize_keys(%{__struct__: _} = struct), do: struct

  # a `"__struct__"` key is dropped: a struct must only ever come from a marker that passed the check
  defp atomize_keys(%{} = map) do
    map
    |> Map.delete("__struct__")
    |> Map.new(fn {key, value} -> {key_to_atom(key) || key, atomize_keys(value)} end)
  end

  defp atomize_keys([_ | _] = list) do
    if Keyword.keyword?(list),
      do: list |> Map.new() |> atomize_keys(),
      else: Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(other), do: other

  # the same as `Bonfire.Common.Types.maybe_to_atom_or_module/1` with no atom creation: a module with that name comes first, then an atom
  defp key_to_atom(key) when is_atom(key), do: key

  defp key_to_atom(key) when is_binary(key) do
    module_name = if String.starts_with?(key, "Elixir."), do: key, else: "Elixir." <> key
    existing_atom_or_nil(module_name) || existing_key_atom(key)
  end

  defp key_to_atom(_), do: nil

  defp existing_key_atom("false"), do: false
  defp existing_key_atom("nil"), do: nil
  defp existing_key_atom(""), do: nil
  defp existing_key_atom(key), do: existing_atom_or_nil(key)

  defp existing_atom_or_nil(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> nil
  end

  defp deserialize(json_data), do: JsonSerde.Deserializer.deserialize(json_data, json_data)

  # Checks a stored node and everything in it. Returns `:ok` or `{:refused, marker}` for the first marker found that `JsonSerde` should not decode.
  defp refusal(%{@marker => type} = node) do
    case marker_values(type, node) do
      {:ok, values} -> first_refusal(values)
      :refused -> {:refused, type}
    end
  end

  defp refusal(%{} = map), do: map |> Map.values() |> first_refusal()
  defp refusal(list) when is_list(list), do: first_refusal(list)
  defp refusal(_other), do: :ok

  defp first_refusal(nodes) do
    Enum.find_value(nodes, :ok, fn node ->
      case refusal(node) do
        :ok -> nil
        refused -> refused
      end
    end)
  end

  # `{:ok, nested nodes to check}` when `JsonSerde` can decode the marked node without creating atoms
  defp marker_values("tuple", %{"values" => values}) when is_list(values), do: {:ok, values}
  defp marker_values("map_set", %{"values" => values}) when is_list(values), do: {:ok, values}

  defp marker_values("atom", %{"value" => name}),
    do: if(existing_atom?(name), do: {:ok, []}, else: :refused)

  defp marker_values(type, node) when type in @builtin_aliases and type != "map_set",
    do: if(valid_builtin?(node), do: {:ok, []}, else: :refused)

  defp marker_values(type, node)
       when is_binary(type) and type not in ["tuple", "atom", "map_set"] do
    fields = Map.delete(node, @marker)

    if existing_struct_module?(type) and Enum.all?(Map.keys(fields), &existing_atom?/1),
      do: {:ok, Map.values(fields)},
      else: :refused
  end

  defp marker_values(_type, _node), do: :refused

  defp valid_builtin?(node) do
    match?({:ok, _}, deserialize(node))
  rescue
    _ -> false
  end

  # Drops the smallest node holding a refused part, going down through plain maps only, and logs it in full so it can be restored by hand.
  defp cut(%{} = map, path) do
    Enum.reduce(map, %{}, fn {key, value}, cleaned ->
      case refusal(value) do
        :ok ->
          Map.put(cleaned, key, value)

        {:refused, marker} ->
          if is_map(value) and not is_map_key(value, @marker) do
            Map.put(cleaned, key, cut(value, [key | path]))
          else
            warn(
              "Dropped stored JSON that cannot be decoded safely: path #{inspect(Enum.reverse([key | path]), limit: :infinity)}, refused marker #{inspect(marker, limit: :infinity, printable_limit: :infinity)}, raw JSON #{Jason.encode!(value)}"
            )

            cleaned
          end
      end
    end)
  end

  defp existing_atom?(name) when is_binary(name) do
    String.to_existing_atom(name)
    true
  rescue
    ArgumentError -> false
  end

  defp existing_atom?(_), do: false

  defp existing_struct_module?(name) when is_binary(name) do
    module = String.to_existing_atom(name)
    Code.ensure_loaded?(module) and function_exported?(module, :__struct__, 0)
  rescue
    ArgumentError -> false
  end

  @doc """
  Converting the data structure to a JSON binary for storage.
  """
  def dump(term), do: JsonSerde.serialize(term)
end
