defmodule EctoSparkles.DataMigration.Runner do
  @moduledoc """
  Runs a `DataMigration`
  """
  import Ecto.Query
  # alias EctoSparkles.DataMigration

  @spec run(module(), keyword()) :: :ok | no_return()
  def run(migration_module, opts \\ []) do
    config = apply_config(migration_module, opts)
    config = %{config | repo: migration_repo(config.repo)}

    if config.async do
      Task.start(fn ->
        throttle_change_in_batches(migration_module, config, config.first_id, opts)
      end)

      :ok

    else
        throttle_change_in_batches(migration_module, config, config.first_id, opts)
    end
  end

  # Use the repo from Ecto's migration runner when available (so data migrations
  # run against the correct repo, e.g. TestInstanceRepo), falling back to config.
  defp migration_repo(fallback_repo) do
    case ProcessTree.get(:ecto_migration) do
      %{runner: _} -> 
        repo = Ecto.Migration.Runner.repo()
        IO.puts("DataMigration: Using repo from Ecto.Migration.Runner: #{inspect(repo)}")
        repo
      _ -> 
        IO.puts("Warning: DataMigration is running outside of Ecto's migration runner; using repo from Ecto config. This may not be the correct repo in some contexts, e.g. when running tests with multiple repos.")
        fallback_repo
    end
  end


  defp throttle_change_in_batches(migration_module, config, last_id, opts, batch_i \\ 1)
  defp throttle_change_in_batches(_migration_module, _, nil, _opts, _i), do: :ok
  defp throttle_change_in_batches(migration_module, config, last_id, opts, batch_i) do

    query =
      apply_base_query(migration_module, opts)
      |> where([i], i.id > ^last_id)
      |> order_by([i], asc: i.id)
      |> limit(^config.batch_size)

    case config.repo.all(query, log: :info, timeout: :infinity) do
      [] ->
        IO.puts("DataMigration: Done")
        # Occurs when no more elements match the query; the migration is done!
        :ok

      query_results ->

        IO.puts("DataMigration: Start batch #{batch_i} - above ID #{last_id}")

        apply_migrate(migration_module, query_results, opts)
        Process.sleep(config.throttle_ms)

        last_processed_id = List.last(query_results).id
        throttle_change_in_batches(migration_module, config, last_processed_id, opts, batch_i + 1)
    end
  end

  # `config/0` | `config/1`, `base_query/0` | `base_query/1`, `migrate/1` | `migrate/2` — call the
  # opts-aware arity when the migration defines it, otherwise fall back to the plain one.
  defp apply_config(module, opts) do
    if function_exported?(module, :config, 1), do: module.config(opts), else: module.config()
  end

  defp apply_base_query(module, opts) do
    if function_exported?(module, :base_query, 1),
      do: module.base_query(opts),
      else: module.base_query()
  end

  defp apply_migrate(module, results, opts) do
    if function_exported?(module, :migrate, 2),
      do: module.migrate(results, opts),
      else: module.migrate(results)
  end
end
