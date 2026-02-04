# Development Guide

This guide provides comprehensive information for developers working on the elrmcp bridge.

## Project Structure

```
elrmcp_bridge/
├── src/                    # Source code
│   ├── elrmcp_mcp_bridge.erl   # Main bridge module
│   ├── elrmcp_mcp_client.erl   # MCP client
│   ├── elrmcp_rate_limiter.erl # Rate limiter
│   ├── elrmcp_bridge_sup.erl   # Supervisor
│   ├── elrmcp_bridge_utils.erl # Utilities
│   └── elrmcp_bridge_app.erl   # Application
├── test/                   # Test suites
│   ├── elrmcp_mcp_bridge_SUITE.erl
│   ├── elrmcp_mcp_client_SUITE.erl
│   ├── elrmcp_rate_limiter_SUITE.erl
│   └── support/
│       └── test_helpers.erl
├── config/                 # Configuration files
│   ├── bridge.config
│   ├── vm.args
│   └── rebar.config
├── deployment/            # Deployment manifests
│   ├── k8s/
│   └── helm/
├── docs/                  # Documentation
│   ├── api/
│   ├── user-guide/
│   ├── deployment/
│   └── development/
└── examples/              # Example code
```

## Development Environment Setup

### Prerequisites

- Erlang/OTP 23+
- Elixir 1.12+ (optional, for testing)
- rebar3
- Git
- Docker (optional)

### 1. Clone Repository

```bash
git clone https://github.com/your-org/elrmcp-bridge.git
cd elrmcp-bridge
```

### 2. Install Dependencies

```bash
rebar3 deps
```

### 3. Build the Project

```bash
rebar3 compile
```

### 4. Run Tests

```bash
rebar3 eunit
rebar3 ct
```

## Code Organization

### Core Modules

#### elrmcp_mcp_bridge.erl
Main bridge module that handles:
- Tool registration and management
- Request forwarding
- Configuration management
- Metrics and monitoring

#### elrmcp_mcp_client.erl
HTTP client for communication with Craftplan MCP:
- JSON-RPC protocol implementation
- Request/response handling
- Error handling

#### elrmcp_rate_limiter.erl
Token bucket rate limiter:
- Rate limiting enforcement
- Token management
- Metrics collection

#### elrmcp_bridge_sup.erl
Supervisor for bridge components:
- Process management
- Failure handling
- Initialization

#### elrmcp_bridge_utils.erl
Utility functions:
- Validation helpers
- Error formatting
- Data manipulation

## Coding Standards

### Erlang Code Style

1. **Module Naming**: Use snake_case for module names
2. **Function Naming**: Use snake_case for function names
3. **Variable Naming**: Use CamelCase for variables
4. **Constants**: Use UPPER_CASE for constants

### Function Specifications

```erlang
-spec function_name(Type1, Type2) -> ReturnType.

-spec list_tools() -> {ok, [tool_info()]} | {error, term()}.
```

### Documentation

```erlang
%% @doc Function description
%% @param Param1 - Description of parameter
%% @param Param2 - Description of parameter
%% @return Description of return value
-spec function_name(Type1, Type2) -> ReturnType.
function_name(Param1, Param2) ->
    %% Function implementation
    Result.
```

### Error Handling

```erlang
try
    Result = some_operation(),
    {ok, Result}
catch
    Error:Reason ->
        {error, {Error, Reason}}
end.
```

### Testing Standards

#### Unit Tests

```erlang
-include_lib("eunit/include/eunit.hrl").

module_function_test() ->
    Result = module:function(Arg1, Arg2),
    ?assertEqual(expected_result, Result).
```

#### Integration Tests

```erlang
init_per_suite(Config) ->
    %% Setup test environment
    {ok, Apps} = application:ensure_all_started(elrmcp_bridge),
    [{apps, Apps} | Config].

end_per_suite(Config) ->
    %% Cleanup test environment
    Apps = ?config(apps, Config),
    [application:stop(App) || App <- Apps],
    ok.
```

