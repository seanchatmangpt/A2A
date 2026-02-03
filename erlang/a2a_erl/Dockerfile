# =============================================================================
# Multi-Stage Dockerfile for A2A Erlang/OTP 28 Application
# =============================================================================
# This Dockerfile uses a multi-stage build to create a minimal production image
# for the A2A Agent-to-Agent Protocol implementation.
#
# Requirements:
# - Erlang/OTP 28 or later
# - rebar3 build system
# - Production release with Cowboy HTTP server
#
# Build: docker build -t a2a-erl:0.1.0 .
# Run: docker run -p 8080:8080 a2a-erl:0.1.0
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: BUILDER - Compile and build production release
# -----------------------------------------------------------------------------
FROM ghcr.io/erlef/ubuntu-otp-build:ubuntu-24.04-otp-28 AS builder

# Set build arguments
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION=0.1.0

# Set environment labels
LABEL maintainer="A2A Project" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.title="A2A Erlang/OTP Implementation" \
      org.opencontainers.image.description="Agent-to-Agent Protocol in Erlang/OTP 28"

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Verify OTP 28 installation
RUN erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell

# Set working directory
WORKDIR /build

# Copy dependency management files first for better Docker caching
COPY rebar.config rebar.lock ./

# Create directory structure for rebar3
RUN mkdir -p _build/default/lib && \
    mkdir -p _build/prod/lib

# Compile dependencies (layer caching)
RUN rebar3 get-deps && \
    rebar3 compile

# Copy application source code
COPY src/ ./src/
COPY include/ ./include/
COPY config/ ./config/

# Build production release
# This creates a complete, self-contained release in _build/prod/rel/a2a_erl
RUN rebar3 as prod release

# Verify release was built successfully
RUN test -x _build/prod/rel/a2a_erl/bin/a2a_erl || \
    (echo "Release build failed!" && exit 1)

# Display release info for debugging
RUN _build/prod/rel/a2a_erl/bin/a2a_erl versions && \
    echo "Release size:" && \
    du -sh _build/prod/rel/a2a_erl

# -----------------------------------------------------------------------------
# Stage 2: RUNTIME - Minimal production image
# -----------------------------------------------------------------------------
FROM ghcr.io/erlef/ubuntu-otp:ubuntu-24.04-otp-28 AS runtime

# Set runtime arguments
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION=0.1.0

# Set runtime labels
LABEL maintainer="A2A Project" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.title="A2A Erlang Runtime" \
      org.opencontainers.image.description="Minimal runtime for A2A Agent Protocol"

# Install runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssl \
    libssl3 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user for security (following principle of least privilege)
RUN groupadd -r a2a && \
    useradd -r -g a2a -s /bin/bash -d /opt/a2a_erl a2a

# Set working directory
WORKDIR /opt/a2a_erl

# Copy production release from builder stage
COPY --from=builder --chown=a2a:a2a /build/_build/prod/rel/a2a_erl/ ./

# Verify the copied release
RUN test -x bin/a2a_erl || (echo "Release binary not executable!" && exit 1)

# Set environment variables
ENV RELEASE_DISTRIBUTION=name \
    RELEASE_NODE=a2a@127.0.0.1 \
    RELEASE_COOKIE=a2a_cookie \
    RELEASE_MODE=interactive \
    PORT=8080 \
    HOST=localhost \
    SCHEME=http \
    ERL_MAX_PORTS=65536 \
    ERL_MAX_ETS_TABLES=2000

# Expose the default HTTP port
# Can be overridden with docker run -p <external>:8080
EXPOSE 8080

# Health check endpoint
# Uses the /.well-known/agent-card.json endpoint to verify service is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/.well-known/agent-card.json || exit 1

# Switch to non-root user
USER a2a

# Create directory for runtime data (logs, etc.)
RUN mkdir -p log data && \
    chmod 755 log data

# Set proper file permissions for OTP release
RUN find . -type d -exec chmod 755 {} \; && \
    find . -type f -exec chmod 644 {} \; && \
    chmod +x bin/* && \
    chmod 755 releases/*/*

# Verify VM arguments and sys.config exist
RUN test -f etc/vm.args || (echo "vm.args missing!" && exit 1) && \
    test -f etc/sys.config || (echo "sys.config missing!" && exit 1)

# Optional: Display release information at startup
RUN echo "A2A Erlang/OTP Release Information:" && \
    bin/a2a_erl versions

# Docker entrypoint script for proper signal handling
# This ensures graceful shutdown when container receives SIGTERM
COPY --chown=a2a:a2a <<EOF /entrypoint.sh
#!/bin/bash
set -e

# Trap signals for graceful shutdown
trap 'bin/a2a_erl stop' SIGTERM SIGINT

# Override config from environment variables if provided
if [ -n "\${PORT}" ]; then
    echo "Setting PORT=\${PORT}"
    export PORT
fi

if [ -n "\${HOST}" ]; then
    echo "Setting HOST=\${HOST}"
    export HOST
fi

if [ -n "\${SCHEME}" ]; then
    echo "Setting SCHEME=\${SCHEME}"
    export SCHEME
fi

# Display startup information
echo "======================================================================"
echo "A2A Erlang/OTP Application Starting"
echo "======================================================================"
echo "Version: ${VERSION}"
echo "Node: \${RELEASE_NODE}"
echo "Port: \${PORT}"
echo "Host: \${HOST}"
echo "Scheme: \${SCHEME}"
echo "======================================================================"

# Start the application
# Using 'foreground' mode for proper Docker integration
exec bin/a2a_erl foreground
EOF

RUN chmod +x /entrypoint.sh

# Set entrypoint and default command
ENTRYPOINT ["/entrypoint.sh"]
CMD []

# -----------------------------------------------------------------------------
# Stage 3: DEVELOPMENT (Optional) - Full development environment
# -----------------------------------------------------------------------------
FROM builder AS development

# Install development and testing tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    vim \
    strace \
    tcpdump \
    net-tools \
    && rm -rf /var/lib/apt/lists/*

# Install rebar3 plugins for dialyzer, proper, etc.
RUN rebar3 install

# Create development user
RUN useradd -m -s /bin/bash dev && \
    chown -R dev:dev /build

USER dev
WORKDIR /build

# Expose ports for development
# 8080: HTTP server
# 4369: EPMD (Erlang Port Mapper Daemon)
# 9100-9155: Distribution ports
EXPOSE 8080 4369

# Default to interactive shell
CMD ["rebar3", "shell"]

# =============================================================================
# Usage Examples:
# =============================================================================
#
# Build production image:
#   docker build -t a2a-erl:0.1.0 .
#
# Run with default settings:
#   docker run -p 8080:8080 a2a-erl:0.1.0
#
# Run with custom configuration:
#   docker run -p 9000:8080 \
#     -e PORT=9000 \
#     -e HOST=a2a.example.com \
#     -e SCHEME=https \
#     a2a-erl:0.1.0
#
# Run in development mode:
#   docker build --target development -t a2a-erl:dev .
#   docker run -it -p 8080:8080 \
#     -v $(pwd):/build \
#     a2a-erl:dev
#
# Run tests in container:
#   docker run --rm -v $(pwd):/build -w /build a2a-erl:dev \
#     rebar3 ct
#
# Check image size:
#   docker images a2a-erl:0.1.0
#
# Inspect layers:
#   docker history a2a-erl:0.1.0
#
# =============================================================================
