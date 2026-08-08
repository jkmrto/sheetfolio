defmodule SheetfolioWeb.EquitoLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.{EquitoProperties, EquitoTransactions}

  @ranges ~w(1w 1m 3m 1y ytd all)
  @views ~w(overview properties movements)

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      {transactions, properties} =
        if connected?(socket) do
          {EquitoTransactions.all(), EquitoProperties.all()}
        else
          {[], []}
        end

      {:ok,
       assign(socket,
         authenticated: true,
         transactions: transactions,
         properties: properties,
         range: "1m",
         # The movements list is a record rather than a chart, so it opens on
         # the full history instead of the chart's last-month window.
         tx_range: "all",
         view: "overview"
       )}
    end
  end

  def handle_event("set_range", %{"range" => range}, socket) when range in @ranges do
    {:noreply, assign(socket, range: range)}
  end

  def handle_event("set_tx_range", %{"range" => range}, socket) when range in @ranges do
    {:noreply, assign(socket, tx_range: range)}
  end

  def handle_event("set_view", %{"view" => view}, socket) when view in @views do
    {:noreply, assign(socket, view: view)}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        totals: EquitoTransactions.totals(assigns.transactions),
        rollup: EquitoTransactions.rollup_by_property(assigns.transactions)
      )

    ~H"""
    <style>
      .e-empty { background: white; border-radius: 12px; padding: 2rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); color: #64748b; font-size: 0.9rem; line-height: 1.6; }
      .e-empty code { background: #f1f5f9; padding: 0.1rem 0.35rem; border-radius: 4px; font-size: 0.85rem; }
      .e-card { background: white; border-radius: 12px; padding: 1.5rem 1.75rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 1.5rem; }
      .e-card h2 { font-size: 1rem; font-weight: 600; margin-bottom: 1rem; color: #0f172a; }
      .e-totals { display: flex; gap: 2.5rem; flex-wrap: wrap; }
      .e-totals .stat { display: flex; flex-direction: column; gap: 0.25rem; }
      .e-totals .stat-label { font-size: 0.75rem; color: #64748b; text-transform: uppercase; letter-spacing: 0.03em; }
      .e-totals .stat-value { font-size: 1.4rem; font-weight: 600; color: #0f172a; }
      .e-totals .stat-value.pos { color: #1baf7a; }
      .e-totals .stat-value.neg { color: #e34948; }
      .e-totals .stat-note { font-size: 0.78rem; color: #94a3b8; }
      .e-subtabs { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; border-bottom: 1px solid #e2e8f0; }
      .e-subtabs button { border: none; background: none; color: #64748b; padding: 0.4rem 1.1rem; font-size: 0.95rem; cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -1px; }
      .e-subtabs button:hover { color: #1e293b; }
      .e-subtabs button.active { color: #1e293b; font-weight: 600; border-bottom-color: #1e293b; }
      table.e-table { width: 100%; border-collapse: collapse; font-size: 0.87rem; }
      table.e-table th { text-align: left; font-weight: 600; color: #64748b; text-transform: uppercase; font-size: 0.72rem; letter-spacing: 0.03em; padding: 0.5rem 0.5rem; border-bottom: 1px solid #e2e8f0; }
      table.e-table td { padding: 0.55rem 0.5rem; border-bottom: 1px solid #f1f5f9; }
      table.e-table td.num, table.e-table th.num { text-align: right; }
      table.e-table td.num { font-variant-numeric: tabular-nums; }
      table.e-table td.code { font-weight: 600; color: #0f172a; white-space: nowrap; }
      table.e-table tfoot td { font-weight: 600; border-top: 2px solid #e2e8f0; }
      .e-pill { display: inline-block; padding: 0.1rem 0.55rem; border-radius: 999px; font-size: 0.72rem; font-weight: 600; }
      .e-pill.purchase { background: #ede9fe; color: #6d28d9; }
      .e-pill.rent { background: #dcfce7; color: #166534; }
      .e-pill.tax { background: #fee2e2; color: #b91c1c; }
      .e-pill.reward { background: #fef3c7; color: #92400e; }
      .e-pill.alquilado { background: #dcfce7; color: #166534; }
      .range-row { display: flex; margin-bottom: 1rem; }
      .range-toggle { display: flex; border: 1px solid #e2e8f0; border-radius: 6px; overflow: hidden; }
      .range-toggle button { border: none; background: white; color: #475569; padding: 0.35rem 0.8rem; font-size: 0.82rem; cursor: pointer; }
      .range-toggle button.selected { background: #1e293b; color: white; }
    </style>

    <%= if @transactions == [] and @properties == [] do %>
      <div class="e-empty">
        No Equito data recorded yet. Share the <strong>Mis propiedades</strong> and
        <strong>Historial</strong> screenshots and they get ingested into the
        <code>equito_properties</code> and <code>equito_transactions</code> collections.
      </div>
    <% else %>
      <div class="e-card">
        <h2>Overall</h2>
        <div class="e-totals">
          <div class="stat">
            <span class="stat-label">Invested</span>
            <span class="stat-value">{format_eur(@totals.invested)}</span>
            <span class="stat-note">{@totals.properties} {pluralize(@totals.properties, "property", "properties")}</span>
          </div>
          <div class="stat">
            <span class="stat-label">Net distributed</span>
            <span class={"stat-value #{pnl_class(@totals.net_income)}"}>{format_eur(@totals.net_income)}</span>
            <span class="stat-note">
              {format_eur(@totals.rent_gross)} rent · {format_eur(@totals.tax_withheld)} withheld
            </span>
          </div>
          <div class="stat">
            <span class="stat-label">Yield on cost</span>
            <span class="stat-value">{format_pct(yield_on_cost(@totals))}</span>
            <span class="stat-note">net, since the first purchase</span>
          </div>
          <%= if @totals.rewards != 0.0 do %>
            <div class="stat">
              <span class="stat-label">Rewards</span>
              <span class="stat-value pos">{format_eur(@totals.rewards)}</span>
            </div>
          <% end %>
        </div>
      </div>

      <div class="e-subtabs">
        <button type="button" class={if @view == "overview", do: "active", else: ""} phx-click="set_view" phx-value-view="overview">
          Overview
        </button>
        <button type="button" class={if @view == "properties", do: "active", else: ""} phx-click="set_view" phx-value-view="properties">
          Properties
        </button>
        <button type="button" class={if @view == "movements", do: "active", else: ""} phx-click="set_view" phx-value-view="movements">
          Movements
        </button>
      </div>

      <%= cond do %>
        <% @view == "overview" -> %>
          {render_overview(assigns)}
        <% @view == "properties" -> %>
          {render_properties(assigns)}
        <% true -> %>
          {render_movements(assigns)}
      <% end %>
    <% end %>
    """
  end

  defp render_overview(assigns) do
    assigns = assign(assigns, chart_payload: chart_payload(assigns.transactions, assigns.range))

    ~H"""
    <div class="e-card">
      <div class="range-row">
        <div class="range-toggle">
          <%= for {value, label} <- range_options() do %>
            <button class={if @range == value, do: "selected"} phx-click="set_range" phx-value-range={value}>{label}</button>
          <% end %>
        </div>
      </div>
      <div id="equito-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(@chart_payload)}>
        <div id="equito-chart-canvas" phx-update="ignore">
          <canvas id="equitoChartCanvas"></canvas>
        </div>
      </div>
    </div>

    <div class="e-card">
      <h2>Distribution per property</h2>
      <%= if @rollup == [] do %>
        <p style="color:#64748b; font-size:0.85rem;">No movements recorded yet.</p>
      <% else %>
        <table class="e-table">
          <thead>
            <tr>
              <th>Property</th>
              <th class="num">Tokens</th>
              <th class="num">Invested</th>
              <th class="num">Rent</th>
              <th class="num">Withheld</th>
              <th class="num">Net</th>
              <th class="num">Payouts</th>
            </tr>
          </thead>
          <tbody>
            <%= for row <- @rollup do %>
              <tr>
                <td class="code">{row.code}<%= if city_of(@properties, row.code), do: " · #{city_of(@properties, row.code)}" %></td>
                <td class="num">{row.tokens}</td>
                <td class="num">{format_eur(row.invested)}</td>
                <td class="num">{format_eur(row.rent_gross)}</td>
                <td class="num">{format_eur(row.tax_withheld)}</td>
                <td class="num">{format_eur(row.net_income)}</td>
                <td class="num">{row.payouts}</td>
              </tr>
            <% end %>
          </tbody>
          <tfoot>
            <tr>
              <td>Total</td>
              <td class="num"></td>
              <td class="num">{format_eur(@totals.invested)}</td>
              <td class="num">{format_eur(@totals.rent_gross)}</td>
              <td class="num">{format_eur(@totals.tax_withheld)}</td>
              <td class="num">{format_eur(@totals.net_income)}</td>
              <td class="num"></td>
            </tr>
          </tfoot>
        </table>
      <% end %>
    </div>
    """
  end

  defp render_properties(assigns) do
    ~H"""
    <div class="e-card">
      <%= if @properties == [] do %>
        <p style="color:#64748b; font-size:0.85rem;">No properties recorded yet.</p>
      <% else %>
        <table class="e-table">
          <thead>
            <tr>
              <th>Property</th>
              <th>City</th>
              <th class="num">Surface</th>
              <th>Status</th>
              <th class="num">Rentabilidad</th>
              <th class="num">Distribuido</th>
            </tr>
          </thead>
          <tbody>
            <%= for property <- @properties do %>
              <tr>
                <td class="code">{property["code"]}</td>
                <td>{property["city"]}</td>
                <td class="num">{property["surface_m2"]} m²</td>
                <td><span class={"e-pill #{status_class(property["status"])}"}>{property["status"]}</span></td>
                <td class="num">{format_pct(property["yield_pct"])}</td>
                <td class="num">{format_pct(property["distributed_pct"])}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  defp render_movements(assigns) do
    assigns = assign(assigns, rows: filter_range(assigns.transactions, assigns.tx_range))

    ~H"""
    <div class="e-card">
      <div class="range-row">
        <div class="range-toggle">
          <%= for {value, label} <- range_options() do %>
            <button class={if @tx_range == value, do: "selected"} phx-click="set_tx_range" phx-value-range={value}>{label}</button>
          <% end %>
        </div>
      </div>
      <%= if @rows == [] do %>
        <p style="color:#64748b; font-size:0.85rem;">No movements in this window.</p>
      <% else %>
        <table class="e-table">
          <thead>
            <tr>
              <th>Date</th>
              <th>Property</th>
              <th>Kind</th>
              <th class="num">Amount</th>
            </tr>
          </thead>
          <tbody>
            <%= for tx <- @rows do %>
              <tr>
                <td>{tx["date"]}</td>
                <td class="code">{tx["code"] || "—"}</td>
                <td><span class={"e-pill #{tx["kind"]}"}>{tx["raw_label"] || tx["kind"]}</span></td>
                <td class="num">{format_eur(tx["amount"])}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  defp chart_payload(transactions, range) do
    series = transactions |> EquitoTransactions.time_series() |> filter_series(range)

    %{
      metric: "value",
      title: "Invested and net distributions (€)",
      datasets: [
        %{
          label: "Invested",
          color: "#2a78d6",
          data: Enum.map(series, &%{x: &1.date, y: &1.invested})
        },
        %{
          label: "Net distributed",
          color: "#1baf7a",
          data: Enum.map(series, &%{x: &1.date, y: &1.net_income})
        }
      ]
    }
  end

  defp city_of(properties, code) do
    Enum.find_value(properties, fn property ->
      if property["code"] == code, do: property["city"]
    end)
  end

  defp yield_on_cost(%{invested: invested}) when invested in [0, 0.0], do: nil
  defp yield_on_cost(%{invested: invested, net_income: net}), do: net / invested * 100

  defp status_class(nil), do: ""
  defp status_class(status), do: status |> String.downcase() |> String.replace(" ", "-")

  defp range_options,
    do: [{"1w", "1W"}, {"1m", "1M"}, {"3m", "3M"}, {"1y", "1Y"}, {"ytd", "YTD"}, {"all", "All"}]

  defp filter_series(series, "all"), do: series

  defp filter_series(series, range) do
    cutoff = range |> cutoff_date(Date.utc_today()) |> Date.to_iso8601()
    Enum.filter(series, &(&1.date >= cutoff))
  end

  defp filter_range(transactions, "all"), do: transactions

  defp filter_range(transactions, range) do
    cutoff = range |> cutoff_date(Date.utc_today()) |> Date.to_iso8601()
    Enum.filter(transactions, &(&1["date"] >= cutoff))
  end

  defp cutoff_date("1w", today), do: Date.shift(today, day: -7)
  defp cutoff_date("1m", today), do: Date.shift(today, month: -1)
  defp cutoff_date("3m", today), do: Date.shift(today, month: -3)
  defp cutoff_date("1y", today), do: Date.shift(today, year: -1)
  defp cutoff_date("ytd", today), do: Date.new!(today.year, 1, 1)

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_count, _singular, plural), do: plural

  defp pnl_class(amount) when amount > 0, do: "pos"
  defp pnl_class(amount) when amount < 0, do: "neg"
  defp pnl_class(_amount), do: ""

  defp format_pct(nil), do: "—"
  defp format_pct(pct), do: "#{:erlang.float_to_binary(pct * 1.0, decimals: 2)}%"

  defp format_eur(amount) do
    sign = if amount < 0, do: "-", else: ""
    abs_amount = abs(amount)
    whole = trunc(abs_amount)
    cents = round((abs_amount - whole) * 100)

    whole_str =
      whole
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
      |> String.reverse()

    cents_str = cents |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{sign}#{whole_str},#{cents_str} €"
  end
end
