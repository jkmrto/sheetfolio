defmodule Sheetfolio.MoneyTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.Money

  describe "parse_number/1" do
    test "reads Spanish format, where the dot is thousands" do
      assert {1418.996, ""} = Money.parse_number("1.418,996")
    end

    test "reads English format, where the comma is thousands" do
      assert {1000.34, ""} = Money.parse_number("1,000.34")
    end

    test "treats a comma followed by exactly three digits as thousands" do
      assert {1188.0, ""} = Money.parse_number("1,188")
    end

    test "treats a comma followed by any other digit count as the decimal point" do
      assert {14.2592, ""} = Money.parse_number("14,2592")
    end

    test "reads a plain number" do
      assert {0.5849, ""} = Money.parse_number("0.5849")
    end

    test "returns :error for something unparseable" do
      assert :error = Money.parse_number("n/a")
    end
  end

  describe "parse_price/1" do
    test "splits amount from currency" do
      assert {2563.52, "EUR"} = Money.parse_price("2563.52 EUR")
      assert {19.85, "USD"} = Money.parse_price("19.85 USD")
    end

    test "handles a thousands separator in the amount" do
      assert {1418.996, "EUR"} = Money.parse_price("1.418,996 EUR")
    end

    test "returns :error when there is no amount and currency" do
      assert :error = Money.parse_price("garbage")
    end
  end

  describe "to_eur/4" do
    test "divides by the rate for USD and CAD" do
      assert Money.to_eur(11.0, "USD", 1.1, 1.5) == 10.0
      assert Money.to_eur(15.0, "CAD", 1.1, 1.5) == 10.0
    end

    test "leaves EUR and unknown currencies alone" do
      assert Money.to_eur(11.0, "EUR", 1.1, 1.5) == 11.0
      assert Money.to_eur(11.0, "GBP", 1.1, 1.5) == 11.0
    end
  end
end
