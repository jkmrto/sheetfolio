defmodule SheetfolioWeb.BitcoinLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.BitcoinDca
  alias Sheetfolio.BitcoinExposure
  alias Sheetfolio.CryptoHoldings
  alias Sheetfolio.PricesApi.YahooFinance

  @isin "GB00BJYDH287"
  @chart_from ~D[2025-01-01]

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket =
        assign(socket,
          authenticated: true,
          etp: %{net_qty: 0.0, cost_basis: 0.0},
          etp_price: nil,
          coinbase: CryptoHoldings.position([], nil),
          btc_price: nil,
          exposure: nil
        )

      if connected?(socket), do: {:ok, load(socket)}, else: {:ok, socket}
    end
  end

  defp load(socket) do
    {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()
    operations = Sheetfolio.OperationsServer.get_operations() || []

    Sheetfolio.EarningsServer.request_price(@isin, self())
    request_btc_price()
    request_exposure()

    assign(socket,
      etp: etp_position(BitcoinDca.state_history(operations, eur_usd, eur_cad)),
      coinbase: CryptoHoldings.position(CryptoHoldings.by_symbol("BTC"), nil)
    )
  end

  defp etp_position([]), do: %{net_qty: 0.0, cost_basis: 0.0}
  defp etp_position(state_history), do: List.last(state_history)

  # BTC is not an ISIN, so it can't go through EarningsServer's ISIN→ticker
  # resolution; the spot pair is quoted directly.
  defp request_btc_price do
    caller = self()

    Task.Supervisor.start_child(Sheetfolio.TaskSupervisor, fn ->
      send(caller, {:btc_price, YahooFinance.fetch_price("BTC-EUR")})
    end)
  end

  def handle_info({:btc_price, {:ok, price, _currency}}, socket) do
    {:noreply,
     assign(socket,
       btc_price: price,
       coinbase: CryptoHoldings.position(CryptoHoldings.by_symbol("BTC"), price)
     )}
  end

  def handle_info({:btc_price, _error}, socket), do: {:noreply, socket}

  def handle_info({:exposure, series}, socket), do: {:noreply, assign(socket, exposure: series)}

  def handle_info({:price_result, @isin, price_eur}, socket) do
    {:noreply, assign(socket, etp_price: price_eur)}
  end

  def handle_info({:price_result, _isin, _price}, socket), do: {:noreply, socket}

  # The snapshots and the price series are both slow reads, so the page paints
  # its totals first and the chart arrives after.
  defp request_exposure do
    caller = self()

    Task.Supervisor.start_child(Sheetfolio.TaskSupervisor, fn ->
      send(caller, {:exposure, build_exposure()})
    end)
  end

  defp build_exposure do
    units = CryptoHoldings.by_symbol("BTC") |> Enum.reduce(0.0, &(&1["units"] + &2))
    BitcoinExposure.series(snapshots_since(@chart_from), btc_series(), units, @isin)
  end

  defp btc_series do
    case YahooFinance.fetch_series("BTC-EUR", @chart_from, Date.utc_today()) do
      {:ok, prices, _currency} -> prices
      _ -> %{}
    end
  end

  defp snapshots_since(from) do
    :mongo
    |> Mongo.find("portfolio_snapshots", %{date: %{"$gte" => Date.to_iso8601(from)}},
      sort: %{date: 1}
    )
    |> Enum.to_list()
  end

  defp chart_payload(series) do
    %{
      stacked: true,
      labels: Enum.map(series, & &1.date),
      datasets: [
        %{label: "Coinbase — spot BTC", color: "#f7931a", data: Enum.map(series, & &1.coinbase)},
        %{label: "WisdomTree Bitcoin ETP", color: "#1e40af", data: Enum.map(series, & &1.etp)}
      ]
    }
  end

  def render(assigns) do
    assigns = assign(assigns, totals: totals(assigns))

    ~H"""
    <style>
      .btc-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
      .btc-card { background: white; border-radius: 12px; padding: 1.25rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .btc-card-label { font-size: 0.78rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.4rem; }
      .btc-card-value { font-size: 1.4rem; font-weight: 700; }
      .btc-section { margin: 1.5rem 0 0.5rem; font-size: 1.1rem; font-weight: 600; color: #334155; }
      .btc-note { color: #64748b; font-size: 0.82rem; margin-bottom: 0.75rem; }
      .btc-table { width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .btc-table th { background: #1e293b; color: white; padding: 0.6rem 1rem; text-align: right; font-size: 0.85rem; font-weight: 600; }
      .btc-table th:first-child, .btc-table td:first-child { text-align: left; }
      .btc-table td { padding: 0.6rem 1rem; border-bottom: 1px solid #f1f5f9; font-size: 0.9rem; text-align: right; font-variant-numeric: tabular-nums; }
      .btc-table tr:last-child td { border-bottom: none; }
      .btc-table tr.sum td { font-weight: 700; background: #f1f5f9; border-top: 2px solid #1e293b; }
      .btc-pos { color: #16a34a; font-weight: 600; }
      .btc-neg { color: #dc2626; font-weight: 600; }
      .btc-link { display: inline-block; margin-top: 1.25rem; color: #2563eb; font-size: 0.9rem; }
      .btc-chart-card { background: white; border-radius: 12px; padding: 1.25rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 1rem; }
      .btc-loading { color: #64748b; font-size: 0.9rem; padding: 2rem 0; text-align: center; }
    </style>

    <div class="btc-cards">
      <div class="btc-card">
        <div class="btc-card-label">Total Invested</div>
        <div class="btc-card-value"><%= eur(@totals.cost_basis) %></div>
      </div>
      <div class="btc-card">
        <div class="btc-card-label">Current Value</div>
        <div class="btc-card-value"><%= eur_or_dash(@totals.value) %></div>
      </div>
      <div class="btc-card">
        <div class="btc-card-label">Unrealized</div>
        <div class={"btc-card-value #{sign_class(@totals.unrealized)}"}>
          <%= eur_or_dash(@totals.unrealized) %>
        </div>
      </div>
      <div class="btc-card">
        <div class="btc-card-label">BTC Spot</div>
        <div class="btc-card-value"><%= eur_or_dash(@btc_price) %></div>
      </div>
    </div>

    <div class="btc-section">Exposure since 2025</div>
    <div class="btc-chart-card">
      <%= if @exposure == nil do %>
        <div class="btc-loading">Loading exposure history…</div>
      <% else %>
        <div id="btc-exposure-chart" phx-hook="CategoryHistoryChart" data-chart={Jason.encode!(chart_payload(@exposure))}>
          <div id="btc-exposure-canvas" phx-update="ignore">
            <canvas></canvas>
          </div>
        </div>
      <% end %>
    </div>

    <div class="btc-section">Exposure</div>
    <div class="btc-note">
      The WisdomTree ETP tracks Bitcoin but is held in ETP units, not coins, so
      only the euro side of the two is comparable.
    </div>
    <table class="btc-table">
      <tr>
        <th>Holding</th><th>Units</th><th>Invested</th><th>Value</th><th>Unrealized</th>
      </tr>
      <tr>
        <td>Coinbase — spot BTC</td>
        <td><%= btc(@coinbase.units) %> BTC</td>
        <td><%= eur(@coinbase.cost_basis) %></td>
        <td><%= eur_or_dash(@coinbase.value) %></td>
        <td class={sign_class(@coinbase.unrealized)}><%= eur_or_dash(@coinbase.unrealized) %></td>
      </tr>
      <tr>
        <td>WisdomTree Bitcoin ETP</td>
        <td><%= units(@etp.net_qty) %></td>
        <td><%= eur(@etp.cost_basis) %></td>
        <td><%= eur_or_dash(etp_value(@etp, @etp_price)) %></td>
        <td class={sign_class(etp_unrealized(@etp, @etp_price))}>
          <%= eur_or_dash(etp_unrealized(@etp, @etp_price)) %>
        </td>
      </tr>
      <tr class="sum">
        <td>Total</td>
        <td>—</td>
        <td><%= eur(@totals.cost_basis) %></td>
        <td><%= eur_or_dash(@totals.value) %></td>
        <td class={sign_class(@totals.unrealized)}><%= eur_or_dash(@totals.unrealized) %></td>
      </tr>
    </table>

    <%= for row <- @coinbase.holdings do %>
      <div class="btc-section">{row.platform} detail</div>
      <table class="btc-table">
        <tr><th>Metric</th><th>Value</th></tr>
        <tr><td>Units held</td><td><%= btc(row.units) %> BTC</td></tr>
        <tr><td>Average cost</td><td><%= eur(row.avg_cost) %> / BTC</td></tr>
        <tr><td>Cost basis</td><td><%= eur(row.cost_basis) %></td></tr>
        <tr><td>Current value</td><td><%= eur_or_dash(row.value) %></td></tr>
        <tr>
          <td>Unrealized</td>
          <td class={sign_class(row.unrealized)}><%= eur_or_dash(row.unrealized) %></td>
        </tr>
      </table>
    <% end %>

    <.link navigate="/summary/dca/bitcoin" class="btc-link">
      See the ETP's DCA history and chart →
    </.link>
    """
  end

  defp totals(assigns) do
    etp_value = etp_value(assigns.etp, assigns.etp_price)
    cost_basis = assigns.coinbase.cost_basis + assigns.etp.cost_basis
    value = add(assigns.coinbase.value, etp_value)

    %{
      cost_basis: Float.round(cost_basis, 2),
      value: value,
      unrealized: unrealized(value, cost_basis)
    }
  end

  defp unrealized(nil, _cost_basis), do: nil
  defp unrealized(value, cost_basis), do: Float.round(value - cost_basis, 2)

  defp add(nil, _second), do: nil
  defp add(_first, nil), do: nil
  defp add(first, second), do: Float.round(first + second, 2)

  defp etp_value(_etp, nil), do: nil
  defp etp_value(etp, price), do: Float.round(etp.net_qty * price, 2)

  defp etp_unrealized(_etp, nil), do: nil
  defp etp_unrealized(etp, price), do: Float.round(etp.net_qty * price - etp.cost_basis, 2)

  defp eur_or_dash(nil), do: "—"
  defp eur_or_dash(value), do: eur(value)

  defp eur(value) do
    [int, dec] =
      Float.round(value / 1, 2)
      |> :erlang.float_to_binary(decimals: 2)
      |> String.split(".")

    "#{String.replace(int, ~r/(?<=\d)(?=(\d{3})+$)/, ".")},#{dec} €"
  end

  defp btc(units), do: :erlang.float_to_binary(units * 1.0, decimals: 8)
  defp units(qty), do: :erlang.float_to_binary(qty * 1.0, decimals: 2)

  defp sign_class(nil), do: ""
  defp sign_class(value) when value < 0, do: "btc-neg"
  defp sign_class(_value), do: "btc-pos"
end
