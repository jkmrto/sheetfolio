defmodule Sheetfolio.OperationOverrides do
  # Keyed by {fecha, isin}. Fields set here replace what the email parser returns.
  # Use skip: true to exclude an operation from earnings calculation entirely.
  @overrides %{
    {"09/01/2026", "US8629451027"} => %{cantidad: "141", precio: "19.85 USD"},
    # Traspaso from Vanguard US 500 (IE0032126645) into Fidelity. Email records
    # the NAV at transfer (20,233.76 EUR) but the original cost basis carried over
    # from the source fund was 21,233.76 EUR (some early subscriptions predate email history).
    {"09/10/2025", "IE00BYX5MX67"} => %{importe_with_comision: "21233.76 EUR"}
  }

  def apply(data) do
    case Map.get(@overrides, {data.fecha, data.isin}) do
      nil -> data
      override -> Map.merge(data, override)
    end
  end
end
