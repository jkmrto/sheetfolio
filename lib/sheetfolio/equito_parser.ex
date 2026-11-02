defmodule Sheetfolio.EquitoParser do
  @moduledoc """
  Parses the monthly rent email Equito sends (`contact@equito.app`,
  "¡…, acabas de recibir la renta de tus propiedades!"). Its table carries one
  row per property:

      Propiedad  Pago    Retenido*  Distribuido
      EQT-0072   1.42 €  0.26 €     1.16 €

  Each row becomes the same RENTA / RET. FISCAL pair the app's Historial shows,
  in the shape `Sheetfolio.EquitoTransactions` stores, so an emailed payout
  and a screenshotted one share a natural key and never double up.

  Purchases aren't emailed, so they still come from screenshots. Everything
  else from the sender is marketing and parses to `:ignore`.
  """

  @rent_subject "acabas de recibir la renta de tus propiedades"

  # Amounts are written with a decimal point ("1.42 €"), not es-ES commas.
  @row ~r/(EQT-\d+)\s+(\d+\.\d{2})\s*€\s+(\d+\.\d{2})\s*€\s+\d+\.\d{2}\s*€/u

  @doc """
  Returns `{:ok, transactions}`, `:ignore` for anything that isn't a rent
  email, or `{:error, reason}` when a rent email has no table rows. `date` is
  the ISO date the email arrived, which is the payout date.
  """
  def parse(subject, html, date) do
    parse_rent(String.contains?(subject, @rent_subject), text(html), date)
  end

  defp parse_rent(false, _text, _date), do: :ignore

  defp parse_rent(true, text, date) do
    case Regex.scan(@row, text, capture: :all_but_first) do
      [] -> {:error, "No property rows in: #{String.slice(text, 0, 120)}"}
      rows -> {:ok, Enum.flat_map(rows, &transactions(&1, date))}
    end
  end

  defp transactions([code, pago, retenido], date) do
    [
      %{
        date: date,
        code: code,
        kind: "rent",
        tokens: nil,
        amount: String.to_float(pago),
        raw_label: "RENTA"
      },
      %{
        date: date,
        code: code,
        kind: "tax",
        tokens: nil,
        amount: -String.to_float(retenido),
        raw_label: "RET. FISCAL"
      }
    ]
  end

  defp text(html) do
    html
    |> String.replace(~r/<(style|head|script)[\s\S]*?<\/\1>/i, " ")
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(["&euro;", "&nbsp;"], fn
      "&euro;" -> "€"
      "&nbsp;" -> " "
    end)
    |> String.replace(~r/\s+/u, " ")
  end
end
