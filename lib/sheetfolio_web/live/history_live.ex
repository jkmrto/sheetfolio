defmodule SheetfolioWeb.HistoryLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.AssetCategories

  @palette ["#2a78d6", "#1baf7a", "#eda100", "#008300", "#4a3aa7", "#e34948", "#e87ba4", "#eb6834"]
  @max_selected length(@palette)
  @ranges ~w(1w 1m 3m 1y ytd all)

  # What each selected holding draws in the value view: what it is worth, what
  # it cost, and the gain between them. Dashes tell them apart at a glance
  # while the asset keeps one colour across all three.
  @series [{:value, nil, nil}, {:invested, "Invested", [6, 4]}, {:gain, "Earnings", [2, 3]}]

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket =
        assign(socket,
          authenticated: true,
          snapshots: [],
          asset_list: [],
          asset_groups: [],
          category_list: [],
          collapsed: MapSet.new(),
          # One selection per view: switching back and forth keeps both.
          color_map: %{"asset" => %{}, "category" => %{}},
          view: "asset",
          metric: "value",
          range: "1m",
          selected_date: nil
        )

      if connected?(socket) do
        snapshots =
          Mongo.find(:mongo, "portfolio_snapshots", %{}, sort: %{date: 1})
          |> Enum.to_list()

        asset_list = build_asset_list(snapshots)
        categories = AssetCategories.get()
        asset_groups = group_by_category(asset_list, categories)
        category_list = Enum.map(asset_groups, fn {category, _assets} -> {category, category} end)

        {:ok,
         assign(socket,
           snapshots: snapshots,
           asset_list: asset_list,
           asset_groups: asset_groups,
           category_list: category_list,
           categories: categories,
           collapsed: asset_groups |> Enum.map(&elem(&1, 0)) |> MapSet.new(),
           color_map: %{"asset" => first_selected(asset_list), "category" => first_selected(category_list)},
           selected_date: latest_date(snapshots)
         )}
      else
        {:ok, socket}
      end
    end
  end

  def handle_event("toggle_asset", %{"isin" => isin}, socket) do
    selected = toggle(selection(socket.assigns), isin)
    {:noreply, assign(socket, color_map: Map.put(socket.assigns.color_map, socket.assigns.view, selected))}
  end

  def handle_event("set_view", %{"view" => view}, socket) when view in ["asset", "category"] do
    {:noreply, assign(socket, view: view)}
  end

  def handle_event("toggle_category", %{"category" => category}, socket) do
    collapsed = socket.assigns.collapsed

    collapsed =
      if MapSet.member?(collapsed, category),
        do: MapSet.delete(collapsed, category),
        else: MapSet.put(collapsed, category)

    {:noreply, assign(socket, collapsed: collapsed)}
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

  defp toggle(selected, key) do
    cond do
      Map.has_key?(selected, key) ->
        Map.delete(selected, key)

      map_size(selected) >= @max_selected ->
        selected

      true ->
        used = MapSet.new(Map.values(selected))
        Map.put(selected, key, Enum.find(0..(@max_selected - 1), &(not MapSet.member?(used, &1))))
    end
  end

  defp selection(assigns), do: Map.fetch!(assigns.color_map, assigns.view)

  defp first_selected([{key, _label} | _rest]), do: %{key => 0}
  defp first_selected([]), do: %{}

  defp series_btn(assigns) do
    ~H"""
    <button class={"asset-btn#{if @slot, do: " selected"}"} phx-click="toggle_asset" phx-value-isin={@id}>
      <%= if @slot do %>
        <span class="asset-dot" style={"background: #{Enum.at(palette(), @slot)}"}></span>
      <% end %>
      <%= @name %>
    </button>
    """
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
      .filter-groups { display: flex; flex-direction: column; gap: 0.4rem; margin-bottom: 1rem; }
      .filter-group { display: flex; align-items: baseline; gap: 0.75rem; }
      .filter-group + .filter-group { border-top: 1px solid #f1f5f9; padding-top: 0.4rem; }
      .cat-header { flex: 0 0 16rem; display: flex; align-items: center; gap: 0.45rem; border: none; background: none; cursor: pointer; padding: 0.2rem 0; font-size: 0.7rem; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: #94a3b8; text-align: left; }
      .cat-header:hover { color: #475569; }
      .cat-chevron { display: inline-block; width: 0.7rem; font-size: 0.6rem; color: #cbd5e1; }
      .cat-state { font-size: 1.05rem; line-height: 1; }
      .cat-state.none { color: #cbd5e1; }
      .cat-state.some { color: #2a78d6; }
      .cat-state.all { color: #1e293b; }
      .cat-count { margin-left: auto; font-weight: 600; color: #cbd5e1; font-variant-numeric: tabular-nums; }
      .filter-buttons { display: flex; flex-wrap: wrap; gap: 0.4rem; flex: 1; }
      .asset-btn { border: 1px solid #e2e8f0; background: white; color: #475569; padding: 0.35rem 0.75rem; border-radius: 6px; font-size: 0.82rem; cursor: pointer; display: inline-flex; align-items: center; gap: 0.4rem; }
      .asset-btn:hover { background: #f1f5f9; }
      .asset-btn.selected { border-color: #1e293b; color: #0b0b0b; font-weight: 600; }
      .asset-dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; }
      .metric-toggle { margin-left: auto; display: flex; gap: 0; border: 1px solid #e2e8f0; border-radius: 6px; overflow: hidden; }
      .metric-toggle button { border: none; background: white; color: #475569; padding: 0.35rem 0.8rem; font-size: 0.82rem; cursor: pointer; }
      .metric-toggle button.selected { background: #1e293b; color: white; }
      .range-toggle { margin-left: 0; }
      .view-toggle { margin-left: 0; }
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
        <div class="metric-toggle view-toggle">
          <button class={if @view == "asset", do: "selected"} phx-click="set_view" phx-value-view="asset">By asset</button>
          <button class={if @view == "category", do: "selected"} phx-click="set_view" phx-value-view="category">By category</button>
        </div>
      </div>

      <%= if @view == "category" do %>
        <div class="filter-row">
          <%= for {category, name} <- @category_list do %>
            <.series_btn id={category} name={name} slot={Map.get(selection(assigns), category)} />
          <% end %>
        </div>
      <% else %>
      <div class="filter-groups">
        <%= for {category, assets} <- @asset_groups do %>
          <% open? = not MapSet.member?(@collapsed, category) %>
          <% selected = selection(assigns) %>
          <div class="filter-group">
            <button class="cat-header" phx-click="toggle_category" phx-value-category={category}>
              <span class="cat-chevron"><%= if open?, do: "▼", else: "▶" %></span>
              <span class={"cat-state #{selection_state(assets, selected)}"}><%= state_icon(selection_state(assets, selected)) %></span>
              <span><%= category %></span>
              <span class="cat-count"><%= selected_count(assets, selected) %>/<%= length(assets) %></span>
            </button>
            <div class="filter-buttons">
              <%= if open? do %>
                <%= for {isin, name} <- assets do %>
                  <.series_btn id={isin} name={name} slot={Map.get(selected, isin)} />
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
      <% end %>

      <div class="filter-row">
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

      <%= case rows_on(@snapshots, @selected_date, @view, @categories) do %>
        <% nil -> %>
          <div class="empty-note">No snapshot recorded for <%= es_date(@selected_date) %>.</div>
        <% positions -> %>
          <div class="table-panel" id="table-panel-1" phx-hook="TablePanel">
            <button class="table-expand" aria-label="Toggle full screen"></button>
            <table class="snapshot-table">
              <thead>
                <tr>
                  <th><%= if @view == "category", do: "Category", else: "Asset" %></th><th>Units held</th><th>Invested (€)</th>
                  <th>Value (€)</th><th>Gain/Loss (€)</th><th>Gain/Loss (%)</th>
                </tr>
              </thead>
              <tbody>
                <%= for p <- positions do %>
                  <tr>
                    <td>
                      <strong><%= p.asset %></strong>
                      <%= if p.isin do %>
                        <br/><small style="color:#94a3b8"><%= p.isin %></small>
                      <% end %>
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
          </div>
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
  defp rows_on(_snapshots, nil, _view, _categories), do: nil

  defp rows_on(snapshots, date, view, categories) do
    case Enum.find(snapshots, &(&1["date"] == date)) do
      nil ->
        nil

      snapshot ->
        snapshot["positions"]
        |> List.wrap()
        |> Enum.map(&position_row/1)
        |> rows_for(view, categories)
        |> sort_rows()
    end
  end

  defp rows_for(rows, "category", categories) do
    rows
    |> Enum.group_by(&AssetCategories.category_for(&1.isin, categories))
    |> Enum.map(fn {category, group} ->
      totals = totals(group)

      %{
        isin: nil,
        asset: category,
        units: nil,
        invested: totals.invested,
        value: totals.value,
        gain: totals.gain,
        gain_pct: totals.gain_pct,
        stale_price: Enum.any?(group, & &1.stale_price)
      }
    end)
  end

  defp rows_for(rows, _asset, _categories), do: rows

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

  defp format_qty(nil), do: "—"

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

  # Categories in the order their biggest holding appears, so the heaviest ones
  # head the list and the rows read like the rest of the app's category views.
  defp group_by_category(asset_list, categories) do
    pairs = Enum.map(asset_list, fn {isin, name} -> {AssetCategories.category_for(isin, categories), {isin, name}} end)
    grouped = Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))

    pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.map(&{&1, Map.fetch!(grouped, &1)})
  end

  # Whether a collapsed category is hiding a selection, and how much of one.
  defp selection_state(assets, color_map) do
    case {selected_count(assets, color_map), length(assets)} do
      {0, _total} -> "none"
      {same, same} -> "all"
      _partial -> "some"
    end
  end

  defp selected_count(assets, color_map) do
    Enum.count(assets, fn {isin, _name} -> Map.has_key?(color_map, isin) end)
  end

  defp state_icon("none"), do: "○"
  defp state_icon("some"), do: "◐"
  defp state_icon("all"), do: "●"

  defp chart_payload(assigns) do
    snapshots = filter_range(assigns.snapshots, assigns.range)

    named = if assigns.view == "category", do: assigns.category_list, else: assigns.asset_list

    datasets =
      assigns
      |> selection()
      |> Enum.sort_by(fn {_key, slot} -> slot end)
      |> Enum.flat_map(fn {key, slot} ->
        name =
          case List.keyfind(named, key, 0) do
            {_key, found} -> found
            nil -> key
          end

        datasets_for(snapshots, series_of(key, assigns), name, Enum.at(palette(), slot), assigns.metric)
      end)

    %{metric: assigns.metric, datasets: datasets, clickEvent: "select_point"}
  end

  # The gain view is already one number per holding, so it keeps its single
  # line; the value view splits the holding into what it is worth, what it cost
  # and the gain on top.
  defp datasets_for(snapshots, isin, name, color, "pct") do
    [%{label: name, color: color, axis: "y", data: series_points(snapshots, isin, :pct)}]
  end

  defp datasets_for(snapshots, isin, name, color, "value") do
    Enum.map(@series, fn {metric, suffix, dash} ->
      %{
        label: label_for(name, suffix),
        color: color,
        dash: dash,
        # Markers on all three would bury the dashes that tell them apart, and
        # the value line is the one a click drills the table down to.
        points: is_nil(suffix),
        axis: axis_for(metric),
        data: series_points(snapshots, isin, metric)
      }
    end)
  end

  # A category's line is the sum of its holdings, so a series carries the list of
  # ISINs behind it rather than a single one.
  defp series_of(key, %{view: "category", categories: categories, asset_list: asset_list}) do
    for {isin, _name} <- asset_list, AssetCategories.category_for(isin, categories) == key, do: isin
  end

  defp series_of(isin, _assigns), do: [isin]

  defp label_for(name, nil), do: name
  defp label_for(name, suffix), do: "#{name} · #{suffix}"

  # A holding's gain is an order of magnitude smaller than the capital it sits
  # on, so on the shared scale it flattens onto the floor of the chart. It gets
  # the right-hand axis instead.
  defp axis_for(:gain), do: "y1"
  defp axis_for(_metric), do: "y"

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

  defp series_points(snapshots, isins, metric) do
    snapshots
    |> Enum.flat_map(fn snap ->
      case Enum.filter(snap["positions"], &(&1["isin"] in isins)) do
        [] -> []
        positions -> point(snap["date"], held(positions), metric)
      end
    end)
  end

  # One holding's figures, or the sum of a category's.
  defp held([position]), do: position

  defp held(positions) do
    %{
      "value" => Enum.reduce(positions, 0.0, &(number(&1["value"]) + &2)),
      "invested" => Enum.reduce(positions, 0.0, &(number(&1["invested"]) + &2))
    }
  end

  defp point(date, %{"value" => value, "invested" => invested}, :pct)
       when is_number(value) and is_number(invested) and invested > 0 do
    [%{x: date, y: Float.round((value - invested) / invested * 100, 2)}]
  end

  defp point(date, %{"value" => value}, :value) when is_number(value) do
    [%{x: date, y: value}]
  end

  defp point(date, %{"invested" => invested}, :invested) when is_number(invested) do
    [%{x: date, y: invested}]
  end

  defp point(date, %{"value" => value, "invested" => invested}, :gain)
       when is_number(value) and is_number(invested) do
    [%{x: date, y: Float.round(value - invested, 2)}]
  end

  defp point(_date, _position, _metric), do: []

  defp palette, do: @palette
end
