defmodule Sheetfolio.HistoricalFxTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.HistoricalFx

  describe "resolve/3" do
    test "a weekend takes the last rate published before it" do
      usd = %{~D[2026-01-09] => 1.16}
      cad = %{~D[2026-01-09] => 1.62}

      assert HistoricalFx.resolve([~D[2026-01-11]], usd, cad) == %{~D[2026-01-11] => {1.16, 1.62}}
    end

    test "a date one series can't cover is left out" do
      usd = %{~D[2026-01-09] => 1.16}

      assert HistoricalFx.resolve([~D[2026-01-09]], usd, %{}) == %{}
    end
  end

  describe "pin/2" do
    test "attaches rates to the dates it knows and leaves the rest alone" do
      known = %{fecha: "09/01/2026"}
      unknown = %{fecha: "10/01/2026"}

      assert HistoricalFx.pin([known, unknown], %{~D[2026-01-09] => {1.16, 1.62}}) == [
               %{fecha: "09/01/2026", fx_usd: 1.16, fx_cad: 1.62},
               unknown
             ]
    end
  end
end
