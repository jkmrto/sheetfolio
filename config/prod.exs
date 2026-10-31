import Config

# Fly terminates TLS and forwards plain HTTP, so trust its x-forwarded-proto
# rather than redirecting every request; HSTS keeps browsers on HTTPS.
config :sheetfolio, SheetfolioWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto], hsts: true]
