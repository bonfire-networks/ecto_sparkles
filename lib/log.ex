# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.Log do
  require Logger

  @moduledoc """
  Log slow Ecto queries
  """

  @exclude_sources ["oban_jobs", "oban_peers"]
  @exclude_queries ["commit", "begin"]
  @exclude_match ["oban_jobs", "oban_peers", "oban_insert", "pg_notify", "pg_try_advisory_xact_lock"]

  def setup(repo_module) do
    config = repo_module.config()
    prefix = config[:telemetry_prefix]
    # <- Telemetry event id for Ecto queries
    query_event = prefix ++ [:query]
    # events = [
    #   query_event,
    #   prefix ++ [:insert],
    #   prefix ++ [:update],
    #   prefix ++ [:delete]
    # ]

    # :telemetry.attach_many("ectosparkles-log", events, &EctoSparkles.Log.handle_event/4, [])
    :telemetry.attach(
      "ectosparkles-log",
      query_event,
      &EctoSparkles.Log.handle_event/4,
      []
    )
  end

  def handle_event(
        _,
        measurements,
        %{query: query, source: source} = metadata,
        config
      )
      when (is_nil(source) or source not in @exclude_sources) and
             query not in @exclude_queries do
    do_handle_event(measurements, metadata)
  end

  def handle_event(_, measurements, metadata, config) do
    # IO.inspect(metadata, label: "EctoSparkles: ignoring ecto log")
    nil
  end

  defp do_handle_event(
         %{query_time: query_time, decode_time: decode_time} = measurements,
         %{query: query, source: source} = metadata
       ) do
    check_if_slow(
      System.convert_time_unit(query_time, :native, :millisecond) +
        System.convert_time_unit(decode_time, :native, :millisecond),
      measurements,
      metadata
    )
  end

  defp do_handle_event(
         %{query_time: query_time} = measurements,
         %{query: query, source: source} = metadata
       ) do
    check_if_slow(
      System.convert_time_unit(query_time, :native, :millisecond),
      measurements,
      metadata
    )
  end

  defp do_handle_event(measurements, metadata) do
    {result, _} = metadata.result
    log_query(result, nil, measurements, metadata)
  end

  defp check_if_slow(duration_in_ms, measurements, %{query: query} = metadata)
      when duration_in_ms > 10 do
    slow_definition_in_ms = Bonfire.Common.Config.get([Bonfire.Common.Repo, :slow_query_ms], 100)

    {result, _} = metadata.result

    if duration_in_ms > slow_definition_in_ms do
      Logger.warn(
        "Slow database query: " <>
          format_log(result, duration_in_ms, measurements, metadata)
      )
    else
      log_query(result, duration_in_ms, measurements, metadata)
    end
  end

  defp check_if_slow(duration_in_ms, measurements, metadata) do
    {result, _} = metadata.result
    log_query(result, duration_in_ms, measurements, metadata)
  end

  def log_query(result, duration_in_ms, measurements, metadata)
      when result in [:error, "error"] do
    if not String.contains?(metadata.query, @exclude_match),
      do:
        Logger.error(
          "SQL query: " <>
            format_log(result, duration_in_ms, measurements, metadata)
        )
  end

  def log_query(result, duration_in_ms, measurements, metadata) do
    level = String.to_atom(System.get_env("DB_QUERIES_LOG_LEVEL", "debug"))

    if level && not String.contains?(metadata.query, @exclude_match) do
      count_n_plus_1 = check_if_n_plus_1(metadata.query)

      cond do
        is_integer(count_n_plus_1) ->
          Logger.warning(
            "---------> Possible n+1 query detected! Number of occurrences: #{count_n_plus_1} SQL query: " <>
              format_log(result, duration_in_ms, measurements, metadata)
          )

        not is_nil(level) ->
         Logger.log(
          level,
          "SQL query: " <>
            format_log(result, duration_in_ms, measurements, metadata)
          )

        true -> # skip
      end
    end
  end

  def check_if_n_plus_1(query) do
    case EctoSparkles.NPlus1Detector.check(query) do
      {:match, count} ->
          count
      _ ->
        # no match
    end
  end

  def format_log(result, duration_in_ms, measurements, metadata) do
    # IO.inspect(metadata)
    # Strip out unnecessary quotes from the query for readability
    query = Regex.replace(~r/(\d\.)"([^"]+)"/, metadata.query, "\\1\\2")

    params = metadata.params |> Enum.map(&decode_value/1) |> inspect(charlists: false)

    source = if metadata.source, do: "source=#{inspect(metadata.source)}"

    # IO.inspect(metadata)
    stacktrace = case metadata[:stacktrace] do
      stacktrace when is_list(stacktrace) ->
        stacktrace
        |> Enum.slice(2, 2)
        |> Exception.format_stacktrace()
      _ -> nil
    end

    "#{result} db=#{duration_in_ms}ms #{source}\n  #{query} \n  params=#{params} \n#{stacktrace}"
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
