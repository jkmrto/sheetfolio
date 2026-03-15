defmodule Sheetfolio.PricesApi.OpenFigi do
  require Logger

  @url "https://api.openfigi.com/v3/mapping"

  @doc """
  Resolves an ISIN to a ticker via OpenFIGI.
  Returns {:ok, ticker} using the first result, or {:error, reason}.
  Optionally set OPENFIGI_API_KEY env var for higher rate limits.
  """
  def resolve_ticker(isin) do
    headers = build_headers()

    case Req.post(@url, json: [%{"idType" => "ID_ISIN", "idValue" => isin}], headers: headers) do
      {:ok, %{status: 200, body: [%{"data" => [%{"ticker" => ticker} | _]} | _]}} ->
        Logger.debug("[OpenFigi] ISIN #{isin} resolved to ticker #{ticker}")
        {:ok, ticker}

      {:ok, %{status: 200, body: body}} ->
        Logger.warning("[OpenFigi] No ticker found for ISIN #{isin}: #{inspect(body)}")
        {:error, {:no_ticker, isin}}

      {:ok, %{status: 429}} ->
        Logger.warning("[OpenFigi] Rate limited for ISIN #{isin}")
        {:error, :rate_limited}

      {:ok, %{status: status}} ->
        Logger.warning("[OpenFigi] HTTP #{status} for ISIN #{isin}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("[OpenFigi] Error for ISIN #{isin}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_headers do
    case System.get_env("OPENFIGI_API_KEY") do
      nil -> []
      key -> [{"X-OPENFIGI-APIKEY", key}]
    end
  end
end
