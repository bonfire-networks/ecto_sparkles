# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.Migrator do
  require Logger

  @doc """
  Run all migrations for configured repos.

  Options:
    - `continue_on_error: true` - run migrations one by one, logging errors but continuing if one fails.
  """
  def migrate(opts \\ []) do
    for repo <- repos(), do: migrate_repo(repo, opts)
  end

  @doc """
  Run all migrations for the given repo.

  Options: see `migrate/1`
  """
  def migrate_repo(repo, opts \\ []) do
    Logger.info("Migrate #{inspect(repo)}")

    if Keyword.get(opts, :continue_on_error, false) do
      run_migrations_one_by_one(repo)
    else
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp run_migrations_one_by_one(repo) do
    paths = repo_migrations_path(repo)

    # Use a single with_repo call to keep the repo running for the entire
    # migration process (including data migrations that query the repo).
    {:ok, results, _} =
      Ecto.Migrator.with_repo(repo, fn repo ->
        migrations = Ecto.Migrator.migrations(repo, paths)

        pending =
          Enum.map(migrations, fn
            {status, version, desc, module} -> {status, version, desc, module}
            {status, version, desc} -> {status, version, desc, nil}
          end)
          |> Enum.filter(fn {status, _version, _desc, _module} -> status == :down end)
          |> Enum.map(fn {_status, version, desc, module} -> {version, desc, module} end)

        Enum.map(pending, fn {version, desc, module} ->
          Logger.info("Running migration #{version} (#{desc}) for #{inspect(repo)}")
          try do
            mod =
              case module do
                nil ->
                  case migration_module_from_file_or_loaded(paths, version, desc) do
                    {:ok, mod} -> mod
                    {:error, reason} ->
                      IO.warn("Skipping migration #{version} (#{desc}): #{reason}")
                      throw({:skip, version, desc, reason})
                  end
                mod -> mod
              end

            case Ecto.Migrator.up(repo, version, mod, []) do
              :ok ->
                {:ok, version, desc}
              :already_up ->
                Logger.info("Migration #{version} (#{desc}) was already up for #{inspect(repo)}")
                {:ok, version, desc}
              other ->
                IO.warn("Migration #{version} (#{desc}) for #{inspect(repo)} returned unexpected result: #{inspect(other)}")
                {:error, version, desc, other}
            end
          catch
            {:skip, version, desc, reason} ->
              {:skipped, version, desc, reason}
          rescue
            e ->
              IO.warn("Migration #{version} (#{desc}) failed for #{inspect(repo)}: #{Exception.message(e)}")
              {:error, version, desc, e}
          end
        end)
      end, mode: :temporary)

    results
  end

  defp migration_module_from_file_or_loaded(paths, version, desc) do
    # Try to find a loaded module matching the migration version and description
    mod_name =
      desc
      |> String.replace(~r/[^a-zA-Z0-9]/, "_")
      |> Macro.camelize()

    candidates =
      for app <- :code.all_loaded() |> Enum.map(fn {m, _} -> m end),
          mod_str = Atom.to_string(app),
          String.contains?(mod_str, Integer.to_string(version)),
          String.contains?(mod_str, mod_name),
          do: app

    case candidates do
      [mod | _] -> {:ok, mod}
      [] ->
        # fallback: load module from migration file
        path =
          List.wrap(paths)
          |> Enum.flat_map(&Path.wildcard(Path.join(&1, "migrations/#{version}_*.exs")))
          |> List.first()

        if path do
          [{mod, _}] = Code.load_file(path)
          {:ok, mod}
        else
          {:error, "Could not find a loaded module for version #{version} or a migration file in #{inspect paths}"}
        end
    end
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
      case repo.__adapter__().storage_up(repo.config()) do
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

  def rollback_to(version) do
    for repo <- repos(), do: rollback_to(repo, version)
  end

  def rollback_all() do
    for repo <- repos(), do: rollback_all(repo)
  end

  def create() do
    for repo <- repos(), do: create(repo)
  end

  def repos do
    app = Application.fetch_env!(:ecto_sparkles, :otp_app)
    Application.load(app)
    repos = Application.fetch_env!(app, :ecto_repos)
    Logger.info("Repos for app #{inspect(app)}: #{inspect(repos)}")
    repos
  end

  @doc """
  Print the migration status for configured Repos' migrations.
  """
  def status do
    for repo <- repos(), do: status(repo)
  end

  def status(repo) do
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
