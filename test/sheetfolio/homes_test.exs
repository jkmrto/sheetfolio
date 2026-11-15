defmodule Sheetfolio.HomesTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.Homes

  @mortgage %{
    "as_of" => "2026-10-01",
    "balance" => 212_000,
    "monthly_payment" => 740,
    "monthly_interest" => 240
  }

  @home %{
    "name" => "Piso",
    "share" => 0.5,
    "purchase" => %{"date" => "2025-09-01", "price" => 315_000, "cash_paid" => 120_000},
    "valuations" => [
      %{"date" => "2025-09-01", "value" => 315_000},
      %{"date" => "2026-11-15", "value" => 320_000}
    ],
    "mortgage" => @mortgage
  }

  test "balance_at is the statement balance until the next payment" do
    assert Homes.balance_at(@mortgage, ~D[2026-10-01]) == 212_000
    assert Homes.balance_at(@mortgage, ~D[2026-10-31]) == 212_000
  end

  test "balance_at repays payment less interest each whole month" do
    assert Homes.balance_at(@mortgage, ~D[2026-11-01]) == 211_500
    assert Homes.balance_at(@mortgage, ~D[2027-10-15]) == 206_000
  end

  test "balance_at never goes below zero" do
    assert Homes.balance_at(@mortgage, ~D[2070-01-01]) == 0
  end

  test "equity_at uses the valuation in force on the date" do
    assert Homes.equity_at(@home, ~D[2025-08-31]) == 0.0
    assert Homes.equity_at(@home, ~D[2026-11-01]) == 51_750.0
    assert Homes.equity_at(@home, ~D[2026-11-15]) == 54_250.0
  end

  test "summary is my share, valued at the latest valuation" do
    assert Homes.summary(@home, ~D[2026-11-15]) == %{
             name: "Piso",
             value: 160_000.0,
             balance: 105_750.0,
             equity: 54_250.0,
             purchase_price: 157_500.0,
             gain: 2500.0,
             cash_paid: 60_000.0,
             principal_repaid: 3500.0,
             put_in: 63_500.0,
             result: -9250.0,
             valuation_date: "2026-11-15",
             monthly_payment: 370.0,
             monthly_interest: 120.0,
             monthly_principal: 250.0
           }
  end
end
