defmodule EctoSparkles.AutoMigrator do
  @moduledoc """
  Runs ecto migrations automatically on startup (add this to your app's supervision tree)
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  def init(opts) do
    if is_nil(System.get_env("DISABLE_DB_AUTOMIGRATION")) do
      startup_migrations(opts)
    end

    {:ok, nil}
  end

  @doc """
  Runs each repo's pending migrations. A failed migration stops boot, as with Ecto, unless `opts[:migration_error_callback_fn]` names a function to report it to and carry on (see `EctoSparkles.Migrator.migrate/1`), for example from the supervision tree: `{EctoSparkles.AutoMigrator, migration_error_callback_fn: &MyApp.report_migration_error/4}`.
  """
  def startup_migrations(opts \\ []) do

    for repo <- EctoSparkles.Migrator.repos() do
      # try do
      Logger.info("Attempting to run migrations on startup for #{inspect(repo)}")
      EctoSparkles.Migrator.create(repo)
      EctoSparkles.Migrator.status(repo)
      EctoSparkles.Migrator.migrate_repo(repo, opts)
      EctoSparkles.Migrator.status(repo)
      Logger.info("Done running migrations on startup for #{inspect(repo)}")
      # no longer rescued: it made every failed migration boot anyway, with one line in the log; carrying on is now the app's choice, through `migration_error_callback_fn`
      # rescue
      #   e ->
      #     Logger.error("Error when running migrations on startup for #{inspect(repo)}: #{inspect(e)}")
      #
      #     :ok
      # end
    end
  end
end
