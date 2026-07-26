defmodule BackfillPensionSnapshots do
  @moduledoc """
  Adds the MyInvestor pension plan (DGS N5396) to the snapshots recorded before
  it was tracked, and recomputes their totals.

  The plan has been held since 05/11/2024, but nothing searched for its
  contribution emails until now, so every snapshot but the newest is missing
  it — which shows up as a step in the Indexados line on the day tracking
  started rather than as the holding it always was.

  Units come from replaying the contributions, the price from the plan's NAV
  history, carried forward over days it didn't publish one.

  Run with: set -a && . ./.env && set +a && mix run scripts/backfill_pension_snapshots.exs
  Pass --dry-run to report what would change without writing.
  """

  @collection "portfolio_snapshots"
  @isin "N5396"
  @ticker "0P0001LIG7.F"

  def run(dry_run?) do
    operations =
      Sheetfolio.MyinvestorEmails.cached_operations()
      |> Sheetfolio.OperationHistory.patch()
      |> Enum.filter(&(&1.isin == @isin))

    IO.puts("#{length(operations)} contributions found")

    # The plan reports in EUR, so the FX rates never come into play.
    states = Sheetfolio.Positions.history(operations, 1.0, 1.0)

    docs = Mongo.find(:mongo, @collection, %{}, sort: %{date: 1}) |> Enum.to_list()
    [first | _] = docs
    last = List.last(docs)

    {:ok, navs, "EUR"} =
      Sheetfolio.PricesApi.YahooFinance.fetch_series(
        @ticker,
        Date.from_iso8601!(first["date"]),
        Date.from_iso8601!(last["date"])
      )

    IO.puts("#{map_size(navs)} NAV points, #{length(docs)} snapshots")

    updated = docs |> Enum.map(&backfill(&1, states, navs, dry_run?)) |> Enum.count(& &1)

    IO.puts(if dry_run?, do: "\nWould update #{updated} snapshots.", else: "\nUpdated #{updated} snapshots.")
  end

  # Snapshots recorded after tracking started already hold the position, and
  # rewriting them from a daily NAV would only lose the intraday price the
  # recorder actually used.
  defp backfill(doc, states, navs, dry_run?) do
    if Enum.any?(doc["positions"] || [], &(&1["isin"] == @isin)),
      do: false,
      else: apply_position(doc, states, navs, dry_run?)
  end

  defp apply_position(doc, states, navs, dry_run?) do
    date = Date.from_iso8601!(doc["date"])

    case position_at(states, navs, date) do
      nil ->
        false

      position ->
        positions = (doc["positions"] || []) ++ [position]
        report(doc, position)
        unless dry_run?, do: write(doc["date"], positions)
        true
    end
  end

  # Every 60th day, so a long run stays readable but still shows the shape.
  defp report(doc, position) do
    if :erlang.phash2(doc["date"]) |> rem(60) == 0 or doc["date"] <= "2025-01-05" do
      IO.puts(
        "  #{doc["date"]}  units #{Float.round(position["units"], 3)}" <>
          "  invested #{position["invested"]}  value #{position["value"]}" <>
          "  (total_value #{doc["total_value"]} -> #{Float.round(doc["total_value"] + position["value"], 2)})"
      )
    end
  end

  defp write(date, positions) do
    # Urbanitae is charted as its own line; totals track only market positions.
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

  defp position_at(states, navs, date) do
    with %{net_qty: units, cost_basis: cost, asset: asset} when units > 0.001 <-
           state_at(states, date),
         nav when not is_nil(nav) <- nav_at(navs, date) do
      %{
        "isin" => @isin,
        "asset" => asset,
        "units" => units,
        "invested" => Float.round(cost, 2),
        "value" => Float.round(units * nav, 2),
        "stale_price" => false
      }
    else
      _ -> nil
    end
  end

  # Latest contribution state on or before the date; nothing before the first.
  defp state_at(states, date) do
    states
    |> Enum.take_while(fn {fecha, _assets} ->
      Date.compare(parse_fecha(fecha), date) != :gt
    end)
    |> List.last()
    |> case do
      nil -> nil
      {_fecha, assets} -> Map.get(assets, @isin)
    end
  end

  # Yahoo publishes a NAV only on days the plan priced, so a weekend or a
  # holiday takes the most recent one before it. The first two snapshots fall on
  # the New Year holiday, before the series starts at all — those take the
  # earliest NAV rather than being left without a value, which would notch the
  # line at the very edge of the chart.
  defp nav_at(navs, date) do
    navs
    |> Enum.filter(fn {nav_date, _nav} -> Date.compare(nav_date, date) != :gt end)
    |> Enum.max_by(fn {nav_date, _nav} -> Date.to_erl(nav_date) end, fn -> nil end)
    |> case do
      nil -> earliest_nav(navs)
      {_nav_date, nav} -> nav
    end
  end

  defp earliest_nav(navs) do
    navs
    |> Enum.min_by(fn {nav_date, _nav} -> Date.to_erl(nav_date) end, fn -> nil end)
    |> case do
      nil -> nil
      {_nav_date, nav} -> nav
    end
  end

  defp parse_fecha(fecha) do
    [d, m, y] = String.split(fecha, "/")
    Date.from_iso8601!("#{y}-#{m}-#{d}")
  end
end

BackfillPensionSnapshots.run("--dry-run" in System.argv())
