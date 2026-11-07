defmodule SheetfolioWeb.NumberFormat do
  @moduledoc """
  How numbers read on every page: `1.234.567,89`, dots for thousands and a
  comma for decimals, with a dash for a missing value.
  """

  @missing "—"
  @email_number ~r/^(-?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?)(\s*[[:alpha:]]*)$/u

  def number(value, decimals \\ 2) do
    value
    |> rounded(decimals)
    |> :erlang.float_to_binary(decimals: decimals)
    |> localize()
  end

  def eur(nil), do: @missing
  def eur(value), do: "#{number(value)} €"

  def signed_eur(nil), do: @missing
  def signed_eur(value) when value >= 0, do: "+#{eur(value)}"
  def signed_eur(value), do: eur(value)

  def pct(nil), do: @missing
  def pct(value), do: "#{number(value)}%"

  def signed_pct(nil), do: @missing
  def signed_pct(value) when value >= 0, do: "+#{pct(value)}"
  def signed_pct(value), do: pct(value)

  @doc "Units, with only the decimals they need."
  def qty(nil), do: @missing

  def qty(value) do
    value
    |> rounded(4)
    |> :erlang.float_to_binary(decimals: 4)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
    |> localize()
  end

  @doc """
  Formats a number as written in a confirmation email, such as `"1,499.91 EUR"`,
  keeping its decimals and unit. Anything else comes back unchanged.
  """
  def text(value) when is_binary(value) do
    case Regex.run(@email_number, String.trim(value)) do
      [_match, digits, unit] -> localize(String.replace(digits, ",", "")) <> unit
      nil -> value
    end
  end

  def text(value), do: value

  # Rounding first keeps a tiny negative from printing as "-0,00".
  defp rounded(value, decimals) do
    case Float.round(value * 1.0, decimals) do
      zero when zero == 0 -> 0.0
      value -> value
    end
  end

  defp localize(digits) do
    [whole | decimals] = String.split(digits, ".")
    grouped = String.replace(whole, ~r/(?<=\d)(?=(\d{3})+$)/, ".")
    Enum.join([grouped | decimals], ",")
  end
end
