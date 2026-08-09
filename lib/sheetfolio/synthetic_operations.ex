defmodule Sheetfolio.SyntheticOperations do
  @moduledoc """
  Operations the Gmail pipeline can never see, held in the
  `synthetic_operations` collection rather than in this file: the repository
  shouldn't carry a record of what was bought and sold.

  Each document is one operation in the shape `MyinvestorParser.parse/2`
  returns, plus:

      { source: "gmail-gap" | "trading212",
        captured_at: <DateTime> }

  `gmail-gap` — MyInvestor operations whose confirmation email never arrived or
  failed to parse. Gmail has holes (14/11–03/12/2025 swallowed several), and a
  missing subscription silently changes both the cost basis and realized P&L.
  Where a hole hides several weekly buys, the gap is recorded as one operation
  carrying the exact difference between MyInvestor's reported units and what
  the emails account for, rather than as invented buys at guessed NAVs.

  `trading212` — a broker that never emailed MyInvestor at all, so nothing
  about it could ever reach the Gmail pipeline. Eleven positions across three
  liquidation days (15/01/2024, 20/09/2024, 02/01/2026) carrying 3593.69 EUR
  of realized P&L that was otherwise uncounted. ISINs, share counts and
  proceeds came from Trading212's own exports, which start in 2022-08 and so
  begin after most of the purchases: a cost basis is quoted directly only
  where an export holds the buys, and is otherwise proceeds minus the export's
  `Result` column, reproducing Trading212's accounting rather than guessing at
  an entry price. Two positions later turned up with their buys on record and
  confirmed that derivation to the cent. Where an asset was bought repeatedly
  the whole basis sits on the first of those dates, since only the total moves
  a closed position.

  Not recorded at all: 89 further sales across some thirty instruments in the
  2020-2021 export, together worth 252.49 EUR. Thirty closed positions to carry
  a rounding error's worth of P&L is a bad trade.

  Note DE000A1E0HS6 appears under `trading212` and is also held at MyInvestor:
  only its *realized* events came from Trading212, and that lot was bought and
  sold in January 2024, well before MyInvestor bought in December 2025, so the
  two never blend.
  """

  @collection "synthetic_operations"

  @doc """
  Every synthetic operation, in the shape the parser produces so they can be
  appended to the Gmail history.
  """
  def all do
    documents() |> Enum.map(&operation/1)
  end

  @doc """
  The ISINs held at Trading212, so pages can mark where an operation happened.
  """
  def trading212_isins do
    documents()
    |> Enum.filter(&(&1["source"] == "trading212"))
    |> MapSet.new(& &1["isin"])
  end

  defp documents do
    Mongo.find(:mongo, @collection, %{}, sort: %{isin: 1, fecha: 1})
    |> Enum.to_list()
  end

  # Spelled out rather than derived from the document's own keys: the history
  # is matched on these fields everywhere downstream, so a renamed or missing
  # one should fail here and not silently produce a half-built operation.
  defp operation(doc) do
    %{
      fecha: doc["fecha"],
      asset: doc["asset"],
      isin: doc["isin"],
      tipo: doc["tipo"],
      cantidad: doc["cantidad"],
      precio: doc["precio"],
      importe_without_comision: doc["importe_without_comision"],
      comision: doc["comision"],
      importe_with_comision: doc["importe_with_comision"],
      traspaso: doc["traspaso"]
    }
  end
end
