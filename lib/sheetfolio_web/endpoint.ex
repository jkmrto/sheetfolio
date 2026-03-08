defmodule SheetfolioWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :sheetfolio

  plug Plug.RequestId
  plug Plug.Logger

  @session_options [
    store: :cookie,
    key: "_sheetfolio_session",
    signing_salt: "sheetfolio_salt",
    same_site: "Lax"
  ]

  plug Plug.Session, @session_options

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug SheetfolioWeb.Router
end
