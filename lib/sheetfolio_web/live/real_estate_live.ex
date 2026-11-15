defmodule SheetfolioWeb.RealEstateLive do
  use SheetfolioWeb, :live_view

  alias SheetfolioWeb.NumberFormat

  alias Sheetfolio.{EquitoTransactions, Homes, RealEstate, UrbanitaeTransactions}

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      {urbanitae, equito, homes} =
        if connected?(socket) do
          {UrbanitaeTransactions.all(), EquitoTransactions.all(), Homes.all()}
        else
          {[], [], []}
        end

      {:ok, assign(socket, authenticated: true, urbanitae: urbanitae, equito: equito, homes: homes)}
    end
  end

  def render(assigns) do
    today = Date.utc_today() |> Date.to_iso8601()

    assigns =
      assign(assigns,
        summary: RealEstate.summary(assigns.urbanitae, assigns.equito, today),
        homes: Enum.map(assigns.homes, &Homes.summary(&1, Date.utc_today())),
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
      .re-big .stat-value.neg { color: #e04848; }
      .re-home-title { font-size: 1.05rem; font-weight: 600; color: #1e293b; margin-bottom: 1.1rem; }
      .re-home-title span { font-size: 0.82rem; font-weight: 400; color: #94a3b8; margin-left: 0.5rem; }
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

    <div :for={home <- @homes} class="re-card">
      <div class="re-home-title">
        {home.name}<span>my share · valued {home.valuation_date}</span>
      </div>
      <div class="re-big">
        <div class="stat">
          <span class="stat-label">Equity</span>
          <span class="stat-value">{format_eur(home.equity)}</span>
          <span class="stat-split">
            Value {format_eur(home.value)} · Mortgage {format_eur(home.balance)}
          </span>
        </div>
        <div class="stat">
          <span class="stat-label">Gain since purchase</span>
          <span class={["stat-value", if(home.gain >= 0, do: "pos", else: "neg")]}>
            {NumberFormat.signed_eur(home.gain)}
          </span>
          <span class="stat-split">Bought for {format_eur(home.purchase_price)}</span>
        </div>
        <div class="stat">
          <span class="stat-label">Equity built per month</span>
          <span class="stat-value pos">{NumberFormat.signed_eur(home.monthly_principal)}</span>
          <span class="stat-split">
            Payment {format_eur(home.monthly_payment)} · Interest {format_eur(home.monthly_interest)}
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

  defp format_eur(amount), do: NumberFormat.eur(amount)
end
