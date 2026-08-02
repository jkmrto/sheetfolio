defmodule SheetfolioWeb.ExpensesLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.WiseExpenses

  @month_labels ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  @year_colors ["#2a78d6", "#eda100", "#1baf7a", "#4a3aa7", "#e34948", "#e87ba4"]

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      if connected?(socket), do: send(self(), :load)
      year = Integer.to_string(Date.utc_today().year)

      {:ok,
       assign(socket,
         authenticated: true,
         expenses: nil,
         registry: [],
         year: year,
         view: "months",
         mode: "total",
         reg_year: "All",
         reg_month: "All",
         reg_category: "All"
       )}
    end
  end

  def handle_params(params, _uri, socket) do
    {:noreply,
     assign(socket,
       view: params["view"] || "months",
       reg_year: params["year"] || "All",
       reg_month: params["month"] || "All",
       reg_category: params["category"] || "All"
     )}
  end

  def handle_info(:load, socket) do
    {:noreply, assign(socket, expenses: WiseExpenses.monthly_by_category(), registry: WiseExpenses.list())}
  end

  def handle_event("select_year", %{"year" => year}, socket) do
    {:noreply, assign(socket, year: year)}
  end

  def handle_event("select_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, mode: mode)}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        categories: WiseExpenses.categories(),
        years: WiseExpenses.years(),
        registry_rows:
          filtered_registry(assigns.registry, assigns.reg_year, assigns.reg_month, assigns.reg_category)
      )

    ~H"""
    <style>
      .expenses-loading { color: #64748b; padding: 2rem; text-align: center; }
      .money-subtabs { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; border-bottom: 1px solid #e2e8f0; }
      .money-subtabs a { color: #64748b; padding: 0.4rem 1.1rem; font-size: 0.95rem; border-bottom: 2px solid transparent; margin-bottom: -1px; text-decoration: none; }
      .money-subtabs a:hover { color: #1e293b; }
      .money-subtabs a.active { color: #1e293b; font-weight: 600; border-bottom-color: #1e293b; }
      .expenses-subtabs { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; border-bottom: 1px solid #e2e8f0; }
      .expenses-subtabs button, .expenses-subtabs a { border: none; background: none; color: #64748b; padding: 0.4rem 1.1rem; font-size: 0.95rem; cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -1px; text-decoration: none; }
      .expenses-subtabs button:hover, .expenses-subtabs a:hover { color: #1e293b; }
      .expenses-subtabs button.active, .expenses-subtabs a.active { color: #1e293b; font-weight: 600; border-bottom-color: #1e293b; }
      .expenses-buttons { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 1rem; }
      .expenses-buttons button, .expenses-buttons a { border: 1px solid #e2e8f0; background: white; color: #64748b; border-radius: 6px; padding: 0.4rem 1.1rem; font-size: 0.9rem; cursor: pointer; text-decoration: none; }
      .expenses-buttons button:hover, .expenses-buttons a:hover { color: #1e293b; }
      .expenses-buttons button.active, .expenses-buttons a.active { background: #1e293b; border-color: #1e293b; color: white; }
      .expenses-table th a, .expenses-table td a { color: inherit; text-decoration: none; }
      .expenses-table th a:hover, .expenses-table td a:hover { text-decoration: underline; }
      .expenses-table { background: white; border-radius: 12px; padding: 1.5rem 2rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-top: 1.5rem; overflow-x: auto; }
      .expenses-table table { border-collapse: collapse; width: 100%; font-size: 0.85rem; }
      .expenses-table th, .expenses-table td { padding: 0.4rem 0.8rem; text-align: right; white-space: nowrap; }
      .expenses-table th:first-child, .expenses-table td:first-child { text-align: left; }
      .expenses-table th.left, .expenses-table td.left { text-align: left; }
      .expenses-table thead th { color: #64748b; border-bottom: 1px solid #e2e8f0; }
      .expenses-table tbody tr:nth-child(even) { background: #f8fafc; }
      .expenses-table td.total { font-weight: 600; }
      .expenses-table tfoot td { font-weight: 600; background: #f1f5f9; }
      .expenses-table tfoot tr:first-child td { border-top: 2px solid #1e293b; }
      .expenses-dot { display: inline-block; width: 0.6rem; height: 0.6rem; border-radius: 50%; margin-right: 0.35rem; }
    </style>

    <div class="money-subtabs">
      <.link navigate="/cash">Cash</.link>
      <.link navigate="/expenses" class="active">Expenses</.link>
    </div>

    <%= if @expenses == nil do %>
      <div class="expenses-loading">Loading Wise activities…</div>
    <% else %>
      <div class="expenses-subtabs">
        <.link patch="/expenses" class={if @view == "months", do: "active", else: ""}>Months</.link>
        <.link patch="/expenses?view=years" class={if @view == "years", do: "active", else: ""}>Years</.link>
        <.link patch={registry_path(@reg_year, @reg_category)} class={if @view == "registry", do: "active", else: ""}>Registry</.link>
      </div>

      <%= if @view == "months" do %>
        <div class="expenses-buttons">
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
                    <.link patch={registry_path(@year, category)}>
                      <span class="expenses-dot" style={"background: #{WiseExpenses.color(category)}"}></span><%= category %>
                    </.link>
                  </th>
                <% end %>
                <th>Total</th>
              </tr>
            </thead>
            <tbody>
              <%= for month <- year_months(@expenses, @year) |> Enum.reverse() do %>
                <tr>
                  <td>
                    <.link patch={registry_path("All", String.slice(month, 0, 7), "All")}><%= String.slice(month, 0, 7) %></.link>
                  </td>
                  <%= for category <- @categories do %>
                    <td>
                      <%= if elem(@expenses, 1)[{month, category}] do %>
                        <.link patch={registry_path("All", String.slice(month, 0, 7), category)}>
                          <%= format(elem(@expenses, 1)[{month, category}]) %>
                        </.link>
                      <% else %>
                        <%= format(nil) %>
                      <% end %>
                    </td>
                  <% end %>
                  <td class="total">
                    <.link patch={registry_path("All", String.slice(month, 0, 7), "All")}><%= format(month_total(@expenses, month)) %></.link>
                  </td>
                </tr>
              <% end %>
            </tbody>
            <tfoot>
              <tr>
                <td>Total</td>
                <%= for category <- @categories do %>
                  <td><%= format(category_total(@expenses, @year, category)) %></td>
                <% end %>
                <td><%= format(year_total(@expenses, @year)) %></td>
              </tr>
              <tr>
                <td>Avg / month</td>
                <%= for category <- @categories do %>
                  <td><%= format(monthly_average(@expenses, @year, category_total(@expenses, @year, category))) %></td>
                <% end %>
                <td><%= format(monthly_average(@expenses, @year, year_total(@expenses, @year))) %></td>
              </tr>
            </tfoot>
          </table>
        </div>
      <% end %>

      <%= if @view == "years" do %>
        <div class="expenses-buttons">
          <button type="button" class={if @mode == "total", do: "active", else: ""} phx-click="select_mode" phx-value-mode="total">
            Total per year
          </button>
          <button type="button" class={if @mode == "avg", do: "active", else: ""} phx-click="select_mode" phx-value-mode="avg">
            Avg per month
          </button>
        </div>

        <div class="chart-container" id="expenses-years-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(years_chart_payload(@expenses, @years))}>
          <div id="expenses-years-chart-canvas" phx-update="ignore">
            <canvas id="expensesYearsChartCanvas"></canvas>
          </div>
        </div>

        <div class="chart-container" style="margin-top: 1.5rem;" id="expenses-categories-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(categories_chart_payload(@expenses, @years, @categories, @mode))}>
          <div id="expenses-categories-chart-canvas" phx-update="ignore">
            <canvas id="expensesCategoriesChartCanvas"></canvas>
          </div>
        </div>

        <div class="expenses-table">
          <table>
            <thead>
              <tr>
                <th>Year</th>
                <%= for category <- @categories do %>
                  <th>
                    <span class="expenses-dot" style={"background: #{WiseExpenses.color(category)}"}></span><%= category %>
                  </th>
                <% end %>
                <th>Total</th>
              </tr>
            </thead>
            <tbody>
              <%= for year <- @years do %>
                <tr>
                  <td><%= year %> <%= if @mode == "avg", do: "(#{length(year_months(@expenses, year))}m)" %></td>
                  <%= for category <- @categories do %>
                    <td><%= format(year_value(@expenses, year, category_total(@expenses, year, category), @mode)) %></td>
                  <% end %>
                  <td class="total"><%= format(year_value(@expenses, year, year_total(@expenses, year), @mode)) %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>

      <%= if @view == "registry" do %>
        <div class="expenses-buttons">
          <%= for year <- ["All" | @years] do %>
            <.link patch={registry_path(year, @reg_category)} class={if year == @reg_year and @reg_month == "All", do: "active", else: ""}>
              <%= year %>
            </.link>
          <% end %>
          <%= if @reg_month != "All" do %>
            <.link patch={registry_path(String.slice(@reg_month, 0, 4), @reg_category)} class="active" title="Click to widen to the whole year">
              <%= @reg_month %> ✕
            </.link>
          <% end %>
        </div>

        <div class="expenses-buttons">
          <%= for category <- ["All" | @categories] do %>
            <.link patch={registry_path(@reg_year, category)} class={if category == @reg_category, do: "active", else: ""}>
              <%= if category != "All" do %>
                <span class="expenses-dot" style={"background: #{WiseExpenses.color(category)}"}></span>
              <% end %>
              <%= category %>
            </.link>
          <% end %>
        </div>

        <div class="expenses-table" style="margin-top: 0;">
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th class="left">Category</th>
                <th class="left">Description</th>
                <th>Amount</th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @registry_rows do %>
                <tr>
                  <td><%= row.date %></td>
                  <td class="left">
                    <span class="expenses-dot" style={"background: #{WiseExpenses.color(row.category)}"}></span><%= row.category %>
                  </td>
                  <td class="left"><%= if row.note != "", do: row.note, else: row.title %></td>
                  <td><%= format(row.amount) %></td>
                </tr>
              <% end %>
            </tbody>
            <tfoot>
              <tr>
                <td colspan="3"><%= length(@registry_rows) %> expenses</td>
                <td><%= format(@registry_rows |> Enum.map(& &1.amount) |> Enum.sum() |> Kernel./(1)) %></td>
              </tr>
            </tfoot>
          </table>
        </div>
      <% end %>
    <% end %>
    """
  end

  defp years_chart_payload({months, _totals} = expenses, years) do
    datasets =
      years
      |> Enum.with_index()
      |> Enum.map(fn {year, index} ->
        data =
          for m <- 1..12 do
            month = "#{year}-#{String.pad_leading(Integer.to_string(m), 2, "0")}-01"
            if month in months, do: Float.round(month_total(expenses, month), 2)
          end

        %{label: year, color: Enum.at(@year_colors, index, "#64748b"), data: data}
      end)

    %{metric: "value", title: "Monthly expenses per year (€)", labels: @month_labels, datasets: datasets}
  end

  defp categories_chart_payload(expenses, years, categories, mode) do
    labels = Enum.reverse(years)

    datasets =
      Enum.map(categories, fn category ->
        data =
          Enum.map(labels, fn year ->
            Float.round(year_value(expenses, year, category_total(expenses, year, category), mode), 2)
          end)

        %{label: category, color: WiseExpenses.color(category), data: data}
      end)

    title =
      if mode == "avg",
        do: "Avg monthly expenses per category (€)",
        else: "Yearly expenses per category (€)"

    %{metric: "value", title: title, labels: labels, xTitle: "Year", datasets: datasets}
  end

  defp registry_path(year, category), do: registry_path(year, "All", category)

  defp registry_path(year, month, category) do
    query =
      [view: "registry", year: year, month: month, category: category]
      |> Enum.reject(fn {_key, value} -> value == "All" end)

    "/expenses?" <> URI.encode_query(query)
  end

  defp filtered_registry(registry, year, month, category) do
    Enum.filter(registry, fn row ->
      (year == "All" or String.starts_with?(row.date, year)) and
        (month == "All" or String.starts_with?(row.date, month)) and
        (category == "All" or row.category == category)
    end)
  end

  defp year_value(_expenses, _year, total, "total"), do: total
  defp year_value(expenses, year, total, "avg"), do: monthly_average(expenses, year, total)

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

  defp category_total({_months, totals} = expenses, year, category) do
    expenses
    |> year_months(year)
    |> Enum.map(&(totals[{&1, category}] || 0.0))
    |> Enum.sum()
  end

  defp year_total(expenses, year) do
    expenses
    |> year_months(year)
    |> Enum.map(&month_total(expenses, &1))
    |> Enum.sum()
  end

  defp monthly_average(expenses, year, total) do
    total / max(length(year_months(expenses, year)), 1)
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
