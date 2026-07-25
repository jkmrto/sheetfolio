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

  test "a sell is covered by a buy made the same day, whatever order they arrive in" do
    # You can only sell units you already hold, and the emails don't record
    # intraday order. Replaying the sell first would call 90 of these units
    # uncovered even though that morning's buy covered them.
    [event] =
      Positions.realized_events(
        [
          op("01/02/2024", "Reembolso", "100", "2530 EUR"),
          op("01/02/2024", "Compra", "100", "2531 EUR"),
          op("01/01/2024", "Compra", "10", "250 EUR")
        ],
        1.0,
        1.0
      )

    assert event.uncovered == 0.0
  end

  test "a same-day buy and sell of the same size leaves the earlier position intact" do
    position =
      build([
        op("01/01/2024", "Compra", "10", "250 EUR"),
        op("01/02/2024", "Reembolso", "100", "2530 EUR"),
        op("01/02/2024", "Compra", "100", "2531 EUR")
      ])

    assert position.net_qty == 10.0
    # The round trip is roughly a wash, so cost basis stays near the original
    # 250 rather than absorbing the full 2531 of a buy that was undone.
    assert_in_delta position.cost_basis, 250.0, 5.0
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

  describe "history/3" do
    test "one entry per date with activity, each carrying the cumulative state" do
      history =
        Positions.history(
          [
            op("01/01/2024", "Compra", "10", "1000 EUR"),
            op("01/02/2024", "Compra", "10", "2000 EUR")
          ],
          1.0,
          1.0
        )

      assert [{"01/01/2024", first}, {"01/02/2024", second}] = history
      assert first[@isin].net_qty == 10.0
      assert first[@isin].cost_basis == 1000.0
      assert second[@isin].net_qty == 20.0
      assert second[@isin].cost_basis == 3000.0
    end

    test "entries come back oldest first regardless of input order" do
      history =
        Positions.history(
          [
            op("01/03/2024", "Compra", "1", "100 EUR"),
            op("01/01/2024", "Compra", "1", "100 EUR"),
            op("01/02/2024", "Compra", "1", "100 EUR")
          ],
          1.0,
          1.0
        )

      assert Enum.map(history, &elem(&1, 0)) == ["01/01/2024", "01/02/2024", "01/03/2024"]
    end

    test "a same-day buy immediately undone by a sell nets out in that day's state" do
      # Regression: a 100-unit buy and a 100-unit sell on the same date, plus
      # an ordinary 5-unit buy, should leave the day's net position at +5
      # units, not +105 — the sell must reduce cost basis the same way
      # build/3 already does, not get ignored because it landed same-day as
      # a buy.
      history =
        Positions.history(
          [
            op("01/01/2024", "Compra", "1000", "100000 EUR"),
            op("07/10/2025", "Compra", "5", "126.58 EUR"),
            op("07/10/2025", "Compra", "100", "2531.4 EUR"),
            op("07/10/2025", "Venta", "100", "2530.7 EUR")
          ],
          1.0,
          1.0
        )

      [_jan, {_fecha, final}] = history

      assert_in_delta final[@isin].net_qty, 1005.0, 0.001
    end

    test "the last entry matches what build/3 reports as the final state" do
      ops = [
        op("01/01/2024", "Compra", "10", "1000 EUR"),
        op("01/02/2024", "Reembolso", "4", "500 EUR")
      ]

      {_fecha, last_state} = Positions.history(ops, 1.0, 1.0) |> List.last()
      built = Positions.build(ops, 1.0, 1.0)

      assert last_state[@isin].net_qty == built[@isin].net_qty
      assert last_state[@isin].cost_basis == built[@isin].cost_basis
    end
  end
end
