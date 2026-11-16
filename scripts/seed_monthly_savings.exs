# Records 2026's monthly income in `monthly_savings` (net salary and meal card
# from the Remote payslips, plus the IRPF refund estimate).
#
#     mix run scripts/seed_monthly_savings.exs
#
# Safe to re-run: it upserts by month. Expenses aren't stored, they come from
# Wise, so the expenses and savings columns below are only checked against
# what the page will derive, and any month that disagrees is printed.

alias Sheetfolio.MonthlySavings

# month,net_salary,meal_card,irpf_refund_estimate,total_income,expenses,savings,savings_rate_pct
rows = """
2026-01,4149.04,183.20,100,4432.24,2868.88,1563.36,35.3
2026-02,4212.41,183.20,100,4495.61,2012.28,2483.33,55.2
2026-03,4212.13,183.20,100,4495.33,2217.91,2277.42,50.7
2026-04,4209.47,183.20,100,4492.67,1956.17,2536.50,56.5
2026-05,4370.00,183.20,100,4653.20,2839.52,1813.68,39.0
2026-06,4144.33,183.20,100,4427.53,2041.93,2385.60,53.9
2026-07,4214.43,183.20,100,4497.63,3514.22,983.41,21.9
2026-08,4161.94,183.20,100,4445.14,1907.24,2537.90,57.1
2026-09,4211.43,183.20,100,4494.63,2063.05,2431.58,54.1
2026-10,4141.48,183.20,100,4424.68,1796.54,2628.14,59.4
"""

MonthlySavings.ensure_index()

expected =
  for line <- String.split(rows, "\n", trim: true) do
    [month | numbers] = String.split(line, ",")

    [net, meal, irpf, income, expenses, savings, _rate] =
      Enum.map(numbers, &(&1 |> Float.parse() |> elem(0)))

    :ok =
      MonthlySavings.upsert(%{
        month: month,
        net_salary: net,
        meal_card: meal,
        irpf_refund_estimate: irpf
      })

    {month, {income, expenses, savings}}
  end

derived = Map.new(MonthlySavings.all(), &{&1.month, {&1.total_income, &1.expenses, &1.savings}})

for {month, figures} <- expected, derived[month] != figures do
  IO.puts("#{month}: expected #{inspect(figures)}, derived #{inspect(derived[month])}")
end

IO.puts("Recorded #{length(expected)} months")
