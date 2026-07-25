defmodule Sheetfolio.SnapshotRecorderTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.SnapshotRecorder

  describe "position_value/3" do
    test "uses today's price when there is one" do
      assert {50.0, false} = SnapshotRecorder.position_value(10.0, 5.0, 4.0)
    end

    test "falls back to the previous snapshot's price and flags it" do
      assert {40.0, true} = SnapshotRecorder.position_value(10.0, nil, 4.0)
    end

    test "records nothing when there is no price and no history" do
      assert {nil, false} = SnapshotRecorder.position_value(10.0, nil, nil)
    end
  end

  describe "unit_prices/1" do
    test "derives per-unit prices from a stored position list" do
      positions = [
        %{"isin" => "A", "value" => 100.0, "units" => 10.0},
        %{"isin" => "B", "value" => 250.0, "units" => 4.0}
      ]

      assert %{"A" => 10.0, "B" => 62.5} = SnapshotRecorder.unit_prices(positions)
    end

    test "skips positions that have no value or no units" do
      positions = [
        %{"isin" => "A", "value" => nil, "units" => 10.0},
        %{"isin" => "B", "value" => 100.0, "units" => 0},
        %{"isin" => "C", "value" => 100.0, "units" => nil}
      ]

      assert SnapshotRecorder.unit_prices(positions) == %{}
    end
  end
end
