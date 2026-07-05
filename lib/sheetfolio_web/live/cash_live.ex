defmodule SheetfolioWeb.CashLive do
  use SheetfolioWeb, :live_view

  @sources ["Bankinter", "MyInvestor", "Wise", "Ibercaja"]
  @colors %{
    "Bankinter" => "#2a78d6",
    "MyInvestor" => "#eda100",
    "Wise" => "#1baf7a",
    "Ibercaja" => "#4a3aa7"
  }
  @collection "cash_snapshots"

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      {:ok, assign(socket, authenticated: true, saved: false, snapshots: load_snapshots(socket))}
    end
  end

  def handle_event("save", params, socket) do
    latest = latest_amounts(socket.assigns.snapshots)

    sources =
      Enum.flat_map(@sources, fn name ->
        case parse_number(params[name]) || latest[name] do
          nil -> []
          amount -> [%{name: name, amount: amount}]
        end
      end)

    doc = %{
      date: Date.to_iso8601(Date.utc_today()),
      recorded_at: DateTime.utc_now(),
      total: sources |> Enum.map(& &1.amount) |> Enum.sum() |> Float.round(2),
      sources: sources
    }

    {:ok, _} = Mongo.update_one(:mongo, @collection, %{date: doc.date}, %{"$set" => doc}, upsert: true)

    {:noreply, assign(socket, saved: true, snapshots: load_snapshots(socket))}
  end

  def render(assigns) do
    assigns = assign(assigns, latest: latest_amounts(assigns.snapshots), sources: @sources)

    ~H"""
    <style>
      .cash-form { background: white; border-radius: 12px; padding: 1.5rem 2rem; box-shadow: 0 1px 4px rgba(0,0,0,0.08); margin-bottom: 1.5rem; }
      .cash-form form { display: flex; flex-wrap: wrap; gap: 1rem; align-items: flex-end; }
      .cash-field { display: flex; flex-direction: column; gap: 0.3rem; }
      .cash-field label { font-size: 0.8rem; color: #64748b; font-weight: 600; }
      .cash-field input { border: 1px solid #e2e8f0; border-radius: 6px; padding: 0.45rem 0.6rem; font-size: 0.9rem; width: 9rem; }
      .cash-form button { background: #1e293b; color: white; border: none; border-radius: 6px; padding: 0.5rem 1.2rem; font-size: 0.9rem; cursor: pointer; }
      .cash-form button:hover { background: #334155; }
      .cash-saved { color: #1baf7a; font-size: 0.85rem; align-self: center; }
    </style>

    <div class="cash-form">
      <form phx-submit="save">
        <%= for name <- @sources do %>
          <div class="cash-field">
            <label><%= name %></label>
            <input type="text" inputmode="decimal" name={name} placeholder={placeholder(@latest[name])} />
          </div>
        <% end %>
        <button type="submit">Save today</button>
        <%= if @saved do %>
          <span class="cash-saved">Saved ✓</span>
        <% end %>
      </form>
    </div>

    <%= if @snapshots != [] do %>
      <div class="chart-container" id="cash-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(chart_payload(@snapshots))}>
        <div id="cash-chart-canvas" phx-update="ignore">
          <canvas id="cashChartCanvas"></canvas>
        </div>
      </div>
    <% end %>
    """
  end

  defp load_snapshots(socket) do
    if connected?(socket) do
      Mongo.find(:mongo, @collection, %{}, sort: %{date: 1}) |> Enum.to_list()
    else
      []
    end
  end

  defp latest_amounts(snapshots) do
    case List.last(snapshots) do
      nil -> %{}
      doc -> Map.new(doc["sources"], &{&1["name"], &1["amount"]})
    end
  end

  defp placeholder(nil), do: "0"
  defp placeholder(amount), do: :erlang.float_to_binary(amount / 1, decimals: 2)

  defp chart_payload(snapshots) do
    source_datasets =
      Enum.map(@sources, fn name ->
        %{label: name, color: @colors[name], data: source_points(snapshots, name)}
      end)

    total_dataset = %{
      label: "Total",
      color: "#1e293b",
      data: Enum.map(snapshots, &%{x: &1["date"], y: &1["total"]})
    }

    %{metric: "value", title: "Cash evolution (€)", datasets: source_datasets ++ [total_dataset]}
  end

  defp source_points(snapshots, name) do
    Enum.flat_map(snapshots, fn snap ->
      case Enum.find(snap["sources"], &(&1["name"] == name)) do
        nil -> []
        source -> [%{x: snap["date"], y: source["amount"]}]
      end
    end)
  end

  # Accepts "1234.56" and "1.234,56".
  defp parse_number(nil), do: nil
  defp parse_number(""), do: nil

  defp parse_number(value) do
    normalized =
      if String.contains?(value, ",") do
        value |> String.replace(".", "") |> String.replace(",", ".")
      else
        value
      end

    case Float.parse(String.trim(normalized)) do
      {number, _} -> number
      :error -> nil
    end
  end
end
