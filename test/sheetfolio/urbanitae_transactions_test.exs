defmodule Sheetfolio.UrbanitaeTransactionsTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.UrbanitaeTransactions, as: Txs

  defp investment(date, key, amount) do
    %{"date" => date, "kind" => "investment", "project_key" => key, "amount" => amount, "city" => "Valencia", "project" => "Montesano"}
  end

  defp repayment(date, key, amount, repayment_kind) do
    %{
      "date" => date,
      "kind" => "repayment",
      "repayment_kind" => repayment_kind,
      "project_key" => key,
      "amount" => amount,
      "city" => "Valencia",
      "project" => "Montesano"
    }
  end

  describe "rollup_by_project/2" do
    test "an active project counts yield without reducing what's outstanding" do
      txs = [
        investment("2024-05-23", "valencia-montesano", 10_000.0),
        repayment("2024-11-23", "valencia-montesano", 500.0, "yield")
      ]

      [project] = Txs.rollup_by_project(txs, %{})

      assert project.invested == 10_000.0
      assert project.yield_returned == 500.0
      assert project.principal_returned == 0.0
      assert project.outstanding == 10_000.0
      assert project.status == "active"
      assert project.net_pnl == -9500.0
    end

    test "a project closes once all principal is back, and outstanding goes to zero" do
      txs = [
        investment("2024-05-23", "valencia-montesano", 10_000.0),
        repayment("2024-11-23", "valencia-montesano", 500.0, "yield"),
        repayment("2025-05-23", "valencia-montesano", 10_000.0, "principal")
      ]

      [project] = Txs.rollup_by_project(txs, %{})

      assert project.status == "closed"
      assert project.outstanding == 0.0
      assert project.returned_total == 10_500.0
      assert project.net_pnl == 500.0
    end

    test "a repayment with no repayment_kind counts as yield" do
      txs = [
        investment("2024-05-23", "valencia-montesano", 10_000.0),
        %{"date" => "2024-11-23", "kind" => "repayment", "project_key" => "valencia-montesano", "amount" => 300.0, "city" => "Valencia", "project" => "Montesano"}
      ]

      [project] = Txs.rollup_by_project(txs, %{})

      assert project.yield_returned == 300.0
      assert project.principal_returned == 0.0
    end
  end

  describe "state_at/2" do
    test "ignores transactions after the given date" do
      txs = [
        investment("2024-05-23", "a", 10_000.0),
        repayment("2025-01-01", "a", 500.0, "yield")
      ]

      assert {10_000.0, +0.0} = Txs.state_at(txs, "2024-12-31")
      assert {10_000.0, 500.0} = Txs.state_at(txs, "2025-01-01")
    end
  end

  describe "time_series/1" do
    test "emits one point per event date plus a trailing point for today" do
      txs = [
        investment("2024-05-23", "a", 10_000.0),
        repayment("2024-11-23", "a", 500.0, "yield")
      ]

      series = Txs.time_series(txs)
      today = Date.utc_today() |> Date.to_iso8601()

      assert Enum.map(series, & &1.date) == ["2024-05-23", "2024-11-23", today]
      assert List.last(series).outstanding == 10_000.0
      assert List.last(series).earnings == 500.0
    end

    test "collapses several movements on one date into that day's end state" do
      txs = [
        investment("2024-05-23", "a", 10_000.0),
        investment("2024-05-23", "b", 5_000.0)
      ]

      series = Txs.time_series(txs)

      assert [%{date: "2024-05-23", outstanding: 15_000.0} | _] = series
      assert Enum.count(series, &(&1.date == "2024-05-23")) == 1
    end

    test "principal returned beyond what was invested counts as earnings" do
      txs = [
        investment("2024-05-23", "a", 10_000.0),
        repayment("2025-05-23", "a", 11_000.0, "principal")
      ]

      series = Txs.time_series(txs)
      final = List.last(series)

      assert final.outstanding == 0.0
      assert final.earnings == 1_000.0
    end

    test "an empty history produces no points" do
      assert Txs.time_series([]) == []
    end
  end

  test "project_key/2 slugifies city and project" do
    assert Txs.project_key("Valencia", "Montesano") == "valencia-montesano"
    assert Txs.project_key("A Coruña", "Casa Nueva") == "a-coruna-casa-nueva"
  end
end
