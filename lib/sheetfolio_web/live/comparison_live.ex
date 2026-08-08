defmodule SheetfolioWeb.ComparisonLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.AssetCategories
  alias Sheetfolio.Positions
  alias Sheetfolio.UrbanitaeTransactions

  @presets ~w(1d 1w 1m 3m 1y ytd)
  @views ~w(category asset)
  @sort_keys ~w(from to flows earnings return)

  # Same hues the Portfolio doughnut uses, so a category keeps its colour here.
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

  def mount(params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket =
        assign(socket,
          authenticated: true,
          snapshots: [],
          cash: [],
          transactions: [],
          dividends_by_isin: %{},
          operations: [],
          fx: {nil, nil},
          categories: %{},
          view: "category",
          period: "1w",
          from_date: nil,
          to_date: nil,
          sort_key: "to",
          sort_dir: "desc"
        )

      if connected?(socket) do
        snapshots =
          Mongo.find(:mongo, "portfolio_snapshots", %{}, sort: %{date: 1})
          |> Enum.to_list()

        cash =
          Mongo.find(:mongo, "cash_snapshots", %{},
            sort: %{date: 1},
            projection: %{date: 1, total: 1}
          )
          |> Enum.to_list()

        period = normalize_period(params["period"])
        {from_date, to_date} = default_dates(snapshots, period)

        # The operation history is slow to load and the flow figures don't need
        # it — only the hover breakdown does — so fetch it off the render path.
        send(self(), :load_operations)

        {:ok,
         assign(socket,
           snapshots: snapshots,
           cash: cash,
           transactions: UrbanitaeTransactions.all(),
           dividends_by_isin: Enum.group_by(Sheetfolio.Dividends.all(), & &1["isin"]),
           fx: Sheetfolio.EarningsServer.get_fx_rates(),
           categories: AssetCategories.get(),
           period: period,
           from_date: from_date,
           to_date: to_date
         )}
      else
        {:ok, socket}
      end
    end
  end

  def handle_event("set_period", %{"period" => period}, socket) when period in @presets do
    {from_date, to_date} = default_dates(socket.assigns.snapshots, period)
    {:noreply, assign(socket, period: period, from_date: from_date, to_date: to_date)}
  end

  def handle_event("set_view", %{"view" => view}, socket) when view in @views do
    {:noreply, assign(socket, view: view)}
  end

  # First click on a column sorts it largest first; clicking the active column
  # again flips to ascending.
  def handle_event("set_sort", %{"key" => key}, socket) when key in @sort_keys do
    %{sort_key: current, sort_dir: dir} = socket.assigns
    new_dir = if current == key and dir == "desc", do: "asc", else: "desc"
    {:noreply, assign(socket, sort_key: key, sort_dir: new_dir)}
  end

  # Editing either date drops out of the presets — the pair is now whatever the
  # inputs say.
  def handle_event("set_dates", %{"from" => from, "to" => to}, socket) do
    from_date = if from != "", do: from, else: socket.assigns.from_date
    to_date = if to != "", do: to, else: socket.assigns.to_date
    {:noreply, assign(socket, period: "custom", from_date: from_date, to_date: to_date)}
  end

  # get_operations/1 blocks until the boot load finishes, so do it in a task and
  # keep the LiveView responsive; the breakdown appears once it lands.
  def handle_info(:load_operations, socket) do
    live = self()
    Task.start(fn -> send(live, {:operations, Sheetfolio.OperationsServer.get_operations(:infinity) || []}) end)
    {:noreply, socket}
  end

  def handle_info({:operations, operations}, socket) do
    {:noreply, assign(socket, operations: operations)}
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

  def render(assigns) do
    ~H"""
    <style>
      .cmp-controls { display: flex; flex-wrap: wrap; gap: 0.75rem; align-items: center; margin-bottom: 1rem; }
      .range-toggle { display: flex; border: 1px solid #e2e8f0; border-radius: 6px; overflow: hidden; }
      .range-toggle button { border: none; background: white; color: #475569; padding: 0.35rem 0.8rem; font-size: 0.82rem; cursor: pointer; }
      .range-toggle button.selected { background: #1e293b; color: white; }
      .cmp-view { margin-left: auto; }
      .date-bar { display: flex; flex-wrap: wrap; align-items: center; gap: 1rem; margin-bottom: 1.5rem; }
      .date-bar label { font-size: 0.85rem; font-weight: 600; color: #475569; }
      .es-date { position: relative; display: inline-flex; align-items: center; border: 1px solid #cbd5e1; border-radius: 6px; background: white; padding: 0 0.35rem 0 0.7rem; }
      .es-date-text { border: none; outline: none; padding: 0.4rem 0; font-size: 0.9rem; color: #1e293b; width: 6rem; background: transparent; font-variant-numeric: tabular-nums; }
      .es-date-btn { border: none; background: transparent; cursor: pointer; font-size: 0.95rem; line-height: 1; padding: 0.2rem 0.25rem; color: #475569; }
      .es-date-btn:hover { color: #1e293b; }
      .es-date-native { position: absolute; left: 0; bottom: 0; width: 100%; height: 1px; opacity: 0; pointer-events: none; }
      .headline { background: white; border-radius: 12px; padding: 1.25rem 1.5rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 1.5rem; }
      .headline-label { font-size: 0.72rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.4rem; }
      .headline-values { font-size: 1.35rem; font-weight: 700; color: #0f172a; }
      .headline-arrow { color: #94a3b8; margin: 0 0.5rem; font-weight: 400; }
      .headline-sub { font-size: 0.85rem; margin-top: 0.4rem; }
      .cmp-table { width: 100%; border-collapse: collapse; background: white; border-radius: 12px; box-shadow: 0 1px 4px rgba(0,0,0,0.08); font-variant-numeric: tabular-nums; }
      .cmp-table thead th:first-child { border-top-left-radius: 12px; }
      .cmp-table thead th:last-child { border-top-right-radius: 12px; }
      .cmp-table tfoot td:first-child { border-bottom-left-radius: 12px; }
      .cmp-table tfoot td:last-child { border-bottom-right-radius: 12px; }
      .flow-cell { position: relative; cursor: help; border-bottom: 1px dotted #94a3b8; }
      .flow-tip { position: absolute; right: 0; top: calc(100% + 6px); z-index: 30; display: none; background: #0f172a; color: #e2e8f0; border-radius: 8px; padding: 0.45rem 0.65rem; box-shadow: 0 8px 24px rgba(0,0,0,0.28); }
      .flow-cell:hover .flow-tip { display: block; }
      .flow-tip-row { display: grid; grid-template-columns: auto auto auto; gap: 0.15rem 0.9rem; align-items: baseline; font-size: 0.78rem; font-weight: 400; line-height: 1.55; white-space: nowrap; }
      .flow-tip.with-asset .flow-tip-row { grid-template-columns: auto auto auto auto; }
      .flow-tip-date { color: #94a3b8; }
      .flow-tip-asset { color: #e2e8f0; text-align: left; }
      .flow-tip-kind { color: #cbd5e1; text-align: left; }
      .flow-tip-amt { text-align: right; }
      .flow-tip .positive { color: #4ade80; }
      .flow-tip .negative { color: #f87171; }
      .cmp-table th { background: #1e293b; color: white; padding: 0.75rem 1rem; text-align: left; font-size: 0.85rem; font-weight: 600; letter-spacing: 0.03em; }
      .cmp-table th:not(:first-child) { text-align: right; }
      .cmp-table th.text, .cmp-table td.text { text-align: left; }
      .cmp-table th.sortable { cursor: pointer; user-select: none; white-space: nowrap; }
      .cmp-table th.sortable:hover { background: #0f172a; }
      .cmp-table td { padding: 0.65rem 1rem; border-bottom: 1px solid #f1f5f9; font-size: 0.9rem; }
      .cmp-table td:not(:first-child) { text-align: right; }
      .cmp-table tr:last-child td { border-bottom: none; }
      .cmp-table tr:hover td { background: #f8fafc; }
      .cmp-table tfoot td { background: #f8fafc; font-weight: 600; border-top: 2px solid #e2e8f0; }
      .cmp-dot { display: inline-block; width: 0.65rem; height: 0.65rem; border-radius: 50%; margin-right: 0.5rem; vertical-align: middle; }
      /* On a phone the column is narrow enough that "Renta fija corto plazo"
         breaks over three lines; the table already scrolls sideways, so let
         the name claim the width it needs and keep every row one line tall. */
      @media (max-width: 768px) {
        .cmp-table td.cat { white-space: nowrap; padding-left: 0.6rem; padding-right: 0.6rem; }
        .cmp-table th:first-child { padding-left: 0.6rem; padding-right: 0.6rem; }
      }
      .cmp-tag { font-size: 0.75rem; color: #94a3b8; }
      .cmp-table td.flow { color: #475569; font-weight: 600; }
      .positive { color: #16a34a; font-weight: 600; }
      .negative { color: #dc2626; font-weight: 600; }
      .empty-note { background: white; border-radius: 12px; padding: 2rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); color: #64748b; font-size: 0.9rem; }
    </style>

    <%= if @snapshots == [] do %>
      <div class="empty-note">
        No snapshots recorded yet. History accumulates one point per day once the recorder runs.
      </div>
    <% else %>
      <div class="cmp-controls">
        <div class="range-toggle">
          <%= for {value, label} <- preset_options() do %>
            <button class={if @period == value, do: "selected"} phx-click="set_period" phx-value-period={value}><%= label %></button>
          <% end %>
        </div>
        <div class="range-toggle cmp-view">
          <%= for {value, label} <- view_options() do %>
            <button class={if @view == value, do: "selected"} phx-click="set_view" phx-value-view={value}><%= label %></button>
          <% end %>
        </div>
      </div>

      <form class="date-bar" phx-change="set_dates">
        <label>From</label>
        <.es_date_field name="from" value={@from_date} min={first_date(@snapshots)} max={latest_date(@snapshots)} />
        <label>To</label>
        <.es_date_field name="to" value={@to_date} min={first_date(@snapshots)} max={latest_date(@snapshots)} />
      </form>

      <%= case comparison(assigns) do %>
        <% nil -> %>
          <div class="empty-note">
            No snapshot recorded on or before one of the chosen dates. Pick a later start date.
          </div>
        <% cmp -> %>
          <div class="headline">
            <div class="headline-label">Net worth — portfolio + cash + Urbanitae</div>
            <div class="headline-values">
              <%= eur(cmp.from_total) %><span class="headline-arrow">→</span><%= eur(cmp.to_total) %>
            </div>
            <div class="headline-sub">
              <span class={delta_class(cmp.delta)}><%= arrow(cmp.delta) %> <%= signed(cmp.delta) %></span>
              <%= if cmp.pct, do: "(#{signed_pct(cmp.pct)})" %>
              over <%= es_date(cmp.from_resolved) %> → <%= es_date(cmp.to_resolved) %>
            </div>
          </div>

          <table class="cmp-table">
            <thead>
              <tr>
                <th><%= if @view == "category", do: "Category", else: "Asset" %></th>
                <%= if @view == "asset" do %>
                  <th class="text">Category</th>
                <% end %>
                <th class="sortable" phx-click="set_sort" phx-value-key="from"><%= es_date(cmp.from_resolved) %> (€)<%= caret(@sort_key, @sort_dir, "from") %></th>
                <th class="sortable" phx-click="set_sort" phx-value-key="to"><%= es_date(cmp.to_resolved) %> (€)<%= caret(@sort_key, @sort_dir, "to") %></th>
                <th class="sortable" phx-click="set_sort" phx-value-key="flows">Money in/out (€)<%= caret(@sort_key, @sort_dir, "flows") %></th>
                <th class="sortable" phx-click="set_sort" phx-value-key="earnings">Earnings (€)<%= caret(@sort_key, @sort_dir, "earnings") %></th>
                <th class="sortable" phx-click="set_sort" phx-value-key="return">Return %<%= caret(@sort_key, @sort_dir, "return") %></th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- cmp.rows do %>
                <tr>
                  <td class={if @view == "category", do: "cat"}>
                    <%= if @view == "category" do %>
                      <span class="cmp-dot" style={"background:#{category_color(row.label)}"}></span>
                    <% end %>
                    <%= row.label %>
                  </td>
                  <%= if @view == "asset" do %>
                    <td class="text cat">
                      <span class="cmp-dot" style={"background:#{category_color(asset_category(row.key, @categories))}"}></span><%= asset_category(row.key, @categories) %>
                    </td>
                  <% end %>
                  <td><%= format_eur(row.from) %></td>
                  <td><%= format_eur(row.to) %></td>
                  <td class="flow">
                    <%= if row.events == [] do %>
                      <%= signed_or_dash(row.flows) %>
                    <% else %>
                      <span class="flow-cell">
                        <%= signed_or_dash(row.flows) %>
                        <span class={"flow-tip#{if @view == "category", do: " with-asset"}"}>
                          <%= for e <- row.events do %>
                            <span class="flow-tip-row">
                              <span class="flow-tip-date"><%= es_date(e.date) %></span>
                              <%= if @view == "category" do %>
                                <span class="flow-tip-asset"><%= e.asset %></span>
                              <% end %>
                              <span class="flow-tip-kind"><%= e.kind %></span>
                              <span class={"flow-tip-amt #{num_class(e.amount)}"}><%= signed(e.amount) %></span>
                            </span>
                          <% end %>
                        </span>
                      </span>
                    <% end %>
                  </td>
                  <td class={earnings_class(row.earnings)}><%= signed_or_dash(row.earnings) %></td>
                  <td class={return_class(row)}><%= return_display(row) %></td>
                </tr>
              <% end %>
            </tbody>
            <tfoot>
              <tr>
                <td>Total</td>
                <%= if @view == "asset" do %>
                  <td></td>
                <% end %>
                <td><%= format_eur(cmp.from_total) %></td>
                <td><%= format_eur(cmp.to_total) %></td>
                <td class="flow"><%= signed_or_dash(cmp.flows_total) %></td>
                <td class={num_class(cmp.earnings_total)}><%= signed_or_dash(cmp.earnings_total) %></td>
                <td class={num_class(cmp.return_total)}><%= if cmp.return_total, do: signed_pct(cmp.return_total), else: "—" %></td>
              </tr>
            </tfoot>
          </table>
      <% end %>
    <% end %>
    """
  end

  # --- comparison -----------------------------------------------------------

  # Both endpoints resolve to the nearest snapshot on or before the chosen day,
  # so a date the recorder happened to skip still lands on real figures. Cash
  # and Urbanitae are folded in exactly as the Portfolio net-worth card does, so
  # the totals here reconcile with the headline delta the user clicked through.
  defp comparison(assigns) do
    case {positions_at(assigns, assigns.from_date), positions_at(assigns, assigns.to_date)} do
      {nil, _} -> nil
      {_, nil} -> nil
      {from, to} -> build_comparison(assigns, from, to)
    end
  end

  defp build_comparison(assigns, from, to) do
    from_by_isin = Map.new(from.entries, &{&1.isin, &1})
    to_by_isin = Map.new(to.entries, &{&1.isin, &1})

    ctx = %{
      categories: assigns.categories,
      operations: assigns.operations,
      dividends_by_isin: assigns.dividends_by_isin,
      transactions: assigns.transactions,
      fx: assigns.fx,
      from: from.date,
      to: to.date
    }

    rows =
      MapSet.union(MapSet.new(Map.keys(from_by_isin)), MapSet.new(Map.keys(to_by_isin)))
      |> Enum.map(&metric(&1, from_by_isin, to_by_isin, ctx))
      |> rows_for(assigns.view)
      |> sort_rows(assigns.sort_key, assigns.sort_dir)

    from_total = total(rows, & &1.from)
    to_total = total(rows, & &1.to)
    flows_total = total(rows, & &1.flows)
    earnings_total = total(rows, & &1.earnings)
    delta = Float.round(to_total - from_total, 2)

    %{
      rows: rows,
      from_total: from_total,
      to_total: to_total,
      flows_total: flows_total,
      earnings_total: earnings_total,
      return_total: percentage(earnings_total, total(rows, & &1.base)),
      delta: delta,
      pct: percentage(delta, from_total),
      from_resolved: from.date,
      to_resolved: to.date
    }
  end

  # Splits one holding's value change into money moved in or out and the earnings
  # on top. Money in/out is a real trade — a change in units held — and shows as
  # the matching cost-basis move; a cost basis that shifts while the units stay
  # put is currency revaluation of a foreign holding, not a contribution, so it
  # stays in earnings. Cash and Urbanitae carry no units, so their whole basis
  # move counts (cash is all money in/out, Urbanitae's basis already isolates its
  # yield). Distributions are credited to earnings on top, everywhere the same.
  defp metric(isin, from_by_isin, to_by_isin, ctx) do
    from = Map.get(from_by_isin, isin)
    to = Map.get(to_by_isin, isin)

    value_from = amount(from, :value)
    value_to = amount(to, :value)
    dividends = amount(to, :dividends) - amount(from, :dividends)

    traded =
      if traded?(units(from), units(to)),
        do: amount(to, :invested) - amount(from, :invested),
        else: 0.0

    flows = Float.round(traded - dividends, 2)
    earnings = Float.round(value_to - value_from - flows, 2)
    name = label(to) || label(from)
    events = balance(events_for(isin, ctx), flows, isin, name, ctx.to)

    %{
      key: isin,
      label: name,
      category: AssetCategories.category_for(isin, ctx.categories),
      from: value_from,
      to: value_to,
      flows: flows,
      earnings: earnings,
      base: dietz_base(value_from, events, ctx),
      events: events
    }
  end

  # The capital the earnings were made on. Dividing them by the opening value
  # alone reads a category that grew mostly from contributions as a catastrophe
  # — a full-period loss over a balance that was a fraction of the money at
  # risk. So each flow is weighted by how much of the window it was invested
  # for (Modified Dietz). Sells have no date of their own: they arrive as the
  # balancing line `balance/4` stamps at the end of the window, which carries a
  # weight of zero, so a position sold down still measures against what it held
  # at the start.
  defp dietz_base(value_from, events, ctx) do
    days = day_offset(ctx.to, ctx.from) || 0
    weighted = Enum.reduce(events, 0.0, &(weight(&1.date, ctx.from, days) * &1.amount + &2))
    Float.round(value_from + weighted, 2)
  end

  defp weight(_date, _from, days) when days <= 0, do: 0.0

  defp weight(date, from, days) do
    case day_offset(date, from) do
      nil -> 0.0
      elapsed -> (days - elapsed) / days
    end
  end

  defp day_offset(date, from) do
    case {Date.from_iso8601(date), Date.from_iso8601(from)} do
      {{:ok, parsed_date}, {:ok, parsed_from}} -> Date.diff(parsed_date, parsed_from)
      _unparseable -> nil
    end
  end

  defp amount(nil, _key), do: 0.0
  defp amount(entry, key), do: Map.get(entry, key, 0.0)

  defp units(nil), do: nil
  defp units(entry), do: entry.units

  defp label(nil), do: nil
  defp label(entry), do: entry.label

  # No units on one side means a holding without units to compare (cash,
  # Urbanitae) or one fully bought or sold in the window — all real movements.
  defp traded?(nil, _to), do: true
  defp traded?(_from, nil), do: true
  defp traded?(from, to), do: from != to

  # The dated events behind a holding's money in/out, for the hover tooltip:
  # purchases from the operation history, distributions, and Urbanitae's own
  # movements. A purchase's recorded cost matches the cost basis the flow is
  # built from, so those reconcile; sells, closures and currency residue don't
  # map to a single operation, so `balance/4` folds whatever is left into one
  # "Withdrawal" line. Operations arrive after the first render, so until then a
  # market holding shows just that balancing line.
  defp events_for(isin, ctx) do
    (buy_events(isin, ctx) ++ dividend_events(isin, ctx) ++ urbanitae_events(isin, ctx))
    |> Enum.sort_by(& &1.date)
  end

  defp buy_events(isin, ctx) do
    ctx.operations
    |> Enum.filter(fn op -> buy?(op) and op.isin == isin and in_window?(iso_of(op.fecha), ctx) end)
    |> Enum.map(fn op ->
      %{date: iso_of(op.fecha), asset: Map.get(op, :asset, ""), amount: buy_amount(op, ctx.fx), kind: "Buy"}
    end)
  end

  defp buy?(%{traspaso: true}), do: false
  defp buy?(%{tipo: tipo}), do: tipo in ["Compra", "Suscripcion"]
  defp buy?(_op), do: false

  defp buy_amount(op, {eur_usd, eur_cad}) do
    {rate_usd, rate_cad} = op_fx(op, eur_usd, eur_cad)
    qty = Positions.parse_cantidad(Map.get(op, :cantidad, "0"))
    importe = Map.get(op, :importe_with_comision, "")
    Float.round(Positions.amount_in_eur(importe, Map.get(op, :precio, ""), qty, rate_usd, rate_cad), 2)
  end

  # A purchase converted at the operation's own day rate holds still; only fall
  # back to today's rate when the pin is missing.
  defp op_fx(%{fx_usd: usd, fx_cad: cad}, _eur_usd, _eur_cad) when is_number(usd) and is_number(cad),
    do: {usd, cad}

  defp op_fx(_op, eur_usd, eur_cad), do: {eur_usd, eur_cad}

  # Cash and Urbanitae already reconcile from their own ledgers; every other
  # holding gets the gap between its listed events and its actual money in/out
  # dropped in as a withdrawal (money out) or, rarely, an unexplained inflow.
  defp balance(events, _flows, isin, _name, _to) when isin in ["EFECTIVO", "URBANITAE"], do: events

  defp balance(events, flows, _isin, name, to) do
    gap = Float.round(flows - Enum.reduce(events, 0.0, &(&1.amount + &2)), 2)

    # Ignore sub-euro gaps: they're the cent-level rounding of summed buys, not a
    # real movement (sells and closures run to tens of euros or more).
    if abs(gap) < 0.5,
      do: events,
      else: events ++ [%{date: to, asset: name, amount: gap, kind: if(gap < 0, do: "Withdrawal", else: "Other")}]
  end

  defp dividend_events(isin, ctx) do
    ctx.dividends_by_isin
    |> Map.get(isin, [])
    |> Enum.filter(&in_window?(&1["date"], ctx))
    |> Enum.map(&%{date: &1["date"], asset: &1["asset"], amount: -Float.round(&1["amount"], 2), kind: "Dividend"})
  end

  defp urbanitae_events("URBANITAE", ctx) do
    ctx.transactions
    |> Enum.filter(&in_window?(&1["date"], ctx))
    |> Enum.map(&urbanitae_event/1)
  end

  defp urbanitae_events(_isin, _ctx), do: []

  defp urbanitae_event(%{"kind" => "investment"} = tx),
    do: %{date: tx["date"], asset: urbanitae_name(tx), amount: Float.round(tx["amount"], 2), kind: "Property"}

  defp urbanitae_event(%{"repayment_kind" => "principal"} = tx),
    do: %{date: tx["date"], asset: urbanitae_name(tx), amount: -Float.round(tx["amount"], 2), kind: "Property back"}

  defp urbanitae_event(tx),
    do: %{date: tx["date"], asset: urbanitae_name(tx), amount: -Float.round(tx["amount"], 2), kind: "Property yield"}

  defp urbanitae_name(tx), do: tx["project"] || "Urbanitae"

  defp in_window?(date, %{from: from, to: to}), do: date > from and date <= to

  defp iso_of(fecha) do
    case String.split(fecha, "/") do
      [day, month, year] ->
        "#{year}-#{String.pad_leading(month, 2, "0")}-#{String.pad_leading(day, 2, "0")}"

      _ ->
        fecha
    end
  end

  # The asset view is one row per holding; the category view rolls the per-ISIN
  # figures up so money in/out and earnings stay separated within each category.
  defp rows_for(metrics, "asset") do
    Enum.map(metrics, &Map.put(&1, :return_pct, percentage(&1.earnings, &1.base)))
  end

  defp rows_for(metrics, "category") do
    metrics
    |> Enum.group_by(& &1.category)
    |> Enum.map(fn {category, group} ->
      earnings = total(group, & &1.earnings)
      base = total(group, & &1.base)

      %{
        key: category,
        label: category,
        from: total(group, & &1.from),
        to: total(group, & &1.to),
        flows: total(group, & &1.flows),
        earnings: earnings,
        base: base,
        return_pct: percentage(earnings, base),
        events: group |> Enum.flat_map(& &1.events) |> Enum.sort_by(& &1.date)
      }
    end)
  end

  # A position opened inside the window has no starting value to earn a return
  # on, so it can't be ranked by Return % — those rows drop to the bottom rather
  # than pretend a number. Every other key is always present.
  defp sort_rows(rows, key, dir) do
    {sortable, rest} = Enum.split_with(rows, &(sort_value(&1, key) != nil))
    Enum.sort_by(sortable, &sort_value(&1, key), sort_order(dir)) ++ rest
  end

  defp sort_value(row, "from"), do: row.from
  defp sort_value(row, "to"), do: row.to
  defp sort_value(row, "flows"), do: row.flows
  defp sort_value(row, "earnings"), do: row.earnings
  defp sort_value(row, "return"), do: row.return_pct

  defp sort_order("asc"), do: :asc
  defp sort_order(_desc), do: :desc

  defp total(rows, fun), do: rows |> Enum.reduce(0.0, &(fun.(&1) + &2)) |> Float.round(2)

  # One entry per holding at a date: its value, cost basis, units held (nil for
  # cash and Urbanitae, which aren't unit-priced) and the distributions received
  # so far. Cash and Urbanitae are folded in the way the Portfolio net-worth card
  # does, so the totals reconcile with the headline delta.
  defp positions_at(assigns, date) do
    case snapshot_asof(assigns.snapshots, date) do
      nil -> nil
      snap -> %{date: snap["date"], entries: entries_at(snap, assigns)}
    end
  end

  defp entries_at(snap, assigns) do
    resolved = snap["date"]

    (snap["positions"] || [])
    |> Enum.filter(&(&1["isin"] != "URBANITAE" and is_number(&1["value"]) and &1["value"] > 0))
    |> Enum.map(&market_entry(&1, assigns.dividends_by_isin, resolved))
    |> Enum.concat(urbanitae_entry(assigns.transactions, resolved))
    |> Enum.concat(cash_entry(assigns.cash, resolved))
  end

  defp market_entry(position, dividends_by_isin, date) do
    %{
      isin: position["isin"],
      label: position["asset"],
      value: number(position["value"]),
      invested: number(position["invested"]),
      units: position["units"],
      dividends: dividends_to(dividends_by_isin, position["isin"], date)
    }
  end

  defp dividends_to(dividends_by_isin, isin, date) do
    dividends_by_isin
    |> Map.get(isin, [])
    |> Enum.reduce(0.0, fn payment, acc ->
      if payment["date"] <= date, do: acc + payment["amount"], else: acc
    end)
    |> Float.round(2)
  end

  # Urbanitae's yield leaves the outstanding balance the moment it's repaid, so
  # treating the whole balance as cost basis would hide every gain. Setting the
  # basis to outstanding minus cumulative earnings makes the split credit that
  # yield as earnings and count only the net cash movement as money in/out.
  defp urbanitae_entry(transactions, date) do
    case UrbanitaeTransactions.state_at(transactions, date) do
      {outstanding, earnings} when outstanding > 0 ->
        [
          %{
            isin: "URBANITAE",
            label: "Urbanitae",
            value: Float.round(outstanding, 2),
            invested: Float.round(outstanding - earnings, 2),
            units: nil,
            dividends: 0.0
          }
        ]

      _ ->
        []
    end
  end

  defp cash_entry(cash, date) do
    case cash_at(cash, date) do
      nil ->
        []

      amount ->
        [%{isin: "EFECTIVO", label: "Cash", value: amount, invested: amount, units: nil, dividends: 0.0}]
    end
  end

  defp snapshot_asof(_snapshots, nil), do: nil

  defp snapshot_asof(snapshots, date) do
    snapshots |> Enum.take_while(&(&1["date"] <= date)) |> List.last()
  end

  defp cash_at(cash, date) do
    cash
    |> Enum.take_while(&(&1["date"] <= date))
    |> List.last()
    |> case do
      nil -> nil
      doc -> doc["total"]
    end
  end

  # --- dates ----------------------------------------------------------------

  defp default_dates([], _period), do: {nil, nil}

  defp default_dates(snapshots, period) do
    latest = latest_date(snapshots)
    {shift_date(latest, period), latest}
  end

  defp shift_date(date, period) do
    day = Date.from_iso8601!(date)

    case period do
      "1d" -> Date.shift(day, day: -1)
      "1w" -> Date.shift(day, day: -7)
      "1m" -> Date.shift(day, month: -1)
      "3m" -> Date.shift(day, month: -3)
      "1y" -> Date.shift(day, year: -1)
      "ytd" -> Date.new!(day.year, 1, 1)
    end
    |> Date.to_iso8601()
  end

  defp normalize_period(period) when period in @presets, do: period
  defp normalize_period(_period), do: "1w"

  defp latest_date([]), do: nil
  defp latest_date(snapshots), do: List.last(snapshots)["date"]

  defp first_date([]), do: nil
  defp first_date([first | _rest]), do: first["date"]

  # --- formatting -----------------------------------------------------------

  defp preset_options,
    do: [{"1d", "1D"}, {"1w", "1W"}, {"1m", "1M"}, {"3m", "3M"}, {"1y", "1Y"}, {"ytd", "YTD"}]

  defp view_options, do: [{"category", "By category"}, {"asset", "By asset"}]

  defp category_color(category), do: Map.get(@category_colors, category, @other_color)

  # dd/mm/yyyy, the Spanish convention the rest of the app's dates follow.
  defp es_date(nil), do: ""

  defp es_date(iso) do
    case String.split(iso, "-") do
      [year, month, day] -> "#{day}/#{month}/#{year}"
      _ -> iso
    end
  end

  defp asset_category(isin, categories), do: AssetCategories.category_for(isin, categories)

  defp caret(active, "asc", column) when active == column, do: " ▲"
  defp caret(active, "desc", column) when active == column, do: " ▼"
  defp caret(_active, _dir, _column), do: ""

  defp percentage(_change, base) when base in [0, 0.0] or base < 0, do: nil
  defp percentage(change, base), do: Float.round(change / base * 100, 2)

  defp return_display(%{from: from, to: to}) when from in [0, 0.0] and to > 0, do: "new"
  defp return_display(%{to: to}) when to in [0, 0.0], do: "closed"
  defp return_display(%{return_pct: nil}), do: "—"
  defp return_display(%{return_pct: pct}) when pct == 0, do: "—"
  defp return_display(%{return_pct: pct}), do: signed_pct(pct)

  # A brand-new or fully-closed position shows a tag rather than a return, so it
  # stays neutral; everything else is coloured by the sign of its return.
  defp return_class(%{from: from, to: to}) when from in [0, 0.0] or to in [0, 0.0], do: ""
  defp return_class(%{return_pct: pct}), do: num_class(pct)

  defp earnings_class(value) when value == 0, do: ""
  defp earnings_class(value), do: num_class(value)

  defp num_class(nil), do: ""
  defp num_class(value) when value >= 0, do: "positive"
  defp num_class(_value), do: "negative"

  defp delta_class(nil), do: ""
  defp delta_class(value) when value >= 0, do: "positive"
  defp delta_class(_value), do: "negative"

  defp number(value) when is_number(value), do: value * 1.0
  defp number(_value), do: 0.0

  defp arrow(value) when value >= 0, do: "▲"
  defp arrow(_value), do: "▼"

  defp format_eur(nil), do: "—"
  defp format_eur(value), do: "#{:erlang.float_to_binary(value * 1.0, decimals: 2)} €"

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

  # Zero contributions or zero earnings are the common case for a held position,
  # so they read as a dash and the rows that actually moved money stand out.
  defp signed_or_dash(value) when value == 0, do: "—"
  defp signed_or_dash(value), do: signed(value)

  defp signed_pct(value) when value == 0, do: "0%"
  defp signed_pct(value) when value > 0, do: "+#{value}%"
  defp signed_pct(value), do: "#{value}%"
end
