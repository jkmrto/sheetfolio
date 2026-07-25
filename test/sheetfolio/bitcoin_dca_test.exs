defmodule Sheetfolio.BitcoinDcaTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.BitcoinDca

  @isin BitcoinDca.isin()
  @other_isin "IE00OTHER0001"

  defp op(fecha, tipo, cantidad, importe, opts \\ []) do
    %{
      fecha: fecha,
      asset: "WISDOMTREE BITCOIN",
      isin: Keyword.get(opts, :isin, @isin),
      tipo: tipo,
      cantidad: cantidad,
      precio: Keyword.get(opts, :precio, "0 EUR"),
      importe_without_comision: importe,
      comision: "",
      importe_with_comision: importe,
      traspaso: Keyword.get(opts, :traspaso, false)
    }
  end

  describe "build_buys/3" do
    test "a single buy becomes a row" do
      [row] = BitcoinDca.build_buys([op("01/01/2024", "Compra", "5", "500 EUR")], 1.0, 1.0)

      assert row.fecha == "01/01/2024"
      assert row.units == 5.0
      assert row.invested == 500.0
      assert row.unit_cost == 100.0
      assert row.value_now == nil
    end

    test "two buys on the same date merge into one row" do
      buys =
        BitcoinDca.build_buys(
          [
            op("01/01/2024", "Compra", "5", "500 EUR"),
            op("01/01/2024", "Suscripcion", "3", "300 EUR")
          ],
          1.0,
          1.0
        )

      assert [row] = buys
      assert row.units == 8.0
      assert row.invested == 800.0
    end

    test "excludes a traspaso" do
      buys = BitcoinDca.build_buys([op("01/01/2024", "Compra", "5", "500 EUR", traspaso: true)], 1.0, 1.0)

      assert buys == []
    end

    test "excludes a sell" do
      buys = BitcoinDca.build_buys([op("01/01/2024", "Reembolso", "5", "500 EUR")], 1.0, 1.0)

      assert buys == []
    end

    test "excludes operations for another ISIN" do
      buys = BitcoinDca.build_buys([op("01/01/2024", "Compra", "5", "500 EUR", isin: @other_isin)], 1.0, 1.0)

      assert buys == []
    end

    test "rows come back newest first" do
      buys =
        BitcoinDca.build_buys(
          [
            op("01/01/2024", "Compra", "1", "100 EUR"),
            op("01/03/2024", "Compra", "1", "100 EUR"),
            op("01/02/2024", "Compra", "1", "100 EUR")
          ],
          1.0,
          1.0
        )

      assert Enum.map(buys, & &1.fecha) == ["01/03/2024", "01/02/2024", "01/01/2024"]
    end
  end

  describe "price_buys/2" do
    test "fills in value_now, pnl and pnl_pct from a single current price" do
      buys = BitcoinDca.build_buys([op("01/01/2024", "Compra", "10", "1000 EUR")], 1.0, 1.0)

      [row] = BitcoinDca.price_buys(buys, 120.0)

      assert row.value_now == 1200.0
      assert row.pnl == 200.0
      assert row.pnl_pct == 20.0
    end
  end

  describe "cumulative_series/5" do
    test "cumulative invested is monotonic and value uses the ETF price on each date" do
      buys =
        BitcoinDca.build_buys(
          [
            op("01/01/2024", "Compra", "10", "1000 EUR"),
            op("03/01/2024", "Compra", "10", "1100 EUR")
          ],
          1.0,
          1.0
        )

      etf_prices = %{~D[2024-01-01] => 100.0, ~D[2024-01-03] => 115.0}
      btc_prices = %{~D[2024-01-01] => 40_000.0, ~D[2024-01-03] => 42_000.0}

      [first, second] = BitcoinDca.cumulative_series(buys, etf_prices, btc_prices, 1.0, 1.0)

      assert first.invested == 1000.0
      assert first.value == 1000.0
      assert first.btc == 40_000.0

      assert second.invested == 2100.0
      # 20 units at the 03/01 ETF price of 115.
      assert second.value == 2300.0
      assert second.btc == 42_000.0
      assert second.invested > first.invested
    end

    test "a date missing an ETF price falls back to the nearest earlier price within 4 days" do
      buys = BitcoinDca.build_buys([op("04/01/2024", "Compra", "10", "1000 EUR")], 1.0, 1.0)

      etf_prices = %{~D[2024-01-01] => 100.0}

      [point] = BitcoinDca.cumulative_series(buys, etf_prices, %{}, 1.0, 1.0)

      assert point.value == 1000.0
      assert point.btc == nil
    end

    test "a date with no price within the lookback window has no value" do
      buys = BitcoinDca.build_buys([op("10/01/2024", "Compra", "10", "1000 EUR")], 1.0, 1.0)

      [point] = BitcoinDca.cumulative_series(buys, %{~D[2024-01-01] => 100.0}, %{}, 1.0, 1.0)

      assert point.value == nil
    end
  end

  describe "nearest_price/2" do
    test "returns the exact date's price when present" do
      assert BitcoinDca.nearest_price(%{~D[2024-01-05] => 42.0}, ~D[2024-01-05]) == 42.0
    end

    test "looks back up to 4 days for the nearest earlier price" do
      assert BitcoinDca.nearest_price(%{~D[2024-01-01] => 42.0}, ~D[2024-01-04]) == 42.0
    end

    test "returns nil beyond the 4 day lookback" do
      assert BitcoinDca.nearest_price(%{~D[2024-01-01] => 42.0}, ~D[2024-01-06]) == nil
    end
  end
end
