defmodule SheetfolioWeb.EarningsLive do
  use SheetfolioWeb, :live_view

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket = assign(socket, authenticated: true, realized_events: [], unrealized: [])

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

  def render(assigns) do
    assigns =
      assign(assigns,
        realized_sum: Enum.reduce(assigns.realized_events, 0.0, &(&1.realized + &2)),
        unrealized_sum: Enum.reduce(assigns.unrealized, 0.0, &(&1.value - &1.invested + &2))
      )

    ~H"""
    <style>
      .earnings-total { background: white; border-radius: 12px; padding: 1.25rem 2rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 1.5rem; font-size: 1.05rem; }
      .earnings-total strong { font-size: 1.2rem; }
      .earnings-section { margin: 1.5rem 0 0.5rem; font-size: 1.1rem; font-weight: 600; color: #334155; }
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
    </style>

    <div class="earnings-total">
      Realized <strong class={sign_class(@realized_sum)}><%= eur(@realized_sum) %></strong>
      + Unrealized <strong class={sign_class(@unrealized_sum)}><%= eur(@unrealized_sum) %></strong>
      = <strong class={sign_class(@realized_sum + @unrealized_sum)}><%= eur(@realized_sum + @unrealized_sum) %></strong>
    </div>

    <div class="earnings-section">Realized — one row per sell operation</div>
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
