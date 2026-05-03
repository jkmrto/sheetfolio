defmodule Sheetfolio.MyinvestorParser do
  @subject_pattern ~r/# (\d{2}\/\d{2}\/\d{4}) # ([^#]+?) # ([^#]+?) # TIT:/

  def parse_traspaso(html_body, subject) do
    isins =
      Regex.scan(~r/C&oacute;digo ISIN: ([A-Z0-9]{12})/, html_body)
      |> Enum.map(fn [_, isin] -> isin end)

    case isins do
      [reemb_isin, suscr_isin | _] ->
        with {:ok, fecha} <- extract_fecha(html_body),
             {:ok, suscr_asset} <- extract_traspaso_asset(subject),
             {:ok, {cantidad, precio, importe_bruto}} <- extract_traspaso_amounts(html_body),
             {:ok, importe_neto} <- extract_traspaso_importe_neto(html_body) do
          reemb_asset = extract_reemb_asset(html_body, reemb_isin)

          compra = %{
            fecha: fecha, asset: suscr_asset, isin: suscr_isin,
            tipo: "Suscripcion", cantidad: cantidad, precio: precio,
            importe_without_comision: importe_bruto, comision: "",
            importe_with_comision: importe_neto, traspaso: true
          }

          venta = %{
            fecha: fecha, asset: reemb_asset, isin: reemb_isin,
            tipo: "Reembolso", cantidad: "", precio: "",
            importe_without_comision: importe_bruto, comision: "",
            importe_with_comision: importe_bruto, traspaso: true
          }

          {:ok, [compra, venta]}
        end

      _ ->
        {:error, "Expected 2 ISINs in traspaso email, found: #{length(isins)}"}
    end
  end

  def parse(html_body, subject) do
    with {:ok, asset} <- extract_asset(html_body, subject),
         {:ok, isin} <- extract_isin(html_body),
         {:ok, tipo} <- extract_tipo(html_body, subject),
         {:ok, fecha} <- extract_fecha(html_body),
         {:ok, {cantidad, precio, importe_without_comision}} <- extract_amounts(html_body),
         {:ok, comision} <- extract_comision(html_body),
         {:ok, importe_with_comision} <- extract_importe_with_comision(html_body) do
      {:ok, %{
        fecha: fecha,
        asset: asset,
        isin: isin,
        tipo: tipo,
        cantidad: cantidad,
        precio: precio,
        importe_without_comision: importe_without_comision,
        comision: comision,
        importe_with_comision: importe_with_comision,
        traspaso: false
      }}
    end
  end

  # Funds:  "FIDELITY S&amp;P 500 INDEX P ACC EUR - <br>"
  # Stocks: "WISDOMTREE BITCOIN - WBIT GR<br>"
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

  defp extract_isin(html) do
    case Regex.run(~r/C&oacute;digo ISIN: ([A-Z0-9]{12})/, html) do
      [_, isin] -> {:ok, isin}
      nil -> {:error, "Could not extract ISIN"}
    end
  end

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

  defp extract_fecha(html) do
    case Regex.run(~r/valign="top">(\d{2}\/\d{2}\/\d{4})<\/td>/, html) do
      [_, fecha] -> {:ok, fecha}
      nil -> {:error, "Could not extract date"}
    end
  end

  defp extract_amounts(html) do
    pattern =
      ~r/valign="top">([\d,.]+)<\/td>.*?valign="top">([\d,.]+)&nbsp;([A-Z]+)<\/td>.*?valign="top">([\d,.]+)&nbsp;([A-Z]+)<\/td>/s

    case Regex.run(pattern, html) do
      [_, cantidad, precio, precio_currency, importe, importe_currency] ->
        {:ok, {cantidad, precio <> " " <> precio_currency, importe <> " " <> importe_currency}}
      nil ->
        {:error, "Could not extract amounts"}
    end
  end

  defp extract_importe_with_comision(html) do
    pattern = ~r/Importe Efectivo Neto.*?valign="top">([\d,.]+)&nbsp;([A-Z]+)/s

    case Regex.run(pattern, html) do
      [_, amount, currency] -> {:ok, amount <> " " <> currency}
      nil -> {:error, "Could not extract Importe Efectivo Neto"}
    end
  end

  defp extract_comision(html) do
    pattern = ~r/<strong>Comisiones<\/strong>.*?valign="top">([\d.]+)&nbsp;([A-Z]+)<\/td>/s

    case Regex.run(pattern, html) do
      [_, comision, currency] -> {:ok, comision <> " " <> currency}
      nil -> {:ok, ""}
    end
  end

  defp extract_traspaso_asset(subject) do
    case Regex.run(~r/TRASPASO DE IIC (.+)$/i, subject) do
      [_, asset] -> {:ok, String.trim(asset)}
      nil -> {:error, "Could not extract asset from traspaso subject"}
    end
  end

  defp extract_reemb_asset(html, reemb_isin) do
    pattern = ~r/>([A-Z][^<]{4,60})<(?:br|BR)[\s\/]*>\s*C&oacute;digo ISIN: #{Regex.escape(reemb_isin)}/
    case Regex.run(pattern, html) do
      [_, asset] -> html_decode(String.trim(asset))
      nil -> reemb_isin
    end
  end

  defp extract_traspaso_amounts(html) do
    pattern =
      ~r/valign="top">([\d,.]+)<\/td>.*?valign="top">([\d,.]+)&nbsp;([A-Z]+)<\/td>.*?valign="top">([\d,.]+)&nbsp;([A-Z]+)<\/td>/s

    case Regex.run(pattern, html) do
      [_, cantidad, precio, precio_cur, importe, importe_cur] ->
        {:ok, {cantidad, precio <> " " <> precio_cur, importe <> " " <> importe_cur}}
      nil ->
        {:error, "Could not extract traspaso amounts"}
    end
  end

  defp extract_traspaso_importe_neto(html) do
    case Regex.run(~r/Importe Neto.*?valign="top">([\d,.]+)&nbsp;([A-Z]+)/s, html) do
      [_, amount, currency] -> {:ok, amount <> " " <> currency}
      nil -> {:error, "Could not extract Importe Neto"}
    end
  end

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
