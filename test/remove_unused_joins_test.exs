  defmodule User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :email, :string
    has_many :posts, Post
    
    timestamps()
  end
end

defmodule Post do
  use Ecto.Schema

  schema "posts" do
    field :title, :string
    field :content, :string
    field :published, :boolean, default: false
    
    belongs_to :user, User
    has_many :comments, Comment
    
    timestamps()
  end
end

defmodule Comment do
  use Ecto.Schema

  schema "comments" do
    field :content, :string
    
    belongs_to :post, Post
    belongs_to :user, User
    
    timestamps()
  end
end


defmodule EctoSparkles.Test do
  use ExUnit.Case
  import EctoSparkles
  import Ecto.Query


doctest EctoSparkles


  describe "remove_unused_joins/1" do
    test "removes unused joins from a simple query" do
      query =
        from u in User,
          join: p in Post, on: p.user_id == u.id,
          join: c in Comment, on: c.post_id == p.id,
          where: p.published == true,
          select: u

      optimized = EctoSparkles.remove_unused_joins(query)
      optimized_string = Inspect.Ecto.Query.to_string(optimized)

      # Only the Post join should remain
      assert optimized_string =~ "join: p1 in Post"
      refute optimized_string =~ "join: c2 in Comment"
      assert optimized_string =~ "where: p1.published == true"
      assert optimized_string =~ "select: u0"
    end

    test "keeps all joins if all are used" do
      query =
        from u in User,
          join: p in Post, on: p.user_id == u.id,
          join: c in Comment, on: c.post_id == p.id,
          where: p.published == true and c.body != "",
          select: {u, c}

      optimized = EctoSparkles.remove_unused_joins(query)
      optimized_string = Inspect.Ecto.Query.to_string(optimized)

      # Both joins should remain
      assert optimized_string =~ "join: p1 in Post"
      assert optimized_string =~ "join: c2 in Comment"
      assert optimized_string =~ "where: p1.published == true and c2.body !="
      assert optimized_string =~ "select: {u0, c2}"
    end

    test "removes join if only used in ON clause of unused join" do
      query =
        from u in User,
          join: p in Post, on: p.user_id == u.id,
          join: c in Comment, on: c.post_id == p.id,
          select: u

      optimized = EctoSparkles.remove_unused_joins(query)
      optimized_string = Inspect.Ecto.Query.to_string(optimized)

      # Both joins should be removed since neither is referenced in select
      refute optimized_string =~ "join: p1 in Post"
      refute optimized_string =~ "join: c2 in Comment"
      assert optimized_string =~ "select: u0"
    end
  end

end
