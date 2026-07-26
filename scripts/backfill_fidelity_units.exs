defmodule BackfillFidelityUnits do
  @moduledoc """
  Restates the Fidelity S&P 500 position in every snapshot that holds it.

  Two corrections land on the same fund. The traspaso from Vanguard was
  overridden to 21,233.76 EUR to paper over a cost basis the accounting used
  to lose; the email says 20,233.76 and the override is gone now that a
  traspaso carries its basis properly. And the weekly subscriptions missing
  from the December 2025 email gaps are recorded, adding 70.547 units.

  Units and cost basis are re-derived from the operations, which is safe here
  because the fund is priced in EUR and no FX rate enters its history. Each
  snapshot's value is rebuilt from its own recorded unit price, so the price
  the recorder saw that day survives.

  Run with: set -a && . ./.env && set +a && mix run scripts/backfill_fidelity_units.exs
  Pass --dry-run to report what would change without writing.
  """

  @collection "portfolio_snapshots"
  @isin "IE00BYX5MX67"

  def run(dry_run?) do
    operations = Sheetfolio.MyinvestorEmails.cached_operations() |> Sheetfolio.OperationHistory.patch()
    states = Sheetfolio.Positions.history(operations, 1.0, 1.0)

    docs = Mongo.find(:mongo, @collection, %{}, sort: %{date: 1}) |> Enum.to_list()
    holding = Enum.filter(docs, fn d -> Enum.any?(d["positions"] || [], &(&1["isin"] == @isin)) end)

    IO.puts("#{length(holding)} of #{length(docs)} snapshots hold #{@isin}\n")

    changed = holding |> Enum.map(&rewrite(&1, states, dry_run?)) |> Enum.count(& &1)

    IO.puts(if dry_run?, do: "\nWould update #{changed} snapshots.", else: "\nUpdated #{changed} snapshots.")
  end

  defp rewrite(doc, states, dry_run?) do
    asset = states |> state_at(Date.from_iso8601!(doc["date"])) |> Map.get(@isin)
    current = Enum.find(doc["positions"], &(&1["isin"] == @isin))

    case restate(current, asset) do
      nil ->
        false

      updated ->
        positions = Enum.map(doc["positions"], &if(&1["isin"] == @isin, do: updated, else: &1))
        report(doc, current, updated)
        unless dry_run?, do: write(doc["date"], positions)
        true
    end
  end

  # Keeps the day's price by carrying the value per unit across, so only the
  # unit count and the basis move.
  defp restate(current, asset) when is_map(current) and is_map(asset) do
    updated =
      current
      |> Map.put("units", asset.net_qty)
      |> Map.put("invested", Float.round(asset.cost_basis, 2))
      |> Map.put("value", revalue(current, asset))

    if updated == current, do: nil, else: updated
  end

  defp restate(_current, _asset), do: nil

  defp revalue(%{"value" => value, "units" => units}, asset) when is_number(value) and units > 0 do
    Float.round(asset.net_qty * (value / units), 2)
  end

  defp revalue(current, _asset), do: current["value"]

  defp report(doc, current, updated) do
    if :erlang.phash2(doc["date"]) |> rem(50) == 0 do
      IO.puts(
        "  #{doc["date"]}  units #{Float.round(current["units"], 3)} -> #{Float.round(updated["units"], 3)}" <>
          "   invested #{current["invested"]} -> #{updated["invested"]}" <>
          "   value #{current["value"]} -> #{updated["value"]}"
      )
    end
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

BackfillFidelityUnits.run("--dry-run" in System.argv())
