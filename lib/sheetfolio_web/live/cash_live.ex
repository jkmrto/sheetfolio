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
  @ranges ~w(1m 3m 1y ytd all)

  def mount(_params, session, socket) do
    if session["authenticated"] != true do
      {:ok, push_navigate(socket, to: "/login")}
    else
      if connected?(socket), do: send(self(), :fetch_wise)

      {:ok,
       assign(socket,
         authenticated: true,
         saved: false,
         range: "all",
         snapshots: load_snapshots(socket),
         wise_balance: nil
       )}
    end
  end

  def handle_info(:fetch_wise, socket) do
    case Sheetfolio.WiseBalance.current_eur() do
      {:ok, amount} -> {:noreply, assign(socket, wise_balance: amount)}
      {:error, _reason} -> {:noreply, socket}
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

  def handle_event("set_range", %{"range" => range}, socket) when range in @ranges do
    {:noreply, assign(socket, range: range)}
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
      .range-row { display: flex; margin-bottom: 1rem; }
      .range-toggle { display: flex; border: 1px solid #e2e8f0; border-radius: 6px; overflow: hidden; }
      .range-toggle button { border: none; background: white; color: #475569; padding: 0.35rem 0.8rem; font-size: 0.82rem; cursor: pointer; }
      .range-toggle button.selected { background: #1e293b; color: white; }
    </style>

    <div class="cash-form">
      <form phx-submit="save">
        <%= for name <- @sources do %>
          <div class="cash-field">
            <label><%= name %></label>
            <input type="text" inputmode="decimal" name={name} placeholder={placeholder(source_placeholder(name, @latest, @wise_balance))} />
          </div>
        <% end %>
        <button type="submit">Save today</button>
        <%= if @saved do %>
          <span class="cash-saved">Saved ✓</span>
        <% end %>
      </form>
    </div>

    <%= if @snapshots != [] do %>
      <div class="range-row">
        <div class="range-toggle">
          <%= for {value, label} <- range_options() do %>
            <button class={if @range == value, do: "selected"} phx-click="set_range" phx-value-range={value}><%= label %></button>
          <% end %>
        </div>
      </div>

      <div class="chart-container" id="cash-chart" phx-hook="HistoryChart" data-chart={Jason.encode!(chart_payload(filter_range(@snapshots, @range)))}>
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

  # The Wise field prefers the freshly-fetched live balance over whatever was
  # last saved; the other fields only ever have the last saved amount.
  defp source_placeholder("Wise", latest, wise_balance), do: wise_balance || latest["Wise"]
  defp source_placeholder(name, latest, _wise_balance), do: latest[name]

  defp range_options, do: [{"1m", "1M"}, {"3m", "3M"}, {"1y", "1Y"}, {"ytd", "YTD"}, {"all", "All"}]

  defp filter_range(snapshots, "all"), do: snapshots

  defp filter_range(snapshots, range) do
    cutoff = range |> cutoff_date(Date.utc_today()) |> Date.to_iso8601()
    Enum.filter(snapshots, &(&1["date"] >= cutoff))
  end

  defp cutoff_date("1m", today), do: Date.shift(today, month: -1)
  defp cutoff_date("3m", today), do: Date.shift(today, month: -3)
  defp cutoff_date("1y", today), do: Date.shift(today, year: -1)
  defp cutoff_date("ytd", today), do: Date.new!(today.year, 1, 1)

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
