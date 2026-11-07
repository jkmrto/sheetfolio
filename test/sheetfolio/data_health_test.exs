defmodule Sheetfolio.DataHealthTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.DataHealth

  @now ~U[2026-11-07 12:00:00Z]

  defp job(success, failure \\ nil, error \\ nil) do
    %{"last_success_at" => success, "last_failure_at" => failure, "last_error" => error}
  end

  defp healthy do
    %{
      snapshot: %{date: ~D[2026-11-07], stale_positions: 0},
      cash: %{date: ~D[2026-11-07], wise_stale: false},
      jobs: %{
        "myinvestor_emails" => job(~U[2026-11-07 09:00:00Z]),
        "urbanitae_emails" => job(~U[2026-11-06 23:00:00Z]),
        "equito_emails" => job(~U[2026-11-07 09:00:00Z])
      },
      equito_last: ~D[2026-11-01],
      dividends_last: ~D[2026-10-30],
      urbanitae_last: ~D[2026-10-26],
      urbanitae_pending: 0,
      forecast_as_of: ~D[2026-11-07],
      forecasts_past_due: 0
    }
  end

  defp row(rows, label), do: Enum.find(rows, &(&1.label == label))

  test "fresh data is all clear" do
    rows = DataHealth.evaluate(healthy(), @now)

    assert Enum.all?(rows, &(&1.status == :ok))
    assert DataHealth.worst(rows) == :ok
  end

  test "a missed daily snapshot warns, then goes overdue" do
    two_days = %{healthy() | snapshot: %{date: ~D[2026-11-05], stale_positions: 0}}
    three_days = %{healthy() | snapshot: %{date: ~D[2026-11-04], stale_positions: 0}}

    assert row(DataHealth.evaluate(two_days, @now), "Portfolio snapshot").status == :warning
    assert row(DataHealth.evaluate(three_days, @now), "Portfolio snapshot").status == :overdue
  end

  test "manual sources get a longer leash" do
    facts = %{healthy() | dividends_last: ~D[2026-09-20]}
    assert row(DataHealth.evaluate(facts, @now), "Dividends").status == :warning

    facts = %{healthy() | dividends_last: ~D[2026-08-20]}
    assert row(DataHealth.evaluate(facts, @now), "Dividends").status == :overdue
  end

  test "a sync whose latest run failed is overdue and says why" do
    jobs =
      Map.put(healthy().jobs, "equito_emails", job(~U[2026-11-06 09:00:00Z], ~U[2026-11-07 09:00:00Z], "timeout"))

    equito = row(DataHealth.evaluate(%{healthy() | jobs: jobs}, @now), "Equito emails")

    assert equito.status == :overdue
    assert equito.detail == "Last run failed: timeout"
  end

  test "a failure followed by a success is cleared" do
    jobs =
      Map.put(healthy().jobs, "equito_emails", job(~U[2026-11-07 09:00:00Z], ~U[2026-11-06 09:00:00Z], "timeout"))

    assert row(DataHealth.evaluate(%{healthy() | jobs: jobs}, @now), "Equito emails").status == :ok
  end

  test "a sync that has never reported only warns" do
    jobs = Map.delete(healthy().jobs, "urbanitae_emails")

    assert row(DataHealth.evaluate(%{healthy() | jobs: jobs}, @now), "Urbanitae emails").status == :warning
  end

  test "fresh data with a known problem still asks for attention" do
    facts = %{
      healthy()
      | snapshot: %{date: ~D[2026-11-07], stale_positions: 2},
        cash: %{date: ~D[2026-11-07], wise_stale: true},
        urbanitae_pending: 1,
        forecasts_past_due: 3
    }

    rows = DataHealth.evaluate(facts, @now)

    assert row(rows, "Portfolio snapshot").detail == "2 positions on an old price"
    assert row(rows, "Cash snapshot").status == :warning
    assert row(rows, "Urbanitae movements").detail == "1 movement in emails not recorded yet"
    assert row(rows, "Urbanitae payout forecasts").detail == "3 expected payouts past due"
  end

  test "a source with no data is overdue" do
    assert row(DataHealth.evaluate(%{healthy() | dividends_last: nil}, @now), "Dividends").status == :overdue
  end

  test "a recent login block appears, then fades after a week" do
    recent = Map.put(healthy().jobs, "login", %{"last_failure_at" => ~U[2026-11-05 09:00:00Z]})
    old = Map.put(healthy().jobs, "login", %{"last_failure_at" => ~U[2026-10-20 09:00:00Z]})

    assert row(DataHealth.evaluate(%{healthy() | jobs: recent}, @now), "Login").status == :warning
    assert row(DataHealth.evaluate(%{healthy() | jobs: old}, @now), "Login") == nil
  end

  test "the worst status wins" do
    assert DataHealth.worst([%{status: :ok}, %{status: :warning}]) == :warning
    assert DataHealth.worst([%{status: :warning}, %{status: :overdue}]) == :overdue
  end
end
