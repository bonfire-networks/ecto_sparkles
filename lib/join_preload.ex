defmodule EctoSparkles.JoinPreload do
  @moduledoc """
  A module for preloading associations using joins.

  Based on https://hexdocs.pm/ecto_preloader (licensed under WTFPL)

  By default, Ecto preloads associations using a separate query for each association, which can degrade performance.

  You could make it run faster by using a combination of join/preload, but that requires a bit of boilerplate (see example below).

  With `Ecto.Preloader`, you can accomplish this with just one line of code.

  ## Example using just Ecto

  It requires calling `Query.join/4`, `Query.assoc/3` and `Query.preload/2`

  ```
  import Ecto.Query

  Invoice
  |> join(:left, [i], assoc(i, :customer), as: :customer)
  |> join(:left, [i, c], assoc(c, :account), as: :account)
  |> join(:left, [i], assoc(i, :lines), as: :lines)
  |> preload([lines: v, customers: c, account: a], lines: v, customer: {c, [a: account]})
  |> Repo.all()
  ```

  ## Example using Ecto.Preloader

  Just one method call:

  ```
  import Ecto.Query
  import Ecto.Preloader

  Invoice
  |> join_preload([:customer, :account])
  |> join_preload([:lines])
  |> Repo.all()
  ```

  """

  import Ecto, only: [assoc: 2]
  # require EctoSparkles.ReusableJoin
  # alias EctoSparkles.JoinPreload
  # alias Ecto.Query.Builder.{Join, Preload}

  @doc "Join + Preload (up to three nested levels of) associations"
  defmacro join_preload(query, associations) when is_list(associations) do
    quote do: preload_join(unquote(query), unquote_splicing(associations))
  end
  defmacro join_preload(query, association) when is_atom(association) do
    quote do: preload_join(unquote(query), association)
  end
  defmacro join_preload(query, associations) do
    IO.inspect(join_preload_failed: associations)
    query
  end

  defmacro do_preload_join(query, association, bindings, expr, preload_bindings, preload_expr ) do
    #IO.inspect(query: query)
    #IO.inspect(queryable: Ecto.Queryable.to_query(query))
    #IO.inspect(bindings: bindings)
    #IO.inspect(expr: expr)
    #IO.inspect(association: association)

    # on = quote do: [{as, unquote(association)}] ++ unquote(opts) # FIXME if we need to pass on
    opts = quote do: [as: unquote(association)]
    #IO.inspect(on: on)

    #IO.inspect(preload_bindings: preload_bindings)
    #IO.inspect(preload_expr: preload_expr)

    quote do

      unquote(query)
      |> EctoSparkles.ReusableJoin.do_reusable_join_as(:left, unquote(bindings), unquote(expr), unquote(opts), unquote(association))
      |> preload(unquote(preload_bindings), unquote(preload_expr))
      # |> IO.inspect
    end
  end

  #doc "Join + Preload an association"
  defmacro preload_join(query, association) when is_atom(association) do

    # association = quote do: unquote(association)
    bindings = quote do: [root]
    expr = quote do: assoc(root, unquote(association))

    preload_bindings = quote do: [{unquote(association), ass}]
    preload_expr = quote do: [{unquote(association), ass}]

    quote do: do_preload_join(unquote(query), unquote(association), unquote(bindings), unquote(expr), unquote(preload_bindings), unquote(preload_expr) )
  end

  #doc "Join + Preload 2 nested associations"
  defmacro preload_join(query, via_association, association ) when is_atom(via_association) and is_atom(association) do

    query = quote do: preload_join(unquote(query), unquote(via_association))

    # association = quote do: unquote(association)
    # via_association_pos = quote do: named_binding_position(unquote(query), unquote(via_association))
    #IO.inspect(via_association_pos: via_association_pos)
    bindings = quote do: [root, {unquote(via_association), via}]
    expr = quote do: assoc(via, unquote(association))

    preload_bindings = quote do: [root,
      {unquote(association), ass},
      {unquote(via_association), via}
    ]
    # preload_expr = quote do: [{unquote(via_association), unquote(association)}]
    preload_expr = quote do: [
      {
        unquote(via_association), {via,
          [{unquote(association), ass}]
        }
      }
    ]

    quote do: do_preload_join(unquote(query), unquote(association), unquote(bindings), unquote(expr), unquote(preload_bindings), unquote(preload_expr) )
  end

  #doc "Join + Preload an assoc within 3 levels of nested associations"
  defmacro preload_join(query, via_association_1, via_association_2, association) when is_atom(via_association_1) and is_atom(via_association_2) and is_atom(association) do

    query = quote do: preload_join(unquote(query), unquote(via_association_1), unquote(via_association_2))
    # |> IO.inspect(label: "pre level 3")

    # association = quote do: unquote(association)
    # via_association_1_pos = named_binding_position(query, via_association_1)
    #IO.inspect(via_association_1_pos: via_association_1_pos)
    # bindings = quote do: [root, {via_2, unquote(via_association_2)}] # bad
    bindings = quote do: [root, {unquote(via_association_2), via_2}] # good
    expr = quote do: assoc(via_2, unquote(association))

    # preload_bindings = quote do: [root, a, b, x]
    # preload_expr = quote do: [{unquote(via_association_1), [{unquote(via_association_2), [unquote(association)]}]}]

    preload_bindings = quote do: [root,
      {unquote(association), ass},
      {unquote(via_association_1), via_1},
      {unquote(via_association_2), via_2}
    ]
    preload_expr = quote do: [
      {
        unquote(via_association_1), {via_1,
          [
            {unquote(via_association_2), {via_2,
              [{unquote(association), ass}]
              }
            }
          ]
        }
      }
    ]
    quote do: do_preload_join(unquote(query), unquote(association), unquote(bindings), unquote(expr), unquote(preload_bindings), unquote(preload_expr))
    # |> IO.inspect(label: "post level 3")
  end

  #doc "Join + Preload an assoc within 4 levels of nested associations"
  defmacro preload_join(query, via_association_1, via_association_2, via_association_3, association) when is_atom(via_association_1) and is_atom(via_association_2) and is_atom(via_association_3) and is_atom(association) do

    query = quote do: preload_join(unquote(query), unquote(via_association_1), unquote(via_association_2), unquote(via_association_3))
    # |> IO.inspect(label: "pre level 4")

    bindings = quote do: [root, {unquote(via_association_3), via_3}]
    expr = quote do: assoc(via_3, unquote(association))

    # preload_bindings = quote do: [root, a, b, x]
    # preload_expr = quote do: [{unquote(via_association_1), [{unquote(via_association_2), [unquote(association)]}]}]

    preload_bindings = quote do: [root,
      {unquote(association), ass},
      {unquote(via_association_1), via_1},
      {unquote(via_association_2), via_2},
      {unquote(via_association_3), via_3}
    ]
    preload_expr = quote do: [
      {
        unquote(via_association_1), {via_1,
          [
            {unquote(via_association_2), {via_2,
                [
                    {unquote(via_association_3), {via_3,
                      [{unquote(association), ass}]
                    }
                  }
                ]
              }
            }
          ]
        }
      }
    ]
    quote do: do_preload_join(unquote(query), unquote(association), unquote(bindings), unquote(expr), unquote(preload_bindings), unquote(preload_expr))
    # |> IO.inspect(label: "post level 4")
  end

  #doc "Join + Preload an assoc within 5 levels of nested associations"
  defmacro preload_join(query, via_association_1, via_association_2, via_association_3, via_association_4, association) when is_atom(via_association_1) and is_atom(via_association_2) and is_atom(via_association_3) and is_atom(via_association_4) and is_atom(association) do

    query = quote do: preload_join(unquote(query), unquote(via_association_1), unquote(via_association_2), unquote(via_association_3), unquote(via_association_4))
    # |> IO.inspect(label: "pre level 5")

    bindings = quote do: [root, {unquote(via_association_4), via_4}]
    expr = quote do: assoc(via_4, unquote(association))

    # preload_bindings = quote do: [root, a, b, x]
    # preload_expr = quote do: [{unquote(via_association_1), [{unquote(via_association_2), [unquote(association)]}]}]

    preload_bindings = quote do: [root,
      {unquote(association), ass},
      {unquote(via_association_1), via_1},
      {unquote(via_association_2), via_2},
      {unquote(via_association_3), via_3},
      {unquote(via_association_4), via_4}
    ]
    preload_expr = quote do: [
      {
        unquote(via_association_1), {via_1,
          [
            {unquote(via_association_2), {via_2,
                [
                  {unquote(via_association_3), {via_3,
                      [
                        {unquote(via_association_4), {via_4,
                            [
                              {unquote(association), ass}
                            ]
                          }
                        }
                      ]
                    }
                  }
                ]
              }
            }
          ]
        }
      }
    ]
    quote do: do_preload_join(unquote(query), unquote(association), unquote(bindings), unquote(expr), unquote(preload_bindings), unquote(preload_expr))
    # |> IO.inspect(label: "post level 5")
  end

end
