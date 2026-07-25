defmodule Sheetfolio.WiseBalanceTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.WiseBalance

  defp balance(value, currency), do: %{"amount" => %{"value" => value, "currency" => currency}}

  describe "sum_eur/2" do
    test "an EUR balance counts at face value" do
      assert WiseBalance.sum_eur([balance(100.0, "EUR")], %{}) == 100.0
    end

    test "a non-EUR balance is converted using the given rate" do
      # 110 USD at a rate of 1.1 USD per EUR is 100 EUR.
      assert WiseBalance.sum_eur([balance(110.0, "USD")], %{"USD" => 1.1}) == 100.0
    end

    test "several balances sum together" do
      balances = [balance(100.0, "EUR"), balance(110.0, "USD")]

      assert WiseBalance.sum_eur(balances, %{"USD" => 1.1}) == 200.0
    end

    test "a zero balance is skipped even without a rate for its currency" do
      assert WiseBalance.sum_eur([balance(0, "VND")], %{}) == 0.0
    end

    test "a non-zero balance in a currency missing from rates contributes nothing" do
      balances = [balance(100.0, "EUR"), balance(50.0, "PLN")]

      assert WiseBalance.sum_eur(balances, %{}) == 100.0
    end
  end
end
