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

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  # The layout links /assets/app.js unversioned, so without this browsers are
  # free to keep serving a cached bundle after a deploy — a new LiveView hook
  # then silently never arrives and its chart renders blank. Revalidating on
  # every request costs one 304 and makes a deploy take effect immediately.
  plug Plug.Static,
    at: "/assets",
    from: {:sheetfolio, "priv/static/assets"},
    gzip: false,
    cache_control_for_etags: "public, no-cache"

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.Session, @session_options

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug SheetfolioWeb.Router
end
