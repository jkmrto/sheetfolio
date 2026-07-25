defmodule Sheetfolio.Money do
  @moduledoc """
  Parsing of the amount strings that come out of the MyInvestor emails, and
  conversion to EUR.

  The emails mix Spanish and English number formats ("1.418,996" and "1,000.34"
  both appear), so which separator is the decimal one has to be worked out per
  value rather than assumed.
  """

  @price_with_currency ~r/([\d.,]+)\s+([A-Z]+)/

  @doc """
  Parses a number written in either Spanish or English convention, returning
  `{float, rest}` like `Float.parse/1`, or `:error`.
  """
  def parse_number(str) do
    cond do
      String.contains?(str, ".") and String.contains?(str, ",") ->
        parse_mixed(str)

      String.contains?(str, ",") ->
        parse_comma_only(str)

      true ->
        Float.parse(str)
    end
  end

  # Determine format by which separator appears last.
  # "1,000.34" → dot last → English (comma=thousands) → 1000.34
  # "1.418,996" → comma last → Spanish (dot=thousands) → 1418.996
  defp parse_mixed(str) do
    last_dot = str |> :binary.matches(".") |> List.last() |> elem(0)
    last_comma = str |> :binary.matches(",") |> List.last() |> elem(0)

    if last_dot > last_comma do
      str |> String.replace(",", "") |> Float.parse()
    else
      str |> String.replace(".", "") |> String.replace(",", ".") |> Float.parse()
    end
  end

  # If exactly 3 digits follow the last comma: English thousands separator.
  # "1,188" → 1188 | "14,2592" → 14.2592
  defp parse_comma_only(str) do
    case Regex.run(~r/^[\d,]+,(\d{3})$/, str) do
      [_, _] -> str |> String.replace(",", "") |> Float.parse()
      _ -> str |> String.replace(",", ".") |> Float.parse()
    end
  end

  @doc """
  Splits a string like `"2563.52 EUR"` into `{amount, currency}`, or `:error`.
  """
  def parse_price(str) do
    case Regex.run(@price_with_currency, str) do
      [_, amount, currency] -> with_currency(parse_number(amount), currency)
      _ -> :error
    end
  end

  defp with_currency({value, _rest}, currency), do: {value, currency}
  defp with_currency(:error, _currency), do: :error

  def to_eur(price, "USD", eur_usd, _eur_cad), do: price / eur_usd
  def to_eur(price, "CAD", _eur_usd, eur_cad), do: price / eur_cad
  def to_eur(price, _currency, _eur_usd, _eur_cad), do: price
end
