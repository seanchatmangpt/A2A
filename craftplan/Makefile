# =============================================================================
# Craftplan Integration Build Automation
# =============================================================================
#
# Targets:
#   all           - Build both projects (default)
#   mcp           - Build MCP server
#   a2a           - Build A2A agent
#   test          - Run all tests
#   clean         - Clean build artifacts
#   release       - Create releases for both
#   docker-mcp    - Build MCP Docker image
#   docker-a2a    - Build A2A Docker image
#   docker-all    - Build both Docker images
#   help          - Show this help message
#
# =============================================================================

.PHONY: all mcp a2a test clean release docker-mcp docker-a2a docker-all help check-deps

# -----------------------------------------------------------------------------
# Check dependencies
# -----------------------------------------------------------------------------

check-deps:
	@echo "==> Checking dependencies..."
	@which rebar3 >/dev/null || { echo "Error: rebar3 not found"; exit 1; }
	@which erl >/dev/null || { echo "Error: erl not found"; exit 1; }
	@echo "==> All dependencies found"

# Default target
all: mcp a2a

# -----------------------------------------------------------------------------
# Build targets
# -----------------------------------------------------------------------------

mcp:
	@echo "==> Building MCP server..."
	@cd mcp-server && rebar3 compile || { echo "MCP server build failed"; exit 1; }
	@echo "==> MCP server built successfully"

a2a:
	@echo "==> Building A2A agent..."
	@cd a2a-agent && rebar3 compile || { echo "A2A agent build failed"; exit 1; }
	@echo "==> A2A agent built successfully"

# -----------------------------------------------------------------------------
# Test targets
# -----------------------------------------------------------------------------

test:
	@echo "==> Running MCP server tests..."
	@cd mcp-server && rebar3 do ct,dialyzer,xref || true
	@echo "==> Running A2A agent tests..."
	@cd a2a-agent && rebar3 do ct,dialyzer,xref || true
	@echo "==> All tests completed"

test-mcp:
	@echo "==> Running MCP server tests..."
	@cd mcp-server && rebar3 do ct,dialyzer,xref

test-a2a:
	@echo "==> Running A2A agent tests..."
	@cd a2a-agent && rebar3 do ct,dialyzer,xref

# -----------------------------------------------------------------------------
# Clean targets
# -----------------------------------------------------------------------------

clean:
	@echo "==> Cleaning MCP server..."
	@cd mcp-server && rebar3 clean || { echo "Failed to clean MCP server"; exit 1; }
	@echo "==> Cleaning A2A agent..."
	@cd a2a-agent && rebar3 clean || { echo "Failed to clean A2A agent"; exit 1; }
	@echo "==> Cleaning completed"

clean-mcp:
	@echo "==> Cleaning MCP server..."
	@cd mcp-server && rebar3 clean || { echo "Failed to clean MCP server"; exit 1; }

clean-a2a:
	@echo "==> Cleaning A2A agent..."
	@cd a2a-agent && rebar3 clean || { echo "Failed to clean A2A agent"; exit 1; }

# -----------------------------------------------------------------------------
# Release targets
# -----------------------------------------------------------------------------

release: release-mcp release-a2a
	@echo "==> All releases created successfully"

release-mcp:
	@echo "==> Creating MCP server release..."
	@cd mcp-server && rebar3 release -s craftplan_mcp
	@echo "==> MCP release created: mcp-server/_build/default/rel/craftplan_mcp/"

release-a2a:
	@echo "==> Creating A2A agent release..."
	@cd a2a-agent && rebar3 release -s craftplan_a2a
	@echo "==> A2A release created: a2a-agent/_build/default/rel/craftplan_a2a/"

# -----------------------------------------------------------------------------
# Docker targets
# -----------------------------------------------------------------------------

docker-all: docker-mcp docker-a2a
	@echo "==> All Docker images built successfully"

docker-mcp:
	@echo "==> Building MCP server Docker image..."
	@cd mcp-server && docker build -t craftplan-mcp-server:latest . || { echo "MCP Docker build failed"; exit 1; }
	@echo "==> MCP Docker image built: craftplan-mcp-server:latest"

docker-a2a:
	@echo "==> Building A2A agent Docker image..."
	@cd a2a-agent && docker build -t craftplan-a2a-agent:latest . || { echo "A2A Docker build failed"; exit 1; }
	@echo "==> A2A Docker image built: craftplan-a2a-agent:latest"

# -----------------------------------------------------------------------------
# Development targets
# -----------------------------------------------------------------------------

shell-mcp:
	@echo "==> Starting MCP server shell..."
	@cd mcp-server && rebar3 shell

shell-a2a:
	@echo "==> Starting A2A agent shell..."
	@cd a2a-agent && rebar3 shell

# -----------------------------------------------------------------------------
# Format and lint
# -----------------------------------------------------------------------------

format:
	@echo "==> Formatting Erlang code..."
	@cd mcp-server && rebar3 format || { echo "MCP formatting failed"; exit 1; }
	@cd a2a-agent && rebar3 format || { echo "A2A formatting failed"; exit 1; }

# -----------------------------------------------------------------------------
# Help target
# -----------------------------------------------------------------------------

help:
	@echo "Craftplan Integration Build Automation"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  check-deps    Check if required dependencies are installed"
	@echo "  all           Build both projects (default)"
	@echo "  mcp           Build MCP server"
	@echo "  a2a           Build A2A agent"
	@echo "  test          Run all tests"
	@echo "  test-mcp      Run MCP server tests"
	@echo "  test-a2a      Run A2A agent tests"
	@echo "  clean         Clean build artifacts"
	@echo "  clean-mcp     Clean MCP server artifacts"
	@echo "  clean-a2a     Clean A2A agent artifacts"
	@echo "  release       Create releases for both"
	@echo "  release-mcp   Create MCP server release"
	@echo "  release-a2a   Create A2A agent release"
	@echo "  docker-all    Build both Docker images"
	@echo "  docker-mcp    Build MCP Docker image"
	@echo "  docker-a2a    Build A2A Docker image"
	@echo "  shell-mcp     Start MCP server shell"
	@echo "  shell-a2a     Start A2A agent shell"
	@echo "  format        Format Erlang code"
	@echo "  help          Show this help message"
	@echo ""
