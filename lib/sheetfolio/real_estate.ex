defmodule Sheetfolio.RealEstate do
  @moduledoc """
  Urbanitae and Equito combined, for the `/real-estate` overview. Both sides
  come from each platform's own `state_at/2`, so the figures here always agree
  with the per-platform pages.

  "Currently invested" is capital still in: Urbanitae's outstanding balance
  plus every Equito purchase (Equito tokens are never redeemed). Earnings are
  Urbanitae's yield and closure gains plus Equito's net rent and rewards.
  """

  alias Sheetfolio.{EquitoTransactions, UrbanitaeTransactions}

  @doc """
  Figures as of `date`, per platform and combined:

      %{urbanitae: %{invested: _, earnings: _}, equito: %{...}, total: %{...}}
  """
  def summary(urbanitae, equito, date) do
    u = state(&UrbanitaeTransactions.state_at/2, urbanitae, date)
    e = state(&EquitoTransactions.state_at/2, equito, date)

    %{
      urbanitae: u,
      equito: e,
      total: %{
        invested: round2(u.invested + e.invested),
        earnings: round2(u.earnings + e.earnings)
      }
    }
  end

  @doc """
  One combined point per date either platform has a movement on, plus
  `today`, so the lines run to the present:

      %{date: "2025-03-13", invested: 10200.00, earnings: 310.00}
  """
  def time_series(urbanitae, equito, today \\ Date.utc_today() |> Date.to_iso8601())

  def time_series([], [], _today), do: []

  def time_series(urbanitae, equito, today) do
    (urbanitae ++ equito)
    |> Enum.map(& &1["date"])
    |> Kernel.++([today])
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn date ->
      %{total: total} = summary(urbanitae, equito, date)
      Map.put(total, :date, date)
    end)
  end

  defp state(state_at, transactions, date) do
    {invested, earnings} = state_at.(transactions, date)
    %{invested: round2(invested), earnings: round2(earnings)}
  end

  defp round2(number), do: Float.round(number * 1.0, 2)
end
