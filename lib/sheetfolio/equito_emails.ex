defmodule Sheetfolio.EquitoEmails do
  @moduledoc """
  Records Equito's monthly rent payouts from Gmail. Only the rent emails are
  fetched (about one a month), and each row is checked against
  `EquitoTransactions.find_matching/1` before insert, so re-running is safe
  and months already ingested from screenshots are left alone.
  """

  require Logger

  alias Sheetfolio.EquitoParser
  alias Sheetfolio.EquitoTransactions
  alias Sheetfolio.GmailClient

  @gmail_query ~s(from:contact@equito.app subject:"renta de tus propiedades")

  @doc "Inserts any emailed payout not yet recorded. Returns `{:ok, inserted_count}`."
  def sync do
    with {:ok, messages} <- GmailClient.search_messages(@gmail_query) do
      now = DateTime.utc_now()

      new =
        messages
        |> Enum.flat_map(&fetch_transactions(&1["id"]))
        |> Enum.filter(&is_nil(EquitoTransactions.find_matching(&1)))
        |> Enum.map(&Map.put(&1, :captured_at, now))

      :ok = EquitoTransactions.insert_many(new)
      {:ok, length(new)}
    end
  end

  defp fetch_transactions(id) do
    with {:ok, message} <- GmailClient.get_message(id),
         {:ok, subject} <- GmailClient.extract_subject(message),
         {:ok, html} <- GmailClient.extract_html_body(message) do
      subject
      |> EquitoParser.parse(html, GmailClient.extract_date(message))
      |> transactions_from(id)
    else
      {:error, reason} -> transactions_from({:error, inspect(reason)}, id)
    end
  end

  defp transactions_from({:ok, transactions}, _id), do: transactions
  defp transactions_from(:ignore, _id), do: []

  defp transactions_from({:error, reason}, id) do
    Logger.warning("[EquitoEmails] Skipped #{id}: #{reason}")
    []
  end
end
