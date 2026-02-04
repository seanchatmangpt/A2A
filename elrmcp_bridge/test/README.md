# elrmcp Bridge Tests

## Test Suite Overview

This directory contains comprehensive test suites for the elrmcp MCP bridge functionality:

### Test Suites

1. **elrmcp_mcp_bridge_SUITE.erl** - Main bridge functionality tests
   - Bridge initialization
   - Tool registration
   - Request forwarding
   - Rate limiting
   - Configuration management
   - Status monitoring
   - Error handling
   - Concurrent request handling

2. **elrmcp_mcp_client_SUITE.erl** - HTTP client tests
   - Client initialization
   - Tools listing
   - Tool calling
   - Error handling
   - Rate limiting integration

3. **elrmcp_rate_limiter_SUITE.erl** - Rate limiter tests
   - Token bucket behavior
   - Rate limit enforcement
   - Token refill mechanism
   - Status reporting
   - Reset functionality

### Test Requirements

- Erlang/OTP 23+
- Common Test framework
- EUnit framework
- Mock framework for external services

### Running Tests

```bash
# Run all tests
rebar3 ct

# Run specific test suite
rebar3 ct --suite elrmcp_mcp_bridge_SUITE

# Run with verbose output
rebar3 ct --verbose

# Run with specific config
rebar3 ct --config test/test.config
```

### Test Configuration

The test configuration is managed in `test.config`:

```erlang
{etest, [
    {suites, [...]},
    {config, [
        {bridge_url, "http://localhost:8090"},
        {timeout, 5000},
        {max_retries, 3}
    ]}
]}.
```

### Mock Services

For integration testing, mock services are provided:

- `test_helpers.erl` - Common test utilities and helpers
- Mock Craftplan MCP server for testing request/response flow

### Coverage

Test coverage targets:
- 100% branch coverage for core modules
- 90% line coverage for all modules
- Integration tests for all API endpoints
- Error scenarios testing

### Continuous Integration

Tests are configured to run in CI/CD pipelines:
- Automated test execution
- Coverage reporting
- Performance benchmarking
- Security scanning

### Troubleshooting

If tests fail:

1. Check that Craftplan MCP server is running on localhost:8090
2. Verify all dependencies are installed
3. Check test configuration in `test.config`
4. Review test logs for detailed error messages

### Adding New Tests

When adding new tests:

1. Follow existing test naming conventions
2. Include both success and error scenarios
3. Add proper setup/teardown
4. Document test purpose in comments
5. Ensure test isolation