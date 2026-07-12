defmodule SheetfolioWeb.SnapshotLive do
  use SheetfolioWeb, :live_view

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()
      today = Date.utc_today() |> Date.to_iso8601()

      socket =
        assign(socket,
          authenticated: true,
          assets: %{},
          all_operations: [],
          selected_date: today,
          eur_usd: eur_usd,
          eur_cad: eur_cad
        )

      if connected?(socket) do
        operations = Sheetfolio.OperationsServer.get_operations() || []
        socket = recalculate(assign(socket, all_operations: operations), today)
        {:ok, socket}
      else
        {:ok, socket}
      end
    end
  end

  def handle_event("set_date", %{"date" => date}, socket) when date != "" do
    socket =
      socket
      |> assign(selected_date: date, assets: %{})
      |> recalculate(date)

    {:noreply, socket}
  end

  def handle_event("set_date", _, socket), do: {:noreply, socket}

  def handle_info({:price_result, _isin, nil}, socket), do: {:noreply, socket}

  def handle_info({:price_result, isin, price_eur}, socket) do
    {:noreply, apply_price(socket, isin, price_eur, false)}
  end

  def handle_info({:price_estimate, isin, price_eur}, socket) do
    {:noreply, apply_price(socket, isin, price_eur, true)}
  end

  defp apply_price(socket, isin, price_eur, estimated) do
    case Map.fetch(socket.assigns.assets, isin) do
      {:ok, a} ->
        current_value = Float.round(a.net_qty * price_eur, 2)
        earnings_abs = Float.round(current_value - a.cost_basis, 2)

        earnings_pct =
          if a.cost_basis != 0.0,
            do: Float.round(earnings_abs / a.cost_basis * 100, 2),
            else: nil

        assets =
          Map.put(socket.assigns.assets, isin, %{
            a
            | current_value: current_value,
              earnings_abs: earnings_abs,
              earnings_pct: earnings_pct,
              estimated: estimated
          })

        assign(socket, assets: assets)

      :error ->
        socket
    end
  end

  defp recalculate(socket, date_str) do
    eur_usd = socket.assigns.eur_usd
    eur_cad = socket.assigns.eur_cad
    cutoff = parse_iso_date(date_str)

    assets =
      socket.assigns.all_operations
      |> Enum.filter(fn %{fecha: f} -> Date.compare(parse_op_date(f), cutoff) in [:lt, :eq] end)
      |> Enum.sort_by(fn %{fecha: f} ->
        case String.split(f, "/") do
          [d, m, y] -> {y, m, d}
          _ -> {"", "", ""}
        end
      end)
      |> Enum.reduce(%{}, fn data, acc ->
        update_asset(acc, data, eur_usd, eur_cad)
      end)

    pid = self()
    date = parse_iso_date(date_str)

    assets
    |> Enum.filter(fn {_, a} -> a.net_qty > 0.001 end)
    |> Enum.each(fn {isin, _} -> Sheetfolio.EarningsServer.request_price_at(isin, date, pid) end)

    assign(socket, assets: assets)
  end

  defp parse_iso_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> Date.utc_today()
    end
  end

  defp parse_op_date(str) do
    case String.split(str, "/") do
      [d, m, y] -> iso_date_or_max("#{y}-#{m}-#{d}")
      _ -> ~D[9999-12-31]
    end
  end

  defp iso_date_or_max(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> ~D[9999-12-31]
    end
  end

  def render(assigns) do
    ~H"""
    <style>
      .snapshot-table { width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .snapshot-table th { background: #1e293b; color: white; padding: 0.75rem 1rem; text-align: left; font-size: 0.85rem; font-weight: 600; letter-spacing: 0.03em; position: sticky; top: 0; z-index: 1; }
      .snapshot-table th:not(:first-child) { text-align: right; }
      .snapshot-table td { padding: 0.65rem 1rem; border-bottom: 1px solid #f1f5f9; font-size: 0.9rem; }
      .snapshot-table td:not(:first-child) { text-align: right; }
      .snapshot-table tr:last-child td { border-bottom: none; }
      .snapshot-table tr:hover td { background: #f8fafc; }
      .snapshot-table tfoot td { background: #f8fafc; font-weight: 600; border-top: 2px solid #e2e8f0; }
      .positive { color: #16a34a; font-weight: 600; }
      .negative { color: #dc2626; font-weight: 600; }
      .date-bar { display: flex; align-items: center; gap: 1rem; margin-bottom: 1.5rem; }
      .date-bar label { font-size: 0.9rem; font-weight: 600; color: #475569; }
      .date-bar input[type=date] { padding: 0.4rem 0.7rem; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 0.9rem; color: #1e293b; background: white; }
      .price-note { font-size: 0.8rem; color: #94a3b8; margin-left: auto; }
    </style>

    <div class="date-bar">
      <label>Snapshot date</label>
      <form phx-change="set_date" style="display:contents;">
        <input type="date" name="date" value={@selected_date} max={Date.utc_today() |> Date.to_iso8601()} />
      </form>
      <span class="price-note">Positions and prices as of selected date</span>
    </div>

    <%= if map_size(@assets) > 0 do %>
      <% active = @assets |> Map.values() |> Enum.filter(& &1.net_qty > 0.001) |> Enum.sort_by(& &1.cost_basis, :desc) %>
      <% meaningful = Enum.filter(active, & &1.cost_basis > 0) %>
      <% priced = Enum.filter(meaningful, & &1.current_value) %>
      <% total_invested = Enum.reduce(priced, 0, fn a, acc -> acc + a.cost_basis end) %>
      <% total_value = Enum.reduce(priced, 0, fn a, acc -> acc + a.current_value end) %>
      <% total_earnings = if total_invested > 0, do: Float.round(total_value - total_invested, 2), else: nil %>
      <% total_pct = if total_invested > 0 and total_earnings, do: Float.round(total_earnings / total_invested * 100, 2), else: nil %>

      <% today_str = Date.utc_today() |> Date.to_iso8601() %>
      <%= if active == [] do %>
        <p style="color:#94a3b8; text-align:center; padding: 2rem;">No active positions on this date.</p>
      <% else %>
        <table class="snapshot-table">
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
              <% show_estimate_warning = a.estimated and @selected_date != today_str %>
              <tr>
                <td>
                  <strong><%= a.asset %></strong><br/>
                  <small style="color:#94a3b8"><%= a.isin %></small>
                  <%= if show_estimate_warning do %>
                    <br/><small style="color:#f59e0b">⚠ No historical data — price estimated at 0.02%/day</small>
                  <% end %>
                </td>
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
              <td><%= if total_value > 0, do: format_eur(total_value), else: "—" %></td>
              <td class={earnings_class(total_earnings)}><%= format_abs(total_earnings) %></td>
              <td class={earnings_class(total_pct)}><%= format_pct(total_pct) %></td>
            </tr>
          </tfoot>
        </table>
      <% end %>
    <% else %>
      <p style="color:#94a3b8; text-align:center; padding: 2rem;">No positions found for this date.</p>
    <% end %>
    """
  end

  defp update_asset(assets, data, eur_usd, eur_cad) do
    qty = Sheetfolio.Positions.parse_cantidad(data.cantidad)
    cost_eur = Sheetfolio.Positions.amount_in_eur(data.importe_with_comision, data.precio, qty, eur_usd, eur_cad)
    is_buy = buy?(data.tipo)

    initial = %{
      asset: data.asset,
      isin: data.isin,
      net_qty: if(is_buy, do: qty, else: -qty),
      cost_basis: if(is_buy, do: cost_eur, else: 0.0),
      total_bought: if(is_buy, do: cost_eur, else: 0.0),
      total_received: if(is_buy, do: 0.0, else: cost_eur),
      current_value: nil,
      earnings_abs: nil,
      earnings_pct: nil,
      estimated: false
    }

    Map.update(assets, data.isin, initial, fn a ->
      if is_buy do
        %{a | net_qty: a.net_qty + qty, cost_basis: a.cost_basis + cost_eur, total_bought: a.total_bought + cost_eur}
      else
        avg_cost = if a.net_qty > 0, do: a.cost_basis / a.net_qty, else: 0.0
        %{a | net_qty: a.net_qty - qty, cost_basis: a.cost_basis - qty * avg_cost, total_received: a.total_received + cost_eur}
      end
    end)
  end

  defp buy?(tipo), do: tipo in ["Suscripcion", "Compra", "Traspaso Entrada"]


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
