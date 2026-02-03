# Docker Deployment Guide for A2A Erlang/OTP 28

Complete Docker containerization setup for the A2A Agent-to-Agent Protocol implementation in Erlang/OTP 28.

## Table of Contents

- [Quick Start](#quick-start)
- [Multi-Stage Build Overview](#multi-stage-build-overview)
- [Dockerfile Stages](#dockerfile-stages)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [Development Workflow](#development-workflow)
- [Production Deployment](#production-deployment)
- [Monitoring & Health Checks](#monitoring--health-checks)
- [Troubleshooting](#troubleshooting)

## Quick Start

### Using Docker (Recommended)

```bash
# Build the production image
docker build -t a2a-erl:0.1.0 .

# Run the container
docker run -p 8080:8080 a2a-erl:0.1.0

# Test the endpoint
curl http://localhost:8080/.well-known/agent-card.json
```

### Using Docker Compose

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

### Using Makefile (Most Convenient)

```bash
# Show all available commands
make help

# Build and run production container
make prod

# Run development container
make dev

# Run tests
make test
```

## Multi-Stage Build Overview

The Dockerfile uses a multi-stage build for optimal image size and security:

```
┌─────────────────────────────────────────────────────────┐
│  Stage 1: BUILDER (otp-28 + build tools)               │
│  - Base: ghcr.io/erlef/ubuntu-otp-build                │
│  - Size: ~1.2GB                                         │
│  - Purpose: Compile Erlang source and build release    │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼ Copy only compiled release
┌─────────────────────────────────────────────────────────┐
│  Stage 2: RUNTIME (otp-28 minimal)                     │
│  - Base: ghcr.io/erlef/ubuntu-otp                       │
│  - Size: ~120MB (optimized)                             │
│  - Purpose: Run production application                  │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼ (Optional)
┌─────────────────────────────────────────────────────────┐
│  Stage 3: DEVELOPMENT (full tooling)                   │
│  - Base: Builder + dev tools                            │
│  - Size: ~1.3GB                                         │
│  - Purpose: Development and testing                    │
└─────────────────────────────────────────────────────────┘
```

### Benefits

1. **Small Final Image**: ~120MB vs 1.2GB with build tools
2. **Security**: Non-root user, minimal attack surface
3. **Speed**: Faster deployment with smaller image
4. **Reproducibility**: Locked dependencies via rebar.lock
5. **Separation**: Build artifacts not in runtime image

## Dockerfile Stages

### Stage 1: Builder

**Purpose**: Compile and build production release

**Base Image**: `ghcr.io/erlef/ubuntu-otp-build:ubuntu-24.04-otp-28`

**Key Operations**:
- Install build dependencies (build-essential, git, curl)
- Verify OTP 28 installation
- Copy dependency files (rebar.config, rebar.lock)
- Fetch and compile dependencies (for layer caching)
- Copy source code
- Build production release with `rebar3 as prod release`

**Output**: `_build/prod/rel/a2a_erl/` (complete, self-contained release)

### Stage 2: Runtime

**Purpose**: Minimal production image

**Base Image**: `ghcr.io/erlef/ubuntu-otp:ubuntu-24.04-otp-28`

**Key Operations**:
- Install runtime dependencies only (openssl, curl)
- Create non-root user (`a2a`)
- Copy compiled release from builder
- Set up environment variables
- Configure health checks
- Set proper file permissions

**Key Features**:
- Non-root user for security
- Health check on port 8080
- Proper signal handling for graceful shutdown
- Volume support for logs and data

### Stage 3: Development (Optional)

**Purpose**: Full development environment

**Base**: Extends builder stage

**Key Operations**:
- Install development tools (vim, strace, tcpdump)
- Mount source code volumes
- Expose additional ports (EPMD)
- Default to interactive shell

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | HTTP server port |
| `HOST` | `localhost` | Agent card host URL |
| `SCHEME` | `http` | URL scheme (http/https) |
| `RELEASE_NODE` | `a2a@127.0.0.1` | Erlang node name |
| `RELEASE_COOKIE` | `a2a_cookie` | Distributed Erlang cookie |
| `ERL_MAX_PORTS` | `65536` | Maximum number of ports |
| `ERL_MAX_ETS_TABLES` | `2000` | Maximum ETS tables |

### Exposed Ports

- `8080`: HTTP server (main application)
- `4369`: EPMD (Erlang Port Mapper Daemon) for distributed Erlang

### Volumes

No persistent volumes required (stateless application). Optional:
- `/opt/a2a_erl/log`: Application logs
- `/opt/a2a_erl/data`: Runtime data

### Health Check

The container includes a built-in health check:

```bash
# Docker health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/.well-known/agent-card.json || exit 1
```

**Check health status**:
```bash
docker ps
docker inspect --format='{{.State.Health.Status}}' a2a-erl
make health
```

## Usage Examples

### Basic Usage

#### Build and Run

```bash
# Build production image
docker build -t a2a-erl:0.1.0 .

# Run with default settings
docker run -d --name a2a-erl -p 8080:8080 a2a-erl:0.1.0

# View logs
docker logs -f a2a-erl

# Stop container
docker stop a2a-erl
docker rm a2a-erl
```

#### Custom Configuration

```bash
# Custom port and host
docker run -d --name a2a-erl \
  -p 9000:8080 \
  -e PORT=9000 \
  -e HOST=a2a.example.com \
  -e SCHEME=https \
  a2a-erl:0.1.0
```

#### Interactive Shell

```bash
# Open shell in running container
docker exec -it a2a-erl bash

# Run Erlang shell
docker exec -it a2a-erl bin/a2a_erl remote_console
```

### Using Docker Compose

```bash
# Start production service
docker-compose up -d

# Start development service (with volume mounts)
docker-compose --profile dev up a2a-dev

# Run tests
docker-compose --profile test run --rm a2a-test

# Scale multiple instances
docker-compose up -d --scale a2a-erl=3

# View logs
docker-compose logs -f

# Stop all services
docker-compose down
```

### Using Makefile

The Makefile provides convenient targets:

```bash
# Show all commands
make help

# Build images
make build        # Build production image
make build-dev    # Build development image

# Run containers
make prod         # Run production container
make dev          # Run development container with volumes
make run          # Alias for 'prod'

# Testing
make test         # Run full test suite
make test-unit    # Run unit tests only
make test-proper  # Run property-based tests

# Management
make stop         # Stop running container
make restart      # Restart production container
make logs         # View logs
make shell        # Open shell in container
make health       # Check container health

# Docker Compose
make compose-up       # Start all services
make compose-dev      # Start development service
make compose-test     # Run tests
make compose-down     # Stop services

# Cleanup
make clean        # Remove stopped containers
make clean-all    # Remove all containers and images

# Info
make info         # Show build information
make status       # Show container status
```

## Development Workflow

### Local Development with Volume Mounts

```bash
# Using Docker
docker run -it --rm \
  -p 8080:8080 \
  -v $(pwd)/src:/build/src \
  -v $(pwd)/include:/build/include \
  -v $(pwd)/config:/build/config \
  -v $(pwd)/test:/build/test \
  -v $(pwd)/rebar.config:/build/rebar.config \
  a2a-erl:dev \
  rebar3 shell

# Using Makefile
make dev

# Using Docker Compose
docker-compose --profile dev up a2a-dev
```

### Running Tests

```bash
# Using Docker
docker run --rm \
  -v $(pwd):/build \
  a2a-erl:dev \
  rebar3 ct

# Using Makefile
make test

# Using Docker Compose
docker-compose --profile test run --rm a2a-test
```

### Interactive Development

```bash
# Start development container
docker run -it --rm \
  -p 8080:8080 \
  -v $(pwd):/build \
  --name a2a-dev \
  a2a-erl:dev \
  bash

# Inside container: run rebar3 commands
rebar3 compile
rebar3 shell
rebar3 ct
rebar3 dialyzer
```

## Production Deployment

### Building Production Image

```bash
# Build with version tags
docker build \
  --build-arg VERSION=0.1.0 \
  --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  --build-arg VCS_REF=$(git rev-parse --short HEAD) \
  -t a2a-erl:0.1.0 \
  -t a2a-erl:latest \
  .

# Verify image
docker images a2a-erl
docker inspect a2a-erl:0.1.0
```

### Running in Production

```bash
# Run with production settings
docker run -d \
  --name a2a-erl \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 4369:4369 \
  -e RELEASE_NODE=a2a@production \
  -e RELEASE_COOKIE=$(openssl rand -base64 32) \
  -e PORT=8080 \
  -e HOST=a2a.example.com \
  -e SCHEME=https \
  --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  --memory=2g \
  --memory-swap=2g \
  --cpus=2 \
  a2a-erl:0.1.0

# Check health
docker ps
curl http://localhost:8080/.well-known/agent-card.json
```

### Using Docker Compose for Production

```bash
# Start with custom environment
export VERSION=0.1.0
export PORT=8080
export HOST=a2a.example.com
export COOKIE=$(openssl rand -base64 32)

docker-compose up -d

# Check status
docker-compose ps
docker-compose logs -f
```

### Pushing to Registry

```bash
# Tag for registry
docker tag a2a-erl:0.1.0 registry.example.com/a2a-erl:0.1.0
docker tag a2a-erl:0.1.0 registry.example.com/a2a-erl:latest

# Push to registry
docker push registry.example.com/a2a-erl:0.1.0
docker push registry.example.com/a2a-erl:latest

# Using Makefile
make release REGISTRY=registry.example.com
```

## Monitoring & Health Checks

### Built-in Health Check

```bash
# Check health status
docker inspect --format='{{.State.Health.Status}}' a2a-erl

# View health check logs
docker inspect --format='{{json .State.Health}}' a2a-erl | jq

# Manual health check
curl -f http://localhost:8080/.well-known/agent-card.json
```

### Application Metrics

```bash
# Access Erlang shell
docker exec -it a2a-erl bin/a2a_erl remote_console

# In shell: check application status
application:which_applications().
supervisor:which_children(a2a_erl_sup).
erlang:memory().
erlang:system_info(process_count).
```

### Log Management

```bash
# View container logs
docker logs -f a2a-erl

# View last 100 lines
docker logs --tail 100 a2a-erl

# View logs with timestamps
docker logs -t a2a-erl

# Access log files
docker exec a2a-erl cat log/crash.dump 2>/dev/null || echo "No crash dump"
docker exec a2a-erl ls -la log/
```

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker logs a2a-erl

# Run in foreground to see errors
docker run --rm -p 8080:8080 a2a-erl:0.1.0

# Check if port is already in use
lsof -i :8080
netstat -tulpn | grep 8080
```

### Health Check Failing

```bash
# Test endpoint manually
curl -v http://localhost:8080/.well-known/agent-card.json

# Check if application is running
docker exec a2a-erl bin/a2a_erl ping

# Check VM arguments
docker exec a2a-erl cat etc/vm.args
```

### Build Failures

```bash
# Build without cache
docker build --no-cache -t a2a-erl:0.1.0 .

# Check OTP version
docker run --rm ghcr.io/erlef/ubuntu-otp-build:ubuntu-24.04-otp-28 \
  erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell

# Build with shell access for debugging
docker run -it --rm \
  -v $(pwd):/build \
  -w /build \
  ghcr.io/erlef/ubuntu-otp-build:ubuntu-24.04-otp-28 \
  bash
```

### Memory Issues

```bash
# Check memory usage
docker stats a2a-erl

# Increase memory limits
docker run -d \
  --memory=4g \
  --memory-swap=4g \
  --memory-reservation=512m \
  a2a-erl:0.1.0

# Tune Erlang VM
docker run -d \
  -e ERL_OPTS="+MBas aobf +MBlmbcs 512" \
  a2a-erl:0.1.0
```

### Networking Issues

```bash
# Check container network
docker network inspect bridge
docker inspect a2a-erl | grep -A 20 NetworkSettings

# Test from inside container
docker exec a2a-erl curl -v http://localhost:8080/.well-known/agent-card.json

# Expose EPMD for distributed Erlang
docker run -d \
  -p 8080:8080 \
  -p 4369:4369 \
  -p 9100-9155:9100-9155 \
  a2a-erl:0.1.0
```

## Best Practices

### Production Checklist

- [ ] Use specific version tags (not `latest`)
- [ ] Set strong RELEASE_COOKIE
- [ ] Configure resource limits
- [ ] Enable health checks
- [ ] Use restart policies
- [ ] Configure log rotation
- [ ] Use non-root user (included)
- [ ] Scan image for vulnerabilities
- [ ] Monitor container metrics
- [ ] Test disaster recovery

### Security Hardening

```bash
# Scan for vulnerabilities
docker scan a2a-erl:0.1.0

# Run as non-root (already configured)
# Use read-only filesystem
docker run --read-only --tmpfs /tmp a2a-erl:0.1.0

# Drop capabilities
docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE a2a-erl:0.1.0

# Use security options
docker run --security-opt=no-new-privileges a2a-erl:0.1.0
```

### Performance Tuning

```bash
# Optimize for performance
docker run -d \
  --cpus=2 \
  --memory=2g \
  --memory-swap=2g \
  -p 8080:8080 \
  -e ERL_MAX_PORTS=65536 \
  -e ERL_MAX_ETS_TABLES=2000 \
  -e ERL_OPTS="+P 1000000 +K true +A 64 +S 4:4" \
  a2a-erl:0.1.0
```

## Additional Resources

- [Erlang/OTP Documentation](https://www.erlang.org/doc/)
- [rebar3 Documentation](https://rebar3.org/docs/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Docker Compose Reference](https://docs.docker.com/compose/compose-file/)
- [A2A Protocol Specification](https://github.com/a2aproject/A2A)

## Support

For issues and questions:
- GitHub Issues: https://github.com/a2aproject/A2A/issues
- Erlang Forums: https://erlangforums.com/
- Docker Community: https://forums.docker.com/
