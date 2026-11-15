defmodule SheetfolioWeb.McpAuthPlug do
  @moduledoc """
  Token check for the MCP endpoint, against `MCP_TOKEN`: a bearer header, or
  the token as the last path segment (`/mcp/<token>`) for clients such as
  claude.ai connectors that can't send headers. With no token configured every
  request is refused, so the endpoint is off by default.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected = Application.get_env(:sheetfolio, :mcp_token)

    if authorized?(supplied_token(conn), expected) do
      conn
    else
      conn
      |> put_resp_header("www-authenticate", ~s(Bearer realm="sheetfolio"))
      |> send_resp(401, "")
      |> halt()
    end
  end

  defp supplied_token(%{path_params: %{"token" => token}}), do: token

  defp supplied_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end

  defp authorized?(token, expected)
       when is_binary(token) and is_binary(expected) and expected != "" do
    Plug.Crypto.secure_compare(token, expected)
  end

  defp authorized?(_header, _expected), do: false
end
