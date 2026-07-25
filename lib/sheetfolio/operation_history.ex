defmodule Sheetfolio.OperationHistory do
  @moduledoc """
  Turns the raw operations parsed out of Gmail into the history the app reports
  on: per-`{fecha, isin}` corrections from `OperationOverrides`, plus the
  hardcoded `SyntheticOperations` for emails that never arrived, minus anything
  an override marks `skip: true`.

  Applied when the history is served rather than when the emails are fetched, so
  editing the overrides needs a restart, not a Gmail refetch.
  """

  alias Sheetfolio.OperationOverrides
  alias Sheetfolio.SyntheticOperations

  def patch(operations) do
    operations
    |> Enum.map(&OperationOverrides.apply/1)
    |> Kernel.++(SyntheticOperations.all())
    |> Enum.reject(&Map.get(&1, :skip, false))
  end
end
