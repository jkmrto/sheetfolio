defmodule SheetfolioWeb.OperationsController do
  use SheetfolioWeb, :controller

  def index(conn, _params) do
    %{headers: headers, rows: rows} = Sheetfolio.OperationsCache.get()
    render(conn, :index, headers: headers, rows: rows)
  end
end
