defmodule Sheetfolio.WiseExpensesTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.WiseExpenses

  describe "title_key/1" do
    test "matches the same merchant across case and spacing" do
      assert WiseExpenses.title_key("Escuela infantil Sol y Luna") ==
               WiseExpenses.title_key("Escuela Infantil SolYLuna")
    end

    test "ignores punctuation but keeps accented letters and digits" do
      assert WiseExpenses.title_key("Sdad.mpal Aparcamientos, S.A.") == "sdadmpalaparcamientossa"
      assert WiseExpenses.title_key("Peluquería Tres14") == "peluqueríatres14"
    end

    test "tells different merchants apart" do
      refute WiseExpenses.title_key("La Parada A5 S.l") == WiseExpenses.title_key("Minimarket La Parada")
    end

    test "a missing title matches nothing in particular" do
      assert WiseExpenses.title_key(nil) == ""
    end
  end
end
