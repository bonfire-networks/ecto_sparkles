defmodule EctoSparkles.NPlus1Detector do
  @moduledoc """
  Accumulates repeated SELECT shapes per Proces or unit of work (LiveView mount/params/event, HTTP request, Oban job) for N+1 detection.

  `check/1` counts query shapes in one process-dictionary entry; `flush/0` returns the counts and clears them. The host app attaches telemetry span-stop handlers that flush at the end of each unit of work and report offenders in one consolidated warning (see example implementation in `priv/sample_telemetry.ex`), so counts can never leak across user actions, and no state lingers in idle/hibernated processes.

  Local pdict only as parallel preload Tasks are not N+1 loops, so nothing is read from or written to ancestor processes.

  Disabled unless `config :ecto_sparkles, :n_plus_1_detect, true` is enabled.
  """

  @key :ecto_sparkles_n_plus_1
  # backstop for boundary-less processes (long-lived GenServers that never hit a flush point):
  # new shapes beyond the cap aren't tracked, already-tracked shapes keep counting
  @max_shapes 64

  def enabled?, do: Application.get_env(:ecto_sparkles, :n_plus_1_detect, false) == true

  @doc "Accumulate one occurrence of a query shape (SELECTs only; no-op unless enabled)."
  def check("SELECT" <> _ = query) do
    if enabled?() do
      case Process.get(@key) do
        nil ->
          Process.put(@key, %{query => 1})

        counts when is_map_key(counts, query) ->
          Process.put(@key, Map.update!(counts, query, &(&1 + 1)))

        counts when map_size(counts) < @max_shapes ->
          Process.put(@key, Map.put(counts, query, 1))

        _at_cap ->
          :ok
      end
    end

    :ok
  end

  def check(_query), do: :ok

  @doc "Returns the accumulated `%{query => count}` and clears the state (call at the end of a unit of work)."
  def flush do
    Process.delete(@key) || %{}
  end
end