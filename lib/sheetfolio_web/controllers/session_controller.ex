defmodule SheetfolioWeb.SessionController do
  use SheetfolioWeb, :controller

  def new(conn, _params) do
    render(conn, :new, error: nil)
  end

  def create(conn, %{"password" => password}) do
    expected = Application.fetch_env!(:sheetfolio, :app_password)

    if password == expected do
      conn
      |> put_session(:authenticated, true)
      |> redirect(to: "/")
    else
      render(conn, :new, error: "Invalid password")
    end
  end
end
