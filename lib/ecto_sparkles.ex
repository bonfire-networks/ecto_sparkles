# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  import Ecto, only: [assoc: 2]
  # import Untangle

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
  defmacro join_preload(query, associations),
    do: join_preload_impl(query, associations)

  defp join_preload_impl(query, associations) do
    root = var(:root)

    cond do
      is_list(associations) ->
        bindings = preload_bindings(associations)
        expr = preload_expr(associations)

        rejoins(query, associations, [root], :root)
        |> preload_clause(bindings, expr)

      is_atom(associations) ->
        expr = quote do: sparkly in assoc(root, unquote(associations))
        preload = [{associations, associations}]

        rejoin(query, [root], expr, associations)
        |> preload_clause(preload, preload)

      true ->
        raise RuntimeError,
              "join_preload expected an atom or list of atoms, got: #{inspect(associations)}"
    end
  end

  defp rejoins(query, [], _bindings, _assoc), do: query

  defp rejoins(query, [j | js], bindings, assoc) do
    bs = bindings ++ [{j, var(j)}]
    condition = quote do: sparkly in assoc(unquote(var(assoc)), unquote(j))

    rejoin(query, bindings, condition, j)
    |> rejoins(js, bs, j)
  end

  # [a: a], [a: a, b: b], [a: a, b: b, c: c] etc.
  defp preload_bindings(names),
    do: Enum.map(names, &{&1, Macro.var(&1, __MODULE__)})

  # [a: {a, [b: b]}], [a: {a, [b: {b, [c: c]}]}] etc.
  defp preload_expr([last]) when is_atom(last),
    do: [{last, Macro.var(last, __MODULE__)}]

  defp preload_expr([next | rest]) when is_atom(next),
    do: [{next, {Macro.var(next, __MODULE__), preload_expr(rest)}}]

  @doc """
  AKA `join_preload++`. It's more powerful, but it does it with more (and different!) syntax.

  e.g.
  ```
  proload(query, activity: [
    :verb, :boost_count, :like_count, :replied,
    # relations under object will have their aliases prefixed with object_, i.e.
    # :object_message, :object_post, :object_post_content
    # the original names will still be used for the associations.
    object: {"object_", [:message, :post, :post_content]}
  ])
  ```
  """
  defmacro proload(query, qual \\ :left, associations),
    do: proload_impl(query, qual, associations, __CALLER__)

  defp proload_impl(query, qual, associations, caller) do
    # we want to expand metadata references
    associations = List.wrap(expand(associations, caller))
    # iterate over the form, generating nested join clauses
    proload_join(query, qual, associations, [var(:root)], :root, "", caller)
    # pipe that into a preload expression
    |> preload_clause(
      proload_preload_bindings(associations),
      proload_preload_expr(associations)
    )
  end

  # this recurses through the forms generating a join clause at each
  # step, which it pipes the query form through returning a new query form.
  defp proload_join(
         # a quoted form that evaluates to a query
         query,
         # left/inner/etc.
         qual,
         # the current expression we are translating
         form,
         # an improper keyword list of nested bindings for our join expr
         bindings,
         # the alias of the thing we are joining from
         assoc,
         # current string prefix to prepend to generated aliases
         prefix, 
         caller
       ) do
    case form do
      # an atom is a simple join
      _ when is_atom(form) ->
        alia = prefix(form, prefix)

        maybe_rejoin(query, qual, bindings, assoc, form, alia, caller)

      # lists are simply folded over
      _ when is_list(form) ->
        Enum.reduce(
          form,
          query,
          &proload_join(&2, qual, &1, bindings, assoc, prefix, caller)
        )

      # a 2-tuple where the key is a binary extends the prefix
      {pre, form} when is_binary(pre) ->
        proload_join(query, qual, form, bindings, assoc, prefix <> pre, caller)

      # a 2-tuple where the key is an atom names an association
      {rel, form} when is_atom(rel) ->
        alia = prefix(rel, prefix)
        # now generate a join, aliasing it with a prefix
        maybe_rejoin(query, qual, bindings, assoc, rel, alia, caller)
        # and recurse generating the rest of the joins
        |> proload_join(
          qual,
          # the nested bit
          form,
          # add our alias to the bindings
          bindings ++ [{alia, var(alia)}],
          # join from us
          alia,
          # pass the prefix through
          prefix, 
          caller
        )

      {:^, _, _} ->
        query

      _ ->
        raise RuntimeError,
              "proload expected an atom, list or 2-tuple, got: #{inspect(form)}"
    end
  end

  defp maybe_rejoin(query, qual, bindings, assoc, rel, alia, _caller) do
    # debug(query)
    # debug(bindings)
    # debug(assoc)
    # debug(rel)
    # TODO: only join assocs that exist
    # assoc_exists?(query, assoc, rel, caller)
    # |> debug()

    # if schema.__schema__(:association, unquote(rel))
    expr = quote(do: sparkly in assoc(unquote(var(assoc)), unquote(rel)))
    rejoin(query, qual, bindings, expr, alia)
  end

  # figures out the list of bindings to supply to preload. this will
  # include all aliases generated by the specification
  defp proload_preload_bindings(form) do
    # get a list of all relevant aliases
    proload_aliases(form)
    # for all the good that it will do, try and minimise duplication
    |> Enum.dedup()
    # turn the names into bindings
    |> Enum.map(&{&1, var(&1)})
  end

  # recursively get a list of all aliases (with prefixes correctly applied)
  defp proload_aliases(form, prefix \\ "") do
    case form do
      _ when is_atom(form) ->
        [prefix(form, prefix)]

      _ when is_list(form) ->
        Enum.flat_map(form, &proload_aliases(&1, prefix))

      {pre, form} when is_binary(pre) ->
        proload_aliases(form, prefix <> pre)

      {rel, form} when is_atom(rel) ->
        [prefix(rel, prefix) | proload_aliases(form, prefix)]
      
      {:^, _, _} ->
        []
    end
  end

  # generates a preload expression from a specification. the structure is mostly the same,
  # it's really just intercepting prefix tuples and generating aliases.
  defp proload_preload_expr(form, prefix \\ "") do
    case form do
      _ when is_atom(form) ->
        [{form, var(prefix(form, prefix))}]

      _ when is_list(form) ->
        Enum.map(form, &proload_preload_expr(&1, prefix)) 

      {pre, form} when is_binary(pre) ->
        proload_preload_expr(form, prefix <> pre)

      {rel, form} when is_atom(rel) ->
        {rel, {var(prefix(rel, prefix)), proload_preload_expr(form, prefix)}}

      {:^, _, _} ->
        IO.warn("TODO: support preload with pinned function or query: https://hexdocs.pm/ecto/Ecto.Query.html#preload/3-preload-queries, got: #{inspect(form)}")
        form
    end
  end

  @doc """
  `reusable_join` is similar to `Ecto.Query.join/{4,5}`, but can be called multiple times with the same alias.

  Note that only the first join operation is performed, the subsequent ones that use the same alias are just ignored. Also note that because of this behaviour, it is mandatory to specify an alias when using this function.

  This is helpful when you need to perform a join while building queries one filter at a time, because the same filter could be used multiple times or you could have multiple filters that require the same join, which poses a problem with how the `filter/3` callback work, as you
  need to return a dynamic with the filtering, which means that the join must have an alias, and by default Ecto raises an error when you add multiple joins with the same alias.

  To solve this, it is recommended to use this macro instead of the default `Ecto.Query.join/{4,5}`, in which case there will be only one join in the query that can be reused by multiple filters.
  """
  defmacro reusable_join(query, qual \\ :left, bindings, expr, opts) do
    as = Keyword.fetch!(opts, :as)
    reusable_join_impl(query, qual, bindings, expr, opts, as)
  end

  # don't think this needs to be public anymore, but it doesn't hurt
  @doc false
  def reusable_join_impl(query, qual \\ :left, bindings, expr, opts, as) do
    args = [qual, bindings, expr, opts]

    quote do
      query = Ecto.Queryable.to_query(unquote(query))

      if Enum.any?(query.joins, &(&1.as == unquote(as))),
        do: query,
        else: join(query, unquote_splicing(args))
    end
  end

  # slightly more do-what-i-mean interface to reusable_join_impl
  defp rejoin(query, bindings, expr, opts) when is_list(opts),
    do: rejoin(query, :left, bindings, expr, opts, Keyword.fetch!(opts, :as))

  defp rejoin(query, bindings, expr, as) when is_atom(as),
    do: rejoin(query, :left, bindings, expr, [as: as], as)

  # not currently used, but handy
  defp rejoin(query, qual, bindings, expr, opts)
       when is_atom(qual) and is_list(opts),
       do: rejoin(query, qual, bindings, expr, opts, Keyword.fetch!(opts, :as))

  defp rejoin(query, qual, bindings, expr, as)
       when is_atom(qual) and is_atom(as),
       do: rejoin(query, qual, bindings, expr, [as: as], as)

  defp rejoin(query, qual, bindings, expr, opts, as),
    do: reusable_join_impl(query, qual, bindings, expr, opts, as)

  # expands aliases and metadata recursively
  defp expand(form, env) do
    case form do
      {:@, _, _} ->
        Macro.expand(form, env)

      {:__aliases__, _, _} ->
        Macro.expand(form, env)

      {k, meta, args} when is_list(args) ->
        {k, meta, Enum.map(args, &expand(&1, env))}

      {k, v} ->
        {expand(k, env), expand(v, env)}

      _ when is_list(form) ->
        Enum.map(form, &expand(&1, env))

      _ ->
        form
    end
  end

  # generates an ecto preload clause
  defp preload_clause(query, bindings, expr),
    do: quote(do: Ecto.Query.preload(unquote(query), unquote(bindings), unquote(expr)))

  # creates a var private to this module
  defp var(name) do
    # IO.warn(inspect name)
    Macro.var(name, __MODULE__)
  end

  # applies the current prefix for projoin
  defp prefix(x, y) when is_atom(x), do: prefix(Atom.to_string(x), y)
  defp prefix(x, y) when is_binary(x), do: String.to_atom(y <> x)


  @doc """
  Removes joins from an Ecto.Query that aren't referenced in other parts of the query.
  
  This function analyzes the query and removes any join whose binding is not used in select, where, order_by, group_by, having, limit, offset, or distinct clauses.
  
  ## Parameters
    - query: An Ecto.Query struct to optimize
  
  ## Returns
    - The optimized Ecto.Query with unused joins removed
  
  ## Examples
  
      iex> import Ecto.Query
      iex> query = from u in User, 
      ...>   join: p in Post, on: p.user_id == u.id,
      ...>   join: c in Comment, on: c.post_id == p.id, 
      ...>   where: p.published == true, 
      ...>   select: u
      iex> remove_unused_joins(query)
      #Ecto.Query<from u0 in User, join: p1 in Post, on: p1.user_id == u0.id, where: p1.published == true, select: u0>
  """
