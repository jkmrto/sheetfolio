defmodule SheetfolioWeb.PortfolioLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.AssetCategories
  alias Sheetfolio.UrbanitaeTransactions

  @ranges ~w(1m 3m 1y ytd all)
  @history_views ~w(stacked lines)

  # Assigned per category, never by rank, so a slice keeps its colour as the
  # allocation shifts. Same hues the Cash and Expenses charts use.
  @category_colors %{
    "Oro/Plata" => "#eda100",
    "Indexados" => "#2a78d6",
    "Inmobiliario" => "#e34948",
    "Renta fija corto plazo" => "#1baf7a",
    "Efectivo" => "#0aa2c0",
    "Custom Stocks" => "#4a3aa7",
    "Bitcoin" => "#eb6834",
    "Indexado Sectorial" => "#9333ea",
    "Renta fija largo plazo" => "#9c8400"
  }
  @other_color "#94a3b8"

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket =
        assign(socket,
          authenticated: true,
          snapshots: [],
          cash: [],
          urbanitae_by_date: %{},
          range: "all",
          allocation: [],
          category_history: nil,
          history_view: "stacked",
          history_range: "all"
        )

      if connected?(socket) do
        snapshots =
          Mongo.find(:mongo, "portfolio_snapshots", %{},
            sort: %{date: 1},
            projection: %{date: 1, total_value: 1, total_invested: 1, total_realized: 1}
          )
          |> Enum.to_list()

        cash =
          Mongo.find(:mongo, "cash_snapshots", %{},
            sort: %{date: 1},
            projection: %{date: 1, total: 1}
          )
          |> Enum.to_list()

        transactions = UrbanitaeTransactions.all()

        # Re-reading every snapshot with its positions costs ~1.5s, so the page
        # renders first and the category history arrives after.
        send(self(), :load_category_history)

        {:ok,
         assign(socket,
           snapshots: snapshots,
           cash: cash,
           urbanitae_by_date: urbanitae_by_date(snapshots, transactions),
           allocation: allocation(transactions)
         )}
      else
        {:ok, socket}
      end
    end
  end

  # The latest snapshot already carries each position's value, so the
  # allocation needs no price fetching. Cash and Urbanitae aren't market
  # positions, so both are folded in from their own sources.
  defp allocation(transactions) do
    case Mongo.find_one(:mongo, "portfolio_snapshots", %{}, sort: %{date: -1}) do
      nil ->
        []

      doc ->
        positions =
          (doc["positions"] || [])
          |> Enum.reject(&(&1["isin"] == "URBANITAE"))
          |> Enum.concat(urbanitae_entries(transactions))
          |> Enum.concat(cash_entries())

        AssetCategories.breakdown(positions, AssetCategories.get())
    end
  end

  # The snapshot's Urbanitae figure is the spreadsheet's invested plus
  # cumulative gains, which counts yield that has already been repaid and now
  # sits in cash — so it overstates what is actually tied up in property. The
  # transaction ledger's outstanding balance is the money still in projects,
  # which is what an allocation should show.
  defp urbanitae_entries(transactions) do
    {outstanding, _earnings} =
      UrbanitaeTransactions.state_at(transactions, Date.to_iso8601(Date.utc_today()))

    [%{"isin" => "URBANITAE", "asset" => "Urbanitae", "value" => Float.round(outstanding, 2)}]
  end

  defp cash_entries do
    case Mongo.find_one(:mongo, "cash_snapshots", %{}, sort: %{date: -1}) do
      nil -> []
      doc -> Enum.map(doc["sources"] || [], &cash_entry/1)
    end
  end

  defp cash_entry(source) do
    %{"isin" => "EFECTIVO", "asset" => source["name"], "value" => source["amount"]}
  end

  defp category_color(category), do: Map.get(@category_colors, category, @other_color)

  def handle_info(:load_category_history, socket) do
    {:noreply, assign(socket, category_history: category_history(socket.assigns))}
  end

  # One point per recorded snapshot, with Urbanitae and cash folded in the same
  # way the doughnut does so the two agree at the right-hand edge.
  defp category_history(%{cash: cash, urbanitae_by_date: urbanitae_by_date}) do
    categories = AssetCategories.get()

    Mongo.find(:mongo, "portfolio_snapshots", %{},
      sort: %{date: 1},
      projection: %{date: 1, "positions.isin": 1, "positions.value": 1}
    )
    |> Enum.map(&dated_positions(&1, cash, urbanitae_by_date))
    |> AssetCategories.history(categories)
  end

  defp dated_positions(doc, cash, urbanitae_by_date) do
    date = doc["date"]

    positions =
      (doc["positions"] || [])
      |> Enum.reject(&(&1["isin"] == "URBANITAE"))
      |> Enum.concat(urbanitae_at(urbanitae_by_date, date))
      |> Enum.concat(cash_at_entry(cash, date))

    {date, positions}
  end

  defp urbanitae_at(urbanitae_by_date, date) do
    case Map.get(urbanitae_by_date, date) do
      {outstanding, _earnings} when outstanding > 0 ->
        [%{"isin" => "URBANITAE", "value" => Float.round(outstanding, 2)}]

      _ ->
        []
    end
  end

  defp cash_at_entry(cash, date) do
    case cash_at(cash, date) do
      nil -> []
      amount -> [%{"isin" => "EFECTIVO", "value" => amount}]
    end
  end

  defp category_history_payload(history, view) do
    names = AssetCategories.history_categories(history)
    labels = Enum.map(history, & &1.date)

    %{
      labels: labels,
      stacked: view == "stacked",
      datasets:
        Enum.map(names, fn name ->
          %{
            label: name,
            color: category_color(name),
            data: Enum.map(history, &Map.get(&1.totals, name, 0.0))
          }
        end)
    }
  end

  def handle_event("set_range", %{"range" => range}, socket) when range in @ranges do
    {:noreply, assign(socket, range: range)}
  end

  def handle_event("set_history_range", %{"range" => range}, socket) when range in @ranges do
    {:noreply, assign(socket, history_range: range)}
  end

  def handle_event("set_history_view", %{"view" => view}, socket) when view in @history_views do
    {:noreply, assign(socket, history_view: view)}
  end

  def render(assigns) do
    ~H"""
    <%= if @snapshots == [] do %>
      <div class="chart-container" style="color:#64748b;font-size:0.9rem;">
        No snapshots recorded yet. History accumulates one point per day once the recorder runs.
      </div>
    <% else %>
      <style>
        .range-row { display: flex; margin-bottom: 1rem; }
        .range-toggle { display: flex; border: 1px solid #e2e8f0; border-radius: 6px; overflow: hidden; }
        .range-toggle button { border: none; background: white; color: #475569; padding: 0.35rem 0.8rem; font-size: 0.82rem; cursor: pointer; }
        .range-toggle button.selected { background: #1e293b; color: white; }
        .alloc { display: flex; flex-wrap: wrap; gap: 2rem; align-items: center; margin-top: 1.5rem; }
        .alloc-chart { flex: 0 0 260px; max-width: 260px; }
        .alloc-legend { flex: 1 1 320px; min-width: 280px; }
        .alloc-title { font-size: 0.85rem; font-weight: 600; color: #64748b; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 1rem; }
        .alloc-legend table { width: 100%; border-collapse: collapse; font-size: 0.88rem; font-variant-numeric: tabular-nums; }
        .alloc-legend td { padding: 0.35rem 0.5rem; border-bottom: 1px solid #f1f5f9; }
        .alloc-legend tr:last-child td { border-bottom: none; }
        .alloc-legend td.num { text-align: right; white-space: nowrap; }
        .alloc-legend td.pct { text-align: right; white-space: nowrap; color: #64748b; width: 3.5rem; }
        .alloc-legend tfoot td { font-weight: 600; border-top: 2px solid #e2e8f0; }
        .alloc-dot { display: inline-block; width: 0.65rem; height: 0.65rem; border-radius: 50%; margin-right: 0.5rem; vertical-align: middle; }
        .alloc-loading { color: #94a3b8; font-size: 0.9rem; padding: 2rem 0; text-align: center; }
        .alloc-controls { display: flex; flex-wrap: wrap; gap: 0.75rem; margin-bottom: 1rem; }
      </style>

      <div class="range-row">
        <div class="range-toggle">
          <%= for {value, label} <- range_options() do %>
            <button class={if @range == value, do: "selected"} phx-click="set_range" phx-value-range={value}>{label}</button>
          <% end %>
        </div>
      </div>

      <div class="chart-container" id="portfolio-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(chart_payload(filter_range(@snapshots, @range), filter_cash_range(@cash, @range), @urbanitae_by_date))}>
        <div id="portfolio-chart-canvas" phx-update="ignore">
          <canvas></canvas>
        </div>
      </div>

      <%= if @allocation != [] do %>
        <div class="chart-container" style="margin-top:1.5rem;">
          <div class="alloc-title">Allocation by category</div>
          <div class="alloc">
            <div class="alloc-chart" id="allocation-chart" phx-hook="CategoryPie" data-chart={Jason.encode!(allocation_payload(@allocation))}>
              <div id="allocation-chart-canvas" phx-update="ignore">
                <canvas></canvas>
              </div>
            </div>
            <div class="alloc-legend">
              <table>
                <tbody>
                  <%= for slice <- @allocation do %>
                    <tr>
                      <td>
                        <span class="alloc-dot" style={"background:#{category_color(slice.category)}"}></span><%= slice.category %>
                      </td>
                      <td class="num"><%= format_eur(slice.value) %></td>
                      <td class="pct"><%= slice.pct %>%</td>
                    </tr>
                  <% end %>
                </tbody>
                <tfoot>
                  <tr>
                    <td>Total</td>
                    <td class="num"><%= format_eur(allocation_total(@allocation)) %></td>
                    <td class="pct"></td>
                  </tr>
                </tfoot>
              </table>
            </div>
          </div>
        </div>

        <div class="chart-container" style="margin-top:1.5rem;">
          <div class="alloc-title">Allocation history</div>
          <div class="alloc-controls">
            <div class="range-toggle">
              <%= for {value, label} <- history_view_options() do %>
                <button class={if @history_view == value, do: "selected"} phx-click="set_history_view" phx-value-view={value}>{label}</button>
              <% end %>
            </div>
            <div class="range-toggle">
              <%= for {value, label} <- range_options() do %>
                <button class={if @history_range == value, do: "selected"} phx-click="set_history_range" phx-value-range={value}>{label}</button>
              <% end %>
            </div>
          </div>
          <%= if @category_history == nil do %>
            <div class="alloc-loading">Loading category history…</div>
          <% else %>
            <div id="category-history-chart" phx-hook="CategoryHistoryChart" data-chart={Jason.encode!(category_history_payload(filter_history(@category_history, @history_range), @history_view))}>
              <div id="category-history-canvas" phx-update="ignore">
                <canvas></canvas>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    <% end %>
    """
  end

  defp filter_history(history, "all"), do: history

  defp filter_history(history, range) do
    cutoff = range |> cutoff_date(Date.utc_today()) |> Date.to_iso8601()
    Enum.filter(history, &(&1.date >= cutoff))
  end

  defp allocation_total(allocation) do
    allocation |> Enum.reduce(0.0, &(&1.value + &2)) |> Float.round(2)
  end

  defp allocation_payload(allocation) do
    %{
      labels: Enum.map(allocation, & &1.category),
      values: Enum.map(allocation, & &1.value),
      colors: Enum.map(allocation, &category_color(&1.category))
    }
  end

  defp format_eur(value) do
    :erlang.float_to_binary(value * 1.0, decimals: 2) <> " €"
  end

  defp range_options, do: [{"1m", "1M"}, {"3m", "3M"}, {"1y", "1Y"}, {"ytd", "YTD"}, {"all", "All"}]

  defp history_view_options, do: [{"stacked", "Cumulative"}, {"lines", "By category"}]

  defp filter_range(snapshots, "all"), do: snapshots

  defp filter_range(snapshots, range) do
    cutoff = range |> cutoff_date(Date.utc_today()) |> Date.to_iso8601()
    Enum.filter(snapshots, &(&1["date"] >= cutoff))
  end

  # cash_at/2 walks the full history to find the latest ≤ date, so we keep
  # all cash points earlier than the cutoff too — otherwise the first
  # snapshot in the window would have no cash value.
  defp filter_cash_range(cash, _range), do: cash

  defp cutoff_date("1m", today), do: Date.shift(today, month: -1)
  defp cutoff_date("3m", today), do: Date.shift(today, month: -3)
  defp cutoff_date("1y", today), do: Date.shift(today, year: -1)
  defp cutoff_date("ytd", today), do: Date.new!(today.year, 1, 1)

  defp chart_payload(snapshots, cash, urbanitae) do
    %{
      metric: "value",
      title: "Portfolio Evolution",
      datasets: [
        %{label: "Portfolio + Cash + Urbanitae (€)", color: "#4a3aa7", data: total_with_cash_points(snapshots, cash, urbanitae)},
        %{label: "Portfolio (€)", color: "#2a78d6", fill: true, data: total_points(snapshots)},
        %{label: "Invested (€)", color: "#94a3b8", data: invested_points(snapshots)},
        %{label: "Urbanitae outstanding (€)", color: "#e34948", data: urbanitae_points(snapshots, urbanitae)},
        %{label: "Cash (€)", color: "#eda100", data: cash_points(snapshots, cash)},
        %{label: "Earnings, realized + unrealized (€)", color: "#008300", fill: true, data: earnings_points(snapshots, urbanitae)}
      ]
    }
  end

  defp total_points(snapshots) do
    for s <- snapshots, is_number(s["total_value"]) do
      %{x: s["date"], y: s["total_value"]}
    end
  end

  defp total_with_cash_points(snapshots, cash, urbanitae) do
    for s <- snapshots, is_number(s["total_value"]), amount = cash_at(cash, s["date"]) do
      {out, _earn} = Map.get(urbanitae, s["date"], {0.0, 0.0})
      %{x: s["date"], y: Float.round(s["total_value"] + amount + out, 2)}
    end
  end

  defp urbanitae_points(snapshots, urbanitae) do
    for s <- snapshots, {out, _earn} = Map.get(urbanitae, s["date"], {nil, nil}), is_number(out) do
      %{x: s["date"], y: Float.round(out, 2)}
    end
  end

  defp invested_points(snapshots) do
    for s <- snapshots, is_number(s["total_invested"]) do
      %{x: s["date"], y: s["total_invested"]}
    end
  end

  defp cash_points(snapshots, cash) do
    for s <- snapshots, amount = cash_at(cash, s["date"]) do
      %{x: s["date"], y: amount}
    end
  end

  defp earnings_points(snapshots, urbanitae) do
    for s <- snapshots, is_number(s["total_value"]) and is_number(s["total_invested"]) do
      unrealized = s["total_value"] - s["total_invested"]
      market_realized = s["total_realized"] || 0.0
      {_out, urb_earnings} = Map.get(urbanitae, s["date"], {0.0, 0.0})
      %{x: s["date"], y: Float.round(unrealized + market_realized + urb_earnings, 2)}
    end
  end

  # Latest cash total recorded on or before the given date.
  defp cash_at(cash, date) do
    cash
    |> Enum.take_while(&(&1["date"] <= date))
    |> List.last()
    |> case do
      nil -> nil
      doc -> doc["total"]
    end
  end

  defp urbanitae_by_date(snapshots, transactions) do
    snapshots
    |> Enum.map(& &1["date"])
    |> Enum.uniq()
    |> Enum.map(&{&1, UrbanitaeTransactions.state_at(transactions, &1)})
    |> Map.new()
  end
end
