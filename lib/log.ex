# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.Log do
  require Logger
  @moduledoc """
  Log slow Ecto queries
  """

  @exclude_sources ["oban_jobs"]
  @exclude_queries ["commit", "begin"]
  @exclude_match ["oban_jobs", "pg_try_advisory_xact_lock"]

  def setup(repo_module) do
    config = repo_module.config()
    prefix = config[:telemetry_prefix]
    query_event = prefix ++ [:query] # <- Telemetry event id for Ecto queries
    # events = [
    #   query_event,
    #   prefix ++ [:insert],
    #   prefix ++ [:update],
    #   prefix ++ [:delete]
    # ]

    # :telemetry.attach_many("ectosparkles-log", events, &EctoSparkles.Log.handle_event/4, [])
    :telemetry.attach("ectosparkles-log", query_event, &EctoSparkles.Log.handle_event/4, [])
  end

  def handle_event(_, measurements, %{query: query, source: source} = metadata, config) when ( is_nil(source) or source not in @exclude_sources ) and query not in @exclude_queries do
    maybe_handle_event(measurements, metadata)
  end
  def handle_event(_, measurements, metadata, config) do
    # IO.inspect(metadata, label: "EctoSparkles: unhandled ecto log")
    nil
  end

  defp maybe_handle_event(%{query_time: query_time, decode_time: decode_time} = measurements, %{query: query, source: source} = metadata) do
    maybe_trace(System.convert_time_unit(query_time, :native, :millisecond)+System.convert_time_unit(decode_time, :native, :millisecond), measurements, metadata)
  end

  defp maybe_handle_event(%{query_time: query_time} = measurements, %{query: query, source: source} = metadata) do
    maybe_trace(System.convert_time_unit(query_time, :native, :millisecond), measurements, metadata)
  end

  defp maybe_handle_event(measurements, metadata) do
    log_query(nil, measurements, metadata)
  end

  def maybe_trace(duration_in_ms, measurements,  %{query: query} = metadata) when duration_in_ms > 10 do

    slow_definition_in_ms = Bonfire.Common.Config.get([Bonfire.Common.Repo, :slow_query_ms], 100)

    if (duration_in_ms > slow_definition_in_ms) do
      Logger.warn("Slow database query: "<>format_log(duration_in_ms, measurements, metadata))
    else
      log_query(duration_in_ms, measurements, metadata)
    end

  end

  def maybe_trace(duration_in_ms, measurements, metadata) do
    log_query(duration_in_ms, measurements, metadata)
  end

  def log_query(duration_in_ms, measurements, metadata) do
    level = String.to_atom(System.get_env("DB_QUERIES_LOG_LEVEL", "debug"))
    if level && not String.contains?(metadata.query, @exclude_match), do: Logger.log(level, "SQL query: "<>format_log(duration_in_ms, measurements, metadata))
  end

  def format_log(duration_in_ms, measurements, metadata) do
    # debug(metadata)
    {ok, _} = metadata.result
    # Strip out unnecessary quotes from the query for readability
    query = Regex.replace(~r/(\d\.)"([^"]+)"/, metadata.query, "\\1\\2")
    params = metadata.params |> Enum.map(&decode_value/1) |> inspect(charlists: false)
    source = if metadata.source, do: "source=#{inspect(metadata.source)}"

    "#{ok} db=#{duration_in_ms}ms #{source}\n  #{query} \n  params=#{params}"
  end

  defp decode_value(value) when is_list(value) do
    Enum.map(value, &decode_value/1)
  end

  defp decode_value(binary) when is_binary(binary) do
    with {:ok, ulid} <- Pointers.ULID.load(binary) do
      ulid
    else
      _ -> binary
    end
  end

  defp decode_value(%Ecto.Query.Tagged{value: value}), do: decode_value(value)

  defp decode_value(value), do: value

end
