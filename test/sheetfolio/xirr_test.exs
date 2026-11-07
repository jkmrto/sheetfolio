defmodule Sheetfolio.XirrTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.Xirr

  test "matches the published spreadsheet XIRR example" do
    flows = [
      {~D[2008-01-01], -10_000.0},
      {~D[2008-03-01], 2750.0},
      {~D[2008-10-30], 4250.0},
      {~D[2009-02-15], 3250.0},
      {~D[2009-04-01], 2750.0}
    ]

    assert_in_delta Xirr.rate(flows), 0.373362535, 1.0e-6
  end

  test "doubling in exactly a year is 100%" do
    assert_in_delta Xirr.rate([{~D[2025-01-01], -100.0}, {~D[2026-01-01], 200.0}]), 1.0, 1.0e-6
  end

  test "losses give a negative rate" do
    assert_in_delta Xirr.rate([{~D[2025-01-01], -100.0}, {~D[2026-01-01], 75.0}]), -0.25, 1.0e-6
  end

  test "the order of the flows doesn't matter" do
    flows = [{~D[2026-01-01], 200.0}, {~D[2025-01-01], -100.0}]

    assert_in_delta Xirr.rate(flows), 1.0, 1.0e-6
  end

  test "money invested later weighs less" do
    early = [{~D[2024-01-01], -100.0}, {~D[2025-01-01], -100.0}, {~D[2026-01-01], 250.0}]
    late = [{~D[2024-01-01], -100.0}, {~D[2025-12-01], -100.0}, {~D[2026-01-01], 250.0}]

    assert Xirr.rate(late) > Xirr.rate(early)
  end

  test "a near-total loss stays above -100%" do
    rate = Xirr.rate([{~D[2025-01-01], -100.0}, {~D[2026-01-01], 0.5}])

    assert rate > -1.0
    assert_in_delta rate, -0.995, 1.0e-6
  end

  test "there is no rate without money both ways" do
    assert Xirr.rate([]) == nil
    assert Xirr.rate([{~D[2025-01-01], -100.0}]) == nil
    assert Xirr.rate([{~D[2025-01-01], 100.0}, {~D[2026-01-01], 100.0}]) == nil
  end
end
