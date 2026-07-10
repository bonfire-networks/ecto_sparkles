defmodule EctoSparkles.AssocHelpers do

  def table_name(schema), do: schema.__schema__(:source)

    defmacro table_src(schema), do: schema.__schema__(:source)

  @doc "Recursively get aliases from association spec - works for both Ecto and SQL"
  def get_aliases(form, prefix \\ "") do
    case form do
      _ when is_atom(form) ->
        [prefix(form, prefix)]
      
      _ when is_list(form) ->
        Enum.flat_map(form, &get_aliases(&1, prefix))
      
      {pre, form} when is_binary(pre) ->
        get_aliases(form, prefix <> pre)
      
      {rel, form} when is_atom(rel) ->
        [prefix(rel, prefix) | get_aliases(form, prefix)]
      
      _ ->
        []
    end
  end
  
  
  @doc "Apply prefix to association name"
  def prefix(x, y) when is_atom(x), do: prefix(Atom.to_string(x), y)
  def prefix(x, y) when is_binary(x), do: String.to_atom(y <> x)
  

  @doc "Walk association spec with callback - DRY for both JOIN generation and mapping"
  def walk_associations(form, schema, acc, callback, prefix \\ "") do
    case form do
      _ when is_atom(form) ->
        callback.(acc, schema, form, prefix)
      
      _ when is_list(form) ->
        Enum.reduce(form, acc, fn f, a ->
          walk_associations(f, schema, a, callback, prefix)
        end)
      
      {pre, form} when is_binary(pre) ->
        walk_associations(form, schema, acc, callback, prefix <> pre)
      
      {rel, form} when is_atom(rel) ->
        # Process this association
        acc = callback.(acc, schema, rel, prefix)
        
        # Get related schema and recurse
        assoc_meta = schema.__schema__(:association, rel)
        walk_associations(form, assoc_meta.related, acc, callback, prefix)
      
      _ ->
        acc
    end
  end


  
  def parent_primary_key(schema) do
    schema.__schema__(:primary_key) |> List.first()
  end
end