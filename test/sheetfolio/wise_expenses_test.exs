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
      refute WiseExpenses.title_key("La Parada A5 S.l") ==
               WiseExpenses.title_key("Minimarket La Parada")
    end

    test "a missing title matches nothing in particular" do
      assert WiseExpenses.title_key(nil) == ""
    end
  end

  describe "title_categories/1" do
    defp doc(title, category, excluded \\ false),
      do: %{"title" => title, "category" => category, "excluded" => excluded}

    test "a merchant whose history agrees passes its category on, across spellings" do
      docs = [
        doc("Escuela Infantil SolYLuna", "FAMILY"),
        doc("Escuela infantil Sol y Luna", "FAMILY")
      ]

      assert %{"escuelainfantilsolyluna" => %{category: "FAMILY", excluded: false}} =
               WiseExpenses.title_categories(docs)
    end

    test "a dominant category survives a few odd filings" do
      docs = List.duplicate(doc("Lidl", "GROCERIES"), 9) ++ [doc("Lidl", "TRIPS")]

      assert %{"lidl" => %{category: "GROCERIES"}} = WiseExpenses.title_categories(docs)
    end

    test "a title filed several ways passes nothing on" do
      transfers = [
        doc("JUAN CARLOS", "FAMILY"),
        doc("JUAN CARLOS", "BILLS"),
        doc("JUAN CARLOS", "HOUSING")
      ]

      uber = [doc("Uber", "BILLS"), doc("Uber", "TRANSPORT")]
      mostly = List.duplicate(doc("Airserv", "GROCERIES"), 3) ++ [doc("Airserv", "EATING_OUT")]

      assert WiseExpenses.title_categories(transfers ++ uber ++ mostly) == %{}
    end

    test "the insights flag is the latest activity's" do
      docs = [doc("Revolut", "GENERAL", false), doc("Revolut", "GENERAL", true)]

      assert %{"revolut" => %{excluded: true}} = WiseExpenses.title_categories(docs)
    end
  end
end
