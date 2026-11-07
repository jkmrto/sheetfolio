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
  where `fun` gives `{outstanding, earnings}` at an ISO date.

  A month's return is its earnings over the capital at work: the value it started
  with plus what was bought during it, so a position bought mid-month still has
  one. A year's return compounds its months, because the capital changes between
  them and percentages of different bases don't add up.
  """

  alias Sheetfolio.Positions

  # Below this there's nothing to measure a return against: a percentage on the
  # leftovers of a sold position would only be noise.
  @min_capital 1.0

  @doc """
  `snapshots` oldest first, and `history` from `Positions.history/3`:

      %{months: ["2026-01", ...],
        rows: [%{key, asset, months: %{"2026-01" => 12.5}, bases: %{"2026-01" => 1000.0}}]}
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

      %{months, total: row, rows: [row]}

  where a row is `%{asset, months, total, pcts, pct}`: euros per month and for
  the year, then the same as returns in percent, `nil` where no capital was at work.
  """
  def for_year(%{months: months, rows: rows}, year) do
    shown = Enum.filter(months, &String.starts_with?(&1, year))

    kept = Enum.map(rows, &year_row(&1.asset, Map.take(&1.months, shown), Map.take(&1.bases, shown)))

    %{
      months: shown,
      total: year_row("Total earnings", sum_by_month(rows, :months, shown), sum_by_month(rows, :bases, shown)),
      rows: kept |> Enum.reject(&idle?/1) |> Enum.sort_by(& &1.total, :desc)
    }
  end

  @doc "The years covered, newest first."
  def years(%{months: months}) do
    months |> Enum.map(&String.slice(&1, 0, 4)) |> Enum.uniq() |> Enum.sort(:desc)
  end

  defp sum_by_month(rows, field, shown) do
    Map.new(shown, fn month ->
      {month, Enum.reduce(rows, 0.0, &(Map.get(Map.fetch!(&1, field), month, 0.0) + &2))}
    end)
  end

  defp year_row(asset, months, bases) do
    pcts = Map.new(months, fn {month, earned} -> {month, return(earned, Map.get(bases, month, 0.0))} end)

    %{asset: asset, months: months, total: months |> Map.values() |> Enum.sum(), pcts: pcts, pct: compound(pcts)}
  end

  defp idle?(row), do: abs(row.total) < 0.005 and Enum.all?(Map.values(row.months), &(abs(&1) < 0.005))

  defp return(earned, base) when base > @min_capital, do: earned / base * 100
  defp return(_earned, _base), do: nil

  defp compound(pcts) do
    case pcts |> Map.values() |> Enum.reject(&is_nil/1) do
      [] -> nil
      returns -> (Enum.reduce(returns, 1.0, &(&2 * (1 + &1 / 100))) - 1) * 100
    end
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
      gain = unrealized(asset, prices[isin])
      add(acc, isin, asset.asset, asset.realized + gain, value(asset, gain), asset.total_bought)
    end)
  end

  defp value(%{net_qty: units}, _unrealized) when units <= 0, do: 0.0
  defp value(%{cost_basis: cost}, unrealized), do: cost + unrealized

  defp unrealized(%{net_qty: units}, _price) when units <= 0, do: 0.0
  defp unrealized(_asset, nil), do: 0.0
  defp unrealized(%{net_qty: units, cost_basis: cost}, price), do: units * price - cost

  defp add_unreplayed(gains, doc, replayed) do
    doc
    |> positions()
    |> Enum.reject(&MapSet.member?(replayed, &1["isin"]))
    |> Enum.filter(&is_number(&1["value"]))
    |> Enum.reduce(gains, fn position, acc ->
      invested = position["invested"] || 0.0
      add(acc, position["isin"], position["asset"], position["value"] - invested, position["value"], invested)
    end)
  end

  defp add_dividends(gains, dividends, date) do
    dividends
    |> Enum.filter(&(&1["date"] <= date))
    |> Enum.reduce(gains, &add(&2, &1["isin"], &1["asset"], &1["amount"]))
  end

  defp add_ledgers(gains, ledgers, date) do
    Enum.reduce(ledgers, gains, fn {label, state_at}, acc ->
      {outstanding, earnings} = state_at.(date)
      add(acc, label, label, earnings, outstanding, outstanding)
    end)
  end

  defp add(gains, key, asset, amount, value \\ 0.0, bought \\ 0.0) do
    entry = %{asset: asset, gain: amount, value: value, bought: bought}
    Map.update(gains, key, entry, &%{&1 | gain: &1.gain + amount, value: &1.value + value, bought: &1.bought + bought})
  end

  # `[{month, key, asset, earned, capital}]`, each checkpoint against the one before.
  defp monthly(gains) do
    gains
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [{_before, was}, {date, now}] -> differences(month_of(date), was, now) end)
  end

  defp differences(month, was, now) do
    for key <- Enum.uniq(Map.keys(was) ++ Map.keys(now)) do
      asset = (now[key] || was[key]).asset
      {month, key, asset, field(now[key], :gain) - field(was[key], :gain), capital(was[key], now[key])}
    end
  end

  defp capital(was, now), do: field(was, :value) + max(field(now, :bought) - field(was, :bought), 0.0)

  defp field(nil, _name), do: 0.0
  defp field(entry, name), do: Map.fetch!(entry, name)

  defp rows(monthly) do
    monthly
    |> Enum.group_by(fn {_month, key, _asset, _earned, _capital} -> key end)
    |> Enum.map(fn {key, entries} ->
      %{
        key: key,
        asset: entries |> List.last() |> elem(2),
        months: Map.new(entries, fn {month, _key, _asset, earned, _capital} -> {month, earned} end),
        bases: Map.new(entries, fn {month, _key, _asset, _earned, capital} -> {month, capital} end)
      }
    end)
  end
end
