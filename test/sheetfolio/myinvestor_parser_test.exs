defmodule Sheetfolio.MyinvestorParserTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.MyinvestorParser

  # Trimmed to the fragments the parser actually matches on, in the order and
  # markup the real "APORTACION A PLANES DE PENSIONES" emails use: a DGS code
  # where fund emails carry an ISIN, and no "Importe Efectivo Neto" block
  # because a contribution carries no fees.
  @pension_subject "** MYINVESTOR **APORTACION A PLANES DE PENSIONES : XXXXXX0388 # 05/11/2024 # APORTACION P.P. # MYINVESTOR INDEXADO GLOBAL PP # TIT: 98.508 # PRE: 15.20 # 1497.00 EUR"

  @pension_html """
  <td valign="top">APORTACION A PLAN DE PENSIONES</td>
  <td>MYINVESTOR INDEXADO GLOBAL PP<br>C&oacute;digo DGS: N5396</td>
  <td style="font-size:11px;" align="left" valign="top">05/11/2024</td>
  <td style="font-size:11px;" align="left" valign="top">98.508</td>
  <td style="font-size:11px;" align="left" valign="top">15.196&nbsp;EUR</td>
  <td style="font-size:11px;" align="left" valign="top">1,497.00&nbsp;EUR</td>
  <td><strong>Comisiones</strong></td>
  <td style="font-size:11px;" valign="top">0.00&nbsp;EUR</td>
  """

  describe "parse/2 on a pension contribution" do
    test "identifies the plan by its DGS code, since it has no ISIN" do
      assert {:ok, op} = MyinvestorParser.parse(@pension_html, @pension_subject)
      assert op.isin == "N5396"
    end

    test "reports the contribution as a subscription, so it replays as a buy" do
      assert {:ok, op} = MyinvestorParser.parse(@pension_html, @pension_subject)

      assert op.tipo == "Suscripcion"
      assert Sheetfolio.Positions.buy?(op.tipo)
    end

    test "takes the gross amount as the cost when there is no net-amount block" do
      assert {:ok, op} = MyinvestorParser.parse(@pension_html, @pension_subject)

      assert op.importe_without_comision == "1,497.00 EUR"
      assert op.importe_with_comision == "1,497.00 EUR"
    end

    test "carries the units, price and date through" do
      assert {:ok, op} = MyinvestorParser.parse(@pension_html, @pension_subject)

      assert op.fecha == "05/11/2024"
      assert op.cantidad == "98.508"
      assert op.precio == "15.196 EUR"
      assert op.asset == "MYINVESTOR INDEXADO GLOBAL PP"
      refute op.traspaso
    end

    test "an email with neither an ISIN nor a DGS code is still an error" do
      html = String.replace(@pension_html, "C&oacute;digo DGS: N5396", "")

      assert {:error, "Could not extract ISIN"} = MyinvestorParser.parse(html, @pension_subject)
    end
  end
end
