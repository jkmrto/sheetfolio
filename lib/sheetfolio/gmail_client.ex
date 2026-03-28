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
        all = acc ++ messages

        case body["nextPageToken"] do
          nil -> {:ok, all}
          next_token -> fetch_all_pages(query, token, next_token, all)
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

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

  defp fetch_token do
    config = load_token_config()
    refresh_access_token(config)
  end

  defp load_token_config do
    %{
      "client_id" => System.fetch_env!("GMAIL_CLIENT_ID"),
      "client_secret" => System.fetch_env!("GMAIL_CLIENT_SECRET"),
      "refresh_token" => System.fetch_env!("GMAIL_REFRESH_TOKEN")
    }
  end

  defp refresh_access_token(config) do
    body = [
      grant_type: "refresh_token",
      refresh_token: config["refresh_token"],
      client_id: config["client_id"],
      client_secret: config["client_secret"]
    ]

    case Req.post("https://oauth2.googleapis.com/token", form: body) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} -> {:ok, token}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
