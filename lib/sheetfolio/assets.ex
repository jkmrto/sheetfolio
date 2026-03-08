defmodule Sheetfolio.Assets do
  @moduledoc """
  Loads the asset → ISIN mapping from the "Participaciones" sheet (row 1 = names, row 2 = ISINs).
  The sheet is the single source of truth for ISINs.
  Assets with a blank ISIN cell are automatically skipped during price fetching.
  """

  alias Sheetfolio.GoogleSheetsClient

  @doc """
  Returns {:ok, %{asset_name => isin_string}} by reading the Participaciones sheet.
  The first column (Fecha/ISIN) is skipped.
  Entries with blank ISINs are excluded.
  """
  def load_isin_map do
    spreadsheet_id = Application.fetch_env!(:sheetfolio, :spreadsheet_id)

    with {:ok, %{"values" => [header_row, isin_row | _]}} <-
           GoogleSheetsClient.get_all_values(spreadsheet_id, "Participaciones") do
      map =
        header_row
        |> Enum.zip(isin_row)
        |> Enum.drop(1)
        |> Enum.reject(fn {_name, isin} -> isin == "" or is_nil(isin) end)
        |> Map.new()

      {:ok, map}
    end
  end
end
