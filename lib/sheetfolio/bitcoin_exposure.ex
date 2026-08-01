defmodule Sheetfolio.BitcoinExposure do
  @moduledoc """
  Bitcoin exposure over time, split between the WisdomTree ETP and coins held
  on an exchange, alongside what was paid for both.

  The ETP's value and cost basis come from the daily portfolio snapshots, so
  the chart agrees with what /history and the overview already report. The
  coins can't: they only entered the snapshots on 2026-08-01, so their value is
  reconstructed as `units * BTC price on the day` and their cost basis is held
  flat at what the exchange reports today.

  Both reconstructions assume the position never changed over the window, which
  is only safe with no exchange activity in it. The last Coinbase purchase was
  2024-06-25, so it is true for 2025 onwards — the range this page charts — and
  would not be for a window reaching further back.
  """

  alias Sheetfolio.BitcoinDca

  @doc """
  One point per snapshot, oldest first:

      %{date: "2025-01-01", etp: 0.0, coinbase: 812.44, invested: 826.13}

  `invested` is the combined cost basis as it stood that day, so the gap
  between it and the stacked bands is the unrealized gain or loss.

  A snapshot with no usable BTC price is dropped rather than charted as a gap:
  a stacked band reading zero for a day would look like the position was sold.
  """
  def series(snapshots, btc_prices, coinbase, etp_isin) do
    snapshots
    |> Enum.sort_by(& &1["date"])
    |> Enum.map(&point(&1, btc_prices, coinbase, etp_isin))
    |> Enum.reject(&is_nil/1)
  end

  defp point(snapshot, btc_prices, coinbase, etp_isin) do
    date = snapshot["date"]
    position = etp_position(snapshot, etp_isin)

    case coinbase_value(date, btc_prices, coinbase.units) do
      nil ->
        nil

      value ->
        %{
          date: date,
          etp: field(position, "value"),
          coinbase: value,
          invested: Float.round(field(position, "invested") + coinbase.cost_basis, 2)
        }
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

  defp etp_position(snapshot, etp_isin) do
    snapshot["positions"]
    |> List.wrap()
    |> Enum.find(&(&1["isin"] == etp_isin))
  end

  # A date before the ETP was bought has no position at all, and a stored
  # position can carry a nil value when its quote failed.
  defp field(nil, _key), do: 0.0

  defp field(position, key) do
    case position[key] do
      value when is_number(value) -> Float.round(value * 1.0, 2)
      _ -> 0.0
    end
  end
end
