defmodule Sheetfolio.PortfolioCalculator do
  @moduledoc """
  Reads the latest row from the "Participaciones" sheet, fetches current prices,
  and returns the total portfolio value in EUR broken down by asset.
  """

  alias Sheetfolio.{Assets, GoogleSheetsClient, PriceFetcher, SheetData}

  def calculate do
    spreadsheet_id = Application.fetch_env!(:sheetfolio, :spreadsheet_id)

    with {:ok, body} <- GoogleSheetsClient.get_all_values(spreadsheet_id, "Participaciones"),
         {:ok, isin_map} <- Assets.load_isin_map(),
         {:ok, headers, quantities} <- parse_latest_row(body) do
      priceable =
        headers
        |> Enum.zip(quantities)
        |> Enum.reject(fn {_name, qty} -> is_nil(qty) or qty == 0.0 end)
        |> Enum.flat_map(fn {name, qty} ->
          case Map.get(isin_map, name) do
            nil -> []
            isin -> [{name, isin, qty}]
          end
        end)

      isin_map = Map.new(priceable, fn {name, isin, _} -> {name, isin} end)
      prices = PriceFetcher.fetch_prices(isin_map)

      assets =
        Enum.map(priceable, fn {name, _isin, qty} ->
          price = Map.get(prices, name)
          value = if price, do: qty * price, else: nil
          %{name: name, quantity: qty, price_eur: price, value_eur: value}
        end)

      total =
        assets
        |> Enum.map(& &1.value_eur)
        |> Enum.reject(&is_nil/1)
        |> Enum.sum()

      {:ok, %{assets: assets, total_eur: total}}
    end
  end

  defp parse_latest_row(%{"values" => rows}) do
    headers = List.first(rows, []) |> Enum.drop(1)

    case rows |> Enum.filter(&SheetData.date_row?/1) |> List.last() do
      nil ->
        {:error, :no_data_rows}

      row ->
        quantities =
          row
          |> Enum.drop(1)
          |> Enum.map(&parse_quantity/1)
          |> pad_to(length(headers), nil)

        {:ok, headers, quantities}
    end
  end

  defp parse_latest_row(_), do: {:error, :invalid_body}

  defp parse_quantity("-"), do: nil
  defp parse_quantity(""), do: nil
  defp parse_quantity(nil), do: nil

  defp parse_quantity(str) do
    cleaned = str |> String.replace(".", "") |> String.replace(",", ".")

    case Float.parse(cleaned) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp pad_to(list, length, fill) do
    list ++ List.duplicate(fill, max(0, length - length(list)))
  end
end
