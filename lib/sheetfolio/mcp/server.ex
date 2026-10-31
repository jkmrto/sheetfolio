defmodule Sheetfolio.Mcp.Server do
  @moduledoc """
  The Model Context Protocol's JSON-RPC layer, as served on `POST /mcp`.

  Stateless: every request stands alone, so there are no sessions to track and
  the Streamable HTTP transport reduces to one JSON response per POST. The
  tools themselves live in `Sheetfolio.Mcp.Tools`.
  """

  alias Sheetfolio.Mcp.Tools

  # Newest first: an unknown client version gets the newest one back.
  @versions ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

  @instructions """
  Read-only access to a personal investment portfolio. Amounts are in EUR.
  Operation dates (`fecha`) are dd/mm/yyyy; every other date is YYYY-MM-DD.
  Spanish field names come from the broker's emails: tipo (operation type),
  cantidad (units), precio (price), importe (amount), traspaso (fund-to-fund
  transfer).
  """

  @doc """
  The response to one JSON-RPC message: `{:reply, map}`, or `:accepted` for a
  notification or a client response, which get no body.
  """
  def handle(%{"jsonrpc" => "2.0", "method" => method, "id" => id} = message) do
    {:reply, respond(id, call(method, Map.get(message, "params") || %{}))}
  end

  def handle(%{"jsonrpc" => "2.0", "method" => _notification}), do: :accepted
  def handle(%{"jsonrpc" => "2.0", "id" => _response}), do: :accepted
  def handle(_message), do: {:reply, error(nil, -32_600, "Invalid request")}

  defp call("initialize", params) do
    {:ok,
     %{
       protocolVersion: version(params["protocolVersion"]),
       capabilities: %{tools: %{listChanged: false}},
       serverInfo: %{name: "sheetfolio", version: to_string(Application.spec(:sheetfolio, :vsn))},
       instructions: @instructions
     }}
  end

  defp call("ping", _params), do: {:ok, %{}}
  defp call("tools/list", _params), do: {:ok, %{tools: Tools.definitions()}}

  defp call("tools/call", %{"name" => name} = params) do
    tool_result(name, Tools.call(name, Map.get(params, "arguments") || %{}))
  end

  defp call("tools/call", _params), do: {:error, -32_602, "Missing tool name"}
  defp call(method, _params), do: {:error, -32_601, "Method not found: #{method}"}

  defp version(requested) when requested in @versions, do: requested
  defp version(_requested), do: hd(@versions)

  # A bad argument is reported inside the result, so the model sees it and can
  # retry; an unknown tool is a protocol error.
  defp tool_result(_name, {:ok, data}),
    do: {:ok, %{content: [text(Jason.encode!(data))], isError: false}}

  defp tool_result(_name, {:error, message}),
    do: {:ok, %{content: [text(message)], isError: true}}

  defp tool_result(name, :unknown), do: {:error, -32_602, "Unknown tool: #{name}"}

  defp text(string), do: %{type: "text", text: string}

  defp respond(id, {:ok, result}), do: %{jsonrpc: "2.0", id: id, result: result}
  defp respond(id, {:error, code, message}), do: error(id, code, message)

  defp error(id, code, message),
    do: %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
end
