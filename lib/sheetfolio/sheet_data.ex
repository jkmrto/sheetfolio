defmodule Sheetfolio.SheetData do
  alias Sheetfolio.GoogleSheetsClient

  def portfolio_chart_data do
    spreadsheet_id = Application.fetch_env!(:sheetfolio, :spreadsheet_id)

    with {:ok, vision_body} <- GoogleSheetsClient.get_all_values(spreadsheet_id, "Vision global"),
         {:ok, ganancias_body} <- GoogleSheetsClient.get_all_values(spreadsheet_id, "Ganancias ") do
      totals = parse_series(vision_body)
      earnings = parse_series(ganancias_body)

      all_dates = Map.keys(totals) |> Enum.concat(Map.keys(earnings)) |> Enum.uniq()

      series =
        all_dates
        |> Enum.map(fn date ->
          %{date: date, total: Map.get(totals, date), earnings: Map.get(earnings, date)}
        end)
        |> Enum.sort_by(& &1.date, {:asc, Date})

      %{series: series}
    else
      {:error, reason} -> %{series: [], error: inspect(reason)}
    end
  end

  defp parse_series(%{"values" => all_rows}) do
    total_idx =
      all_rows
      |> Enum.find_value(fn row -> Enum.find_index(row, &(&1 == "Total")) end)

    if is_nil(total_idx) do
      %{}
    else
      all_rows
      |> Enum.filter(&date_row?/1)
      |> Enum.reduce(%{}, fn row, acc ->
        raw_date = List.first(row)
        value = row |> Enum.at(total_idx, "") |> parse_number()

        case {parse_date(raw_date), value} do
          {{:ok, date}, v} when not is_nil(v) -> Map.put(acc, date, v)
          _ -> acc
        end
      end)
    end
  end

  def date_row?(row) do
    case List.first(row) do
      nil -> false
      str -> Regex.match?(~r/^\d{1,2}\/\d{1,2}\/\d{4}$/, str)
    end
  end

  defp parse_date(str) do
    case String.split(str, "/") do
      [d, m, y] -> Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d))
      _ -> :error
    end
  end

  defp parse_number(""), do: nil
  defp parse_number(nil), do: nil

  defp parse_number(str) do
    cleaned = str |> String.replace(".", "") |> String.replace(",", ".")

    case Float.parse(cleaned) do
      {n, _} -> n
      :error -> nil
    end
  end
end
