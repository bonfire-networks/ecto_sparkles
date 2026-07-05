defmodule EctoSparkles.LogLevelSkipTest do
  # async: false — mutates the global Logger level
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  defmodule FakeRepo do
    def __adapter__, do: Ecto.Adapters.Postgres
  end

  @metadata %{
    query: "SELECT p0.id FROM posts AS p0 WHERE p0.id = $1",
    params: [1],
    source: "posts",
    repo: FakeRepo,
    stacktrace: nil,
    result: {:ok, %{}}
  }

  setup do
    prev_level = Logger.level()
    prev_setting = Application.get_env(:ecto_sparkles, :queries_log_level, :not_set)

    on_exit(fn ->
      Logger.configure(level: prev_level)

      case prev_setting do
        :not_set -> Application.delete_env(:ecto_sparkles, :queries_log_level)
        v -> Application.put_env(:ecto_sparkles, :queries_log_level, v)
      end
    end)

    :ok
  end

  test "does no work at all when the configured level is below the runtime Logger level" do
    Application.put_env(:ecto_sparkles, :queries_log_level, :debug)
    Logger.configure(level: :warning)

    keys_before = Process.get_keys()
    EctoSparkles.Log.log_query(:ok, 5, @metadata)

    # message formatting, n+1 tracking and flood counters must ALL be skipped —
    # nothing may touch the process dictionary when the Logger would discard the line
    assert Process.get_keys() -- keys_before == []
  end

  test "still logs when the runtime level allows it" do
    Application.put_env(:ecto_sparkles, :queries_log_level, :info)
    Logger.configure(level: :debug)

    log = capture_log(fn -> EctoSparkles.Log.log_query(:ok, 5, @metadata) end)
    assert log =~ "SQL query"
  end
end
