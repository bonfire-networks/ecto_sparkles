defmodule EctoSparkles.DataMigration.Config do
  use TypedStruct

  typedstruct enforce: true do
    @typedoc """
    Configuration for a `DataMigration` behaviour module, used by the `DataMigration.Runner`.
    
    batch size: how many elements from your table to migrate at a time. 
    
    throttle time: the amount of downtime the runner should sleep between batches.

    async: Whether to run the migration in an async process, meaning the execution of the rest of the migrations (and the app startup if you're auto-migrating on start) won't be delayed. WARNING: this means the migration will be marked as done as soon as it starts, so if the process is interrupted it won't be re-run automatically.

    first_id: The very first ID when sorting UUIDs in ascending order. If you use integer IDs instead, this would be 0.

    """
    field :batch_size, integer
    field :throttle_ms, integer
    field :repo, atom, default: nil
    field :async, boolean, default: false
    field :first_id, any, default: Ecto.UUID.dump!("00000000-0000-0000-0000-000000000000")
  end
end
