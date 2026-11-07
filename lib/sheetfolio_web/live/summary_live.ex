defmodule SheetfolioWeb.SummaryLive do
  use SheetfolioWeb, :live_view

  alias SheetfolioWeb.NumberFormat

  alias Sheetfolio.{AssetCategories, Returns}

  @sort_columns Map.new(
                  ~w(asset category net_qty invested current_value weight gain gain_pct xirr sold_cost total_received pnl pnl_pct)a,
                  &{Atom.to_string(&1), &1}
                )

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()

      socket = assign(socket,
        authenticated: true,
        assets: %{},
        categories: AssetCategories.get(),
        dividends: %{},
        flows: %{},
        sort: default_sort(socket.assigns.live_action),
        eur_usd: eur_usd,
        eur_cad: eur_cad
      )

      if connected?(socket) do
        operations = Sheetfolio.OperationsServer.get_operations() || []

        assets = Sheetfolio.Positions.build(operations, eur_usd, eur_cad)

        ops_by_isin = Enum.group_by(operations, & &1.isin)

        pid = self()

        assets
        |> Enum.filter(fn {_, a} -> a.net_qty > 0.001 end)
        |> Enum.each(fn {isin, _} -> Sheetfolio.EarningsServer.request_price(isin, pid) end)

        dividend_docs = Sheetfolio.Dividends.all()
        dividends = Sheetfolio.Dividends.totals_by_isin(dividend_docs)
        flows = operations |> Sheetfolio.Positions.cash_flows(eur_usd, eur_cad) |> Returns.flows_by_isin(dividend_docs)

        {:ok, assign(socket, assets: assets, ops_by_isin: ops_by_isin, dividends: dividends, flows: flows, selected_isin: nil)}
      else
        {:ok, assign(socket, ops_by_isin: %{}, selected_isin: nil)}
      end
    end
  end

  def handle_info({:price_result, _isin, nil}, socket) do
    {:noreply, socket}
  end

  def handle_info({:price_result, isin, price_eur}, socket) do
    assets = Map.update!(socket.assigns.assets, isin, fn a ->
      current_value = Float.round(a.net_qty * price_eur, 2)
      earnings_abs = Float.round(current_value - a.cost_basis, 2)
      earnings_pct = if a.cost_basis != 0.0, do: Float.round(earnings_abs / a.cost_basis * 100, 2), else: nil
      %{a | current_value: current_value, earnings_abs: earnings_abs, earnings_pct: earnings_pct}
    end)

    {:noreply, assign(socket, assets: assets)}
  end

  def handle_event("toggle_isin", %{"isin" => isin}, socket) do
    selected = if socket.assigns.selected_isin == isin, do: nil, else: isin
    {:noreply, assign(socket, selected_isin: selected)}
  end

  def handle_event("sort", %{"column" => column}, socket) do
    key = Map.fetch!(@sort_columns, column)
    {:noreply, update(socket, :sort, &next_sort(&1, key))}
  end

  def handle_event("refresh_prices", _, socket) do
    Sheetfolio.EarningsServer.clear_price_cache()

    assets = Map.new(socket.assigns.assets, fn {isin, a} ->
      {isin, %{a | current_value: nil, earnings_abs: nil, earnings_pct: nil}}
    end)

    pid = self()
    assets
    |> Enum.filter(fn {_, a} -> a.net_qty > 0.001 end)
    |> Enum.each(fn {isin, _} -> Sheetfolio.EarningsServer.request_price(isin, pid) end)

    {:noreply, assign(socket, assets: assets)}
  end

  def render(assigns) do
    ~H"""
    <style>
      main:has(.assets-subtabs) { max-width: 1400px; }
      .assets-subtabs { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; border-bottom: 1px solid #e2e8f0; }
      .assets-subtabs a { color: #64748b; padding: 0.4rem 1.1rem; font-size: 0.95rem; border-bottom: 2px solid transparent; margin-bottom: -1px; text-decoration: none; }
      .assets-subtabs a:hover { color: #1e293b; }
      .assets-subtabs a.active { color: #1e293b; font-weight: 600; border-bottom-color: #1e293b; }
      .summary-table { width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .summary-table th { background: #1e293b; color: white; padding: 0.75rem 1rem; text-align: left; font-size: 0.85rem; font-weight: 600; letter-spacing: 0.03em; position: sticky; top: 0; z-index: 1; box-shadow: 1px 0 0 #1e293b; }
      .summary-table th:not(:first-child) { text-align: right; }
      .xirr-note { color: #64748b; font-size: 0.85rem; margin-bottom: 1rem; }
      .sort-btn { all: unset; cursor: pointer; white-space: nowrap; }
      .sort-btn:hover { text-decoration: underline; }
      .sort-icon { display: inline-block; margin-left: 0.3rem; opacity: 0.55; }
      .sort-icon:not(.current) { font-size: 1.35em; line-height: 1; vertical-align: -0.05em; }
      .sort-icon.current { opacity: 1; }
      .sort-btn:focus-visible { outline: 2px solid white; outline-offset: 2px; }
      .summary-table td { padding: 0.65rem 1rem; border-bottom: 1px solid #f1f5f9; font-size: 0.9rem; }
      .summary-table td:not(:first-child) { text-align: right; }
      .summary-table th, .summary-table td { padding-left: 0.7rem; padding-right: 0.7rem; }
      .summary-table th.category-col, .summary-table td.category-col { text-align: left; white-space: nowrap; color: #475569; }
      .summary-table th.category-col { color: white; }
      .summary-table tr:last-child td { border-bottom: none; }
      .summary-table tr:hover td { background: #f8fafc; }
      .summary-table tfoot td { background: #f8fafc; font-weight: 600; border-top: 2px solid #e2e8f0; }
      .dividends-note { color: #64748b; font-weight: 400; white-space: nowrap; }
      @media (max-width: 1200px) { .summary-table { display: block; overflow-x: auto; } }
      .positive { color: #16a34a; font-weight: 600; }
      .negative { color: #dc2626; font-weight: 600; }
      .positions-subtabs { display: flex; gap: 0.5rem; border-bottom: 1px solid #e2e8f0; flex: 1; }
      .positions-subtabs a { border: none; background: none; color: #64748b; padding: 0.4rem 1.1rem; font-size: 0.95rem; cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -1px; text-decoration: none; }
      .positions-subtabs a:hover { color: #1e293b; }
      .positions-subtabs a.active { color: #1e293b; font-weight: 600; border-bottom-color: #1e293b; }
      .positions-bar { display: flex; align-items: flex-end; gap: 1rem; margin-bottom: 1rem; }
    </style>

    <div class="assets-subtabs">
      <.link navigate="/summary" class="active">Positions</.link>
      <.link navigate="/operations">Operations</.link>
    </div>

    <div class="positions-bar">
      <div class="positions-subtabs">
        <.link navigate="/summary" class={if @live_action == :active, do: "active", else: ""}>Active</.link>
        <.link navigate="/summary/settled" class={if @live_action == :settled, do: "active", else: ""}>Settled</.link>
      </div>
      <button phx-click="refresh_prices" style="background: #1e293b; color: white; border: none; padding: 0.4rem 0.9rem; border-radius: 6px; font-size: 0.85rem; cursor: pointer; white-space: nowrap;">
        ↺ Refresh prices
      </button>
    </div>

    <%= if map_size(@assets) > 0 do %>
      <% overall = overall_xirr(@assets, @flows) %>
      <p class="xirr-note">
        Annualized return (XIRR) of everything held or sold:
        <strong class={earnings_class(overall)}><%= format_pct(overall) %></strong>.
        It accounts for when each euro went in and came out, dividends included.
        Excludes Urbanitae, Equito and coins held on exchanges.
      </p>
    <% end %>

    <%= if @live_action == :active do %>
      <%= render_active(assigns) %>
    <% else %>
      <%= render_settled(assigns) %>
    <% end %>
    """
  end

  defp render_active(assigns) do
    ~H"""
    <%= if map_size(@assets) > 0 do %>
      <% active = @assets |> Map.values() |> Enum.filter(& &1.net_qty > 0.001) %>
      <% meaningful = Enum.filter(active, & &1.cost_basis > 0) %>
      <% total_invested = Enum.reduce(meaningful, 0, fn a, acc -> acc + a.cost_basis end) %>
      <% total_value = meaningful |> Enum.filter(& &1.current_value) |> Enum.reduce(0, fn a, acc -> acc + a.current_value end) %>
      <% total_dividends = Enum.reduce(meaningful, 0, fn a, acc -> acc + Map.get(@dividends, a.isin, 0.0) end) %>
      <% total_earnings = if total_invested > 0, do: Float.round(total_value + total_dividends - total_invested, 2), else: nil %>
      <% total_pct = if total_invested > 0 and total_earnings, do: Float.round(total_earnings / total_invested * 100, 2), else: nil %>
      <% held_value = active |> Enum.map(& &1.current_value) |> Enum.reject(&is_nil/1) |> Enum.sum() %>

      <div class="expand-panel" id="panel-1" phx-hook="ExpandPanel">
        <button class="expand-btn" aria-label="Toggle full screen"></button>
        <table class="summary-table">
          <thead>
            <tr>
              <.sort_header sort={@sort} column={:asset} label="Asset" />
              <.sort_header sort={@sort} column={:category} label="Category" class="category-col" />
              <.sort_header sort={@sort} column={:net_qty} label="Units held" />
              <.sort_header sort={@sort} column={:invested} label="Invested (€)" />
              <.sort_header sort={@sort} column={:current_value} label="Current Value (€)" />
              <.sort_header sort={@sort} column={:weight} label="Weight (%)" />
              <.sort_header sort={@sort} column={:gain} label="Gain/Loss (€)" />
              <.sort_header sort={@sort} column={:gain_pct} label="Gain/Loss (%)" />
              <.sort_header sort={@sort} column={:xirr} label="XIRR (%)" />
            </tr>
          </thead>
          <tbody>
            <%= for a <- active |> Enum.map(&active_row(&1, @categories, @dividends, held_value, @flows)) |> sort_rows(@sort) do %>
              <tr>
                <td><strong><%= a.asset %></strong><br/><small style="color:#94a3b8"><%= a.isin %></small></td>
                <td class="category-col"><%= a.category %></td>
                <td><%= format_qty(a.net_qty) %></td>
                <td><%= format_eur(a.invested) %></td>
                <td><%= format_eur(a.current_value) %></td>
                <td><%= NumberFormat.pct(a.weight) %></td>
                <td class={earnings_class(a.gain)}>
                  <%= format_abs(a.gain) %>
                  <%= if a.dividends > 0 do %><br/><small class="dividends-note">incl. <%= format_eur(a.dividends) %> dividends</small><% end %>
                </td>
                <td class={earnings_class(a.gain_pct)}><%= format_pct(a.gain_pct) %></td>
                <.xirr_cell row={a} />
              </tr>
            <% end %>
          </tbody>
          <tfoot>
            <tr>
              <td>Total</td>
              <td></td>
              <td></td>
              <td><%= format_eur(total_invested) %></td>
              <td><%= format_eur(total_value) %></td>
              <td><%= NumberFormat.pct(if held_value > 0, do: 100) %></td>
              <td class={earnings_class(total_earnings)}><%= format_abs(total_earnings) %></td>
              <td class={earnings_class(total_pct)}><%= format_pct(total_pct) %></td>
              <% active_xirr = active_xirr(active, @flows) %>
              <td class={earnings_class(active_xirr)}><%= format_pct(active_xirr) %></td>
            </tr>
          </tfoot>
        </table>
      </div>
    <% end %>
    """
  end

  defp render_settled(assigns) do
    ~H"""
    <style>
      .row-clickable { cursor: pointer; }
      .row-clickable:hover td { background: #f1f5f9 !important; }
      .row-toggle-icon { float: right; color: #94a3b8; font-size: 0.8rem; }
      .ops-detail td { background: #f8fafc; font-size: 0.82rem; padding: 0.4rem 1rem; border-bottom: 1px solid #e2e8f0; }
      .ops-detail td:not(:first-child) { text-align: right; }
      .ops-detail th { background: #e2e8f0; color: #475569; font-size: 0.78rem; padding: 0.35rem 1rem; text-align: right; }
      .ops-detail th:first-child { text-align: left; }
      .ops-buy { color: #16a34a; }
      .ops-sell { color: #dc2626; }
    </style>
    <%= if map_size(@assets) > 0 do %>
      <% settled = @assets |> Map.values() |> Enum.filter(& &1.total_received > 0) |> Enum.map(&settled_row(&1, @categories, @flows)) %>
      <% total_invested = Enum.reduce(settled, 0, fn a, acc -> acc + a.sold_cost end) %>
      <% total_received = Enum.reduce(settled, 0, fn a, acc -> acc + a.total_received end) %>
      <% total_pnl = Float.round(total_received - total_invested, 2) %>
      <% total_pct = if total_invested > 0, do: Float.round(total_pnl / total_invested * 100, 2), else: nil %>

      <div class="expand-panel" id="panel-2" phx-hook="ExpandPanel">
        <button class="expand-btn" aria-label="Toggle full screen"></button>
        <table class="summary-table">
          <thead>
            <tr>
              <.sort_header sort={@sort} column={:asset} label="Asset" />
              <.sort_header sort={@sort} column={:category} label="Category" class="category-col" />
              <.sort_header sort={@sort} column={:sold_cost} label="Cost of sold (€)" />
              <.sort_header sort={@sort} column={:total_received} label="Received (€)" />
              <.sort_header sort={@sort} column={:pnl} label="Realized P&L (€)" />
              <.sort_header sort={@sort} column={:pnl_pct} label="Realized P&L (%)" />
              <.sort_header sort={@sort} column={:xirr} label="XIRR (%)" />
            </tr>
          </thead>
          <tbody>
            <%= for a <- sort_rows(settled, @sort) do %>
              <% expanded = @selected_isin == a.isin %>
              <% partial = a.net_qty > 0.001 %>
              <tr class="row-clickable" phx-click="toggle_isin" phx-value-isin={a.isin}>
                <td>
                  <strong><%= a.asset %></strong>
                  <%= if partial do %><span style="font-size:0.72rem;background:#dbeafe;color:#1d4ed8;border-radius:4px;padding:1px 5px;margin-left:4px;">active</span><% end %>
                  <span class="row-toggle-icon"><%= if expanded, do: "▲", else: "▼" %></span>
                  <br/><small style="color:#94a3b8"><%= a.isin %></small>
                </td>
                <td class="category-col"><%= a.category %></td>
                <td><%= format_eur(a.sold_cost) %></td>
                <td><%= format_eur(a.total_received) %></td>
                <td class={earnings_class(a.pnl)}><%= format_abs(a.pnl) %></td>
                <td class={earnings_class(a.pnl_pct)}><%= format_pct(a.pnl_pct) %></td>
                <.xirr_cell row={a} />
              </tr>
              <%= if expanded do %>
                <% ops = Map.get(@ops_by_isin, a.isin, []) |> Enum.sort_by(& &1.fecha) %>
                <tr class="ops-detail">
                  <td colspan="7" style="padding: 0;">
                    <table style="width:100%; border-collapse: collapse;">
                      <thead>
                        <tr>
                          <th>Type</th>
                          <th>Date</th>
                          <th>Units</th>
                          <th>Amount (€)</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for op <- ops do %>
                          <% is_buy = buy?(op.tipo) %>
                          <tr>
                            <td class={if is_buy, do: "ops-buy", else: "ops-sell"}>
                              <%= if is_buy, do: "Buy", else: "Sell" %>
                            </td>
                            <td><%= op.fecha %></td>
                            <td><%= format_qty(parse_cantidad(op.cantidad)) %></td>
                            <td><%= format_eur(amount_in_eur(op.importe_with_comision, op.precio, parse_cantidad(op.cantidad), @eur_usd, @eur_cad)) %></td>
                          </tr>
                        <% end %>
                      </tbody>
                    </table>
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
          <tfoot>
            <tr>
              <td>Total</td>
              <td></td>
              <td><%= format_eur(total_invested) %></td>
              <td><%= format_eur(total_received) %></td>
              <td class={earnings_class(total_pnl)}><%= format_abs(total_pnl) %></td>
              <td class={earnings_class(total_pct)}><%= format_pct(total_pct) %></td>
              <td></td>
            </tr>
          </tfoot>
        </table>
      </div>
    <% end %>
    """
  end

  defp sort_header(assigns) do
    assigns = assign_new(assigns, :class, fn -> nil end)

    ~H"""
    <th class={@class} aria-sort={aria_sort(@sort, @column)}>
      <button type="button" class="sort-btn" phx-click="sort" phx-value-column={@column}>
        {@label}<span class={["sort-icon", elem(@sort, 0) == @column && "current"]} aria-hidden="true">{sort_arrow(@sort, @column)}</span>
      </button>
    </th>
    """
  end

  defp xirr_cell(assigns) do
    ~H"""
    <td class={earnings_class(@row.xirr)}>
      <%= format_pct(@row.xirr) %>
      <%= if @row.xirr && @row.xirr_short do %><br/><small class="dividends-note">under 1 year</small><% end %>
    </td>
    """
  end

  # What's held today, for a position's return: nothing once it's sold, and
  # unknown until a held position has its price.
  defp held_value(%{net_qty: net_qty} = a) when net_qty > 0.001, do: a.current_value
  defp held_value(_a), do: 0.0

  defp position_flows(a, flows), do: {Map.get(flows, a.isin, []), held_value(a)}

  defp with_xirr(row, flows) do
    {asset_flows, value} = position_flows(row, flows)
    today = Date.utc_today()

    Map.merge(row, %{
      xirr: Returns.annual_pct(asset_flows, value, today),
      xirr_short: Returns.under_a_year?(asset_flows, value, today)
    })
  end

  defp active_xirr(active, flows) do
    active |> Enum.map(&position_flows(&1, flows)) |> Returns.combined_pct(Date.utc_today())
  end

  defp overall_xirr(assets, flows), do: assets |> Map.values() |> active_xirr(flows)

  defp aria_sort({column, :asc}, column), do: "ascending"
  defp aria_sort({column, :desc}, column), do: "descending"
  defp aria_sort(_sort, _column), do: "none"

  defp sort_arrow({column, :asc}, column), do: "▲"
  defp sort_arrow({column, :desc}, column), do: "▼"
  defp sort_arrow(_sort, _column), do: "↕"

  defp default_sort(:settled), do: {:total_received, :desc}
  defp default_sort(_active), do: {:invested, :desc}

  @doc """
  The sort after clicking a column: the current one flips, a new one starts
  A to Z for names and largest first for amounts.
  """
  def next_sort({key, :asc}, key), do: {key, :desc}
  def next_sort({key, :desc}, key), do: {key, :asc}
  def next_sort(_sort, key) when key in [:asset, :category], do: {key, :asc}
  def next_sort(_sort, key), do: {key, :desc}

  @doc """
  Sorts rows by one field. Rows with no value, shown as "—", stay last in both
  directions so reversing a column never leads with blanks.
  """
  def sort_rows(rows, {key, direction}) do
    {blank, filled} = Enum.split_with(rows, &is_nil(Map.fetch!(&1, key)))
    Enum.sort_by(filled, &sort_value(Map.fetch!(&1, key)), direction) ++ blank
  end

  defp sort_value(value) when is_binary(value), do: String.downcase(value)
  defp sort_value(value), do: value

  defp active_row(a, categories, dividends, held_value, flows) do
    a
    |> gains(Map.get(dividends, a.isin, 0.0))
    |> with_xirr(flows)
    |> Map.put(:category, AssetCategories.category_for(a.isin, categories))
    |> Map.put(:weight, weight(a.current_value, held_value))
  end

  @doc "A position's share of the portfolio, in percent. Blank until it has a price."
  def weight(nil, _held_value), do: nil
  def weight(_value, held_value) when held_value <= 0, do: nil
  def weight(value, held_value), do: Float.round(value / held_value * 100, 2)

  defp gains(%{cost_basis: cost_basis} = a, dividends) when cost_basis > 0 do
    {gain, gain_pct} = with_dividends(a.earnings_abs, cost_basis, dividends)
    Map.merge(a, %{invested: cost_basis, dividends: dividends, gain: gain, gain_pct: gain_pct})
  end

  defp gains(a, _dividends), do: Map.merge(a, %{invested: nil, dividends: 0.0, gain: nil, gain_pct: nil})

  @doc """
  `{gain, gain_pct}` counting the cash distributions received, the same way
  `/history` does. Blank until the position has a price.
  """
  def with_dividends(nil, _cost_basis, _dividends), do: {nil, nil}

  def with_dividends(earnings_abs, cost_basis, dividends) do
    gain = Float.round(earnings_abs + dividends, 2)
    {gain, Float.round(gain / cost_basis * 100, 2)}
  end

  defp settled_row(a, categories, flows) do
    sold_cost = max(0.0, a.total_bought - max(0.0, a.cost_basis))
    pnl = Float.round(a.total_received - sold_cost, 2)
    pnl_pct = if sold_cost > 0, do: Float.round(pnl / sold_cost * 100, 2), else: nil

    a
    |> with_xirr(flows)
    |> Map.merge(%{
      category: AssetCategories.category_for(a.isin, categories),
      sold_cost: sold_cost,
      pnl: pnl,
      pnl_pct: pnl_pct
    })
  end

  defdelegate buy?(tipo), to: Sheetfolio.Positions
  defdelegate parse_cantidad(str), to: Sheetfolio.Positions
  defdelegate amount_in_eur(importe, precio, qty, eur_usd, eur_cad), to: Sheetfolio.Positions

  defp earnings_class(nil), do: ""
  defp earnings_class(val) when val >= 0, do: "positive"
  defp earnings_class(_), do: "negative"

  defp format_eur(value), do: NumberFormat.eur(value)
  defp format_abs(value), do: NumberFormat.signed_eur(value)
  defp format_pct(value), do: NumberFormat.signed_pct(value)
  defp format_qty(value), do: NumberFormat.qty(value)
end
