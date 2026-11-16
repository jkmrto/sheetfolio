defmodule SheetfolioWeb.SavingsLive do
  use SheetfolioWeb, :live_view

  alias SheetfolioWeb.NumberFormat

  alias Sheetfolio.MonthlySavings

  @month_labels ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      rows = if connected?(socket), do: MonthlySavings.all(), else: []
      {:ok, assign(socket, authenticated: true, rows: rows)}
    end
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        totals: MonthlySavings.year_totals(assigns.rows, latest_year(assigns.rows)),
        chart_payload: chart_payload(assigns.rows)
      )

    ~H"""
    <style>
      .money-subtabs { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; border-bottom: 1px solid #e2e8f0; }
      .money-subtabs a { color: #64748b; padding: 0.4rem 1.1rem; font-size: 0.95rem; border-bottom: 2px solid transparent; margin-bottom: -1px; text-decoration: none; }
      .money-subtabs a:hover { color: #1e293b; }
      .money-subtabs a.active { color: #1e293b; font-weight: 600; border-bottom-color: #1e293b; }
      .sv-card { background: white; border-radius: 12px; padding: 1.5rem 1.75rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 1.5rem; }
      .sv-tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 1.5rem; }
      .sv-tiles .stat { display: flex; flex-direction: column; gap: 0.4rem; }
      .sv-tiles .stat-label { font-size: 0.8rem; color: #64748b; text-transform: uppercase; letter-spacing: 0.03em; }
      .sv-tiles .stat-value { font-size: 2rem; font-weight: 700; color: #0f172a; font-variant-numeric: tabular-nums; line-height: 1.1; }
      .sv-tiles .stat-split { font-size: 0.82rem; color: #94a3b8; }
      .sv-empty { color: #64748b; padding: 2rem; text-align: center; }
      .sv-table { overflow-x: auto; }
      .sv-table table { border-collapse: collapse; width: 100%; font-size: 0.85rem; }
      .sv-table th, .sv-table td { padding: 0.4rem 0.8rem; text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
      .sv-table th:first-child, .sv-table td:first-child, .sv-table .left { text-align: left; }
      .sv-table .left { white-space: normal; color: #64748b; }
      .sv-table thead th { color: #64748b; border-bottom: 1px solid #e2e8f0; }
      .sv-table tbody tr:nth-child(even) { background: #f8fafc; }
      .sv-table td.strong { font-weight: 600; }
      .sv-table tfoot td { font-weight: 600; background: #f1f5f9; border-top: 2px solid #1e293b; }
    </style>

    <div class="money-subtabs">
      <.link navigate="/cash">Cash</.link>
      <.link navigate="/expenses">Expenses</.link>
      <.link navigate="/savings" class="active">Savings</.link>
    </div>

    <%= if @rows == [] do %>
      <div class="sv-empty">No months recorded yet.</div>
    <% else %>
      <div class="sv-card">
        <div class="sv-tiles">
          <div class="stat">
            <span class="stat-label">{@totals.year} income</span>
            <span class="stat-value">{format_eur(@totals.income)}</span>
            <span class="stat-split">{@totals.months} months to date</span>
          </div>
          <div class="stat">
            <span class="stat-label">{@totals.year} expenses</span>
            <span class="stat-value">{format_eur(@totals.expenses)}</span>
            <span class="stat-split">Wise spending</span>
          </div>
          <div class="stat">
            <span class="stat-label">{@totals.year} savings</span>
            <span class="stat-value">{format_eur(@totals.savings)}</span>
          </div>
          <div class="stat">
            <span class="stat-label">Savings rate</span>
            <span class="stat-value">{NumberFormat.pct(@totals.savings_rate_pct)}</span>
          </div>
          <div class="stat">
            <span class="stat-label">Saved per month</span>
            <span class="stat-value">{format_eur(@totals.avg_monthly_savings)}</span>
            <span class="stat-split">average</span>
          </div>
        </div>
      </div>

      <div class="sv-card">
        <div id="savings-chart" phx-hook="SavingsChart" data-chart={Jason.encode!(@chart_payload)}>
          <div id="savings-chart-canvas" phx-update="ignore">
            <canvas id="savingsChartCanvas"></canvas>
          </div>
        </div>
      </div>

      <div class="sv-card sv-table">
        <table>
          <thead>
            <tr>
              <th>Month</th>
              <th>Net salary</th>
              <th>Meal card</th>
              <th>IRPF refund (est.)</th>
              <th>Total income</th>
              <th>Expenses</th>
              <th>Savings</th>
              <th>Rate</th>
              <th class="left">Notes</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- Enum.reverse(@rows)}>
              <td>{row.month}</td>
              <td>{format_eur(row.net_salary)}</td>
              <td>{format_eur(row.meal_card)}</td>
              <td>{format_eur(row.irpf_refund_estimate)}</td>
              <td class="strong">{format_eur(row.total_income)}</td>
              <td>{format_eur(row.expenses)}</td>
              <td class="strong">{NumberFormat.signed_eur(row.savings)}</td>
              <td>{NumberFormat.pct(row.savings_rate_pct)}</td>
              <td class="left">{row.notes}</td>
            </tr>
          </tbody>
          <tfoot>
            <tr>
              <td>{@totals.year}</td>
              <td colspan="3"></td>
              <td>{format_eur(@totals.income)}</td>
              <td>{format_eur(@totals.expenses)}</td>
              <td>{NumberFormat.signed_eur(@totals.savings)}</td>
              <td>{NumberFormat.pct(@totals.savings_rate_pct)}</td>
              <td></td>
            </tr>
          </tfoot>
        </table>
      </div>
    <% end %>
    """
  end

  defp chart_payload(rows) do
    %{
      title: "Income, expenses and savings per month (€)",
      labels: Enum.map(rows, &month_label(&1.month)),
      rates: Enum.map(rows, & &1.savings_rate_pct),
      datasets: [
        %{label: "Income", color: "#2a78d6", data: Enum.map(rows, & &1.total_income)},
        %{label: "Expenses", color: "#eda100", data: Enum.map(rows, & &1.expenses)},
        %{label: "Savings", color: "#1baf7a", data: Enum.map(rows, & &1.savings)}
      ]
    }
  end

  # The tiles cover the year of the latest recorded month.
  defp latest_year([]), do: Integer.to_string(Date.utc_today().year)
  defp latest_year(rows), do: rows |> List.last() |> Map.fetch!(:month) |> String.slice(0, 4)

  defp month_label(<<year::binary-size(4), "-", month::binary-size(2)>>),
    do: "#{Enum.at(@month_labels, String.to_integer(month) - 1)} #{year}"

  defp format_eur(amount), do: NumberFormat.eur(amount)
end
