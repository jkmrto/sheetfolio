defmodule BackfillTraspasoBasis do
  @moduledoc """
  Rewrites each snapshot's cost basis and cumulative realized P&L after
  traspasos stopped being treated as sales.

  A traspaso now carries its cost basis to the destination fund instead of
  realizing a gain, so both figures move: `total_realized` drops by whatever
  is still sitting in a fund that was never sold, and the destination's
  `invested` falls by the same amount.

  Only the difference the traspaso change makes is applied, never a wholesale
  re-derivation. Each snapshot's basis was recorded at the FX rate of its own
  day, and replaying the history now would silently restate every dollar and
  Canadian-dollar holding at today's rate. So the history is replayed twice
  over the same rates — once with the traspaso pairing and once without it —
  and only the delta between them is added to what is already stored.

  Each position's `value` is left alone; it holds the price the recorder saw
  that day, which can't be recovered now. So are positions with no operations
  behind them (Urbanitae).

  Run with: set -a && . ./.env && set +a && mix run scripts/backfill_traspaso_basis.exs
  Pass --dry-run to report what would change without writing.
  """

  @collection "portfolio_snapshots"

  def run(dry_run?) do
    operations = Sheetfolio.MyinvestorEmails.cached_operations() |> Sheetfolio.OperationHistory.patch()
    {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()

    IO.puts("#{length(operations)} operations")

    # Dropping traspaso_to is what the accounting keyed off before, so the same
    # operations replay exactly as they used to.
    was = Sheetfolio.Positions.history(Enum.map(operations, &Map.delete(&1, :traspaso_to)), eur_usd, eur_cad)
    now = Sheetfolio.Positions.history(operations, eur_usd, eur_cad)

    docs = Mongo.find(:mongo, @collection, %{}, sort: %{date: 1}) |> Enum.to_list()
    IO.puts("#{length(docs)} snapshots\n")

    changed = docs |> Enum.map(&rewrite(&1, was, now, dry_run?)) |> Enum.count(& &1)

    IO.puts(if dry_run?, do: "\nWould update #{changed} snapshots.", else: "\nUpdated #{changed} snapshots.")
  end

  defp rewrite(doc, was, now, dry_run?) do
    date = Date.from_iso8601!(doc["date"])
    before = state_at(was, date)
    after_ = state_at(now, date)

    positions = Enum.map(doc["positions"] || [], &reprice(&1, before, after_))

    realized =
      Float.round(doc["total_realized"] + total_realized(after_) - total_realized(before), 2)

    valued = Enum.filter(positions, &(&1["value"] && &1["isin"] != "URBANITAE"))
    invested = valued |> Enum.reduce(0.0, &(&1["invested"] + &2)) |> Float.round(2)

    if changed?(doc, positions, invested, realized) do
      report(doc, invested, realized)
      unless dry_run?, do: write(doc["date"], positions, invested, realized)
      true
    else
      false
    end
  end

  defp total_realized(assets) do
    assets |> Map.values() |> Enum.reduce(0.0, &(&1.realized + &2))
  end

  defp changed?(doc, positions, invested, realized) do
    doc["total_invested"] != invested or doc["total_realized"] != realized or
      positions != doc["positions"]
  end

  # Shift the stored basis by what the traspaso change moved, leaving the rate
  # it was originally recorded at intact. Urbanitae has no operations behind
  # it, so it keeps whatever it was given.
  defp reprice(position, before, after_) do
    delta = cost_basis(after_, position["isin"]) - cost_basis(before, position["isin"])

    case Map.has_key?(after_, position["isin"]) and delta != 0.0 do
      true -> Map.put(position, "invested", Float.round(position["invested"] + delta, 2))
      false -> position
    end
  end

  defp cost_basis(assets, isin) do
    case Map.get(assets, isin) do
      nil -> 0.0
      asset -> asset.cost_basis
    end
  end

  defp report(doc, invested, realized) do
    if :erlang.phash2(doc["date"]) |> rem(90) == 0 do
      IO.puts(
        "  #{doc["date"]}  invested #{doc["total_invested"]} -> #{invested}" <>
          "   realized #{doc["total_realized"]} -> #{realized}"
      )
    end
  end

  defp write(date, positions, invested, realized) do
    {:ok, _} =
      Mongo.update_one(:mongo, @collection, %{date: date}, %{
        "$set" => %{positions: positions, total_invested: invested, total_realized: realized}
      })
  end

  defp state_at(states, date) do
    states
    |> Enum.take_while(fn {fecha, _assets} -> Date.compare(parse_fecha(fecha), date) != :gt end)
    |> List.last()
    |> case do
      nil -> %{}
      {_fecha, assets} -> assets
    end
  end

  defp parse_fecha(fecha) do
    [d, m, y] = String.split(fecha, "/")
    Date.from_iso8601!("#{y}-#{m}-#{d}")
  end
end

BackfillTraspasoBasis.run("--dry-run" in System.argv())
