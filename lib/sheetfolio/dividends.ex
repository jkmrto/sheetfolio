defmodule Sheetfolio.Dividends do
  @moduledoc """
  Cash distributions credited by MyInvestor ("ABONO DE DIVIDENDO").

  MyInvestor only emails buy/sell confirmations, never distributions, so unlike
  the operation history these can't come from Gmail. They are extracted from the
  cuenta corriente CSV export ("Movimientos Mi Cuenta"), where a distribution
  appears as a positive amount under the security's name — the same shape sale
  proceeds take, so candidate rows have to be checked against the operation
  history before being recorded.

  Each document:

      { date: "2026-07-31",
        isin: "IE00BF8HV600",
        asset: "ETF PIMCO SHORT TERM HIGH YIELD",
        amount: 71.72,        # net EUR credited, after retención
        currency: "EUR",
        raw_concepto: "ETF PIMCO SHORT TERM HIGH YIEL",
        captured_at: <DateTime> }

  Amounts are recorded net, as credited. A distribution changes neither units
  held nor cost basis, so it stays out of `Positions` and out of the daily
  snapshot: it is a third earnings component alongside realized sells and
  unrealized value.
  """

  @collection "dividends"

  def all do
    Mongo.find(:mongo, @collection, %{}, sort: %{date: -1}) |> Enum.to_list()
  end

  def insert_many([]), do: :ok

  def insert_many(docs) do
    {:ok, _} = Mongo.insert_many(:mongo, @collection, docs)
    :ok
  end

  @doc """
  Look up an existing doc with the same natural key (date + isin + amount),
  so re-ingesting an overlapping CSV export doesn't duplicate rows.
  """
  def find_matching(%{date: date, isin: isin, amount: amount}) do
    Mongo.find_one(:mongo, @collection, %{"date" => date, "isin" => isin, "amount" => amount})
  end

  @doc """
  Total distributions received, in EUR.
  """
  def total(dividends), do: dividends |> Enum.reduce(0.0, &(&1["amount"] + &2)) |> round2()

  @doc """
  One row per asset, newest payment first within each, ordered by total
  received:

      %{asset, isin, total, count, first_date, last_date, payments}
  """
  def by_asset(dividends) do
    dividends
    |> Enum.group_by(&{&1["isin"], &1["asset"]})
    |> Enum.map(fn {{isin, asset}, payments} ->
      dates = Enum.map(payments, & &1["date"])

      %{
        isin: isin,
        asset: asset,
        total: total(payments),
        count: length(payments),
        first_date: Enum.min(dates),
        last_date: Enum.max(dates),
        payments: Enum.sort_by(payments, & &1["date"], :desc)
      }
    end)
    |> Enum.sort_by(& &1.total, :desc)
  end

  @doc """
  `%{isin => total_received}`, for pages that already have positions in hand
  and just need the distribution figure alongside.
  """
  def totals_by_isin(dividends) do
    dividends
    |> Enum.group_by(& &1["isin"])
    |> Map.new(fn {isin, payments} -> {isin, total(payments)} end)
  end

  defp round2(number), do: Float.round(number * 1.0, 2)
end
