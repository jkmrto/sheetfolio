defmodule Sheetfolio.EquitoParserTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.EquitoParser

  @subject "¡Juan carlos, acabas de recibir la renta de tus propiedades!"

  test "turns each property row into a RENTA and RET. FISCAL pair" do
    html = """
    <table><tr><th>Propiedad</th><th>Pago</th><th>Retenido*</th><th>Distribuido</th></tr>
    <tr><td style='text-align: center'>EQT-0010 </td><td>1.33 €</td><td>0.25 €</td><td>1.08 €</td></tr>
    <tr><td>EQT-0072</td><td>1.42 &euro;</td><td>0.26 &euro;</td><td>1.16 &euro;</td></tr>
    <tr><td><b>Total</b></td><td>2.75 €</td><td>0.51 €</td><td>2.24 €</td></tr></table>
    """

    assert {:ok, transactions} = EquitoParser.parse(@subject, html, "2026-11-01")

    assert transactions == [
             %{
               date: "2026-11-01",
               code: "EQT-0010",
               kind: "rent",
               tokens: nil,
               amount: 1.33,
               raw_label: "RENTA"
             },
             %{
               date: "2026-11-01",
               code: "EQT-0010",
               kind: "tax",
               tokens: nil,
               amount: -0.25,
               raw_label: "RET. FISCAL"
             },
             %{
               date: "2026-11-01",
               code: "EQT-0072",
               kind: "rent",
               tokens: nil,
               amount: 1.42,
               raw_label: "RENTA"
             },
             %{
               date: "2026-11-01",
               code: "EQT-0072",
               kind: "tax",
               tokens: nil,
               amount: -0.26,
               raw_label: "RET. FISCAL"
             }
           ]
  end

  test "ignores marketing mail" do
    assert EquitoParser.parse(
             "Venta de tokens: límites renovados",
             "<p>EQT-0125</p>",
             "2026-01-06"
           ) ==
             :ignore
  end

  test "errors when a rent email has no table" do
    assert {:error, _} = EquitoParser.parse(@subject, "<p>Hola</p>", "2026-11-01")
  end
end
