defmodule Sheetfolio.Mcp.ServerTest do
  use ExUnit.Case, async: true

  alias Sheetfolio.Mcp.Server

  defp request(method, params \\ %{}) do
    {:reply, response} =
      Server.handle(%{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params})

    response
  end

  describe "initialize" do
    test "echoes a supported protocol version" do
      assert %{result: %{protocolVersion: "2025-06-18"}} =
               request("initialize", %{"protocolVersion" => "2025-06-18"})
    end

    test "answers an unknown version with the newest one" do
      assert %{result: %{protocolVersion: "2025-11-25", capabilities: %{tools: _}}} =
               request("initialize", %{"protocolVersion" => "1999-01-01"})
    end
  end

  test "notifications and client responses get no reply" do
    assert :accepted =
             Server.handle(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

    assert :accepted = Server.handle(%{"jsonrpc" => "2.0", "id" => 7, "result" => %{}})
  end

  test "rejects a message that isn't JSON-RPC 2.0, including a batch" do
    assert {:reply, %{id: nil, error: %{code: -32_600}}} = Server.handle(%{"_json" => []})
  end

  test "ping" do
    assert %{id: 1, result: %{}} = request("ping")
  end

  test "an unknown method is a protocol error" do
    assert %{error: %{code: -32_601}} = request("resources/list")
  end

  describe "tools/list" do
    test "lists every tool as a read-only object schema" do
      %{result: %{tools: tools}} = request("tools/list")

      assert length(tools) == 9

      for tool <- tools do
        assert %{inputSchema: %{type: "object"}, annotations: %{readOnlyHint: true}} = tool
      end
    end

    test "the definitions encode as JSON" do
      assert {:ok, _json} = Jason.encode(request("tools/list"))
    end
  end

  describe "tools/call" do
    test "an unknown tool is a protocol error" do
      assert %{error: %{code: -32_602}} = request("tools/call", %{"name" => "delete_everything"})
    end

    test "a bad argument comes back as a tool error, before any I/O" do
      assert %{result: %{isError: true, content: [%{text: "from must be a YYYY-MM-DD string"}]}} =
               request("tools/call", %{
                 "name" => "get_portfolio_history",
                 "arguments" => %{"from" => "yesterday"}
               })

      assert %{result: %{isError: true, content: [%{text: "limit must be" <> _}]}} =
               request("tools/call", %{
                 "name" => "list_operations",
                 "arguments" => %{"limit" => 0}
               })

      assert %{result: %{isError: true}} =
               request("tools/call", %{
                 "name" => "get_positions",
                 "arguments" => %{"include_closed" => "yes"}
               })

      assert %{result: %{isError: true}} =
               request("tools/call", %{"name" => "get_expenses", "arguments" => "everything"})
    end
  end
end
