# elrmcp MCP Bridge

A comprehensive bridge module connecting elrmcp to Craftplan MCP servers with dynamic tool registration, request forwarding, and advanced features.

## Features

- 🔌 **MCP Protocol Integration**: Full Model Context Protocol support
- 🔄 **Dynamic Tool Registration**: Automatically discovers and registers Craftplan tools
- 🚦 **Rate Limiting**: Configurable token bucket rate limiting
- 📊 **Request Caching**: Intelligent caching for performance optimization
- 🛡️ **Security**: Input validation, output sanitization, and access control
- 📈 **Monitoring**: Built-in metrics and health checks
- 🏗️ **Kubernetes Ready**: Helm charts and Kubernetes manifests
- 🧪 **Comprehensive Testing**: Full test suite with integration tests

## Quick Start

### 1. Build the Application

```bash
make compile
```

### 2. Start the Bridge

```bash
make start
```

### 3. Initialize Craftplan Connection

```bash
make init-bridge
```

### 4. Register Tools

```bash
make register-tools
```

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   elrmcp Client │    │   Bridge Core   │    │ Craftplan MCP   │
│                 │    │                 │    │                 │
│ • Request      │───▶│ • Tool Routing   │───▶│ • Tools        │
│ • Tools List   │    │ • Rate Limiting │    │ • Processing    │
│ • Tool Call    │    │ • Cache         │    │ • API Client   │
│ • Error Handling│    │ • Metrics       │    │                │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Configuration

### Bridge Configuration

```erlang
{
  "elrmcp_bridge": {
    "craftplan": {
      "url": "http://localhost:8090",
      "timeout": 30000
    },
    "rate_limiting": {
      "enabled": true,
      "requests_per_second": 100,
      "burst_size": 10
    },
    "tool_management": {
      "whitelist": [],
      "blacklist": [],
      "auto_register": true
    },
    "performance": {
      "enable_caching": true,
      "cache_ttl": 300000
    }
  }
}
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CRAFTPLAN_URL` | Craftplan MCP server URL | `http://localhost:8090` |
| `BRIDGE_TIMEOUT` | Request timeout in ms | `30000` |
| `BRIDGE_RATE_LIMIT` | Rate limit requests per second | `100` |
| `LOG_LEVEL` | Logging level | `info` |

## API Reference

### Core API

#### Initialize Bridge

```erlang
elrmcp_mcp_bridge:initialize_craftplan() -> ok | {error, term()}
```

#### Register Tools

```erlang
elrmcp_mcp_bridge:register_tools() -> ok | {error, term()}
```

#### List Available Tools

```erlang
elrmcp_mcp_bridge:list_available_tools() -> {ok, [tool_info()]} | {error, term()}
```

#### Get Tool Information

```erlang
elrmcp_mcp_bridge:get_tool_info(binary()) -> {ok, tool_info()} | {error, not_found}
```

#### Call Tool

```erlang
elrmcp_mcp_bridge:call_tool(binary(), map()) -> {ok, map()} | {error, term()}
```

#### Forward Request

```erlang
elrmcp_mcp_bridge:forward_request(binary(), map()) -> {ok, map()} | {error, term()}
```

### Tool Info Structure

```erlang
tool_info() :: #{
    name := binary(),
    description := binary(),
    input_schema := map(),
    output_schema => map(),
    category => binary(),
    version => binary()
}
```

## Testing

### Run Tests

```bash
# Run all tests
rebar3 ct

# Run specific test suite
rebar3 ct --suite elrmcp_mcp_bridge_SUITE

# Run with verbose output
rebar3 ct --verbose
```

### Test Coverage

```bash
rebar3 cover
```

## Deployment

### Kubernetes

```bash
# Using Helm
helm install elrmcp-bridge ./deployment/helm/elrmcp-bridge

# Using kubectl
kubectl apply -f deployment/k8s/
```

### Docker

```bash
# Build image
docker build -t elrmcp-bridge .

# Run container
docker run -p 8091:8091 elrmcp-bridge
```

## Monitoring

### Health Check

```bash
curl http://localhost:8091/health
```

### Bridge Status

```erlang
elrmcp_mcp_bridge:get_bridge_status() -> {ok, map()}
```

### Metrics

```bash
curl http://localhost:9090/metrics
```

## Performance

### Rate Limiting

The bridge implements a token bucket rate limiter:
- **Rate**: Configurable requests per second
- **Burst**: Configurable burst size
- **Refill**: Automatic token refill

### Caching

Intelligent caching for performance:
- **TTL**: Configurable cache time-to-live
- **Size**: Configurable cache size
- **Key**: Tool name + arguments

## Security

### Input Validation

- Schema validation for all inputs
- Size limits for requests
- Type checking
- Malicious content detection

### Output Sanitization

- Remove sensitive information
- Cleanse error messages
- Format standardization

### Access Control

- Tool whitelisting/blacklisting
- Rate limiting
- Request size limits

## Development

### Project Structure

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
├── config/                 # Configuration files
│   ├── bridge.config
│   ├── vm.args
│   └── rebar.config
├── deployment/            # Deployment manifests
│   ├── k8s/
│   └── helm/
└── docs/                  # Documentation
```

### Adding New Features

1. **Feature Branch**: Create from main
2. **Implementation**: Add feature with tests
3. **Documentation**: Update docs
4. **Testing**: Run full test suite
5. **Review**: Submit pull request

### Code Style

- Follow Erlang coding conventions
- Use type specifications
- Include docstrings
- Write comprehensive tests
- Use proper error handling

## Troubleshooting

### Common Issues

1. **Connection Failed**
   - Check Craftplan MCP server status
   - Verify URL and port
   - Check network connectivity

2. **Tool Registration Failed**
   - Check Craftplan MCP logs
   - Verify tool names
   - Check configuration

3. **Rate Limited**
   - Check rate limit settings
   - Monitor request frequency
   - Consider increasing limits

4. **High Latency**
   - Check network latency
   - Enable caching
   - Optimize tool calls

### Debug Mode

Enable debug logging:

```bash
export LOG_LEVEL=debug
make start
```

### Log Analysis

Check application logs:

```bash
tail -f logs/erlang.log.1
```

## Contributing

1. Fork the repository
2. Create feature branch
3. Write tests
4. Ensure all tests pass
5. Submit pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

- GitHub Issues: Report bugs and feature requests
- Documentation: See docs/ directory
- Examples: Check examples/ directory

## Changelog

### v1.0.0
- Initial release
- Basic MCP bridge functionality
- Tool registration and forwarding
- Rate limiting and caching
- Kubernetes deployment support