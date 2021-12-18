# SPDX-License-Identifier: MIT
defmodule EctoSparkles.Filter.Build do
  @moduledoc "Behaviour for query building from filter tuples"

  @type filter_tuple :: {filter_type :: atom, value :: any}
  @type accumulator_query :: Ecto.Query.t

  @doc "Adds to accumulator query with filter_type and value"
  @callback filter(filter_tuple, accumulator_query) :: Ecto.Query.t

  @spec filter(module, filter_tuple, accumulator_query) :: Ecto.Query.t

  def filter(builder_module, filter_tuple, query) when is_atom(builder_module) do
    builder_module.filter(filter_tuple, query)
  end

  def filter(filter_fn, filter_tuple, query) when is_function(filter_fn) do
    filter_fn.(filter_tuple, query)
  end
  def filter(filter_fn, filter, val, query) when is_function(filter_fn) do
    filter_fn.(filter, val, query)
  end

  @spec query_schema(Ecto.Query.t) :: Ecto.Schema.t
  @doc "Pulls the schema from a query"
  def query_schema(%{from: %{source: {_, schema}}}), do: query_schema(schema)
  def query_schema(%{from: %{query: %{from: {_, schema}}}}), do: schema
  def query_schema(query), do: query
end
