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

        ops_by_isin = Enum.group_by(operations, & &1.isin)

        pid = self()

        assets
        |> Enum.filter(fn {_, a} -> a.net_qty > 0.001 end)
        |> Enum.each(fn {isin, _} -> Sheetfolio.EarningsServer.request_price(isin, pid) end)

        {:ok, assign(socket, assets: assets, ops_by_isin: ops_by_isin, selected_isin: nil)}
      else
        {:ok, assign(socket, ops_by_isin: %{}, selected_isin: nil)}
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

  def handle_event("toggle_isin", %{"isin" => isin}, socket) do
    selected = if socket.assigns.selected_isin == isin, do: nil, else: isin
    {:noreply, assign(socket, selected_isin: selected)}
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

    <%= if @live_action == :active do %>
      <%= render_active(assigns) %>
    <% else %>
      <%= render_settled(assigns) %>
    <% end %>
    """
  end

  defp render_active(assigns) do
    ~H"""
    <%= if map_size(@assets) > 0 do %>
      <% active = @assets |> Map.values() |> Enum.filter(& &1.net_qty > 0.001) |> Enum.sort_by(& &1.cost_basis, :desc) %>
      <% meaningful = Enum.filter(active, & &1.cost_basis > 0) %>
      <% total_invested = Enum.reduce(meaningful, 0, fn a, acc -> acc + a.cost_basis end) %>
      <% total_value = meaningful |> Enum.filter(& &1.current_value) |> Enum.reduce(0, fn a, acc -> acc + a.current_value end) %>
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
              <td><%= if a.cost_basis > 0, do: format_eur(a.cost_basis), else: "—" %></td>
              <td><%= if a.current_value, do: format_eur(a.current_value), else: "—" %></td>
              <td class={earnings_class(if a.cost_basis > 0, do: a.earnings_abs, else: nil)}>
                <%= if a.cost_basis > 0, do: format_abs(a.earnings_abs), else: "—" %>
              </td>
              <td class={earnings_class(if a.cost_basis > 0, do: a.earnings_pct, else: nil)}>
                <%= if a.cost_basis > 0, do: format_pct(a.earnings_pct), else: "—" %>
              </td>
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

  defp render_settled(assigns) do
    ~H"""
    <style>
      .row-clickable { cursor: pointer; }
      .row-clickable:hover td { background: #f1f5f9 !important; }
      .row-toggle-icon { float: right; color: #94a3b8; font-size: 0.8rem; }
      .ops-detail td { background: #f8fafc; font-size: 0.82rem; padding: 0.4rem 1rem; border-bottom: 1px solid #e2e8f0; }
      .ops-detail td:not(:first-child) { text-align: right; }
      .ops-detail th { background: #e2e8f0; color: #475569; font-size: 0.78rem; padding: 0.35rem 1rem; text-align: right; }
      .ops-detail th:first-child { text-align: left; }
      .ops-buy { color: #16a34a; }
      .ops-sell { color: #dc2626; }
    </style>
    <%= if map_size(@assets) > 0 do %>
      <% settled = @assets |> Map.values() |> Enum.filter(& &1.total_received > 0) |> Enum.sort_by(& &1.total_received, :desc) %>
      <% cost_sold = fn a -> max(0.0, a.total_bought - max(0.0, a.cost_basis)) end %>
      <% total_invested = Enum.reduce(settled, 0, fn a, acc -> acc + cost_sold.(a) end) %>
      <% total_received = Enum.reduce(settled, 0, fn a, acc -> acc + a.total_received end) %>
      <% total_pnl = Float.round(total_received - total_invested, 2) %>
      <% total_pct = if total_invested > 0, do: Float.round(total_pnl / total_invested * 100, 2), else: nil %>

      <table class="summary-table">
        <thead>
          <tr>
            <th>Asset</th>
            <th>Cost of sold (€)</th>
            <th>Received (€)</th>
            <th>Realized P&amp;L (€)</th>
            <th>Realized P&amp;L (%)</th>
          </tr>
        </thead>
        <tbody>
          <%= for a <- settled do %>
            <% sold_cost = cost_sold.(a) %>
            <% pnl = Float.round(a.total_received - sold_cost, 2) %>
            <% pnl_pct = if sold_cost > 0, do: Float.round(pnl / sold_cost * 100, 2), else: nil %>
            <% expanded = @selected_isin == a.isin %>
            <% partial = a.net_qty > 0.001 %>
            <tr class="row-clickable" phx-click="toggle_isin" phx-value-isin={a.isin}>
              <td>
                <strong><%= a.asset %></strong>
                <%= if partial do %><span style="font-size:0.72rem;background:#dbeafe;color:#1d4ed8;border-radius:4px;padding:1px 5px;margin-left:4px;">active</span><% end %>
                <span class="row-toggle-icon"><%= if expanded, do: "▲", else: "▼" %></span>
                <br/><small style="color:#94a3b8"><%= a.isin %></small>
              </td>
              <td><%= format_eur(sold_cost) %></td>
              <td><%= format_eur(a.total_received) %></td>
              <td class={earnings_class(pnl)}><%= format_abs(pnl) %></td>
              <td class={earnings_class(pnl_pct)}><%= format_pct(pnl_pct) %></td>
            </tr>
            <%= if expanded do %>
              <% ops = Map.get(@ops_by_isin, a.isin, []) |> Enum.sort_by(& &1.fecha) %>
              <tr class="ops-detail">
                <td colspan="5" style="padding: 0;">
                  <table style="width:100%; border-collapse: collapse;">
                    <thead>
                      <tr>
                        <th>Type</th>
                        <th>Date</th>
                        <th>Units</th>
                        <th>Amount (€)</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for op <- ops do %>
                        <% is_buy = buy?(op.tipo) %>
                        <tr>
                          <td class={if is_buy, do: "ops-buy", else: "ops-sell"}>
                            <%= if is_buy, do: "Buy", else: "Sell" %>
                          </td>
                          <td><%= op.fecha %></td>
                          <td><%= format_qty(parse_cantidad(op.cantidad)) %></td>
                          <td><%= format_eur(amount_in_eur(op.importe_with_comision, op.precio, parse_cantidad(op.cantidad), @eur_usd, @eur_cad)) %></td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </td>
              </tr>
            <% end %>
          <% end %>
        </tbody>
        <tfoot>
          <tr>
            <td>Total</td>
            <td><%= format_eur(total_invested) %></td>
            <td><%= format_eur(total_received) %></td>
            <td class={earnings_class(total_pnl)}><%= format_abs(total_pnl) %></td>
            <td class={earnings_class(total_pct)}><%= format_pct(total_pct) %></td>
          </tr>
        </tfoot>
      </table>
    <% end %>
    """
  end

  defp update_asset(assets, data, eur_usd, eur_cad) do
    qty = parse_cantidad(data.cantidad)
    cost_eur = amount_in_eur(data.importe_with_comision, data.precio, qty, eur_usd, eur_cad)
    is_buy = buy?(data.tipo)
    {qty_delta, cost_delta, bought_delta, received_delta} =
      if is_buy,
        do: {qty, cost_eur, cost_eur, 0.0},
        else: {-qty, -cost_eur, 0.0, cost_eur}

    Map.update(assets, data.isin,
      %{asset: data.asset, isin: data.isin, net_qty: qty_delta, cost_basis: cost_delta,
        total_bought: bought_delta, total_received: received_delta,
        current_value: nil, earnings_abs: nil, earnings_pct: nil},
      fn a -> %{a |
        net_qty: a.net_qty + qty_delta,
        cost_basis: a.cost_basis + cost_delta,
        total_bought: a.total_bought + bought_delta,
        total_received: a.total_received + received_delta
      } end
    )
  end

  defp buy?(tipo), do: tipo in ["Suscripcion", "Compra", "Traspaso Entrada"]

  defp parse_cantidad(str) do
    case parse_number(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  # Prefers importe_with_comision (actual EUR amount) over precio×qty when available in EUR.
  defp amount_in_eur(importe_str, precio_str, qty, eur_usd, eur_cad) do
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

  defp parse_number(str) do
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
