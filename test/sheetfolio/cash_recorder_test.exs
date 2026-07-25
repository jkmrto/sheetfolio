defmodule Sheetfolio.CashRecorderTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.CashRecorder

  describe "put_source/3" do
    test "replaces an existing source's amount, leaving the others untouched" do
      sources = [%{name: "Bankinter", amount: 100.0}, %{name: "Wise", amount: 50.0}]

      updated = CashRecorder.put_source(sources, "Wise", 75.0)

      assert updated == [%{name: "Bankinter", amount: 100.0}, %{name: "Wise", amount: 75.0}]
    end

    test "appends the source when it isn't present yet" do
      updated = CashRecorder.put_source([%{name: "Bankinter", amount: 100.0}], "Wise", 75.0)

      assert updated == [%{name: "Bankinter", amount: 100.0}, %{name: "Wise", amount: 75.0}]
    end

    test "appends into an empty list" do
      assert CashRecorder.put_source([], "Wise", 75.0) == [%{name: "Wise", amount: 75.0}]
    end
  end
end
