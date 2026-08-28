defmodule Sheetfolio.UrbanitaeParserTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.UrbanitaeParser

  describe "investment emails" do
    test "extracts city, project and amount" do
      html = """
      <p>Tu inversi&oacute;n de 5.000&euro; en el proyecto Valencia | Proyecto P&eacute;rez Gald&oacute;s se ha realizado con &eacute;xito.</p>
      <table><tr><td>Nombre del proyecto:</td><td>Valencia | Proyecto P&eacute;rez Gald&oacute;s</td></tr>
      <tr><td>Cantidad invertida:</td><td>5.000&euro;</td></tr>
      <tr><td>Porcentaje de participaci&oacute;n:</td><td>0,21%</td></tr></table>
      """

      assert {:ok, event} =
               UrbanitaeParser.parse("Tu inversión se ha realizado con éxito", html, "2024-12-18")

      assert event == %{
               kind: :investment,
               date: "2024-12-18",
               city: "Valencia",
               project: "Pérez Galdós",
               amount: 5000.00
             }
    end
  end

  describe "funding close emails" do
    test "extracts the project and the total invested" do
      html = """
      <p>Te escribimos para informarte de que el proyecto Lisboa | Proyecto Tom&aacute;s Ribeiro
      en el que has invertido 1.000&euro;, se ha financiado con &eacute;xito.</p>
      """

      assert {:ok, event} =
               UrbanitaeParser.parse("Proyecto Cerrado con éxito", html, "2026-08-21")

      assert event == %{
               kind: :funded,
               date: "2026-08-21",
               city: "Lisboa",
               project: "Tomás Ribeiro",
               amount: 1000.00
             }
    end
  end

  describe "distribution emails" do
    test "a quarterly rent payment is yield, and the body supplies the city" do
      html = """
      <h1>Proyecto P&eacute;rez Gald&oacute;s | Liquidaci&oacute;n trimestral de rentas</h1>
      <p>Nos es grato comunicarles el cuarto reparto de rentas del Proyecto Valencia | P&eacute;rez Gald&oacute;s.</p>
      """

      assert {:ok, event} = UrbanitaeParser.parse("Ingreso de inversión", html, "2026-01-28")

      assert event == %{
               kind: :distribution,
               date: "2026-01-28",
               city: "Valencia",
               project: "Pérez Galdós",
               repayment_kind: "yield"
             }
    end

    test "a project liquidation is principal, and names no city" do
      html = """
      <h1>Proyecto Golf Terraces | Liquidaci&oacute;n del proyecto</h1>
      <p>Procedemos a efectuar la liquidaci&oacute;n del Proyecto Golf Terraces.</p>
      """

      assert {:ok, event} = UrbanitaeParser.parse("Ingreso de inversión", html, "2026-07-13")

      assert event == %{
               kind: :distribution,
               date: "2026-07-13",
               city: nil,
               project: "Golf Terraces",
               repayment_kind: "principal"
             }
    end
  end

  describe "everything else" do
    test "marketing mail is ignored" do
      assert :ignore =
               UrbanitaeParser.parse(
                 "Cuenta atrás... Tomás Ribeiro",
                 "<p>Nuevo proyecto</p>",
                 "2026-08-14"
               )

      assert :ignore =
               UrbanitaeParser.parse(
                 "Devuelto proyecto Balcón del Sur |11,22% de TIR alcanzada",
                 "<p>Un caso de éxito</p>",
                 "2026-06-16"
               )
    end

    test "a known subject that doesn't parse reports an error" do
      assert {:error, reason} =
               UrbanitaeParser.parse("Proyecto Cerrado con éxito", "<p>vacío</p>", "2026-08-21")

      assert reason =~ "No funded line"
    end
  end
end
