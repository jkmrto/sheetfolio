defmodule SheetfolioWeb.DcaBitcoinLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.BitcoinDca
  alias Sheetfolio.PriceFetcher
  alias Sheetfolio.PricesApi.YahooFinance

  @isin "GB00BJYDH287"
  @ranges ~w(1m 3m 1y ytd all)

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket =
        assign(socket,
          authenticated: true,
          subtab: "bitcoin",
          buys: [],
          position: %{net_qty: 0.0, cost_basis: 0.0},
          current_price: nil,
          chart_data: [],
          range: "all"
        )

      if connected?(socket) do
        {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()
        all_ops = Sheetfolio.OperationsServer.get_operations() || []
        state_history = BitcoinDca.state_history(all_ops, eur_usd, eur_cad)
        buys = BitcoinDca.build_buys(state_history)

        etf_prices = fetch_etf_history(state_history)
        btc_prices = fetch_history("BTC-USD", state_history)
        chart_data = BitcoinDca.cumulative_series(state_history, etf_prices, btc_prices, eur_usd, eur_cad)

        Sheetfolio.EarningsServer.request_price(@isin, self())

        socket =
          socket
          |> assign(buys: buys, position: position(state_history), chart_data: chart_data)
          |> push_chart(chart_data, "all")

        {:ok, socket}
      else
        {:ok, socket}
      end
    end
  end

  defp position([]), do: %{net_qty: 0.0, cost_basis: 0.0}
  defp position(state_history), do: List.last(state_history)

  def handle_info({:price_result, _isin, nil}, socket), do: {:noreply, socket}

  def handle_info({:price_result, @isin, price_eur}, socket) do
    {:noreply,
     assign(socket,
       buys: BitcoinDca.price_buys(socket.assigns.buys, price_eur),
       current_price: price_eur
     )}
  end

  def handle_event("set_range", %{"range" => range}, socket) when range in @ranges do
    {:noreply,
     socket
     |> assign(range: range)
     |> push_chart(socket.assigns.chart_data, range)}
  end

  # The chart is driven by pushed events rather than a data attribute, so
  # narrowing the range means sending the shorter series again.
  defp push_chart(socket, chart_data, range) do
    data = filter_range(chart_data, range)

    push_event(socket, "update_btc_dca_chart", %{
      labels: Enum.map(data, & &1.date),
      invested: Enum.map(data, & &1.invested),
      value: Enum.map(data, & &1.value),
      btc: Enum.map(data, & &1.btc)
    })
  end

  defp range_options, do: [{"1m", "1M"}, {"3m", "3M"}, {"1y", "1Y"}, {"ytd", "YTD"}, {"all", "All"}]

  defp filter_range(chart_data, "all"), do: chart_data

  defp filter_range(chart_data, range) do
    cutoff = range |> cutoff_date(Date.utc_today()) |> Date.to_iso8601()
    Enum.filter(chart_data, &(&1.date >= cutoff))
  end

  defp cutoff_date("1m", today), do: Date.shift(today, month: -1)
  defp cutoff_date("3m", today), do: Date.shift(today, month: -3)
  defp cutoff_date("1y", today), do: Date.shift(today, year: -1)
  defp cutoff_date("ytd", today), do: Date.new!(today.year, 1, 1)

  def render(assigns) do
    ~H"""
    <style>
      .dca-subtabs { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; border-bottom: 1px solid #e2e8f0; }
      .dca-subtabs a { border: none; background: none; color: #64748b; padding: 0.4rem 1.1rem; font-size: 0.95rem; cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -1px; text-decoration: none; }
      .dca-subtabs a:hover { color: #1e293b; }
      .dca-subtabs a.active { color: #1e293b; font-weight: 600; border-bottom-color: #1e293b; }
      .dca-table { width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-top: 2rem; }
      .dca-table th { background: #1e293b; color: white; padding: 0.75rem 1rem; text-align: left; font-size: 0.85rem; font-weight: 600; letter-spacing: 0.03em; position: sticky; top: 0; z-index: 1; }
      .dca-table th:not(:first-child) { text-align: right; }
      .dca-table td { padding: 0.65rem 1rem; border-bottom: 1px solid #f1f5f9; font-size: 0.9rem; font-variant-numeric: tabular-nums; }
      .dca-table td:not(:first-child) { text-align: right; }
      .dca-table tr:last-child td { border-bottom: none; }
      .dca-table tr:hover td { background: #f8fafc; }
      .dca-table tfoot td { background: #f8fafc; font-weight: 600; border-top: 2px solid #e2e8f0; }
      .positive { color: #16a34a; font-weight: 600; }
      .negative { color: #dc2626; font-weight: 600; }
      .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
      .card { background: white; border-radius: 12px; padding: 1.25rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .card-label { font-size: 0.78rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.4rem; }
      .card-value { font-size: 1.4rem; font-weight: 700; }
      .range-row { display: flex; margin-bottom: 1rem; }
      .range-toggle { display: flex; border: 1px solid #e2e8f0; border-radius: 6px; overflow: hidden; }
      .range-toggle button { border: none; background: white; color: #475569; padding: 0.35rem 0.8rem; font-size: 0.82rem; cursor: pointer; }
      .range-toggle button.selected { background: #1e293b; color: white; }
    </style>

    <div class="dca-subtabs">
      <.link navigate="/summary/dca" class={if @subtab == "sp500", do: "active", else: ""}>S&amp;P 500</.link>
      <.link navigate="/summary/dca/bitcoin" class={if @subtab == "bitcoin", do: "active", else: ""}>Bitcoin</.link>
    </div>

    <% buys = @buys %>
    <% total_invested = Float.round(@position.cost_basis, 2) %>
    <% total_units = @position.net_qty %>
    <% total_value = total_value(total_units, @current_price) %>
    <% total_pnl = total_pnl(total_value, total_invested) %>
    <% total_pnl_pct = total_pnl_pct(total_pnl, total_invested) %>
    <% avg_cost = avg_cost(total_invested, total_units) %>

    <div class="cards">
      <div class="card">
        <div class="card-label">Total Invested</div>
        <div class="card-value"><%= format_eur(total_invested) %></div>
      </div>
      <div class="card">
        <div class="card-label">Current Value</div>
        <div class="card-value"><%= format_eur(total_value) %></div>
      </div>
      <div class="card">
        <div class="card-label">Gain / Loss</div>
        <div class={"card-value #{earnings_class(total_pnl)}"}><%= format_abs(total_pnl) %></div>
      </div>
      <div class="card">
        <div class="card-label">Return</div>
        <div class={"card-value #{earnings_class(total_pnl_pct)}"}><%= format_pct(total_pnl_pct) %></div>
      </div>
      <div class="card">
        <div class="card-label">Units Held</div>
        <div class="card-value"><%= format_units(total_units) %></div>
      </div>
      <div class="card">
        <div class="card-label">Avg Cost / Unit</div>
        <div class="card-value"><%= format_eur(avg_cost) %></div>
      </div>
      <div class="card">
        <div class="card-label">Number of Buys</div>
        <div class="card-value"><%= length(buys) %></div>
      </div>
    </div>

    <div class="chart-container" style="margin-bottom: 2rem;">
      <div class="range-row">
        <div class="range-toggle">
          <%= for {value, label} <- range_options() do %>
            <button class={if @range == value, do: "selected"} phx-click="set_range" phx-value-range={value}><%= label %></button>
          <% end %>
        </div>
      </div>
      <canvas id="btc-dca-chart" phx-hook="DcaBitcoinChart" phx-update="ignore"></canvas>
    </div>

    <%= if buys != [] do %>
      <table class="dca-table">
        <thead>
          <tr>
            <th>Date</th>
            <th>Units</th>
            <th>Avg Cost (€)</th>
            <th>Invested (€)</th>
            <th>Value Now (€)</th>
            <th>Gain/Loss (€)</th>
            <th>Return (%)</th>
          </tr>
        </thead>
        <tbody>
          <%= for buy <- buys do %>
            <tr>
              <td style="white-space:nowrap"><%= buy.fecha %></td>
              <td><%= format_units(buy.units) %></td>
              <td><%= format_eur(buy.unit_cost) %></td>
              <td><%= format_eur(buy.invested) %></td>
              <td><%= format_eur(buy.value_now) %></td>
              <td class={earnings_class(buy.pnl)}><%= format_abs(buy.pnl) %></td>
              <td class={earnings_class(buy.pnl_pct)}><%= format_pct(buy.pnl_pct) %></td>
            </tr>
          <% end %>
        </tbody>
        <tfoot>
          <tr>
            <td colspan="3">Total</td>
            <td><%= format_eur(total_invested) %></td>
            <td><%= format_eur(total_value) %></td>
            <td class={earnings_class(total_pnl)}><%= format_abs(total_pnl) %></td>
            <td class={earnings_class(total_pnl_pct)}><%= format_pct(total_pnl_pct) %></td>
          </tr>
        </tfoot>
      </table>
    <% end %>
    """
  end

  defp fetch_etf_history(state_history) do
    case PriceFetcher.resolve_ticker(@isin) do
      {:ok, ticker} -> fetch_history(ticker, state_history)
      _ -> %{}
    end
  end

  defp fetch_history(_ticker, []), do: %{}

  defp fetch_history(ticker, state_history) do
    dates = Enum.map(state_history, &parse_op_date(&1.fecha))
    min_date = Enum.min(dates, Date)
    max_date = Date.utc_today()

    case YahooFinance.fetch_series(ticker, min_date, max_date) do
      {:ok, prices, _currency} -> prices
      _ -> %{}
    end
  end

  defp parse_op_date(fecha) do
    [d, m, y] = String.split(fecha, "/")
    Date.new!(String.to_integer(y), String.to_integer(m), String.to_integer(d))
  end

  defp total_value(_total_units, nil), do: nil
  defp total_value(total_units, price), do: Float.round(total_units * price, 2)

  defp total_pnl(nil, _total_invested), do: nil
  defp total_pnl(total_value, total_invested), do: Float.round(total_value - total_invested, 2)

  defp total_pnl_pct(nil, _total_invested), do: nil
  defp total_pnl_pct(_total_pnl, total_invested) when total_invested <= 0, do: nil
  defp total_pnl_pct(total_pnl, total_invested), do: Float.round(total_pnl / total_invested * 100, 2)

  defp avg_cost(_total_invested, total_units) when total_units == 0.0, do: 0.0
  defp avg_cost(total_invested, total_units), do: total_invested / total_units

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

  defp format_units(val), do: :erlang.float_to_binary(val * 1.0, decimals: 4)
end
