run:
	export $$(sed 's|~/|$(HOME)/|g' .env | xargs) && iex -S mix phx.server

wise-operations:
	export $$(sed 's|~/|$(HOME)/|g' .env | xargs) && mix wise_operations

docker-build:
	docker build -t sheetfolio .

generate-gmail-token:
	python scripts/generate_gmail_token.py client_secret_email_app.json
	@echo "Now run: fly secrets set GMAIL_REFRESH_TOKEN=<refresh_token> --app sheetfolio"
