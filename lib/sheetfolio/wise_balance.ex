defmodule Sheetfolio.WiseBalance do
  @moduledoc """
  Total money held in the Wise account, converted to EUR.
  """

  require Logger

  alias Sheetfolio.PricesApi.YahooFinance
  alias Sheetfolio.WiseClient

  @doc "Returns {:ok, float} or {:error, reason} if Wise can't be reached."
  def current_eur do
    with {:ok, profiles} <- WiseClient.profiles(),
         {:ok, profile} <- first_profile(profiles),
         {:ok, balances} <- WiseClient.balances(profile["id"]) do
      {:ok, sum_eur(balances, rates_for(balances))}
    end
  end

  defp first_profile([profile | _]), do: {:ok, profile}
  defp first_profile([]), do: {:error, :no_wise_profile}

  @doc """
  Sums Wise balances into EUR. `rates` maps currency code => value of 1 EUR in
  that currency (Yahoo's `EUR<CUR>=X` convention); EUR itself needs no entry.
  A balance in a currency missing from `rates`, or that is exactly zero, is
  skipped.
  """
  def sum_eur(balances, rates) do
    balances
    |> Enum.reject(&zero?/1)
    |> Enum.reduce(0.0, &(balance_eur(&1, rates) + &2))
    |> Float.round(2)
  end

  defp zero?(%{"amount" => %{"value" => value}}), do: value == 0

  defp balance_eur(%{"amount" => %{"value" => value, "currency" => "EUR"}}, _rates), do: value

  defp balance_eur(%{"amount" => %{"value" => value, "currency" => currency}}, rates) do
    case Map.fetch(rates, currency) do
      {:ok, rate} -> value / rate
      :error -> 0.0
    end
  end

  # eur_usd/eur_cad come from EarningsServer's cache (no extra HTTP call);
  # any other currency present is looked up live and dropped with a warning
  # if Yahoo has no rate for it. Zero balances (most of the account's travel
  # currencies) are skipped before this, so this is rarely more than one or
  # two lookups.
  defp rates_for(balances) do
    {eur_usd, eur_cad} = Sheetfolio.EarningsServer.get_fx_rates()
    base = %{"USD" => eur_usd, "CAD" => eur_cad}

    balances
    |> Enum.reject(&zero?/1)
    |> Enum.map(& &1["amount"]["currency"])
    |> Enum.uniq()
    |> Enum.reject(&(&1 in ["EUR", "USD", "CAD"]))
    |> Enum.reduce(base, &fetch_rate/2)
  end

  defp fetch_rate(currency, rates) do
    case YahooFinance.fetch_price("EUR#{currency}=X") do
      {:ok, rate, _} ->
        Map.put(rates, currency, rate)

      _ ->
        Logger.warning("[WiseBalance] Could not fetch EUR#{currency}=X rate, skipping that balance")
        rates
    end
  end
end
