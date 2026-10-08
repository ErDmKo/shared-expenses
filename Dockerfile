# syntax=docker/dockerfile:1
FROM elixir:1.20.4-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl git pkg-config libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod ERL_FLAGS="+S 1:1 +A 1"

RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs mix.lock ./
COPY config/ config/
RUN mix deps.get --only prod && mix deps.compile

COPY lib/ lib/
COPY priv/ priv/
COPY assets/ assets/
ARG TARGETARCH
RUN mix compile \
    && case "$TARGETARCH" in amd64) esbuild_arch=x64 ;; arm64) esbuild_arch=arm64 ;; *) exit 1 ;; esac \
    && curl --fail --location --retry 3 --connect-timeout 10 --max-time 90 \
      "https://registry.npmjs.org/@esbuild/linux-${esbuild_arch}/-/linux-${esbuild_arch}-0.25.4.tgz" \
      --output /tmp/esbuild.tgz \
    && tar -xzf /tmp/esbuild.tgz -C /tmp package/bin/esbuild \
    && install -m 0755 /tmp/package/bin/esbuild "/app/_build/esbuild-linux-${esbuild_arch}" \
    && rm -rf /tmp/package /tmp/esbuild.tgz \
    && mix assets.setup && mix assets.deploy && mix release

FROM debian:trixie-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl libncurses6 libsctp1 libsqlite3-0 libssl3t64 libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 app \
    && useradd --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app \
    && mkdir -p /app/data \
    && chown app:app /app/data

WORKDIR /app
COPY --from=build --chown=app:app /app/_build/prod/rel/shared_expenses/ ./

ENV HOME=/app LANG=C.UTF-8 LC_ALL=C.UTF-8 PHX_SERVER=true PORT=4000
USER app
EXPOSE 4000
CMD ["bin/shared_expenses", "start"]
