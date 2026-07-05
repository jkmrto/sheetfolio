defmodule SheetfolioWeb.LoadingHook do
  import Phoenix.LiveView

  def on_mount(:default, _params, %{"authenticated" => true}, socket) do
    case Sheetfolio.OperationsServer.get_status() do
      {:loading, _, _} -> {:halt, redirect(socket, to: "/loading")}
      :ready -> {:cont, socket}
    end
  end

  def on_mount(:default, _params, _session, socket), do: {:cont, socket}
end
