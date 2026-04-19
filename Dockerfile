FROM elixir:1.19.5-otp-28-alpine AS build

WORKDIR /app

RUN apk add --no-cache build-base git

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN MIX_ENV=prod mix deps.get --only prod

COPY config config
COPY lib lib
COPY priv priv

RUN MIX_ENV=prod mix release

FROM elixir:1.19.5-otp-28-alpine AS runtime

WORKDIR /app

RUN apk add --no-cache libstdc++ openssl ncurses-libs

COPY --from=build /app/_build/prod/rel/sheetfolio ./

ENV PHX_SERVER=true

CMD ["/app/bin/sheetfolio", "start"]
