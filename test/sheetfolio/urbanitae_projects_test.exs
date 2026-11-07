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
