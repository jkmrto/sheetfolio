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
  #   URBANITAE                 — tracked in a column that carries no ISIN
  @fallback_categories %{
    "DE000A1E0HS6" => "Silver",
    "CA50077N1024" => "Custom Stocks",
    "US8629451027" => "Custom Stocks",
    "IE000RHYOR04" => "Renta fija corto plazo",
    "URBANITAE" => "Inmobiliario"
  }

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

  @doc "The category for an identifier, falling back to the overrides then to uncategorized."
  def category_for(isin, categories) do
    Map.get(categories, isin) || Map.get(@fallback_categories, isin) || @uncategorized
  end

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
end
