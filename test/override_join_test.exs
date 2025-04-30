defmodule EctoSparkles.OverrideJoinTest do
  use ExUnit.Case, async: true
  
  import Ecto.Query
  import EctoSparkles
  
  # Define test schemas for our examples
  defmodule Post do
    use Ecto.Schema
    
    schema "posts" do
      field :title, :string
      field :published, :boolean, default: false
      
      has_many :comments, EctoSparkles.JoinOverrideTest.Comment
      belongs_to :user, EctoSparkles.JoinOverrideTest.User
      has_many :likes, EctoSparkles.JoinOverrideTest.Like
    end
  end
  
  defmodule Comment do
    use Ecto.Schema
    
    schema "comments" do
      field :body, :string
      belongs_to :post, EctoSparkles.JoinOverrideTest.Post
    end
  end
  
  defmodule User do
    use Ecto.Schema
    
    schema "users" do
      field :name, :string
      has_many :posts, EctoSparkles.JoinOverrideTest.Post
    end
  end
  
  defmodule Like do
    use Ecto.Schema
    
    schema "likes" do
      belongs_to :post, EctoSparkles.JoinOverrideTest.Post
      belongs_to :user, EctoSparkles.JoinOverrideTest.User
    end
  end


  # Helper function to find a join with a specific 'as' value
  defp find_join(query, as_value) do
    Enum.find(query.joins, fn join -> join.as == as_value end)
  end
  
  describe "join_override/5" do
    test "replaces existing join with same alias" do
      # First create a query with a join
      query = from p in Post,
                join: c in assoc(p, :comments), as: :comments,
                where: p.published == true

      # Now override the join with a different one
      result = join_override(query, :inner, [p], Comment, on: [post_id: p.id], as: :comments)
      
      # Should still have same number of joins
      assert length(query.joins) == length(result.joins)
      
      # The join should now be an inner join
      comments_join = find_join(result, :comments)
      assert comments_join.qual == :inner
    end
    
    test "adds join when no join with that alias exists" do
      # Create a query with no joins
      query = from p in Post,
                where: p.published == true

      # Add a join with override (should behave like normal join)
      result = join_override(query, :left, [p], c in Comment, on: c.post_id == p.id, as: :comments)
      
      # Should now have one join
      assert length(result.joins) == 1
      
      # The join should have the expected properties
      comments_join = find_join(result, :comments)
      assert comments_join.qual == :left
      assert comments_join.as == :comments
    end
    
    test "correctly handles different join qualifiers" do
      # Create queries with different types of joins
      query_with_left = from p in Post,
                          left_join: c in assoc(p, :comments), as: :comments
      
      # Override left join with inner join
      result_inner = join_override(query_with_left, :inner, [p], c in Comment, on: c.post_id == p.id, as: :comments)
      inner_join = find_join(result_inner, :comments)
      assert inner_join.qual == :inner
      
      # Override with right join
      result_right = join_override(query_with_left, :right, [p], c in Comment, on: c.post_id == p.id, as: :comments)
      right_join = find_join(result_right, :comments)
      assert right_join.qual == :right
      
      # Override with full join
      result_full = join_override(query_with_left, :full, [p], c in Comment, on: c.post_id == p.id, as: :comments)
      full_join = find_join(result_full, :comments)
      assert full_join.qual == :full
    end
    
    test "preserves other joins when replacing one" do
      # Create a query with multiple joins
      query = from p in Post,
                join: c in assoc(p, :comments), as: :comments,
                join: u in assoc(p, :user), as: :author,
                join: l in assoc(p, :likes), as: :likes

      # Replace just the comments join
      result = join_override(query, :inner, [p], c in Comment, on: c.post_id == p.id and c.body != "", as: :comments)
      
      # Should still have three joins
      assert length(result.joins) == 3
      
      # The comments join should be replaced (now inner)
      comments_join = find_join(result, :comments)
      assert comments_join.qual == :inner
      
      # The other joins should remain unchanged
      author_join = find_join(result, :author)
      assert author_join.qual == :inner # Default join type for join/5
      
      likes_join = find_join(result, :likes)
      assert likes_join.qual == :inner # Default join type for join/5
    end
    
    test "preserves the rest of query structure when replacing join" do
      # Create a complex query
      query = from p in Post,
                join: c in assoc(p, :comments), as: :comments,
                where: p.published == true,
                select: {p.title, count(c.id)},
                group_by: p.id,
                order_by: [desc: p.id],
                limit: 10

      # Replace the comments join
      result = join_override(query, :left, [p], c in Comment, 
                           on: c.post_id == p.id and c.body != "", 
                           as: :comments)
      
      # Verify the structure is preserved
      assert result.wheres == query.wheres
      assert result.select == query.select
      assert result.group_bys == query.group_bys
      assert result.order_bys == query.order_bys
      assert result.limit == query.limit
    end
    
    test "handles complex join expressions" do
      query = from p in Post,
                join: c in assoc(p, :comments), as: :comments

      # Replace with a more complex join expression
      result = join_override(query, :inner, [p], c in Comment, 
                           on: c.post_id == p.id and like(c.body, "important%") and
                               c.inserted_at > ago(1, "day"),
                           as: :comments)
      
      comments_join = find_join(result, :comments)
      assert comments_join.qual == :inner
      # We can't easily inspect the ON clause, but we can verify the join exists
      assert comments_join != nil
    end
    
    test "works with subqueries" do
      # Create a subquery
      subquery = from c in Comment,
                   where: c.body != "",
                   select: c
                   
      # Create a base query with a join
      query = from p in Post,
                join: c in ^subquery, on: c.post_id == p.id, as: :filtered_comments
                
      # Override the join
      result = join_override(query, :left, [p], c in ^subquery, 
                           on: c.post_id == p.id and p.published == true, 
                           as: :filtered_comments)
      
      filtered_join = find_join(result, :filtered_comments)
      assert filtered_join.qual == :left
    end
    
    test "handles bindings that are referenced elsewhere in query" do
      # Create a query with a join and reference the binding elsewhere
      query = from p in Post,
                join: c in assoc(p, :comments), as: :comments,
                where: c.body != "",  # using the 'c' binding in the where clause
                select: {p.title, c.body}  # using it in the select too
                
      # Now override the join to use a different source but same binding name
      result = join_override(query, :left, [p], c in Comment, 
                            on: c.post_id == p.id and c.body != "", 
                            as: :comments)
                
      # The join should be replaced
      comments_join = find_join(result, :comments)
      assert comments_join != nil
      assert comments_join.qual == :left
      
      # And query should still be valid since the binding is maintained
      # (We can't easily test compilation, but the structure should be sound)
      assert Enum.any?(result.wheres, fn where -> 
        case where do
          %{expr: {:!=, _, [{{:., _, [{:&, _, [ix]}, :body]}, _, _}, _]}} -> true
          _ -> false
        end
      end)
      
      # Check that the select is preserved
      case result.select.expr do
        {:%, _, [_, {:%{}, _, fields}]} ->
          field_names = Keyword.keys(fields)
          assert :title in field_names
          assert :body in field_names
        {:{}, [], fields} when is_list(fields) ->
          # Handles tuple select expressions like {p.title, c.body}
          assert Enum.any?(fields, fn 
            {{:., _, [{:&, _, [_]}, :title]}, _, _} -> true
            _ -> false
          end)
          assert Enum.any?(fields, fn 
            {{:., _, [{:&, _, [_]}, :body]}, _, _} -> true
            _ -> false
          end)
        _ ->
          IO.inspect(result.select.expr, label: "Unexpected select expression")
          flunk("Select clause structure not as expected")
      end
    end
  end


  describe "drop_join/2" do
    test "removes a join with a named binding" do
      query = from p in Post,
                join: c in assoc(p, :comments), as: :comments,
                join: u in assoc(p, :user), as: :user

      result = drop_join(query, :comments)
      
      # Should have one join less
      assert length(query.joins) - 1 == length(result.joins)
      
      # Should no longer contain the :comments join
      refute Enum.any?(result.joins, fn join -> join.as == :comments end)
      
      # Should still contain the :user join
      assert Enum.any?(result.joins, fn join -> join.as == :user end)
    end
    
    test "handles queries with no matching named bindings" do
      query = from p in Post,
                join: c in assoc(p, :comments), as: :comments

      # Should not change when trying to remove a non-existent binding
      result = drop_join(query, :non_existent)
      assert query.joins == result.joins
    end
    
    test "handles multiple joins with the same association but different named bindings" do
      query = from p in Post,
                join: c1 in assoc(p, :comments), as: :recent_comments,
                join: c2 in assoc(p, :comments), as: :pinned_comments

      result = drop_join(query, :recent_comments)
      
      # Should have one join less
      assert length(query.joins) - 1 == length(result.joins)
      
      # Should no longer contain the :recent_comments join
      refute Enum.any?(result.joins, fn join -> join.as == :recent_comments end)
      
      # Should still contain the :pinned_comments join
      assert Enum.any?(result.joins, fn join -> join.as == :pinned_comments end)
    end
    
    test "preserves the rest of the query structure" do
      query = from p in Post,
                join: c in assoc(p, :comments), as: :comments,
                join: u in assoc(p, :user), as: :user,
                where: p.published == true,
                select: {p.title, u.name, fragment("COUNT(?)", c.id)},
                group_by: [p.id, u.id],
                order_by: [desc: p.id]

      result = drop_join(query, :comments)
      
      # Basic structure checks
      assert result.from == query.from
      assert result.wheres == query.wheres
      assert result.order_bys == query.order_bys
      assert result.group_bys == query.group_bys
      
      # Should still contain the :user join
      assert Enum.any?(result.joins, fn join -> join.as == :user end)
      
      # Should no longer contain the :comments join
      refute Enum.any?(result.joins, fn join -> join.as == :comments end)
    end
    
    test "handles empty queries" do
      query = from p in Post

      result = drop_join(query, :comments)
      
      # Should not change a query with no joins
      assert result.joins == query.joins
    end
    
    test "should remove join but bindings may still be referenced" do
      # This test demonstrates the warning from Ecto docs:
      # "keep in mind that if a join is removed and its bindings were referenced elsewhere, 
      # the bindings won't be removed, leading to a query that won't compile."
      
      # Create a query with a join and reference the binding elsewhere
      query = from p in Post,
                join: c in assoc(p, :comments), as: :comments,
                where: c.body != "",  # using the 'c' binding in the where clause
                select: {p.title, c.body}  # using it in the select too
                
      # Drop the join but the references to 'c' will remain
      result = drop_join(query, :comments)
      
      # The join should be removed
      refute Enum.any?(result.joins, fn join -> join.as == :comments end)
      
      # But the where clause and select still reference the binding
      # (In an actual compiled query, this would cause a compilation error)
      assert Enum.any?(result.wheres, fn where -> 
        case where do
          %{expr: {:!=, _, [{{:., _, [{:&, _, [_]}, :body]}, _, _}, _]}} -> true
          _ -> false
        end
      end)
      
      # The select also still references the removed binding
      case result.select.expr do
        {:%, _, [_, {:%{}, _, fields}]} ->
          field_names = Keyword.keys(fields)
          assert :title in field_names
          assert :body in field_names
        {:{}, [], fields} when is_list(fields) ->
          # Handles tuple select expressions like {p.title, c.body}
          assert Enum.any?(fields, fn 
            {{:., _, [{:&, _, [_]}, :title]}, _, _} -> true
            _ -> false
          end)
          assert Enum.any?(fields, fn 
            {{:., _, [{:&, _, [_]}, :body]}, _, _} -> true
            _ -> false
          end)
        _ -> 
          IO.inspect(result.select.expr, label: "Unexpected select expression in drop_join test")
          flunk("Select clause structure not as expected")
      end
      
      # Note: We can't compile this query because the binding is gone, but the references remain.
      # This test just verifies the structure before compilation.
    end
  end


end