defmodule SheetfolioWeb.ControlLive do
  use SheetfolioWeb, :live_view

  @poll_ms 800

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      if connected?(socket), do: schedule_poll()

      {:ok,
       assign(socket,
         authenticated: true,
         status: Sheetfolio.OperationsServer.get_status(),
         prices_cleared: false
       )}
    end
  end

  def handle_info(:poll, socket) do
    schedule_poll()
    {:noreply, assign(socket, status: Sheetfolio.OperationsServer.get_status())}
  end

  def handle_event("reload_emails", _, socket) do
    Sheetfolio.OperationsServer.reload()
    {:noreply, assign(socket, status: Sheetfolio.OperationsServer.get_status(), prices_cleared: false)}
  end

  def handle_event("clear_prices", _, socket) do
    Sheetfolio.EarningsServer.clear_price_cache()
    {:noreply, assign(socket, prices_cleared: true)}
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_ms)

  defp loading?({:loading, _, _}), do: true
  defp loading?(_), do: false

  def render(assigns) do
    ~H"""
    <div style="display:flex;flex-direction:column;gap:2rem;max-width:480px;">

      <div style="background:white;border-radius:12px;padding:1.5rem;box-shadow:0 1px 4px rgba(0,0,0,0.08);">
        <div style="font-size:1rem;font-weight:600;margin-bottom:1rem;">Operations</div>
        <div style="color:#64748b;font-size:0.9rem;margin-bottom:1rem;">
          <%= case @status do %>
            <% :ready -> %>
              Ready
            <% {:loading, current, total} when total > 0 -> %>
              Loading: {current} / {total} emails
              <div style="margin-top:0.5rem;height:6px;background:#e2e8f0;border-radius:99px;overflow:hidden;">
                <div style={"height:100%;background:#6366f1;border-radius:99px;width:#{trunc(current / total * 100)}%;transition:width 0.3s;"}></div>
              </div>
            <% {:loading, _, _} -> %>
              Fetching email list…
          <% end %>
        </div>
        <button
          phx-click="reload_emails"
          disabled={loading?(@status)}
          style={"padding:0.5rem 1rem;border-radius:8px;border:none;cursor:#{if loading?(@status), do: "not-allowed", else: "pointer"};background:#{if loading?(@status), do: "#e2e8f0", else: "#6366f1"};color:#{if loading?(@status), do: "#94a3b8", else: "white"};font-size:0.875rem;font-weight:500;"}
        >
          <%= if loading?(@status), do: "Loading…", else: "Reload emails" %>
        </button>
      </div>

      <div style="background:white;border-radius:12px;padding:1.5rem;box-shadow:0 1px 4px rgba(0,0,0,0.08);">
        <div style="font-size:1rem;font-weight:600;margin-bottom:1rem;">Prices</div>
        <div style="color:#64748b;font-size:0.9rem;margin-bottom:1rem;">
          <%= if @prices_cleared do %>
            Cache cleared — prices will be re-fetched on next page visit.
          <% else %>
            Clear the in-memory price cache to force fresh quotes on next load.
          <% end %>
        </div>
        <button
          phx-click="clear_prices"
          style="padding:0.5rem 1rem;border-radius:8px;border:none;cursor:pointer;background:#6366f1;color:white;font-size:0.875rem;font-weight:500;"
        >
          Clear price cache
        </button>
      </div>

    </div>
    """
  end
end
