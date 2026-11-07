defmodule Sheetfolio.MonthlyEarningsTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.MonthlyEarnings
  alias Sheetfolio.Positions

  defp op(fecha, tipo, cantidad, importe, isin \\ "IE1") do
    %{
      fecha: fecha, asset: "FUND #{isin}", isin: isin, tipo: tipo, cantidad: cantidad,
      precio: "0 EUR", importe_with_comision: importe, traspaso: false
    }
  end

  defp position(isin, units, value, invested \\ 0.0) do
    %{"isin" => isin, "asset" => "FUND #{isin}", "units" => units, "value" => value, "invested" => invested}
  end

  defp snapshot(date, positions), do: %{"date" => date, "positions" => positions}

  defp history(ops), do: Positions.history(ops, 1.0, 1.0)

  defp earned(result, key, month) do
    result.rows |> Enum.find(&(&1.key == key)) |> Map.fetch!(:months) |> Map.get(month)
  end

  test "a price move is the month's unrealized earnings" do
    ops = [op("15/12/2025", "Compra", "10", "100 EUR")]

    snapshots = [
      snapshot("2026-01-01", [position("IE1", 10.0, 100.0)]),
      snapshot("2026-01-31", [position("IE1", 10.0, 130.0)]),
      snapshot("2026-02-28", [position("IE1", 10.0, 120.0)])
    ]

    result = MonthlyEarnings.build(snapshots, history(ops), [])

    assert result.months == ["2026-01", "2026-02"]
    assert_in_delta earned(result, "IE1", "2026-01"), 30.0, 1.0e-6
    assert_in_delta earned(result, "IE1", "2026-02"), -10.0, 1.0e-6
  end

  test "selling at the last price earns nothing: it only makes the gain realized" do
    ops = [op("15/12/2025", "Compra", "10", "100 EUR"), op("10/02/2026", "Venta", "10", "130 EUR")]

    snapshots = [
      snapshot("2026-01-01", [position("IE1", 10.0, 100.0)]),
      snapshot("2026-01-31", [position("IE1", 10.0, 130.0)]),
      snapshot("2026-02-28", [])
    ]

    result = MonthlyEarnings.build(snapshots, history(ops), [])

    assert_in_delta earned(result, "IE1", "2026-01"), 30.0, 1.0e-6
    assert_in_delta earned(result, "IE1", "2026-02"), 0.0, 1.0e-6
  end

  test "buying more earns nothing by itself" do
    ops = [op("15/12/2025", "Compra", "10", "100 EUR"), op("10/02/2026", "Compra", "10", "100 EUR")]

    snapshots = [
      snapshot("2026-01-31", [position("IE1", 10.0, 100.0)]),
      snapshot("2026-02-28", [position("IE1", 20.0, 200.0)])
    ]

    assert_in_delta earned(MonthlyEarnings.build(snapshots, history(ops), []), "IE1", "2026-02"), 0.0, 1.0e-6
  end

  test "a snapshot still holding a sold position doesn't count its value" do
    ops = [op("15/12/2025", "Compra", "10", "100 EUR"), op("30/12/2025", "Venta", "10", "100 EUR")]

    snapshots = [
      snapshot("2026-01-01", [position("IE1", 10.0, 120.0)]),
      snapshot("2026-01-31", [])
    ]

    assert_in_delta earned(MonthlyEarnings.build(snapshots, history(ops), []), "IE1", "2026-01"), 0.0, 1.0e-6
  end

  test "a dividend counts in the month it arrives" do
    ops = [op("15/12/2025", "Compra", "10", "100 EUR")]
    dividend = %{"date" => "2026-02-10", "isin" => "IE1", "asset" => "FUND IE1", "amount" => 7.0}

    snapshots = [
      snapshot("2026-01-31", [position("IE1", 10.0, 100.0)]),
      snapshot("2026-02-28", [position("IE1", 10.0, 100.0)])
    ]

    assert_in_delta earned(MonthlyEarnings.build(snapshots, history(ops), [dividend]), "IE1", "2026-02"), 7.0, 1.0e-6
  end

  test "an asset with no operations uses the snapshot's own value and cost" do
    snapshots = [
      snapshot("2026-01-31", [position("COIN", 1.0, 150.0, 100.0)]),
      snapshot("2026-02-28", [position("COIN", 1.0, 120.0, 100.0)])
    ]

    assert_in_delta earned(MonthlyEarnings.build(snapshots, [], []), "COIN", "2026-02"), -30.0, 1.0e-6
  end

  test "a gap in the snapshots keeps the last price" do
    ops = [op("15/12/2025", "Compra", "10", "100 EUR")]

    snapshots = [
      snapshot("2026-01-31", [position("IE1", 10.0, 130.0)]),
      snapshot("2026-02-28", [])
    ]

    assert_in_delta earned(MonthlyEarnings.build(snapshots, history(ops), []), "IE1", "2026-02"), 0.0, 1.0e-6
  end

  test "Urbanitae's own row stays out, and its ledger counts once" do
    snapshots = [
      snapshot("2026-01-31", [position("URBANITAE", 1.0, 900.0, 800.0)]),
      snapshot("2026-02-28", [position("URBANITAE", 1.0, 950.0, 800.0)])
    ]

    earnings_at = fn date -> if date >= "2026-02-01", do: 25.0, else: 0.0 end
    result = MonthlyEarnings.build(snapshots, [], [], [{"Urbanitae", earnings_at}])

    assert Enum.map(result.rows, & &1.key) == ["Urbanitae"]
    assert_in_delta earned(result, "Urbanitae", "2026-02"), 25.0, 1.0e-6
  end

  test "the first month counts from the first snapshot" do
    ops = [op("15/12/2025", "Compra", "10", "100 EUR")]

    snapshots = [
      snapshot("2026-01-10", [position("IE1", 10.0, 110.0)]),
      snapshot("2026-01-31", [position("IE1", 10.0, 115.0)])
    ]

    assert_in_delta earned(MonthlyEarnings.build(snapshots, history(ops), []), "IE1", "2026-01"), 5.0, 1.0e-6
  end

  describe "for_year/2" do
    setup do
      ops = [op("15/11/2025", "Compra", "10", "100 EUR"), op("15/11/2025", "Compra", "10", "100 EUR", "IE2")]

      snapshots = [
        snapshot("2025-12-31", [position("IE1", 10.0, 100.0), position("IE2", 10.0, 100.0)]),
        snapshot("2026-01-31", [position("IE1", 10.0, 90.0), position("IE2", 10.0, 120.0)]),
        snapshot("2026-02-28", [position("IE1", 10.0, 85.0), position("IE2", 10.0, 125.0)])
      ]

      %{result: MonthlyEarnings.build(snapshots, history(ops), [])}
    end

    test "sorts by the year's total and sums each month", %{result: result} do
      year = MonthlyEarnings.for_year(result, "2026")

      assert Enum.map(year.rows, & &1.asset) == ["FUND IE2", "FUND IE1"]
      assert_in_delta year.total.months["2026-01"], 10.0, 1.0e-6
      assert_in_delta year.total.months["2026-02"], 0.0, 1.0e-6
      assert_in_delta year.total.total, 10.0, 1.0e-6
    end

    test "lists the years, newest first", %{result: result} do
      assert MonthlyEarnings.years(result) == ["2026", "2025"]
    end
  end

  test "no snapshots means an empty table" do
    assert MonthlyEarnings.build([], [], []) == %{months: [], rows: []}
  end
end
