defmodule Sheetfolio.MyinvestorParser do
  @moduledoc """
  Parses MyInvestor operation confirmation emails.
  Primary source: HTML body. Falls back to email subject for tipo and asset.
  """

  @subject_pattern ~r/# (\d{2}\/\d{2}\/\d{4}) # ([^#]+?) # ([^#]+?) # TIT:/

  def parse(html_body, subject) do
    with {:ok, asset} <- extract_asset(html_body, subject),
         {:ok, isin} <- extract_isin(html_body),
         {:ok, tipo} <- extract_tipo(html_body, subject),
         {:ok, fecha} <- extract_fecha(html_body),
         {:ok, {cantidad, precio, importe_without_comision}} <- extract_amounts(html_body),
         {:ok, comision} <- extract_comision(html_body),
         {:ok, importe_with_comision} <- extract_importe_with_comision(html_body) do
      {:ok,
       %{
         fecha: fecha,
         asset: asset,
         isin: isin,
         tipo: tipo,
         cantidad: cantidad,
         precio: precio,
         importe_without_comision: importe_without_comision,
         comision: comision,
         importe_with_comision: importe_with_comision
       }}
    end
  end

  # Funds:  "FIDELITY S&amp;P 500 INDEX P ACC EUR - <br>"
  # Stocks: "WISDOMTREE BITCOIN - WBIT GR<br>"
  # Both formats: asset name is always before " - "
  defp extract_asset(html, subject) do
    case Regex.run(~r/valign="top" colspan="3">([^<]+?) - /s, html) do
      [_, asset] ->
        {:ok, html_decode(String.trim(asset))}

      nil ->
        case subject_parts(subject) do
          {_, _, asset} -> {:ok, String.trim(asset)}
          nil -> {:error, "Could not extract asset name"}
        end
    end
  end

  # "Código ISIN: IE00BYX5MX67"
  defp extract_isin(html) do
    case Regex.run(~r/C&oacute;digo ISIN: ([A-Z0-9]{12})/, html) do
      [_, isin] -> {:ok, isin}
      nil -> {:error, "Could not extract ISIN"}
    end
  end

  # "SUSCRIPCION I.I.C.", "COMPRA", "REEMBOLSO", "VENTA"
  # Falls back to subject if not found in HTML
  defp extract_tipo(html, subject) do
    pattern = ~r/valign="top">(SUSCRIPCION[^<]*|COMPRA|REEMBOLSO[^<]*|VENTA[^<]*)<\/td>/

    case Regex.run(pattern, html) do
      [_, tipo] ->
        {:ok, normalize_tipo(String.trim(tipo))}

      nil ->
        case subject_parts(subject) do
          {_, tipo, _} -> {:ok, normalize_tipo(String.trim(tipo))}
          nil -> {:error, "Could not extract operation type"}
        end
    end
  end

  # First date in the detail section is Fecha Operación
  defp extract_fecha(html) do
    case Regex.run(~r/valign="top">(\d{2}\/\d{2}\/\d{4})<\/td>/, html) do
      [_, fecha] -> {:ok, fecha}
      nil -> {:error, "Could not extract date"}
    end
  end

  # Units, price, importe_without_comision appear together in one table row
  defp extract_amounts(html) do
    pattern =
      ~r/valign="top">([\d,.]+)<\/td>.*?valign="top">([\d,.]+)&nbsp;([A-Z]+)<\/td>.*?valign="top">([\d,.]+)&nbsp;([A-Z]+)<\/td>/s

    case Regex.run(pattern, html) do
      [_, cantidad, precio, precio_currency, importe_without_comision, importe_without_comision_currency] ->
        {:ok, {cantidad, precio <> " " <> precio_currency, importe_without_comision <> " " <> importe_without_comision_currency}}

      nil ->
        {:error, "Could not extract amounts"}
    end
  end

  # "Importe Efectivo Neto" — what was actually charged/received
  defp extract_importe_with_comision(html) do
    pattern = ~r/Importe Efectivo Neto.*?valign="top">([\d,.]+)&nbsp;([A-Z]+)/s

    case Regex.run(pattern, html) do
      [_, amount, currency] -> {:ok, amount <> " " <> currency}
      nil -> {:error, "Could not extract Importe Efectivo Neto"}
    end
  end

  # Commission is the first currency value after the "Comisiones" label
  defp extract_comision(html) do
    pattern = ~r/<strong>Comisiones<\/strong>.*?valign="top">([\d.]+)&nbsp;([A-Z]+)<\/td>/s

    case Regex.run(pattern, html) do
      [_, comision, currency] -> {:ok, comision <> " " <> currency}
      nil -> {:ok, ""}
    end
  end

  # Parses subject: "... # DATE # TYPE # ASSET # TIT: ..."
  defp subject_parts(subject) do
    case Regex.run(@subject_pattern, subject) do
      [_, _date, tipo, asset] -> {nil, tipo, asset}
      nil -> nil
    end
  end

  defp normalize_tipo("SUSCRIPCION" <> _), do: "Suscripcion"
  defp normalize_tipo("COMPRA"), do: "Compra"
  defp normalize_tipo("REEMBOLSO" <> _), do: "Reembolso"
  defp normalize_tipo("VENTA" <> _), do: "Venta"
  defp normalize_tipo(tipo), do: tipo

  defp html_decode(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&apos;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&nbsp;", " ")
  end
end
