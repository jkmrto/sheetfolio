defmodule Sheetfolio.UrbanitaeProjectsTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.UrbanitaeProjects, as: Projects

  describe "merge_forecast/2" do
    test "the first forecast starts from its own close date" do
      merged = Projects.merge_forecast(nil, %{"close_date" => "2027-04-15"})

      assert merged["first_close_date"] == "2027-04-15"
    end

    test "a first forecast can carry an earlier estimate" do
      forecast = %{"close_date" => "2027-04-15", "first_close_date" => "2026-04-21"}

      assert Projects.merge_forecast(nil, forecast)["first_close_date"] == "2026-04-21"
    end

    test "a refresh keeps the earliest estimate" do
      stored = %{"close_date" => "2027-04-15", "first_close_date" => "2026-04-21"}
      refresh = %{"close_date" => "2027-09-30", "first_close_date" => "2027-09-30"}

      merged = Projects.merge_forecast(stored, refresh)

      assert merged["close_date"] == "2027-09-30"
      assert merged["first_close_date"] == "2026-04-21"
    end
  end

  describe "monthly_payouts/2" do
    defp project(name, close_date, to_receive, extra \\ %{}) do
      forecast = Map.merge(%{"close_date" => close_date, "to_receive" => to_receive}, extra)
      %{"project" => name, "forecast" => forecast}
    end

    test "adds up projects paying in the same month" do
      projects = [project("A", "2026-11-21", 6610.0), project("B", "2026-11-02", 1165.0)]

      [row] = Projects.monthly_payouts(projects, ~D[2026-11-07])

      assert row.month == ~D[2026-11-01]
      assert row.amount == 7775.0
      assert length(row.projects) == 2
    end

    test "keeps the months with nothing due" do
      rows = Projects.monthly_payouts([project("A", "2027-01-15", 100.0)], ~D[2026-11-07])

      assert Enum.map(rows, & &1.amount) == [0.0, 0.0, 100.0]
      assert List.last(rows).month == ~D[2027-01-01]
    end

    test "spreads instalments and leaves the rest for the close, keeping the total" do
      recurring = %{"recurring_amount" => 81.25, "recurring_months" => [1, 4, 7, 10]}
      projects = [project("A", "2027-07-03", 1000.0, recurring)]

      rows = Projects.monthly_payouts(projects, ~D[2026-11-07])
      amounts = Map.new(rows, &{&1.month, &1.amount})

      assert amounts[~D[2027-01-01]] == 81.25
      assert amounts[~D[2027-04-01]] == 81.25
      assert amounts[~D[2027-07-01]] == 837.5
      assert rows |> Enum.map(& &1.amount) |> Enum.sum() == 1000.0
    end

    test "a payout past its date counts as due this month" do
      [row] = Projects.monthly_payouts([project("A", "2026-09-30", 100.0)], ~D[2026-11-07])

      assert row.month == ~D[2026-11-01]
      assert row.amount == 100.0
    end

    test "no projects gives just the current month, empty" do
      assert [%{amount: +0.0, projects: []}] = Projects.monthly_payouts([], ~D[2026-11-07])
    end
  end

  describe "delay_months/1" do
    test "counts calendar months, later is positive" do
      forecast = %{"close_date" => "2027-04-15", "first_close_date" => "2026-04-21"}

      assert Projects.delay_months(forecast) == 12
    end

    test "is negative when the payout moved earlier" do
      forecast = %{"close_date" => "2028-08-11", "first_close_date" => "2029-03-30"}

      assert Projects.delay_months(forecast) == -7
    end

    test "is zero within the same month" do
      forecast = %{"close_date" => "2027-05-14", "first_close_date" => "2027-05-27"}

      assert Projects.delay_months(forecast) == 0
    end
  end
end
