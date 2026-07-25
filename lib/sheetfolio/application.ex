defmodule Sheetfolio.Application do
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(children(), strategy: :one_for_one)
  end

  # Tests exercise the pure calculation layer, so they start nothing external.
  defp children do
    if Application.get_env(:sheetfolio, :start_services, true), do: services(), else: []
  end

  defp services do
    credentials = Application.fetch_env!(:sheetfolio, :google_credentials)

    source = {:service_account, credentials, scopes: ["https://www.googleapis.com/auth/spreadsheets"]}

    [
      # Google service-account auth for the Sheets API
      {Goth, name: Sheetfolio.Goth, source: source},
      # MongoDB Atlas connection, used for portfolio snapshot history
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
      # Runs the price/FX fetches that EarningsServer must not block on
      {Task.Supervisor, name: Sheetfolio.TaskSupervisor},
      # Caches the Gmail OAuth access token so every API call doesn't refresh it
      Sheetfolio.GmailToken,
      # Caches current/historical prices and FX rates, computes earnings on demand
      Sheetfolio.EarningsServer,
      # Loads all operations from MyInvestor Gmail emails at boot, serves them from memory
      Sheetfolio.OperationsServer,
      # Writes a daily portfolio snapshot to MongoDB (boot + 22:00 UTC)
      Sheetfolio.SnapshotRecorder,
      # Phoenix HTTP endpoint
      SheetfolioWeb.Endpoint
    ]
  end
end
