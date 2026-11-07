defmodule SheetfolioWeb.SummaryLiveTest do
  use ExUnit.Case, async: true

  alias SheetfolioWeb.SummaryLive

  defp names(rows), do: Enum.map(rows, & &1.asset)

  describe "sort_rows/2" do
    test "orders amounts both ways" do
      rows = [%{asset: "A", gain: 5.0}, %{asset: "B", gain: -2.0}, %{asset: "C", gain: 9.0}]

      assert names(SummaryLive.sort_rows(rows, {:gain, :desc})) == ["C", "A", "B"]
      assert names(SummaryLive.sort_rows(rows, {:gain, :asc})) == ["B", "A", "C"]
    end

    test "keeps rows without a value last in both directions" do
      rows = [%{asset: "A", gain: nil}, %{asset: "B", gain: 1.0}, %{asset: "C", gain: 2.0}]

      assert names(SummaryLive.sort_rows(rows, {:gain, :desc})) == ["C", "B", "A"]
      assert names(SummaryLive.sort_rows(rows, {:gain, :asc})) == ["B", "C", "A"]
    end

    test "ignores case in names" do
      rows = [%{asset: "bitcoin"}, %{asset: "Amundi"}, %{asset: "Zeta"}]

      assert names(SummaryLive.sort_rows(rows, {:asset, :asc})) == ["Amundi", "bitcoin", "Zeta"]
    end
  end

  describe "number formats" do
    test "amounts use dots for thousands and a comma for decimals" do
      assert SummaryLive.format_eur(1_234_567.89) == "1.234.567,89 €"
      assert SummaryLive.format_eur(999) == "999,00 €"
      assert SummaryLive.format_eur(1000.5) == "1.000,50 €"
    end

    test "gains carry their sign" do
      assert SummaryLive.format_abs(1234.5) == "+1.234,50 €"
      assert SummaryLive.format_abs(-1234.5) == "-1.234,50 €"
      assert SummaryLive.format_pct(1234.5) == "+1.234,50%"
      assert SummaryLive.format_pct(-3.2) == "-3,20%"
    end

    test "units keep only the decimals they need" do
      assert SummaryLive.format_qty(1234.5) == "1.234,5"
      assert SummaryLive.format_qty(0.1234) == "0,1234"
      assert SummaryLive.format_qty(100.0) == "100"
    end

    test "a missing value shows a dash" do
      assert SummaryLive.format_eur(nil) == "—"
      assert SummaryLive.format_abs(nil) == "—"
      assert SummaryLive.format_pct(nil) == "—"
    end
  end

  describe "next_sort/2" do
    test "clicking the current column reverses it" do
      assert SummaryLive.next_sort({:gain, :desc}, :gain) == {:gain, :asc}
      assert SummaryLive.next_sort({:gain, :asc}, :gain) == {:gain, :desc}
    end

    test "a new column starts largest first, names A to Z" do
      assert SummaryLive.next_sort({:asset, :asc}, :gain) == {:gain, :desc}
      assert SummaryLive.next_sort({:gain, :desc}, :asset) == {:asset, :asc}
      assert SummaryLive.next_sort({:gain, :desc}, :category) == {:category, :asc}
    end
  end
end
