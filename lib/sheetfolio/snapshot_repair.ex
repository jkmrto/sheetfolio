defmodule Sheetfolio.SnapshotRepair do
  @moduledoc """
  Fills the snapshot positions a late confirmation email left short.

  MyInvestor confirms an order days after it is placed, so `SnapshotRecorder`
  writes snapshots that miss the purchase until the email lands: units and
  value understate the holding for the days in between, and the step the
  arriving email then makes reads as money in on any comparison window spanning
  it — dated at the window, not at the operation. The recorder runs this over
  the recent snapshots after each recording; `scripts/repair_confirmation_lag.exs`
  runs it over the whole history.

  Only positions the replay knows to be larger than the snapshot recorded are
  touched. A holding the operation history can't account for (early buys
  missing from Gmail, an exchange balance) is left exactly as it is, and so is
  a position the snapshot doesn't carry at all, which has no unit price of its
  own to rebuild the value from. Each position keeps the price its snapshot
  recorded, so the quote of the day survives, and only the cost of the late
  purchases is added to its basis — the recorded basis carries the FX of the
  day and corrections of its own that a wholesale restate would step over.
  """

  alias Sheetfolio.Positions

  @collection "portfolio_snapshots"

  @doc """
  Restates every snapshot short of what the operations say it held, and returns
  one `%{date, isin, from, to}` per position filled.

  Options: `:since` limits the sweep to snapshots on or after a date, and
  `:dry_run` reports the changes without writing them.
  """
  def repair(operations, {eur_usd, eur_cad}, opts \\ []) do
    states = Positions.history(operations, eur_usd, eur_cad)
    dry_run? = Keyword.get(opts, :dry_run, false)

    :mongo
    |> Mongo.find(@collection, since_query(Keyword.get(opts, :since)), sort: %{date: 1})
    |> Enum.flat_map(&repair_doc(&1, states, dry_run?))
  end

  defp since_query(nil), do: %{}
  defp since_query(date), do: %{date: %{"$gte" => Date.to_iso8601(date)}}

  defp repair_doc(doc, states, dry_run?) do
    date = Date.from_iso8601!(doc["date"])
    assets = state_at(states, date)
    positions = Enum.map(doc["positions"] || [], &restate(&1, Map.get(assets, &1["isin"]), states, date))

    case changes(doc, positions) do
      [] ->
        []

      changes ->
        unless dry_run?, do: write(doc["date"], positions)
        changes
    end
  end

  defp restate(position, asset, states, date) when is_map(asset) do
    if short?(position, asset), do: fill(position, asset, states, date), else: position
  end

  defp restate(position, _asset, _states, _date), do: position

  defp short?(%{"units" => units}, asset) when is_number(units), do: asset.net_qty - units > 0.0005
  defp short?(_position, _asset), do: false

  # The cost of the purchases the snapshot hadn't seen is what the replay had
  # accumulated by its date less what it held back when it stood at the units
  # the snapshot recorded. Without that anchor there is nothing to add, so the
  # position is left alone.
  defp fill(position, asset, states, date) do
    case basis_at_units(states, position["isin"], position["units"], date) do
      nil ->
        position

      basis ->
        position
        |> Map.put("units", asset.net_qty)
        |> Map.put("invested", Float.round(position["invested"] + asset.cost_basis - basis, 2))
        |> Map.put("value", revalue(position, asset))
    end
  end

  defp basis_at_units(states, isin, units, date) do
    states
    |> up_to(date)
    |> Enum.reverse()
    |> Enum.find_value(fn {_fecha, assets} -> basis_of(Map.get(assets, isin), units) end)
  end

  defp basis_of(%{net_qty: qty, cost_basis: basis}, units) when abs(qty - units) < 0.0005, do: basis
  defp basis_of(_asset, _units), do: nil

  defp revalue(%{"value" => value, "units" => units}, asset) when is_number(value) and units > 0 do
    Float.round(asset.net_qty * (value / units), 2)
  end

  defp revalue(position, _asset), do: position["value"]

  defp changes(doc, positions) do
    doc["positions"]
    |> Enum.zip(positions)
    |> Enum.reject(fn {before, now} -> before == now end)
    |> Enum.map(fn {before, now} -> %{date: doc["date"], isin: before["isin"], from: before, to: now} end)
  end

  defp write(date, positions) do
    valued = Enum.filter(positions, &(&1["value"] && &1["isin"] != "URBANITAE"))

    {:ok, _} =
      Mongo.update_one(:mongo, @collection, %{date: date}, %{
        "$set" => %{
          positions: positions,
          total_invested: valued |> Enum.reduce(0.0, &(&1["invested"] + &2)) |> Float.round(2),
          total_value: valued |> Enum.reduce(0.0, &(&1["value"] + &2)) |> Float.round(2)
        }
      })
  end

  defp state_at(states, date) do
    case states |> up_to(date) |> List.last() do
      nil -> %{}
      {_fecha, assets} -> assets
    end
  end

  defp up_to(states, date) do
    Enum.take_while(states, fn {fecha, _assets} -> Date.compare(parse_fecha(fecha), date) != :gt end)
  end

  defp parse_fecha(fecha) do
    [day, month, year] = String.split(fecha, "/")
    Date.from_iso8601!("#{year}-#{month}-#{day}")
  end
end
