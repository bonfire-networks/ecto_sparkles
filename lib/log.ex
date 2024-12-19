# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.Log do
  use Untangle

  @moduledoc """
  Log Ecto queries, and output warnings for slow or possible n+1 queries

  To set up, simply add `EctoSparkles.Log.setup(YourApp.Repo)` in your app's main `Application.start/2` module.
  """

  @exclude_sources ["oban_jobs", "oban_peers"]
  @exclude_queries ["commit", "begin"]
  @exclude_match ["oban_jobs", "oban_peers", "oban_insert", "pg_notify", "pg_try_advisory_xact_lock", "schema_migrations"]

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
        _config
      )
      when (is_nil(source) or source not in @exclude_sources) and
             query not in @exclude_queries do
    do_handle_event(measurements, metadata)
  end

  def handle_event(_, _measurements, _metadata, _config) do
    # IO.inspect(metadata, label: "EctoSparkles: ignoring ecto log")
    nil
  end

  defp do_handle_event(
         %{query_time: query_time, decode_time: decode_time} = measurements,
         metadata
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
         metadata
       ) do
    check_if_slow(
      System.convert_time_unit(query_time, :native, :millisecond),
      measurements,
      metadata
    )
  end

  defp do_handle_event(_measurements, metadata) do
    {result, _} = metadata.result
    log_query(result, nil, metadata)
  end

  defp check_if_slow(duration_in_ms, _measurements, metadata)
      when duration_in_ms > 10 do
    slow_definition_in_ms = Application.get_env(:ecto_sparkles, :slow_query_ms, 100) 

    {result, _} = metadata.result

    if duration_in_ms > slow_definition_in_ms do
      Logger.warning(
        "Slow database query: " <>
          format_log(result, duration_in_ms, metadata)
      )
    else
      log_query(result, duration_in_ms, metadata)
    end
  end

  defp check_if_slow(duration_in_ms, measurements, metadata) do
    {result_key, _} = metadata.result
    log_query(result_key, duration_in_ms, metadata)
  end

  def log_query(result_key, duration_in_ms, metadata)
      when result_key in [:error, "error"] do
    if not String.contains?(metadata.query, @exclude_match),
      do:
        Logger.error(
          "SQL query: " <>
            format_log(result_key, duration_in_ms, metadata)
        )
  end

  def log_query(result_key, duration_in_ms, metadata) do
    level = Application.get_env(:ecto_sparkles, :queries_log_level, :debug)

    if level && not String.contains?(metadata.query, @exclude_match) do
      count_n_plus_1 = check_if_n_plus_1(metadata.query)

      cond do
        is_integer(count_n_plus_1) ->
          Logger.warning(
            "---------> Possible n+1 query detected! Number of occurrences: #{count_n_plus_1} SQL query: " <>
              format_log(result_key, duration_in_ms, metadata)
          )

        not is_nil(level) ->
         Logger.log(
          level,
          "SQL query: " <>
            format_log(result_key, duration_in_ms, metadata)
          )

        true -> # skip
          nil
      end
    end
  end

  def check_if_n_plus_1(query) do
    case EctoSparkles.NPlus1Detector.check(query) do
      {:match, count} ->
          count
      _ -> # no match
        nil
    end
  end

  def format_log(result_key, duration_in_ms, metadata) do
    params = metadata.params 
    |> Enum.map(&prepare_value/1)
    #|> inspect(charlists: false)

    # Strip out unnecessary quotes from the query for readability
    # Regex.replace(~r/(\d\.)"([^"]+)"/, metadata.query, "\\1\\2")

    source = if metadata.source, do: "source=#{inspect(metadata.source)}"

    # \n  params=#{params}
    "#{result_key} db=#{duration_in_ms}ms #{source} repo=#{metadata.repo}\n  #{inline_params(metadata.query, params, metadata[:repo].__adapter__())} \n#{format_stacktrace_sliced(metadata[:stacktrace])}"
  end

  def inline_params(query, params, repo_adapter \\ Ecto.Adapters.SQL) do
    query
    |> Ecto.DevLogger.inline_params(params, sql_color(query), repo_adapter)
  end

  defp prepare_value(value) when is_list(value) do
    Enum.map(value, &prepare_value/1)
  end
  defp prepare_value("-----BEGIN RSA PRIVATE KEY"<>_), do: "***"
  defp prepare_value("$pbkdf2"<>_), do: "***"
  defp prepare_value("$argon2"<>_), do: "***"
  defp prepare_value(binary) when is_binary(binary) do
    with {:ok, uid} <- Code.ensure_loaded?(Needle.UID) and Needle.UID.load(binary) do
      uid
    else
      _ -> binary
    end
  end
  defp prepare_value(%Ecto.Query.Tagged{value: value}), do: prepare_value(value)
  defp prepare_value(value), do: value

  defp sql_color("SELECT" <> _), do: :cyan
  defp sql_color("ROLLBACK" <> _), do: :red
  defp sql_color("LOCK" <> _), do: :white
  defp sql_color("INSERT" <> _), do: :green
  defp sql_color("UPDATE" <> _), do: :yellow
  defp sql_color("DELETE" <> _), do: :red
  defp sql_color("begin" <> _), do: :magenta
  defp sql_color("commit" <> _), do: :magenta
  defp sql_color(_), do: :default_color
end
