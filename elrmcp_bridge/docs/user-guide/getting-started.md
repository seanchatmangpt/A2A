# Getting Started with elrmcp Bridge

This guide will help you get started with the elrmcp MCP bridge, connecting elrmcp to Craftplan MCP servers.

## Prerequisites

- Erlang/OTP 23+
- Craftplan MCP server running
- Basic knowledge of Erlang/OTP

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/elrmcp-bridge.git
cd elrmcp-bridge
```

### 2. Build the Application

```bash
make compile
```

### 3. Start the Bridge

```bash
make start
```

## Basic Usage

### 1. Initialize Connection to Craftplan MCP

```bash
make init-bridge
```

This command will:
- Connect to the Craftplan MCP server
- Initialize the HTTP client
- Prepare for tool registration

### 2. Register Available Tools

```bash
make register-tools
```

This will:
- Fetch available tools from Craftplan MCP
- Register them in the local registry
- Enable tool forwarding

### 3. Check Bridge Status

```bash
make show-status
```

Example output:
```json
{
  "status": "connected",
  "tools_count": 6,
  "metrics": {
    "total_requests": 0,
    "successful_requests": 0,
    "failed_requests": 0
  },
  "config": {
    "craftplan_url": "http://localhost:8090",
    "timeout": 30000,
    "rate_limit": 100
  },
  "cache_size": 0,
  "uptime": 1640995200000
}
```

### 4. List Available Tools

```bash
erl -pa _build/default/lib/*/ebin -eval "
case elrmcp_mcp_bridge:list_available_tools() of
    {ok, Tools} ->
        io:format('~ts~n', [jsx:encode(Tools)]);
    Error ->
        io:format('Error: ~p~n', [Error])
end,
halt().
"
```

Example output:
```json
[
  {
    "name": "customer_management",
    "description": "Create, read, update, and delete customer records",
    "inputSchema": {
      "type": "object",
      "properties": {
        "operation": {
          "type": "string",
          "enum": ["list", "get", "create", "update", "delete"]
        },
        "customer_id": {"type": "string"},
        "customer_data": {"type": "object"}
      },
      "required": ["operation"]
    },
    "category": "craftplan",
    "version": "1.0.0"
  }
]
```

### 5. Call a Tool

```bash
erl -pa _build/default/lib/*/ebin -eval "
Args = #{operation => list},
case elrmcp_mcp_bridge:call_tool(<<\"customer_management\">>, Args) of
    {ok, Result} ->
        io:format('~ts~n', [jsx:encode(Result)]);
    Error ->
        io:format('Error: ~p~n', [Error])
end,
halt().
"
```

## Configuration

### Basic Configuration

Edit `config/bridge.config` to customize the bridge:

```json
{
  "elrmcp_bridge": {
    "craftplan": {
      "url": "http://craftplan-mcp:8090",
      "timeout": 30000
    },
    "rate_limiting": {
      "enabled": true,
      "requests_per_second": 100,
      "burst_size": 10
    },
    "tool_management": {
      "whitelist": [],
      "blacklist": ["internal_only"],
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

Set environment variables for runtime configuration:

```bash
export CRAFTPLAN_URL="http://localhost:8090"
export BRIDGE_TIMEOUT="30000"
export BRIDGE_RATE_LIMIT="100"
export LOG_LEVEL="info"
```

## Advanced Usage

### 1. Tool Whitelisting/Blacklisting

Restrict which tools are available through the bridge:

```json
{
  "tool_management": {
    "whitelist": ["customer_management", "order_management"],
    "blacklist": ["admin_tools"]
  }
}
```

### 2. Rate Limiting

Configure rate limiting to prevent abuse:

```json
{
  "rate_limiting": {
    "enabled": true,
    "requests_per_second": 50,
    "burst_size": 5,
    "refill_interval_ms": 1000
  }
}
```

### 3. Caching

Enable caching for frequently used tools:

```json
{
  "performance": {
    "enable_caching": true,
    "cache_size": 1000,
    "cache_ttl": 600000
  }
}
```

## Monitoring

### Health Check

```bash
curl http://localhost:8091/health
```

Example response:
```json
{
  "status": "healthy",
  "server": "elrmcp-bridge",
  "version": "1.0.0",
  "timestamp": 1640995200000
}
```

### Metrics Access

```bash
curl http://localhost:9090/metrics
```

Example metrics:
```prometheus
# elrmcp_bridge_requests_total
elrmcp_bridge_requests_total{status="success", tool="customer_management"} 100
elrmcp_bridge_requests_total{status="error", tool="order_management"} 5

# elrmcp_bridge_cache_hits_total
elrmcp_bridge_cache_hits_total{tool="customer_management"} 50

# elrmcp_bridge_rate_limit_denied_total
elrmcp_bridge_rate_limit_denied_total 10
```

## Troubleshooting

### Common Issues

1. **Connection Failed**
   - Ensure Craftplan MCP server is running
   - Verify URL and port configuration
   - Check network connectivity

2. **Tool Registration Failed**
   - Check Craftplan MCP server logs
   - Verify tool names and schemas
   - Check authentication if required

3. **Rate Limited**
   - Monitor request frequency
   - Adjust rate limiting settings
   - Consider increasing limits

4. **High Latency**
   - Enable caching
   - Check network latency
   - Optimize tool calls

### Debug Mode

Enable debug logging for troubleshooting:

```bash
export LOG_LEVEL=debug
make start
```

### Log Analysis

Check application logs:

```bash
tail -f logs/erlang.log.1
```

### Performance Tuning

1. **Increase Cache Size**
   ```json
   {
     "performance": {
       "enable_caching": true,
       "cache_size": 5000,
       "cache_ttl": 900000
     }
   }
   ```

2. **Adjust Rate Limits**
   ```json
   {
     "rate_limiting": {
       "requests_per_second": 200,
       "burst_size": 20
     }
   }
   ```

3. **Increase Timeouts**
   ```json
   {
     "craftplan": {
       "timeout": 60000
     }
   }
   ```

## Next Steps

- Explore the [API Documentation](../api/README.md)
- Learn about [Deployment Options](../deployment/README.md)
- Read about [Advanced Configuration](../configuration.md)
- Check the [Troubleshooting Guide](../troubleshooting.md)