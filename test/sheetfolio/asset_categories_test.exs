defmodule Sheetfolio.AssetCategoriesTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.AssetCategories

  defp position(isin, asset, value), do: %{"isin" => isin, "asset" => asset, "value" => value}

  describe "zip_columns/2" do
    test "pairs each column's identifier with the category above it" do
      isins = ["ISIN", "IE00B579F325", "IE00BF8HV600"]
      categories = ["", "Gold", "Renta fija corto plazo"]

      assert AssetCategories.zip_columns(isins, categories) == %{
               "IE00B579F325" => "Gold",
               "IE00BF8HV600" => "Renta fija corto plazo"
             }
    end

    test "drops columns missing an identifier or a category" do
      isins = ["ISIN", "", "IE00BF8HV600", "ES0165265001"]
      categories = ["", "Inmobiliario", "Renta fija corto plazo", ""]

      assert AssetCategories.zip_columns(isins, categories) == %{
               "IE00BF8HV600" => "Renta fija corto plazo"
             }
    end

    test "tolerates the two rows having different lengths" do
      # Vision global carries extra cash columns that Participaciones doesn't.
      isins = ["ISIN", "IE00B579F325"]
      categories = ["", "Gold", "Efectivo", "Efectivo"]

      assert AssetCategories.zip_columns(isins, categories) == %{"IE00B579F325" => "Gold"}
    end

    test "trims surrounding whitespace" do
      assert AssetCategories.zip_columns(["ISIN", " IE00B579F325 "], ["", " Gold "]) == %{
               "IE00B579F325" => "Gold"
             }
    end
  end

  describe "category_for/2" do
    test "uses the sheet when it has the identifier" do
      assert AssetCategories.category_for("ES0165265001", %{"ES0165265001" => "Indexados"}) ==
               "Indexados"
    end

    test "falls back for holdings the sheet can't match on its own" do
      # Bought after the sheet's header row was last extended.
      assert AssetCategories.category_for("IE000RHYOR04", %{}) == "Renta fija corto plazo"
      assert AssetCategories.category_for("URBANITAE", %{}) == "Inmobiliario"
    end

    test "the sheet wins over the fallback, so the fallback goes quiet once it's fixed" do
      categories = %{"IE000RHYOR04" => "Renta fija largo plazo"}

      assert AssetCategories.category_for("IE000RHYOR04", categories) == "Renta fija largo plazo"
    end

    test "anything else is uncategorized" do
      assert AssetCategories.category_for("XX0000000000", %{}) == AssetCategories.uncategorized()
    end

    test "cash entries are reported as Efectivo" do
      assert AssetCategories.category_for("EFECTIVO", %{}) == "Efectivo"
    end

    test "the pension plan is Indexados, keyed by its DGS code" do
      assert AssetCategories.category_for("N5396", %{}) == "Indexados"
    end
  end

  describe "breakdown/2 with cash folded in" do
    test "cash accounts collapse into one Efectivo slice alongside the market positions" do
      positions = [
        position("A", "Fund A", 700.0),
        position("EFECTIVO", "Bankinter", 100.0),
        position("EFECTIVO", "Wise", 200.0)
      ]

      assert [funds, cash] = AssetCategories.breakdown(positions, %{"A" => "Indexados"})

      assert funds.category == "Indexados"
      assert cash.category == "Efectivo"
      assert cash.value == 300.0
      assert cash.pct == 30.0
      assert cash.assets == ["Wise", "Bankinter"]
    end

    test "a zero-balance account doesn't show up as an asset" do
      positions = [
        position("A", "Fund A", 700.0),
        position("EFECTIVO", "Bankinter", 0.0),
        position("EFECTIVO", "Wise", 300.0)
      ]

      assert [_funds, cash] = AssetCategories.breakdown(positions, %{"A" => "Indexados"})

      assert cash.assets == ["Wise"]
      assert cash.value == 300.0
    end
  end

  describe "category_for/2 precious-metals regrouping" do
    test "the sheet's Gold and Silver are both reported as Oro/Plata" do
      assert AssetCategories.category_for("IE00B579F325", %{"IE00B579F325" => "Gold"}) ==
               "Oro/Plata"

      assert AssetCategories.category_for("IE00B4ND3602", %{"IE00B4ND3602" => "Silver"}) ==
               "Oro/Plata"
    end

    test "a fallback that lands on Silver is regrouped too" do
      # The sheet's ISIN row holds the ticker XAD6.DE for the silver ETF, so
      # this one reaches Silver through the fallback rather than the sheet.
      assert AssetCategories.category_for("DE000A1E0HS6", %{}) == "Oro/Plata"
    end

    test "VanEck Gold Miners moves even though the sheet files it as Indexado Sectorial" do
      categories = %{"IE00BQQP9F84" => "Indexado Sectorial"}

      assert AssetCategories.category_for("IE00BQQP9F84", categories) == "Oro/Plata"
    end

    test "other Indexado Sectorial holdings stay put" do
      # Van Eck Semiconductors shares that category and is not a metal.
      categories = %{"IE00BMC38736" => "Indexado Sectorial"}

      assert AssetCategories.category_for("IE00BMC38736", categories) == "Indexado Sectorial"
    end

    test "the three of them collapse into a single slice" do
      positions = [
        position("IE00B579F325", "Invesco Physical Gold", 29_292.31),
        position("DE000A1E0HS6", "ETF DB Physical Silver", 14_474.40),
        position("IE00BQQP9F84", "VanEck Gold Miners", 10_154.55),
        position("ES0165265001", "Indexado Global", 1000.0)
      ]

      categories = %{
        "IE00B579F325" => "Gold",
        "IE00BQQP9F84" => "Indexado Sectorial",
        "ES0165265001" => "Indexados"
      }

      assert [metals, _indexados] = AssetCategories.breakdown(positions, categories)

      assert metals.category == "Oro/Plata"
      assert metals.value == 53_921.26
      assert length(metals.assets) == 3
    end
  end

  describe "breakdown/2" do
    test "sums positions per category, largest first, with percentages" do
      positions = [
        position("A", "Fund A", 300.0),
        position("B", "Fund B", 100.0),
        position("C", "Fund C", 600.0)
      ]

      categories = %{"A" => "Indexados", "B" => "Indexados", "C" => "Bitcoin"}

      assert [bitcoin, indexados] = AssetCategories.breakdown(positions, categories)

      assert bitcoin.category == "Bitcoin"
      assert bitcoin.value == 600.0
      assert bitcoin.pct == 60.0

      assert indexados.category == "Indexados"
      assert indexados.value == 400.0
      assert indexados.pct == 40.0
      assert indexados.assets == ["Fund A", "Fund B"]
    end

    test "leaves out positions with no value rather than counting them as zero" do
      positions = [position("A", "Fund A", 100.0), position("B", "Fund B", nil)]

      categories = %{"A" => "Indexados", "B" => "Bitcoin"}

      assert [only] = AssetCategories.breakdown(positions, categories)
      assert only.category == "Indexados"
      assert only.pct == 100.0
    end

    test "groups anything the sheet doesn't know under one uncategorized slice" do
      positions = [position("XX0000000000", "Mystery", 50.0), position("A", "Fund A", 50.0)]

      breakdown = AssetCategories.breakdown(positions, %{"A" => "Indexados"})

      assert Enum.map(breakdown, & &1.category) |> Enum.sort() ==
               Enum.sort(["Indexados", AssetCategories.uncategorized()])
    end

    test "an empty position list produces no slices" do
      assert AssetCategories.breakdown([], %{}) == []
    end
  end

  describe "history/2" do
    test "gives each date's category totals, in the order the dates came in" do
      dated = [
        {"2025-01-01", [position("A", "Fund A", 100.0)]},
        {"2025-01-02", [position("A", "Fund A", 150.0), position("B", "Fund B", 50.0)]}
      ]

      categories = %{"A" => "Indexados", "B" => "Bitcoin"}

      assert [first, second] = AssetCategories.history(dated, categories)

      assert first == %{date: "2025-01-01", totals: %{"Indexados" => 100.0}}
      assert second.date == "2025-01-02"
      assert second.totals == %{"Indexados" => 150.0, "Bitcoin" => 50.0}
    end

    test "a category not held on a date is absent rather than zero" do
      dated = [{"2025-01-01", [position("A", "Fund A", 100.0)]}]

      [point] = AssetCategories.history(dated, %{"A" => "Indexados", "B" => "Bitcoin"})

      refute Map.has_key?(point.totals, "Bitcoin")
    end

    test "positions of sold-out share classes still categorize through the fallbacks" do
      # These only appear in older snapshots; the sheet lists their successors.
      dated = [
        {"2025-01-01",
         [
           position("IE0032126645", "Vanguard US 500", 1000.0),
           position("ES0170156048", "Santalucia Renta Fija", 500.0),
           position("IE00B04GQX83", "Vanguard US Inv Grade", 250.0)
         ]}
      ]

      [point] = AssetCategories.history(dated, %{})

      assert point.totals == %{
               "Indexados" => 1000.0,
               "Renta fija corto plazo" => 500.0,
               "Renta fija largo plazo" => 250.0
             }

      refute Map.has_key?(point.totals, AssetCategories.uncategorized())
    end
  end

  describe "history_categories/1" do
    test "lists every category seen, largest cumulative total first" do
      history = [
        %{date: "2025-01-01", totals: %{"Indexados" => 100.0, "Bitcoin" => 500.0}},
        %{date: "2025-01-02", totals: %{"Indexados" => 900.0}}
      ]

      assert AssetCategories.history_categories(history) == ["Indexados", "Bitcoin"]
    end

    test "Inmobiliario leads regardless of size, so the flat band sits at the bottom" do
      history = [
        %{date: "2025-01-01", totals: %{"Indexados" => 900.0, "Inmobiliario" => 100.0}}
      ]

      assert AssetCategories.history_categories(history) == ["Inmobiliario", "Indexados"]
    end

    test "Inmobiliario is skipped when the history never held any" do
      history = [%{date: "2025-01-01", totals: %{"Indexados" => 900.0}}]

      assert AssetCategories.history_categories(history) == ["Indexados"]
    end

    test "an empty history has no categories" do
      assert AssetCategories.history_categories([]) == []
    end
  end
end
