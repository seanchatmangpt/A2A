# Craftplan MCP + A2A Integration Test Suite

This comprehensive test suite covers the Craftplan MCP server and A2A agent integration, providing unit tests, integration tests, and coverage analysis.

## Test Structure

### Unit Tests

#### MCP Server Tests (`/mcp-server/test/`)
- **`craftplan_mcp_server_tests.erl`** - Tests MCP server functionality, JSON-RPC handling, and tool calls
- **`craftplan_api_client_tests.erl`** - Tests HTTP client functionality, API calls, and error handling
- **`craftplan_test_support.erl`** - Common test utilities and mock data

#### A2A Agent Tests (`/a2a-agent/test/`)
- **`craftplan_a2a_server_tests.erl`** - Tests A2A server functionality and task management
- **`craftplan_task_handler_tests.erl`** - Tests individual task processing and execution logic
- **`craftplan_agent_card_tests.erl`** - Tests agent discovery and capability registration
- **`craftplan_test_support.erl`** - Common test utilities and mock data

### Integration Tests (`/test/`)
- **`craftplan_integration_tests.erl`** - End-to-end MCP ↔ A2A interaction tests

### Configuration Files
- **`cover.spec`** - Coverage specification for each component
- **`rebar.config`** - Updated with test dependencies and coverage settings

## Running Tests

### Complete Test Suite
```bash
cd /Users/sac/A2A/craftplan
./test/run_tests.sh
```

### Individual Component Tests

#### MCP Server Tests
```bash
cd /Users/sac/A2A/craftplan/mcp-server
rebar3 eunit          # Run unit tests
rebar3 proper         # Run property-based tests
rebar3 cover          # Generate coverage report
```

#### A2A Agent Tests
```bash
cd /Users/sac/A2A/craftplan/a2a-agent
rebar3 eunit          # Run unit tests
rebar3 proper         # Run property-based tests
rebar3 cover          # Generate coverage report
```

### Integration Tests
```bash
cd /Users/sac/A2A/craftplan/test
rebar3 compile
erl -pa ebin deps/*/ebin -eval "eunit:test([craftplan_integration_tests], [verbose]), halt(0)"
```

## Test Dependencies

The test suite includes:
- **EUnit** - Unit testing framework
- **Meck** - Mocking library
- **Proper** - Property-based testing
- **Coverage analysis** - Built-in coverage reporting

## Test Categories

### 1. Unit Tests
- **MCP Server**: JSON-RPC handling, tool calls, server lifecycle
- **API Client**: HTTP requests, error handling, retry logic
- **A2A Server**: Task management, WebSocket handling, state tracking
- **Task Handler**: Task execution, state management, validation
- **Agent Card**: Capability registration, discovery, metadata

### 2. Integration Tests
- **MCP ↔ A2A Workflow**: End-to-end message passing
- **Task Execution Pipeline**: Complete task flow
- **Error Propagation**: Error handling across components
- **Concurrent Operations**: Parallel task execution
- **State Consistency**: State synchronization

### 3. Coverage Analysis
- **Line Coverage**: Measures executed code lines
- **Branch Coverage**: Measures conditional branches
- **Function Coverage**: Measures executed functions

## Mocking Strategy

The test suite uses Meck for mocking external dependencies:
- **API calls**: HTTP client responses
- **A2A handler**: WebSocket communication
- **Gen servers**: Process lifecycle
- **Timer operations**: Time-based events

## Test Data

Common test data structures are defined in support modules:
- **Tool definitions**: Schema and parameters
- **Task definitions**: Type and context
- **Agent cards**: Capabilities and metadata
- **Request/Response**: JSON-RPC messages

## Coverage Reports

Coverage reports are generated in:
- MCP Server: `_build/test/cover/index.html`
- A2A Agent: `_build/test/cover/index.html`

Reports include:
- **Source code analysis**
- **Coverage metrics**
- **Uncovered code highlighting**

## Best Practices

### Writing Tests
1. **Use test support modules** for common utilities
2. **Mock external dependencies** consistently
3. **Follow EUnit conventions** for test organization
4. **Include both success and error cases**
5. **Add comments explaining complex scenarios**

### Running Tests
1. **Run tests after code changes** to catch regressions
2. **Check coverage reports** for complete testing
3. **Use integration tests** for end-to-end validation
4. **Run property tests** for edge case detection

## Troubleshooting

### Common Issues
1. **Missing dependencies**: Run `rebar3 deps` first
2. **Module not found**: Ensure `rebar3 compile` completed
3. **Test timeouts**: Increase timeout in test configuration
4. **Mock failures**: Verify Meck expectations are correct

### Debug Mode
```bash
rebar3 eunit -v  # Verbose output
rebar3 cover -v  # Verbose coverage
```

## Continuous Integration

The test suite is designed for CI integration:
- **Minimal dependencies** for quick setup
- **Consistent test structure** for automation
- **Detailed output** for debugging
- **Coverage reports** for quality metrics

## Contributing

When adding new tests:
1. **Follow existing patterns** in test structure
2. **Use mock data** from support modules
3. **Include both unit and integration tests**
4. **Update coverage specifications** if needed
5. **Document complex test scenarios**