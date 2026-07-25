defmodule Sheetfolio.GmailClient do
  @base_url "https://gmail.googleapis.com/gmail/v1/users/me"

  def search_messages(query) do
    with {:ok, token} <- fetch_token() do
      fetch_all_pages(query, token, nil, [])
    end
  end

  defp fetch_all_pages(query, token, page_token, acc) do
    url = "#{@base_url}/messages"
    params = [q: query, maxResults: 100] ++ if(page_token, do: [pageToken: page_token], else: [])

    case Req.get(url, auth: {:bearer, token}, params: params) do
      {:ok, %{status: 200, body: body}} ->
        messages = body["messages"] || []
        fetch_next_page(body["nextPageToken"], query, token, acc ++ messages)

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_next_page(nil, _query, _token, acc), do: {:ok, acc}
  defp fetch_next_page(next_token, query, token, acc), do: fetch_all_pages(query, token, next_token, acc)

  def get_message(id) do
    with {:ok, token} <- fetch_token() do
      url = "#{@base_url}/messages/#{id}"

      case Req.get(url, auth: {:bearer, token}, params: [format: "full"]) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{status: status, body: body}} -> {:error, {status, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def extract_subject(message) do
    headers = get_in(message, ["payload", "headers"]) || []

    case Enum.find(headers, &(&1["name"] == "Subject")) do
      %{"value" => subject} -> {:ok, subject}
      nil -> {:error, "No subject header found"}
    end
  end

  def extract_html_body(message) do
    case find_html_part(message["payload"]) do
      nil -> {:error, "No HTML body found"}
      data -> {:ok, Base.url_decode64!(data, padding: false)}
    end
  end

  defp find_html_part(%{"mimeType" => "text/html", "body" => %{"data" => data}}), do: data

  defp find_html_part(%{"parts" => parts}) when is_list(parts) do
    Enum.find_value(parts, &find_html_part/1)
  end

  defp find_html_part(_), do: nil

  defp fetch_token, do: Sheetfolio.GmailToken.fetch()
end
