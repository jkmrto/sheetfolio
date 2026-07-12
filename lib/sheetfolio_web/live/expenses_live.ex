defmodule SheetfolioWeb.ExpensesLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.WiseExpenses

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      if connected?(socket), do: send(self(), :load)
      year = Integer.to_string(Date.utc_today().year)
      {:ok, assign(socket, authenticated: true, expenses: nil, year: year)}
    end
  end

  def handle_info(:load, socket) do
    {:noreply, assign(socket, expenses: WiseExpenses.monthly_by_category())}
  end

  def handle_event("select_year", %{"year" => year}, socket) do
    {:noreply, assign(socket, year: year)}
  end

  def render(assigns) do
    assigns = assign(assigns, categories: WiseExpenses.categories(), years: WiseExpenses.years())

    ~H"""
    <style>
      .expenses-loading { color: #64748b; padding: 2rem; text-align: center; }
      .expenses-years { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; }
      .expenses-years button { border: 1px solid #e2e8f0; background: white; color: #64748b; border-radius: 6px; padding: 0.4rem 1.1rem; font-size: 0.9rem; cursor: pointer; }
      .expenses-years button:hover { color: #1e293b; }
      .expenses-years button.active { background: #1e293b; border-color: #1e293b; color: white; }
      .expenses-table { background: white; border-radius: 12px; padding: 1.5rem 2rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-top: 1.5rem; overflow-x: auto; }
      .expenses-table table { border-collapse: collapse; width: 100%; font-size: 0.85rem; }
      .expenses-table th, .expenses-table td { padding: 0.4rem 0.8rem; text-align: right; white-space: nowrap; }
      .expenses-table th:first-child, .expenses-table td:first-child { text-align: left; }
      .expenses-table thead th { color: #64748b; border-bottom: 1px solid #e2e8f0; }
      .expenses-table tbody tr:nth-child(even) { background: #f8fafc; }
      .expenses-table td.total { font-weight: 600; }
      .expenses-dot { display: inline-block; width: 0.6rem; height: 0.6rem; border-radius: 50%; margin-right: 0.35rem; }
    </style>

    <%= if @expenses == nil do %>
      <div class="expenses-loading">Loading Wise activities…</div>
    <% else %>
      <div class="expenses-years">
        <%= for year <- @years do %>
          <button type="button" class={if year == @year, do: "active", else: ""} phx-click="select_year" phx-value-year={year}>
            <%= year %>
          </button>
        <% end %>
      </div>

      <div class="chart-container" id="expenses-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(chart_payload(@expenses, @categories, @year))}>
        <div id="expenses-chart-canvas" phx-update="ignore">
          <canvas id="expensesChartCanvas"></canvas>
        </div>
      </div>

      <div class="expenses-table">
        <table>
          <thead>
            <tr>
              <th>Month</th>
              <%= for category <- @categories do %>
                <th>
                  <span class="expenses-dot" style={"background: #{WiseExpenses.color(category)}"}></span><%= category %>
                </th>
              <% end %>
              <th>Total</th>
            </tr>
          </thead>
          <tbody>
            <%= for month <- year_months(@expenses, @year) |> Enum.reverse() do %>
              <tr>
                <td><%= String.slice(month, 0, 7) %></td>
                <%= for category <- @categories do %>
                  <td><%= format(elem(@expenses, 1)[{month, category}]) %></td>
                <% end %>
                <td class="total"><%= format(month_total(@expenses, month)) %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    <% end %>
    """
  end

  defp year_months({months, _totals}, year) do
    Enum.filter(months, &String.starts_with?(&1, year <> "-"))
  end

  defp chart_payload({_months, totals} = expenses, categories, year) do
    months = year_months(expenses, year)

    datasets =
      Enum.map(categories, fn category ->
        %{
          label: category,
          color: WiseExpenses.color(category),
          data: Enum.map(months, &%{x: &1, y: totals[{&1, category}] || 0.0})
        }
      end)

    %{metric: "value", title: "Monthly expenses by category #{year} (€)", timeUnit: "month", datasets: datasets}
  end

  defp month_total({_months, totals}, month) do
    totals
    |> Enum.filter(fn {{m, _category}, _total} -> m == month end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sum()
  end

  defp format(nil), do: "—"
  defp format(amount), do: "#{:erlang.float_to_binary(amount / 1, decimals: 2)} €"
end
