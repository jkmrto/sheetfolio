defmodule SheetfolioWeb.ComparisonLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.AssetCategories
  alias Sheetfolio.UrbanitaeTransactions

  @presets ~w(1d 1w 1m 3m 1y ytd)
  @views ~w(category asset)

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
          categories: %{},
          view: "category",
          period: "1w",
          from_date: nil,
          to_date: nil
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

        {:ok,
         assign(socket,
           snapshots: snapshots,
           cash: cash,
           transactions: UrbanitaeTransactions.all(),
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

  # Editing either date drops out of the presets — the pair is now whatever the
  # inputs say.
  def handle_event("set_dates", %{"from" => from, "to" => to}, socket) do
    from_date = if from != "", do: from, else: socket.assigns.from_date
    to_date = if to != "", do: to, else: socket.assigns.to_date
    {:noreply, assign(socket, period: "custom", from_date: from_date, to_date: to_date)}
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
      .date-bar input[type=date] { padding: 0.4rem 0.7rem; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 0.9rem; color: #1e293b; background: white; }
      .headline { background: white; border-radius: 12px; padding: 1.25rem 1.5rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 1.5rem; }
      .headline-label { font-size: 0.72rem; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.4rem; }
      .headline-values { font-size: 1.35rem; font-weight: 700; color: #0f172a; }
      .headline-arrow { color: #94a3b8; margin: 0 0.5rem; font-weight: 400; }
      .headline-sub { font-size: 0.85rem; margin-top: 0.4rem; }
      .cmp-table { width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.08); font-variant-numeric: tabular-nums; }
      .cmp-table th { background: #1e293b; color: white; padding: 0.75rem 1rem; text-align: left; font-size: 0.85rem; font-weight: 600; letter-spacing: 0.03em; }
      .cmp-table th:not(:first-child) { text-align: right; }
      .cmp-table td { padding: 0.65rem 1rem; border-bottom: 1px solid #f1f5f9; font-size: 0.9rem; }
      .cmp-table td:not(:first-child) { text-align: right; }
      .cmp-table tr:last-child td { border-bottom: none; }
      .cmp-table tr:hover td { background: #f8fafc; }
      .cmp-table tfoot td { background: #f8fafc; font-weight: 600; border-top: 2px solid #e2e8f0; }
      .cmp-dot { display: inline-block; width: 0.65rem; height: 0.65rem; border-radius: 50%; margin-right: 0.5rem; vertical-align: middle; }
      .cmp-tag { font-size: 0.75rem; color: #94a3b8; }
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
        <input type="date" name="from" value={@from_date}
               min={first_date(@snapshots)} max={latest_date(@snapshots)} />
        <label>To</label>
        <input type="date" name="to" value={@to_date}
               min={first_date(@snapshots)} max={latest_date(@snapshots)} />
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
              over <%= cmp.from_resolved %> → <%= cmp.to_resolved %>
            </div>
          </div>

          <table class="cmp-table">
            <thead>
              <tr>
                <th><%= if @view == "category", do: "Category", else: "Asset" %></th>
                <th><%= cmp.from_resolved %> (€)</th>
                <th><%= cmp.to_resolved %> (€)</th>
                <th>Change (€)</th>
                <th>Change (%)</th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- cmp.rows do %>
                <tr>
                  <td>
                    <%= if @view == "category" do %>
                      <span class="cmp-dot" style={"background:#{category_color(row.label)}"}></span>
                    <% end %>
                    <%= row.label %>
                  </td>
                  <td><%= format_eur(row.from) %></td>
                  <td><%= format_eur(row.to) %></td>
                  <td class={delta_class(row.delta)}><%= signed(row.delta) %></td>
                  <td class={delta_class(row.delta)}><%= pct_display(row) %></td>
                </tr>
              <% end %>
            </tbody>
            <tfoot>
              <tr>
                <td>Total</td>
                <td><%= format_eur(cmp.from_total) %></td>
                <td><%= format_eur(cmp.to_total) %></td>
                <td class={delta_class(cmp.delta)}><%= signed(cmp.delta) %></td>
                <td class={delta_class(cmp.delta)}><%= if cmp.pct, do: signed_pct(cmp.pct), else: "—" %></td>
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
    from_map = grouped(from.positions, assigns.view, assigns.categories)
    to_map = grouped(to.positions, assigns.view, assigns.categories)

    rows =
      MapSet.union(MapSet.new(Map.keys(from_map)), MapSet.new(Map.keys(to_map)))
      |> Enum.map(&row(&1, from_map, to_map))
      |> Enum.sort_by(&{-&1.to, -&1.from})

    from_total = total(rows, & &1.from)
    to_total = total(rows, & &1.to)
    delta = Float.round(to_total - from_total, 2)

    %{
      rows: rows,
      from_total: from_total,
      to_total: to_total,
      delta: delta,
      pct: percentage(delta, from_total),
      from_resolved: from.date,
      to_resolved: to.date
    }
  end

  defp row(key, from_map, to_map) do
    from = Map.get(from_map, key)
    to = Map.get(to_map, key)
    from_value = value_of(from)
    to_value = value_of(to)
    delta = Float.round(to_value - from_value, 2)

    %{
      label: (to && to.label) || from.label,
      from: from_value,
      to: to_value,
      delta: delta,
      pct: percentage(delta, from_value)
    }
  end

  defp value_of(nil), do: 0.0
  defp value_of(%{value: value}), do: value

  defp total(rows, fun), do: rows |> Enum.reduce(0.0, &(fun.(&1) + &2)) |> Float.round(2)

  defp grouped(positions, "category", categories) do
    positions
    |> AssetCategories.breakdown(categories)
    |> Map.new(&{&1.category, %{label: &1.category, value: &1.value}})
  end

  defp grouped(positions, "asset", _categories) do
    positions
    |> Enum.filter(&(is_number(&1["value"]) and &1["value"] > 0))
    |> Map.new(&{&1["isin"], %{label: &1["asset"], value: Float.round(&1["value"] * 1.0, 2)}})
  end

  # A snapshot with cash and the outstanding Urbanitae balance folded in, the
  # same shape the Portfolio doughnut and net-worth card feed on.
  defp positions_at(assigns, date) do
    case snapshot_asof(assigns.snapshots, date) do
      nil -> nil
      snap -> %{date: snap["date"], positions: fold_extras(snap, assigns)}
    end
  end

  defp fold_extras(snap, assigns) do
    resolved = snap["date"]

    (snap["positions"] || [])
    |> Enum.reject(&(&1["isin"] == "URBANITAE"))
    |> Enum.concat(urbanitae_entry(assigns.transactions, resolved))
    |> Enum.concat(cash_entry(assigns.cash, resolved))
  end

  defp urbanitae_entry(transactions, date) do
    case UrbanitaeTransactions.state_at(transactions, date) do
      {outstanding, _earnings} when outstanding > 0 ->
        [%{"isin" => "URBANITAE", "asset" => "Urbanitae", "value" => Float.round(outstanding, 2)}]

      _ ->
        []
    end
  end

  defp cash_entry(cash, date) do
    case cash_at(cash, date) do
      nil -> []
      amount -> [%{"isin" => "EFECTIVO", "asset" => "Cash", "value" => amount}]
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

  defp percentage(_change, base) when base in [0, 0.0] or base < 0, do: nil
  defp percentage(change, base), do: Float.round(change / base * 100, 2)

  defp pct_display(%{from: from, to: to}) when from in [0, 0.0] and to > 0, do: "new"
  defp pct_display(%{to: to}) when to in [0, 0.0], do: "closed"
  defp pct_display(%{pct: nil}), do: "—"
  defp pct_display(%{pct: pct}), do: signed_pct(pct)

  defp delta_class(nil), do: ""
  defp delta_class(value) when value >= 0, do: "positive"
  defp delta_class(_value), do: "negative"

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

  defp signed_pct(value) when value >= 0, do: "+#{value}%"
  defp signed_pct(value), do: "#{value}%"
end
