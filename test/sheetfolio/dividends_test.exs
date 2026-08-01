defmodule Sheetfolio.DividendsTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.Dividends

  defp dividend(date, isin, asset, amount) do
    %{"date" => date, "isin" => isin, "asset" => asset, "amount" => amount, "currency" => "EUR"}
  end

  defp pimco(date, amount), do: dividend(date, "IE00BF8HV600", "ETF PIMCO", amount)

  describe "total/1" do
    test "sums the net amounts credited" do
      assert Dividends.total([pimco("2026-01-30", 40.77), pimco("2026-02-27", 50.80)]) == 91.57
    end

    test "is zero with nothing recorded" do
      assert Dividends.total([]) == 0.0
    end
  end

  describe "by_asset/1" do
    test "groups payments per asset, newest first, ordered by total received" do
      dividends = [
        pimco("2026-01-30", 40.77),
        dividend("2026-03-15", "IE00OTHER001", "OTHER ETF", 10.0),
        pimco("2026-02-27", 50.80)
      ]

      [first, second] = Dividends.by_asset(dividends)

      assert first.asset == "ETF PIMCO"
      assert first.total == 91.57
      assert first.count == 2
      assert first.first_date == "2026-01-30"
      assert first.last_date == "2026-02-27"
      assert Enum.map(first.payments, & &1["date"]) == ["2026-02-27", "2026-01-30"]

      assert second.asset == "OTHER ETF"
      assert second.total == 10.0
    end

    test "a single payment reports the same first and last date" do
      [row] = Dividends.by_asset([pimco("2026-07-31", 71.72)])

      assert row.first_date == row.last_date
      assert row.count == 1
    end
  end

  describe "totals_by_isin/1" do
    test "keys the received total by ISIN" do
      dividends = [
        pimco("2026-01-30", 40.77),
        pimco("2026-02-27", 50.80),
        dividend("2026-03-15", "IE00OTHER001", "OTHER ETF", 10.0)
      ]

      assert Dividends.totals_by_isin(dividends) == %{
               "IE00BF8HV600" => 91.57,
               "IE00OTHER001" => 10.0
             }
    end
  end
end
