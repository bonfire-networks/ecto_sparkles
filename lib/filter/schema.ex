# SPDX-License-Identifier: MIT
defmodule EctoSparkles.Filter.Schema do
  @moduledoc """
  This module contains query building parts for schemas themselves,
  when passed a query it can pull the schema from it and attempt
  to filter on any natural field
  """

  import Logger, only: [debug: 1, error: 1]

  import Ecto.Query

  alias EctoSparkles.Filter.Build

  @behaviour Build

  @impl Build
  def filter({filter_field, val}, query) do
    filter(
      {filter_field, val},
      Build.query_schema(query),
      query
    )
  end

  def filter({filter_field, val}, schema, query) do
    if filter_field in schema.__schema__(:fields) do
      create_schema_field_filter(query, filter_field, val)
    else
      error "query_filter: `#{Atom.to_string(filter_field)}` is not a recognised filter or field for `#{schema.__schema__(:source)}` where you attempted to filter by: #{inspect val}"

      query
    end
  end

  defp create_schema_field_filter(query, filter_field, val) when is_list(val) do
    query |> where([r], field(r, ^filter_field) in ^val)
  end

  defp create_schema_field_filter(query, filter_field, %NaiveDateTime{} = val) do
    query |> where([r], field(r, ^filter_field) == ^val)
  end

  defp create_schema_field_filter(query, filter_field, %DateTime{} = val) do
    query |> where([r], field(r, ^filter_field) == ^val)
  end

  defp create_schema_field_filter(query, filter_field, filters) when is_map(filters) do
    Enum.reduce(filters, query, fn ({filter_type, value}, query_acc) ->
      create_schema_field_comparison_filter(query_acc, filter_field, filter_type, value)
    end)
  end

  defp create_schema_field_filter(query, filter_field, val) do
    query |> where([r], field(r, ^filter_field) == ^val)
  end

  defp create_schema_field_comparison_filter(query, filter_field, :==, nil) do
    query |> where([r], is_nil(field(r, ^filter_field)))
  end

  defp create_schema_field_comparison_filter(query, filter_field, :!=, nil) do
    query |> where([r], not is_nil(field(r, ^filter_field)))
  end

  defp create_schema_field_comparison_filter(query, filter_field, :gt, val) do
    query |> where([r], field(r, ^filter_field) > ^val)
  end

  defp create_schema_field_comparison_filter(query, filter_field, :lt, val) do
    query |> where([r], field(r, ^filter_field) < ^val)
  end

  defp create_schema_field_comparison_filter(query, filter_field, :gte, val) do
    query |> where([r], field(r, ^filter_field) >= ^val)
  end

  defp create_schema_field_comparison_filter(query, filter_field, :lte, val) do
    query |> where([r], field(r, ^filter_field) <= ^val)
  end

  defp create_schema_field_comparison_filter(query, filter_field, :like, val) do
    search_query = "%#{val}%"

    query |> where([r], like(field(r, ^filter_field), ^search_query))
  end

  defp create_schema_field_comparison_filter(query, filter_field, :ilike, val) do
    search_query = "%#{val}%"

    query |> where([r], ilike(field(r, ^filter_field), ^search_query))
  end
end
