# Build Automation for Craftplan MCP + A2A Integration

This document describes the build automation system for the Craftplan MCP (Model Context Protocol) server and A2A (Agent-to-Agent) agent integration.

## Overview

The build automation system provides comprehensive build, test, and deployment capabilities for the Craftplan integration components:

- **MCP Server**: Erlang/OTP-based MCP server for connecting to Craftplan ERP
- **A2A Agent**: Erlang/OTP-based agent implementing Agent-to-Agent protocol
- **Docker Integration**: Containerized deployment support
- **CI/CD Integration**: GitHub Actions workflow for automated testing and deployment

## Directory Structure

```
craftplan/
├── Makefile                    # Primary build automation
├── docker-compose.local.yml    # Local development environment
├── scripts/                    # Build and test scripts
│   ├── build-mcp.sh           # MCP server build script
│   ├── build-a2a.sh           # A2A agent build script
│   ├── build-all.sh           # Build both components
│   ├── test-all.sh            # Comprehensive test suite
│   └── docker-build.sh        # Docker image build script
├── mock-api/                  # Mock API for testing
│   ├── index.html             # Mock API HTML
│   └── nginx.conf             # Mock API nginx config
└── BUILD_AUTOMATION.md        # This documentation
```

## Build System

### Make Targets

The `Makefile` provides the following targets:

#### Build Targets
- `make all` - Build both MCP server and A2A agent (default)
- `make mcp` - Build MCP server only
- `make a2a` - Build A2A agent only

#### Test Targets
- `make test` - Run all tests (unit tests)
- `make test-mcp` - Run MCP server tests
- `make test-a2a` - Run A2A agent tests

#### Release Targets
- `make release` - Create releases for both components
- `make release-mcp` - Create MCP server release
- `make release-a2a` - Create A2A agent release

#### Docker Targets
- `make docker-all` - Build both Docker images
- `make docker-mcp` - Build MCP Docker image
- `make docker-a2a` - Build A2A Docker image

#### Development Targets
- `make shell-mcp` - Start MCP server shell
- `make shell-a2a` - Start A2A agent shell
- `make format` - Format Erlang code

### Build Scripts

#### build-mcp.sh
Builds the MCP server release with error handling:
```bash
./scripts/build-mcp.sh          # Build release
./scripts/build-mcp.sh --clean  # Clean and build
./scripts/build-mcp.sh --debug  # Build with debug output
```

#### build-a2a.sh
Builds the A2A agent release with error handling:
```bash
./scripts/build-a2a.sh          # Build release
./scripts/build-a2a.sh --clean  # Clean and build
./scripts/build-a2a.sh --debug  # Build with debug output
```

#### build-all.sh
Builds both components with comprehensive testing:
```bash
./scripts/build-all.sh                    # Build both projects
./scripts/build-all.sh --clean            # Clean and build
./scripts/build-all.sh --skip-tests       # Build without running tests
./scripts/build-all.sh --debug            # Build with debug output
```

#### test-all.sh
Comprehensive test suite for both components:
```bash
./scripts/test-all.sh                    # Run all tests
./scripts/test-all.sh --unit            # Run unit tests only
./scripts/test-all.sh --integration     # Run integration tests only
./scripts/test-all.sh --clean           # Clean and test
./scripts/test-all.sh --verbose         # Test with verbose output
```

#### docker-build.sh
Builds Docker images for both components:
```bash
./scripts/docker-build.sh               # Build all Docker images
./scripts/docker-build.sh --mcp-only    # Build MCP image only
./scripts/docker-build.sh --a2a-only    # Build A2A image only
```

## Local Development

### Docker Compose Local Environment

The `docker-compose.local.yml` file provides a local development environment with:

- **craftplan-mcp-server**: MCP server on port 8090
- **craftplan-a2a-agent**: A2A agent on port 8080
- **mock-craftplan-api**: Mock API on port 4000
- **postgres**: PostgreSQL database on port 5432
- **redis**: Redis cache on port 6379
- **minio**: MinIO storage on ports 9000/9001

