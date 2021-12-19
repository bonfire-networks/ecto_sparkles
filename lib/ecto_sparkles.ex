# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles do
  import Ecto, only: [assoc: 2]

  @moduledoc """
  `query_filter` brings convenience and shortens the boilterplate of ecto queries

  Common filters available include:

  - `preload` - Preloads fields onto the query results
  - `start_date` - Query for items inserted after this date
  - `end_date` - Query for items inserted before this date
  - `before` - Get items with IDs before this value
  - `after` - Get items with IDs after this value
  - `ids` - Get items with a list of ids
  - `first` - Gets the first n items
  - `last` - Gets the last n items
  - `limit` - Gets the first n items
  - `offset` - Offsets limit by n items
  - `search` - ***Warning:*** This requires schemas using this to have a `&by_search(query, val)` function

  You are also able to filter on any natural field of a model, as well as use

  - gte/gt
  - lte/lt
  - like/ilike
  - is_nil/not(is_nil)

  ```elixir
  query_filter(User, %{name: %{ilike: "steve"}})
  query_filter(User, %{name: %{ilike: "steve"}}, :last_name, :asc)
  query_filter(User, %{name: %{age: %{gte: 18, lte: 30}}})
  query_filter(User, %{name: %{is_banned: %{!=: nil}}})
  query_filter(User, %{name: %{is_banned: %{==: nil}}})

  my_query = query_filter(User, %{name: "Billy"})
  query_filter(my_query, %{last_name: "Joe"})
  ```
  """

  def query_filter(module_or_query, filters, order_by_prop \\ :id, order_direction \\ :desc) do
    EctoSparkles.Filter.query_params(module_or_query, filters, order_by_prop, order_direction)
  end


  @doc """
  `join_preload` is a helper for preloading associations using joins.

  By default, Ecto preloads associations using a separate query for each association, which can degrade performance.
  You could make it run faster by using a combination of join/preload, but that requires a bit of boilerplate (see example below).

  With `EctoSparkles`, you can accomplish this with just one line of code.

  ## Example using just Ecto

  ```
  import Ecto.Query
  Invoice
  |> join(:left, [i], assoc(i, :customer), as: :customer)
  |> join(:left, [i, c], assoc(c, :account), as: :account)
  |> join(:left, [i], assoc(i, :lines), as: :lines)
  |> preload([lines: v, customers: c, account: a], lines: v, customer: {c, [a: account]})
  |> Repo.all()
  ```

  ## Example using `join_preload`

  ```
  import EctoSparkles
  Invoice
  |> join_preload([:customer, :account])
  |> join_preload([:lines])
  |> Repo.all()
  ```
  """
  defmacro join_preload(query, associations), do: do_join_preload(query, associations)

  defp do_join_preload(query, []), do: query
  defp do_join_preload(query, associations) do
    root = Macro.var(:root, __MODULE__)
    cond do
      is_list(associations) ->
        bindings = preload_bindings(associations)
        expr = preload_expr(associations)
        joins(query, associations, [root], :root)
        |> preload_clause(bindings, expr)
      is_atom(associations) ->
        expr = quote do: sparkly in assoc(root, unquote(associations))
        preload = [{associations, associations}]
        opts = quote do: [as: unquote(associations)]
        join_clause(query, [root], expr, opts, root)
        |> preload_clause(preload, preload)
      true ->
        raise RuntimeError,
          "join_preload expected an atom or list of atoms, got: #{inspect(associations)}"
    end
  end

  defp joins(query, [], _bindings, _assoc), do: query
  defp joins(query, [j | js], bindings, assoc) do
    bs = bindings ++ [{j, Macro.var(j, __MODULE__)}]
    var = Macro.var(assoc, __MODULE__)
    condition = quote do: sparkly in assoc(unquote(var), unquote(j))
    join_clause(query, bindings, condition, [as: j], j)
    |> joins(js, bs, j)
  end

  # [a: a], [a: a, b: b], [a: a, b: b, c: c] etc.
  defp preload_bindings(names), do: Enum.map(names, &{&1, Macro.var(&1, __MODULE__)})

  # [a: {a, [b: b]}], [a: {a, [b: {b, [c: c]}]}] etc.
  defp preload_expr([last]) when is_atom(last), do: [{last, Macro.var(last, __MODULE__)}]
  defp preload_expr([next | rest]) when is_atom(next),
    do: [{next, {Macro.var(next, __MODULE__), preload_expr(rest)}}]

  defp join_clause(query, bindings, expr, opts, association),
    do: EctoSparkles.reusable_join_impl(query, :left, bindings, expr, opts, association)

  defp preload_clause(query, bindings, expr),
    do: quote(do: Ecto.Query.preload(unquote(query), unquote(bindings), unquote(expr)))


  @doc """
  `reusable_join` is similar to `Ecto.Query.join/{4,5}`, but can be called multiple times with the same alias.

  Note that only the first join operation is performed, the subsequent ones that use the same alias
  are just ignored. Also note that because of this behaviour, it is mandatory to specify an alias when
  using this function.

  This is helpful when you need to perform a join while building queries one filter at a time,
  because the same filter could be used multiple times or you could have multiple filters that
  require the same join, which poses a problem with how the `filter/3` callback work, as you
  need to return a dynamic with the filtering, which means that the join must have an alias,
  and by default Ecto raises an error when you add multiple joins with the same alias.

  To solve this, it is recommended to use this macro instead of the default `Ecto.Query.join/{4,5}`,
  in which case there will be only one join in the query that can be reused by multiple filters.
  """
  defmacro reusable_join(query, qual \\ :left, bindings, expr, opts) do
    as = Keyword.fetch!(opts, :as)
    reusable_join_impl(query, qual, bindings, expr, opts, as)
  end

  @doc false
  def reusable_join_impl(query, qual, bindings, expr, opts, as) do
    args = [qual, bindings, expr, opts]
    quote do
      query = Ecto.Queryable.to_query(unquote(query))
      if Enum.any?(query.joins, &(&1.as == unquote(as))),
        do: query,
        else: join(query, unquote_splicing(args))
    end
  end

end
