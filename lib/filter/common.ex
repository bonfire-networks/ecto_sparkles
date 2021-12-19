# SPDX-License-Identifier: MIT
defmodule EctoSparkles.Filter.Common do
  @moduledoc """
  This module contains query building parts for common things such
  as preload, start/end date and others
  """

  import Logger, only: [debug: 1]
  import Ecto.Query, only: [
    offset: 2, preload: 2, where: 3, limit: 2,
    exclude: 2, from: 2, subquery: 1, order_by: 2
  ]

  alias EctoSparkles.Filter.Build

  @behaviour Build

  @filters [
    :preload,
    :start_date,
    :end_date,
    :before,
    :after,
    :id,
    :ids,
    :first,
    :last,
    :limit,
    :offset,
    :search
  ]

  @spec filters :: list(atom)
  def filters, do: @filters

  def filter({:preload, val}, query), do: preload(query, ^val)

  def filter({:start_date, val}, query), do: where(query, [m], m.inserted_at >= ^(val))

  def filter({:end_date, val}, query), do: where(query, [m], m.inserted_at <= ^val)

  def filter({:before, id}, query), do: where(query, [m], m.id < ^id)

  def filter({:after, id}, query), do: where(query, [m], m.id > ^id)

  def filter({:ids, ids}, query) when is_list(ids), do: where(query, [m], m.id in ^ids)

  def filter({:ids, id}, query), do: where(query, [m], m.id == ^id)

  def filter({:id, id}, query), do: where(query, [m], m.id == ^id)

  def filter({:offset, val}, query), do: offset(query, ^val)

  def filter({:limit, val}, query), do: limit(query, ^val)

  def filter({:first, val}, query), do: limit(query, ^val)

  def filter({:last, val}, query) do
    query
      |> exclude(:order_by)
      |> from(order_by: [desc: :inserted_at], limit: ^val)
      |> subquery
      |> order_by(:id)
  end

  def filter({:search, val}, query) do
    schema = Build.query_schema(query)

    if Kernel.function_exported?(schema, :by_search, 2) do
      schema.by_search(query, val)
    else
      debug "filter: #{inspect schema} doesn't define &search_by/2 (query, params)"

      query
    end
  end

end
