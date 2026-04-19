defmodule SheetfolioWeb.AuthPlug do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :authenticated) do
      assign(conn, :authenticated, true)
    else
      conn
      |> redirect(to: "/login")
      |> halt()
    end
  end
end
