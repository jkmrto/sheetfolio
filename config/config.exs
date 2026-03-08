import Config

config :sheetfolio, SheetfolioWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: SheetfolioWeb.ErrorHTML], layout: false]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
