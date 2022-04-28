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

    startup_migrations()

    {:ok, nil}
  end

  def startup_migrations() do
    if is_nil(System.get_env("DISABLE_DB_AUTOMIGRATION")) do
      try do
        EctoSparkles.Migrator.create()
        EctoSparkles.Migrator.migrate()
      rescue
        e ->
          Logger.error("Error when running migrations on startup: #{inspect e}")

          :ok
      end
    end
  end
end
