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

  describe "weight/2" do
    test "is the position's share of what's held" do
      assert SummaryLive.weight(25.0, 100.0) == 25.0
      assert SummaryLive.weight(1.0, 3.0) == 33.33
    end

    test "stays blank without a price or anything held" do
      assert SummaryLive.weight(nil, 100.0) == nil
      assert SummaryLive.weight(10.0, 0) == nil
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
