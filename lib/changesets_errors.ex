# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.Changesets.Errors do
  alias Ecto.Changeset 
  
  def error(changeset, []), do: changeset

  def error(changeset, [{k, v} | errors]),
    do: error(Changeset.add_error(changeset, k, v), errors)

  def changeset_errors_string(changeset, include_schema_tree \\ true)

  def changeset_errors_string(%Ecto.Changeset{} = changeset, _) do
    changeset
    # |> IO.inspect(label: "changeset_error")
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, 
      acc ->
        do_to_string(acc) 
        |> String.replace("%{#{do_to_string(key)}}", do_to_string(value))
      end)
    end)
    |> enum_errors()
  end

  def changeset_errors_string(changeset, _), do: changeset

  defp enum_errors(changeset) do
    changeset
    |> Enum.reduce("", fn {k, v}, acc ->
      joined_errors = do_to_string(v, "; ")

      "#{acc} \n#{Recase.to_sentence(to_string(k))}: #{joined_errors}"
    end)
  end

  defp do_to_string(val, sep \\ ", ")


  defp do_to_string(val, sep) when is_list(val) do
    Enum.map(val, &do_to_string/1)
    |> Enum.filter(& &1)
    |> Enum.join(sep)
  end

  defp do_to_string(empty, _) when empty == %{} or empty == "", do: nil
  defp do_to_string(val, _sep) when is_binary(val), do: val
  defp do_to_string({a, b}, _sep), do: "{#{do_to_string(a)}, #{do_to_string(b)}}"
  defp do_to_string(%{} = enum_errors, _), do: enum_errors(enum_errors)
  defp do_to_string(val, _), do: to_string(val)
end
