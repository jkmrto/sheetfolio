defmodule SheetfolioWeb.RealEstateLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.{EquitoTransactions, RealEstate, UrbanitaeTransactions}

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      {urbanitae, equito} =
        if connected?(socket) do
          {UrbanitaeTransactions.all(), EquitoTransactions.all()}
        else
          {[], []}
        end

      {:ok, assign(socket, authenticated: true, urbanitae: urbanitae, equito: equito)}
    end
  end

  def render(assigns) do
    today = Date.utc_today() |> Date.to_iso8601()

    assigns =
      assign(assigns,
        summary: RealEstate.summary(assigns.urbanitae, assigns.equito, today),
        chart_payload: chart_payload(RealEstate.time_series(assigns.urbanitae, assigns.equito))
      )

    ~H"""
    <style>
      .re-subtabs { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; border-bottom: 1px solid #e2e8f0; }
      .re-subtabs a { color: #64748b; padding: 0.4rem 1.1rem; font-size: 0.95rem; border-bottom: 2px solid transparent; margin-bottom: -1px; text-decoration: none; }
      .re-subtabs a:hover { color: #1e293b; }
      .re-subtabs a.active { color: #1e293b; font-weight: 600; border-bottom-color: #1e293b; }
      .re-card { background: white; border-radius: 12px; padding: 1.5rem 1.75rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 1.5rem; }
      .re-big { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1.5rem; }
      .re-big .stat { display: flex; flex-direction: column; gap: 0.4rem; }
      .re-big .stat-label { font-size: 0.8rem; color: #64748b; text-transform: uppercase; letter-spacing: 0.03em; }
      .re-big .stat-value { font-size: 2.4rem; font-weight: 700; color: #0f172a; font-variant-numeric: tabular-nums; line-height: 1.1; }
      .re-big .stat-value.pos { color: #1baf7a; }
      .re-big .stat-split { font-size: 0.82rem; color: #94a3b8; font-variant-numeric: tabular-nums; }
    </style>

    <div class="re-subtabs">
      <.link navigate="/real-estate" class="active">Overview</.link>
      <.link navigate="/urbanitae">Urbanitae</.link>
      <.link navigate="/equito">Equito</.link>
    </div>

    <div class="re-card">
      <div class="re-big">
        <div class="stat">
          <span class="stat-label">Currently invested</span>
          <span class="stat-value">{format_eur(@summary.total.invested)}</span>
          <span class="stat-split">
            Urbanitae {format_eur(@summary.urbanitae.invested)} · Equito {format_eur(@summary.equito.invested)}
          </span>
        </div>
        <div class="stat">
          <span class="stat-label">Total earned</span>
          <span class="stat-value pos">{format_eur(@summary.total.earnings)}</span>
          <span class="stat-split">
            Urbanitae {format_eur(@summary.urbanitae.earnings)} · Equito {format_eur(@summary.equito.earnings)}
          </span>
        </div>
      </div>
    </div>

    <div class="re-card">
      <div id="real-estate-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(@chart_payload)}>
        <div id="real-estate-chart-canvas" phx-update="ignore">
          <canvas id="realEstateChartCanvas"></canvas>
        </div>
      </div>
    </div>
    """
  end

  defp chart_payload(series) do
    %{
      metric: "value",
      title: "Currently invested and cumulative earnings (€)",
      datasets: [
        %{
          label: "Currently invested",
          color: "#2a78d6",
          data: Enum.map(series, &%{x: &1.date, y: &1.invested})
        },
        %{
          label: "Earnings",
          color: "#1baf7a",
          data: Enum.map(series, &%{x: &1.date, y: &1.earnings})
        }
      ]
    }
  end

  defp format_eur(amount) do
    sign = if amount < 0, do: "-", else: ""
    abs_amount = abs(amount)
    whole = trunc(abs_amount)
    cents = round((abs_amount - whole) * 100)

    whole_str =
      whole
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
      |> String.reverse()

    cents_str = cents |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{sign}#{whole_str},#{cents_str} €"
  end
end
