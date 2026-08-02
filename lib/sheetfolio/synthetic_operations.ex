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

  # Held at Trading212, so MyInvestor never emailed any of it and the Gmail
  # pipeline could never have seen it. Eleven positions across two liquidation
  # days — 15/01/2024, 20/09/2024 and 02/01/2026 — carrying 3593.69 EUR of
  # realized P&L that was going uncounted.
  #
  # ISINs, share counts and proceeds are Trading212's own, from its exports
  # running 2022-08 onwards. Those start after most of the purchases, so a cost
  # basis is only quoted directly where an export holds the buys. Everywhere
  # else it is proceeds minus the `Result` column, Trading212's own realized
  # figure, which reproduces its accounting exactly instead of guessing at an
  # entry price. Two positions later turned up with their buys on record and
  # confirmed the derivation to the cent — the EUR-hedged gold ETC (four lots
  # on 20/09/2024 totalling 2510.55) and the inverse ETF (two lots on
  # 28/11/2022 totalling 2250.00) — which is the check that the method is
  # sound. Small recurring top-ups and dividends on several holdings already
  # sit inside the derived bases, so they are not repeated as operations.
  #
  # Purchase dates come from those exports where available and otherwise from
  # the spreadsheet's "Registro de Operaciones". Every date here is now a real
  # one. Where an asset was bought repeatedly the whole basis sits on the first
  # of those dates rather than being split across them, since only the total
  # moves a closed position: the five sold on 15/01/2024 were each accumulated
  # over several buys in 2020-2021, and the property ETF in particular was
  # mostly sold off before the lot recorded here.
  #
  # Not recorded at all: the 2020-2021 export holds 89 further sales across
  # some thirty instruments, together worth 252.49 EUR. Thirty more closed
  # positions to carry a rounding error's worth of P&L is a bad trade, so that
  # window stays out.
  #
  # The silver ETC shares DE000A1E0HS6 with an open MyInvestor holding, and
  # keeps that holding's name so the position is not renamed underneath it. The
  # Trading212 lot is bought and sold in January 2024, well before MyInvestor
  # bought in December 2025, so the two never blend.
  #
  # Not included, for the opposite reason: a 0.13-share VanEck Gold Miners lot
  # sold 02/01/2026 for a 1.18 EUR gain. Trading212 bought it on 08/10/2025,
  # the very day MyInvestor bought its 134 units of the same IE00BQQP9F84, so
  # the two would blend and the sale would realize against a merged average
  # cost rather than its own.
  @doc """
  The ISINs held at Trading212, so pages can mark where an operation happened.

  Note DE000A1E0HS6 is in here and also held at MyInvestor: only its *realized*
  events came from Trading212, the open units are MyInvestor's.
  """
  def trading212_isins, do: trading212_positions() |> MapSet.new(&elem(&1, 0))

  defp trading212, do: Enum.flat_map(trading212_positions(), &asset_operations/1)

  defp trading212_positions do
    [
      {"IE0009JOT9U1", "ISHARES PHYSICAL GOLD EUR HEDGED", "20/09/2024", "2510.55", "02/01/2026",
       [{"52.0", "4031.30"}, {"0.617631", "47.88"}]},
      {"US02079K3059", "ALPHABET INC CLASS A", "16/06/2021", "1006.30", "02/01/2026",
       [{"9.899507", "2701.94"}]},
      {"US30303M1027", "META PLATFORMS INC", "16/06/2021", "1007.34", "02/01/2026",
       [{"3.32629336", "1876.08"}, {"0.25346378", "141.72"}]},
      {"IE00BMC38736", "VANECK SEMICONDUCTOR ETF", "08/02/2021", "462.55", "02/01/2026",
       [{"25.0", "1344.79"}]},
      {"US01609W1027", "ALIBABA GROUP HOLDING ADR", "20/04/2021", "1494.88", "02/01/2026",
       [{"9.5382478", "1242.63"}]},
      {"LU0411078636", "XTRACKERS S&P 500 2X INVERSE DAILY", "28/11/2022", "2250.00",
       "20/09/2024", [{"2968.4", "700.84"}, {"2006.1741", "473.86"}]},
      {"IE00B4ND3602", "ISHARES PHYSICAL GOLD ETC", "23/02/2021", "306.70", "15/01/2024",
       [{"10.537627", "383.69"}]},
      {"IE00B4556L06", "ISHARES PHYSICAL PALLADIUM", "23/02/2021", "456.75", "15/01/2024",
       [{"8.03680342", "205.17"}]},
      {"DE000A1E0HS6", "ETF DB PHYSICAL SILVER EUR", "23/02/2021", "457.06", "15/01/2024",
       [{"2.0780307", "415.40"}]},
      {"IE00B1TXLS18", "ISHARES UK PROPERTY", "23/02/2021", "150.87", "15/01/2024",
       [{"23.929324", "129.55"}]},
      {"IE00B1FZS350", "ISHARES DEVELOPED MARKETS PROPERTY", "16/11/2020", "148.34", "15/01/2024",
       [{"7.13031845", "150.18"}]}
    ]
  end

  defp asset_operations({isin, asset, bought_on, cost, sold_on, sales}) do
    units = sales |> Enum.map(fn {qty, _total} -> String.to_float(qty) end) |> Enum.sum()

    [operation(isin, asset, "Compra", bought_on, units, cost)] ++
      Enum.map(sales, fn {qty, total} ->
        operation(isin, asset, "Venta", sold_on, String.to_float(qty), total)
      end)
  end

  defp operation(isin, asset, tipo, fecha, units, amount) do
    unit_price = amount |> String.to_float() |> Kernel./(units)

    %{
      fecha: fecha,
      asset: asset,
      isin: isin,
      tipo: tipo,
      cantidad: :erlang.float_to_binary(units, decimals: 8),
      precio: "#{:erlang.float_to_binary(unit_price, decimals: 4)} EUR",
      importe_without_comision: "#{amount} EUR",
      comision: "",
      importe_with_comision: "#{amount} EUR",
      traspaso: false
    }
  end

  def all, do: @ops ++ trading212()
end
