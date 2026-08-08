defmodule Sheetfolio.EquitoTransactions do
  @moduledoc """
  Per-movement Equito history, read from Historial screenshots (Equito has no
  API). One document per row on screen:

      { date: "2026-07-01",         # ISO date the movement happened
        code: "EQT-0072",           # nil for movements not tied to a property
        kind: "purchase" | "rent" | "tax" | "reward",
        tokens: 2,                  # the count the row prefixes the code with
        amount: -200.00,            # signed as the app shows it
        raw_label: "COMPRA",
        captured_at: <DateTime> }

  Amounts keep the app's own sign — money out negative, money in positive —
  so a row reads the same here as on the phone. RENTA and RET. FISCAL arrive
  as separate rows on the same date; rent is gross and the retention is the
  19% withholding, so the net distribution is their sum.
  """

  @collection "equito_transactions"
  @kinds ~w(purchase rent tax reward)

  def kinds, do: @kinds

  def all do
    Mongo.find(:mongo, @collection, %{}, sort: %{date: -1, captured_at: -1})
    |> Enum.to_list()
  end

  def insert_many([]), do: :ok

  def insert_many(docs) do
    {:ok, _} = Mongo.insert_many(:mongo, @collection, docs)
    :ok
  end

  @doc """
  Look up a movement by natural key (date + code + kind + amount), so
  re-ingesting an overlapping screenshot doesn't duplicate rows.
  """
  def find_matching(%{date: date, code: code, kind: kind, amount: amount}) do
    Mongo.find_one(:mongo, @collection, %{
      "date" => date,
      "code" => code,
      "kind" => kind,
      "amount" => amount
    })
  end

  @doc """
  One entry per property, in code order:

      %{code, tokens, invested, rent_gross, tax_withheld, net_income,
        payouts, first_date, last_date}

  `invested` is positive (the app writes purchases as negative), and
  `net_income` is what actually landed: gross rent less the retention.
  """
  def rollup_by_property(transactions) do
    transactions
    |> Enum.reject(&is_nil(&1["code"]))
    |> Enum.group_by(& &1["code"])
    |> Enum.map(fn {code, rows} ->
      rent_gross = sum_amount(rows, "rent")
      tax_withheld = sum_amount(rows, "tax")
      dates = Enum.map(rows, & &1["date"])

      %{
        code: code,
        tokens: tokens_held(rows),
        invested: round2(-sum_amount(rows, "purchase")),
        rent_gross: round2(rent_gross),
        tax_withheld: round2(tax_withheld),
        net_income: round2(rent_gross + tax_withheld),
        payouts: Enum.count(rows, &(&1["kind"] == "rent")),
        first_date: Enum.min(dates),
        last_date: Enum.max(dates)
      }
    end)
    |> Enum.sort_by(& &1.code)
  end

  @doc """
  Portfolio-wide figures. `rewards` covers the movements with no property
  attached (RECOMPENSA), which are income but not a property's yield.
  """
  def totals(transactions) do
    rollup = rollup_by_property(transactions)

    %{
      invested: round2(Enum.reduce(rollup, 0.0, &(&1.invested + &2))),
      rent_gross: round2(Enum.reduce(rollup, 0.0, &(&1.rent_gross + &2))),
      tax_withheld: round2(Enum.reduce(rollup, 0.0, &(&1.tax_withheld + &2))),
      net_income: round2(Enum.reduce(rollup, 0.0, &(&1.net_income + &2))),
      rewards: round2(sum_amount(transactions, "reward")),
      properties: length(rollup)
    }
  end

  @doc """
  Running `{outstanding, earnings}` as of the given ISO date, for overlaying
  Equito onto the portfolio-wide figures.

  Outstanding is the capital still in tokens: nothing has been sold or
  redeemed, so it's simply what has been bought by that date. Earnings are the
  distributions actually received — rent net of the retention — plus any
  platform rewards.
  """
  def state_at(transactions, date_string) do
    transactions
    |> Enum.filter(&(&1["date"] <= date_string))
    |> Enum.reduce({0.0, 0.0}, fn tx, {outstanding, earnings} ->
      {outstanding + purchase_amount(tx), earnings + income_amount(tx) + reward_amount(tx)}
    end)
    |> then(fn {outstanding, earnings} -> {round2(outstanding), round2(earnings)} end)
  end

  @doc """
  Time series over the movement history: one point per date, plus a final
  `today` point so the line runs to the present.

      %{date: "2026-07-01", invested: 1200.00, net_income: 47.32}

  Both series accumulate, which is what a monthly rent stream is: capital
  goes in a step at a time and the distributions pile up on top.
  """
  def time_series([]), do: []

  def time_series(transactions) do
    points =
      transactions
      |> Enum.sort_by(& &1["date"])
      |> Enum.scan(%{date: nil, invested: 0.0, net_income: 0.0}, &accumulate/2)
      |> Enum.reverse()
      |> Enum.uniq_by(& &1.date)
      |> Enum.reverse()
      |> Enum.map(&%{&1 | invested: round2(&1.invested), net_income: round2(&1.net_income)})

    points ++ [%{List.last(points) | date: Date.utc_today() |> Date.to_iso8601()}]
  end

  defp accumulate(tx, acc) do
    %{
      date: tx["date"],
      invested: acc.invested + purchase_amount(tx),
      net_income: acc.net_income + income_amount(tx)
    }
  end

  defp purchase_amount(%{"kind" => "purchase", "amount" => amount}), do: -amount
  defp purchase_amount(_tx), do: 0.0

  defp income_amount(%{"kind" => kind, "amount" => amount}) when kind in ["rent", "tax"], do: amount
  defp income_amount(_tx), do: 0.0

  defp reward_amount(%{"kind" => "reward", "amount" => amount}), do: amount
  defp reward_amount(_tx), do: 0.0

  # Purchases carry the token count; a later top-up on the same property adds
  # to it, which is why this sums rather than takes the last row.
  defp tokens_held(rows) do
    rows
    |> Enum.filter(&(&1["kind"] == "purchase"))
    |> Enum.reduce(0, &((&1["tokens"] || 0) + &2))
  end

  defp sum_amount(rows, kind) do
    rows
    |> Enum.filter(&(&1["kind"] == kind))
    |> Enum.reduce(0.0, &(&1["amount"] + &2))
  end

  defp round2(number), do: Float.round(number * 1.0, 2)
end
