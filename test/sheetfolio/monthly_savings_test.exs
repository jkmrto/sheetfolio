defmodule Sheetfolio.MonthlySavingsTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.MonthlySavings

  defp doc(month, net),
    do: %{
      "month" => month,
      "net_salary" => net,
      "meal_card" => 183.2,
      "irpf_refund_estimate" => 100
    }

  test "expenses are Wise's categories summed per month" do
    totals = %{
      {"2026-01-01", "Groceries"} => 1000.0,
      {"2026-01-01", "Bills"} => 1868.88,
      {"2026-02-01", "Bills"} => 2012.28
    }

    assert MonthlySavings.expenses_by_month(totals) == %{
             "2026-01" => 2868.88,
             "2026-02" => 2012.28
           }
  end

  test "income, savings and rate are derived from the inputs and expenses" do
    row = MonthlySavings.row(doc("2026-01", 4149.04), 2868.88)

    assert row.total_income == 4432.24
    assert row.savings == 1563.36
    assert row.savings_rate_pct == 35.3
    assert row.notes == ""
  end

  test "a month without Wise spending saves all its income" do
    [row] = MonthlySavings.rows([doc("2026-11", 4000)], %{})
    assert row.expenses == 0.0
    assert row.savings == 4283.2
  end

  test "year totals cover only that year" do
    rows =
      MonthlySavings.rows(
        [doc("2025-12", 4000), doc("2026-01", 4149.04), doc("2026-02", 4212.41)],
        %{
          "2026-01" => 2868.88,
          "2026-02" => 2012.28
        }
      )

    totals = MonthlySavings.year_totals(rows, "2026")

    assert totals.months == 2
    assert totals.income == 8927.85
    assert totals.expenses == 4881.16
    assert totals.savings == 4046.69
    assert totals.savings_rate_pct == 45.3
    assert totals.avg_monthly_savings == 2023.35
  end
end
