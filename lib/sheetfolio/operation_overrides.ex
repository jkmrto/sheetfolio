defmodule Sheetfolio.OperationOverrides do
  # Keyed by {fecha, isin}. Fields set here replace what the email parser returns.
  # Use skip: true to exclude an operation from earnings calculation entirely.
  @overrides %{
    {"09/01/2026", "US8629451027"} => %{cantidad: "141", precio: "19.85 USD"}
  }

  def apply(data) do
    case Map.get(@overrides, {data.fecha, data.isin}) do
      nil -> data
      override -> Map.merge(data, override)
    end
  end
end
