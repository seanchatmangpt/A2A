# =============================================================================
# Craftplan A2A Agent Dockerfile
# Multi-stage build for Erlang/OTP A2A agent
# =============================================================================

# ============================================================================
# Stage 1: Builder
# ============================================================================
FROM erlang:27-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    curl \
    make \
    gcc

WORKDIR /build

# Copy rebar.config and src
COPY rebar.config.lock .
COPY rebar.config .
COPY src/ ./src/
COPY include/ ./include/

# Build the release
RUN rebar3 compile
RUN rebar3 release -s craftplan_a2a

# ============================================================================
# Stage 2: Runtime
# ============================================================================
FROM alpine:3.19 AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    libstdc++ \
    curl \
    bash

WORKDIR /app

# Copy the release from builder
COPY --from=builder /build/_build/default/rel/craftplan_a2a/ .

# Copy agent card for discovery
COPY agent-card/agent-card.json /app/priv/agent-card.json

# Create non-root user
RUN addgroup -g 1000 craftplan && \
    adduser -D -u 1000 -G craftplan craftplan && \
    chown -R craftplan:craftplan /app

USER craftplan

# Expose A2A port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Set environment defaults
ENV A2A_PORT=8080 \
    MCP_SERVER_URL=http://craftplan-mcp-server:8090/mcp \
    AGENT_ID=craftplan-erp-agent \
    LOG_LEVEL=info

# Run the application
CMD ["./bin/craftplan_a2a", "foreground"]
