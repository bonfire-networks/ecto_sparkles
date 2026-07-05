# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.Log do
  use Untangle

  @moduledoc """
  Log Ecto queries, and output warnings for slow or possible n+1 queries

  To set up, simply add `EctoSparkles.Log.setup(YourApp.Repo)` in your app's main `Application.start/2` module.
  """

  @exclude_sources ["oban_jobs", "oban_peers"]
  @exclude_queries ["commit", "begin"]
  @exclude_match ["oban_jobs", "oban_peers", "oban_insert", "pg_notify", "pg_try_advisory_xact_lock", "schema_migrations", "pg_try_advisory_lock"]

  def setup(repo_module, opts \\ []) do
    if Code.ensure_loaded?(:telemetry) do
      :telemetry.attach(
        "ectosparkles-log",
        query_event(repo_module),
        &EctoSparkles.Log.handle_event/4,
        []
      )

      # no-op unless :n_plus_1_detect is enabled (see NPlus1Reporter.setup/1)
      EctoSparkles.NPlus1Reporter.setup(opts)
    else
      Logger.debug "Cannot set up telemetry for EctoSparkles"
    end
  end

  @doc """
  The telemetry event id for the repo's queries (e.g. `[:bonfire, :common, :repo, :query]`),
  derived from the repo's `:telemetry_prefix` config (falling back to Ecto's module-name default).
  The canonical helper for every consumer of the repo query event.
  """
  def query_event(repo_module), do: telemetry_prefix(repo_module) ++ [:query]

  def telemetry_prefix(repo_module) do
    repo_module.config()[:telemetry_prefix] || default_telemetry_prefix(repo_module)
  rescue
    _ -> default_telemetry_prefix(repo_module)
  end

  # Ecto's own default when no :telemetry_prefix is configured
  defp default_telemetry_prefix(repo_module) do
    repo_module
    |> Module.split()
    |> Enum.map(&(&1 |> Macro.underscore() |> String.to_atom()))
  end

  @doc "Converts a telemetry `:native` time to microseconds (nil/garbage-safe: returns 0)."
  def native_us(t) when is_integer(t), do: System.convert_time_unit(t, :native, :microsecond)
  def native_us(_), do: 0

  def handle_event(
        _,
        measurements,
        %{query: query, source: source} = metadata,
        _config
      )
      when (is_nil(source) or source not in @exclude_sources) and
             query not in @exclude_queries do
    # N+1 accumulation is independent of query LOGGING: counts flush + report once per unit of
    # work via the host app's span-stop telemetry handlers (no-op unless :n_plus_1_detect is on)
    EctoSparkles.NPlus1Detector.check(query)

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
        Untangle.log_or_flood(:error,
          "SQL query: " <>
            format_log(result_key, duration_in_ms, metadata)
        )
  end

  def log_query(result_key, duration_in_ms, metadata) do
    level = Application.get_env(:ecto_sparkles, :queries_log_level, :debug)

    # when the current Logger level would discard the line anyway (e.g. prod at :warning with this at :debug), skip ALL the work message formatting and param inlining. This runs on every query. (N+1 detection is separate: see `NPlus1Detector.check/1` in `handle_event`,
    # reported once per unit of work by the host app's span-stop handlers.)
    if level && Untangle.log_enabled?(level) &&
         not String.contains?(metadata.query, @exclude_match) do
      Untangle.log_or_flood(
        level,
        "SQL query: " <> format_log(result_key, duration_in_ms, metadata)
      )
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
