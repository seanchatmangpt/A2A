.PHONY: all compile test clean build run install start stop docs

# Default target
all: compile

# Compile Erlang application
compile:
	@echo "Compiling elrmcp bridge..."
	rebar3 compile

# Build release
build: compile
	@echo "Building release..."
	rebar3 release

# Run tests
test: compile
	@echo "Running tests..."
	rebar3 eunit
	rebar3 ct

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rebar3 clean
	rm -rf _build

# Install application
install: build
	@echo "Installing application..."
	rebar3 install

# Start application in development mode
start: compile
	@echo "Starting elrmcp bridge..."
	rebar3 shell

# Run in foreground
run: start

# Stop application
stop:
	@echo "Stopping elrmcp bridge..."
	./_build/default/rel/elrmcp_bridge/bin/elrmcp_bridge stop

# Generate documentation
docs: compile
	@echo "Generating documentation..."
	rebar3 ex_doc

# Development helpers
dev-setup:
	@echo "Setting up development environment..."
	rebar3 deps
	rebar3 compile

dev-test:
	@echo "Running development tests..."
	rebar3 eunit --verbose

dev-lint:
	@echo "Running linting..."
	rebar3 lint

# Docker support
docker-build:
	@echo "Building Docker image..."
	docker build -t elrmcp-bridge .

docker-run:
	@echo "Running elrmcp bridge in Docker..."
	docker run -p 8091:8091 elrmcp-bridge

# Hot reload
reload: compile
	@echo "Reloading application..."
	rebar3 shell --name elrmcp_bridge@127.0.0.1 --cookie elrmcp

# Health check
health-check:
	@echo "Checking bridge health..."
	curl -s http://localhost:8091/health || echo "Bridge not available"

# Initialize bridge
init-bridge:
	@echo "Initializing bridge..."
	erl -pa _build/default/lib/*/ebin -eval "
	case elrmcp_mcp_bridge:initialize_craftplan() of
		ok -> io:format('Bridge initialized successfully\n');
		Error -> io:format('Failed to initialize bridge: ~p\n', [Error])
	end,
	halt().
"

# Register tools
register-tools:
	@echo "Registering tools..."
	erl -pa _build/default/lib/*/ebin -eval "
	case elrmcp_mcp_bridge:register_tools() of
		ok -> io:format('Tools registered successfully\n');
		Error -> io:format('Failed to register tools: ~p\n', [Error])
	end,
	halt().
"

# Show bridge status
show-status:
	@echo "Showing bridge status..."
	erl -pa _build/default/lib/*/ebin -eval "
	case elrmcp_mcp_bridge:get_bridge_status() of
		{ok, Status} ->
			io:format('~ts\n', [jsx:encode(Status)]);
		Error ->
			io:format('Failed to get status: ~p\n', [Error])
	end,
	halt().
"