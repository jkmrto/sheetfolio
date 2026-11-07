defmodule Sheetfolio.Xirr do
  @moduledoc """
  Money-weighted annual return: the rate at which a series of dated cash flows
  nets to zero, the same definition as a spreadsheet's XIRR. Money going in is
  negative, money coming out positive. Unlike a simple gain percentage it
  accounts for when each euro was invested.
  """

  @lowest_rate -0.9999
  @highest_rate 1.0e6
  @iterations 200
  @days_in_year 365.0

  @doc """
  The annual rate as a fraction (`0.12` is 12%), or `nil` when no rate exists:
  a return needs money both going in and coming out.
  """
  def rate(flows) do
    if solvable?(flows), do: solve(flows), else: nil
  end

  defp solvable?(flows) do
    Enum.any?(flows, &(elem(&1, 1) > 0)) and Enum.any?(flows, &(elem(&1, 1) < 0))
  end

  # Bisection rather than Newton: slower, but it can't diverge or escape below
  # -100%, which matters for a young position with a large move.
  defp solve(flows) do
    first = flows |> Enum.map(&elem(&1, 0)) |> Enum.min(Date)
    timed = Enum.map(flows, fn {date, amount} -> {Date.diff(date, first) / @days_in_year, amount} end)

    if bracketed?(timed), do: bisect(timed, @lowest_rate, @highest_rate, @iterations), else: nil
  end

  defp bracketed?(timed) do
    net_value(timed, @lowest_rate) * net_value(timed, @highest_rate) < 0
  end

  defp bisect(_timed, low, high, 0), do: (low + high) / 2

  defp bisect(timed, low, high, steps) do
    middle = (low + high) / 2

    if net_value(timed, low) * net_value(timed, middle) <= 0 do
      bisect(timed, low, middle, steps - 1)
    else
      bisect(timed, middle, high, steps - 1)
    end
  end

  defp net_value(timed, rate) do
    Enum.reduce(timed, 0.0, fn {years, amount}, acc -> acc + amount / :math.pow(1 + rate, years) end)
  end
end
