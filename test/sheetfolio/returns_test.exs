defmodule Sheetfolio.ReturnsTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.{Positions, Returns}

  @today ~D[2026-01-01]

  defp op(fecha, tipo, isin, cantidad, importe, extra \\ %{}) do
    Map.merge(
      %{fecha: fecha, tipo: tipo, isin: isin, asset: isin, cantidad: cantidad, precio: "", importe_with_comision: importe},
      extra
    )
  end

  defp flows(ops, dividends \\ []) do
    ops |> Positions.cash_flows(1.0, 1.0) |> Returns.flows_by_isin(dividends)
  end

  describe "annual_pct/3" do
    test "a held position ends at today's value" do
      flows = flows([op("01/01/2025", "Compra", "A", "10", "100 EUR")])

      assert Returns.annual_pct(flows["A"], 110.0, @today) == 10.0
    end

    test "a sold position ends at its last sale" do
      flows = flows([op("01/01/2024", "Compra", "A", "10", "100 EUR"), op("01/01/2025", "Venta", "A", "10", "120 EUR")])

      assert_in_delta Returns.annual_pct(flows["A"], 0.0, @today), 20.0, 0.1
    end

    test "dividends count as money received" do
      ops = [op("01/01/2025", "Compra", "A", "10", "100 EUR")]
      dividends = [%{"isin" => "A", "date" => "2026-01-01", "amount" => 5.0}]

      assert Returns.annual_pct(flows(ops, dividends)["A"], 100.0, @today) == 5.0
    end

    test "stays blank while a held position has no price" do
      flows = flows([op("01/01/2025", "Compra", "A", "10", "100 EUR")])

      assert Returns.annual_pct(flows["A"], nil, @today) == nil
    end

    test "sales of units with no recorded buy aren't counted as money from nowhere" do
      flows = flows([op("01/01/2025", "Venta", "A", "10", "100 EUR")])

      assert Returns.annual_pct(flows["A"], 0.0, @today) == nil
    end

    test "half covered sale counts only the covered half" do
      ops = [op("01/01/2024", "Compra", "A", "5", "50 EUR"), op("01/01/2025", "Venta", "A", "10", "110 EUR")]

      assert_in_delta Returns.annual_pct(flows(ops)["A"], 0.0, @today), 10.0, 0.1
    end
  end

  describe "combined_pct/2" do
    test "pools money across positions" do
      flows = flows([op("01/01/2025", "Compra", "A", "1", "100 EUR"), op("01/01/2025", "Compra", "B", "1", "100 EUR")])

      assert Returns.combined_pct([{flows["A"], 130.0}, {flows["B"], 90.0}], @today) == 10.0
    end

    test "a traspaso between funds isn't a gain or a loss" do
      transfer = %{traspaso: true, traspaso_from: "A", traspaso_to: "B"}

      flows =
        flows([
          op("01/01/2025", "Compra", "A", "10", "100 EUR"),
          op("01/07/2025", "Reembolso", "A", "10", "105 EUR", transfer),
          op("01/07/2025", "Suscripcion", "B", "5", "105 EUR", transfer)
        ])

      assert Returns.combined_pct([{flows["A"], 0.0}, {flows["B"], 110.0}], @today) == 10.0
    end

    test "units transferred with no recorded buy count as invested on that date" do
      transfer = %{traspaso: true, traspaso_from: "A", traspaso_to: "B"}

      flows =
        flows([
          op("01/01/2025", "Reembolso", "A", "10", "100 EUR", transfer),
          op("01/01/2025", "Suscripcion", "B", "5", "100 EUR", transfer)
        ])

      assert Returns.combined_pct([{flows["A"], 0.0}, {flows["B"], 110.0}], @today) == 10.0
    end

    test "stays blank until every held position has a price" do
      flows = flows([op("01/01/2025", "Compra", "A", "1", "100 EUR")])

      assert Returns.combined_pct([{flows["A"], 110.0}, {flows["A"], nil}], @today) == nil
    end
  end

  describe "under_a_year?/3" do
    test "looks at a held position up to today" do
      flows = flows([op("01/06/2025", "Compra", "A", "1", "100 EUR")])

      assert Returns.under_a_year?(flows["A"], 110.0, @today)
      refute Returns.under_a_year?(flows["A"], 110.0, ~D[2026-07-01])
    end

    test "looks at a sold position up to its last flow" do
      flows = flows([op("01/01/2020", "Compra", "A", "1", "100 EUR"), op("01/03/2020", "Venta", "A", "1", "110 EUR")])

      assert Returns.under_a_year?(flows["A"], 0.0, @today)
    end
  end
end
