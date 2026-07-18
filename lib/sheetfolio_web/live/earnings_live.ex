defmodule SheetfolioWeb.EarningsLive do
  use SheetfolioWeb, :live_view

  @views ~w(by_asset by_operation)

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket =
        assign(socket,
          authenticated: true,
          realized_events: [],
          unrealized: [],
          view: "by_asset",
          expanded_assets: MapSet.new()
        )

      if connected?(socket) do
        operations = Sheetfolio.OperationsServer.get_operations() || []
        {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()

        realized_events =
          Sheetfolio.Positions.realized_events(operations, eur_usd, eur_cad)
          |> Enum.reverse()

        {:ok, assign(socket, realized_events: realized_events, unrealized: unrealized_positions())}
      else
        {:ok, socket}
      end
    end
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

  def render(assigns) do
    assigns =
      assign(assigns,
        realized_sum: Enum.reduce(assigns.realized_events, 0.0, &(&1.realized + &2)),
        unrealized_sum: Enum.reduce(assigns.unrealized, 0.0, &(&1.value - &1.invested + &2)),
        by_asset: group_by_asset(assigns.realized_events)
      )

    ~H"""
    <style>
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
    </style>

    <div class="earnings-total">
      Realized <strong class={sign_class(@realized_sum)}><%= eur(@realized_sum) %></strong>
      + Unrealized <strong class={sign_class(@unrealized_sum)}><%= eur(@unrealized_sum) %></strong>
      = <strong class={sign_class(@realized_sum + @unrealized_sum)}><%= eur(@realized_sum + @unrealized_sum) %></strong>
    </div>

    <div class="earnings-section">Realized</div>
    <div class="earnings-subtabs">
      <button type="button" class={if @view == "by_asset", do: "active", else: ""} phx-click="set_view" phx-value-view="by_asset">
        By asset
      </button>
      <button type="button" class={if @view == "by_operation", do: "active", else: ""} phx-click="set_view" phx-value-view="by_operation">
        By operation
      </button>
    </div>

    <%= if @view == "by_asset" do %>
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
              <%= if row.uncovered > 0.001 do %>
                <div class="warn">⚠ <%= Float.round(row.uncovered, 2) %> units without buy history — excluded</div>
              <% end %>
            </td>
            <td><%= row.sells %></td>
            <td><%= Float.round(row.qty, 3) %></td>
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
                        <td><%= Float.round(e.qty, 3) %></td>
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
    <% else %>
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
              <%= if e.uncovered > 0.001 do %>
                <div class="warn">⚠ <%= Float.round(e.uncovered, 2) %> units without buy history — excluded</div>
              <% end %>
            </td>
            <td class="left"><%= e.tipo %></td>
            <td><%= Float.round(e.qty, 3) %></td>
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
    <% end %>

    <div class="earnings-section">Unrealized — open positions at the latest snapshot</div>
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
    """
  end

  defp group_by_asset(events) do
    events
    |> Enum.group_by(& &1.asset)
    |> Enum.map(fn {asset, evs} ->
      %{
        asset: asset,
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

  defp eur(value) do
    [int, dec] =
      Float.round(value / 1, 2)
      |> :erlang.float_to_binary(decimals: 2)
      |> String.split(".")

    "#{String.replace(int, ~r/(?<=\d)(?=(\d{3})+$)/, ".")},#{dec} €"
  end

  defp sign_class(value) when value < 0, do: "neg"
  defp sign_class(_value), do: "pos"
end
