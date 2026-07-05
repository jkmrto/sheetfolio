defmodule Sheetfolio.SyntheticOperations do
  # Operations missing from Gmail: either the email was never received or parsing failed.
  # Each entry must include all fields that MyinvestorParser.parse/2 returns.
  @ops [
    %{
      fecha: "28/10/2024",
      asset: "AXA Trésor Court Terme C",
      isin: "FR0000447823",
      tipo: "Reembolso",
      cantidad: "0.5849",
      precio: "2563.52 EUR",
      importe_without_comision: "1499.91 EUR",
      comision: "",
      importe_with_comision: "1499.91 EUR",
      traspaso: false
    },
    %{
      fecha: "26/11/2024",
      asset: "AXA Trésor Court Terme C",
      isin: "FR0000447823",
      tipo: "Reembolso",
      cantidad: "0.389",
      precio: "2571.95 EUR",
      importe_without_comision: "1000.19 EUR",
      comision: "",
      importe_with_comision: "1000.19 EUR",
      traspaso: true
    }
  ]

  def all, do: @ops
end
