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
          dividends: 0.0,
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
            projection: %{date: 1, total_value: 1, total_invested: 1, total_realized: 1, partial: 1}
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
           allocation: allocation(transactions),
           dividends: Sheetfolio.Dividends.total(Sheetfolio.Dividends.all())
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
        .kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 1rem; margin-bottom: 1.5rem; }
        .kpi { background: white; border-radius: 12px; padding: 1.1rem 1.25rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
        .kpi-label { font-size: 0.72rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.35rem; }
        .kpi-value { font-size: 1.35rem; font-weight: 700; color: #0f172a; }
        .kpi-sub { font-size: 0.78rem; color: #64748b; margin-top: 0.3rem; }
        .kpi-up { color: #16a34a; font-weight: 600; }
        .kpi-down { color: #dc2626; font-weight: 600; }
        .kpi-warn { background: #fffbeb; border: 1px solid #fde68a; color: #b45309; border-radius: 8px; padding: 0.55rem 0.9rem; font-size: 0.82rem; margin-bottom: 1.5rem; }
      </style>

      <% k = kpis(assigns) %>
      <%= if k do %>
        <div class="kpis">
          <div class="kpi">
            <div class="kpi-label">Net worth</div>
            <div class="kpi-value"><%= eur(k.net_worth) %></div>
            <%= if k.day_change == nil and k.week_change == nil do %>
              <div class="kpi-sub">portfolio + cash + Urbanitae</div>
            <% end %>
            <%= for {change, label} <- [{k.day_change, "vs yesterday"}, {k.week_change, "vs last week"}] do %>
              <%= if change do %>
                <div class="kpi-sub">
                  <span class={delta_class(change.amount)}>
                    <%= arrow(change.amount) %> <%= signed(change.amount) %>
                  </span>
                  <%= if change.pct, do: "(#{signed_pct(change.pct)})" %> <%= label %>
                </div>
              <% end %>
            <% end %>
          </div>
          <div class="kpi">
            <div class="kpi-label">Portfolio value</div>
            <div class="kpi-value"><%= eur(k.value) %></div>
            <div class="kpi-sub"><%= eur(k.invested) %> invested</div>
          </div>
          <div class="kpi">
            <div class="kpi-label">Unrealized</div>
            <div class={"kpi-value #{delta_class(k.unrealized)}"}><%= signed(k.unrealized) %></div>
            <div class="kpi-sub"><%= if k.unrealized_pct, do: signed_pct(k.unrealized_pct), else: "—" %> on cost</div>
          </div>
          <div class="kpi">
            <div class="kpi-label">Total earnings</div>
            <div class={"kpi-value #{delta_class(k.earnings)}"}><%= signed(k.earnings) %></div>
            <div class="kpi-sub"><%= eur(k.realized) %> realized · <%= eur(k.unrealized) %> unrealized</div>
            <div class="kpi-sub"><%= eur(k.dividends) %> dividends · <%= eur(k.urbanitae) %> Urbanitae</div>
          </div>
        </div>

        <%= if k.partial do %>
          <div class="kpi-warn">
            ⚠ The <%= k.date %> snapshot is partial — at least one position was priced from an
            earlier day, so these figures may be slightly stale.
          </div>
        <% end %>
      <% end %>

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

  # Thousands-separated, for the headline cards where the numbers are large
  # enough that the grouping is what makes them readable at a glance.
  defp eur(nil), do: "—"

  defp eur(value) do
    [int, dec] =
      Float.round(value / 1, 2)
      |> :erlang.float_to_binary(decimals: 2)
      |> String.split(".")

    "#{String.replace(int, ~r/(?<=\d)(?=(\d{3})+$)/, ".")},#{dec} €"
  end

  defp signed(nil), do: "—"
  defp signed(value) when value >= 0, do: "+" <> eur(value)
  defp signed(value), do: eur(value)

  defp signed_pct(value) when value >= 0, do: "+#{value}%"
  defp signed_pct(value), do: "#{value}%"

  defp delta_class(nil), do: ""
  defp delta_class(value) when value >= 0, do: "kpi-up"
  defp delta_class(_value), do: "kpi-down"

  defp arrow(value) when value >= 0, do: "▲"
  defp arrow(_value), do: "▼"

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

  # Headline figures for the top of the page. Everything comes from the same
  # sources the chart below already plots, so the cards and the lines can't
  # disagree: net worth is the purple line's latest point, and realized P&L is
  # the figure the recorder stored rather than a fresh replay of the operation
  # history, which this page never loads.
  defp kpis(%{snapshots: []}), do: nil

  defp kpis(assigns) do
    latest = List.last(assigns.snapshots)
    net = total_with_cash_points(assigns.snapshots, assigns.cash, assigns.urbanitae_by_date)
    invested = number(latest["total_invested"])
    value = number(latest["total_value"])
    realized = number(latest["total_realized"])
    unrealized = Float.round(value - invested, 2)
    {_outstanding, urbanitae} = Map.get(assigns.urbanitae_by_date, latest["date"], {0.0, 0.0})
    urbanitae = Float.round(urbanitae, 2)

    %{
      date: latest["date"],
      net_worth: net_worth(net),
      day_change: change_since(net, 1),
      week_change: change_since(net, 7),
      invested: invested,
      value: value,
      unrealized: unrealized,
      unrealized_pct: percentage(unrealized, invested),
      realized: realized,
      dividends: assigns.dividends,
      urbanitae: urbanitae,
      earnings: Float.round(realized + assigns.dividends + urbanitae + unrealized, 2),
      partial: latest["partial"] == true
    }
  end

  defp net_worth([]), do: nil
  defp net_worth(points), do: List.last(points).y

  # Compares against the point `days` back on the calendar rather than N
  # entries back in the list, so a gap in recording can't silently turn a
  # "last week" comparison into a much older one.
  defp change_since(points, _days) when length(points) < 2, do: nil

  defp change_since(points, days) do
    current = List.last(points)
    cutoff = current.x |> Date.from_iso8601!() |> Date.shift(day: -days) |> Date.to_iso8601()

    case Enum.filter(points, &(&1.x <= cutoff)) do
      [] -> nil
      earlier -> delta(List.last(earlier), current)
    end
  end

  defp delta(previous, current) do
    change = Float.round(current.y - previous.y, 2)
    %{amount: change, pct: percentage(change, previous.y), from: previous.x}
  end

  defp percentage(_change, base) when base in [0, 0.0] or base < 0, do: nil
  defp percentage(change, base), do: Float.round(change / base * 100, 2)

  defp number(value) when is_number(value), do: value * 1.0
  defp number(_value), do: 0.0

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
