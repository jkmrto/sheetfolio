defmodule SheetfolioWeb.HistoryLive do
  use SheetfolioWeb, :live_view

  @palette ["#2a78d6", "#1baf7a", "#eda100", "#008300", "#4a3aa7", "#e34948", "#e87ba4", "#eb6834"]
  @max_selected length(@palette)
  @ranges ~w(1m 3m 1y ytd all)

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket =
        assign(socket,
          authenticated: true,
          snapshots: [],
          asset_list: [],
          color_map: %{},
          metric: "value",
          range: "all"
        )

      if connected?(socket) do
        snapshots =
          Mongo.find(:mongo, "portfolio_snapshots", %{}, sort: %{date: 1})
          |> Enum.to_list()

        asset_list = build_asset_list(snapshots)

        color_map =
          case asset_list do
            [{isin, _name} | _] -> %{isin => 0}
            [] -> %{}
          end

        {:ok, assign(socket, snapshots: snapshots, asset_list: asset_list, color_map: color_map)}
      else
        {:ok, socket}
      end
    end
  end

  def handle_event("toggle_asset", %{"isin" => isin}, socket) do
    color_map = socket.assigns.color_map

    color_map =
      cond do
        Map.has_key?(color_map, isin) ->
          Map.delete(color_map, isin)

        map_size(color_map) >= @max_selected ->
          color_map

        true ->
          used = MapSet.new(Map.values(color_map))
          slot = Enum.find(0..(@max_selected - 1), &(not MapSet.member?(used, &1)))
          Map.put(color_map, isin, slot)
      end

    {:noreply, assign(socket, color_map: color_map)}
  end

  def handle_event("set_metric", %{"metric" => metric}, socket) when metric in ["value", "pct"] do
    {:noreply, assign(socket, metric: metric)}
  end

  def handle_event("set_range", %{"range" => range}, socket) when range in @ranges do
    {:noreply, assign(socket, range: range)}
  end

  def render(assigns) do
    ~H"""
    <style>
      .filter-row { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 1rem; align-items: center; }
      .asset-btn { border: 1px solid #e2e8f0; background: white; color: #475569; padding: 0.35rem 0.75rem; border-radius: 6px; font-size: 0.82rem; cursor: pointer; display: inline-flex; align-items: center; gap: 0.4rem; }
      .asset-btn:hover { background: #f1f5f9; }
      .asset-btn.selected { border-color: #1e293b; color: #0b0b0b; font-weight: 600; }
      .asset-dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; }
      .metric-toggle { margin-left: auto; display: flex; gap: 0; border: 1px solid #e2e8f0; border-radius: 6px; overflow: hidden; }
      .metric-toggle button { border: none; background: white; color: #475569; padding: 0.35rem 0.8rem; font-size: 0.82rem; cursor: pointer; }
      .metric-toggle button.selected { background: #1e293b; color: white; }
      .range-toggle { margin-left: 0; }
      .empty-note { background: white; border-radius: 12px; padding: 2rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); color: #64748b; font-size: 0.9rem; }
    </style>

    <%= if @snapshots == [] do %>
      <div class="empty-note">
        No snapshots recorded yet. History accumulates one point per day once the recorder runs.
      </div>
    <% else %>
      <div class="filter-row">
        <%= for {isin, name} <- @asset_list do %>
          <% slot = Map.get(@color_map, isin) %>
          <button class={"asset-btn#{if slot, do: " selected"}"} phx-click="toggle_asset" phx-value-isin={isin}>
            <%= if slot do %>
              <span class="asset-dot" style={"background: #{Enum.at(palette(), slot)}"}></span>
            <% end %>
            <%= name %>
          </button>
        <% end %>
        <div class="metric-toggle">
          <button class={if @metric == "value", do: "selected"} phx-click="set_metric" phx-value-metric="value">Value (€)</button>
          <button class={if @metric == "pct", do: "selected"} phx-click="set_metric" phx-value-metric="pct">Gain/Loss (%)</button>
        </div>
        <div class="metric-toggle range-toggle">
          <%= for {value, label} <- range_options() do %>
            <button class={if @range == value, do: "selected"} phx-click="set_range" phx-value-range={value}><%= label %></button>
          <% end %>
        </div>
      </div>

      <div class="chart-container" id="history-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(chart_payload(assigns))}>
        <div id="history-chart-canvas" phx-update="ignore">
          <canvas id="historyChartCanvas"></canvas>
        </div>
      </div>
    <% end %>
    """
  end

  defp build_asset_list(snapshots) do
    latest_value =
      snapshots
      |> Enum.flat_map(& &1["positions"])
      |> Enum.reduce(%{}, fn p, acc ->
        Map.put(acc, p["isin"], {p["asset"], p["value"] || 0.0})
      end)

    latest_value
    |> Enum.sort_by(fn {_isin, {_name, value}} -> -value end)
    |> Enum.map(fn {isin, {name, _value}} -> {isin, name} end)
  end

  defp chart_payload(assigns) do
    snapshots = filter_range(assigns.snapshots, assigns.range)

    datasets =
      assigns.color_map
      |> Enum.sort_by(fn {_isin, slot} -> slot end)
      |> Enum.map(fn {isin, slot} ->
        name =
          case List.keyfind(assigns.asset_list, isin, 0) do
            {_, n} -> n
            nil -> isin
          end

        %{
          label: name,
          color: Enum.at(palette(), slot),
          data: series_points(snapshots, isin, assigns.metric)
        }
      end)

    %{metric: assigns.metric, datasets: datasets}
  end

  defp range_options, do: [{"1m", "1M"}, {"3m", "3M"}, {"1y", "1Y"}, {"ytd", "YTD"}, {"all", "All"}]

  defp filter_range(snapshots, "all"), do: snapshots

  defp filter_range(snapshots, range) do
    cutoff = range |> cutoff_date(Date.utc_today()) |> Date.to_iso8601()
    Enum.filter(snapshots, &(&1["date"] >= cutoff))
  end

  defp cutoff_date("1m", today), do: Date.shift(today, month: -1)
  defp cutoff_date("3m", today), do: Date.shift(today, month: -3)
  defp cutoff_date("1y", today), do: Date.shift(today, year: -1)
  defp cutoff_date("ytd", today), do: Date.new!(today.year, 1, 1)

  defp series_points(snapshots, isin, metric) do
    snapshots
    |> Enum.flat_map(fn snap ->
      case Enum.find(snap["positions"], &(&1["isin"] == isin)) do
        nil -> []
        position -> point(snap["date"], position, metric)
      end
    end)
  end

  defp point(date, %{"value" => value, "invested" => invested}, "pct")
       when is_number(value) and is_number(invested) and invested > 0 do
    [%{x: date, y: Float.round((value - invested) / invested * 100, 2)}]
  end

  defp point(date, %{"value" => value}, "value") when is_number(value) do
    [%{x: date, y: value}]
  end

  defp point(_date, _position, _metric), do: []

  defp palette, do: @palette
end
