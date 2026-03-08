import Config

config :sheetfolio, SheetfolioWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  debug_errors: true,
  secret_key_base: "local_dev_secret_key_base_at_least_64_chars_long_xxxxxxxxxxxxxxxx"
