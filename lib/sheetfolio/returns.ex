defmodule Sheetfolio.Returns do
  @moduledoc """
  Annualized money-weighted returns (`Sheetfolio.Xirr`) for market assets, built
  from `Positions.cash_flows/3`, dividends, and what's still held today.

  Traspaso legs stay in as ordinary flows. Across the portfolio they cancel out
  within days, except for units with no recorded buy: there the incoming leg is
  what puts their value in as money invested on the transfer date, the same
  assumption `Positions` makes for their cost basis. Dropping the legs would
  leave those units in the final value with nothing paid for them.
  """

  alias Sheetfolio.Xirr

  @year_in_days 365

  @doc "`%{isin => [{date, amount}]}`, with dividends as money coming out."
  def flows_by_isin(cash_flows, dividends) do
    operations = Enum.map(cash_flows, &{&1.isin, {parse_fecha(&1.fecha), &1.amount}})
    paid = Enum.map(dividends, &{&1["isin"], {Date.from_iso8601!(&1["date"]), &1["amount"]}})

    Enum.group_by(operations ++ paid, &elem(&1, 0), &elem(&1, 1))
  end

  @doc """
  Annual return in percent. `value` is what's held today: `0.0` once sold, and
  `nil` while a held position has no price, which leaves the return blank
  rather than reading as a total loss.
  """
  def annual_pct(_flows, nil, _today), do: nil

  def annual_pct(flows, value, today) do
    case flows |> with_value(value, today) |> Xirr.rate() do
      nil -> nil
      rate -> Float.round(rate * 100, 2)
    end
  end

  @doc "The combined return of several `{flows, value}` positions. Blank until all are priced."
  def combined_pct(positions, today) do
    values = Enum.map(positions, &elem(&1, 1))

    if Enum.any?(values, &is_nil/1) do
      nil
    else
      annual_pct(Enum.flat_map(positions, &elem(&1, 0)), Enum.sum(values), today)
    end
  end

  @doc """
  Whether the money was invested for less than a year. Annualizing such a short
  period projects it onto a full year, so its figure is much less meaningful.
  """
  def under_a_year?([], _value, _today), do: false

  def under_a_year?(flows, value, today) do
    dates = flows |> with_value(value || 0.0, today) |> Enum.map(&elem(&1, 0))
    Date.diff(Enum.max(dates, Date), Enum.min(dates, Date)) < @year_in_days
  end

  defp with_value(flows, value, today) when value > 0, do: [{today, value} | flows]
  defp with_value(flows, _value, _today), do: flows

  defp parse_fecha(fecha) do
    [day, month, year] = String.split(fecha, "/")
    Date.from_iso8601!("#{year}-#{month}-#{day}")
  end
end
