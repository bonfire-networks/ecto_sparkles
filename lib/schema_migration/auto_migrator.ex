defmodule EctoSparkles.AutoMigrator do
  @moduledoc """
  Runs ecto migrations automatically on startup (add this to your app's supervision tree)
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], [])
  end

  def init(_) do
    if is_nil(System.get_env("DISABLE_DB_AUTOMIGRATION")) do
      startup_migrations()
    end

    {:ok, nil}
  end

  def startup_migrations() do
    for repo <- EctoSparkles.Migrator.repos() do
      try do
        Logger.info("Attempting to run migrations on startup for #{inspect(repo)}")
        EctoSparkles.Migrator.create(repo)
        EctoSparkles.Migrator.status(repo)
        EctoSparkles.Migrator.migrate_repo(repo, continue_on_error: true)
        EctoSparkles.Migrator.status(repo)
        Logger.info("Done running migrations on startup for #{inspect(repo)}")
      rescue
        e ->
          Logger.error("Error when running migrations on startup for #{inspect(repo)}: #{inspect(e)}")

          :ok
      end
    end
  end
end
