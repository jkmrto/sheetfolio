defmodule SheetfolioWeb.Router do
  use SheetfolioWeb, :router

  # No inline scripts anywhere, so scripts are limited to the bundle and the two
  # pinned Chart.js files. Styles stay inline: every LiveView carries its own
  # <style> block and style attributes.
  @csp Enum.join(
         [
           "default-src 'self'",
           "script-src 'self' https://cdn.jsdelivr.net",
           "style-src 'self' 'unsafe-inline'",
           "img-src 'self' data:",
           "connect-src 'self'",
           "object-src 'none'",
           "base-uri 'self'",
           "form-action 'self'",
           "frame-ancestors 'none'"
         ],
         "; "
       )

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @csp}
    plug :put_root_layout, html: {SheetfolioWeb.Layouts, :root}
  end

  pipeline :auth do
    plug SheetfolioWeb.AuthPlug
  end

  # Model Context Protocol for AI clients, behind a bearer token rather than
  # the browser session. Read-only.
  pipeline :mcp do
    plug SheetfolioWeb.McpAuthPlug
  end

  scope "/mcp", SheetfolioWeb do
    pipe_through :mcp

    post "/", McpController, :handle
    get "/", McpController, :no_stream
    delete "/", McpController, :no_session
  end

  scope "/", SheetfolioWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
  end

  scope "/", SheetfolioWeb do
    pipe_through [:browser, :auth]

    live "/", PortfolioLive
    live "/loading", LoadingLive
    live "/control", ControlLive
    live "/history", HistoryLive
    live "/comparison", ComparisonLive
    live "/cash", CashLive
    live "/expenses", ExpensesLive
    live "/urbanitae", UrbanitaeLive
    live "/equito", EquitoLive

    live_session :authenticated, on_mount: [{SheetfolioWeb.LoadingHook, :default}] do
      live "/earnings", EarningsLive
      live "/operations", OperationsLive
      live "/summary", SummaryLive, :active
      live "/summary/settled", SummaryLive, :settled
      live "/summary/dca", DcaLive
      live "/summary/dca/bitcoin", DcaBitcoinLive
      live "/bitcoin", BitcoinLive
    end
  end
end
