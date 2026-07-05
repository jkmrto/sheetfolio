defmodule SheetfolioWeb.EvolutionLive do
  use SheetfolioWeb, :live_view

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      snapshots =
        if connected?(socket) do
          Mongo.find(:mongo, "portfolio_snapshots", %{}, sort: %{date: 1}) |> Enum.to_list()
        else
          []
        end

      {:ok, assign(socket, authenticated: true, snapshots: snapshots)}
    end
  end

  def render(assigns) do
    ~H"""
    <style>
      .empty-note { background: white; border-radius: 12px; padding: 2rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); color: #64748b; font-size: 0.9rem; }
    </style>

    <%= if @snapshots == [] do %>
      <div class="empty-note">
        No snapshots recorded yet. History accumulates one point per day once the recorder runs.
      </div>
    <% else %>
      <div class="chart-container" id="evolution-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(chart_payload(@snapshots))}>
        <div id="evolution-chart-canvas" phx-update="ignore">
          <canvas id="evolutionChartCanvas"></canvas>
        </div>
      </div>
    <% end %>
    """
  end

  defp chart_payload(snapshots) do
    %{
      metric: "value",
      title: "Portfolio evolution (€)",
      datasets: [
        %{label: "Total value", color: "#2a78d6", data: points(snapshots, & &1["total_value"])},
        %{label: "Invested", color: "#94a3b8", data: points(snapshots, & &1["total_invested"])},
        %{
          label: "Earnings",
          color: "#1baf7a",
          data: points(snapshots, &Float.round(&1["total_value"] - &1["total_invested"], 2))
        }
      ]
    }
  end

  defp points(snapshots, fun) do
    Enum.map(snapshots, fn snap -> %{x: snap["date"], y: fun.(snap)} end)
  end
end
