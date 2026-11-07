defmodule Sheetfolio.TaxGainsTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.Positions
  alias Sheetfolio.TaxGains

  defp op(fecha, tipo, cantidad, importe, extra \\ %{}, isin \\ "IE1") do
    Map.merge(
      %{
        fecha: fecha, asset: "FUND", isin: isin, tipo: tipo, cantidad: cantidad,
        precio: "0 EUR", importe_with_comision: importe, traspaso: false
      },
      extra
    )
  end

  defp sales(ops), do: TaxGains.sales(ops, 1.0, 1.0)

  test "the oldest units are sold first, whatever the average cost is" do
    [sale] =
      sales([
        op("01/01/2023", "Compra", "10", "100 EUR"),
        op("01/01/2024", "Compra", "10", "300 EUR"),
        op("01/01/2025", "Reembolso", "10", "500 EUR")
      ])

    assert sale.cost == 100.0
    assert sale.gain == 400.0
  end

  test "a sale spanning two lots splits the second" do
    [_first, second] =
      sales([
        op("01/01/2023", "Compra", "10", "100 EUR"),
        op("01/01/2024", "Compra", "10", "300 EUR"),
        op("01/01/2025", "Reembolso", "15", "600 EUR"),
        op("01/02/2025", "Reembolso", "5", "250 EUR")
      ])

    assert_in_delta second.cost, 150.0, 1.0e-6
  end

  test "operations are replayed in settlement order, not as listed" do
    [sale] =
      sales([
        op("01/01/2025", "Reembolso", "10", "500 EUR"),
        op("01/01/2023", "Compra", "10", "100 EUR")
      ])

    assert sale.cost == 100.0
  end

  test "units beyond the recorded buys realize nothing and are reported" do
    [sale] =
      sales([
        op("01/01/2023", "Compra", "5", "50 EUR"),
        op("01/01/2025", "Reembolso", "10", "200 EUR")
      ])

    assert sale.uncovered == 5.0
    assert sale.proceeds == 100.0
    assert sale.gain == 50.0
  end

  test "a traspaso is no sale, and its lots keep their cost and date" do
    out = %{traspaso: true, traspaso_from: "IE1", traspaso_to: "IE2"}

    result =
      sales([
        op("01/01/2020", "Compra", "10", "100 EUR"),
        op("01/01/2024", "Compra", "10", "400 EUR", %{}, "IE2"),
        op("01/01/2025", "Reembolso", "10", "300 EUR", out),
        op("03/01/2025", "Suscripcion", "20", "300 EUR", out, "IE2"),
        op("01/06/2025", "Reembolso", "30", "600 EUR", %{}, "IE2")
      ])

    # The moved lot dates from 2020, so it goes before the 2024 buy.
    assert [%{fecha: "01/06/2025", isin: "IE2", cost: cost}] = result
    assert_in_delta cost, 500.0, 1.0e-6
  end

  test "a traspaso split into two incoming legs shares its cost" do
    out = %{traspaso: true, traspaso_from: "IE1", traspaso_to: "IE2"}

    [sale] =
      sales([
        op("01/01/2020", "Compra", "10", "100 EUR"),
        op("01/01/2025", "Reembolso", "10", "300 EUR", out),
        op("03/01/2025", "Suscripcion", "10", "100 EUR", out, "IE2"),
        op("04/01/2025", "Suscripcion", "20", "200 EUR", out, "IE2"),
        op("01/06/2025", "Reembolso", "30", "450 EUR", %{}, "IE2")
      ])

    assert_in_delta sale.cost, 100.0, 1.0e-6
    assert_in_delta sale.gain, 350.0, 1.0e-6
  end

  test "a traspaso whose source was never seen starts from its value" do
    out = %{traspaso: true, traspaso_from: "IE9", traspaso_to: "IE2"}

    [sale] =
      sales([
        op("03/01/2025", "Suscripcion", "10", "100 EUR", out, "IE2"),
        op("01/06/2025", "Reembolso", "10", "150 EUR", %{}, "IE2")
      ])

    assert sale.cost == 100.0
  end

  test "over a fully sold position the total matches average cost" do
    ops = [
      op("01/01/2023", "Compra", "10", "100 EUR"),
      op("01/06/2023", "Compra", "10", "300 EUR"),
      op("01/01/2024", "Reembolso", "5", "150 EUR"),
      op("01/01/2025", "Reembolso", "15", "600 EUR")
    ]

    fifo = ops |> sales() |> Enum.reduce(0.0, &(&1.gain + &2))
    average = Positions.build(ops, 1.0, 1.0)["IE1"].realized

    assert_in_delta fifo, average, 1.0e-6
  end

  test "selling different lots only moves cost between sold and held" do
    out = %{traspaso: true, traspaso_from: "IE1", traspaso_to: "IE2"}

    ops = [
      op("01/01/2023", "Compra", "10", "100 EUR"),
      op("01/06/2023", "Compra", "10", "300 EUR"),
      op("01/01/2024", "Reembolso", "4", "120 EUR", out),
      op("03/01/2024", "Suscripcion", "8", "120 EUR", out, "IE2"),
      op("01/06/2024", "Reembolso", "3", "60 EUR", %{}, "IE2"),
      op("01/01/2025", "Reembolso", "6", "180 EUR")
    ]

    gain = ops |> sales() |> Enum.reduce(0.0, &(&1.gain + &2))
    held = ops |> TaxGains.open_cost(1.0, 1.0) |> Map.values() |> Enum.sum()
    positions = ops |> Positions.build(1.0, 1.0) |> Map.values()
    average = Enum.reduce(positions, 0.0, &(&1.realized - &1.cost_basis + &2))

    assert_in_delta gain - held, average, 1.0e-6
  end

  test "by_year/3 groups sales by year, newest first" do
    years =
      TaxGains.by_year(
        [
          op("01/01/2023", "Compra", "20", "200 EUR"),
          op("01/06/2024", "Reembolso", "10", "150 EUR"),
          op("01/06/2025", "Reembolso", "10", "300 EUR")
        ],
        1.0,
        1.0
      )

    assert [%{year: "2025", gain: 200.0}, %{year: "2024", gain: 50.0}] = years
  end

  test "foreign sales convert at their own day's rate" do
    buy = %{op("01/01/2024", "Compra", "10", "0.00 USD") | precio: "110.00 USD"} |> Map.merge(%{fx_usd: 1.1, fx_cad: 1.5})
    sell = %{op("01/06/2024", "Venta", "10", "0.00 USD") | precio: "110.00 USD"} |> Map.merge(%{fx_usd: 1.375, fx_cad: 1.5})

    [sale] = TaxGains.sales([buy, sell], 9.9, 9.9)

    assert_in_delta sale.gain, -200.0, 1.0e-6
  end
end
