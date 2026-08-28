defmodule Sheetfolio.UrbanitaeEmailStore do
  @moduledoc """
  Mongo-backed cache of the Urbanitae mail, so the daily check and the
  `/urbanitae` page don't refetch the whole mailbox from Gmail.

  Same shape and reasoning as `Sheetfolio.MyinvestorEmailStore`: keyed by the
  Gmail message id, storing the gzipped HTML rather than the parsed event, so
  a change to `UrbanitaeParser` takes effect on the next restart instead of
  needing a cache rebuild. Marketing mail is cached too — it's most of the
  mailbox, and remembering that we've already seen and dismissed it is what
  keeps the daily sync down to a couple of Gmail calls.

      { _id: "1a025cda31014699",
        subject: "Proyecto Cerrado con éxito",
        date: "2026-08-21",
        html_gz: <BSON.Binary>,
        fetched_at: <DateTime> }
  """

  @collection "urbanitae_emails"

  @doc "The Gmail message ids already cached."
  def known_ids do
    Mongo.find(:mongo, @collection, %{}, projection: %{_id: 1})
    |> Enum.map(& &1["_id"])
    |> MapSet.new()
  end

  def count, do: Mongo.count!(:mongo, @collection, %{})

  @doc "Every cached email as `%{id, subject, date, html}`, HTML already gunzipped."
  def all do
    Mongo.find(:mongo, @collection, %{})
    |> Enum.map(fn doc ->
      %{id: doc["_id"], subject: doc["subject"], date: doc["date"], html: gunzip(doc["html_gz"])}
    end)
  end

  def store_many([]), do: :ok

  def store_many(emails) do
    now = DateTime.utc_now()

    docs =
      Enum.map(emails, fn email ->
        %{
          _id: email.id,
          subject: email.subject,
          date: email.date,
          html_gz: %BSON.Binary{binary: :zlib.gzip(email.html)},
          fetched_at: now
        }
      end)

    {:ok, _} = Mongo.insert_many(:mongo, @collection, docs, ordered: false)
    :ok
  end

  defp gunzip(%BSON.Binary{binary: binary}), do: :zlib.gunzip(binary)
end
