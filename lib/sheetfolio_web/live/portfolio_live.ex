defmodule SheetfolioWeb.PortfolioLive do
  use SheetfolioWeb, :live_view

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket = assign(socket, authenticated: true, snapshots: [], cash: [])

      if connected?(socket) do
        snapshots =
          Mongo.find(:mongo, "portfolio_snapshots", %{},
            sort: %{date: 1},
            projection: %{date: 1, total_value: 1, total_invested: 1}
          )
          |> Enum.to_list()

        cash =
          Mongo.find(:mongo, "cash_snapshots", %{},
            sort: %{date: 1},
            projection: %{date: 1, total: 1}
          )
          |> Enum.to_list()

        {:ok, assign(socket, snapshots: snapshots, cash: cash)}
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
      <div class="chart-container" id="portfolio-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(chart_payload(@snapshots, @cash))}>
        <div id="portfolio-chart-canvas" phx-update="ignore">
          <canvas></canvas>
        </div>
      </div>
    <% end %>
    """
  end

  defp chart_payload(snapshots, cash) do
    total =
      for s <- snapshots, is_number(s["total_value"]) do
        %{x: s["date"], y: s["total_value"]}
      end

    total_with_cash =
      for s <- snapshots, is_number(s["total_value"]), amount = cash_at(cash, s["date"]) do
        %{x: s["date"], y: Float.round(s["total_value"] + amount, 2)}
      end

    cash_points =
      for s <- snapshots, amount = cash_at(cash, s["date"]) do
        %{x: s["date"], y: amount}
      end

    earnings =
      for s <- snapshots, is_number(s["total_value"]) and is_number(s["total_invested"]) do
        %{x: s["date"], y: Float.round(s["total_value"] - s["total_invested"], 2)}
      end

    %{
      metric: "value",
      title: "Portfolio Evolution",
      datasets: [
        %{label: "Total + Cash (€)", color: "#4a3aa7", data: total_with_cash},
        %{label: "Total Portfolio (€)", color: "#2a78d6", fill: true, data: total},
        %{label: "Cash (€)", color: "#eda100", data: cash_points},
        %{label: "Earnings (€)", color: "#008300", fill: true, data: earnings}
      ]
    }
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
end
