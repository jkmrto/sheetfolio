defmodule SheetfolioWeb.ControlLive do
  use SheetfolioWeb, :live_view

  alias Sheetfolio.{DataHealth, HealthMonitor}
  alias SheetfolioWeb.NumberFormat

  @poll_ms 800

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      if connected?(socket), do: schedule_poll()

      {:ok,
       assign(socket,
         authenticated: true,
         health: if(connected?(socket), do: HealthMonitor.publish(DataHealth.report()), else: []),
         status: Sheetfolio.OperationsServer.get_status(),
         prices_cleared: false,
         recording: false,
         snapshot: nil
       )}
    end
  end

  def handle_info(:poll, socket) do
    schedule_poll()
    {:noreply, assign(socket, status: Sheetfolio.OperationsServer.get_status())}
  end

  def handle_info({:snapshot_recorded, result}, socket) do
    {:noreply, assign(socket, recording: false, snapshot: snapshot_summary(result))}
  end

  def handle_event("reload_emails", _, socket) do
    Sheetfolio.OperationsServer.reload()
    {:noreply, assign(socket, status: Sheetfolio.OperationsServer.get_status(), prices_cleared: false)}
  end

  def handle_event("clear_prices", _, socket) do
    Sheetfolio.EarningsServer.clear_price_cache()
    {:noreply, assign(socket, prices_cleared: true)}
  end

  # Refetching every quote and re-storing the day's snapshot takes a few seconds,
  # so run it in a task and keep the page responsive; the result comes back as a
  # message. Clear the price cache first so the fetch pulls fresh quotes rather
  # than whatever EarningsServer already had.
  def handle_event("record_snapshot", _, socket) do
    if socket.assigns.recording do
      {:noreply, socket}
    else
      live = self()

      Task.start(fn ->
        Sheetfolio.EarningsServer.clear_price_cache()
        send(live, {:snapshot_recorded, Sheetfolio.SnapshotRecorder.record_now()})
      end)

      {:noreply, assign(socket, recording: true, snapshot: nil)}
    end
  end

  defp snapshot_summary({:ok, doc}) do
    %{
      ok: true,
      date: doc.date,
      positions: length(doc.positions),
      value: doc.total_value,
      partial: doc.partial
    }
  end

  defp snapshot_summary(_error), do: %{ok: false}

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_ms)

  defp loading?({:loading, _, _}), do: true
  defp loading?({:syncing, _, _}), do: true
  defp loading?(_), do: false

  defp status_label(:ok), do: "OK"
  defp status_label(:warning), do: "Check"
  defp status_label(:overdue), do: "Overdue"

  defp kind_label(:automatic), do: "Automatic"
  defp kind_label(:manual), do: "Manual import"

  defp last_label(nil), do: "Never"
  defp last_label(date), do: Calendar.strftime(date, "%d/%m/%Y")

  def render(assigns) do
    ~H"""
    <style>
      main:has(.health-card) { max-width: 960px; }
      .health-card { background: white; border-radius: 12px; padding: 1.5rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 2rem; }
      .health-title { font-size: 1rem; font-weight: 600; margin-bottom: 1rem; }
      .health-table { width: 100%; border-collapse: collapse; font-size: 0.88rem; }
      .health-table th { text-align: left; color: #64748b; font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.03em; padding: 0.4rem 0.6rem; border-bottom: 1px solid #e2e8f0; }
      .health-table td { padding: 0.55rem 0.6rem; border-bottom: 1px solid #f1f5f9; vertical-align: top; }
      .health-table tr:last-child td { border-bottom: none; }
      .health-pill { display: inline-block; padding: 0.1rem 0.5rem; border-radius: 999px; font-size: 0.75rem; font-weight: 600; white-space: nowrap; }
      .health-pill.ok { background: #dcfce7; color: #166534; }
      .health-pill.warning { background: #fef3c7; color: #92400e; }
      .health-pill.overdue { background: #fee2e2; color: #991b1b; }
      .health-muted { color: #64748b; }
    </style>

    <div class="health-card">
      <div class="health-title">Data health</div>
      <table class="health-table">
        <thead>
          <tr><th>Source</th><th>Status</th><th>Last update</th><th>Updated by</th><th>Note</th></tr>
        </thead>
        <tbody>
          <%= for row <- @health do %>
            <tr>
              <td>{row.label}</td>
              <td><span class={"health-pill #{row.status}"}>{status_label(row.status)}</span></td>
              <td>{last_label(row.last)}</td>
              <td class="health-muted">{kind_label(row.kind)}</td>
              <td class="health-muted">{row.detail}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>

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
            <% {:syncing, current, total} when total > 0 -> %>
              Serving the cached history; downloading {current} / {total} new emails
            <% {:syncing, _, _} -> %>
              Serving the cached history; checking Gmail for new emails…
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

      <div style="background:white;border-radius:12px;padding:1.5rem;box-shadow:0 1px 4px rgba(0,0,0,0.08);">
        <div style="font-size:1rem;font-weight:600;margin-bottom:1rem;">Snapshot</div>
        <div style="color:#64748b;font-size:0.9rem;margin-bottom:1rem;">
          <%= cond do %>
            <% @recording -> %>
              Refetching prices for every holding and re-storing today's snapshot…
            <% @snapshot && @snapshot.ok -> %>
              Recorded <%= @snapshot.date %> — <%= @snapshot.positions %> positions, <%= format_eur(@snapshot.value) %>.<%= if @snapshot.partial, do: " Some prices were carried forward.", else: "" %>
            <% @snapshot -> %>
              Recording failed — see the server log.
            <% true -> %>
              Refetch fresh prices for every asset and overwrite today's stored snapshot.
          <% end %>
        </div>
        <button
          phx-click="record_snapshot"
          disabled={@recording}
          style={"padding:0.5rem 1rem;border-radius:8px;border:none;cursor:#{if @recording, do: "not-allowed", else: "pointer"};background:#{if @recording, do: "#e2e8f0", else: "#6366f1"};color:#{if @recording, do: "#94a3b8", else: "white"};font-size:0.875rem;font-weight:500;"}
        >
          <%= if @recording, do: "Recording…", else: "Recapture today's snapshot" %>
        </button>
      </div>

    </div>
    """
  end

  defp format_eur(value), do: NumberFormat.eur(value)
end
