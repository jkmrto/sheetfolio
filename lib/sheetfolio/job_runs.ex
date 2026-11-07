defmodule Sheetfolio.JobRuns do
  @moduledoc """
  The last outcome of each background sync, kept in Mongo so `/control` can
  tell "failed last night" from "hasn't run", even after a restart.

      { job: "urbanitae_emails",
        last_success_at: <DateTime>,
        last_failure_at: <DateTime>,
        last_error: "..." }

  Recording never raises: a sync that worked shouldn't crash because its
  bookkeeping couldn't be written.
  """

  @collection "job_runs"
  @error_length 200

  def success(job), do: put(job, %{last_success_at: DateTime.utc_now()})

  def failure(job, reason) do
    put(job, %{last_failure_at: DateTime.utc_now(), last_error: summarize(reason)})
  end

  def all do
    Mongo.find(:mongo, @collection, %{}) |> Map.new(&{&1["job"], &1})
  end

  defp put(job, fields) do
    Mongo.update_one(:mongo, @collection, %{job: job}, %{"$set" => fields}, upsert: true)
    :ok
  end

  defp summarize(reason) when is_binary(reason), do: String.slice(reason, 0, @error_length)
  defp summarize(reason), do: reason |> inspect() |> String.slice(0, @error_length)
end
