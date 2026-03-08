run:
	export $$(sed 's|~/|$(HOME)/|g' .env | xargs) && iex -S mix phx.server