## Building and Testing

### Building

```bash
# Compile
rebar3 compile

# Release build
rebar3 release

# Generate documentation
rebar3 edoc
```

### Testing

```bash
# Run all tests
rebar3 ct

# Run specific test suite
rebar3 ct --suite elrmcp_mcp_bridge_SUITE

# Run with coverage
rebar3 cover

# Run tests in parallel
rebar3 ct --jobs 4
```

### Testing Tips

1. **Test Coverage**: Aim for 80%+ coverage
2. **Edge Cases**: Test boundary conditions
3. **Error Paths**: Test error handling
4. **Integration**: Test with external services

## Debugging

### Debug Mode

Enable debug logging:

```bash
export LOG_LEVEL=debug
make start
```

### Debugging Tools

#### erlang shell

```bash
# Start interactive shell
rebar3 shell

# Debug in the shell
1> elrmcp_mcp_bridge:list_available_tools().
```

#### Console Logging

```erlang
%% Add to your code
lager:debug("Debug message: ~p", [Data]),
lager:info("Info message: ~p", [Data]),
lager:error("Error message: ~p", [Error]),
```

#### Common Debug Commands

```erlang
% Check process info
process_info(self())

% Monitor processes
spawn_monitor(fun() -> some_function() end)

% Trap exits
process_flag(trap_exit, true)
```

## Performance Optimization

### Profiling

```bash
# Enable profiling
rebar3 as profile compile

# Run with profiling
erl +pc unicode -pa _build/default/lib/*/ebin -eval "
profiling:start(),
your_function(),
profiling:stop().
"
```

### Memory Management

```erlang
%% Use efficient data structures
maps:from_list([{Key, Value} || {Key, Value} <- List])

%% Avoid excessive copying
binary:copy(Binary, Size)

%% Use process dictionaries sparingly
put(key, value)
get(key)
```

### Concurrency

```erlang
%% Use gen_server for stateful processes
-behaviour(gen_server).

%% Use gen_statem for complex state machines
-behaviour(gen_statem).

%% Use poolboy for process pools
poolboy:start_link([{name, {local, pool_name}}, ...])
```

## Configuration

### Development Configuration

```json
{
  "elrmcp_bridge": {
    "craftplan": {
      "url": "http://localhost:8090",
      "timeout": 30000
    },
    "rate_limiting": {
      "enabled": false
    },
    "logging": {
      "level": "debug"
    }
  }
}
```

### Testing Configuration

```json
{
  "elrmcp_bridge": {
    "craftplan": {
      "url": "http://localhost:18090",
      "timeout": 5000
    },
    "rate_limiting": {
      "enabled": false
    }
  }
}
```

## Deployment Testing

### Unit Testing

```bash
# Run unit tests
rebar3 eunit --verbose

# Run specific module tests
rebar3 eunit --module elrmcp_mcp_bridge
```

### Integration Testing

```bash
# Run integration tests
rebar3 ct --suite elrmcp_mcp_bridge_SUITE

# Run with custom config
rebar3 ct --config test/test.config
```

### End-to-End Testing

```bash
# Start test environment
docker-compose -f docker-compose.test.yml up -d

# Run E2E tests
python tests/e2e/test_bridge.py

# Cleanup
docker-compose -f docker-compose.test.yml down
```

## Contributing

### Development Workflow

1. **Fork the repository**
2. **Create feature branch**
3. **Make changes**
4. **Write tests**
5. **Update documentation**
6. **Submit pull request**

### Pull Request Process

1. **Title**: Use descriptive titles
2. **Description**: Explain the changes
3. **Tests**: Include test coverage
4. **Documentation**: Update relevant docs
5. **Review Address**: Address review comments

### Code Review Checklist

- [ ] Code follows style guidelines
- [ ] Tests are included
- [ ] Documentation is updated
- [ ] Error handling is comprehensive
- [ ] Performance is considered
- [ ] Security is reviewed
- [ ] Dependencies are managed

