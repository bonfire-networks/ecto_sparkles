defmodule EctoSparkles.DataMigration do
  @moduledoc """
  A behaviour implemented by our data migrations (generally backfills).
  
  Based on [A microframework for backfill migrations in Elixir's Ecto](https://tylerayoung.com/2023/08/13/migrations/), in turn based on David Bernheisel's [template for deterministic backfills](https://fly.io/phoenix-files/backfilling-data/#batching-deterministic-data).

  A data migration using this behaviour may look like this (which you can put simply put in Ecto migrations, eg. `priv/repo/migrations/priv/repo/migrations/20231019004944_data_onboarding_step.exs`):

  ```elixir
  defmodule MyApp.Repo.Migrations.BackfillOnboardingStep do
    alias EctoSparkles.DataMigration
    use DataMigration
    
    @impl DataMigration
    def base_query do
      # NOTE: This works in cases where:
      # 1. The data can be queried with a condition that not longer applies after the migration ran, so you can repeatedly query the data and update the data until the query result is empty. For example, if a column is currently null and will be updated to not be null, then you can query for the null records and pick up where you left off.
      # 2. The migration is written in such a way that it can be ran several times on the same data without causing data loss or duplication (or crashing).

      from(u in "users", # Notice how we do not use Ecto schemas here.
        where: is_nil(u.onboarding_step),
        select: %{id: u.id}
      )
      # NOTE: result should contain an :id key for the migration runner to track progress
    end

    @impl DataMigration
    def config do
      %DataMigration.Config{batch_size: 100, throttle_ms: 1_000, repo: MyApp.Repo}
    end

    @impl DataMigration
    def migrate(results) do
      Enum.each(results, fn %{id: user_id} ->
        # hooks into a context module, which is more likely to be kept up to date as the app evolves, to avoid having to update old migrations
        user_id
        |> MyApp.Users.set_onboarding_step!()
      end)
    end
  end
  ```
  """
  alias EctoSparkles.DataMigration

  @callback config() :: DataMigration.Config.t()

  @doc """
  The core of the query you want to use to SELECT a map of your data.
  The `DataMigration.Runner` will take care of limiting this to a batch size, ordering
  it by row ID, and restricting it to rows you haven't yet handled.
  The query *must* select a map, and that map must have an `:id` key for the
  migration runner to reference as the last-modified row in your table.
  """
  @callback base_query() :: Ecto.Query.t()

  @doc """
  The callback to operate on a result set from your query.
  Implementers should `raise` an error if you're unable to process the batch.
  """
  @callback migrate([map]) :: :ok | no_return()

  defmacro __using__(_) do
    quote do
      use Ecto.Migration
      import Ecto.Query
      alias EctoSparkles.DataMigration

      @behaviour DataMigration

      @disable_ddl_transaction true
      @disable_migration_lock true

      @spec up :: :ok | no_return()
      def up do
        DataMigration.Runner.run(__MODULE__)
      end

      @spec down :: :ok
      def down, do: :ok
    end
  end
end
