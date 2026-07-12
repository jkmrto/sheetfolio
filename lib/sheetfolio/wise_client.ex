defmodule Sheetfolio.WiseClient do
  @moduledoc """
  Wise API client, auth via WISE_API_TOKEN. Balance statements are not available:
  Wise dropped API request signing (SCA) for personal accounts under PSD2, so
  operations are read from the activities endpoint instead.
  """

  @base_url "https://api.transferwise.com"

  def profiles, do: get("/v2/profiles")

  def balances(profile_id), do: get("/v4/profiles/#{profile_id}/balances?types=STANDARD")

  def activity(profile_id, activity_id) do
    get("/v1/profiles/#{profile_id}/activities/#{activity_id}")
  end

  def activities(profile_id, %DateTime{} = since) do
    activities(profile_id, since, nil, [])
  end

  defp activities(profile_id, since, cursor, acc) do
    query = "?size=100&since=#{DateTime.to_iso8601(since)}" <> cursor_param(cursor)

    case get("/v1/profiles/#{profile_id}/activities" <> query) do
      {:ok, %{"activities" => activities, "cursor" => next}} when is_binary(next) and activities != [] ->
        activities(profile_id, since, next, acc ++ activities)

      {:ok, %{"activities" => activities}} ->
        {:ok, acc ++ activities}

      error ->
        error
    end
  end

  defp cursor_param(nil), do: ""
  defp cursor_param(cursor), do: "&nextCursor=#{URI.encode_www_form(cursor)}"

  defp get(path) do
    headers = [{"authorization", "Bearer #{System.fetch_env!("WISE_API_TOKEN")}"}]

    case Req.get(@base_url <> path, headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
