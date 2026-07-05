defmodule Sheetfolio.MyinvestorEmails do
  require Logger

  @gmail_query_operaciones "from:notificaciones@myinvestor.es subject:CONFIRMACIÓN DE OPERACIÓN DE VALORES"
  @gmail_query_traspasos "from:notificaciones@myinvestor.es subject:TRASPASO"

  @doc "Returns {:ok, [operation_map]} or {:error, reason}. Optional progress/2 callback called with (current, total)."
  def fetch_all(progress \\ nil) do
    with {:ok, op_ids} <- list_ids(@gmail_query_operaciones),
         {:ok, traspaso_ids} <- list_ids(@gmail_query_traspasos) do
      all_ids = op_ids ++ traspaso_ids
      total = length(all_ids)

      ops =
        all_ids
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {id, current} ->
          if progress, do: progress.(current, total)

          case fetch_and_parse(id) do
            {:ok, ops} -> ops
            {:error, reason} ->
              Logger.warning("[MyinvestorEmails] Failed to parse #{id}: #{inspect(reason)}")
              []
          end
        end)

      {:ok, ops}
    end
  end

  defp list_ids(query) do
    with {:ok, messages} <- Sheetfolio.GmailClient.search_messages(query) do
      Logger.info("[MyinvestorEmails] Found #{length(messages)} emails for: #{query}")
      {:ok, Enum.map(messages, & &1["id"])}
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
