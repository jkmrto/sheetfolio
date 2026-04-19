defmodule Sheetfolio.MyinvestorEmails do
  require Logger

  @gmail_query "from:notificaciones@myinvestor.es subject:CONFIRMACIÓN DE OPERACIÓN DE VALORES"

  @doc "Sends {:loading_started, total}, {:email_loaded, data}, and :loading_done to pid as emails are parsed."
  def stream_to(pid) do
    with {:ok, messages} <- Sheetfolio.GmailClient.search_messages(@gmail_query) do
      total = length(messages)
      send(pid, {:loading_started, total})

      messages
      |> Enum.with_index(1)
      |> Enum.each(fn {%{"id" => id}, idx} ->
        Logger.info("[MyinvestorEmails] Loading email #{idx}/#{total}")

        case fetch_and_parse(id) do
          {:ok, data} -> send(pid, {:email_loaded, Sheetfolio.OperationOverrides.apply(data)})
          {:error, reason} ->
            Logger.warning("[MyinvestorEmails] Failed to parse email #{id}: #{inspect(reason)}")
        end
      end)

      send(pid, :loading_done)
    else
      error ->
        Logger.error("[MyinvestorEmails] Failed to fetch emails: #{inspect(error)}")
        send(pid, {:loading_error, inspect(error)})
    end
  end

  @doc "Returns {:ok, [operation_map]} or {:error, reason}."
  def fetch_all do
    with {:ok, messages} <- Sheetfolio.GmailClient.search_messages(@gmail_query) do
      total = length(messages)
      Logger.info("[MyinvestorEmails] Found #{total} emails, loading...")

      operations =
        messages
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {%{"id" => id}, _idx} ->
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
      {:ok, Sheetfolio.OperationOverrides.apply(data)}
    end
  end
end
