defmodule Sheetfolio.AssetCategories do
  @moduledoc """
  Asset → category mapping, read from the spreadsheet.

  "Vision global" row 1 holds the category sitting above each asset column, and
  "Participaciones" row 2 holds that same column's ISIN, so the two rows are
  joined by **column position** rather than by asset name. The sheets keep the
  same column order but not always the same label — the column now holding
  Fidelity (IE00BYX5MX67) is still titled "Vanguard U.S. 500" in Vision global
  after the traspaso, so a name join would drop it.

  Loaded once at boot and refreshed daily; categories change about as often as a
  new asset is bought.
  """
  use GenServer

  require Logger

  alias Sheetfolio.GoogleSheetsClient

  @vision_sheet "Vision global"
  @participaciones_sheet "Participaciones"
  @refresh_ms 24 * 60 * 60 * 1000
  @uncategorized "Sin categoría"

  # The sheet is the source of truth. These are consulted only when it has
  # nothing for a holding, so they go quiet on their own once the sheet is
  # updated:
  #   DE000A1E0HS6, CA50077N1024 — the sheet's ISIN row holds a ticker
  #                                (XAD6.DE, PNG.V) for these two
  #   US8629451027              — Strive's ISIN changed; the sheet still has
  #                                the old US8629453007
  #   IE000RHYOR04              — bought after the header row was last extended
  #   URBANITAE, EQUITO,        — property held through crowdfunding platforms,
  #   EFECTIVO                     tracked in columns that carry no ISIN; cash
  #                                comes from cash_snapshots rather than from
  #                                a market position
  #   COINBASE-BTC              — coins held on an exchange, synthesised by
  #                                SnapshotRecorder; grouped with the Bitcoin
  #                                ETP so the donut shows one Bitcoin slice
  #   N5396                     — the MyInvestor Indexado Global pension plan,
  #                                identified by its DGS code; the sheet
  #                                doesn't track it at all
  # Sold-out holdings that only appear in older snapshots. Each is an earlier
  # share class of a fund the sheet does list under its current ISIN, so the
  # sheet alone can't categorise the history:
  #   ES0170156048 — Santalucía Renta Fija, now ES0158457037
  #   IE0032126645 — Vanguard US 500, traspaso'd into Fidelity IE00BYX5MX67
  #   IE00B04GQX83 — Vanguard US Investment Grade, now IE00BZ163M45
  @fallback_categories %{
    "DE000A1E0HS6" => "Silver",
    "CA50077N1024" => "Custom Stocks",
    "US8629451027" => "Custom Stocks",
    "IE000RHYOR04" => "Renta fija corto plazo",
    "URBANITAE" => "Inmobiliario",
    "EQUITO" => "Inmobiliario",
    "COINBASE-BTC" => "Bitcoin",
    "EFECTIVO" => "Efectivo",
    "ES0170156048" => "Renta fija corto plazo",
    "IE0032126645" => "Indexados",
    "IE00B04GQX83" => "Renta fija largo plazo",
    "N5396" => "Indexados"
  }

  # Regrouping applied on top of whatever the sheet says, so the dashboard can
  # report precious metals as one holding while the sheet keeps its finer
  # split. VanEck Gold Miners moves by ISIN because the sheet files it under
  # "Indexado Sectorial", which Van Eck Semiconductors also uses — that one
  # should stay put.
  @regroup_by_isin %{"IE00BQQP9F84" => "Oro/Plata"}
  @regroup_by_category %{"Gold" => "Oro/Plata", "Silver" => "Oro/Plata"}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Identifier → category, as read from the sheet. Empty until the first load lands."
  def get, do: GenServer.call(__MODULE__, :get)

  def reload, do: GenServer.cast(__MODULE__, :load)

  def uncategorized, do: @uncategorized

  @impl true
  def init(nil) do
    send(self(), :load)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:load, state) do
    Process.send_after(self(), :load, @refresh_ms)
    {:noreply, load_categories(state)}
  end

  @impl true
  def handle_cast(:load, state), do: {:noreply, load_categories(state)}

  @impl true
  def handle_call(:get, _from, state), do: {:reply, state, state}

  # Keeps the previous mapping when the sheet can't be read, so a transient
  # Sheets failure doesn't drop every position into "uncategorized".
  defp load_categories(state) do
    case fetch_from_sheet() do
      {:ok, categories} ->
        Logger.info("[AssetCategories] Loaded #{map_size(categories)} asset categories")
        categories

      {:error, reason} ->
        Logger.warning("[AssetCategories] Could not read categories: #{inspect(reason)}")
        state
    end
  end

  defp fetch_from_sheet do
    spreadsheet_id = Application.fetch_env!(:sheetfolio, :spreadsheet_id)

    with {:ok, %{"values" => [categories | _]}} <-
           GoogleSheetsClient.get_all_values(spreadsheet_id, @vision_sheet),
         {:ok, %{"values" => [_names, isins | _]}} <-
           GoogleSheetsClient.get_all_values(spreadsheet_id, @participaciones_sheet) do
      {:ok, zip_columns(isins, categories)}
    end
  end

  @doc """
  Pairs each column's identifier with the category above it, dropping the
  leading `Fecha`/`ISIN` label column and any column missing either value.
  """
  def zip_columns(isins, categories) do
    width = max(length(isins), length(categories))

    pad(isins, width)
    |> Enum.zip(pad(categories, width))
    |> Enum.drop(1)
    |> Enum.map(fn {isin, category} -> {trim(isin), trim(category)} end)
    |> Enum.reject(fn {isin, category} -> isin == "" or category == "" end)
    |> Map.new()
  end

  defp pad(list, width), do: list ++ List.duplicate("", max(0, width - length(list)))

  defp trim(value), do: value |> to_string() |> String.trim()

  @doc """
  The category an identifier is reported under: the sheet's value, or a
  fallback when the sheet can't match it, with the precious-metals regrouping
  applied on top.
  """
  def category_for(isin, categories) do
    Map.get(@regroup_by_isin, isin) || regroup(from_sheet(isin, categories))
  end

  defp from_sheet(isin, categories) do
    Map.get(categories, isin) || Map.get(@fallback_categories, isin) || @uncategorized
  end

  defp regroup(category), do: Map.get(@regroup_by_category, category, category)

  @doc """
  Groups valued positions into `%{category, value, pct, assets}`, largest
  first. Positions without a value (no quote and no history to carry forward)
  are left out rather than counted as zero.
  """
  def breakdown(positions, categories) do
    valued = Enum.filter(positions, &(is_number(&1["value"]) and &1["value"] > 0))
    total = Enum.reduce(valued, 0.0, &(&1["value"] + &2))

    valued
    |> Enum.group_by(&category_for(&1["isin"], categories))
    |> Enum.map(fn {category, group} -> slice(category, group, total) end)
    |> Enum.sort_by(&(-&1.value))
  end

  defp slice(category, group, total) do
    value = Enum.reduce(group, 0.0, &(&1["value"] + &2))

    %{
      category: category,
      value: Float.round(value, 2),
      pct: percentage(value, total),
      assets: group |> Enum.sort_by(&(-&1["value"])) |> Enum.map(& &1["asset"])
    }
  end

  defp percentage(_value, total) when total <= 0, do: 0.0
  defp percentage(value, total), do: Float.round(value / total * 100, 1)

  @doc """
  Category totals for a series of dated position lists, in the order given:

      [%{date: "2025-01-01", totals: %{"Indexados" => 1234.0, ...}}, ...]

  A category absent on a date is absent from that date's map rather than
  present as zero, so callers can tell "not held yet" from "held, worth
  nothing".
  """
  def history(dated_positions, categories) do
    Enum.map(dated_positions, fn {date, positions} ->
      totals =
        positions
        |> breakdown(categories)
        |> Map.new(&{&1.category, &1.value})

      %{date: date, totals: totals}
    end)
  end

  # A stacked chart is easiest to read with its steadiest series on the bottom:
  # every band above it then moves with its own value instead of inheriting the
  # floor's wobble. Urbanitae's outstanding balance only changes when a project
  # opens or closes, so Inmobiliario leads.
  @leading_categories ["Inmobiliario"]

  @doc """
  Every category appearing anywhere in a `history/2` series, in stacking order:
  the steady categories first, then the rest largest total first.
  """
  def history_categories(history) do
    totals =
      Enum.reduce(history, %{}, fn %{totals: totals}, acc ->
        Map.merge(acc, totals, fn _category, running, value -> running + value end)
      end)

    leading = Enum.filter(@leading_categories, &Map.has_key?(totals, &1))

    rest =
      totals
      |> Map.drop(@leading_categories)
      |> Enum.sort_by(fn {_category, total} -> -total end)
      |> Enum.map(&elem(&1, 0))

    leading ++ rest
  end
end
