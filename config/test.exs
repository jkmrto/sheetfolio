import Config

# Tests cover the pure calculation layer, so nothing external starts: no Mongo,
# no Gmail, no price fetching, no HTTP endpoint. runtime.exs skips its secret
# lookups in this environment for the same reason.
config :sheetfolio, start_services: false

config :sheetfolio, SheetfolioWeb.Endpoint,
  server: false,
  secret_key_base: "test_secret_key_base_at_least_64_chars_long_xxxxxxxxxxxxxxxxxxxx"

config :logger, level: :warning
