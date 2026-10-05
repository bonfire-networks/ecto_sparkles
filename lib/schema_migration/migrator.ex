# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.Migrator do
  require Logger

  @doc """
  Run all migrations for configured repos.

  Options:
    - `migration_error_callback_fn: fun` - run migrations one by one, calling `fun.(version, description, error, stacktrace)` for each that fails and carrying on. Without it, a failed migration raises and stops the run, as with Ecto. For example, to log failures and carry on:

          migrate_repo(MyApp.Repo,
            migration_error_callback_fn: fn version, desc, error, stacktrace ->
              Logger.error("Migration \#{version} (\#{desc}) failed: " <> Exception.format(:error, error, stacktrace))
            end
          )

  Either way migrations run on connections of their own without the repo's `statement_timeout` or `idle_in_transaction_session_timeout`, since a migration that rewrites a big table can take longer than any query should (see `with_migration_repo/2`).
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

    case opts[:migration_error_callback_fn] do
      migration_error_callback_fn when is_function(migration_error_callback_fn, 4) ->
        run_migrations_one_by_one(repo, migration_error_callback_fn, opts)
      _ ->
        {:ok, _, _} =
          Ecto.Migrator.with_repo(repo, fn repo ->
            with_migration_repo(repo, fn -> Ecto.Migrator.run(repo, :up, all: true) end)
        end)
    end
  end

  @doc """
  Runs `fun` with the repo pointing at a pool of its own (as its dynamic repo), whose connections have no `statement_timeout` or `idle_in_transaction_session_timeout`, then stops that pool.

  A migration runs in its own process on a connection from the repo's pool (`Ecto.Migrator.up/4`), and every connection of an app's pool opens with the limits its queries should have, so a migration that outlasts them is cancelled. Code that a migration calls itself (a data migration's own queries) uses the same pool, since the migrator gives the migration's process the dynamic repo of the process that called it.
  """
  def with_migration_repo(repo, fun) do
    parameters =
      Keyword.merge(repo.config()[:parameters] || [],
        statement_timeout: "0",
        idle_in_transaction_session_timeout: "0"
      )

    {:ok, pid} =
      repo.start_link(
        name: nil,
        pool: DBConnection.ConnectionPool,
        pool_size: 2,
        parameters: parameters
      )

    previous = repo.get_dynamic_repo()
    repo.put_dynamic_repo(pid)

    try do
      fun.()
    after
      repo.put_dynamic_repo(previous)
      Supervisor.stop(pid)
    end
  end

  defp run_migrations_one_by_one(repo, migration_error_callback_fn, opts) do
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

        run_pending(repo, migration_error_callback_fn, pending, Keyword.put(opts, :paths, paths))
      end, mode: :temporary)

    results
  end

  @doc """
  Runs these migrations one by one, `[{version, description, module}]`, on a pool without timeouts (`with_migration_repo/2`). A `nil` module is loaded from the migration file under `opts[:paths]`.

  A failure goes to `on_error` (required) and the run carries on. Without a callback there's no need for this: `migrate_repo/2` runs Ecto's own migrator, which raises.

  Returns a result per migration: `{:ok, version, description}`, `{:skipped, version, description, reason}` or `{:error, version, description, error}`.
  """
  def run_pending(repo, on_error, pending, opts \\ []) do
    paths = opts[:paths]

    with_migration_repo(repo, fn ->
      Enum.map(pending, fn {version, desc, module} ->
        Logger.info("Running migration #{version} (#{desc}) for #{inspect(repo)}")

        try do
          mod =
            case module do
              nil ->
                case migration_module_from_file_or_loaded(paths, version, desc) do
                  {:ok, mod} -> mod
                  {:error, reason} -> throw({:skip, reason})
                end

              mod ->
                mod
            end

          case Ecto.Migrator.up(repo, version, mod, []) do
            :ok ->
              {:ok, version, desc}

            :already_up ->
              Logger.info("Migration #{version} (#{desc}) was already up for #{inspect(repo)}")
              {:ok, version, desc}

            other ->
              throw({:unexpected, other})
          end
        catch
          {:skip, reason} ->
            on_error.(version, desc, reason, [])
            {:skipped, version, desc, reason}

          {:unexpected, other} ->
            on_error.(version, desc, other, [])
            {:error, version, desc, other}
        rescue
          e ->
            on_error.(version, desc, e, __STACKTRACE__)
            {:error, version, desc, e}
        end
      end)
    end)
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

  def rollback_to(repo \\ nil, version) 
  def rollback_to(nil, version) do
    for repo <- repos(), do: rollback_to(repo, version)
  end
  def rollback_to(repo, version) do
    Logger.info("Rollback #{inspect(repo)} to version #{inspect(version)}")

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def rollback_all(repo \\ nil) 
  def rollback_all(nil) do
    for repo <- repos(), do: rollback_all(repo)
  end
  def rollback_all(repo) do
    Logger.info("Rollback #{inspect(repo)}")

    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, all: true))
  end

  def migrated_versions(repo \\ nil)
  def migrated_versions(nil) do
    for repo <- repos(), do: migrated_versions(repo)
  end
  def migrated_versions(repo) do
    Ecto.Migrator.with_repo(repo, &Ecto.Migrator.migrated_versions/1)
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
