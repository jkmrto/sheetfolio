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

  describe "note_tokens/1" do
    test "drops months, accents, filler and numbers, and stems to five letters" do
      assert WiseExpenses.note_tokens("Ticket restaurantes - Septiembre 2026") == [
               "ticke",
               "resta"
             ]

      assert WiseExpenses.note_tokens("Cómida aromas") == ["comid", "aroma"]
      assert WiseExpenses.note_tokens("Luz de Octubre") == ["luz"]
    end
  end

  describe "guess_from_note/2" do
    defp transfer(note, category), do: %{"note" => note, "category" => category}

    setup do
      model =
        WiseExpenses.note_model([
          transfer("Luz - Noviembre", "BILLS"),
          transfer("Factura luz Diciembre", "BILLS"),
          transfer("Ticket restaurante Noviembre", "EATING_OUT"),
          transfer("Ticker restaurantes - Enero", "EATING_OUT"),
          transfer("Canguro Dario", "FAMILY"),
          transfer("Ropa Dario", "FAMILY"),
          transfer("Compras casa", "SHOPPING")
        ])

      %{model: model}
    end

    test "a note made of known words gets their category", %{model: model} do
      assert WiseExpenses.guess_from_note("Luz Octubre", model) == "BILLS"
      assert WiseExpenses.guess_from_note("ticket restaurant - Octubre", model) == "EATING_OUT"
      assert WiseExpenses.guess_from_note("Ropa Dario - Septiembre", model) == "FAMILY"
    end

    test "unknown words guess nothing", %{model: model} do
      assert WiseExpenses.guess_from_note("candlelight - malaga", model) == nil
      assert WiseExpenses.guess_from_note("", model) == nil
    end

    test "words pulling different ways guess nothing", %{model: model} do
      assert WiseExpenses.guess_from_note("luz casa", model) == nil
    end
  end

  describe "infer/3" do
    test "a merchant with agreeing history wins over the note, and is no guess" do
      inference = %{
        titles: %{"lidl" => %{category: "GROCERIES", excluded: false}},
        notes: %{"luz" => %{"BILLS" => 3}}
      }

      assert %{category: "GROCERIES", guessed: false} =
               WiseExpenses.infer("Lidl", "luz", inference)
    end

    test "otherwise the note is guessed from, and marked as a guess" do
      inference = %{titles: %{}, notes: %{"luz" => %{"BILLS" => 3}}}

      assert %{category: "BILLS", guessed: true, excluded: false} =
               WiseExpenses.infer("JUAN CARLOS MARTINEZ", "Luz Octubre", inference)
    end

    test "a guess of a category with no label of its own is dropped" do
      inference = %{titles: %{}, notes: %{"ahorr" => %{"GENERAL" => 2}}}

      assert %{category: nil, guessed: false} =
               WiseExpenses.infer("JUAN CARLOS", "Ahorro Octubre", inference)
    end
  end
end
