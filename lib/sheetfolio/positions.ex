defmodule Sheetfolio.Positions do
  @moduledoc """
  Aggregates operations into per-ISIN positions using average-cost basis.
  """

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

  defp replay(operations, eur_usd, eur_cad) do
    operations
    |> Enum.sort_by(fn %{fecha: f} ->
      case String.split(f, "/") do
        [d, m, y] -> {y, m, d}
        _ -> {"", "", ""}
      end
    end)
    |> Enum.reduce({%{}, []}, fn data, {assets, events} ->
      case update_asset(assets, data, eur_usd, eur_cad) do
        {assets, nil} -> {assets, events}
        {assets, event} -> {assets, [event | events]}
      end
    end)
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
    case parse_number(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  # Prefers importe_with_comision (actual EUR amount) over precio×qty when available in EUR.
  def amount_in_eur(importe_str, precio_str, qty, eur_usd, eur_cad) do
    case Regex.run(~r/([\d.,]+)\s+EUR\b/, String.trim(importe_str)) do
      [_, amount] ->
        case parse_number(amount) do
          {val, _} when val > 0 -> val
          _ -> cost_in_eur(precio_str, qty, eur_usd, eur_cad)
        end
      _ -> cost_in_eur(precio_str, qty, eur_usd, eur_cad)
    end
  end

  defp cost_in_eur(precio_str, qty, eur_usd, eur_cad) do
    case Regex.run(~r/([\d.,]+)\s+([A-Z]+)/, precio_str) do
      [_, amount, currency] ->
        case parse_number(amount) do
          {price, _} -> to_eur(price, currency, eur_usd, eur_cad) * qty
          :error -> 0.0
        end
      _ -> 0.0
    end
  end

  def parse_number(str) do
    cond do
      String.contains?(str, ".") and String.contains?(str, ",") ->
        # Determine format by which separator appears last.
        # "1,000.34" → dot last → English (comma=thousands) → 1000.34
        # "1.418,996" → comma last → Spanish (dot=thousands) → 1418.996
        last_dot = str |> :binary.matches(".") |> List.last() |> elem(0)
        last_comma = str |> :binary.matches(",") |> List.last() |> elem(0)
        if last_dot > last_comma do
          str |> String.replace(",", "") |> Float.parse()
        else
          str |> String.replace(".", "") |> String.replace(",", ".") |> Float.parse()
        end
      String.contains?(str, ",") ->
        # If exactly 3 digits follow the last comma: English thousands separator.
        # "1,188" → 1188 | "14,2592" → 14.2592
        case Regex.run(~r/^[\d,]+,(\d{3})$/, str) do
          [_, _] -> str |> String.replace(",", "") |> Float.parse()
          _ -> str |> String.replace(",", ".") |> Float.parse()
        end
      true ->
        Float.parse(str)
    end
  end

  def to_eur(price, "USD", eur_usd, _), do: price / eur_usd
  def to_eur(price, "CAD", _, eur_cad), do: price / eur_cad
  def to_eur(price, _, _, _), do: price
end
