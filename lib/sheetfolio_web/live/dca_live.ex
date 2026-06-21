defmodule SheetfolioWeb.DcaLive do
  use SheetfolioWeb, :live_view

  @base_amount 250.0
  @sp500_isins ~w[IE0032126645 IE00BYX5MX67]

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()

      socket = assign(socket,
        authenticated: true,
        operations: [],
        prices: %{},
        recommendation: nil,
        show_modal: false,
        eur_usd: eur_usd,
        eur_cad: eur_cad
      )

      if connected?(socket) do
        all_ops = Sheetfolio.OperationsServer.get_operations() || []
        ops = build_operations(all_ops, eur_usd, eur_cad)
        sp500_prices = fetch_sp500_history(ops)
        ops = attach_sp500_prices(ops, sp500_prices)
        recommendation = build_recommendation()

        pid = self()
        ops |> Enum.map(& &1.isin) |> Enum.uniq() |> Enum.each(fn isin ->
          Sheetfolio.EarningsServer.request_price(isin, pid)
        end)

        {:ok, assign(socket, operations: ops, recommendation: recommendation, show_modal: recommendation != nil)}
      else
        {:ok, socket}
      end
    end
  end

  def handle_info({:price_result, _isin, nil}, socket), do: {:noreply, socket}

  def handle_info({:price_result, isin, price_eur}, socket) do
    new_prices = Map.put(socket.assigns.prices, isin, price_eur)

    ops = Enum.map(socket.assigns.operations, fn op ->
      if op.isin != isin do
        op
      else
        extra_value = Float.round(op.extra_units * price_eur, 2)
        extra_pnl = Float.round(extra_value - op.extra_invested, 2)
        extra_pnl_pct =
          if op.extra_invested > 0,
            do: Float.round(extra_pnl / op.extra_invested * 100, 2),
            else: nil
        %{op | extra_value: extra_value, extra_pnl: extra_pnl, extra_pnl_pct: extra_pnl_pct}
      end
    end)

    chart_data = build_chart_data(ops, new_prices)

    socket =
      socket
      |> assign(operations: ops, prices: new_prices)
      |> push_event("update_dca_chart", %{
        labels: Enum.map(chart_data, & &1.date),
        baseline: Enum.map(chart_data, & &1.baseline),
        actual: Enum.map(chart_data, & &1.actual),
        sp500: Enum.map(chart_data, & &1.sp500),
        invested: Enum.map(chart_data, & &1.invested)
      })

    {:noreply, socket}
  end

  def handle_event("dismiss_modal", _, socket) do
    {:noreply, assign(socket, show_modal: false)}
  end

  def render(assigns) do
    ~H"""
    <style>
      .dca-table { width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-top: 2rem; }
      .dca-table th { background: #1e293b; color: white; padding: 0.75rem 1rem; text-align: left; font-size: 0.85rem; font-weight: 600; letter-spacing: 0.03em; position: sticky; top: 0; z-index: 1; }
      .dca-table th:not(:first-child):not(:nth-child(2)) { text-align: right; }
      .dca-table td { padding: 0.65rem 1rem; border-bottom: 1px solid #f1f5f9; font-size: 0.9rem; font-variant-numeric: tabular-nums; }
      .dca-table td:not(:first-child):not(:nth-child(2)) { text-align: right; }
      .dca-table tr:last-child td { border-bottom: none; }
      .dca-table tr:hover td { background: #f8fafc; }
      .dca-table tfoot td { background: #f8fafc; font-weight: 600; border-top: 2px solid #e2e8f0; }
      .positive { color: #16a34a; font-weight: 600; }
      .negative { color: #dc2626; font-weight: 600; }
      .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
      .card { background: white; border-radius: 12px; padding: 1.25rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .card-label { font-size: 0.78rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.4rem; }
      .card-value { font-size: 1.4rem; font-weight: 700; }
      .section-title { font-size: 0.85rem; font-weight: 600; color: #64748b; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.75rem; }
      .no-extra { color: #cbd5e1; }
    </style>

    <% ops = @operations %>
    <% total_extra_invested = Enum.reduce(ops, 0.0, fn o, acc -> acc + o.extra_invested end) %>
    <% total_extra_value = ops |> Enum.filter(& &1.extra_value) |> Enum.reduce(0.0, fn o, acc -> acc + o.extra_value end) %>
    <% total_extra_pnl = if total_extra_invested > 0 and total_extra_value > 0, do: Float.round(total_extra_value - total_extra_invested, 2), else: nil %>
    <% total_extra_pnl_pct = if total_extra_invested > 0 and total_extra_pnl, do: Float.round(total_extra_pnl / total_extra_invested * 100, 2), else: nil %>

    <%= if @show_modal and @recommendation do %>
      <% r = @recommendation %>
      <div style="position:fixed;inset:0;background:rgba(0,0,0,0.45);z-index:200;display:flex;align-items:center;justify-content:center;" phx-click="dismiss_modal">
        <div style="background:white;border-radius:16px;padding:2rem;max-width:400px;width:90%;box-shadow:0 8px 40px rgba(0,0,0,0.2);" phx-click-away="dismiss_modal">
          <h2 style="font-size:1.05rem;font-weight:700;color:#1e293b;margin-bottom:1.5rem;">This week's investment</h2>

          <div style="display:flex;flex-direction:column;gap:0.6rem;margin-bottom:1.5rem;font-size:0.9rem;">
            <div style="display:flex;justify-content:space-between;">
              <span style="color:#64748b;">S&amp;P500 now</span>
              <span style="font-weight:600;">$<%= format_sp500(r.current) %></span>
            </div>
            <div style="display:flex;justify-content:space-between;">
              <span style="color:#64748b;">All-time high</span>
              <span style="font-weight:600;">$<%= format_sp500(r.ath) %></span>
            </div>
            <div style="display:flex;justify-content:space-between;padding-top:0.4rem;border-top:1px solid #f1f5f9;">
              <span style="color:#64748b;">Below ATH</span>
              <span style={if r.pct_below > 0, do: "font-weight:600;color:#dc2626;", else: "font-weight:600;color:#16a34a;"}>
                <%= if r.pct_below > 0, do: "-#{:erlang.float_to_binary(r.pct_below, decimals: 2)}%", else: "At ATH" %>
              </span>
            </div>
          </div>

          <div style="text-align:center;background:#f8fafc;border-radius:12px;padding:1.25rem;margin-bottom:1.5rem;">
            <div style="font-size:0.78rem;color:#94a3b8;text-transform:uppercase;letter-spacing:0.05em;margin-bottom:0.5rem;">Invest this week</div>
            <div style="font-size:2.8rem;font-weight:800;color:#6366f1;line-height:1;"><%= r.amount %> €</div>
            <%= if r.pct_below > 0 do %>
              <div style="font-size:0.8rem;color:#94a3b8;margin-top:0.4rem;">250 + <%= r.steps %> × 50</div>
            <% end %>
          </div>

          <button phx-click="dismiss_modal" style="width:100%;padding:0.65rem;background:#6366f1;color:white;border:none;border-radius:8px;font-size:0.9rem;font-weight:600;cursor:pointer;">
            Got it
          </button>
        </div>
      </div>
    <% end %>

    <p class="section-title">Extra DCA impact — base: 250 €/week, extra: 50 € per 1% below ATH</p>

    <div class="cards">
      <div class="card">
        <div class="card-label">Total Extra Invested</div>
        <div class="card-value"><%= format_eur(total_extra_invested) %></div>
      </div>
      <div class="card">
        <div class="card-label">Extra Current Value</div>
        <div class="card-value"><%= format_eur(total_extra_value) %></div>
      </div>
      <div class="card">
        <div class="card-label">Extra Gain / Loss</div>
        <div class={"card-value #{earnings_class(total_extra_pnl)}"}><%= format_abs(total_extra_pnl) %></div>
      </div>
      <div class="card">
        <div class="card-label">Extra Return</div>
        <div class={"card-value #{earnings_class(total_extra_pnl_pct)}"}><%= format_pct(total_extra_pnl_pct) %></div>
      </div>
    </div>

    <div class="chart-container" style="margin-bottom: 2rem;">
      <canvas id="dca-chart" phx-hook="DcaChart" phx-update="ignore"></canvas>
    </div>

    <%= if ops != [] do %>
      <table class="dca-table">
        <thead>
          <tr>
            <th>Date</th>
            <th>ETF</th>
            <th>S&amp;P500 (USD)</th>
            <th>Total (€)</th>
            <th>Extra (€)</th>
            <th>Extra Value (€)</th>
            <th>Extra Gain/Loss (€)</th>
            <th>Extra Return (%)</th>
          </tr>
        </thead>
        <tbody>
          <%= for op <- ops do %>
            <tr>
              <td style="white-space:nowrap"><%= op.fecha %></td>
              <td><small style="color:#64748b"><%= short_name(op.asset) %></small></td>
              <td><%= format_usd(op.sp500_value) %></td>
              <td><%= format_eur(op.total_invested) %></td>
              <td>
                <%= if op.extra_invested > 0 do %>
                  <%= format_eur(op.extra_invested) %>
                <% else %>
                  <span class="no-extra">—</span>
                <% end %>
              </td>
              <td><%= format_eur(op.extra_value) %></td>
              <td class={earnings_class(op.extra_pnl)}><%= format_abs(op.extra_pnl) %></td>
              <td class={earnings_class(op.extra_pnl_pct)}><%= format_pct(op.extra_pnl_pct) %></td>
            </tr>
          <% end %>
        </tbody>
        <tfoot>
          <tr>
            <td colspan="4">Total</td>
            <td><%= format_eur(total_extra_invested) %></td>
            <td><%= format_eur(total_extra_value) %></td>
            <td class={earnings_class(total_extra_pnl)}><%= format_abs(total_extra_pnl) %></td>
            <td class={earnings_class(total_extra_pnl_pct)}><%= format_pct(total_extra_pnl_pct) %></td>
          </tr>
        </tfoot>
      </table>
    <% end %>
    """
  end

  defp build_chart_data(ops, prices) do
    ops
    |> Enum.sort_by(&date_sort_key(&1.fecha))
    |> Enum.reduce({[], 0.0, 0.0}, fn op, {pts, cum_base_earn, cum_extra_earn} ->
      case Map.get(prices, op.isin) do
        nil ->
          {pts, cum_base_earn, cum_extra_earn}

        price ->
          new_base = cum_base_earn + (op.base_units * price - op.base_invested)
          new_extra = cum_extra_earn + (op.extra_units * price - op.extra_invested)

          point = %{
            date: to_iso_date(op.fecha),
            baseline: Float.round(new_base, 2),
            actual: Float.round(new_base + new_extra, 2),
            sp500: op.sp500_value,
            invested: Float.round(op.total_invested, 2)
          }

          {[point | pts], new_base, new_extra}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp build_operations(operations, eur_usd, eur_cad) do
    operations
    |> Enum.filter(fn op ->
      op.tipo in ["Suscripcion", "Compra"] and
        op.isin in @sp500_isins and
        not op.traspaso
    end)
    |> Enum.group_by(fn op -> {op.fecha, op.isin} end)
    |> Enum.map(fn {{fecha, isin}, ops} ->
      {total_qty, total_amount} =
        Enum.reduce(ops, {0.0, 0.0}, fn op, {qty_acc, amt_acc} ->
          qty = parse_cantidad(op.cantidad)
          amt = amount_in_eur(op.importe_with_comision, op.precio, qty, eur_usd, eur_cad)
          {qty_acc + qty, amt_acc + amt}
        end)

      base_invested = min(total_amount, @base_amount)
      extra_invested = max(0.0, total_amount - @base_amount)
      base_units = if total_amount > 0, do: total_qty * base_invested / total_amount, else: total_qty
      extra_units = if total_amount > 0, do: total_qty * extra_invested / total_amount, else: 0.0

      %{
        fecha: fecha,
        asset: hd(ops).asset,
        isin: isin,
        total_invested: total_amount,
        base_invested: base_invested,
        extra_invested: extra_invested,
        base_units: base_units,
        extra_units: extra_units,
        extra_value: nil,
        extra_pnl: nil,
        extra_pnl_pct: nil
      }
    end)
    |> Enum.sort_by(fn op -> date_sort_key(op.fecha) end, :desc)
  end

  defp build_recommendation do
    with {:ok, current, _} <- Sheetfolio.PricesApi.YahooFinance.fetch_price("^GSPC"),
         {:ok, ath} <- fetch_sp500_ath() do
      pct_below = max(0.0, (ath - current) / ath * 100)
      steps = round(pct_below)
      %{current: current, ath: ath, pct_below: pct_below, steps: steps, amount: 250 + steps * 50}
    else
      _ -> nil
    end
  end

  defp fetch_sp500_ath do
    url = "https://query1.finance.yahoo.com/v8/finance/chart/%5EGSPC"

    case Req.get(url, params: [range: "5y", interval: "1d"]) do
      {:ok, %{status: 200, body: body}} ->
        try do
          highs =
            body["chart"]["result"]
            |> List.first()
            |> get_in(["indicators", "quote"])
            |> List.first()
            |> Map.get("high")
            |> Enum.filter(& &1)

          {:ok, Enum.max(highs)}
        rescue
          _ -> {:error, :parse}
        end

      _ ->
        {:error, :fetch}
    end
  end

  defp fetch_sp500_history([]), do: %{}

  defp fetch_sp500_history(ops) do
    dates = Enum.map(ops, &parse_op_date(&1.fecha))
    min_date = Enum.min(dates, Date)
    max_date = Date.utc_today()
    period1 = DateTime.new!(min_date, ~T[00:00:00], "Etc/UTC") |> DateTime.to_unix()
    period2 = DateTime.new!(max_date, ~T[23:59:59], "Etc/UTC") |> DateTime.to_unix()

    case Sheetfolio.PricesApi.YahooFinance.fetch_historical("^GSPC", period1, period2) do
      {:ok, prices} -> prices
      _ -> %{}
    end
  end

  defp attach_sp500_prices(ops, prices) do
    Enum.map(ops, fn op ->
      date = parse_op_date(op.fecha)
      sp500_value = Enum.find_value(0..4, fn offset -> Map.get(prices, Date.add(date, -offset)) end)
      Map.put(op, :sp500_value, sp500_value)
    end)
  end

  defp parse_op_date(fecha) do
    [d, m, y] = String.split(fecha, "/")
    Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d))
  end

  defp to_iso_date(fecha) do
    [d, m, y] = String.split(fecha, "/")
    "#{y}-#{m}-#{d}"
  end

  defp date_sort_key(fecha) do
    case String.split(fecha, "/") do
      [d, m, y] -> {String.to_integer(y), String.to_integer(m), String.to_integer(d)}
      _ -> {0, 0, 0}
    end
  end

  defp short_name(asset) do
    asset
    |> String.replace("FIDELITY S&P 500 INDEX P ACC EUR", "Fidelity S&P500")
    |> String.replace("VANGUARD US 500 STOCK INDEX EUR", "Vanguard US500")
    |> then(fn s -> if String.length(s) > 24, do: String.slice(s, 0, 24) <> "…", else: s end)
  end

  defp parse_cantidad(str) do
    case parse_number(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end

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
        last_dot = str |> :binary.matches(".") |> List.last() |> elem(0)
        last_comma = str |> :binary.matches(",") |> List.last() |> elem(0)
        if last_dot > last_comma do
          str |> String.replace(",", "") |> Float.parse()
        else
          str |> String.replace(".", "") |> String.replace(",", ".") |> Float.parse()
        end
      String.contains?(str, ",") ->
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

  defp format_usd(nil), do: "—"
  defp format_usd(val), do: "$#{:erlang.float_to_binary(val * 1.0, decimals: 0)}"

  defp format_sp500(val), do: :erlang.float_to_binary(val * 1.0, decimals: 2)
end
