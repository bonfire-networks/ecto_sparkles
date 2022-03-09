# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.ReleaseTasks do
  require Logger

  def rollback(repo \\ nil, step \\ 1)

  def migrate(repo) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
  end

  def rollback(repo, step) when not is_nil(repo) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, step: step))
  end

  def rollback_to(repo, version) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def rollback_all(repo) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, all: true))
  end

  def create(repo) do
    try do
      case repo.__adapter__.storage_up(repo.config) do
        :ok ->
          Logger.info("The database for #{inspect(repo)} has been created")

        {:error, :already_up} ->
          :ok
        e ->
          Logger.error("The database for #{inspect(repo)} could not be created #{inspect e}")
      end
    rescue
      e ->
        Logger.error("The database for #{inspect(repo)} failed to be created #{inspect e}")
    end
  end


  def migrate do
    for repo <- repos(), do: migrate(repo)
  end

  def rollback(nil, step) do
    for repo <- repos(), do: rollback(repo, step)
  end

  def rollback_to(version) do
    for repo <- repos(), do: rollback_to(repo, version)
  end

  def rollback_all() do
    for repo <- repos(), do: rollback_all(repo)
  end

  def create() do
    for repo <- repos(), do: create(repo)
  end


  defp repos do
    app = Application.fetch_env!(:ecto_sparkles, :otp_app)
    Application.load(app)
    Application.fetch_env!(app, :ecto_repos)
  end

end
