# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.Log do
  require Logger
  @moduledoc """
  Log slow Ecto queries
  """

  def setup(otp_app) do
    events = [
      [otp_app, :repo, :query], # <- Telemetry event id for Ecto queries
    ]

    :telemetry.attach_many("#{otp_app}-instrumenter", events, &handle_event/4, nil)
  end

  def handle_event([_, :repo, :query], %{query_time: query_time, decode_time: decode_time} = measurements, %{query: query, source: source} = metadata, _config) when not is_nil(source) and source not in ["oban_jobs"] and query not in ["commit", "begin"] do
    maybe_trace(System.convert_time_unit(query_time, :native, :millisecond)+System.convert_time_unit(decode_time, :native, :millisecond), measurements, metadata)
  end

  def handle_event([_, :repo, :query], %{query_time: query_time} = measurements, %{query: query, source: source} = metadata, _config) when not is_nil(source) and source not in ["oban_jobs"] and query not in ["commit", "begin"] do
    maybe_trace(System.convert_time_unit(query_time, :native, :millisecond), measurements, metadata)
  end

  def handle_event(duration_in_ms, measurements, %{query: query, source: source} = metadata, _config) when not is_nil(source) and source not in ["oban_jobs"] and is_binary(query) and query not in ["commit", "begin"] do
    log_query(duration_in_ms, measurements, metadata)
  end

  def handle_event(_duration_in_ms, _measurements, _metadata, _config) do
    nil
  end

  def maybe_trace(duration_in_ms, measurements,  %{query: query} = metadata) when duration_in_ms > 10 do

    slow_definition_in_ms = Bonfire.Common.Config.get([Bonfire.Repo, :slow_query_ms], 100)

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
    String.to_atom(System.get_env("DB_QUERIES_LOG_LEVEL", "info"))
    |> Logger.log("SQL query: "<>format_log(duration_in_ms, measurements, metadata))
  end

  def format_log(duration_in_ms, measurements, metadata) do
    # debug(metadata)
    {ok, _} = metadata.result
    # Strip out unnecessary quotes from the query for readability
    query = Regex.replace(~r/(\d\.)"([^"]+)"/, metadata.query, "\\1\\2")
    params = metadata.params |> Enum.map(&decode_value/1) |> inspect(charlists: false)

    "#{ok} source=#{inspect(metadata.source)} db=#{duration_in_ms}ms \n  #{query} \n  params=#{params}"
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
