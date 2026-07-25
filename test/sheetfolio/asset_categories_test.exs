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
      assert AssetCategories.category_for("IE00B579F325", %{"IE00B579F325" => "Gold"}) == "Gold"
    end

    test "falls back for holdings the sheet can't match on its own" do
      # The sheet's ISIN row holds the ticker XAD6.DE for this one.
      assert AssetCategories.category_for("DE000A1E0HS6", %{}) == "Silver"
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
  end

  describe "breakdown/2" do
    test "sums positions per category, largest first, with percentages" do
      positions = [
        position("A", "Fund A", 300.0),
        position("B", "Fund B", 100.0),
        position("C", "Fund C", 600.0)
      ]

      categories = %{"A" => "Indexados", "B" => "Indexados", "C" => "Gold"}

      assert [gold, indexados] = AssetCategories.breakdown(positions, categories)

      assert gold.category == "Gold"
      assert gold.value == 600.0
      assert gold.pct == 60.0

      assert indexados.category == "Indexados"
      assert indexados.value == 400.0
      assert indexados.pct == 40.0
      assert indexados.assets == ["Fund A", "Fund B"]
    end

    test "leaves out positions with no value rather than counting them as zero" do
      positions = [position("A", "Fund A", 100.0), position("B", "Fund B", nil)]

      assert [only] = AssetCategories.breakdown(positions, %{"A" => "Gold", "B" => "Silver"})
      assert only.category == "Gold"
      assert only.pct == 100.0
    end

    test "groups anything the sheet doesn't know under one uncategorized slice" do
      positions = [position("XX0000000000", "Mystery", 50.0), position("A", "Fund A", 50.0)]

      breakdown = AssetCategories.breakdown(positions, %{"A" => "Gold"})

      assert Enum.map(breakdown, & &1.category) |> Enum.sort() ==
               Enum.sort(["Gold", AssetCategories.uncategorized()])
    end

    test "an empty position list produces no slices" do
      assert AssetCategories.breakdown([], %{}) == []
    end
  end
end