Start the local environment:
```bash
docker-compose -f docker-compose.local.yml up -d
```

Stop the environment:
```bash
docker-compose -f docker-compose.local.yml down -v
```

### Testing

Run the comprehensive test suite:
```bash
# Run all tests
./scripts/test-all.sh

# Run only unit tests
./scripts/test-all.sh --unit

# Run only integration tests
./scripts/test-all.sh --integration

# Clean and run tests
./scripts/test-all.sh --clean
```

### Development Workflow

1. **Build both components**:
   ```bash
   make all
   ```

2. **Run tests**:
   ```bash
   make test
   ```

3. **Start local environment**:
   ```bash
   docker-compose -f docker-compose.local.yml up -d
   ```

4. **Test health endpoints**:
   ```bash
   curl http://localhost:8090/health
   curl http://localhost:8080/health
   ```

5. **Build Docker images**:
   ```bash
   make docker-all
   ```

## CI/CD Integration

The GitHub Actions workflow `.github/workflows/craftplan-ci.yml` provides:

### Triggers
- Push to main/develop branches
- Pull requests targeting main/develop branches
- Manual workflow dispatch

### Jobs

1. **build-mcp**: Build MCP server with tests
2. **build-a2a**: Build A2A agent with tests
3. **build-docker**: Build Docker images (on push)
4. **integration-tests**: Full integration testing
5. **code-quality**: XREF, dialyzer, and format checks
6. **security-scan**: Trivy vulnerability scanning
7. **release**: Create GitHub release (on main branch)

### Environment Variables

```yaml
env:
  OTP_VERSION: '27'
  REBAR3_VERSION: '3.23.0'
```

### Secrets Required

- `DOCKER_USERNAME`: Docker Hub username
- `DOCKER_PASSWORD`: Docker Hub password
- `GITHUB_TOKEN`: GitHub token for releases

## Production Deployment

### Using Docker Stack

For production deployment with Docker Swarm:
```bash
docker stack deploy -c docker-compose.stack.yml craftplan
```

### Manual Release

1. **Create releases**:
   ```bash
   make release
   ```

2. **Build Docker images**:
   ```bash
   make docker-all
   ```

3. **Tag and push**:
   ```bash
   docker tag craftplan-mcp-server:latest your-repo/craftplan-mcp-server:latest
   docker tag craftplan-a2a-agent:latest your-repo/craftplan-a2a-agent:latest
   docker push your-repo/craftplan-mcp-server:latest
   docker push your-repo/craftplan-a2a-agent:latest
   ```

## Error Handling

All scripts include comprehensive error handling:

- **Dependency checking**: Validates required tools (rebar3, erl, docker, etc.)
- **Project validation**: Ensures correct project structure
- **Build verification**: Confirms successful builds
- **Test validation**: Ensures tests pass
- **Health checks**: Verifies service availability

## Best Practices

1. **Always run tests before deployment**
2. **Use the `--clean` option for clean builds**
3. **Check health endpoints after deployment**
4. **Monitor logs for issues**
5. **Use proper environment variables for configuration**
6. **Follow semantic versioning for releases**

## Troubleshooting

### Common Issues

1. **Build failures**:
   - Check dependencies with `make check-deps`
   - Run `make clean` and rebuild
   - Check rebar3.config syntax

2. **Test failures**:
   - Run tests with `--verbose` for detailed output
   - Check test coverage with `rebar3 cover`
   - Review dialyzer warnings

3. **Docker issues**:
   - Check Docker daemon is running
   - Verify ports are not in use
   - Check Docker Compose syntax

### Debug Mode

All scripts support debug mode:
```bash
./scripts/build-all.sh --debug
./scripts/test-all.sh --debug
```

## Contributing

1. Follow the existing build automation patterns
2. Add comprehensive tests for new features
3. Update documentation for changes
4. Ensure all scripts are executable
5. Follow shell best practices and error handling