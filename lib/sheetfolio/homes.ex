defmodule Sheetfolio.Homes do
  @moduledoc """
  Homes owned outright or with a mortgage, one document per home in the
  `homes` collection. Figures are for the whole home; `share` is the part
  that is mine, so a home bought between two has `share: 0.5`.

      { name: "Av. Cruz del Campo 33",
        share: 0.5,
        purchase: { date: "2025-09-01", price: 315000, cash_paid: 120000 },
        valuations: [ { date: "2026-11-15", value: 320000, note: "..." } ],
        mortgage: { as_of: "2026-10-01", balance: 212000,
                    monthly_payment: 740, monthly_interest: 240 } }

  The mortgage is a statement, not a schedule: `balance` is what was owed on
  `as_of`, and every monthly payment since then repays `monthly_payment -
  monthly_interest` of it. The real split moves a little towards principal
  each month, so recording a newer statement re-anchors the projection.
  The latest valuation is the market value.

  `cash_paid` is everything paid out of pocket at purchase, down payment and
  purchase costs (taxes, notary, registry) alike. What's been put in is that
  plus the principal repaid since, so `result` is the equity against it: the
  purchase costs count against it and the revaluation for it.
  """

  @collection "homes"

  def all, do: Mongo.find(:mongo, @collection, %{}, sort: %{name: 1}) |> Enum.to_list()

  @doc "Upsert by name."
  def upsert(%{name: name} = doc) do
    {:ok, _} =
      Mongo.update_one(
        :mongo,
        @collection,
        %{"name" => name},
        %{"$set" => Map.put(doc, :updated_at, DateTime.utc_now())},
        upsert: true
      )

    :ok
  end

  @doc """
  My share of a home as of `date` (`Date`):

      %{name: _, value: _, balance: _, equity: _, purchase_price: _, gain: _,
        put_in: _, cash_paid: _, principal_repaid: _, result: _,
        valuation_date: _, monthly_payment: _, monthly_interest: _,
        monthly_principal: _}
  """
  def summary(home, date) do
    share = home["share"]
    mortgage = home["mortgage"]
    valuation = Enum.max_by(home["valuations"], & &1["date"])
    value = valuation["value"] * share
    balance = balance_at(mortgage, date) * share
    purchase = home["purchase"]
    purchase_price = purchase["price"] * share
    cash_paid = purchase["cash_paid"] * share

    repaid =
      (balance_at(mortgage, Date.from_iso8601!(purchase["date"])) - balance_at(mortgage, date)) *
        share

    put_in = cash_paid + repaid

    %{
      name: home["name"],
      value: round2(value),
      balance: round2(balance),
      equity: round2(value - balance),
      purchase_price: round2(purchase_price),
      gain: round2(value - purchase_price),
      cash_paid: round2(cash_paid),
      principal_repaid: round2(repaid),
      put_in: round2(put_in),
      result: round2(value - balance - put_in),
      valuation_date: valuation["date"],
      monthly_payment: round2(mortgage["monthly_payment"] * share),
      monthly_interest: round2(mortgage["monthly_interest"] * share),
      monthly_principal: round2(principal(mortgage) * share)
    }
  end

  @doc """
  My equity on `date` (`Date`): my share of the latest valuation, less my
  share of the balance then. Zero before the purchase. Every date takes the
  latest valuation, so a new one shifts the whole history instead of showing
  up as a one-day jump: over time, equity only grows with the principal
  repaid.
  """
  def equity_at(home, date) do
    if Date.to_iso8601(date) < home["purchase"]["date"] do
      0.0
    else
      valuation = Enum.max_by(home["valuations"], & &1["date"])
      round2((valuation["value"] - balance_at(home["mortgage"], date)) * home["share"])
    end
  end

  @doc "The whole outstanding balance on `date`, never below zero."
  def balance_at(mortgage, date) do
    payments = months_between(Date.from_iso8601!(mortgage["as_of"]), date)
    max(mortgage["balance"] - payments * principal(mortgage), 0)
  end

  defp principal(mortgage), do: mortgage["monthly_payment"] - mortgage["monthly_interest"]

  # Whole months from `from` to `to`; negative before `from`.
  defp months_between(from, to) do
    months = (to.year - from.year) * 12 + (to.month - from.month)
    if to.day < from.day, do: months - 1, else: months
  end

  defp round2(number), do: Float.round(number * 1.0, 2)
end
