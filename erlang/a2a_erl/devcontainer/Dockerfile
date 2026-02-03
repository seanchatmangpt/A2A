# =============================================================================
# A2A Erlang DevContainer Dockerfile
# =============================================================================
# Development container for A2A Agent-to-Agent Protocol Erlang implementation
# Based on Alpine Linux with Erlang/OTP 28
# =============================================================================

FROM erlang:28-alpine

# Metadata
LABEL maintainer="A2A Project" \
      description="Development container for A2A Erlang/OTP implementation"

# Set working directory
WORKDIR /workspace

# Install development tools
RUN apk add --no-cache \
    build-base \
    git \
    curl \
    vim \
    wget \
    net-tools \
    iputils \
    bind-tools \
    strace \
    tcpdump \
    htop \
    openssl-dev \
    ca-certificates \
    bash \
    coreutils \
    linux-headers

# Install rebar3 if not already available
RUN if ! command -v rebar3 &> /dev/null; then \
        curl -O https://s3.amazonaws.com/rebar3/rebar3 && \
        chmod +x rebar3 && \
        mv rebar3 /usr/local/bin/; \
    fi

# Verify installations
RUN erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell && \
    rebar3 version

# Install common rebar3 plugins for development
RUN rebar3 local install proper && \
    rebar3 local install rebar3_eqc && \
    rebar3 local install rebar3_dialyzer

# Create non-root user for development
RUN addgroup -g 1000 dev && \
    adduser -D -u 1000 -G dev -h /workspace -s /bin/bash dev && \
    chown -R dev:dev /workspace

# Expose common ports
# 8080: HTTP server
# 4369: EPMD
EXPOSE 8080 4369

# Set environment variables
ENV REBAR_GLOBAL_CONFIG_DIR=/workspace/.rebar3 \
    ERL_MAX_PORTS=65536 \
    ERL_MAX_ETS_TABLES=2000

# Switch to development user
USER dev

# Set default command to interactive shell
CMD ["/bin/bash"]
