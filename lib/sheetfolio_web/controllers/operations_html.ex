defmodule SheetfolioWeb.OperationsHTML do
  use SheetfolioWeb, :html

  embed_templates "operations_html/*"

  # Columns 9 (Ganancia €) and 10 (Ganancia %) get color
  def earnings_style(idx, value) when idx in [9, 10] and value != "" do
    case Float.parse(value) do
      {v, _} when v >= 0 -> "color: #16a34a; font-weight: 600;"  # green-700
      {_, _} -> "color: #dc2626; font-weight: 600;"              # red-600
      :error -> ""
    end
  end
  def earnings_style(_, _), do: ""
end
