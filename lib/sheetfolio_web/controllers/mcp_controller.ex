defmodule SheetfolioWeb.McpController do
  use SheetfolioWeb, :controller

  alias Sheetfolio.Mcp.Server

  def handle(conn, _params) do
    case Server.handle(conn.body_params) do
      {:reply, response} -> json(conn, response)
      :accepted -> send_resp(conn, 202, "")
    end
  end

  # The server never pushes messages, so there is no SSE stream to open...
  def no_stream(conn, _params), do: post_only(conn)

  # ...and, being stateless, no session to end.
  def no_session(conn, _params), do: post_only(conn)

  defp post_only(conn) do
    conn
    |> put_resp_header("allow", "POST")
    |> send_resp(405, "")
  end
end