def remove_unused_joins(%Ecto.Query{} = query) do
  # Get all referenced indices in query parts
  referenced = MapSet.new()
  |> add_indices_from_expr(query.select)
  |> add_indices_from_expr(query.wheres)
  |> add_indices_from_expr(query.order_bys)
  |> add_indices_from_expr(query.group_bys)
  |> add_indices_from_expr(query.havings)
  |> add_indices_from_expr(query.distinct)
  |> add_indices_from_expr(query.limit)
  |> add_indices_from_expr(query.offset)
  |> IO.inspect(label: "referenced after pipeline")

  # Find which joins to keep based on references
  {used_joins, _} =
    Enum.reduce(Enum.with_index(query.joins, 1), {[], referenced}, fn {join, idx}, {keeps, refs} ->
      # Check if this join is referenced directly
      if MapSet.member?(refs, idx) do
        # Keep this join and continue checking its dependencies
        {[join | keeps], add_join_dependencies(refs, join)}
      else
        # Check if this join is needed for any other referenced join
        deps_in_refs = join_needed_by_refs?(join, refs, query.joins)
        if deps_in_refs do
          {[join | keeps], add_join_dependencies(refs, join)}
        else
          {keeps, refs}
        end
      end
    end)

  # Put used joins back in the correct order
  kept_joins = Enum.reverse(used_joins)
  %{query | joins: kept_joins}
