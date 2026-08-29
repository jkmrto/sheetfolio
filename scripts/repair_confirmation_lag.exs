defmodule RepairConfirmationLag do
  @moduledoc """
  Runs `Sheetfolio.SnapshotRepair` over the whole snapshot history.

  The recorder repairs the recent snapshots on its own after each recording;
  this is the one-off sweep for everything older than that window.

  Run with: set -a && . ./.env && set +a && mix run scripts/repair_confirmation_lag.exs
  Pass --dry-run to report what would change without writing.
  """

  alias Sheetfolio.PricesApi.YahooFinance
  alias Sheetfolio.SnapshotRepair

  def run(dry_run?) do
    operations = Sheetfolio.MyinvestorEmails.cached_operations() |> Sheetfolio.OperationHistory.patch()
    changes = SnapshotRepair.repair(operations, {fx("EURUSD=X"), fx("EURCAD=X")}, dry_run: dry_run?)

    Enum.each(changes, &report/1)
    dates = changes |> Enum.map(& &1.date) |> Enum.uniq() |> length()

    IO.puts(if dry_run?, do: "\nWould update #{dates} snapshots.", else: "\nUpdated #{dates} snapshots.")
  end

  defp report(%{date: date, isin: isin, from: before, to: now}) do
    IO.puts(
      "  #{date}  #{isin}  units #{Float.round(before["units"] * 1.0, 3)} -> #{Float.round(now["units"], 3)}" <>
        "   invested #{before["invested"]} -> #{now["invested"]}" <>
        "   value #{before["value"]} -> #{now["value"]}"
    )
  end

  defp fx(pair) do
    case YahooFinance.fetch_price(pair) do
      {:ok, rate, _currency} -> rate
      _unavailable -> 1.0
    end
  end
end

RepairConfirmationLag.run("--dry-run" in System.argv())
