defmodule BackfillCash do
  @moduledoc """
  Loads the historical cash balances (Efectivo columns of "Vision global")
  into the cash_snapshots collection, one document per sheet row.

  Run with: set -a && . ./.env && set +a && mix run scripts/backfill_cash.exs
  """

  @sources ["Bankinter", "MyInvestor", "Wise", "Ibercaja"]
  @collection "cash_snapshots"

  def run do
    spreadsheet_id = Application.fetch_env!(:sheetfolio, :spreadsheet_id)

    {:ok, %{"values" => rows}} =
      Sheetfolio.GoogleSheetsClient.get_sheet_data(spreadsheet_id, "Vision global!A2:AG30")

    [header | data] = rows
    indexes = Enum.map(@sources, fn name -> Enum.find_index(header, &(&1 == name)) end)

    docs =
      data
      |> Enum.map(&row_doc(&1, indexes))
      |> Enum.filter(& &1)

    Enum.each(docs, fn doc ->
      {:ok, _} =
        Mongo.update_one(:mongo, @collection, %{date: doc.date}, %{"$set" => doc}, upsert: true)
    end)

    IO.puts("Upserted #{length(docs)} cash snapshots.")
  end

  defp row_doc([fecha | _] = row, indexes) do
    with %Date{} = date <- parse_fecha(fecha),
         [_ | _] = sources <- row_sources(row, indexes) do
      %{
        date: Date.to_iso8601(date),
        recorded_at: DateTime.utc_now(),
        total: sources |> Enum.map(& &1.amount) |> Enum.sum() |> Float.round(2),
        sources: sources
      }
    else
      _ -> nil
    end
  end

  defp row_doc(_row, _indexes), do: nil

  defp row_sources(row, indexes) do
    @sources
    |> Enum.zip(indexes)
    |> Enum.flat_map(fn {name, idx} ->
      case parse_number(Enum.at(row, idx, "")) do
        nil -> []
        amount -> [%{name: name, amount: amount}]
      end
    end)
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

BackfillCash.run()
