import Config

credentials =
  case System.get_env("GOOGLE_CREDENTIALS_JSON") do
    nil ->
      path =
        System.get_env("GOOGLE_APPLICATION_CREDENTIALS") ||
          raise "Missing GOOGLE_CREDENTIALS_JSON or GOOGLE_APPLICATION_CREDENTIALS"

      path |> File.read!() |> Jason.decode!()

    json ->
      Jason.decode!(json)
  end

config :sheetfolio, google_credentials: credentials

app_password = System.get_env("APP_PASSWORD", "")
config :sheetfolio, app_password: app_password

spreadsheet_id =
  System.get_env("SPREADSHEET_ID") ||
    raise "Missing SPREADSHEET_ID environment variable"

config :sheetfolio, spreadsheet_id: spreadsheet_id

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "Missing SECRET_KEY_BASE environment variable"

  port = String.to_integer(System.get_env("PORT") || "4000")
  host = System.get_env("PHX_HOST") || "sheetfolio.fly.dev"

  config :sheetfolio, SheetfolioWeb.Endpoint,
    server: true,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
