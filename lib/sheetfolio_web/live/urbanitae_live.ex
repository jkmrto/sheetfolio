defmodule SheetfolioWeb.UrbanitaeLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.UrbanitaeTransactions

  @ranges ~w(1m 3m 1y ytd all)

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      transactions = if connected?(socket), do: UrbanitaeTransactions.all(), else: []
      {:ok, assign(socket, authenticated: true, transactions: transactions, range: "all")}
    end
  end

  def handle_event("set_range", %{"range" => range}, socket) when range in @ranges do
    {:noreply, assign(socket, range: range)}
  end

  def render(assigns) do
    filtered = filter_range(assigns.transactions, assigns.range)

    assigns =
      assign(assigns,
        rollup: UrbanitaeTransactions.rollup_by_project(assigns.transactions),
        rows: filtered,
        totals: totals(assigns.transactions)
      )

    ~H"""
    <style>
      .u-empty { background: white; border-radius: 12px; padding: 2rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); color: #64748b; font-size: 0.9rem; }
      .u-card { background: white; border-radius: 12px; padding: 1.5rem 1.75rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 1.5rem; }
      .u-card h2 { font-size: 1rem; font-weight: 600; margin-bottom: 1rem; color: #0f172a; }
      .u-totals { display: flex; gap: 2.5rem; flex-wrap: wrap; }
      .u-totals .stat { display: flex; flex-direction: column; gap: 0.25rem; }
      .u-totals .stat-label { font-size: 0.75rem; color: #64748b; text-transform: uppercase; letter-spacing: 0.03em; }
      .u-totals .stat-value { font-size: 1.4rem; font-weight: 600; color: #0f172a; }
      .u-totals .stat-value.pos { color: #1baf7a; }
      .u-totals .stat-value.neg { color: #e34948; }
      table.u-table { width: 100%; border-collapse: collapse; font-size: 0.87rem; }
      table.u-table th { text-align: left; font-weight: 600; color: #64748b; text-transform: uppercase; font-size: 0.72rem; letter-spacing: 0.03em; padding: 0.5rem 0.5rem; border-bottom: 1px solid #e2e8f0; }
      table.u-table td { padding: 0.55rem 0.5rem; border-bottom: 1px solid #f1f5f9; }
      table.u-table td.num { text-align: right; font-variant-numeric: tabular-nums; }
      table.u-table td.pos { color: #1baf7a; font-weight: 600; }
      table.u-table td.neg { color: #e34948; font-weight: 600; }
      .u-pill { display: inline-block; padding: 0.1rem 0.55rem; border-radius: 999px; font-size: 0.72rem; font-weight: 600; }
      .u-pill.active { background: #e0f2fe; color: #0369a1; }
      .u-pill.closed { background: #dcfce7; color: #166534; }
      .u-pill.investment { background: #fef3c7; color: #92400e; }
      .u-pill.repayment { background: #dcfce7; color: #166534; }
      .range-row { display: flex; margin-bottom: 1rem; }
      .range-toggle { display: flex; border: 1px solid #e2e8f0; border-radius: 6px; overflow: hidden; }
      .range-toggle button { border: none; background: white; color: #475569; padding: 0.35rem 0.8rem; font-size: 0.82rem; cursor: pointer; }
      .range-toggle button.selected { background: #1e293b; color: white; }
    </style>

    <%= if @transactions == [] do %>
      <div class="u-empty">
        No Urbanitae transactions recorded yet. Share Movimientos screenshots and I'll ingest them via the <code>urbanitae-ingest</code> skill.
      </div>
    <% else %>
      <div class="u-card">
        <h2>Overall</h2>
        <div class="u-totals">
          <div class="stat">
            <span class="stat-label">Invested</span>
            <span class="stat-value">{format_eur(@totals.invested)}</span>
          </div>
          <div class="stat">
            <span class="stat-label">Returned</span>
            <span class="stat-value">{format_eur(@totals.returned)}</span>
          </div>
          <div class="stat">
            <span class="stat-label">Outstanding</span>
            <span class="stat-value">{format_eur(@totals.outstanding)}</span>
          </div>
          <div class="stat">
            <span class="stat-label">Net P&amp;L (closed projects)</span>
            <span class={"stat-value #{pnl_class(@totals.closed_pnl)}"}>{format_eur(@totals.closed_pnl)}</span>
          </div>
        </div>
      </div>

      <div class="u-card">
        <h2>Projects</h2>
        <table class="u-table">
          <thead>
            <tr>
              <th>Status</th>
              <th>City</th>
              <th>Project</th>
              <th class="num">Invested</th>
              <th class="num">Returned</th>
              <th class="num">Outstanding</th>
              <th class="num">Net P&amp;L</th>
              <th class="num">Txs</th>
              <th>First → Last</th>
            </tr>
          </thead>
          <tbody>
            <%= for r <- @rollup do %>
              <tr>
                <td><span class={"u-pill #{r.status}"}>{r.status}</span></td>
                <td>{r.city}</td>
                <td>{r.project}</td>
                <td class="num">{format_eur(r.invested)}</td>
                <td class="num">{format_eur(r.returned)}</td>
                <td class="num">{format_eur(r.outstanding)}</td>
                <td class={"num #{pnl_class(r.net_pnl)}"}>{format_eur(r.net_pnl)}</td>
                <td class="num">{r.tx_count}</td>
                <td>{r.first_date} → {r.last_date}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <div class="u-card">
        <h2>Transactions</h2>
        <div class="range-row">
          <div class="range-toggle">
            <%= for {value, label} <- range_options() do %>
              <button class={if @range == value, do: "selected"} phx-click="set_range" phx-value-range={value}>{label}</button>
            <% end %>
          </div>
        </div>
        <%= if @rows == [] do %>
          <p style="color:#64748b; font-size:0.85rem;">No transactions in this window.</p>
        <% else %>
          <table class="u-table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Kind</th>
                <th>City</th>
                <th>Project</th>
                <th class="num">Amount</th>
              </tr>
            </thead>
            <tbody>
              <%= for tx <- @rows do %>
                <tr>
                  <td>{tx["date"]}</td>
                  <td><span class={"u-pill #{tx["kind"]}"}>{tx["kind"]}</span></td>
                  <td>{tx["city"]}</td>
                  <td>{tx["project"]}</td>
                  <td class="num">{format_eur(tx["amount"])}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp totals(transactions) do
    rollup = UrbanitaeTransactions.rollup_by_project(transactions)
    invested = Enum.reduce(rollup, 0.0, &(&1.invested + &2))
    returned = Enum.reduce(rollup, 0.0, &(&1.returned + &2))

    closed_pnl =
      rollup
      |> Enum.filter(&(&1.status == "closed"))
      |> Enum.reduce(0.0, &(&1.net_pnl + &2))

    %{
      invested: Float.round(invested, 2),
      returned: Float.round(returned, 2),
      outstanding: Float.round(invested - returned, 2),
      closed_pnl: Float.round(closed_pnl, 2)
    }
  end

  defp range_options, do: [{"1m", "1M"}, {"3m", "3M"}, {"1y", "1Y"}, {"ytd", "YTD"}, {"all", "All"}]

  defp filter_range(transactions, "all"), do: transactions

  defp filter_range(transactions, range) do
    cutoff = range |> cutoff_date(Date.utc_today()) |> Date.to_iso8601()
    Enum.filter(transactions, &(&1["date"] >= cutoff))
  end

  defp cutoff_date("1m", today), do: Date.shift(today, month: -1)
  defp cutoff_date("3m", today), do: Date.shift(today, month: -3)
  defp cutoff_date("1y", today), do: Date.shift(today, year: -1)
  defp cutoff_date("ytd", today), do: Date.new!(today.year, 1, 1)

  defp pnl_class(amount) when amount > 0, do: "pos"
  defp pnl_class(amount) when amount < 0, do: "neg"
  defp pnl_class(_), do: ""

  defp format_eur(amount) do
    # es-ES style: "." thousands, "," decimals.
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
