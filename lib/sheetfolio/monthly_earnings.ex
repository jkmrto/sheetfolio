defmodule Sheetfolio.MonthlyEarnings do
  @moduledoc """
  What each asset earned per month: realized, unrealized and dividends together.

  For every month-end an asset's cumulative gain is

      value - cost still held + realized so far + dividends so far

  and a month's earnings are the change in that figure, so the months of a
  position always add up to its total, and a sale moves gain from unrealized to
  realized without counting as earnings.

  Units, cost and realized come from replaying the operations rather than from
  the stored snapshots, which hold a late-confirmed sale as still owned and carry
  older cost figures. A snapshot only supplies the unit price of its date. Assets
  with no operations, such as coins held on an exchange, use the snapshot's own
  value and cost. Ledgers like Urbanitae and Equito are passed in as `{label, fun}`,
  where `fun` gives the cumulative earnings at an ISO date.
  """

  alias Sheetfolio.Positions

  @doc """
  `snapshots` oldest first, and `history` from `Positions.history/3`:

      %{months: ["2026-01", ...], rows: [%{key, asset, months: %{"2026-01" => 12.5}}]}
  """
  def build(snapshots, history, dividends, ledgers \\ [])

  def build([], _history, _dividends, _ledgers), do: %{months: [], rows: []}

  def build(snapshots, history, dividends, ledgers) do
    [first | _] = checkpoints = checkpoints(snapshots)
    replayed = replayed_keys(history)

    {gains, _prices} =
      Enum.map_reduce(checkpoints, %{}, fn doc, prices ->
        prices = update_prices(prices, doc)
        {{doc["date"], gains_at(doc, prices, history, replayed, dividends, ledgers)}, prices}
      end)

    months = monthly(gains)

    %{
      months: checkpoints |> Enum.drop(1) |> Enum.map(&month_of(&1["date"])) |> Enum.uniq(),
      first_date: first["date"],
      rows: rows(months)
    }
  end

  @doc """
  One year of `build/4`'s result, best earner first, with the totals by month:

      %{months, total: %{months, total}, rows: [%{asset, months, total}]}
  """
  def for_year(%{months: months, rows: rows}, year) do
    shown = Enum.filter(months, &String.starts_with?(&1, year))

    rows =
      rows
      |> Enum.map(&year_row(&1, shown))
      |> Enum.reject(&(abs(&1.total) < 0.005 and Enum.all?(Map.values(&1.months), fn v -> abs(v) < 0.005 end)))
      |> Enum.sort_by(& &1.total, :desc)

    by_month = Map.new(shown, &{&1, Enum.reduce(rows, 0.0, fn row, acc -> acc + Map.get(row.months, &1, 0.0) end)})

    %{months: shown, rows: rows, total: %{months: by_month, total: by_month |> Map.values() |> Enum.sum()}}
  end

  @doc "The years covered, newest first."
  def years(%{months: months}) do
    months |> Enum.map(&String.slice(&1, 0, 4)) |> Enum.uniq() |> Enum.sort(:desc)
  end

  defp year_row(row, shown) do
    kept = Map.take(row.months, shown)
    %{asset: row.asset, months: kept, total: kept |> Map.values() |> Enum.sum()}
  end

  # The first snapshot anchors the first month, then each month's last one.
  defp checkpoints([first | _] = snapshots) do
    ends =
      snapshots
      |> Enum.chunk_by(&month_of(&1["date"]))
      |> Enum.map(&List.last/1)

    [first | ends]
  end

  defp month_of(date), do: String.slice(date, 0, 7)

  defp replayed_keys([]), do: MapSet.new()

  defp replayed_keys(history) do
    {_fecha, assets} = List.last(history)
    assets |> Map.keys() |> MapSet.new()
  end

  # The last price seen stands in when a snapshot lacks a position it should
  # hold, so a gap doesn't read as the whole value vanishing for a month.
  defp update_prices(prices, doc) do
    doc
    |> positions()
    |> Enum.filter(&priced?/1)
    |> Enum.reduce(prices, &Map.put(&2, &1["isin"], &1["value"] / &1["units"]))
  end

  defp priced?(%{"value" => value, "units" => units}) when is_number(value) and is_number(units), do: units > 0
  defp priced?(_position), do: false

  defp positions(doc), do: Enum.reject(doc["positions"] || [], &(&1["isin"] == "URBANITAE"))

  defp gains_at(doc, prices, history, replayed, dividends, ledgers) do
    date = doc["date"]

    %{}
    |> add_replayed(assets_at(history, date), prices)
    |> add_unreplayed(doc, replayed)
    |> add_dividends(dividends, date)
    |> add_ledgers(ledgers, date)
  end

  defp assets_at(history, date) do
    history
    |> Enum.take_while(fn {fecha, _assets} -> iso(fecha) <= date end)
    |> List.last()
    |> then(fn
      nil -> %{}
      {_fecha, assets} -> assets
    end)
  end

  defp iso(fecha) do
    {year, month, day} = Positions.date_sort_key(fecha)
    "#{year}-#{month}-#{day}"
  end

  defp add_replayed(gains, assets, prices) do
    Enum.reduce(assets, gains, fn {isin, asset}, acc ->
      add(acc, isin, asset.asset, asset.realized + unrealized(asset, prices[isin]))
    end)
  end

  defp unrealized(%{net_qty: units}, _price) when units <= 0, do: 0.0
  defp unrealized(_asset, nil), do: 0.0
  defp unrealized(%{net_qty: units, cost_basis: cost}, price), do: units * price - cost

  defp add_unreplayed(gains, doc, replayed) do
    doc
    |> positions()
    |> Enum.reject(&MapSet.member?(replayed, &1["isin"]))
    |> Enum.filter(&is_number(&1["value"]))
    |> Enum.reduce(gains, &add(&2, &1["isin"], &1["asset"], &1["value"] - (&1["invested"] || 0.0)))
  end

  defp add_dividends(gains, dividends, date) do
    dividends
    |> Enum.filter(&(&1["date"] <= date))
    |> Enum.reduce(gains, &add(&2, &1["isin"], &1["asset"], &1["amount"]))
  end

  defp add_ledgers(gains, ledgers, date) do
    Enum.reduce(ledgers, gains, fn {label, earnings_at}, acc -> add(acc, label, label, earnings_at.(date)) end)
  end

  defp add(gains, key, asset, amount) do
    Map.update(gains, key, %{asset: asset, gain: amount}, &%{&1 | gain: &1.gain + amount})
  end

  # `[{month, key, asset, earned}]`, each checkpoint against the one before.
  defp monthly(gains) do
    gains
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [{_before, was}, {date, now}] -> differences(month_of(date), was, now) end)
  end

  defp differences(month, was, now) do
    for key <- Enum.uniq(Map.keys(was) ++ Map.keys(now)) do
      asset = (now[key] || was[key]).asset
      {month, key, asset, gain_of(now[key]) - gain_of(was[key])}
    end
  end

  defp gain_of(nil), do: 0.0
  defp gain_of(%{gain: gain}), do: gain

  defp rows(monthly) do
    monthly
    |> Enum.group_by(fn {_month, key, _asset, _earned} -> key end)
    |> Enum.map(fn {key, entries} ->
      %{
        key: key,
        asset: entries |> List.last() |> elem(2),
        months: Map.new(entries, fn {month, _key, _asset, earned} -> {month, earned} end)
      }
    end)
  end
end
