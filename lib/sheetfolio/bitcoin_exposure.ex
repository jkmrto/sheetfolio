defmodule Sheetfolio.BitcoinExposure do
  @moduledoc """
  Bitcoin exposure over time, split between the WisdomTree ETP and coins held
  on an exchange.

  The ETP's value comes from the daily portfolio snapshots, so the chart agrees
  with what /history and the overview already report. The coins can't: they only
  entered the snapshots on 2026-08-01, so their history is reconstructed as
  `units * BTC price on the day`.

  That reconstruction holds the unit count constant, which is only safe over a
  window with no exchange activity. The last Coinbase purchase was 2024-06-25,
  so it is true for 2025 onwards — the range this page charts — and would not be
  for a window reaching further back.
  """

  alias Sheetfolio.BitcoinDca

  @doc """
  One point per snapshot, oldest first:

      %{date: "2025-01-01", etp: 0.0, coinbase: 812.44}

  A snapshot with no usable BTC price is dropped rather than charted as a gap:
  a stacked band reading zero for a day would look like the position was sold.
  """
  def series(snapshots, btc_prices, units, etp_isin) do
    snapshots
    |> Enum.sort_by(& &1["date"])
    |> Enum.map(&point(&1, btc_prices, units, etp_isin))
    |> Enum.reject(&is_nil/1)
  end

  defp point(snapshot, btc_prices, units, etp_isin) do
    date = snapshot["date"]

    case coinbase_value(date, btc_prices, units) do
      nil -> nil
      value -> %{date: date, etp: etp_value(snapshot, etp_isin), coinbase: value}
    end
  end

  defp coinbase_value(date, btc_prices, units) do
    with {:ok, parsed} <- Date.from_iso8601(date),
         price when is_number(price) <- BitcoinDca.nearest_price(btc_prices, parsed) do
      Float.round(units * price, 2)
    else
      _ -> nil
    end
  end

  defp etp_value(snapshot, etp_isin) do
    snapshot["positions"]
    |> List.wrap()
    |> Enum.find(&(&1["isin"] == etp_isin))
    |> position_value()
  end

  defp position_value(%{"value" => value}) when is_number(value), do: Float.round(value * 1.0, 2)
  defp position_value(_position), do: 0.0
end
