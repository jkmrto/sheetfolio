defmodule SheetfolioWeb.PortfolioLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.AssetCategories
  alias Sheetfolio.UrbanitaeTransactions

  @ranges ~w(1m 3m 1y ytd all)

  # Assigned per category, never by rank, so a slice keeps its colour as the
  # allocation shifts. Same hues the Cash and Expenses charts use.
  @category_colors %{
    "Indexados" => "#2a78d6",
    "Renta fija corto plazo" => "#eda100",
    "Gold" => "#1baf7a",
    "Inmobiliario" => "#e34948",
    "Custom Stocks" => "#4a3aa7",
    "Silver" => "#0aa2c0",
    "Indexado Sectorial" => "#eb6834",
    "Bitcoin" => "#9333ea",
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
          allocation: []
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

        urbanitae_by_date = urbanitae_by_date(snapshots)

        {:ok,
         assign(socket,
           snapshots: snapshots,
           cash: cash,
           urbanitae_by_date: urbanitae_by_date,
           allocation: allocation()
         )}
      else
        {:ok, socket}
      end
    end
  end

  # The latest snapshot already carries each position's value, so the
  # allocation needs no price fetching.
  defp allocation do
    case Mongo.find_one(:mongo, "portfolio_snapshots", %{}, sort: %{date: -1}) do
      nil -> []
      doc -> AssetCategories.breakdown(doc["positions"] || [], AssetCategories.get())
    end
  end

  defp category_color(category), do: Map.get(@category_colors, category, @other_color)

  def handle_event("set_range", %{"range" => range}, socket) when range in @ranges do
    {:noreply, assign(socket, range: range)}
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
      <% end %>
    <% end %>
    """
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

  defp urbanitae_by_date(snapshots) do
    transactions = UrbanitaeTransactions.all()

    snapshots
    |> Enum.map(& &1["date"])
    |> Enum.uniq()
    |> Enum.map(&{&1, UrbanitaeTransactions.state_at(transactions, &1)})
    |> Map.new()
  end
end
