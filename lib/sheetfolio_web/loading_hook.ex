defmodule SheetfolioWeb.LoadingHook do
  import Phoenix.LiveView

  def on_mount(:default, _params, %{"authenticated" => true}, socket) do
    case Sheetfolio.OperationsServer.get_status() do
      # A background sync still serves the cached history, so only a cold load blocks.
      {:loading, _, _} -> {:halt, redirect(socket, to: "/loading")}
      _ready_or_syncing -> {:cont, socket}
    end
  end

  def on_mount(:default, _params, _session, socket), do: {:cont, socket}
end
