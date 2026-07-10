defmodule EctoSparkles.SQL.Query do
    # see https://claude.ai/chat/7d2e915d-4023-4257-8d7d-2de21a3e969d
  use SQL, pool: :default, adapter: SQL.Adapters.Postgres, repo: Bonfire.Common.Repo
  import EctoSparkles.AssocHelpers
  alias EctoSparkles.SQL.Query

  # import Bonfire.Common.Extend, only: [extend_struct: 2]
  # extend_struct SQL, some: "extra", key: "with overrides", b: "three"

  def test, do: 
    SQL.map(~SQL[select * from bonfire_data_identity_account left join bonfire_data_identity_email USING (id) left join bonfire_data_identity_accounted ON bonfire_data_identity_accounted.account_id = bonfire_data_identity_account.id left join bonfire_data_identity_user ON bonfire_data_identity_accounted.id = bonfire_data_identity_user.id left join bonfire_data_social_profile ON bonfire_data_identity_user.id = bonfire_data_social_profile.id], fn       
      # row, columns -> 
      #   IO.inspect(columns, label: "columns")
      #   IO.inspect(row, label: "row")
      #   Map.new(Enum.zip(columns, row))
      row, columns, repo -> repo.load(Bonfire.Data.Identity.Account, {columns, row})
     end) 
     |> Enum.to_list()

     
  defmacro test_macro() do
    quote do
        SQL.parse("select * from #{unquote(table_name(Bonfire.Data.Identity.Account))} left join #{unquote(table_name(Bonfire.Data.Identity.Email))} USING (id)")

    #  SQL.build(unquote(left), "select * from #{unquote(table_name(Bonfire.Data.Identity.Account))} left join #{unquote(table_name(Bonfire.Data.Identity.Email))} USING (id)", [], __ENV__)
    end
  end

    # def test, do: 
  #   SQL.map(test_macro(), fn       
  #     row, columns -> 
  #       IO.inspect(columns, label: "columns")
  #       IO.inspect(row, label: "row")
  #       Map.new(Enum.zip(columns, row))
  #     # row, columns, repo -> repo.load(Bonfire.Data.Identity.Account, {columns, row})
  #    end) 
  #    |> Enum.to_list()

#   def test, do: 
#     SQL.map(from(Bonfire.Data.Identity.Account), fn       
#       row, columns -> 
#         IO.inspect(columns, label: "columns")
#         IO.inspect(row, label: "row")
#         Map.new(Enum.zip(columns, row))
#       # row, columns, repo -> repo.load(Bonfire.Data.Identity.Account, {columns, row})
#      end) 
#      |> Enum.to_list()


  defmacro from(table_schema) do
    quote do
        SQL.parse("from #{unquote(table_name(table_schema))}")
    end
  end

  defmacro join(qual \\ "left", table_schema) do
    quote do
        "#{unquote(qual)} join #{unquote(table_name(table_schema))} USING (id)"
    end
  end

# def test do
#     SQL.parse("select * from #{table_src(Bonfire.Data.Identity.Account)} left join #{table_src(Bonfire.Data.Identity.Email)} USING (column_name)")
#     |> SQL.map(fn row, columns, repo -> repo.load(Bonfire.Data.Identity.Account, {columns, row}) end)
#     |> Enum.to_list()
# end

#   defstruct [:sql, :schema, :preload_spec, :joined_aliases]
  
#   def new(schema) do
#     %__MODULE__{
#       sql: ~SQL[from #{table_name(schema)} as t],
#       schema: schema,
#       preload_spec: [],
#       joined_aliases: MapSet.new([:t])  # Track which aliases we've already joined
#     }
#   end
  
#   def query(schema, sql_fragment) when is_atom(schema) do
#     %{new(schema) | sql: new(schema).query |> sql_fragment}
#   end
  
#   def query(q, sql_fragment) do
#     %{q | sql: q.query |> sql_fragment}
#   end
  
#   def proload(q, qual \\ :left, associations) do
#     # Similar to EctoSparkles.proload, but track joined aliases
#     {new_query, new_aliases} = join_assoc_sql(
#       q.query, 
#       q.schema, 
#       associations, 
#       qual, 
#       q.joined_aliases
#     )
    
#     %{q | 
#       sql: new_query,
#       preload_spec: q.preload_spec ++ [associations],
#       joined_aliases: new_aliases
#     }
#   end
  
#   def all(q) do
#     q.query
#     |> SQL.map(fn row, columns -> Enum.zip(columns, row) |> Map.new() end)
#     |> Enum.to_list()
#     |> nest_from_spec(q.schema, q.preload_spec)
#   end
  
#   # Generate JOINs with reusable_join logic
#   defp join_assoc_sql(query, schema, form, qual, joined_aliases, prefix \\ "") do
#     walk_associations(form, schema, {query, joined_aliases}, fn {q, aliases}, sch, rel, pfx ->
#       alia = prefix(rel, pfx)
      
#       # Only join if we haven't already - like EctoSparkles.reusable_join
#       if MapSet.member?(aliases, alia) do
#         # Already joined, skip
#         {q, aliases}
#       else
#         # Perform the join and track the alias
#         new_query = join_single_assoc(q, sch, rel, alia, qual)
#         {new_query, MapSet.put(aliases, alia)}
#       end
#     end, prefix)
#   end
  
#   defp join_single_assoc(query, schema, rel, alia, qual) do
#     assoc_meta = schema.__schema__(:association, rel)
#     table = assoc_meta.related.__schema__(:source)
    
#     case assoc_meta do
#       %Ecto.Association.BelongsTo{} ->
#         query 
#         |> ~SQL[{{qual_to_sql(qual)}} join {{table}} as {{alia}} 
#                 on {{alia}}.{{assoc_meta.related_key}} = t.{{assoc_meta.owner_key}}]
      
#       %Ecto.Association.Has{} ->
#         query 
#         |> ~SQL[{{qual_to_sql(qual)}} join {{table}} as {{alia}} 
#                 on {{alia}}.{{assoc_meta.related_key}} = t.{{assoc_meta.owner_key}}]
      
#       _ ->
#         raise "Unsupported association type: #{inspect(assoc_meta.__struct__)}"
#     end
#   end
  
#   defp qual_to_sql(:left), do: "left"
#   defp qual_to_sql(:inner), do: "inner"
#   defp qual_to_sql(:right), do: "right"
  


#     @doc """
#   Map flat rows using the same spec format as EctoSparkles.proload
#   """
#   def nest_from_spec(flat_rows, parent_schema, preload_specs) do
#     # Use proload_aliases to get all the aliases that were generated
#     aliases = Enum.flat_map(preload_specs, &get_aliases/1)
    
#     # Group rows by parent ID
#     flat_rows
#     |> Enum.group_by(&Map.get(&1, parent_primary_key(parent_schema)))
#     |> Enum.map(fn {_id, rows} ->
#       nest_row_group(rows, parent_schema, preload_specs, aliases)
#     end)
#   end
  

#   defp nest_row_group(rows, parent_schema, preload_specs, _aliases) do
#     first = List.first(rows)
#     parent_fields = parent_schema.__schema__(:fields)
    
#     # Extract parent data
#     parent_data = Map.take(first, parent_fields)
#     parent = struct(parent_schema, parent_data)
    
#     # Map each association in the spec
#     # TODO: implement nested association mapping using the spec structure
#     parent
#   end
end