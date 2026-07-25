defmodule Sheetfolio.BitcoinDca do
  @moduledoc """
  Pure aggregation behind the Bitcoin DCA subtab: per-day buy rows and the
  cumulative invested/value/benchmark series behind its chart. Kept separate
  from DcaBitcoinLive so it can be tested without a LiveView, Mongo or the
  network.

  Unlike the S&P 500 DCA page, there is no base/extra split here — the
  Bitcoin buys are a steady weekly amount with no discretionary top-up, so
  this just tracks DCA performance against Bitcoin itself.
  """

  alias Sheetfolio.Money
  alias Sheetfolio.Positions

  @isin "GB00BJYDH287"

  def isin, do: @isin

  @doc """
  One row per day the ETF was bought, newest first. Sells, traspasos and
  other ISINs are excluded; two buys on the same day are merged.
  """
  def build_buys(operations, eur_usd, eur_cad) do
    operations
    |> Enum.filter(&buy?/1)
    |> Enum.group_by(& &1.fecha)
    |> Enum.map(&merge_buys(&1, eur_usd, eur_cad))
    |> Enum.sort_by(&date_sort_key(&1.fecha), :desc)
  end

  defp buy?(op) do
    op.isin == @isin and op.tipo in ["Compra", "Suscripcion"] and not op.traspaso
  end

  defp merge_buys({fecha, ops}, eur_usd, eur_cad) do
    {units, invested} =
      Enum.reduce(ops, {0.0, 0.0}, fn op, {units_acc, invested_acc} ->
        qty = Positions.parse_cantidad(op.cantidad)
        amt = Positions.amount_in_eur(op.importe_with_comision, op.precio, qty, eur_usd, eur_cad)
        {units_acc + qty, invested_acc + amt}
      end)

    %{
      fecha: fecha,
      asset: hd(ops).asset,
      units: units,
      invested: invested,
      unit_cost: unit_cost(invested, units),
      value_now: nil,
      pnl: nil,
      pnl_pct: nil
    }
  end

  defp unit_cost(_invested, units) when units == 0.0, do: 0.0
  defp unit_cost(invested, units), do: invested / units

  @doc "Fills in value_now/pnl/pnl_pct on every row from a single current EUR price."
  def price_buys(buys, price_eur) do
    Enum.map(buys, fn buy ->
      value_now = Float.round(buy.units * price_eur, 2)
      pnl = Float.round(value_now - buy.invested, 2)
      pnl_pct = pnl_pct(pnl, buy.invested)
      %{buy | value_now: value_now, pnl: pnl, pnl_pct: pnl_pct}
    end)
  end

  defp pnl_pct(_pnl, invested) when invested <= 0, do: nil
  defp pnl_pct(pnl, invested), do: Float.round(pnl / invested * 100, 2)

  @doc """
  Chart points in date order: cumulative invested, cumulative value (units
  bought so far × the ETF's EUR price on that date, from `etf_prices_usd`),
  and the raw Bitcoin benchmark price on that date (from `btc_prices_usd`).
  Both price maps are `%{Date => usd_price}`; a date missing from either
  falls back to the nearest earlier price within 4 days, since Yahoo only
  returns trading days.
  """
  def cumulative_series(buys, etf_prices_usd, btc_prices_usd, eur_usd, eur_cad) do
    buys
    |> Enum.sort_by(&date_sort_key(&1.fecha))
    |> Enum.map_reduce({0.0, 0.0}, fn buy, {cum_invested, cum_units} ->
      date = parse_date(buy.fecha)
      new_invested = cum_invested + buy.invested
      new_units = cum_units + buy.units

      point = %{
        date: iso_date(buy.fecha),
        invested: Float.round(new_invested, 2),
        value: value_at(new_units, etf_prices_usd, date, eur_usd, eur_cad),
        btc: nearest_price(btc_prices_usd, date)
      }

      {point, {new_invested, new_units}}
    end)
    |> elem(0)
  end

  defp value_at(units, prices, date, eur_usd, eur_cad) do
    case nearest_price(prices, date) do
      nil -> nil
      price_usd -> Float.round(units * Money.to_eur(price_usd, "USD", eur_usd, eur_cad), 2)
    end
  end

  @doc "The price on `date`, or the nearest earlier price within 4 days."
  def nearest_price(prices, date) do
    Enum.find_value(0..4, fn offset -> Map.get(prices, Date.add(date, -offset)) end)
  end

  defp date_sort_key(fecha) do
    case String.split(fecha, "/") do
      [d, m, y] -> {String.to_integer(y), String.to_integer(m), String.to_integer(d)}
      _ -> {0, 0, 0}
    end
  end

  defp parse_date(fecha) do
    [d, m, y] = String.split(fecha, "/")
    Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d))
  end

  defp iso_date(fecha) do
    [d, m, y] = String.split(fecha, "/")
    "#{y}-#{m}-#{d}"
  end
end
