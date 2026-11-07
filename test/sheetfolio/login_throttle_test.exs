defmodule Sheetfolio.LoginThrottleTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.LoginThrottle, as: Throttle

  @now 1_000_000
  @window 15 * 60

  defp fail_times(failures \\ [], address, times, at \\ @now) do
    Enum.reduce(1..times, failures, fn _, acc -> Throttle.record(acc, address, at) end)
  end

  test "an address is allowed four wrong passwords, and blocked after five" do
    assert Throttle.permitted?(fail_times("1.1.1.1", 4), "1.1.1.1", @now)
    refute Throttle.permitted?(fail_times("1.1.1.1", 5), "1.1.1.1", @now)
  end

  test "one blocked address doesn't affect another" do
    assert Throttle.permitted?(fail_times("1.1.1.1", 5), "2.2.2.2", @now)
  end

  test "guesses spread over many addresses still hit the global limit" do
    failures = Enum.reduce(1..30, [], &Throttle.record(&2, "10.0.0.#{&1}", @now))

    refute Throttle.permitted?(failures, "9.9.9.9", @now)
  end

  test "a block lifts once the failures leave the window" do
    failures = fail_times("1.1.1.1", 5)

    refute Throttle.permitted?(failures, "1.1.1.1", @now + @window - 1)
    assert Throttle.permitted?(failures, "1.1.1.1", @now + @window)
  end

  test "old failures are dropped when a new one is recorded" do
    failures = fail_times("1.1.1.1", 5)

    assert [{"1.1.1.1", _}] = Throttle.record(failures, "1.1.1.1", @now + @window)
  end

  test "a correct password clears only that address" do
    failures = fail_times("1.1.1.1", 3) |> fail_times("2.2.2.2", 2)

    assert [{"2.2.2.2", _}, {"2.2.2.2", _}] = Throttle.clear(failures, "1.1.1.1")
  end
end
