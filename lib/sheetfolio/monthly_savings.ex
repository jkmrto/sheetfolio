defmodule Sheetfolio.MonthlySavings do
  @moduledoc """
  Income and savings per month, one document per month in `monthly_savings`:

      { month: "2026-01", net_salary: 4149.04, meal_card: 183.20,
        irpf_refund_estimate: 100, notes: "..." }

  Only what can't be derived is stored: the net salary and meal card come
  from the Remote payslips. Expenses are Wise's spending for the month (the
  same totals as /expenses), so a recategorized or late activity moves the
  savings with it. `row/2` derives the rest:

      total_income = net_salary + meal_card + irpf_refund_estimate
      savings      = total_income - expenses
  """

  alias Sheetfolio.WiseExpenses

  @collection "monthly_savings"
  @inputs [:net_salary, :meal_card, :irpf_refund_estimate]

  def ensure_index do
    Mongo.create_indexes(:mongo, @collection, [
      %{key: %{month: 1}, name: "month_unique", unique: true}
    ])
  end

  @doc "Upsert by month. Takes the inputs only."
  def upsert(%{month: month} = doc) do
    {:ok, _} =
      Mongo.update_one(
        :mongo,
        @collection,
        %{"month" => month},
        %{
          "$set" =>
            doc
            |> Map.take([:month, :notes | @inputs])
            |> Map.put(:updated_at, DateTime.utc_now())
        },
        upsert: true
      )

    :ok
  end

  @doc "Every recorded month, oldest first, with expenses from the stored Wise activities."
  def all do
    docs = Mongo.find(:mongo, @collection, %{}, sort: %{month: 1}) |> Enum.to_list()
    {_months, totals} = WiseExpenses.stored_monthly_by_category()
    rows(docs, expenses_by_month(totals))
  end

  @doc "`%{\"YYYY-MM\" => total}` from WiseExpenses' `%{{\"YYYY-MM-01\", category} => total}`."
  def expenses_by_month(totals) do
    totals
    |> Enum.group_by(
      fn {{month, _category}, _total} -> String.slice(month, 0, 7) end,
      &elem(&1, 1)
    )
    |> Map.new(fn {month, amounts} -> {month, round2(Enum.sum(amounts))} end)
  end

  def rows(docs, expenses), do: Enum.map(docs, &row(&1, Map.get(expenses, &1["month"], 0.0)))

  def row(doc, expenses) do
    income = @inputs |> Enum.map(&number(doc[Atom.to_string(&1)])) |> Enum.sum()
    savings = income - expenses

    %{
      month: doc["month"],
      net_salary: number(doc["net_salary"]),
      meal_card: number(doc["meal_card"]),
      irpf_refund_estimate: number(doc["irpf_refund_estimate"]),
      total_income: round2(income),
      expenses: round2(expenses),
      savings: round2(savings),
      savings_rate_pct: rate(savings, income),
      notes: doc["notes"] || ""
    }
  end

  @doc "Totals over the rows of `year` (\"YYYY\"), with the monthly average saved."
  def year_totals(rows, year) do
    rows = Enum.filter(rows, &String.starts_with?(&1.month, year <> "-"))
    income = sum(rows, :total_income)
    expenses = sum(rows, :expenses)
    savings = sum(rows, :savings)

    %{
      year: year,
      months: length(rows),
      income: income,
      expenses: expenses,
      savings: savings,
      savings_rate_pct: rate(savings, income),
      avg_monthly_savings: if(rows == [], do: 0.0, else: round2(savings / length(rows)))
    }
  end

  @doc "The last day of the latest recorded month, or nil."
  def last_recorded do
    case Mongo.find_one(:mongo, @collection, %{}, sort: %{month: -1}) do
      %{"month" => month} -> Date.end_of_month(Date.from_iso8601!(month <> "-01"))
      nil -> nil
    end
  end

  defp sum(rows, key), do: rows |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum() |> round2()

  defp rate(_savings, income) when income == 0, do: 0.0
  defp rate(savings, income), do: Float.round(savings / income * 100, 1)

  defp number(nil), do: 0.0
  defp number(value), do: value * 1.0

  defp round2(number), do: Float.round(number * 1.0, 2)
end
