defmodule Sheetfolio.BitcoinExposureTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.BitcoinExposure

  @etp "GB00BJYDH287"

  defp snapshot(date, positions), do: %{"date" => date, "positions" => positions}
  defp etp(value), do: %{"isin" => @etp, "asset" => "WISDOMTREE BITCOIN", "value" => value}

  describe "series/4" do
    test "values the coins at each day's price and reads the ETP from the snapshot" do
      snapshots = [
        snapshot("2025-01-02", [etp(1000.0)]),
        snapshot("2025-01-01", [etp(900.0)])
      ]

      prices = %{~D[2025-01-01] => 50_000.0, ~D[2025-01-02] => 60_000.0}

      assert [first, second] = BitcoinExposure.series(snapshots, prices, 0.02, @etp)

      assert first == %{date: "2025-01-01", etp: 900.0, coinbase: 1000.0}
      assert second == %{date: "2025-01-02", etp: 1000.0, coinbase: 1200.0}
    end

    test "a snapshot without the ETP contributes only the coins" do
      snapshots = [snapshot("2025-01-01", [%{"isin" => "OTHER", "value" => 500.0}])]

      assert [%{etp: +0.0, coinbase: 1000.0}] =
               BitcoinExposure.series(snapshots, %{~D[2025-01-01] => 50_000.0}, 0.02, @etp)
    end

    test "falls back to a recent earlier price when the day itself has none" do
      snapshots = [snapshot("2025-01-03", [etp(0.0)])]

      assert [%{coinbase: 1000.0}] =
               BitcoinExposure.series(snapshots, %{~D[2025-01-01] => 50_000.0}, 0.02, @etp)
    end

    test "drops a day whose price is too old to stand in, rather than charting a zero" do
      snapshots = [snapshot("2025-02-01", [etp(500.0)])]

      assert BitcoinExposure.series(snapshots, %{~D[2025-01-01] => 50_000.0}, 0.02, @etp) == []
    end

    test "an ETP position with no recorded value counts as zero, not a crash" do
      snapshots = [snapshot("2025-01-01", [%{"isin" => @etp, "value" => nil}])]

      assert [%{etp: +0.0}] =
               BitcoinExposure.series(snapshots, %{~D[2025-01-01] => 50_000.0}, 0.02, @etp)
    end
  end

end
