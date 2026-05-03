defmodule Sheetfolio.MyinvestorEmails do
  require Logger

  @gmail_query_operaciones "from:notificaciones@myinvestor.es subject:CONFIRMACIÓN DE OPERACIÓN DE VALORES"
  @gmail_query_traspasos "from:notificaciones@myinvestor.es subject:TRASPASO"

  @doc "Returns {:ok, [operation_map]} or {:error, reason}."
  def fetch_all do
    with {:ok, ops} <- fetch_query(@gmail_query_operaciones),
         {:ok, traspasos} <- fetch_query(@gmail_query_traspasos) do
      {:ok, ops ++ traspasos}
    end
  end

  defp fetch_query(query) do
    with {:ok, messages} <- Sheetfolio.GmailClient.search_messages(query) do
      Logger.info("[MyinvestorEmails] Found #{length(messages)} emails for: #{query}")
      operations =
        Enum.flat_map(messages, fn %{"id" => id} ->
          case fetch_and_parse(id) do
            {:ok, ops} -> ops
            {:error, reason} ->
              Logger.warning("[MyinvestorEmails] Failed to parse #{id}: #{inspect(reason)}")
              []
          end
        end)
      {:ok, operations}
    end
  end

  defp fetch_and_parse(id) do
    with {:ok, message} <- Sheetfolio.GmailClient.get_message(id),
         {:ok, subject} <- Sheetfolio.GmailClient.extract_subject(message),
         {:ok, html_body} <- Sheetfolio.GmailClient.extract_html_body(message) do
      result =
        if String.contains?(subject, "TRASPASO"),
          do: Sheetfolio.MyinvestorParser.parse_traspaso(html_body, subject),
          else: Sheetfolio.MyinvestorParser.parse(html_body, subject)

      case result do
        {:ok, ops} when is_list(ops) ->
          {:ok, Enum.map(ops, &Sheetfolio.OperationOverrides.apply/1)}
        {:ok, op} ->
          {:ok, [Sheetfolio.OperationOverrides.apply(op)]}
        error ->
          error
      end
    end
  end
end
