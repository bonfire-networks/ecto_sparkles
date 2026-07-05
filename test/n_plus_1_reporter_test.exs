defmodule EctoSparkles.NPlus1ReporterTest do
  # async: false — mutates app env + globally-named telemetry handlers
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias EctoSparkles.{NPlus1Detector, NPlus1Reporter}

  @query "SELECT a FROM b WHERE id = $1"

  setup do
    prev = Application.get_env(:ecto_sparkles, :n_plus_1_detect, :not_set)
    Application.put_env(:ecto_sparkles, :n_plus_1_detect, true)
    NPlus1Reporter.setup()
    NPlus1Detector.flush()

    on_exit(fn ->
      NPlus1Reporter.detach()

      case prev do
        :not_set -> Application.delete_env(:ecto_sparkles, :n_plus_1_detect)
        v -> Application.put_env(:ecto_sparkles, :n_plus_1_detect, v)
      end
    end)

    :ok
  end

  defp lv_stop(metadata \\ %{}) do
    :telemetry.execute(
      [:phoenix, :live_view, :handle_event, :stop],
      %{duration: System.convert_time_unit(230, :millisecond, :native)},
      metadata
    )
  end

  test "flushes at span end into ONE consolidated warning with span context" do
    for _ <- 1..4, do: NPlus1Detector.check(@query)

    log =
      capture_log(fn ->
        lv_stop(%{socket: %{view: MyApp.SomeLive}, event: "validate"})
      end)

    assert log =~ "Possible N+1"
    assert log =~ "MyApp.SomeLive"
    assert log =~ "validate"
    assert log =~ "4× #{@query}"
    # one warning per span, not one per repeat
    assert length(String.split(log, "Possible N+1")) == 2
    # state cleared by the flush
    assert NPlus1Detector.flush() == %{}
  end

  test "below the threshold: silence" do
    NPlus1Detector.check(@query)
    NPlus1Detector.check(@query)

    log = capture_log(fn -> lv_stop() end)
    refute log =~ "Possible N+1"
    assert NPlus1Detector.flush() == %{}
  end

  test "exception spans clear state without reporting (no leak into the next span)" do
    for _ <- 1..5, do: NPlus1Detector.check(@query)

    log =
      capture_log(fn ->
        :telemetry.execute([:phoenix, :live_view, :handle_event, :exception], %{duration: 0}, %{})
      end)

    refute log =~ "Possible N+1"
    assert NPlus1Detector.flush() == %{}
  end

  test "setup/1 is a no-op (and detaches) when detection is disabled" do
    Application.put_env(:ecto_sparkles, :n_plus_1_detect, false)
    NPlus1Reporter.setup()

    refute Enum.any?(:telemetry.list_handlers([]), fn %{id: id} ->
             id == "ecto-sparkles-n-plus-1-flush"
           end)
  end
end