end

# Add binding indices from a part of the query
defp add_indices_from_expr(indices, nil), do: indices
defp add_indices_from_expr(indices, %{expr: expr}), do: extract_indices(expr, indices)
defp add_indices_from_expr(indices, exprs) when is_list(exprs) do
  Enum.reduce(exprs, indices, fn expr, acc -> add_indices_from_expr(acc, expr) end)
end
defp add_indices_from_expr(indices, expr) do
  IO.inspect(expr, label: "Unsupported Expression A")
  indices
end

# Extract binding indices from an expression
defp extract_indices(%{expr: expr}, acc), do: extract_indices(expr, acc)
defp extract_indices(%Ecto.Query.Tagged{value: value} = expr, acc) do
  IO.inspect(expr, label: "Tagged Expression")
  extract_indices(value, acc)
end
defp extract_indices(nil, acc), do: acc
defp extract_indices({:&, _, [idx]}, acc), do: MapSet.put(acc, idx)
defp extract_indices(tuple, acc) when is_tuple(tuple) do
  tuple
  |> Tuple.to_list()
  |> Enum.reduce(acc, &extract_indices/2)
end
defp extract_indices(list, acc) when is_list(list) do
  Enum.reduce(list, acc, &extract_indices/2)
end
defp extract_indices(_, acc), do: acc
defp extract_indices(expr, acc) do
  IO.inspect(expr, label: "Unsupported Expression B")
  acc
end

# Add dependencies from a join to the referenced indices
defp add_join_dependencies(refs, %{on: %{expr: expr}}), do: extract_indices(expr, refs)
defp add_join_dependencies(refs, _), do: refs


# Check if a join is needed by any referenced join
defp join_needed_by_refs?(%{ix: join_ix}, refs, _joins), do: MapSet.member?(refs, join_ix)
defp join_needed_by_refs?(%{as: join_as}, refs, _joins), do: MapSet.member?(refs, join_as)
defp join_needed_by_refs?(join, refs, joins) do
  # Check if this join is referenced in the ON clause of another join that we're keeping
  Enum.with_index(joins, 1)
  |> Enum.any?(fn {other_join, other_idx} ->
    MapSet.member?(refs, other_idx) && join_referenced_in?(join, other_join.on)
  end)
end

# Check if a join is referenced in an expression
defp join_referenced_in?(_, nil), do: false
defp join_referenced_in?(%{ix: join_ix}, %{expr: {:&, _, [idx]}}), do: join_ix == idx
defp join_referenced_in?(%{as: join_as}, %{expr: {:&, _, [idx]}}), do: join_as == idx
defp join_referenced_in?(join, %{expr: {_, _, args}}) when is_list(args) do
  Enum.any?(args, &join_referenced_in?(join, %{expr: &1}))
end
defp join_referenced_in?(_, _), do: false
end