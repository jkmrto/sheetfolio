defmodule SheetfolioWeb.PortfolioController do
  use SheetfolioWeb, :controller

  def index(conn, _params) do
    chart_data = Sheetfolio.SheetData.portfolio_chart_data()
    render(conn, :index, chart_data: chart_data)
  end
end
