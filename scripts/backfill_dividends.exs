defmodule BackfillDividends do
  @moduledoc """
  Seeds the `dividends` collection from the MyInvestor cuenta corriente CSV
  export ("Movimientos Mi Cuenta"), covering 30/01/2026 to 31/07/2026.

  Distributions show up there as a positive amount under the security's name.
  Sale proceeds look identical, so every candidate was checked against the
  Gmail operation history first: the 1.952,99 € credited on 08/05/2026 is the
  VENTA of 27 units at 72,42 and is deliberately not listed here. The 5,21 €
  credited on 11/03/2026 as "STRIVE INC-A @ 1" matches no operation and is left
  out pending an explanation.

  Amounts are net, as credited (MyInvestor withholds before paying).

  Dry-run by default — prints what would be inserted vs. skipped and stops.
  Pass `--commit` to actually write.

      set -a && . ./.env && set +a && mix run scripts/backfill_dividends.exs
      set -a && . ./.env && set +a && mix run scripts/backfill_dividends.exs --commit
  """

  alias Sheetfolio.Dividends

  @isin "IE00BF8HV600"
  @asset "ETF PIMCO SHORT TERM HIGH YIELD"
  @concepto "ETF PIMCO SHORT TERM HIGH YIEL"

  @rows [
    {"2026-01-30", 40.77},
    {"2026-02-27", 50.80},
    {"2026-03-31", 65.92},
    {"2026-04-30", 64.06},
    {"2026-05-29", 85.96},
    {"2026-06-30", 75.09},
    {"2026-07-31", 71.72}
  ]

  def run(args) do
    commit? = "--commit" in args
    now = DateTime.utc_now()

    {new, dupes} =
      @rows
      |> Enum.map(&build_doc(&1, now))
      |> Enum.split_with(&(Dividends.find_matching(&1) == nil))

    IO.puts("== Dividends ==")
    Enum.each(new, &print_row("+", &1))
    Enum.each(dupes, &print_row("=", &1))

    IO.puts("\n#{length(new)} new, #{length(dupes)} already recorded")
    IO.puts("New total: #{fmt(Enum.reduce(new, 0.0, &(&1.amount + &2)))} €")

    if commit?, do: commit(new), else: IO.puts("\nDry run — pass --commit to write.")
  end

  defp commit(new) do
    :ok = Dividends.insert_many(new)
    all = Dividends.all()
    IO.puts("\nInserted #{length(new)}. Collection now has #{length(all)} docs")
    IO.puts("totalling #{fmt(Dividends.total(all))} €.")
  end

  defp build_doc({date, amount}, now) do
    %{
      date: date,
      isin: @isin,
      asset: @asset,
      amount: amount,
      currency: "EUR",
      raw_concepto: @concepto,
      captured_at: now
    }
  end

  defp print_row(marker, doc) do
    IO.puts("#{marker} #{doc.date}  #{String.pad_trailing(doc.asset, 34)}#{String.pad_leading(fmt(doc.amount), 8)} €")
  end

  defp fmt(amount), do: :erlang.float_to_binary(amount * 1.0, decimals: 2)
end

BackfillDividends.run(System.argv())
