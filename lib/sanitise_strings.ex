defmodule EctoSparkles.SanitiseStrings do
  @moduledoc """
  Provides functions for sanitising input on `Ecto.Changeset` string fields.
  """

  @doc """
  Sanitises all changes in the given changeset that apply to field which are of the `:string` `Ecto` type.

  By default it uses the `HtmlSanitizeEx.strip_tags/1` function on any change that satisfies all of the following conditions:
  1. The field associated with the change is of the type `:string`.
  2. The field associated with the change is not in the blacklisted_fields list of `opts` as defined using the `:except` key in `opts`.
  Note that this function will change the value in the `:changes` map of an
  `%Ecto.Changeset{}` struct if the given changes are sanitized.

  ## Examples
      iex> attrs = %{string_field: "<script>Bad</script>"}
      iex> result_changeset =
      ...>   attrs
      ...>   |> FakeEctoSchema.changeset()
      ...>   |> EctoSparkles.SanitiseStrings.strip_all_tags()
      iex> result_changeset.changes
      %{string_field: "Bad"}
  Fields can be exempted from sanitization via the `:except` option.
      iex> attrs = %{string_field: "<script>Bad</script>"}
      iex> result_changeset =
      ...>   attrs
      ...>   |> FakeEctoSchema.changeset()
      ...>   |> EctoSparkles.SanitiseStrings.strip_all_tags(except: [:string_field])
      iex> result_changeset.changes
      %{string_field: "<script>Bad</script>"}

  ### You can also specify a specific scrubber (by passing a function as reference):
  ies> attrs
      ...>   |> FakeEctoSchema.changeset()
      ...>   |> EctoSparkles.SanitiseStrings.sanitise_strings(scrubber: HtmlSanitizeEx.Scrubber.html5/1)
  """

  def strip_all_tags(%Ecto.Changeset{} = changeset, opts \\ []) do
    sanitise_strings(
      changeset,
      opts ++ [scrubber: &HtmlSanitizeEx.strip_tags/1]
    )
  end

  def clean_html(%Ecto.Changeset{} = changeset, opts \\ []) do
    sanitise_strings(
      changeset,
      opts ++ [scrubber: &HtmlSanitizeEx.markdown_html/1]
    )
  end

  def sanitise_strings(%Ecto.Changeset{} = changeset, opts \\ []) do
    blacklisted_fields = Keyword.get(opts, :except, [])
    scrubber = Keyword.get(opts, :scrubber, &HtmlSanitizeEx.strip_tags/1)
    decode_entities = Keyword.get(opts, :decode_entities, false)

    sanitized_changes =
      Enum.into(changeset.changes, %{}, fn change ->
        scrub_change(change, blacklisted_fields, changeset.types, scrubber, decode_entities)
      end)

    %{changeset | changes: sanitized_changes}
  end

  defp scrub_change({field, value}, blacklisted_fields, types, scrubber, decode_entities)
       when is_binary(value) do
    if field in blacklisted_fields do
      {field, value}
    else
      if Map.get(types, field) == :string do
        scrubbed = scrubber.(value)

        final_value =
          if decode_entities do
            HtmlEntities.decode(scrubbed)
          else
            scrubbed
          end

        {field, final_value}
      else
        {field, value}
      end
    end
  end

  defp scrub_change(change, _, _, _, _), do: change
end
