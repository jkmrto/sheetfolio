defmodule SheetfolioWeb.McpAuthPlug do
  @moduledoc """
  Bearer-token check for the MCP endpoint, against `MCP_TOKEN`. With no token
  configured every request is refused, so the endpoint is off by default.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected = Application.get_env(:sheetfolio, :mcp_token)

    if authorized?(get_req_header(conn, "authorization"), expected) do
      conn
    else
      conn
      |> put_resp_header("www-authenticate", ~s(Bearer realm="sheetfolio"))
      |> send_resp(401, "")
      |> halt()
    end
  end

  defp authorized?(["Bearer " <> token], expected) when is_binary(expected) and expected != "" do
    Plug.Crypto.secure_compare(token, expected)
  end

  defp authorized?(_header, _expected), do: false
end
