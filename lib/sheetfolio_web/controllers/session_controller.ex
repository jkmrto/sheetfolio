defmodule SheetfolioWeb.SessionController do
  use SheetfolioWeb, :controller

  alias Sheetfolio.LoginThrottle

  def new(conn, _params) do
    render(conn, :new, error: nil)
  end

  def create(conn, %{"password" => password}) do
    address = client_address(conn)

    if LoginThrottle.allowed?(address) do
      check_password(conn, password, address)
    else
      conn
      |> put_status(:too_many_requests)
      |> render(:new, error: "Too many attempts. Try again later.")
    end
  end

  defp check_password(conn, password, address) do
    expected = Application.fetch_env!(:sheetfolio, :app_password)

    if Plug.Crypto.secure_compare(password, expected) do
      LoginThrottle.succeeded(address)

      conn
      |> configure_session(renew: true)
      |> put_session(:authenticated, true)
      |> redirect(to: "/")
    else
      LoginThrottle.failed(address)
      render(conn, :new, error: "Invalid password")
    end
  end

  # Fly's proxy sits in front of the app, so remote_ip is the same for every
  # visitor. It sets this header itself and overwrites any value a client sends.
  defp client_address(conn) do
    case get_req_header(conn, "fly-client-ip") do
      [address | _] -> address
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
