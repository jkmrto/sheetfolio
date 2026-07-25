defmodule Sheetfolio.Positions do
  @moduledoc """
  Aggregates operations into per-ISIN positions using average-cost basis.
  """

  alias Sheetfolio.Money

  def build(operations, eur_usd, eur_cad) do
    {assets, _events} = replay(operations, eur_usd, eur_cad)
    assets
  end

  @doc """
  One event per sell operation with the realized P&L over the covered units
  (those with a known cost basis), oldest first. Units sold beyond the
  recorded buy history are reported as uncovered and realize nothing.
  """
  def realized_events(operations, eur_usd, eur_cad) do
    {_assets, events} = replay(operations, eur_usd, eur_cad)
    Enum.reverse(events)
  end

  @doc """
  Like `build/3`, but one entry per date that had activity, oldest first,
  each carrying every ISIN's cumulative state as of that date — the same
  average-cost-basis accounting `build/3` produces as its final totals,
  checkpointed along the way instead of only at the end.

  This is what makes a same-day buy that's immediately undone by a sell net
  out correctly (a sell reduces cost_basis proportionally, same as `build/3`)
  instead of the buy permanently inflating a caller's running series.
  """
  def history(operations, eur_usd, eur_cad) do
    operations
    |> Enum.sort_by(&settlement_key/1)
    |> Enum.group_by(& &1.fecha)
    |> Enum.sort_by(fn {fecha, _ops} -> date_sort_key(fecha) end)
    |> Enum.map_reduce(%{}, fn {fecha, ops}, assets ->
      assets = Enum.reduce(ops, assets, &apply_op(&2, &1, eur_usd, eur_cad))
      {{fecha, assets}, assets}
    end)
    |> elem(0)
  end

  defp apply_op(assets, data, eur_usd, eur_cad), do: elem(update_asset(assets, data, eur_usd, eur_cad), 0)

  defp replay(operations, eur_usd, eur_cad) do
    operations
    |> Enum.sort_by(&settlement_key/1)
    |> Enum.reduce({%{}, []}, fn data, {assets, events} ->
      case update_asset(assets, data, eur_usd, eur_cad) do
        {assets, nil} -> {assets, events}
        {assets, event} -> {assets, [event | events]}
      end
    end)
  end

  # Within one date, buys settle before sells: you can only sell units you
  # already hold, and the emails don't record intraday order. Replaying a
  # same-day sell first would treat units as uncovered that the same day's
  # buy actually covered, wrongly realizing P&L and then re-adding the full
  # cost of units that had already been sold.
  defp settlement_key(op), do: {date_sort_key(op.fecha), sell?(op.tipo)}

  defp sell?(tipo), do: if(buy?(tipo), do: 0, else: 1)

  defp date_sort_key(fecha) do
    case String.split(fecha, "/") do
      [d, m, y] -> {y, m, d}
      _ -> {"", "", ""}
    end
  end

  defp update_asset(assets, data, eur_usd, eur_cad) do
    qty = parse_cantidad(data.cantidad)
    cost_eur = amount_in_eur(data.importe_with_comision, data.precio, qty, eur_usd, eur_cad)

    a =
      Map.get(assets, data.isin, %{
        asset: data.asset, isin: data.isin,
        net_qty: 0.0, cost_basis: 0.0, total_bought: 0.0, total_received: 0.0, realized: 0.0,
        current_value: nil, earnings_abs: nil, earnings_pct: nil
      })

    if buy?(data.tipo) do
      a = %{a | net_qty: a.net_qty + qty, cost_basis: a.cost_basis + cost_eur, total_bought: a.total_bought + cost_eur}
      {Map.put(assets, data.isin, a), nil}
    else
      avg_cost = if a.net_qty > 0, do: a.cost_basis / a.net_qty, else: 0.0
      covered = min(qty, max(a.net_qty, 0.0))
      cost = covered * avg_cost
      realized = if qty > 0, do: covered * (cost_eur / qty) - cost, else: 0.0

      a = %{a | net_qty: a.net_qty - qty, cost_basis: a.cost_basis - cost,
            total_received: a.total_received + cost_eur, realized: a.realized + realized}

      event = %{
        fecha: data.fecha, asset: data.asset, isin: data.isin, tipo: data.tipo,
        qty: qty, uncovered: qty - covered, proceeds: cost_eur, cost: cost, realized: realized
      }

      {Map.put(assets, data.isin, a), event}
    end
  end

  def buy?(tipo), do: tipo in ["Suscripcion", "Compra", "Traspaso Entrada"]

  def parse_cantidad(str) do
    case Money.parse_number(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  # Prefers importe_with_comision (actual EUR amount) over precio×qty when available in EUR.
  def amount_in_eur(importe_str, precio_str, qty, eur_usd, eur_cad) do
    case Regex.run(~r/([\d.,]+)\s+EUR\b/, String.trim(importe_str)) do
      [_, amount] -> importe_or_cost(Money.parse_number(amount), precio_str, qty, eur_usd, eur_cad)
      _ -> cost_in_eur(precio_str, qty, eur_usd, eur_cad)
    end
  end

  defp importe_or_cost({val, _}, _precio_str, _qty, _eur_usd, _eur_cad) when val > 0, do: val

  defp importe_or_cost(_parsed, precio_str, qty, eur_usd, eur_cad) do
    cost_in_eur(precio_str, qty, eur_usd, eur_cad)
  end

  defp cost_in_eur(precio_str, qty, eur_usd, eur_cad) do
    price_cost(Money.parse_price(precio_str), qty, eur_usd, eur_cad)
  end

  defp price_cost({price, currency}, qty, eur_usd, eur_cad) do
    Money.to_eur(price, currency, eur_usd, eur_cad) * qty
  end

  defp price_cost(:error, _qty, _eur_usd, _eur_cad), do: 0.0
end
