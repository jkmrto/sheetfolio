defmodule Sheetfolio.MyinvestorEmails do
  require Logger

  @gmail_query "from:notificaciones@myinvestor.es subject:CONFIRMACIÓN DE OPERACIÓN DE VALORES"

  @doc "Returns {:ok, [operation_map]} or {:error, reason}."
  def fetch_all do
    with {:ok, messages} <- Sheetfolio.GmailClient.search_messages(@gmail_query) do
      operations =
        Enum.flat_map(messages, fn %{"id" => id} ->
          case fetch_and_parse(id) do
            {:ok, data} -> [data]
            {:error, reason} ->
              Logger.warning("[MyinvestorEmails] Failed to parse email #{id}: #{inspect(reason)}")
              []
          end
        end)

      {:ok, operations}
    end
  end

  defp fetch_and_parse(id) do
    with {:ok, message} <- Sheetfolio.GmailClient.get_message(id),
         {:ok, subject} <- Sheetfolio.GmailClient.extract_subject(message),
         {:ok, html_body} <- Sheetfolio.GmailClient.extract_html_body(message),
         {:ok, data} <- Sheetfolio.MyinvestorParser.parse(html_body, subject) do
      {:ok, data}
    end
  end
end
