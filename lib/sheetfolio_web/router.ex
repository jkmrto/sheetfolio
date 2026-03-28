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

    get "/", PortfolioController, :index
    live "/operations", OperationsLive
  end
end
