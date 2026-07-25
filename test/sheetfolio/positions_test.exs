defmodule Sheetfolio.PositionsTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.Positions

  @isin "IE00TEST00001"

  defp op(fecha, tipo, cantidad, importe, precio \\ "0 EUR") do
    %{
      fecha: fecha,
      asset: "TEST FUND",
      isin: @isin,
      tipo: tipo,
      cantidad: cantidad,
      precio: precio,
      importe_without_comision: importe,
      comision: "",
      importe_with_comision: importe,
      traspaso: false
    }
  end

  defp build(ops), do: Positions.build(ops, 1.0, 1.0) |> Map.fetch!(@isin)

  test "a single buy sets units and cost basis from the actual EUR amount" do
    position = build([op("01/01/2024", "Compra", "10", "1000 EUR")])

    assert position.net_qty == 10.0
    assert position.cost_basis == 1000.0
    assert position.realized == 0.0
  end

  test "two buys at different prices average their cost" do
    position =
      build([
        op("01/01/2024", "Compra", "10", "1000 EUR"),
        op("01/02/2024", "Compra", "10", "2000 EUR")
      ])

    assert position.net_qty == 20.0
    assert position.cost_basis == 3000.0
  end

  test "a sell realizes the gain over the average cost of the units sold" do
    # 20 units at an average of 150 EUR; sell 10 for 2000 EUR realizes 500.
    position =
      build([
        op("01/01/2024", "Compra", "10", "1000 EUR"),
        op("01/02/2024", "Compra", "10", "2000 EUR"),
        op("01/03/2024", "Reembolso", "10", "2000 EUR")
      ])

    assert position.net_qty == 10.0
    assert position.cost_basis == 1500.0
    assert position.realized == 500.0
  end

  test "operations are replayed in date order regardless of input order" do
    ordered =
      build([
        op("01/01/2024", "Compra", "10", "1000 EUR"),
        op("01/03/2024", "Reembolso", "10", "2000 EUR"),
        op("01/02/2024", "Compra", "10", "2000 EUR")
      ])

    assert ordered.realized == 500.0
    assert ordered.cost_basis == 1500.0
  end

  test "selling more units than were ever bought realizes only the covered part" do
    [event] =
      Positions.realized_events(
        [
          op("01/01/2024", "Compra", "10", "1000 EUR"),
          op("01/02/2024", "Reembolso", "15", "3000 EUR")
        ],
        1.0,
        1.0
      )

    assert event.qty == 15.0
    assert event.uncovered == 5.0
    # 10 covered units cost 1000 and sold for 10/15 of 3000.
    assert event.cost == 1000.0
    assert_in_delta event.realized, 1000.0, 0.001
  end

  test "a sell with no recorded buys at all realizes nothing" do
    [event] =
      Positions.realized_events([op("01/02/2024", "Reembolso", "5", "500 EUR")], 1.0, 1.0)

    assert event.uncovered == 5.0
    assert event.realized == 0.0
  end

  test "buys and traspaso entries both add units" do
    for tipo <- ["Compra", "Suscripcion", "Traspaso Entrada"] do
      assert Positions.buy?(tipo)
    end

    refute Positions.buy?("Reembolso")
  end

  test "a USD price is converted at the given rate when no EUR amount is present" do
    ops = [op("01/01/2024", "Compra", "10", "n/a", "110 USD")]

    position = Positions.build(ops, 1.1, 1.0) |> Map.fetch!(@isin)

    assert_in_delta position.cost_basis, 1000.0, 0.001
  end
end
