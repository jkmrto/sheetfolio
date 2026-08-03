defmodule SheetfolioWeb.Router do
  use SheetfolioWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_root_layout, html: {SheetfolioWeb.Layouts, :root}
  end

  pipeline :auth do
    plug SheetfolioWeb.AuthPlug
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
