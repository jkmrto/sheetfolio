defmodule Sheetfolio.RealEstateTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.RealEstate

  @equito [
    %{"date" => "2025-03-13", "code" => "EQT-0070", "kind" => "purchase", "amount" => -200.0},
    %{"date" => "2025-07-01", "code" => "EQT-0070", "kind" => "rent", "amount" => 1.38},
    %{"date" => "2025-07-01", "code" => "EQT-0070", "kind" => "tax", "amount" => -0.26}
  ]

  test "summary splits by platform and adds them up" do
    assert %{
             equito: %{invested: 200.0, earnings: 1.12},
             urbanitae: %{invested: 0.0, earnings: 0.0},
             total: %{invested: 200.0, earnings: 1.12}
           } = RealEstate.summary([], @equito, "2026-11-02")
  end

  test "time_series has a point per movement date plus today" do
    assert RealEstate.time_series([], @equito, "2026-11-02") == [
             %{date: "2025-03-13", invested: 200.0, earnings: 0.0},
             %{date: "2025-07-01", invested: 200.0, earnings: 1.12},
             %{date: "2026-11-02", invested: 200.0, earnings: 1.12}
           ]
  end

  test "time_series is empty with no history" do
    assert RealEstate.time_series([], [], "2026-11-02") == []
  end
end
