defmodule Sheetfolio.OperationHistory do
  @moduledoc """
  Turns the raw operations parsed out of Gmail into the history the app reports
  on: per-`{fecha, isin}` corrections from `OperationOverrides`, plus the
  recorded `SyntheticOperations` for what Gmail never saw, minus anything an
  override marks `skip: true`.

  Applied when the history is served rather than when the emails are fetched, so
  editing the overrides needs a restart, not a Gmail refetch.
  """

  alias Sheetfolio.OperationOverrides
  alias Sheetfolio.SyntheticOperations

  def patch(operations), do: patch(operations, SyntheticOperations.all())

  @doc """
  The synthetic operations are passed in so the patching itself can be
  exercised without the collection they normally come from.
  """
  def patch(operations, synthetic) do
    operations
    |> Enum.map(&OperationOverrides.apply/1)
    |> Kernel.++(synthetic)
    |> Enum.reject(&Map.get(&1, :skip, false))
  end
end
