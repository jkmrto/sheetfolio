defmodule SheetfolioWeb.UrbanitaeLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.UrbanitaeTransactions

  @ranges ~w(1m 3m 1y ytd all)
  @views ~w(projects transactions)

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      transactions = if connected?(socket), do: UrbanitaeTransactions.all(), else: []

      {:ok,
       assign(socket,
         authenticated: true,
         transactions: transactions,
         range: "all",
         view: "projects"
       )}
    end
  end

  def handle_event("set_range", %{"range" => range}, socket) when range in @ranges do
    {:noreply, assign(socket, range: range)}
  end

  def handle_event("set_view", %{"view" => view}, socket) when view in @views do
    {:noreply, assign(socket, view: view)}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        rollup: UrbanitaeTransactions.rollup_by_project(assigns.transactions),
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
      .u-subtabs { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; border-bottom: 1px solid #e2e8f0; }
      .u-subtabs button { border: none; background: none; color: #64748b; padding: 0.4rem 1.1rem; font-size: 0.95rem; cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -1px; }
      .u-subtabs button:hover { color: #1e293b; }
      .u-subtabs button.active { color: #1e293b; font-weight: 600; border-bottom-color: #1e293b; }
      table.u-table { width: 100%; border-collapse: collapse; font-size: 0.87rem; }
      table.u-table th { text-align: left; font-weight: 600; color: #64748b; text-transform: uppercase; font-size: 0.72rem; letter-spacing: 0.03em; padding: 0.5rem 0.5rem; border-bottom: 1px solid #e2e8f0; }
      table.u-table td { padding: 0.55rem 0.5rem; border-bottom: 1px solid #f1f5f9; }
      table.u-table td.num { text-align: right; font-variant-numeric: tabular-nums; }
      table.u-table th.num { text-align: right; }
      table.u-table td.pos, .u-totals .stat-value.pos, .stat-value.pos { color: #1baf7a; font-weight: 600; }
      table.u-table td.neg, .u-totals .stat-value.neg { color: #e34948; font-weight: 600; }
      .u-pill { display: inline-block; padding: 0.1rem 0.55rem; border-radius: 999px; font-size: 0.72rem; font-weight: 600; }
      .u-pill.active { background: #e0f2fe; color: #0369a1; }
      .u-pill.closed { background: #dcfce7; color: #166534; }
      .u-pill.investment { background: #fef3c7; color: #92400e; }
      .u-pill.repayment { background: #dcfce7; color: #166534; }
      .range-row { display: flex; margin-bottom: 1rem; }
      .range-toggle { display: flex; border: 1px solid #e2e8f0; border-radius: 6px; overflow: hidden; }
      .range-toggle button { border: none; background: white; color: #475569; padding: 0.35rem 0.8rem; font-size: 0.82rem; cursor: pointer; }
      .range-toggle button.selected { background: #1e293b; color: white; }
      .u-project { border: 1px solid #e2e8f0; border-radius: 10px; padding: 1rem 1.25rem; margin-bottom: 1rem; }
      .u-project-header { display: flex; align-items: baseline; gap: 0.75rem; margin-bottom: 0.75rem; flex-wrap: wrap; }
      .u-project-title { font-size: 1rem; font-weight: 600; color: #0f172a; }
      .u-project-city { color: #64748b; font-size: 0.85rem; }
      .u-project-stats { display: flex; gap: 1.75rem; flex-wrap: wrap; margin-bottom: 0.75rem; font-size: 0.85rem; }
      .u-project-stats .k { color: #64748b; margin-right: 0.35rem; }
      .u-project-stats .v { font-variant-numeric: tabular-nums; font-weight: 600; color: #0f172a; }
      .u-project-stats .v.pos { color: #1baf7a; }
      .u-project-stats .v.neg { color: #e34948; }
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

      <div class="u-subtabs">
        <button type="button" class={if @view == "projects", do: "active", else: ""} phx-click="set_view" phx-value-view="projects">
          Projects
        </button>
        <button type="button" class={if @view == "transactions", do: "active", else: ""} phx-click="set_view" phx-value-view="transactions">
          Transactions
        </button>
      </div>

      <%= if @view == "projects" do %>
        <%= render_projects(assigns) %>
      <% else %>
        <%= render_transactions(assigns) %>
      <% end %>
    <% end %>
    """
  end

  defp render_projects(assigns) do
    ~H"""
    <div class="u-card">
      <%= for r <- @rollup do %>
        <% project_txs = project_transactions(@transactions, r.project_key) %>
        <div class="u-project">
          <div class="u-project-header">
            <span class={"u-pill #{r.status}"}>{r.status}</span>
            <span class="u-project-title">{r.project}</span>
            <span class="u-project-city">{r.city}</span>
          </div>
          <div class="u-project-stats">
            <span><span class="k">Invested</span><span class="v">{format_eur(r.invested)}</span></span>
            <span><span class="k">Returned</span><span class="v">{format_eur(r.returned)}</span></span>
            <span><span class="k">Outstanding</span><span class="v">{format_eur(r.outstanding)}</span></span>
            <span><span class="k">Net P&amp;L</span><span class={"v #{pnl_class(r.net_pnl)}"}>{format_eur(r.net_pnl)}</span></span>
          </div>
          <table class="u-table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Kind</th>
                <th class="num">Amount</th>
              </tr>
            </thead>
            <tbody>
              <%= for tx <- project_txs do %>
                <tr>
                  <td>{tx["date"]}</td>
                  <td><span class={"u-pill #{tx["kind"]}"}>{tx["kind"]}</span></td>
                  <td class="num">{format_eur(tx["amount"])}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_transactions(assigns) do
    assigns = assign(assigns, rows: filter_range(assigns.transactions, assigns.range))

    ~H"""
    <div class="u-card">
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
    """
  end

  defp project_transactions(transactions, project_key) do
    transactions
    |> Enum.filter(&(&1["project_key"] == project_key))
    |> Enum.sort_by(& &1["date"], :desc)
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
