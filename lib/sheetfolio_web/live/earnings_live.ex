defmodule SheetfolioWeb.EarningsLive do
  use SheetfolioWeb, :live_view

  alias SheetfolioWeb.NumberFormat

  @views ~w(by_asset by_operation tax)
  @palette ["#2a78d6", "#1baf7a", "#eda100", "#008300", "#4a3aa7", "#e34948", "#e87ba4", "#eb6834"]
  @chart_views ~w(category asset)

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket =
        assign(socket,
          authenticated: true,
          realized_events: [],
          tax_years: [],
          unrealized: [],
          dividends: [],
          urbanitae: [],
          equito: [],
          view: "by_asset",
          expanded_assets: MapSet.new(),
          expanded_dividends: MapSet.new(),
          cumulative: [],
          names: %{},
          categories: %{},
          params: %{},
          chart_view: "category",
          chart_keys: ["Total"],
          opened: MapSet.new()
        )

      if connected?(socket) do
        operations = Sheetfolio.OperationsServer.get_operations() || []
        {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()

        realized_events =
          Sheetfolio.Positions.realized_events(operations, eur_usd, eur_cad)
          |> Enum.reverse()

        earnings = monthly_earnings(operations, eur_usd, eur_cad)

        {:ok,
         assign(socket,
           realized_events: realized_events,
           tax_years: Sheetfolio.TaxGains.by_year(operations, eur_usd, eur_cad),
           unrealized: unrealized_positions(),
           dividends: Sheetfolio.Dividends.all(),
           urbanitae: urbanitae_earnings(),
           equito: equito_earnings(),
           cumulative: earnings.cumulative,
           names: earnings.names,
           categories: Sheetfolio.AssetCategories.get()
         )
         |> open_selected()}
      else
        {:ok, socket}
      end
    end
  end

  # The chart's grouping and lines live in `?chart=` and `?show=`, so a
  # refresh keeps them.
  def handle_params(params, _uri, socket) do
    view = if params["chart"] in @chart_views, do: params["chart"], else: "category"
    keys = (params["show"] || "Total") |> String.split(",", trim: true) |> Enum.uniq() |> Enum.take(length(@palette))

    {:noreply, socket |> assign(params: params, chart_view: view, chart_keys: keys) |> open_selected()}
  end

  # A category holding a picked asset opens, as it does on /history.
  defp open_selected(%{assigns: %{chart_view: "asset", categories: categories} = assigns} = socket) do
    groups = for key <- assigns.chart_keys, key != "Total", do: category_of(key, categories)
    assign(socket, opened: MapSet.union(assigns.opened, MapSet.new(groups)))
  end

  defp open_selected(socket), do: socket

  def handle_event("chart_group", %{"group" => group}, socket) do
    {:noreply, assign(socket, opened: toggle(socket.assigns.opened, group))}
  end

  def handle_event("chart_view", %{"view" => view}, socket) when view in @chart_views do
    {:noreply, patch_chart(socket, %{"chart" => view, "show" => "Total"})}
  end

  def handle_event("chart_toggle", %{"key" => key}, socket) do
    keys = socket.assigns.chart_keys

    keys =
      cond do
        key in keys -> keys -- [key]
        length(keys) >= length(@palette) -> keys
        true -> keys ++ [key]
      end

    {:noreply, patch_chart(socket, %{"show" => Enum.join(keys, ",")})}
  end

  def handle_event("set_view", %{"view" => view}, socket) when view in @views do
    {:noreply, assign(socket, view: view)}
  end

  def handle_event("toggle_asset", %{"asset" => asset}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded_assets, asset) do
        MapSet.delete(socket.assigns.expanded_assets, asset)
      else
        MapSet.put(socket.assigns.expanded_assets, asset)
      end

    {:noreply, assign(socket, expanded_assets: expanded)}
  end

  def handle_event("toggle_dividend_asset", %{"asset" => asset}, socket) do
    {:noreply, assign(socket, expanded_dividends: toggle(socket.assigns.expanded_dividends, asset))}
  end

  defp patch_chart(socket, changes) do
    params = Map.merge(socket.assigns.params, changes)
    push_patch(socket, to: "/earnings?" <> URI.encode_query(params))
  end

  defp monthly_earnings(operations, eur_usd, eur_cad) do
    snapshots = Mongo.find(:mongo, "portfolio_snapshots", %{}, sort: %{date: 1}) |> Enum.to_list()
    history = Sheetfolio.Positions.history(operations, eur_usd, eur_cad)
    urbanitae = Sheetfolio.UrbanitaeTransactions.all()
    equito = Sheetfolio.EquitoTransactions.all()

    ledgers = [
      {"Urbanitae", &Sheetfolio.UrbanitaeTransactions.state_at(urbanitae, &1)},
      {"Equito", &Sheetfolio.EquitoTransactions.state_at(equito, &1)}
    ]

    Sheetfolio.MonthlyEarnings.build(snapshots, history, Sheetfolio.Dividends.all(), ledgers)
  end

  # Ledgers are keyed by their label ("Urbanitae"), the categories sheet by
  # upper-case id ("URBANITAE"); ISINs are upper case already.
  defp category_of(key, categories), do: Sheetfolio.AssetCategories.category_for(String.upcase(key), categories)

  # What can be drawn: the total, then each category or asset, biggest
  # earner first by what it has made so far.
  defp chart_options(%{cumulative: []}), do: []

  defp chart_options(assigns) do
    {_date, latest} = List.last(assigns.cumulative)

    groups =
      latest
      |> Enum.group_by(fn {key, _gain} -> group_key(key, assigns) end, &elem(&1, 1))
      |> Enum.map(fn {group, gains} -> {group, Enum.sum(gains)} end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.map(fn {group, _gain} -> {group, group_name(group, assigns)} end)

    [{"Total", "Total"} | groups]
  end

  # The asset view's buttons under their categories, both biggest earner first.
  defp asset_groups(%{cumulative: []}), do: []

  defp asset_groups(assigns) do
    {_date, latest} = List.last(assigns.cumulative)

    latest
    |> Enum.group_by(fn {key, _gain} -> category_of(key, assigns.categories) end)
    |> Enum.map(fn {group, entries} ->
      assets = entries |> Enum.sort_by(&elem(&1, 1), :desc) |> Enum.map(fn {key, _gain} -> {key, Map.get(assigns.names, key, key)} end)
      {group, assets, entries |> Enum.map(&elem(&1, 1)) |> Enum.sum()}
    end)
    |> Enum.sort_by(&elem(&1, 2), :desc)
    |> Enum.map(fn {group, assets, _gain} -> {group, assets} end)
  end

  defp group_state(assets, keys) do
    case {Enum.count(assets, &(elem(&1, 0) in keys)), length(assets)} do
      {0, _total} -> {"none", "○", 0}
      {same, same} -> {"all", "●", same}
      {some, _total} -> {"some", "◐", some}
    end
  end

  defp group_key(key, %{chart_view: "category", categories: categories}), do: category_of(key, categories)
  defp group_key(key, _assigns), do: key

  defp group_name(group, %{chart_view: "asset", names: names}), do: Map.get(names, group, group)
  defp group_name(group, _assigns), do: group

  defp earnings_chart(assigns) do
    named = Map.new(chart_options(assigns))

    datasets =
      assigns.chart_keys
      |> Enum.filter(&Map.has_key?(named, &1))
      |> Enum.with_index()
      |> Enum.map(fn {group, slot} ->
        %{
          label: named[group],
          color: Enum.at(@palette, slot),
          data:
            for {date, gains} <- assigns.cumulative do
              y = for({key, gain} <- gains, group == "Total" or group_key(key, assigns) == group, do: gain) |> Enum.sum()
              %{x: date, y: Float.round(y * 1.0, 2)}
            end
        }
      end)

    %{metric: "value", title: "Cumulative earnings (€)", timeUnit: "month", datasets: datasets}
  end

  defp chart_slot(assigns, key), do: Enum.find_index(assigns.chart_keys, &(&1 == key))

  defp palette, do: @palette

  defp key_btn(assigns) do
    ~H"""
    <button class={"key-btn#{if @slot, do: " selected"}"} phx-click="chart_toggle" phx-value-key={@key}>
      <span :if={@slot} class="key-dot" style={"background: #{Enum.at(palette(), @slot)}"}></span><%= @name %>
    </button>
    """
  end

  defp toggle(set, key) do
    if MapSet.member?(set, key), do: MapSet.delete(set, key), else: MapSet.put(set, key)
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        realized_sum: Enum.reduce(assigns.realized_events, 0.0, &(&1.realized + &2)),
        unrealized_sum: Enum.reduce(assigns.unrealized, 0.0, &(&1.value - &1.invested + &2)),
        dividends_sum: Sheetfolio.Dividends.total(assigns.dividends),
        dividends_by_asset: Sheetfolio.Dividends.by_asset(assigns.dividends),
        urbanitae_sum: Enum.reduce(assigns.urbanitae, 0.0, &(&1.earnings + &2)),
        equito_sum: Enum.reduce(assigns.equito, 0.0, &(&1.earnings + &2)),
        by_asset: group_by_asset(assigns.realized_events),
        trading212: Sheetfolio.SyntheticOperations.trading212_isins()
      )

    ~H"""
    <style>
      .earnings-page-tabs { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; border-bottom: 1px solid #e2e8f0; }
      .earnings-page-tabs a { color: #64748b; padding: 0.4rem 1.1rem; font-size: 0.95rem; border-bottom: 2px solid transparent; margin-bottom: -1px; text-decoration: none; }
      .earnings-page-tabs a:hover { color: #1e293b; }
      .earnings-page-tabs a.active { color: #1e293b; font-weight: 600; border-bottom-color: #1e293b; }
      .earnings-total { background: white; border-radius: 12px; padding: 1.25rem 2rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 1.5rem; font-size: 1.05rem; }
      .earnings-total strong { font-size: 1.2rem; }
      .earnings-section { margin: 1.5rem 0 0.5rem; font-size: 1.1rem; font-weight: 600; color: #334155; }
      .earnings-subtabs { display: flex; gap: 0.5rem; margin: 0.5rem 0 1rem; border-bottom: 1px solid #e2e8f0; }
      .earnings-subtabs button { border: none; background: none; color: #64748b; padding: 0.4rem 1.1rem; font-size: 0.95rem; cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -1px; }
      .earnings-subtabs button:hover { color: #1e293b; }
      .earnings-subtabs button.active { color: #1e293b; font-weight: 600; border-bottom-color: #1e293b; }
      .earnings-table { width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .earnings-table th { background: #1e293b; color: white; padding: 0.6rem 1rem; text-align: right; font-size: 0.85rem; font-weight: 600; }
      .earnings-table th:first-child, .earnings-table td:first-child,
      .earnings-table th.left, .earnings-table td.left { text-align: left; }
      .earnings-table td { padding: 0.55rem 1rem; border-bottom: 1px solid #f1f5f9; font-size: 0.88rem; text-align: right; }
      .earnings-table tr:hover td { background: #f8fafc; }
      .earnings-table tr.sum td { font-weight: 700; background: #f1f5f9; border-top: 2px solid #1e293b; }
      .pos { color: #008300; }
      .neg { color: #e34948; }
      .warn { color: #b45309; font-size: 0.78rem; }
      .broker-tag { font-size: 0.68rem; background: #e0e7ff; color: #4338ca; border-radius: 4px; padding: 1px 5px; margin-left: 0.4rem; vertical-align: middle; white-space: nowrap; }
      .muted { color: #64748b; font-size: 0.78rem; }
      .earnings-table tr.asset-row { cursor: pointer; }
      .earnings-table tr.asset-row:hover td { background: #eef2f7; }
      .chevron { display: inline-block; width: 0.9rem; color: #64748b; font-size: 0.7rem; transition: transform 0.15s; margin-right: 0.35rem; }
      .chevron.open { transform: rotate(90deg); }
      .earnings-table tr.details-row td { padding: 0; background: #f8fafc; }
      .earnings-table tr.details-row .details-inner { padding: 0.5rem 1rem 0.9rem 2.25rem; }
      .details-table { width: 100%; border-collapse: collapse; font-size: 0.83rem; }
      .details-table th { text-align: right; font-weight: 600; color: #64748b; text-transform: uppercase; font-size: 0.68rem; letter-spacing: 0.03em; padding: 0.35rem 0.6rem; border-bottom: 1px solid #e2e8f0; }
      .details-table th:first-child, .details-table td:first-child, .details-table th.left, .details-table td.left { text-align: left; }
      .details-table td { padding: 0.35rem 0.6rem; border-bottom: 1px solid #f1f5f9; text-align: right; }
      .details-table tr:last-child td { border-bottom: none; }
      .chart-controls { display: flex; flex-direction: column; gap: 0.6rem; margin-bottom: 1rem; }
      .seg { display: inline-flex; align-self: flex-start; border: 1px solid #e2e8f0; border-radius: 6px; overflow: hidden; }
      .seg button { border: none; background: white; color: #475569; padding: 0.35rem 0.8rem; font-size: 0.82rem; cursor: pointer; }
      .seg button.selected { background: #1e293b; color: white; }
      .chart-keys { display: flex; flex-wrap: wrap; gap: 0.4rem; flex: 1; }
      .filter-groups { display: flex; flex-direction: column; gap: 0.4rem; }
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
      .key-btn { border: 1px solid #e2e8f0; background: white; color: #475569; padding: 0.35rem 0.75rem; border-radius: 6px; font-size: 0.82rem; cursor: pointer; display: inline-flex; align-items: center; gap: 0.4rem; }
      .key-btn:hover { background: #f1f5f9; }
      .key-btn.selected { border-color: #1e293b; color: #0b0b0b; font-weight: 600; }
      .key-dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; }
      .chart-note { margin: 0.5rem 0 1rem; }
    </style>

    <div class="earnings-page-tabs">
      <a href="/earnings" class="active">Overview</a>
      <a href="/earnings/monthly">Monthly</a>
    </div>

    <% total_sum = @realized_sum + @dividends_sum + @urbanitae_sum + @equito_sum + @unrealized_sum %>
    <div class="earnings-total">
      Realized <strong class={sign_class(@realized_sum)}><%= eur(@realized_sum) %></strong>
      + Dividends <strong class={sign_class(@dividends_sum)}><%= eur(@dividends_sum) %></strong>
      + Urbanitae <strong class={sign_class(@urbanitae_sum)}><%= eur(@urbanitae_sum) %></strong>
      + Equito <strong class={sign_class(@equito_sum)}><%= eur(@equito_sum) %></strong>
      + Unrealized <strong class={sign_class(@unrealized_sum)}><%= eur(@unrealized_sum) %></strong>
      = <strong class={sign_class(total_sum)}><%= eur(total_sum) %></strong>
    </div>

    <%= if @cumulative != [] do %>
      <div class="earnings-section">Over time</div>
      <div class="chart-controls">
        <div class="seg">
          <button class={if @chart_view == "category", do: "selected"} phx-click="chart_view" phx-value-view="category">By category</button>
          <button class={if @chart_view == "asset", do: "selected"} phx-click="chart_view" phx-value-view="asset">By asset</button>
        </div>
        <%= if @chart_view == "category" do %>
          <div class="chart-keys">
            <%= for {key, name} <- chart_options(assigns) do %>
              <.key_btn key={key} name={name} slot={chart_slot(assigns, key)} />
            <% end %>
          </div>
        <% else %>
          <div class="chart-keys">
            <.key_btn key="Total" name="Total" slot={chart_slot(assigns, "Total")} />
          </div>
          <div class="filter-groups">
            <%= for {group, assets} <- asset_groups(assigns) do %>
              <% open? = MapSet.member?(@opened, group) %>
              <% {state, icon, count} = group_state(assets, @chart_keys) %>
              <div class="filter-group">
                <button class="cat-header" phx-click="chart_group" phx-value-group={group}>
                  <span class="cat-chevron"><%= if open?, do: "▼", else: "▶" %></span>
                  <span class={"cat-state #{state}"}><%= icon %></span>
                  <span><%= group %></span>
                  <span class="cat-count"><%= count %>/<%= length(assets) %></span>
                </button>
                <div class="chart-keys">
                  <%= if open? do %>
                    <%= for {key, name} <- assets do %>
                      <.key_btn key={key} name={name} slot={chart_slot(assigns, key)} />
                    <% end %>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
      <div class="expand-panel" id="panel-chart" phx-hook="ExpandPanel">
        <button class="expand-btn" aria-label="Toggle full screen"></button>
        <div class="chart-container" id="earnings-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(earnings_chart(assigns))}>
          <div id="earnings-chart-canvas" phx-update="ignore">
            <canvas id="earningsChartCanvas"></canvas>
          </div>
        </div>
      </div>
      <div class="muted chart-note">
        Everything earned up to each month's end: unrealized, realized, dividends and the crowdfunding ledgers. A sold
        position keeps its result, and the first point carries what was earned before the snapshots began.
      </div>
    <% end %>

    <div class="earnings-section">Realized</div>
    <div class="earnings-subtabs">
      <button type="button" class={if @view == "by_asset", do: "active", else: ""} phx-click="set_view" phx-value-view="by_asset">
        By asset
      </button>
      <button type="button" class={if @view == "by_operation", do: "active", else: ""} phx-click="set_view" phx-value-view="by_operation">
        By operation
      </button>
      <button type="button" class={if @view == "tax", do: "active", else: ""} phx-click="set_view" phx-value-view="tax">
        Tax (FIFO)
      </button>
    </div>

    <%= cond do %>
    <% @view == "by_asset" -> %>
      <div class="expand-panel" id="panel-1" phx-hook="ExpandPanel">
        <button class="expand-btn" aria-label="Toggle full screen"></button>
        <table class="earnings-table">
          <tr>
            <th class="left">Asset</th>
            <th>Sells</th>
            <th>Qty sold</th>
            <th>Proceeds</th>
            <th>Cost basis</th>
            <th>Realized</th>
          </tr>
          <%= for row <- @by_asset do %>
            <% open? = MapSet.member?(@expanded_assets, row.asset) %>
            <tr class="asset-row" phx-click="toggle_asset" phx-value-asset={row.asset}>
              <td class="left">
                <span class={"chevron#{if open?, do: " open"}"}>▶</span><%= row.asset %>
                <%= if MapSet.member?(@trading212, row.isin) do %>
                  <span class="broker-tag">Trading212</span>
                <% end %>
                <%= if row.uncovered > 0.001 do %>
                  <div class="warn">⚠ <%= NumberFormat.number(row.uncovered) %> units without buy history — excluded</div>
                <% end %>
              </td>
              <td><%= row.sells %></td>
              <td><%= NumberFormat.qty(row.qty) %></td>
              <td><%= eur(row.proceeds) %></td>
              <td><%= eur(row.cost) %></td>
              <td class={sign_class(row.realized)}><%= eur(row.realized) %></td>
            </tr>
            <%= if open? do %>
              <tr class="details-row">
                <td colspan="6">
                  <div class="details-inner">
                    <table class="details-table">
                      <tr>
                        <th class="left">Fecha</th>
                        <th class="left">Tipo</th>
                        <th>Qty</th>
                        <th>Proceeds</th>
                        <th>Cost basis</th>
                        <th>Realized</th>
                      </tr>
                      <%= for e <- row.events do %>
                        <tr>
                          <td class="left"><%= e.fecha %></td>
                          <td class="left"><%= e.tipo %></td>
                          <td><%= NumberFormat.qty(e.qty) %></td>
                          <td><%= eur(e.proceeds) %></td>
                          <td><%= eur(e.cost) %></td>
                          <td class={sign_class(e.realized)}><%= eur(e.realized) %></td>
                        </tr>
                      <% end %>
                    </table>
                  </div>
                </td>
              </tr>
            <% end %>
          <% end %>
          <tr class="sum">
            <td class="left" colspan="5">Total realized</td>
            <td class={sign_class(@realized_sum)}><%= eur(@realized_sum) %></td>
          </tr>
        </table>
      </div>
    <% @view == "by_operation" -> %>
      <div class="expand-panel" id="panel-2" phx-hook="ExpandPanel">
        <button class="expand-btn" aria-label="Toggle full screen"></button>
        <table class="earnings-table">
          <tr>
            <th>Fecha</th><th class="left">Asset</th><th class="left">Tipo</th>
            <th>Qty</th><th>Proceeds</th><th>Cost basis</th><th>Realized</th>
          </tr>
          <%= for e <- @realized_events do %>
            <tr>
              <td class="left"><%= e.fecha %></td>
              <td class="left">
                <%= e.asset %>
                <%= if MapSet.member?(@trading212, e.isin) do %>
                  <span class="broker-tag">Trading212</span>
                <% end %>
                <%= if e.uncovered > 0.001 do %>
                  <div class="warn">⚠ <%= NumberFormat.number(e.uncovered) %> units without buy history — excluded</div>
                <% end %>
              </td>
              <td class="left"><%= e.tipo %></td>
              <td><%= NumberFormat.qty(e.qty) %></td>
              <td><%= eur(e.proceeds) %></td>
              <td><%= eur(e.cost) %></td>
              <td class={sign_class(e.realized)}><%= eur(e.realized) %></td>
            </tr>
          <% end %>
          <tr class="sum">
            <td class="left" colspan="6">Total realized</td>
            <td class={sign_class(@realized_sum)}><%= eur(@realized_sum) %></td>
          </tr>
        </table>
      </div>
    <% true -> %>
      <div class="earnings-total muted">
        Oldest units sold first, as the IRPF counts them, so yearly figures differ from the average-cost tabs.
        An estimate to prepare the return from: the two-month rule on losses isn't applied, and USD and CAD
        convert at the day's market rate, not what the broker charged.
      </div>
      <div class="expand-panel" id="panel-tax" phx-hook="ExpandPanel">
        <button class="expand-btn" aria-label="Toggle full screen"></button>
        <table class="earnings-table">
          <tr>
            <th class="left">Year / sale</th><th class="left">Tipo</th>
            <th>Qty</th><th>Proceeds</th><th>Cost basis</th><th>Gain</th>
          </tr>
          <%= for year <- @tax_years do %>
            <tr class="sum">
              <td class="left" colspan="3">
                <%= year.year %>
                <%= if year.uncovered > 0 do %>
                  <div class="warn">⚠ <%= year.uncovered %> sales include units without buy history — those are excluded</div>
                <% end %>
              </td>
              <td><%= eur(year.proceeds) %></td>
              <td><%= eur(year.cost) %></td>
              <td class={sign_class(year.gain)}><%= eur(year.gain) %></td>
            </tr>
            <%= for s <- year.sales do %>
              <tr>
                <td class="left"><%= s.fecha %> · <%= s.asset %></td>
                <td class="left"><%= s.tipo %></td>
                <td><%= NumberFormat.qty(s.qty) %></td>
                <td><%= eur(s.proceeds) %></td>
                <td><%= eur(s.cost) %></td>
                <td class={sign_class(s.gain)}><%= eur(s.gain) %></td>
              </tr>
            <% end %>
          <% end %>
        </table>
      </div>
    <% end %>

    <div class="earnings-section">Dividends — net cash distributions received</div>
    <%= if @dividends_by_asset == [] do %>
      <div class="earnings-total muted">No distributions recorded yet.</div>
    <% else %>
      <div class="expand-panel" id="panel-3" phx-hook="ExpandPanel">
        <button class="expand-btn" aria-label="Toggle full screen"></button>
        <table class="earnings-table">
          <tr>
            <th class="left">Asset</th><th>Payments</th><th>First</th><th>Last</th><th>Received</th>
          </tr>
          <%= for row <- @dividends_by_asset do %>
            <% open? = MapSet.member?(@expanded_dividends, row.asset) %>
            <tr class="asset-row" phx-click="toggle_dividend_asset" phx-value-asset={row.asset}>
              <td class="left">
                <span class={"chevron#{if open?, do: " open"}"}>▶</span><%= row.asset %>
              </td>
              <td><%= row.count %></td>
              <td><%= row.first_date %></td>
              <td><%= row.last_date %></td>
              <td class="pos"><%= eur(row.total) %></td>
            </tr>
            <%= if open? do %>
              <tr class="details-row">
                <td colspan="5">
                  <div class="details-inner">
                    <table class="details-table">
                      <tr><th class="left">Fecha</th><th>Amount</th></tr>
                      <%= for p <- row.payments do %>
                        <tr>
                          <td class="left"><%= p["date"] %></td>
                          <td class="pos"><%= eur(p["amount"]) %></td>
                        </tr>
                      <% end %>
                    </table>
                  </div>
                </td>
              </tr>
            <% end %>
          <% end %>
          <tr class="sum">
            <td class="left" colspan="4">Total dividends</td>
            <td class="pos"><%= eur(@dividends_sum) %></td>
          </tr>
        </table>
      </div>
    <% end %>

    <div class="earnings-section">Urbanitae — yield repaid and gains on closed projects</div>
    <%= if @urbanitae == [] do %>
      <div class="earnings-total muted">No Urbanitae earnings recorded yet.</div>
    <% else %>
      <div class="expand-panel" id="panel-4" phx-hook="ExpandPanel">
        <button class="expand-btn" aria-label="Toggle full screen"></button>
        <table class="earnings-table">
          <tr>
            <th class="left">Project</th><th class="left">Type</th><th class="left">Status</th>
            <th>Yield</th><th>Closure gain</th><th>Earnings</th>
          </tr>
          <%= for row <- @urbanitae do %>
            <tr>
              <td class="left"><%= row.project %></td>
              <td class="left"><%= row.type || "—" %></td>
              <td class="left"><%= row.status %></td>
              <td><%= eur(row.yield) %></td>
              <td><%= eur(row.closure_gain) %></td>
              <td class="pos"><%= eur(row.earnings) %></td>
            </tr>
          <% end %>
          <tr class="sum">
            <td class="left" colspan="5">Total Urbanitae</td>
            <td class="pos"><%= eur(@urbanitae_sum) %></td>
          </tr>
        </table>
      </div>
    <% end %>

    <div class="earnings-section">Equito — rent distributed, net of retention</div>
    <%= if @equito == [] do %>
      <div class="earnings-total muted">No Equito earnings recorded yet.</div>
    <% else %>
      <div class="expand-panel" id="panel-5" phx-hook="ExpandPanel">
        <button class="expand-btn" aria-label="Toggle full screen"></button>
        <table class="earnings-table">
          <tr>
            <th class="left">Property</th><th>Payouts</th>
            <th>Rent</th><th>Withheld</th><th>Earnings</th>
          </tr>
          <%= for row <- @equito do %>
            <tr>
              <td class="left"><%= row.label %></td>
              <td><%= row.payouts %></td>
              <td><%= eur(row.rent) %></td>
              <td><%= eur(row.withheld) %></td>
              <td class="pos"><%= eur(row.earnings) %></td>
            </tr>
          <% end %>
          <tr class="sum">
            <td class="left" colspan="4">Total Equito</td>
            <td class="pos"><%= eur(@equito_sum) %></td>
          </tr>
        </table>
      </div>
    <% end %>

    <div class="earnings-section">Unrealized — open positions at the latest snapshot</div>
    <div class="expand-panel" id="panel-6" phx-hook="ExpandPanel">
      <button class="expand-btn" aria-label="Toggle full screen"></button>
      <table class="earnings-table">
        <tr>
          <th class="left">Asset</th><th>Invested</th><th>Value</th><th>Unrealized</th>
        </tr>
        <%= for p <- Enum.sort_by(@unrealized, &(&1.invested - &1.value)) do %>
          <tr>
            <td class="left"><%= p.asset %></td>
            <td><%= eur(p.invested) %></td>
            <td><%= eur(p.value) %></td>
            <td class={sign_class(p.value - p.invested)}><%= eur(p.value - p.invested) %></td>
          </tr>
        <% end %>
        <tr class="sum">
          <td class="left" colspan="3">Total unrealized</td>
          <td class={sign_class(@unrealized_sum)}><%= eur(@unrealized_sum) %></td>
        </tr>
      </table>
    </div>
    """
  end

  defp group_by_asset(events) do
    events
    |> Enum.group_by(& &1.asset)
    |> Enum.map(fn {asset, evs} ->
      %{
        asset: asset,
        isin: hd(evs).isin,
        events: evs,
        sells: length(evs),
        qty: Enum.reduce(evs, 0.0, &(&1.qty + &2)),
        proceeds: Enum.reduce(evs, 0.0, &(&1.proceeds + &2)),
        cost: Enum.reduce(evs, 0.0, &(&1.cost + &2)),
        realized: Enum.reduce(evs, 0.0, &(&1.realized + &2)),
        uncovered: Enum.reduce(evs, 0.0, &(&1.uncovered + &2))
      }
    end)
    |> Enum.sort_by(& &1.realized, :desc)
  end

  # Yield repaid on projects still running, plus the surplus over capital on
  # ones that have closed — the same two components UrbanitaeTransactions
  # reports as a single earnings figure, split so the source is visible.
  defp urbanitae_earnings do
    Sheetfolio.UrbanitaeTransactions.all()
    |> Sheetfolio.UrbanitaeTransactions.rollup_by_project()
    |> Enum.map(&urbanitae_row/1)
    |> Enum.filter(&(&1.earnings > 0.005))
    |> Enum.sort_by(& &1.earnings, :desc)
  end

  defp urbanitae_row(project) do
    closure_gain = Float.round(max(project.principal_returned - project.invested, 0.0), 2)

    %{
      project: "#{project.city} · #{project.project}",
      type: project.type,
      status: project.status,
      yield: project.yield_returned,
      closure_gain: closure_gain,
      earnings: Float.round(project.yield_returned + closure_gain, 2)
    }
  end

  # Rent net of the retention, per property, plus the platform rewards as a row
  # of their own: they are money received but not a property's yield, and the
  # Portfolio card counts them in the same total.
  defp equito_earnings do
    transactions = Sheetfolio.EquitoTransactions.all()

    properties =
      transactions
      |> Sheetfolio.EquitoTransactions.rollup_by_property()
      |> Enum.map(&equito_row/1)
      |> Enum.filter(&(&1.earnings > 0.005))
      |> Enum.sort_by(& &1.earnings, :desc)

    properties ++ rewards_row(Sheetfolio.EquitoTransactions.totals(transactions))
  end

  defp equito_row(property) do
    %{
      label: property.code,
      payouts: property.payouts,
      rent: property.rent_gross,
      withheld: property.tax_withheld,
      earnings: property.net_income
    }
  end

  defp rewards_row(%{rewards: rewards}) when rewards > 0.005 do
    [%{label: "Rewards", payouts: "—", rent: 0.0, withheld: 0.0, earnings: rewards}]
  end

  defp rewards_row(_totals), do: []

  defp unrealized_positions do
    case Mongo.find_one(:mongo, "portfolio_snapshots", %{}, sort: %{date: -1}) do
      nil ->
        []

      doc ->
        for p <- doc["positions"], p["isin"] != "URBANITAE", is_number(p["value"]) do
          %{asset: p["asset"], invested: p["invested"], value: p["value"]}
        end
    end
  end

  defp eur(value), do: NumberFormat.eur(value)

  defp sign_class(value) when value < 0, do: "neg"
  defp sign_class(_value), do: "pos"
end
