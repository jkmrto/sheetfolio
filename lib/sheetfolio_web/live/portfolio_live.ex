defmodule SheetfolioWeb.PortfolioLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.UrbanitaeTransactions

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket = assign(socket, authenticated: true, snapshots: [], cash: [], urbanitae_by_date: %{})

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

        {:ok, assign(socket, snapshots: snapshots, cash: cash, urbanitae_by_date: urbanitae_by_date)}
      else
        {:ok, socket}
      end
    end
  end

  def render(assigns) do
    ~H"""
    <%= if @snapshots == [] do %>
      <div class="chart-container" style="color:#64748b;font-size:0.9rem;">
        No snapshots recorded yet. History accumulates one point per day once the recorder runs.
      </div>
    <% else %>
      <div class="chart-container" id="portfolio-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(chart_payload(@snapshots, @cash, @urbanitae_by_date))}>
        <div id="portfolio-chart-canvas" phx-update="ignore">
          <canvas></canvas>
        </div>
      </div>
    <% end %>
    """
  end

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