## Release Process

### Version Management

1. **Semantic Versioning**
   - MAJOR: Breaking changes
   - MINOR: New features
   - PATCH: Bug fixes

2. **Changelog Updates**
   - Update CHANGELOG.md
   - Include version changes
   - Reference PRs

### Release Steps

1. **Update Version**
   ```erlang
   % In src/elrmcp_bridge.app.src
   {vsn, "1.0.0"}
   ```

2. **Update Documentation**
   ```markdown
   ## v1.0.0
   - New feature
   - Bug fix
   ```

3. **Create Release**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

4. **Publish to Hex**
   ```bash
   rebar3 hex publish
   ```

## Troubleshooting

### Common Issues

#### Build Failures

```bash
# Clean build
rebar3 clean
rebar3 compile
```

#### Dependency Issues

```bash
# Update dependencies
rebar3 upgrade

# Force rebuild
rebar3 compile --force
```

#### Test Failures

```bash
# Run tests with verbose output
rebar3 ct --verbose

# Run specific test case
rebar3 ct --module elrmcp_mcp_bridge_SUITE --case test_bridge_initialization
```

### Debug Mode

Enable debug logging:

```erlang
% In your code
lager:set_log_level(lager_console_backend, debug)
```

### Performance Issues

```bash
% Check memory usage
erlang:memory()

% Monitor processes
observer:start()
```

## Tools and Utilities

### Development Tools

1. **Erlang Mode (Emacs)**
   - Syntax highlighting
   - Auto-completion
   - Integration with rebar3

2. **IntelliJ Erlang Plugin**
   - IDE support
   - Refactoring
   - Debugging

3. **Observer**
   - Process monitoring
   - Memory analysis
   - System monitoring

### Linting and Formatting

```bash
# Run linter
rebar3 lint

# Format code
rebar3 format
```

### Static Analysis

```bash
# Run dialyzer
rebar3 dialyzer

# With plt file
rebar3 dialyzer --plt ~/.dialyzer/plt
```

## Advanced Topics

### Performance Tuning

1. **Erlang VM Tuning**
   ```bash
   erl +K true +P 1048576 +hms 64 +hmsz 64
   ```

2. **Cache Optimization**
   ```erlang
   % Use ETS for caching
   ets:new(cache_table, [set, public, named_table, {heir, self(), none}])
   ```

### Security Considerations

1. **Input Validation**
   ```erlang
   % Validate input types
   validate_binary(Input) when is_binary(Input) -> ok;
   validate_binary(_) -> {error, invalid_type}.
   ```

2. **Error Handling**
   ```erlang
   % Secure error messages
   format_error({sensitive, Data}) -> "Internal error";
   format_error(Error) -> iolist_to_binary(io_lib:format("~p", [Error])).
   ```

### Monitoring and Observability

1. **Metrics Collection**
   ```erlang
   % Increment metric
   elrmcp_metrics:increment(requests_total),
   ```

2. **Logging**
   ```erlang
   % Structured logging
   lager:info("Called tool=~p, duration=~ms", [Tool, Duration]),
   ```

## Resources

### Learning Resources

1. **Erlang Documentation**
   - Official Erlang/OTP documentation
   - Erlang Design Patterns

2. **rebar3 Documentation**
   - rebar3 user guide
   - Plugin development

3. **Community Resources**
   - Erlang Forum
   - Erlang Slack
   - Stack Overflow

### External Libraries

1. **HTTP Clients**
   - hackney
   - ibrowse

2. **JSON Processing**
   - jiffy
   - jsx

3. **Logging**
   - lager
   - logger

### Testing Frameworks

1. **Common Test**
   - Integration testing
   - Test suites

2. **EUnit**
   - Unit testing
   - Quick checks

3. **PropEr**
   - Property-based testing
   - QuickCheck-style testing