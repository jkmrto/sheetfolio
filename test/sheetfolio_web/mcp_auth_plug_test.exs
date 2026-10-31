defmodule SheetfolioWeb.McpAuthPlugTest do
  # Swaps the :mcp_token application env, so not async.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias SheetfolioWeb.McpAuthPlug

  setup do
    previous = Application.get_env(:sheetfolio, :mcp_token)
    on_exit(fn -> Application.put_env(:sheetfolio, :mcp_token, previous) end)
  end

  defp call(header, token) do
    Application.put_env(:sheetfolio, :mcp_token, token)
    conn = conn(:post, "/mcp")
    conn = if header, do: put_req_header(conn, "authorization", header), else: conn
    McpAuthPlug.call(conn, [])
  end

  test "lets the right bearer token through" do
    refute call("Bearer s3cret", "s3cret").halted
  end

  test "refuses a wrong or missing token with a Bearer challenge" do
    for header <- ["Bearer nope", "s3cret", nil] do
      conn = call(header, "s3cret")
      assert conn.halted
      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") == [~s(Bearer realm="sheetfolio")]
    end
  end

  test "refuses everything when no token is configured" do
    assert call("Bearer ", "").status == 401
    assert call("Bearer ", nil).status == 401
  end
end
