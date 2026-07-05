defmodule Sheetfolio.Application do
  use Application

  @impl true
  def start(_type, _args) do
    credentials = Application.fetch_env!(:sheetfolio, :google_credentials)

    source = {:service_account, credentials, scopes: ["https://www.googleapis.com/auth/spreadsheets"]}

    children = [
      {Goth, name: Sheetfolio.Goth, source: source},
      {Mongo,
       [
         name: :mongo,
         url: Application.fetch_env!(:sheetfolio, :mongodb_uri),
         pool_size: 2,
         ssl_opts: [
           verify: :verify_peer,
           cacerts: :public_key.cacerts_get(),
           customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
         ]
       ]},
      Sheetfolio.EarningsServer,
      Sheetfolio.OperationsServer,
      Sheetfolio.SnapshotRecorder,
      SheetfolioWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
