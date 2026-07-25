defmodule Sheetfolio.MyinvestorEmailStore do
  @moduledoc """
  Mongo-backed cache of the MyInvestor confirmation emails, so boot doesn't have
  to refetch the whole mailbox from Gmail every time.

  Keyed by the Gmail message id, which is stable, and these emails never change
  once sent — so a stored document is never invalidated, only added to.

  What's cached is the raw HTML body (gzipped; ~24KB becomes ~3KB, and the whole
  mailbox fits in under a megabyte), not the parsed operations. Parsing all of
  them costs about 100ms, which is worth paying to keep one code path: a change
  to `MyinvestorParser` takes effect on the next restart instead of needing a
  cache rebuild.

      { _id: "18f2c...",           # Gmail message id
        subject: "CONFIRMACIÓN DE OPERACIÓN DE VALORES",
        html_gz: <BSON.Binary>,    # gzipped HTML body
        fetched_at: <DateTime> }
  """

  @collection "myinvestor_emails"

  @doc "The Gmail message ids already cached."
  def known_ids do
    Mongo.find(:mongo, @collection, %{}, projection: %{_id: 1})
    |> Enum.map(& &1["_id"])
    |> MapSet.new()
  end

  def count, do: Mongo.count!(:mongo, @collection, %{})

  @doc "Every cached email as `%{id, subject, html}`, HTML already gunzipped."
  def all do
    Mongo.find(:mongo, @collection, %{})
    |> Enum.map(fn doc ->
      %{id: doc["_id"], subject: doc["subject"], html: gunzip(doc["html_gz"])}
    end)
  end

  @doc """
  Stores `%{id, subject, html}` emails. Callers pass only ids that `known_ids/0`
  didn't already have, and `OperationsServer` never runs two syncs at once, so
  these are always genuinely new documents.
  """
  def store_many([]), do: :ok

  def store_many(emails) do
    now = DateTime.utc_now()

    docs =
      Enum.map(emails, fn email ->
        %{
          _id: email.id,
          subject: email.subject,
          html_gz: %BSON.Binary{binary: :zlib.gzip(email.html)},
          fetched_at: now
        }
      end)

    {:ok, _} = Mongo.insert_many(:mongo, @collection, docs, ordered: false)
    :ok
  end

  defp gunzip(%BSON.Binary{binary: binary}), do: :zlib.gunzip(binary)
end
