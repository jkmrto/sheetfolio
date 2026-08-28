defmodule Sheetfolio.UrbanitaeEmails do
  @moduledoc """
  Fetches the Urbanitae mail from Gmail and runs it through
  `Sheetfolio.UrbanitaeParser`. The events are a cross-check for the
  screenshot-fed `urbanitae_transactions` collection, not a replacement for it
  — see `Sheetfolio.UrbanitaePending` for what that check surfaces.
  """

  require Logger

  alias Sheetfolio.GmailClient
  alias Sheetfolio.UrbanitaeEmailStore
  alias Sheetfolio.UrbanitaeParser

  @gmail_query "from:contacto@urbanitae.com"

  @concurrency 8
  @message_timeout 30_000

  @doc """
  Brings the Mongo cache up to date and returns every event in it. Only ids we
  have never seen are downloaded, so a daily run is two listing requests and
  usually nothing else.
  """
  def sync(progress \\ nil) do
    with {:ok, messages} <- GmailClient.search_messages(@gmail_query) do
      known = UrbanitaeEmailStore.known_ids()

      messages
      |> Enum.map(& &1["id"])
      |> Enum.reject(&MapSet.member?(known, &1))
      |> fetch_bodies(progress)
      |> UrbanitaeEmailStore.store_many()

      {:ok, cached_events()}
    end
  end

  @doc "Every event parseable from the cache, without touching Gmail."
  def cached_events do
    {events, _ignored} = parse_all(UrbanitaeEmailStore.all())
    events
  end

  @doc """
  Every event parseable from the Urbanitae inbox, oldest first. Returns
  `{:ok, {events, ignored_count}}` — the count is how many marketing mails
  were skipped, which is most of them.
  """
  def fetch_all(progress \\ nil) do
    with {:ok, messages} <- GmailClient.search_messages(@gmail_query) do
      Logger.info("[UrbanitaeEmails] Found #{length(messages)} emails")

      {:ok,
       messages
       |> Enum.map(& &1["id"])
       |> fetch_bodies(progress)
       |> parse_all()}
    end
  end

  defp parse_all(emails) do
    {events, ignored} = Enum.reduce(emails, {[], 0}, &collect/2)
    {Enum.sort_by(events, & &1.date), ignored}
  end

  defp collect(email, {events, ignored}) do
    case UrbanitaeParser.parse(email.subject, email.html, email.date) do
      {:ok, event} ->
        {[event | events], ignored}

      :ignore ->
        {events, ignored + 1}

      {:error, reason} ->
        Logger.warning("[UrbanitaeEmails] Failed to parse #{email.id}: #{reason}")
        {events, ignored}
    end
  end

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
      {:ok, %{id: id, subject: subject, html: html, date: GmailClient.extract_date(message)}}
    end
  end

  defp body_from({:ok, {_id, {:ok, email}}}), do: [email]

  defp body_from({:ok, {id, {:error, reason}}}) do
    Logger.warning("[UrbanitaeEmails] Failed to fetch #{id}: #{inspect(reason)}")
    []
  end

  defp body_from({:exit, reason}) do
    Logger.warning("[UrbanitaeEmails] Message fetch crashed: #{inspect(reason)}")
    []
  end
end
