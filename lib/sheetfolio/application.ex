defmodule Sheetfolio.Application do
  use Application

  @impl true
  def start(_type, _args) do
    credentials = Application.fetch_env!(:sheetfolio, :google_credentials)

    source = {:service_account, credentials, scopes: ["https://www.googleapis.com/auth/spreadsheets"]}

    children = [
      {Goth, name: Sheetfolio.Goth, source: source},
      Sheetfolio.EarningsServer,
      SheetfolioWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
