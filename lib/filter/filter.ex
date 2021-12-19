# SPDX-License-Identifier: MIT
defmodule EctoSparkles.Filter do
  @moduledoc """
  Calls a collection of common schema filters, which are found in:
  - EctoSparkles.Filter.Common
  - EctoSparkles.Filter.Schema
  """

  import Ecto.Query, only: [where: 2, order_by: 2]
  require Logger

  alias EctoSparkles.Filter

  @common_filters Filter.Common.filters()

  @doc "Converts filter params into a query"
  @spec query_params(
    queryable :: Ecto.Query.t(),
    params :: Keyword.t | map
  ) :: Ecto.Query.t
  def query_params(query, params, order_by_prop \\ :id, order_direction \\ :desc)

  def query_params(query, params, order_by_prop, order_direction) when is_map(params), do: query_params(query, Map.to_list(params), order_by_prop, order_direction)

  def query_params(query, params, order_by_prop, order_direction) when is_tuple(params), do: query_params(query, [params], order_by_prop, order_direction)

  # def query_params(query, params, order_by_prop, order_direction) when not is_list(params), do: query_params(query, Enum.to_list(params), order_by_prop, order_direction)

  def query_params(query, [], _, _), do: query

  def query_params(query, params, order_by_prop, :desc) when is_atom(order_by_prop) do
    params
      |> ensure_last_is_final_filter
      |> Enum.reduce(order_by(query, desc: ^order_by_prop), &filter/2)
  end

  def query_params(query, params, order_by_prop, :asc) when is_atom(order_by_prop) do
    params
      |> ensure_last_is_final_filter
      |> Enum.reduce(order_by(query, asc: ^order_by_prop), &filter/2)
  end

  def query_params(query, params, _, _) do
    params
      |> ensure_last_is_final_filter
      |> Enum.reduce(query, &filter/2)
  end

  def filter({filter, _} = filter_tuple, query) when filter in @common_filters do
    # IO.inspect(filter_tuple: filter_tuple)
    Filter.Build.filter(Filter.Common, filter_tuple, query)
  end

  def filter({filter, {filter_fn, val}}, query) when is_function(filter_fn) do
    Filter.Build.filter(filter_fn, filter, val, query)
  end

  def filter({filter, {val, filter_fn}}, query) when is_function(filter_fn) do
    Filter.Build.filter(filter_fn, filter, val, query)
  end

  def filter({filter, filter_fn}, query) when is_function(filter_fn) do
    Filter.Build.filter(filter_fn, filter, query)
  end

  def filter({_filter, %Ecto.Query.DynamicExpr{} = dynamic_filter}, query) do
    query |> where(^dynamic_filter)
  end

  def filter(filter_tuple, query) do
    Filter.Build.filter(Filter.Schema, filter_tuple, query)
  end

  defp ensure_last_is_final_filter(params) when is_list(params) do # what's this for?
    # IO.inspect(params)
    if Keyword.has_key?(params, :last) do
      params
        |> Keyword.delete(:last)
        |> Kernel.++([last: params[:last]])
    else
      params
    end
  end

  defp ensure_last_is_final_filter(params), do: params

end
