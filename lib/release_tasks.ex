# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.ReleaseTasks do

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


  defp repos do
    app = Application.fetch_env!(:ecto_sparkles, :otp_app)
    Application.load(app)
    Application.fetch_env!(app, :ecto_repos)
  end

end
