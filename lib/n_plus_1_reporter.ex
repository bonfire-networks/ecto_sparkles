defmodule EctoSparkles.NPlus1Reporter do
  @moduledoc """
  Span-end reporting for `EctoSparkles.NPlus1Detector`: attaches telemetry handlers on Phoenix LiveView/router and Oban span endings that flush the per-process query counts at the end of each unit of work and log ONE consolidated warning per span for shapes repeated ≥ the threshold (`config :ecto_sparkles, :n_plus_1_threshold`, default 3).

  Attach once at application start: `EctoSparkles.NPlus1Reporter.setup()`. The handlers run IN the LiveView/request/job process, so the flush clears exactly the state that unit of work accumulated. On `:exception` spans the state is cleared WITHOUT reporting, so a crashed span can't leak counts into the next one. Near-free when detection is off (the recommended prod default): the flush is a single pdict delete-miss.
  """
  require Logger

  @handler_id "ecto-sparkles-n-plus-1-flush"

  # span sources whose end-of-unit-of-work should flush (atom lists are plain data — no
  # compile-time dependency on Phoenix or Oban)
  @span_sources [
    [:phoenix, :live_view, :mount],
    [:phoenix, :live_view, :handle_params],
    [:phoenix, :live_view, :handle_event],
    [:phoenix, :router_dispatch],
    [:oban, :job]
  ]

  @doc """
  Attach the flush/report handlers — a no-op unless `NPlus1Detector.enabled?/0` (so callers can
  invoke it unconditionally at boot or after flipping the config, and detection off means ZERO
  attached handlers). Idempotent; pass `events:` to override the span list.
  """
  def setup(opts \\ []) do
    if EctoSparkles.NPlus1Detector.enabled?() do
      :telemetry.attach_many(
        @handler_id,
        for source <- opts[:events] || @span_sources, ending <- [:stop, :exception] do
          source ++ [ending]
        end,
        &__MODULE__.flush_and_report/4,
        []
      )
    else
      detach()
      :ok
    end
  end

  def detach, do: :telemetry.detach(@handler_id)

  defp threshold, do: Application.get_env(:ecto_sparkles, :n_plus_1_threshold, 3)

  @doc false
  def flush_and_report(event, measurements, metadata, _config) do
    counts = EctoSparkles.NPlus1Detector.flush()

    with :stop <- List.last(event),
         [_ | _] = offenders <-
           Enum.filter(counts, fn {_q, count} -> count >= threshold() end) do
      duration_ms = div(EctoSparkles.Log.native_us(measurements[:duration]), 1000)

      Logger.warning(
        "Possible N+1 in #{span_label(event, metadata)} (#{duration_ms}ms) — repeated queries:\n" <>
          Enum.map_join(offenders, "\n", fn {q, count} ->
            "  #{count}× #{String.slice(q, 0, 200)}"
          end)
      )
    else
      _ -> :ok
    end
  rescue
    # never take down the span's own process for a diagnostic
    _ -> :ok
  end

  defp span_label([:phoenix, :live_view, phase, _], metadata) do
    view =
      case metadata[:socket] do
        %{view: view} -> inspect(view)
        _ -> "LiveView"
      end

    event = if e = metadata[:event], do: " #{inspect(e)}", else: ""
    "#{view} #{phase}#{event}"
  end

  defp span_label([:phoenix, :router_dispatch, _], metadata),
    do: "#{metadata[:conn] && metadata[:conn].method} #{metadata[:route] || "?"}"

  defp span_label([:oban, :job, _], metadata) do
    case metadata[:job] do
      %{worker: worker, queue: queue} -> "Oban #{worker} (#{queue})"
      _ -> "Oban job"
    end
  end

  defp span_label(event, _metadata), do: inspect(event)
end
