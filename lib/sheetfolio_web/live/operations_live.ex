defmodule SheetfolioWeb.OperationsLive do
  use SheetfolioWeb, :live_view

  @headers [
    "Fecha", "Asset", "ISIN", "Tipo", "Cantidad", "Precio",
    "Importe", "Comisión", "Importe Neto", "Ganancia (€)", "Ganancia (%)"
  ]

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      socket =
        assign(socket,
          headers: @headers,
          operations: %{},
          order: [],
          next_id: 0,
          total: nil,
          loaded: 0,
          loading: false,
          asset_counts: %{},
          selected_assets: MapSet.new()
        )

      if connected?(socket) do
        pid = self()
        Task.start(fn -> Sheetfolio.MyinvestorEmails.stream_to(pid) end)
        {:ok, assign(socket, loading: true)}
      else
        {:ok, socket}
      end
    end
  end

  def handle_info({:loading_started, total}, socket) do
    {:noreply, assign(socket, total: total)}
  end

  def handle_info({:email_loaded, data}, socket) do
    ref = socket.assigns.next_id

    entry = %{
      row: [
        data.fecha, data.asset, data.isin, data.tipo,
        data.cantidad, data.precio, data.importe_without_comision,
        data.comision, data.importe_with_comision
      ],
      earnings_abs: nil,
      earnings_pct: nil
    }

    Sheetfolio.EarningsServer.request(ref, data.isin, data.precio, data.cantidad, self())

    operations = Map.put(socket.assigns.operations, ref, entry)
    order =
      [ref | socket.assigns.order]
      |> Enum.sort_by(fn id -> operations |> Map.get(id) |> Map.get(:row) |> hd() |> date_sort_key() end, :desc)

    asset_counts = Map.update(socket.assigns.asset_counts, data.asset, 1, &(&1 + 1))

    {:noreply, assign(socket,
      operations: operations,
      order: order,
      next_id: ref + 1,
      loaded: socket.assigns.loaded + 1,
      asset_counts: asset_counts
    )}
  end

  def handle_info(:loading_done, socket) do
    {:noreply, assign(socket, loading: false)}
  end

  def handle_info({:earnings_result, _ref, nil}, socket) do
    {:noreply, socket}
  end

  def handle_info({:earnings_result, ref, {abs, pct}}, socket) do
    operations =
      Map.update!(socket.assigns.operations, ref, fn entry ->
        %{entry | earnings_abs: abs, earnings_pct: pct}
      end)

    {:noreply, assign(socket, operations: operations)}
  end

  def handle_event("toggle_asset", %{"asset" => asset}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected_assets, asset) do
        MapSet.delete(socket.assigns.selected_assets, asset)
      else
        MapSet.put(socket.assigns.selected_assets, asset)
      end

    {:noreply, assign(socket, selected_assets: selected)}
  end

  def render(assigns) do
    ~H"""
    <style>
      .operations-table { width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
      .operations-table th { background: #1e293b; color: white; padding: 0.75rem 1rem; text-align: left; font-size: 0.85rem; font-weight: 600; letter-spacing: 0.03em; position: sticky; top: 0; z-index: 1; }
      .operations-table td { padding: 0.65rem 1rem; border-bottom: 1px solid #f1f5f9; font-size: 0.9rem; }
      .operations-table tr:last-child td { border-bottom: none; }
      .operations-table tr:hover td { background: #f8fafc; }
      .badge { display: inline-block; padding: 0.2rem 0.5rem; border-radius: 4px; font-size: 0.78rem; font-weight: 600; }
      .badge-suscripcion, .badge-compra { background: #dcfce7; color: #166534; } /* green-100 / green-800 */
      .badge-reembolso, .badge-venta { background: #fee2e2; color: #991b1b; }   /* red-100 / red-800 */
      .status-bar { margin-bottom: 1rem; font-size: 0.9rem; color: #64748b; display: flex; align-items: center; gap: 0.75rem; }
      .spinner { width: 14px; height: 14px; border: 2px solid #cbd5e1; border-top-color: #6366f1; border-radius: 50%; animation: spin 0.7s linear infinite; }
      @keyframes spin { to { transform: rotate(360deg); } }
      .positive { color: #16a34a; font-weight: 600; } /* green-700 */
      .negative { color: #dc2626; font-weight: 600; } /* red-600 */
      .filters { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 1.25rem; }
      .filter-btn { padding: 0.3rem 0.75rem; border-radius: 999px; border: 1px solid #cbd5e1; background: white; color: #475569; font-size: 0.82rem; cursor: pointer; }
      .filter-btn:hover { border-color: #6366f1; color: #6366f1; } /* indigo */
      .filter-btn.active { background: #6366f1; border-color: #6366f1; color: white; } /* indigo */
    </style>

    <div class="status-bar">
      <%= if @loading do %>
        <div class="spinner"></div>
        <span>Loading emails<%= if @total do %> — <%= @loaded %>/<%= @total %><% end %></span>
      <% else %>
        <span><%= map_size(@operations) %> operations loaded</span>
      <% end %>
    </div>

    <%= if @asset_counts != %{} do %>
      <div class="filters">
        <%= for {name, count} <- Enum.sort_by(@asset_counts, fn {_, c} -> c end, :desc) do %>
          <button
            class={"filter-btn#{if MapSet.member?(@selected_assets, name), do: " active", else: ""}"}
            phx-click="toggle_asset"
            phx-value-asset={name}
          >
            <%= name %> <span style="opacity: 0.65">(#<%= count %>)</span>
          </button>
        <% end %>
      </div>
    <% end %>

    <%= if map_size(@operations) > 0 do %>
      <table class="operations-table">
        <thead>
          <tr>
            <%= for h <- @headers do %>
              <th><%= h %></th>
            <% end %>
          </tr>
        </thead>
        <tbody>
          <%= for id <- visible_order(@order, @operations, @selected_assets) do %>
            <% entry = @operations[id] %>
            <tr>
              <%= for {cell, idx} <- Enum.with_index(entry.row) do %>
                <td>
                  <%= if idx == 3 do %>
                    <span class={"badge badge-#{String.downcase(cell)}"}>
                      <%= cell %>
                    </span>
                  <% else %>
                    <%= cell %>
                  <% end %>
                </td>
              <% end %>
              <td class={earnings_class(entry.earnings_abs)}>
                <%= format_abs(entry.earnings_abs) %>
              </td>
              <td class={earnings_class(entry.earnings_pct)}>
                <%= format_pct(entry.earnings_pct) %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    <% end %>
    """
  end

  defp visible_order(order, _operations, selected) when selected == %MapSet{}, do: order
  defp visible_order(order, operations, selected) do
    Enum.filter(order, fn id ->
      asset = operations |> Map.get(id) |> Map.get(:row) |> Enum.at(1)
      MapSet.member?(selected, asset)
    end)
  end

  defp date_sort_key(fecha) do
    case String.split(fecha, "/") do
      [d, m, y] -> {String.to_integer(y), String.to_integer(m), String.to_integer(d)}
      _ -> {0, 0, 0}
    end
  end

  defp earnings_class(nil), do: ""
  defp earnings_class(val) when val >= 0, do: "positive"
  defp earnings_class(_), do: "negative"

  defp format_abs(nil), do: ""
  defp format_abs(val), do: "#{val} €"

  defp format_pct(nil), do: ""
  defp format_pct(val), do: "#{val}%"
end
