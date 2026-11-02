defmodule Sheetfolio.EquitoTransactionsTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.EquitoTransactions

  describe "movement_rows/1" do
    test "folds a payout's rent and retention into one row, newest first" do
      transactions = [
        %{
          "date" => "2025-03-13",
          "code" => "EQT-0070",
          "kind" => "purchase",
          "amount" => -200.0,
          "raw_label" => "COMPRA"
        },
        %{
          "date" => "2025-07-01",
          "code" => "EQT-0070",
          "kind" => "rent",
          "amount" => 1.38,
          "raw_label" => "RENTA"
        },
        %{
          "date" => "2025-07-01",
          "code" => "EQT-0070",
          "kind" => "tax",
          "amount" => -0.26,
          "raw_label" => "RET. FISCAL"
        },
        %{
          "date" => "2025-07-01",
          "code" => "EQT-0072",
          "kind" => "rent",
          "amount" => 1.42,
          "raw_label" => "RENTA"
        },
        %{
          "date" => "2025-07-01",
          "code" => "EQT-0072",
          "kind" => "tax",
          "amount" => -0.27,
          "raw_label" => "RET. FISCAL"
        }
      ]

      assert EquitoTransactions.movement_rows(transactions) == [
               %{
                 date: "2025-07-01",
                 code: "EQT-0072",
                 kind: "rent",
                 label: "RENTA",
                 rent: 1.42,
                 withheld: -0.27,
                 amount: 1.15
               },
               %{
                 date: "2025-07-01",
                 code: "EQT-0070",
                 kind: "rent",
                 label: "RENTA",
                 rent: 1.38,
                 withheld: -0.26,
                 amount: 1.12
               },
               %{
                 date: "2025-03-13",
                 code: "EQT-0070",
                 kind: "purchase",
                 label: "COMPRA",
                 rent: nil,
                 withheld: nil,
                 amount: -200.0
               }
             ]
    end
  end
end
