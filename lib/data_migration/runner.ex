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

        # NOTE: `inspect/1` (not string interpolation) because `last_id` can be a raw binary id (e.g. a
        # Needle ULID loaded as its 16-byte form), which crashes `IO.puts` with an ArgumentError when it
        # contains non-UTF-8 bytes.
        IO.puts("DataMigration: Start batch #{batch_i} - above ID #{inspect(last_id)}")

        safely_migrate(migration_module, query_results, opts, batch_i)
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

  # one batch that raises must not end the run: an async migration is marked done as it starts and never re-run, so the batches after it would stay unmigrated for good. The batch is logged, with its ids, and the run goes on to the next
  defp safely_migrate(module, results, opts, batch_i) do
    apply_migrate(module, results, opts)
  rescue
    e ->
      log_failed_batch(module, results, batch_i, Exception.format(:error, e, __STACKTRACE__))
  catch
    kind, reason ->
      log_failed_batch(module, results, batch_i, Exception.format(kind, reason, __STACKTRACE__))
  end

  defp log_failed_batch(module, results, batch_i, error) do
    require Logger

    Logger.error(
      "DataMigration #{inspect(module)}: batch #{batch_i} failed, going on with the next one. Its rows: #{inspect(Enum.map(results, &Map.get(&1, :id)))}\n#{error}"
    )
  end

  defp apply_migrate(module, results, opts) do
    if function_exported?(module, :migrate, 2),
      do: module.migrate(results, opts),
      else: module.migrate(results)
  end
end
