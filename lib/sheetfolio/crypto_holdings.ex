defmodule Sheetfolio.CryptoHoldings do
  @moduledoc """
  Coins held directly on an exchange, outside the MyInvestor brokerage.

  Coinbase has no API wired up here, so a holding is captured from the app's
  Saldo screen: units held plus the average cost it reports. Only the cost side
  is stored — the value is priced live against BTC-EUR, so a stale screenshot
  can't freeze a wrong valuation into the page.

  The average cost is taken as authoritative rather than replayed from the
  transaction list, which the Coinbase UI filters by date and can silently
  under-report: as of the 2026-08-01 capture the visible transactions accounted
  for 0.01563 BTC of a 0.02018811 BTC balance.

      { platform: "Coinbase",
        symbol: "BTC",
        units: 0.02018811,
        cost_basis: 826.13,       # EUR, units * avg_cost
        avg_cost: 40921.66,       # EUR per coin, as Coinbase reports it
        captured_at: <DateTime> }
  """

  @collection "crypto_holdings"

  def all do
    Mongo.find(:mongo, @collection, %{}, sort: %{platform: 1}) |> Enum.to_list()
  end

  def by_symbol(symbol) do
    Mongo.find(:mongo, @collection, %{"symbol" => symbol}) |> Enum.to_list()
  end

  @doc """
  Upsert by `{platform, symbol}` — re-capturing the same wallet updates it in
  place instead of accumulating one document per screenshot.
  """
  def upsert(%{platform: platform, symbol: symbol} = doc) do
    now = DateTime.utc_now()
    fields = doc |> Map.take([:units, :cost_basis, :avg_cost]) |> Map.put(:captured_at, now)

    {:ok, _} =
      Mongo.update_one(
        :mongo,
        @collection,
        %{"platform" => platform, "symbol" => symbol},
        %{"$set" => fields, "$setOnInsert" => %{"platform" => platform, "symbol" => symbol}},
        upsert: true
      )

    :ok
  end

  @doc """
  Value the holdings at `price` (EUR per coin), returning totals plus a row per
  holding. A nil price leaves the value side nil rather than guessing.

      %{units, cost_basis, value, unrealized, holdings: [...]}
  """
  def position(holdings, price) do
    rows = Enum.map(holdings, &row(&1, price))

    %{
      units: rows |> Enum.reduce(0.0, &(&1.units + &2)) |> round8(),
      cost_basis: rows |> Enum.reduce(0.0, &(&1.cost_basis + &2)) |> round2(),
      value: total_value(rows),
      unrealized: total_unrealized(rows),
      holdings: rows
    }
  end

  defp row(holding, price) do
    units = holding["units"] * 1.0
    cost_basis = holding["cost_basis"] * 1.0

    %{
      platform: holding["platform"],
      symbol: holding["symbol"],
      units: units,
      cost_basis: round2(cost_basis),
      avg_cost: holding["avg_cost"],
      value: value_at(units, price),
      unrealized: unrealized_at(units, cost_basis, price)
    }
  end

  defp value_at(_units, nil), do: nil
  defp value_at(units, price), do: round2(units * price)

  defp unrealized_at(_units, _cost_basis, nil), do: nil
  defp unrealized_at(units, cost_basis, price), do: round2(units * price - cost_basis)

  defp total_value(rows), do: sum_or_nil(rows, & &1.value)
  defp total_unrealized(rows), do: sum_or_nil(rows, & &1.unrealized)

  # Any unpriced holding makes the total meaningless, so it stays nil.
  defp sum_or_nil(rows, field) do
    if Enum.any?(rows, &(field.(&1) == nil)),
      do: nil,
      else: rows |> Enum.reduce(0.0, &(field.(&1) + &2)) |> round2()
  end

  defp round2(number), do: Float.round(number * 1.0, 2)
  defp round8(number), do: Float.round(number * 1.0, 8)
end
