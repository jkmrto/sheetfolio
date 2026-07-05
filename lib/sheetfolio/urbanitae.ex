defmodule Sheetfolio.Urbanitae do
  @moduledoc """
  Urbanitae is tracked manually in the spreadsheet: "Vision global" holds the
  invested balance and "Ganancias" the cumulative gain. This module turns those
  columns into a snapshot position (value = invested + gain).
  """

  @isin "URBANITAE"
  @column "Urbanitae"

  def fetch_history do
    spreadsheet_id = Application.fetch_env!(:sheetfolio, :spreadsheet_id)

    with {:ok, %{"values" => vision}} <-
           Sheetfolio.GoogleSheetsClient.get_sheet_data(spreadsheet_id, "Vision global!A2:AG40"),
         {:ok, %{"values" => gains}} <-
           Sheetfolio.GoogleSheetsClient.get_sheet_data(spreadsheet_id, "'Ganancias '!A1:AG40") do
      {:ok, %{invested: column_series(vision), gains: column_series(gains)}}
    end
  end

  def position_at(%{invested: invested, gains: gains}, date) do
    case value_at(invested, date) do
      nil ->
        nil

      amount ->
        gain = value_at(gains, date) || 0.0

        %{
          isin: @isin,
          asset: "Urbanitae",
          units: 1.0,
          invested: Float.round(amount, 2),
          value: Float.round(amount + gain, 2)
        }
    end
  end

  defp value_at(series, date) do
    series
    |> Enum.take_while(fn {d, _} -> Date.compare(d, date) != :gt end)
    |> List.last()
    |> case do
      nil -> nil
      {_d, value} -> value
    end
  end

  defp column_series([header | rows]) do
    idx = Enum.find_index(header, &(&1 == @column))

    rows
    # The sheets stack extra summary tables below the main one, separated by
    # blank rows — only the first table has the per-asset columns.
    |> Enum.take_while(fn row -> List.first(row) not in [nil, ""] end)
    |> Enum.flat_map(fn row ->
      with [fecha | _] <- row,
           %Date{} = date <- parse_fecha(fecha),
           amount when is_float(amount) <- parse_number(Enum.at(row, idx, "")) do
        [{date, amount}]
      else
        _ -> []
      end
    end)
    |> Enum.sort_by(&elem(&1, 0), Date)
  end

  defp parse_fecha(fecha) do
    with [d, m, y] <- String.split(fecha, "/"),
         {day, _} <- Integer.parse(d),
         {month, _} <- Integer.parse(m),
         {year, _} <- Integer.parse(y),
         {:ok, date} <- Date.new(year, month, day) do
      date
    else
      _ -> nil
    end
  end

  # es-ES formatted: "." thousands, "," decimals.
  defp parse_number(""), do: nil

  defp parse_number(value) do
    case value |> String.replace(".", "") |> String.replace(",", ".") |> Float.parse() do
      {number, _} -> number
      :error -> nil
    end
  end
end
