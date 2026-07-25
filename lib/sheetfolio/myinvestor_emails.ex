defmodule Sheetfolio.MyinvestorEmails do
  require Logger

  alias Sheetfolio.GmailClient
  alias Sheetfolio.MyinvestorEmailStore
  alias Sheetfolio.MyinvestorParser

  @gmail_query_operaciones "from:notificaciones@myinvestor.es subject:CONFIRMACIÓN DE OPERACIÓN DE VALORES"
  @gmail_query_traspasos "from:notificaciones@myinvestor.es subject:TRASPASO"

  @concurrency 8
  @message_timeout 30_000

  @doc """
  Brings the Mongo cache up to date and returns every operation in it.

  Listing message ids is two cheap requests (100 ids per page); only ids we've
  never seen are actually downloaded. Returns {:ok, [operation_map]} or
  {:error, reason} if Gmail can't be reached — callers that already have cached
  operations should keep serving those. Optional progress/2 callback is called
  with (current, total) over the messages being downloaded.
  """
  def sync(progress \\ nil) do
    with {:ok, ids} <- list_all_ids() do
      known = MyinvestorEmailStore.known_ids()

      ids
      |> Enum.reject(&MapSet.member?(known, &1))
      |> fetch_bodies(progress)
      |> MyinvestorEmailStore.store_many()

      {:ok, cached_operations()}
    end
  end

  @doc "Every operation parseable from the cache, without touching Gmail."
  def cached_operations do
    MyinvestorEmailStore.all() |> Enum.flat_map(&parse_email/1)
  end

  @doc """
  Fetches and parses straight from Gmail, bypassing the cache and writing
  nothing. Used by `mix parse_myinvestor_emails` to exercise the parser.

  Operations come back exactly as parsed — corrections and synthetic operations
  are layered on later by `Sheetfolio.OperationHistory`.
  """
  def fetch_all(progress \\ nil) do
    with {:ok, ids} <- list_all_ids() do
      {:ok, ids |> fetch_bodies(progress) |> Enum.flat_map(&parse_email/1)}
    end
  end

  defp list_all_ids do
    with {:ok, op_ids} <- list_ids(@gmail_query_operaciones),
         {:ok, traspaso_ids} <- list_ids(@gmail_query_traspasos) do
      {:ok, op_ids ++ traspaso_ids}
    end
  end

  defp list_ids(query) do
    with {:ok, messages} <- GmailClient.search_messages(query) do
      Logger.info("[MyinvestorEmails] Found #{length(messages)} emails for: #{query}")
      {:ok, Enum.map(messages, & &1["id"])}
    end
  end

  # Downloads message bodies concurrently, returning %{id, subject, html} for
  # the ones that came back intact.
  defp fetch_bodies(ids, progress) do
    total = length(ids)

    ids
    |> Task.async_stream(&{&1, fetch_body(&1)},
      max_concurrency: @concurrency,
      timeout: @message_timeout
    )
    |> Stream.with_index(1)
    |> Enum.flat_map(fn {result, current} ->
      if progress, do: progress.(current, total)
      body_from(result)
    end)
  end

  defp fetch_body(id) do
    with {:ok, message} <- GmailClient.get_message(id),
         {:ok, subject} <- GmailClient.extract_subject(message),
         {:ok, html} <- GmailClient.extract_html_body(message) do
      {:ok, %{id: id, subject: subject, html: html}}
    end
  end

  defp body_from({:ok, {_id, {:ok, email}}}), do: [email]

  defp body_from({:ok, {id, {:error, reason}}}) do
    Logger.warning("[MyinvestorEmails] Failed to fetch #{id}: #{inspect(reason)}")
    []
  end

  defp body_from({:exit, reason}) do
    Logger.warning("[MyinvestorEmails] Message fetch crashed: #{inspect(reason)}")
    []
  end

  defp parse_email(%{id: id, subject: subject, html: html}) do
    result =
      if String.contains?(subject, "TRASPASO"),
        do: MyinvestorParser.parse_traspaso(html, subject),
        else: MyinvestorParser.parse(html, subject)

    ops_from(result, id)
  end

  defp ops_from({:ok, ops}, _id) when is_list(ops), do: ops
  defp ops_from({:ok, op}, _id), do: [op]

  defp ops_from({:error, reason}, id) do
    Logger.warning("[MyinvestorEmails] Failed to parse #{id}: #{inspect(reason)}")
    []
  end
end
