# SPDX-License-Identifier: Apache-2.0
defmodule EctoSparkles.LogSlow do
  require Logger
  @moduledoc """
  Log slow Ecto queries
  """

  def setup(otp_app) do
    events = [
      [otp_app, :repo, :query], # <- Telemetry event id for Ecto
    ]

    :telemetry.attach_many("#{otp_app}-instrumenter", events, &handle_event/4, nil)
  end

  def handle_event([_, :repo, :query], %{query_time: query_time, decode_time: decode_time} = measurements, %{query: query, source: source} = metadata, _config) when source not in ["oban_jobs"] and query not in ["commit", "begin"] do
    trace(System.convert_time_unit(query_time, :native, :millisecond)+System.convert_time_unit(decode_time, :native, :millisecond), measurements, metadata)
  end

  def handle_event([_, :repo, :query], %{query_time: query_time} = measurements, %{query: query, source: source} = metadata, _config) when source not in ["oban_jobs"] and query not in ["commit", "begin"] do
    trace(System.convert_time_unit(query_time, :native, :millisecond), measurements, metadata)
  end

  def handle_event(_, _measurements, _metadata, _config) do
    # IO.inspect measurements
    # IO.inspect metadata
  end


  def trace(duration_in_ms, _measurements,  %{query: query} = _metadata) when duration_in_ms > 10 do

    slow_definition_in_ms = Bonfire.Common.Config.get([Bonfire.Repo, :slow_query_ms], 100)

    if (duration_in_ms > slow_definition_in_ms) do
      Logger.warn("Slow database query: #{duration_in_ms} ms\n\s\s\s\s#{query}\n")
      # IO.inspect measurements
    else
      # Logger.debug("Query in #{duration_in_ms} ms")
    end

  end

  def trace(_, _measurements, _metadata) do
    nil
  end

end
