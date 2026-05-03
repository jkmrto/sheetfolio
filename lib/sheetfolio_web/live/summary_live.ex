defmodule SheetfolioWeb.SummaryLive do
  use SheetfolioWeb, :live_view

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()

      socket = assign(socket,
        authenticated: true,
        assets: %{},
        eur_usd: eur_usd,
        eur_cad: eur_cad
      )

      if connected?(socket) do
        operations = Sheetfolio.OperationsServer.get_operations() || []

        assets =
          Enum.reduce(operations, %{}, fn data, acc ->
            update_asset(acc, data, eur_usd, eur_cad)
          end)

        pid = self()

        assets
        |> Enum.filter(fn {_, a} -> a.net_qty > 0 end)
        |> Enum.each(fn {isin, _} -> Sheetfolio.EarningsServer.request_price(isin, pid) end)

        {:ok, assign(socket, assets: assets)}
      else
        {:ok, socket}
      end
    end
  end

  def handle_info({:price_result, _isin, nil}, socket) do
    {:noreply, socket}
  end

  def handle_info({:price_result, isin, price_eur}, socket) do
    assets = Map.update!(socket.assigns.assets, isin, fn a ->
      current_value = Float.round(a.net_qty * price_eur, 2)
      earnings_abs = Float.round(current_value - a.cost_basis, 2)
      earnings_pct = if a.cost_basis != 0.0, do: Float.round(earnings_abs / a.cost_basis * 100, 2), else: nil
      %{a | current_value: current_value, earnings_abs: earnings_abs, earnings_pct: earnings_pct}
    end)

    {:noreply, assign(socket, assets: assets)}
  end

  def render(assigns) do
    ~H"""
    <style>
      .summary-table { width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .summary-table th { background: #1e293b; color: white; padding: 0.75rem 1rem; text-align: left; font-size: 0.85rem; font-weight: 600; letter-spacing: 0.03em; position: sticky; top: 0; z-index: 1; }
      .summary-table th:not(:first-child) { text-align: right; }
      .summary-table td { padding: 0.65rem 1rem; border-bottom: 1px solid #f1f5f9; font-size: 0.9rem; }
      .summary-table td:not(:first-child) { text-align: right; }
      .summary-table tr:last-child td { border-bottom: none; }
      .summary-table tr:hover td { background: #f8fafc; }
      .summary-table tfoot td { background: #f8fafc; font-weight: 600; border-top: 2px solid #e2e8f0; }
      .positive { color: #16a34a; font-weight: 600; }
      .negative { color: #dc2626; font-weight: 600; }
    </style>

    <%= if map_size(@assets) > 0 do %>
      <% active = @assets |> Map.values() |> Enum.filter(& &1.net_qty > 0) |> Enum.sort_by(& &1.cost_basis, :desc) %>
      <% total_invested = Enum.reduce(active, 0, fn a, acc -> acc + a.cost_basis end) %>
      <% total_value = active |> Enum.filter(& &1.current_value) |> Enum.reduce(0, fn a, acc -> acc + a.current_value end) %>
      <% total_earnings = if total_invested > 0, do: Float.round(total_value - total_invested, 2), else: nil %>
      <% total_pct = if total_invested > 0 and total_earnings, do: Float.round(total_earnings / total_invested * 100, 2), else: nil %>

      <table class="summary-table">
        <thead>
          <tr>
            <th>Asset</th>
            <th>Units held</th>
            <th>Invested (€)</th>
            <th>Current Value (€)</th>
            <th>Gain/Loss (€)</th>
            <th>Gain/Loss (%)</th>
          </tr>
        </thead>
        <tbody>
          <%= for a <- active do %>
            <tr>
              <td><strong><%= a.asset %></strong><br/><small style="color:#94a3b8"><%= a.isin %></small></td>
              <td><%= format_qty(a.net_qty) %></td>
              <td><%= format_eur(a.cost_basis) %></td>
              <td><%= if a.current_value, do: format_eur(a.current_value), else: "—" %></td>
              <td class={earnings_class(a.earnings_abs)}><%= format_abs(a.earnings_abs) %></td>
              <td class={earnings_class(a.earnings_pct)}><%= format_pct(a.earnings_pct) %></td>
            </tr>
          <% end %>
        </tbody>
        <tfoot>
          <tr>
            <td>Total</td>
            <td></td>
            <td><%= format_eur(total_invested) %></td>
            <td><%= format_eur(total_value) %></td>
            <td class={earnings_class(total_earnings)}><%= format_abs(total_earnings) %></td>
            <td class={earnings_class(total_pct)}><%= format_pct(total_pct) %></td>
          </tr>
        </tfoot>
      </table>
    <% end %>
    """
  end

  defp update_asset(assets, data, eur_usd, eur_cad) do
    qty = parse_cantidad(data.cantidad)
    cost_eur = cost_in_eur(data.precio, qty, eur_usd, eur_cad)
    {qty_delta, cost_delta} = if buy?(data.tipo), do: {qty, cost_eur}, else: {-qty, -cost_eur}

    Map.update(assets, data.isin,
      %{asset: data.asset, isin: data.isin, net_qty: qty_delta, cost_basis: cost_delta,
        current_value: nil, earnings_abs: nil, earnings_pct: nil},
      fn a -> %{a | net_qty: a.net_qty + qty_delta, cost_basis: a.cost_basis + cost_delta} end
    )
  end

  defp buy?(tipo), do: tipo in ["Suscripcion", "Compra", "Traspaso Entrada"]

  defp parse_cantidad(str) do
    case Float.parse(String.replace(str, ",", "")) do
      {qty, _} -> qty
      :error -> 0.0
    end
  end

  defp cost_in_eur(precio_str, qty, eur_usd, eur_cad) do
    case Regex.run(~r/([\d.]+)\s+([A-Z]+)/, precio_str) do
      [_, amount, currency] ->
        case Float.parse(amount) do
          {price, _} -> to_eur(price, currency, eur_usd, eur_cad) * qty
          :error -> 0.0
        end
      _ -> 0.0
    end
  end

  defp to_eur(price, "USD", eur_usd, _), do: price / eur_usd
  defp to_eur(price, "CAD", _, eur_cad), do: price / eur_cad
  defp to_eur(price, _, _, _), do: price

  defp earnings_class(nil), do: ""
  defp earnings_class(val) when val >= 0, do: "positive"
  defp earnings_class(_), do: "negative"

  defp format_eur(nil), do: "—"
  defp format_eur(val), do: "#{:erlang.float_to_binary(val * 1.0, decimals: 2)} €"

  defp format_abs(nil), do: "—"
  defp format_abs(val) when val >= 0, do: "+#{:erlang.float_to_binary(val * 1.0, decimals: 2)} €"
  defp format_abs(val), do: "#{:erlang.float_to_binary(val * 1.0, decimals: 2)} €"

  defp format_pct(nil), do: "—"
  defp format_pct(val) when val >= 0, do: "+#{val}%"
  defp format_pct(val), do: "#{val}%"

  defp format_qty(val) do
    :erlang.float_to_binary(val * 1.0, decimals: 4)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end
end
