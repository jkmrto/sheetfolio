defmodule Sheetfolio.CryptoHoldingsTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.CryptoHoldings

  defp coinbase_btc do
    %{
      "platform" => "Coinbase",
      "symbol" => "BTC",
      "units" => 0.02018811,
      "cost_basis" => 826.13,
      "avg_cost" => 40_921.66
    }
  end

  describe "position/2" do
    test "values the holding at the given spot price" do
      position = CryptoHoldings.position([coinbase_btc()], 54_277.89)

      assert position.units == 0.02018811
      assert position.cost_basis == 826.13
      assert position.value == 1095.77
      assert position.unrealized == 269.64
    end

    test "leaves value and unrealized nil when the price is unknown" do
      position = CryptoHoldings.position([coinbase_btc()], nil)

      assert position.cost_basis == 826.13
      assert position.value == nil
      assert position.unrealized == nil
      assert [%{value: nil, unrealized: nil}] = position.holdings
    end

    test "sums across platforms" do
      other = %{coinbase_btc() | "platform" => "Kraken"}
      other = %{other | "units" => 0.01, "cost_basis" => 500.0}

      position = CryptoHoldings.position([coinbase_btc(), other], 50_000.0)

      assert position.units == 0.03018811
      assert position.cost_basis == 1326.13
      assert position.value == 1509.41
    end

    test "one unpriced holding makes the totals nil rather than understating them" do
      unpriced = %{coinbase_btc() | "symbol" => "ETH"}
      position = CryptoHoldings.position([coinbase_btc(), unpriced], nil)

      assert position.value == nil
      assert position.unrealized == nil
    end

    test "no holdings reports zero cost with no value" do
      position = CryptoHoldings.position([], 50_000.0)

      assert position.units == 0.0
      assert position.cost_basis == 0.0
      assert position.value == 0.0
      assert position.holdings == []
    end
  end
end
