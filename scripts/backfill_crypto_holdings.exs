defmodule BackfillCryptoHoldings do
  @moduledoc """
  Seeds `crypto_holdings` from the Coinbase Saldo screen captured 2026-08-01:
  0,02018811 BTC at a reported average cost of 40.921,66 €/BTC.

  The cost basis is derived from those two figures rather than from the
  Transacciones list, which was filtered to 25/7/21 onwards and only accounted
  for 0.01563 BTC (788,08 €). The missing 0.00455811 BTC implies roughly
  8.348 €/BTC — a 2019/2020 purchase sitting before the filter's start date.

  Coinbase's own "rendimientos no realizados" of +269,53 € against a
  1.095,67 € balance corroborates the 826,13 € basis.

  Idempotent: upserts by {platform, symbol}.

      set -a && . ./.env && set +a && mix run scripts/backfill_crypto_holdings.exs
      set -a && . ./.env && set +a && mix run scripts/backfill_crypto_holdings.exs --commit
  """

  alias Sheetfolio.CryptoHoldings

  @units 0.02018811
  @avg_cost 40_921.66

  def run(args) do
    cost_basis = Float.round(@units * @avg_cost, 2)

    doc = %{
      platform: "Coinbase",
      symbol: "BTC",
      units: @units,
      cost_basis: cost_basis,
      avg_cost: @avg_cost
    }

    IO.puts("Coinbase BTC")
    IO.puts("  units      #{:erlang.float_to_binary(@units, decimals: 8)}")
    IO.puts("  avg cost   #{:erlang.float_to_binary(@avg_cost, decimals: 2)} €/BTC")
    IO.puts("  cost basis #{:erlang.float_to_binary(cost_basis, decimals: 2)} €")

    if "--commit" in args, do: commit(doc), else: IO.puts("\nDry run — pass --commit to write.")
  end

  defp commit(doc) do
    :ok = CryptoHoldings.upsert(doc)
    IO.puts("\nUpserted. Collection now holds #{length(CryptoHoldings.all())} position(s).")
  end
end

BackfillCryptoHoldings.run(System.argv())
