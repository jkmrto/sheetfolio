defmodule Sheetfolio.DataHealth do
  @moduledoc """
  Whether each data source is up to date. `report/0` gathers the facts and
  `evaluate/2` turns them into one row per source:

      %{label: "Dividends", kind: :manual, last: ~D[2026-10-30],
        status: :ok | :warning | :overdue, detail: nil | "..."}

  Thresholds are in days, and follow how often each source really changes: a
  snapshot runs daily, Equito pays monthly, and dividends and Urbanitae figures
  only move when someone imports them.
  """

  alias Sheetfolio.{JobRuns, UrbanitaePending, UrbanitaeProjects, UrbanitaeTransactions}

  @login_window_days 7

  def report(now \\ DateTime.utc_now()), do: evaluate(facts(now), now)

  @doc "The worst status in a report."
  def worst(rows) do
    statuses = Enum.map(rows, & &1.status)

    cond do
      :overdue in statuses -> :overdue
      :warning in statuses -> :warning
      true -> :ok
    end
  end

  def evaluate(facts, now) do
    today = DateTime.to_date(now)

    [
      snapshot_row(facts.snapshot, today),
      cash_row(facts.cash, today),
      job_row("MyInvestor emails", facts.jobs["myinvestor_emails"], today),
      job_row("FX rates", facts.jobs["historical_fx"], today),
      holdings_row(facts.jobs["holdings_check"], today),
      job_row("Urbanitae emails", facts.jobs["urbanitae_emails"], today),
      job_row("Equito emails", facts.jobs["equito_emails"], today),
      dated_row("Equito rent", :automatic, facts.equito_last, today, 35, 45),
      dated_row("Dividends", :manual, facts.dividends_last, today, 40, 70),
      urbanitae_row(facts.urbanitae_last, facts.urbanitae_pending, today),
      forecast_row(facts.forecast_as_of, facts.forecasts_past_due, today),
      login_row(facts.jobs["login"], now)
    ]
    |> List.flatten()
  end

  defp snapshot_row(%{date: date, stale_positions: stale}, today) do
    "Portfolio snapshot"
    |> dated_row(:automatic, date, today, 1, 2)
    |> flag(stale > 0, "#{stale} #{plural(stale, "position")} on an old price")
  end

  defp cash_row(%{date: date, wise_stale: wise_stale}, today) do
    "Cash snapshot"
    |> dated_row(:automatic, date, today, 1, 2)
    |> flag(wise_stale, "Wise balance couldn't be fetched")
  end

  defp urbanitae_row(last, pending, today) do
    "Urbanitae movements"
    |> dated_row(:manual, last, today, 100, 200)
    |> flag(pending > 0, "#{pending} #{plural(pending, "movement")} in emails not recorded yet")
  end

  defp forecast_row(as_of, past_due, today) do
    "Urbanitae payout forecasts"
    |> dated_row(:manual, as_of, today, 35, 62)
    |> flag(past_due > 0, "#{past_due} expected #{plural(past_due, "payout")} past due")
  end

  # A sync's verdict is its latest run, so a failure counts until a later
  # success replaces it.
  defp job_row(label, nil, _today) do
    %{label: label, kind: :automatic, last: nil, status: :warning, detail: "No run recorded yet"}
  end

  defp job_row(label, job, today) do
    success = job["last_success_at"]
    row = dated_row(label, :automatic, success && DateTime.to_date(success), today, 1, 2)

    if failed_last?(success, job["last_failure_at"]) do
      %{row | status: :overdue, detail: "Last run failed: #{job["last_error"]}"}
    else
      row
    end
  end

  # Disagreeing with the sheet isn't a broken sync: it wants a look, and it stays
  # until the history or the sheet is corrected.
  defp holdings_row(job, today) do
    case job_row("Holdings vs sheet", job, today) do
      %{detail: "Last run failed: " <> finding} = row -> %{row | status: :warning, detail: finding}
      row -> row
    end
  end

  defp failed_last?(_success, nil), do: false
  defp failed_last?(nil, _failure), do: true
  defp failed_last?(success, failure), do: DateTime.compare(failure, success) == :gt

  # Only a problem worth a row: quiet logins would just be noise.
  defp login_row(nil, _now), do: []

  defp login_row(%{"last_failure_at" => blocked_at}, now) do
    if DateTime.diff(now, blocked_at, :day) < @login_window_days do
      [
        %{
          label: "Login",
          kind: :automatic,
          last: DateTime.to_date(blocked_at),
          status: :warning,
          detail: "Blocked after too many wrong passwords"
        }
      ]
    else
      []
    end
  end

  defp dated_row(label, kind, nil, _today, _warn_after, _overdue_after) do
    %{label: label, kind: kind, last: nil, status: :overdue, detail: "No data yet"}
  end

  defp dated_row(label, kind, last, today, warn_after, overdue_after) do
    age = Date.diff(today, last)

    %{
      label: label,
      kind: kind,
      last: last,
      status: age_status(age, warn_after, overdue_after),
      detail: nil
    }
  end

  defp age_status(age, _warn_after, overdue_after) when age > overdue_after, do: :overdue
  defp age_status(age, warn_after, _overdue_after) when age > warn_after, do: :warning
  defp age_status(_age, _warn_after, _overdue_after), do: :ok

  # Something wrong with fresh data still needs attention, but never hides a
  # source that is overdue outright.
  defp flag(row, false, _detail), do: row
  defp flag(%{status: :overdue} = row, true, detail), do: %{row | detail: detail}
  defp flag(row, true, detail), do: %{row | status: :warning, detail: detail}

  defp plural(1, word), do: word
  defp plural(_count, word), do: word <> "s"

  defp facts(now) do
    today = DateTime.to_date(now)
    latest_snapshot = latest("portfolio_snapshots")
    latest_cash = latest("cash_snapshots")

    %{
      snapshot: %{date: doc_date(latest_snapshot), stale_positions: stale_positions(latest_snapshot)},
      cash: %{date: doc_date(latest_cash), wise_stale: (latest_cash || %{})["wise_stale"] == true},
      jobs: JobRuns.all(),
      equito_last: doc_date(latest("equito_transactions")),
      dividends_last: doc_date(latest("dividends")),
      urbanitae_last: doc_date(latest("urbanitae_transactions")),
      urbanitae_pending: length(UrbanitaePending.list()),
      forecast_as_of: forecast_as_of(),
      forecasts_past_due: forecasts_past_due(today)
    }
  end

  defp latest(collection), do: Mongo.find_one(:mongo, collection, %{}, sort: %{date: -1})

  defp doc_date(%{"date" => <<iso::binary-size(10), _rest::binary>>}), do: Date.from_iso8601!(iso)
  defp doc_date(_doc), do: nil

  defp stale_positions(nil), do: 0

  defp stale_positions(doc) do
    doc |> Map.get("positions", []) |> Enum.count(&(&1["stale_price"] == true))
  end

  defp forecast_as_of do
    case UrbanitaeProjects.forecasts() |> Enum.map(& &1["forecast"]["as_of"]) |> Enum.max(fn -> nil end) do
      nil -> nil
      iso -> Date.from_iso8601!(iso)
    end
  end

  defp forecasts_past_due(today) do
    active =
      UrbanitaeTransactions.all()
      |> UrbanitaeTransactions.rollup_by_project()
      |> Enum.filter(&(&1.status == "active"))
      |> MapSet.new(& &1.project_key)

    UrbanitaeProjects.forecasts()
    |> Enum.filter(&MapSet.member?(active, &1["project_key"]))
    |> Enum.count(&(Date.compare(Date.from_iso8601!(&1["forecast"]["close_date"]), today) == :lt))
  end
end
