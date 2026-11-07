defmodule SheetfolioWeb.EarningsMonthlyLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.{Dividends, EquitoTransactions, MonthlyEarnings, UrbanitaeTransactions}
  alias SheetfolioWeb.NumberFormat

  @month_names ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket = assign(socket, authenticated: true, earnings: %{months: [], rows: []}, years: [], year: nil)

      if connected?(socket) do
        earnings = load()
        years = MonthlyEarnings.years(earnings)
        {:ok, assign(socket, earnings: earnings, years: years, year: List.first(years))}
      else
        {:ok, socket}
      end
    end
  end

  def handle_event("set_year", %{"year" => year}, socket) do
    if year in socket.assigns.years, do: {:noreply, assign(socket, year: year)}, else: {:noreply, socket}
  end

  defp load do
    operations = Sheetfolio.OperationsServer.get_operations() || []
    {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()
    snapshots = Mongo.find(:mongo, "portfolio_snapshots", %{}, sort: %{date: 1}) |> Enum.to_list()
    history = Sheetfolio.Positions.history(operations, eur_usd, eur_cad)

    MonthlyEarnings.build(snapshots, history, Dividends.all(), ledgers())
  end

  defp ledgers do
    urbanitae = UrbanitaeTransactions.all()
    equito = EquitoTransactions.all()

    [
      {"Urbanitae", &elem(UrbanitaeTransactions.state_at(urbanitae, &1), 1)},
      {"Equito", &elem(EquitoTransactions.state_at(equito, &1), 1)}
    ]
  end

  def render(assigns) do
    assigns = assign(assigns, table: MonthlyEarnings.for_year(assigns.earnings, assigns.year || ""))

    ~H"""
    <style>
      main:has(.monthly-table) { max-width: 1400px; }
      .earnings-page-tabs { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; border-bottom: 1px solid #e2e8f0; }
      .earnings-page-tabs a { color: #64748b; padding: 0.4rem 1.1rem; font-size: 0.95rem; border-bottom: 2px solid transparent; margin-bottom: -1px; text-decoration: none; }
      .earnings-page-tabs a:hover { color: #1e293b; }
      .earnings-page-tabs a.active { color: #1e293b; font-weight: 600; border-bottom-color: #1e293b; }
      .monthly-years { display: flex; gap: 0.4rem; margin-bottom: 1rem; }
      .monthly-years button { border: 1px solid #e2e8f0; background: white; color: #64748b; border-radius: 6px; padding: 0.25rem 0.8rem; font-size: 0.85rem; cursor: pointer; }
      .monthly-years button.active { background: #1e293b; border-color: #1e293b; color: white; font-weight: 600; }
      .monthly-scroll { overflow-x: auto; border-radius: 12px; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .monthly-table { width: 100%; border-collapse: collapse; background: white; font-size: 0.82rem; white-space: nowrap; }
      .monthly-table th { background: #1e293b; color: white; padding: 0.55rem 0.6rem; text-align: right; font-weight: 600; }
      .monthly-table td { padding: 0.45rem 0.6rem; border-bottom: 1px solid #f1f5f9; text-align: right; }
      .monthly-table th:first-child, .monthly-table td:first-child { text-align: left; position: sticky; left: 0; max-width: 16rem; overflow: hidden; text-overflow: ellipsis; }
      .monthly-table td:first-child { background: white; }
      .monthly-table tr.sum td { font-weight: 700; background: #f1f5f9; border-bottom: 2px solid #1e293b; }
      .monthly-table td.year { font-weight: 600; border-left: 1px solid #e2e8f0; }
      .monthly-note { color: #64748b; font-size: 0.78rem; margin-top: 0.75rem; }
      .pos { color: #008300; }
      .neg { color: #e34948; }
      .zero { color: #cbd5e1; }
    </style>

    <div class="earnings-page-tabs">
      <a href="/earnings">Overview</a>
      <a href="/earnings/monthly" class="active">Monthly</a>
    </div>

    <div class="monthly-years">
      <button :for={year <- @years} type="button" class={if year == @year, do: "active", else: ""} phx-click="set_year" phx-value-year={year}>
        {year}
      </button>
    </div>

    <div class="expand-panel" id="panel-monthly" phx-hook="ExpandPanel">
      <button class="expand-btn" aria-label="Toggle full screen"></button>
      <div class="monthly-scroll">
        <table class="monthly-table">
          <tr>
            <th>Asset</th>
            <th :for={month <- @table.months}>{month_name(month)}</th>
            <th>Total</th>
          </tr>
          <tr class="sum">
            <td>Total earnings</td>
            <td :for={month <- @table.months} class={cell_class(@table.total.months[month])}>{amount(@table.total.months[month])}</td>
            <td class={"year #{cell_class(@table.total.total)}"}>{amount(@table.total.total)}</td>
          </tr>
          <tr :for={row <- @table.rows}>
            <td title={row.asset}>{row.asset}</td>
            <td :for={month <- @table.months} class={cell_class(row.months[month])}>{amount(row.months[month])}</td>
            <td class={"year #{cell_class(row.total)}"}>{amount(row.total)}</td>
          </tr>
        </table>
      </div>
    </div>

    <div class="monthly-note">
      In euros. Each month is the change in value less cost, plus sales and dividends, so a sale only adds what
      the price moved since the month before. The current month runs to the latest snapshot.
    </div>
    """
  end

  defp month_name(month), do: Enum.at(@month_names, String.to_integer(String.slice(month, 5, 2)) - 1)

  defp amount(nil), do: "—"
  defp amount(value) when abs(value) < 0.5, do: "—"
  defp amount(value), do: NumberFormat.number(value, 0)

  defp cell_class(nil), do: "zero"
  defp cell_class(value) when abs(value) < 0.5, do: "zero"
  defp cell_class(value) when value < 0, do: "neg"
  defp cell_class(_value), do: "pos"
end
