defmodule EctoSparkles.NPlus1DetectorTest do
  # async: false — mutates :ecto_sparkles app env
  use ExUnit.Case, async: false

  alias EctoSparkles.NPlus1Detector

  setup do
    prev = Application.get_env(:ecto_sparkles, :n_plus_1_detect, :not_set)
    Application.put_env(:ecto_sparkles, :n_plus_1_detect, true)
    NPlus1Detector.flush()

    on_exit(fn ->
      case prev do
        :not_set -> Application.delete_env(:ecto_sparkles, :n_plus_1_detect)
        v -> Application.put_env(:ecto_sparkles, :n_plus_1_detect, v)
      end
    end)

    :ok
  end

  test "accumulates counts per SELECT shape; flush returns and clears them" do
    NPlus1Detector.check("SELECT a FROM b WHERE id = $1")
    NPlus1Detector.check("SELECT a FROM b WHERE id = $1")
    NPlus1Detector.check("SELECT x FROM y")
    # non-SELECTs are ignored
    NPlus1Detector.check("UPDATE b SET x = 1")

    assert %{"SELECT a FROM b WHERE id = $1" => 2, "SELECT x FROM y" => 1} ==
             NPlus1Detector.flush()

    # flushed = cleared: the next unit of work starts from zero
    assert NPlus1Detector.flush() == %{}
  end

  test "does nothing at all when disabled (prod default)" do
    Application.put_env(:ecto_sparkles, :n_plus_1_detect, false)

    keys_before = Process.get_keys()
    NPlus1Detector.check("SELECT a FROM b")

    assert Process.get_keys() -- keys_before == []
    assert NPlus1Detector.flush() == %{}
  end

  test "caps the number of tracked shapes (backstop for boundary-less processes)" do
    for i <- 1..100, do: NPlus1Detector.check("SELECT #{i}")

    counts = NPlus1Detector.flush()
    assert map_size(counts) <= 64
    # shapes already tracked keep counting even at the cap
    NPlus1Detector.check("SELECT 1")
    NPlus1Detector.check("SELECT 1")
    assert NPlus1Detector.flush()["SELECT 1"] == 2
  end
end
