defmodule SheetfolioWeb.Layouts do
  use SheetfolioWeb, :html

  embed_templates "layouts/*"

  def current_path(%{conn: %Plug.Conn{request_path: path}}), do: path
  def current_path(%{socket: %{view: SheetfolioWeb.OperationsLive}}), do: "/operations"
  def current_path(_), do: "/"

  @doc """
  The bundle URL, carrying a hash of its contents as the version.

  There is no `phx.digest` step, so `/assets/app.js` is one unchanging URL
  across every build. A browser that cached it back when `Plug.Static` still
  sent a bare `public` can keep serving that copy for as long as its heuristic
  freshness lasts, silently running an old bundle against a new server. Giving
  each build its own URL means a new bundle is never the same request.
  """
  def app_js_path do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        path = "/assets/app.js?v=" <> app_js_hash()
        :persistent_term.put(__MODULE__, path)
        path

      path ->
        path
    end
  end

  defp app_js_hash do
    :sheetfolio
    |> Application.app_dir("priv/static/assets/app.js")
    |> File.read()
    |> case do
      {:ok, contents} ->
        :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower) |> binary_part(0, 8)

      {:error, _reason} ->
        "dev"
    end
  end
end
