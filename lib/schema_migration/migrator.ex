# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.Migrator do
  require Logger


  def migrate(repo) do
    Logger.info("Migrate #{inspect(repo)}")

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
  end

  def rollback(repo \\ nil, step \\ 1)
  def rollback(repo, step) when not is_nil(repo) do
    Logger.info("Rollback #{inspect(repo)} by #{inspect(step)} step")

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, step: step))
  end
  def rollback(nil, step) do
    for repo <- repos(), do: rollback(repo, step)
  end

  def rollback_to(repo, version) do
    Logger.info("Rollback #{inspect(repo)} to version #{inspect(version)}")

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def rollback_all(repo) do
    Logger.info("Rollback #{inspect(repo)}")

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, all: true))
  end

  def create(repo, attempt \\ 0) do
    try do
      case repo.__adapter__().storage_up(repo.config) do
        :ok ->
          Logger.info("The database for #{inspect(repo)} has been created")
          :ok

        {:error, :already_up} ->
          :ok

        e ->
          Logger.warning("The database for #{inspect(repo)} could not be created: #{inspect(e)}")

          if attempt < 10 do
            # wait for Postgres to be up
            Process.sleep(1000)
            create(repo, attempt + 1)
          else
            Logger.warning("After 10 attempts, the database for #{inspect(repo)} still could not be created: #{inspect(e)}")
          end
      end
    rescue
      e ->
        Logger.error("The database for #{inspect(repo)} failed to be created: #{inspect(e)}")
    end
  end

  def migrate do
    for repo <- repos(), do: migrate(repo)
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

  @doc """
  Print the migration status for configured Repos' migrations.
  """
  def status do
    for repo <- repos(), do: print_migrations_for(repo)
  end

  defp print_migrations_for(repo) do
    paths =
      repo_migrations_path(repo)
      |> IO.inspect(label: "Migration path")

    {:ok, repo_status, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.migrations(&1, paths), mode: :temporary)

    IO.puts(
      """
      Repo: #{inspect(repo)}
        Status    Migration ID    Migration Name
      --------------------------------------------------
      """ <>
        Enum.map_join(repo_status, "\n", fn {status, number, description} ->
          "  #{pad(status, 10)}#{pad(number, 16)}#{description}"
        end) <> "\n"
    )
  end

  defp repo_migrations_path(repo) do
    config = repo.config()

    priv =
      config[:priv] ||
        "priv/#{repo |> Module.split() |> List.last() |> Macro.underscore()}"


    (Keyword.get(config, :project_path) || Application.app_dir(Keyword.fetch!(config, :otp_app)))
    |> Path.join(priv)
  end

  defp pad(content, pad) do
    content
    |> to_string
    |> String.pad_trailing(pad)
  end
end
