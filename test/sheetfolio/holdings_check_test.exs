defmodule Sheetfolio.HoldingsCheckTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.HoldingsCheck

  defp op(fecha, isin, tipo, cantidad) do
    %{
      fecha: fecha, asset: "ASSET #{isin}", isin: isin, tipo: tipo, cantidad: cantidad,
      precio: "1 EUR", importe_with_comision: "#{cantidad} EUR", traspaso: false
    }
  end

  defp sheet(isin, units) do
    [["Fecha", "Fund"], ["ISIN", isin], ["08/03/2026", units]]
  end

  test "units bought after the sheet's date aren't a difference" do
    ops = [op("01/02/2026", "IE1", "Compra", "100"), op("01/04/2026", "IE1", "Compra", "50")]

    assert %{as_of: "08/03/2026", differences: []} = HoldingsCheck.check(sheet("IE1", "100"), ops)
  end

  test "reads the sheet's units in Spanish format" do
    ops = [op("01/02/2026", "IE1", "Compra", "1844.4")]

    assert %{differences: []} = HoldingsCheck.check(sheet("IE1", "1.844"), ops)
  end

  test "reports a difference of a whole unit or more" do
    ops = [op("01/02/2026", "IE1", "Compra", "90")]

    assert %{differences: [%{name: "Fund", isin: "IE1", sheet: 100.0, replay: 90.0}]} =
             HoldingsCheck.check(sheet("IE1", "100"), ops)
  end

  test "units in the sheet with no operations at all are a difference" do
    assert %{differences: [%{replay: +0.0}]} = HoldingsCheck.check(sheet("IE1", "100"), [])
  end

  test "follows the sheet's aliases to the emails' identifier" do
    ops = [op("01/02/2026", "CA50077N1024", "Compra", "220")]

    assert %{differences: []} = HoldingsCheck.check(sheet("PNG.V", "220"), ops)
  end

  test "skips columns without an identifier or a number" do
    rows = [["Fecha", "Urbanitae", "Fund"], ["ISIN", "", "IE1"], ["08/03/2026", "12", "-"]]

    assert %{differences: []} = HoldingsCheck.check(rows, [])
  end

  test "units below zero are flagged, wherever the sheet is" do
    ops = [op("01/02/2026", "IE1", "Reembolso", "5")]

    assert %{negative: [%{isin: "IE1", units: -5.0}]} = HoldingsCheck.check(sheet("IE2", "0"), ops)
  end

  test "a known gap stays quiet until its shortfall changes" do
    gap = op("07/12/2023", "IE00B04GQR24", "Reembolso", "55.48")
    worse = op("08/12/2023", "IE00B04GQR24", "Reembolso", "1")

    assert %{negative: []} = HoldingsCheck.check(sheet("IE2", "0"), [gap])
    assert %{negative: [_]} = HoldingsCheck.check(sheet("IE2", "0"), [gap, worse])
  end

  test "summary/1 is nil when everything agrees" do
    assert HoldingsCheck.summary(%{as_of: "08/03/2026", differences: [], negative: []}) == nil
  end

  test "summary/1 names what differs" do
    result = %{
      as_of: "08/03/2026",
      differences: [%{name: "Quanterix", isin: "US1", sheet: 1386.0, replay: 1188.0}],
      negative: [%{asset: "VANGUARD", isin: "IE1", units: -5.0}]
    }

    assert HoldingsCheck.summary(result) ==
             "As of 08/03/2026: Quanterix sheet 1386.0 vs 1188.0; VANGUARD at -5.0 units"
  end
end
