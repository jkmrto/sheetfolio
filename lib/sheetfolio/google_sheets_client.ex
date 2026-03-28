defmodule Sheetfolio.GoogleSheetsClient do
  @base_url "https://sheets.googleapis.com/v4/spreadsheets"

  def get_sheet_data(spreadsheet_id, range) do
    with {:ok, token} <- fetch_token(),
         {:ok, response} <- do_request(spreadsheet_id, range, token) do
      {:ok, response.body}
    end
  end

  def get_all_values(spreadsheet_id, sheet_name) do
    get_sheet_data(spreadsheet_id, sheet_name)
  end

  def update_cells(spreadsheet_id, range, values) do
    with {:ok, token} <- fetch_token() do
      url = "#{@base_url}/#{spreadsheet_id}/values/#{URI.encode(range)}"

      body = %{"range" => range, "majorDimension" => "ROWS", "values" => values}

      case Req.put(url, auth: {:bearer, token}, json: body, params: [valueInputOption: "USER_ENTERED"]) do
        {:ok, %{status: 200} = response} -> {:ok, response.body}
        {:ok, %{status: status, body: body}} -> {:error, {status, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  def append_rows(spreadsheet_id, sheet_name, rows) do
    with {:ok, token} <- fetch_token() do
      range = URI.encode(sheet_name)
      url = "#{@base_url}/#{spreadsheet_id}/values/#{range}:append"
      params = [valueInputOption: "USER_ENTERED", insertDataOption: "INSERT_ROWS"]

      case Req.post(url, auth: {:bearer, token}, json: %{"values" => rows}, params: params) do
        {:ok, %{status: 200} = response} -> {:ok, response.body}
        {:ok, %{status: status, body: body}} -> {:error, {status, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fetch_token do
    case Goth.fetch(Sheetfolio.Goth) do
      {:ok, %{token: token}} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_request(spreadsheet_id, range, token) do
    url = "#{@base_url}/#{spreadsheet_id}/values/#{URI.encode(range)}"

    case Req.get(url, auth: {:bearer, token}) do
      {:ok, %{status: 200} = response} -> {:ok, response}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
