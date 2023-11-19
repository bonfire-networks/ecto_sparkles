defmodule EctoSparkles.DataMigration.Runner do
  @moduledoc """
  Runs a `DataMigration`
  """
  import Ecto.Query
  alias EctoSparkles.DataMigration

  @spec run(module()) :: :ok | no_return()
  def run(migration_module) do
    config = migration_module.config()

    if config.async do 
      Task.start(fn ->
        throttle_change_in_batches(migration_module, config, config.first_id)
      end)

      :ok

    else
        throttle_change_in_batches(migration_module, config, config.first_id)
    end
  end


  defp throttle_change_in_batches(migration_module, config, last_id, batch_i \\ 1)
  defp throttle_change_in_batches(_migration_module, _, nil, _), do: :ok
  defp throttle_change_in_batches(migration_module, config, last_id, batch_i) do
    
    query =
      migration_module.base_query()
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

        migration_module.migrate(query_results)
        Process.sleep(config.throttle_ms)

        last_processed_id = List.last(query_results).id
        throttle_change_in_batches(migration_module, config, last_processed_id, batch_i+1)
    end
  end
end
