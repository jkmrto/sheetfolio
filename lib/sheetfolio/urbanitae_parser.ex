defmodule Sheetfolio.UrbanitaeParser do
  @moduledoc """
  Parses the transactional emails Urbanitae sends (`contacto@urbanitae.com`).
  Three subjects carry information; the rest of the inbox is `Cuenta atrás…`
  and `Direct Investments` marketing, which parses to `:ignore`.

      "Tu inversión se ha realizado con éxito" -> :investment   city, project, amount
      "Proyecto Cerrado con éxito"             -> :funded       city, project, amount
      "Ingreso de inversión"                   -> :distribution project, repayment_kind

  A distribution email announces the payout but never says what *you* received
  — it only names the project and whether this is a quarterly rent/interest
  payment or the final liquidation. So distributions carry a date and a
  `repayment_kind` but no amount; the amount still has to come from a
  Movimientos screenshot.
  """

  @investment_subject "Tu inversión se ha realizado con éxito"
  @funded_subject "Proyecto Cerrado con éxito"
  @distribution_subject "Ingreso de inversión"

  # "Nombre del proyecto: Valencia | Proyecto Pérez Galdós Cantidad invertida: 5.000€"
  @investment ~r/Nombre del proyecto:\s*(.+?)\s*\|\s*Proyecto\s+(.+?)\s+Cantidad invertida:\s*([\d.,]+)\s*€/u

  # "el proyecto Lisboa | Proyecto Tomás Ribeiro en el que has invertido 1.000€"
  @funded ~r/el proyecto\s+(.+?)\s*\|\s*Proyecto\s+(.+?)\s+en el que has invertido\s+([\d.,]+)\s*€/u

  # "Proyecto Pérez Galdós | Liquidación trimestral de rentas"
  @distribution ~r/Proyecto\s+(.+?)\s*\|\s*Liquidación\s+(trimestral de rentas|del proyecto)/u

  @entities %{
    "&aacute;" => "á",
    "&eacute;" => "é",
    "&iacute;" => "í",
    "&oacute;" => "ó",
    "&uacute;" => "ú",
    "&ntilde;" => "ñ",
    "&Aacute;" => "Á",
    "&Eacute;" => "É",
    "&Iacute;" => "Í",
    "&Oacute;" => "Ó",
    "&Uacute;" => "Ú",
    "&Ntilde;" => "Ñ",
    "&uuml;" => "ü",
    "&euro;" => "€",
    "&amp;" => "&",
    "&nbsp;" => " ",
    "&#39;" => "'"
  }

  @doc """
  Turns one email into an event map, `:ignore` for the marketing mail, or
  `{:error, reason}` when a known subject doesn't parse. `date` is the ISO
  date the email arrived.
  """
  def parse(subject, html, date) do
    parse_kind(kind(subject), text(html), date)
  end

  @doc "Which of the three transactional shapes this subject is, if any."
  def kind(subject) do
    cond do
      String.contains?(subject, @investment_subject) -> :investment
      String.contains?(subject, @funded_subject) -> :funded
      String.contains?(subject, @distribution_subject) -> :distribution
      true -> :ignored
    end
  end

  defp parse_kind(:ignored, _text, _date), do: :ignore

  defp parse_kind(:investment, text, date) do
    case Regex.run(@investment, text) do
      [_, city, project, amount] -> holding_event(:investment, city, project, amount, date)
      nil -> {:error, "No investment line in: #{excerpt(text)}"}
    end
  end

  defp parse_kind(:funded, text, date) do
    case Regex.run(@funded, text) do
      [_, city, project, amount] -> holding_event(:funded, city, project, amount, date)
      nil -> {:error, "No funded line in: #{excerpt(text)}"}
    end
  end

  defp parse_kind(:distribution, text, date) do
    case Regex.run(@distribution, text) do
      [_, project, tipo] -> {:ok, distribution_event(String.trim(project), tipo, text, date)}
      nil -> {:error, "No liquidación heading in: #{excerpt(text)}"}
    end
  end

  defp holding_event(kind, city, project, amount, date) do
    case parse_amount(amount) do
      {:ok, amount} ->
        {:ok,
         %{
           kind: kind,
           date: date,
           city: String.trim(city),
           project: String.trim(project),
           amount: amount
         }}

      :error ->
        {:error, "Could not parse amount: #{amount}"}
    end
  end

  defp distribution_event(project, tipo, text, date) do
    %{
      kind: :distribution,
      date: date,
      city: distribution_city(text, project),
      project: project,
      repayment_kind: repayment_kind(tipo)
    }
  end

  defp repayment_kind("trimestral de rentas"), do: "yield"
  defp repayment_kind("del proyecto"), do: "principal"

  # The heading omits the city, but the body usually repeats the project as
  # "del Proyecto Valencia | Pérez Galdós". Liquidation mails often don't.
  defp distribution_city(text, project) do
    case Regex.run(~r/Proyecto\s+([^|]+?)\s*\|\s*#{Regex.escape(project)}/u, text) do
      [_, city] -> String.trim(city)
      nil -> nil
    end
  end

  # Urbanitae writes es-ES only: "1.170,39" is one thousand one hundred seventy.
  defp parse_amount(str) do
    case str |> String.replace(".", "") |> String.replace(",", ".") |> Float.parse() do
      {amount, _} -> {:ok, amount}
      :error -> :error
    end
  end

  defp text(html) do
    html
    |> String.replace(~r/<(style|head|script)[\s\S]*?<\/\1>/i, " ")
    |> String.replace(~r/<[^>]+>/, " ")
    |> html_decode()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp html_decode(text) do
    Enum.reduce(@entities, text, fn {entity, char}, acc ->
      String.replace(acc, entity, char)
    end)
  end

  defp excerpt(text), do: String.slice(text, 0, 120)
end
