defmodule SheetfolioWeb.Layouts do
  use SheetfolioWeb, :html

  embed_templates "layouts/*"

  def current_path(%{conn: %Plug.Conn{request_path: path}}), do: path
  def current_path(%{socket: %{view: SheetfolioWeb.OperationsLive}}), do: "/operations"
  def current_path(_), do: "/"
end
