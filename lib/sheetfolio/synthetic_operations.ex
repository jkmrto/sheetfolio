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
    },
    # The weekly Fidelity subscriptions whose emails never arrived. Gmail jumps
    # 17/11 -> 04/12 and 12/12 -> 31/12/2025, the same two holes that swallowed
    # the Bitcoin and pension emails; four weekly buys are missing from them.
    #
    # The total is exact rather than guessed: MyInvestor reports 2298.724 units
    # for 33233.76 EUR against the 2228.177 for 32233.49 the emails account for.
    # Four 250 EUR buys at the NAVs of those weeks come to 69.913 units, which
    # is the shape of it but not to the cent, so the gap is recorded as one
    # operation carrying the exact difference instead of four invented ones.
    # Dated in the first hole; the individual dates are not recoverable.
    %{
      fecha: "01/12/2025",
      asset: "S&P 500 INDEX P ACC EUR",
      isin: "IE00BYX5MX67",
      tipo: "Suscripcion",
      cantidad: "70.547",
      precio: "14.1788 EUR",
      importe_without_comision: "1000.27 EUR",
      comision: "",
      importe_with_comision: "1000.27 EUR",
      traspaso: false
    },
    # The fourth pension contribution. Gmail holds three (05/11/2024,
    # 18/09/2025, 16/10/2025) totalling 158.615 units for 2497.00 €, while
    # MyInvestor reports 187.889 units for 2997.00 €. The 29.274-unit,
    # 500.00 € difference is exact, and the price it implies
    # (500/29.274 = 17.0800) matches the plan's NAV of 17.0798 on 25/11/2025 —
    # the only day in its history within a cent. Contributions settle at the
    # prior day's NAV, so the operation is dated the 26th. It falls inside the
    # 14/11–03/12/2025 hole where other emails are missing too, and it brings
    # 2025 to 1500.00 €, the annual contribution limit.
    %{
      fecha: "26/11/2025",
      asset: "MYINVESTOR INDEXADO GLOBAL PP",
      isin: "N5396",
      tipo: "Suscripcion",
      cantidad: "29.274",
      precio: "17.080 EUR",
      importe_without_comision: "500.00 EUR",
      comision: "",
      importe_with_comision: "500.00 EUR",
      traspaso: false
    }
  ]

  def all, do: @ops
end
