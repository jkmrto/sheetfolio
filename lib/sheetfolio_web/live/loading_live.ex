defmodule SheetfolioWeb.LoadingLive do
  use SheetfolioWeb, :live_view

  @poll_ms 300

  def mount(_params, _session, socket) do
    case Sheetfolio.OperationsServer.get_status() do
      :ready ->
        {:ok, redirect(socket, to: "/")}

      {:loading, current, total} ->
        if connected?(socket), do: Process.send_after(self(), :poll, @poll_ms)
        {:ok, assign(socket, current: current, total: total)}
    end
  end

  def handle_info(:poll, socket) do
    case Sheetfolio.OperationsServer.get_status() do
      :ready ->
        {:noreply, push_navigate(socket, to: "/")}

      {:loading, current, total} ->
        Process.send_after(self(), :poll, @poll_ms)
        {:noreply, assign(socket, current: current, total: total)}
    end
  end

  def render(assigns) do
    ~H"""
    <div style="display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:60vh;gap:1.5rem;">
      <div style="font-size:1.25rem;font-weight:600;color:#1e293b;">Loading operations…</div>
      <div style="color:#64748b;font-size:0.95rem;">
        <%= if @total > 0 do %>
          {@current} / {@total} emails
        <% else %>
          Fetching email list…
        <% end %>
      </div>
      <%= if @total > 0 do %>
        <div style="width:320px;height:8px;background:#e2e8f0;border-radius:99px;overflow:hidden;">
          <div style={"height:100%;background:#6366f1;border-radius:99px;width:#{trunc(@current / @total * 100)}%;transition:width 0.2s;"}>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
