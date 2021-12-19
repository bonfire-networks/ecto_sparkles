# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.Changesets.Errors do

  def error(changeset, []), do: changeset
  def error(changeset, [{k, v} | errors]),
    do: error(Changeset.add_error(changeset, k, v), errors)

  def cs_to_string(%Ecto.Changeset{} = changeset) do
    IO.inspect(changeset)
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", do_to_string(value))
      end)
    end)
    |> many()
  end
  def cs_to_string(changeset), do: changeset

  defp many(changeset) do
    changeset
    |> Enum.reduce("", fn {k, v}, acc ->
      IO.inspect(v: v)
      joined_errors = do_to_string(v, "; ")

      "#{acc} \n#{k}: #{joined_errors}"
    end)
  end

  defp do_to_string(val, sep \\ ", ")
  defp do_to_string(val, sep) when is_list(val) do
    Enum.map(val, &do_to_string/1)
    |> Enum.filter(& &1)
    |> Enum.join(sep)
  end
  defp do_to_string(empty, _) when empty == %{} or empty == "", do: nil
  defp do_to_string(%{} = many, _), do: many(many)
  defp do_to_string(val, _), do: to_string(val)


  # TODO: consolidate the duplicated functionality in above and below functions?

  def changeset_errors_string(changeset, include_first_level_of_keys \\ true)
  def changeset_errors_string(%Ecto.Changeset{} = changeset, include_first_level_of_keys) do
    errors = Ecto.Changeset.traverse_errors(changeset, fn
        {msg, opts} -> String.replace(msg, "%{count}", to_string(opts[:count]))
        msg -> msg
      end)
    errors_map_string(errors, include_first_level_of_keys)
  end
  def changeset_errors_string(error, _), do: error

  def errors_map_string(errors, include_keys \\ true)

  def errors_map_string(%{} = errors, true) do
    Enum.map_join(errors, ", ", fn {key, val} -> "#{key} #{errors_map_string(val)}" end)
  end

  def errors_map_string(%{} = errors, false) do
    Enum.map_join(errors, ", ", fn {_key, val} -> "#{errors_map_string(val)}" end)
  end

  def errors_map_string(e, _) do
    e
  end
end
