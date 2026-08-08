defmodule SheetfolioWeb.HistoryLive do
  use SheetfolioWeb, :live_view

  @palette ["#2a78d6", "#1baf7a", "#eda100", "#008300", "#4a3aa7", "#e34948", "#e87ba4", "#eb6834"]
  @max_selected length(@palette)
  @ranges ~w(1w 1m 3m 1y ytd all)

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
          range: "1m",
          selected_date: nil
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

        {:ok,
         assign(socket,
           snapshots: snapshots,
           asset_list: asset_list,
           color_map: color_map,
           selected_date: latest_date(snapshots)
         )}
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

  def handle_event("set_date", %{"date" => date}, socket) when date != "" do
    {:noreply, assign(socket, selected_date: date)}
  end

  def handle_event("set_date", _params, socket), do: {:noreply, socket}

  # Clicking a point on the chart drills the table below to that day.
  def handle_event("select_point", %{"date" => date}, socket) do
    {:noreply, assign(socket, selected_date: date)}
  end

  # dd/mm/yyyy text field over a hidden native date input (see the SpanishDate
  # JS hook). The text is what the user reads and edits; the native input holds
  # the ISO value the form submits and supplies the calendar the button opens.
  defp es_date_field(assigns) do
    ~H"""
    <div class="es-date" id={"date-#{@name}"} phx-hook="SpanishDate">
      <input type="text" class="es-date-text" value={es_date(@value)} inputmode="numeric"
             placeholder="dd/mm/aaaa" autocomplete="off" />
      <button type="button" class="es-date-btn" tabindex="-1" aria-label="Abrir calendario">📅</button>
      <input type="date" class="es-date-native" name={@name} value={@value} min={@min} max={@max}
             tabindex="-1" aria-hidden="true" />
    </div>
    """
  end

  # dd/mm/yyyy, the Spanish convention the rest of the app's dates follow.
  defp es_date(nil), do: ""

  defp es_date(iso) do
    case String.split(iso, "-") do
      [year, month, day] -> "#{day}/#{month}/#{year}"
      _ -> iso
    end
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
      .date-bar { display: flex; align-items: center; gap: 1rem; margin: 2rem 0 1rem; }
      .date-bar label { font-size: 0.9rem; font-weight: 600; color: #475569; }
      .es-date { position: relative; display: inline-flex; align-items: center; border: 1px solid #cbd5e1; border-radius: 6px; background: white; padding: 0 0.35rem 0 0.7rem; }
      .es-date-text { border: none; outline: none; padding: 0.4rem 0; font-size: 0.9rem; color: #1e293b; width: 6rem; background: transparent; font-variant-numeric: tabular-nums; }
      .es-date-btn { border: none; background: transparent; cursor: pointer; font-size: 0.95rem; line-height: 1; padding: 0.2rem 0.25rem; color: #475569; }
      .es-date-btn:hover { color: #1e293b; }
      .es-date-native { position: absolute; left: 0; bottom: 0; width: 100%; height: 1px; opacity: 0; pointer-events: none; }
      .price-note { font-size: 0.8rem; color: #94a3b8; margin-left: auto; }
      .snapshot-table { width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .snapshot-table th { background: #1e293b; color: white; padding: 0.75rem 1rem; text-align: left; font-size: 0.85rem; font-weight: 600; letter-spacing: 0.03em; }
      .snapshot-table th:not(:first-child) { text-align: right; }
      .snapshot-table td { padding: 0.65rem 1rem; border-bottom: 1px solid #f1f5f9; font-size: 0.9rem; }
      .snapshot-table td:not(:first-child) { text-align: right; }
      .snapshot-table tr:last-child td { border-bottom: none; }
      .snapshot-table tr:hover td { background: #f8fafc; }
      .snapshot-table tfoot td { background: #f8fafc; font-weight: 600; border-top: 2px solid #e2e8f0; }
      .positive { color: #16a34a; font-weight: 600; }
      .negative { color: #dc2626; font-weight: 600; }
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

      <div class="date-bar">
        <label>Positions on</label>
        <form phx-change="set_date" style="display:contents;">
          <.es_date_field name="date" value={@selected_date} min={first_date(@snapshots)} max={latest_date(@snapshots)} />
        </form>
        <span class="price-note">Click a point on the chart to jump to that day</span>
      </div>

      <%= case positions_on(@snapshots, @selected_date) do %>
        <% nil -> %>
          <div class="empty-note">No snapshot recorded for <%= es_date(@selected_date) %>.</div>
        <% positions -> %>
          <table class="snapshot-table">
            <thead>
              <tr>
                <th>Asset</th><th>Units held</th><th>Invested (€)</th>
                <th>Value (€)</th><th>Gain/Loss (€)</th><th>Gain/Loss (%)</th>
              </tr>
            </thead>
            <tbody>
              <%= for p <- positions do %>
                <tr>
                  <td>
                    <strong><%= p.asset %></strong><br/>
                    <small style="color:#94a3b8"><%= p.isin %></small>
                    <%= if p.stale_price do %>
                      <br/><small style="color:#f59e0b">⚠ price carried forward from an earlier day</small>
                    <% end %>
                  </td>
                  <td><%= format_qty(p.units) %></td>
                  <td><%= format_eur(p.invested) %></td>
                  <td><%= format_eur(p.value) %></td>
                  <td class={earnings_class(p.gain)}><%= format_abs(p.gain) %></td>
                  <td class={earnings_class(p.gain_pct)}><%= format_pct(p.gain_pct) %></td>
                </tr>
              <% end %>
            </tbody>
            <tfoot>
              <% totals = totals(positions) %>
              <tr>
                <td>Total</td>
                <td></td>
                <td><%= format_eur(totals.invested) %></td>
                <td><%= format_eur(totals.value) %></td>
                <td class={earnings_class(totals.gain)}><%= format_abs(totals.gain) %></td>
                <td class={earnings_class(totals.gain_pct)}><%= format_pct(totals.gain_pct) %></td>
              </tr>
            </tfoot>
          </table>
      <% end %>
    <% end %>
    """
  end

  defp latest_date([]), do: nil
  defp latest_date(snapshots), do: List.last(snapshots)["date"]

  defp first_date([]), do: nil
  defp first_date([first | _rest]), do: first["date"]

  # Read straight from the stored snapshot rather than replaying the operation
  # history: those figures are what every other page reports, and they already
  # carry the average-cost basis Positions computed when the day was recorded.
  defp positions_on(_snapshots, nil), do: nil

  defp positions_on(snapshots, date) do
    case Enum.find(snapshots, &(&1["date"] == date)) do
      nil -> nil
      snapshot -> snapshot["positions"] |> List.wrap() |> Enum.map(&position_row/1) |> sort_rows()
    end
  end

  defp sort_rows(rows), do: Enum.sort_by(rows, & &1.invested, :desc)

  defp position_row(position) do
    invested = number(position["invested"])
    value = number(position["value"])
    gain = Float.round(value - invested, 2)

    %{
      isin: position["isin"],
      asset: position["asset"],
      units: number(position["units"]),
      invested: invested,
      value: value,
      gain: gain,
      gain_pct: percentage(gain, invested),
      stale_price: position["stale_price"] == true
    }
  end

  defp totals(rows) do
    invested = rows |> Enum.reduce(0.0, &(&1.invested + &2)) |> Float.round(2)
    value = rows |> Enum.reduce(0.0, &(&1.value + &2)) |> Float.round(2)
    gain = Float.round(value - invested, 2)

    %{invested: invested, value: value, gain: gain, gain_pct: percentage(gain, invested)}
  end

  defp percentage(_gain, invested) when invested <= 0, do: nil
  defp percentage(gain, invested), do: Float.round(gain / invested * 100, 2)

  defp number(value) when is_number(value), do: value * 1.0
  defp number(_value), do: 0.0

  defp earnings_class(nil), do: ""
  defp earnings_class(value) when value >= 0, do: "positive"
  defp earnings_class(_value), do: "negative"

  defp format_eur(nil), do: "—"
  defp format_eur(value), do: "#{:erlang.float_to_binary(value * 1.0, decimals: 2)} €"

  defp format_abs(nil), do: "—"
  defp format_abs(value) when value >= 0, do: "+#{format_eur(value)}"
  defp format_abs(value), do: format_eur(value)

  defp format_pct(nil), do: "—"
  defp format_pct(value) when value >= 0, do: "+#{value}%"
  defp format_pct(value), do: "#{value}%"

  defp format_qty(value) do
    :erlang.float_to_binary(value * 1.0, decimals: 4)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
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

    %{metric: assigns.metric, datasets: datasets, clickEvent: "select_point"}
  end

  defp range_options, do: [{"1w", "1W"}, {"1m", "1M"}, {"3m", "3M"}, {"1y", "1Y"}, {"ytd", "YTD"}, {"all", "All"}]

  defp filter_range(snapshots, "all"), do: snapshots

  defp filter_range(snapshots, range) do
    cutoff = range |> cutoff_date(Date.utc_today()) |> Date.to_iso8601()
    Enum.filter(snapshots, &(&1["date"] >= cutoff))
  end

  defp cutoff_date("1w", today), do: Date.shift(today, day: -7)
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
