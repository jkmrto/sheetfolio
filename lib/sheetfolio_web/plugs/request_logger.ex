defmodule SheetfolioWeb.RequestLogger do
  @moduledoc """
  `Plug.Logger`, except for `/mcp/<token>`, whose path carries the MCP token.
  """
  def init(opts), do: Plug.Logger.init(opts)

  def call(%Plug.Conn{path_info: ["mcp", _token]} = conn, _opts), do: conn
  def call(conn, opts), do: Plug.Logger.call(conn, opts)
end
