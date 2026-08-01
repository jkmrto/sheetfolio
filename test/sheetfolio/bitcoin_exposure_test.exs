defmodule Sheetfolio.BitcoinExposureTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.BitcoinExposure

  @etp "GB00BJYDH287"
  @coinbase %{units: 0.02, cost_basis: 800.0}

  defp snapshot(date, positions), do: %{"date" => date, "positions" => positions}

  defp etp(value, invested \\ 0.0) do
    %{"isin" => @etp, "asset" => "WISDOMTREE BITCOIN", "value" => value, "invested" => invested}
  end

  describe "series/4" do
    test "values the coins at each day's price and reads the ETP from the snapshot" do
      snapshots = [
        snapshot("2025-01-02", [etp(1000.0, 1200.0)]),
        snapshot("2025-01-01", [etp(900.0, 1100.0)])
      ]

      prices = %{~D[2025-01-01] => 50_000.0, ~D[2025-01-02] => 60_000.0}

      assert [first, second] = BitcoinExposure.series(snapshots, prices, @coinbase, @etp)

      assert first == %{date: "2025-01-01", etp: 900.0, coinbase: 1000.0, invested: 1900.0}
      assert second == %{date: "2025-01-02", etp: 1000.0, coinbase: 1200.0, invested: 2000.0}
    end

    test "a date before the ETP was bought carries only the coins' cost" do
      snapshots = [snapshot("2025-01-01", [%{"isin" => "OTHER", "value" => 500.0}])]

      assert [%{etp: +0.0, coinbase: 1000.0, invested: 800.0}] =
               BitcoinExposure.series(snapshots, %{~D[2025-01-01] => 50_000.0}, @coinbase, @etp)
    end

    test "falls back to a recent earlier price when the day itself has none" do
      snapshots = [snapshot("2025-01-03", [etp(0.0)])]

      assert [%{coinbase: 1000.0}] =
               BitcoinExposure.series(snapshots, %{~D[2025-01-01] => 50_000.0}, @coinbase, @etp)
    end

    test "drops a day whose price is too old to stand in, rather than charting a zero" do
      snapshots = [snapshot("2025-02-01", [etp(500.0)])]

      assert BitcoinExposure.series(snapshots, %{~D[2025-01-01] => 50_000.0}, @coinbase, @etp) ==
               []
    end

    test "an ETP position with no recorded value counts as zero, not a crash" do
      snapshots = [snapshot("2025-01-01", [%{"isin" => @etp, "value" => nil, "invested" => nil}])]

      assert [%{etp: +0.0, invested: 800.0}] =
               BitcoinExposure.series(snapshots, %{~D[2025-01-01] => 50_000.0}, @coinbase, @etp)
    end

    test "invested tracks cost basis, not market value" do
      snapshots = [snapshot("2025-01-01", [etp(5000.0, 1100.0)])]

      assert [%{invested: 1900.0, etp: 5000.0}] =
               BitcoinExposure.series(snapshots, %{~D[2025-01-01] => 50_000.0}, @coinbase, @etp)
    end
  end
end
