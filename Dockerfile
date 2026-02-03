# =============================================================================
# Multi-Stage Dockerfile for A2A Erlang/OTP Application
# =============================================================================
FROM erlang:27-alpine AS builder

ARG VERSION=0.1.0

RUN apk add --no-cache git curl openssl-dev build-base

WORKDIR /build

COPY rebar.config rebar.lock ./

RUN mkdir -p _build/default/lib && mkdir -p _build/prod/lib

RUN rebar3 get-deps && rebar3 compile

COPY src/ ./src/
COPY include/ ./include/
COPY config/ ./config/

RUN rebar3 as prod release

RUN test -x _build/prod/rel/a2a_erl/bin/a2a_erl || (echo "Release build failed!" && exit 1)

FROM erlang:27-alpine AS runtime

RUN apk add --no-cache curl ca-certificates bash

RUN addgroup -g 1000 a2a && adduser -D -u 1000 -G a2a -s /bin/bash -h /opt/a2a_erl a2a

WORKDIR /opt/a2a_erl

COPY --from=builder --chown=a2a:a2a /build/_build/prod/rel/a2a_erl/ ./

RUN mkdir -p log data && chmod 755 log data

ENV PORT=8080 \
    HOST=localhost \
    SCHEME=http

EXPOSE 8080

# Use foreground mode directly without distribution
ENTRYPOINT ["bin/a2a_erl", "foreground"]
CMD []
