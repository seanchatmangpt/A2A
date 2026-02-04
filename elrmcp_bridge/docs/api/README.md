# API Documentation

This document provides comprehensive API documentation for the elrmcp MCP bridge.

## Core API

### elrmcp_mcp_bridge

Main module for bridge functionality.

#### initialize_craftplan()

Initialize connection to Craftplan MCP server.

**Returns**
- `ok` - Successfully initialized
- `{error, Reason}` - Initialization failed

**Example**
```erlang
case elrmcp_mcp_bridge:initialize_craftplan() of
    ok -> io:format("Initialized successfully\n");
    {error, Reason} -> io:format("Failed: ~p\n", [Reason])
end
```

#### register_tools()

Register available tools from Craftplan MCP.

**Returns**
- `ok` - Successfully registered tools
- `{error, Reason}` - Registration failed

**Example**
```erlang
case elrmcp_mcp_bridge:register_tools() of
    ok -> io:format("Tools registered\n");
    {error, Reason} -> io:format("Registration failed: ~p\n", [Reason])
end
```

#### list_available_tools()

List all available tools from both elrmcp and Craftplan.

**Returns**
- `{ok, [tool_info()]}` - List of available tools
- `{error, Reason}` - Failed to retrieve tools

**Example**
```erlang
{ok, Tools} = elrmcp_mcp_bridge:list_available_tools(),
io:format("Available tools: ~p\n", [Tools]).
```

#### get_tool_info(ToolName)

Get detailed information about a specific tool.

**Parameters**
- `ToolName` (binary) - Name of the tool

**Returns**
- `{ok, tool_info()}` - Tool information
- `{error, not_found}` - Tool not found

**Example**
```erlang
case elrmcp_mcp_bridge:get_tool_info(<<"customer_management">>) of
    {ok, Tool} -> io:format("Tool: ~ts\n", [jsx:encode(Tool)]);
    {error, not_found} -> io:format("Tool not found\n")
end
```

#### call_tool(ToolName, Arguments)

Call a tool directly through the bridge.

**Parameters**
- `ToolName` (binary) - Name of the tool to call
- `Arguments` (map) - Tool arguments

**Returns**
- `{ok, map()}` - Tool execution result
- `{error, Reason}` - Execution failed

**Example**
```erlang
Args = #{operation => list, customer_id => <<"cust_123">>},
case elrmcp_mcp_bridge:call_tool(<<"customer_management">>, Args) of
    {ok, Result} -> io:format("Result: ~ts\n", [jsx:encode(Result)]);
    {error, Reason} -> io:format("Error: ~p\n", [Reason])
end
```

#### forward_request(ToolName, Arguments)

Forward a request to Craftplan MCP.

**Parameters**
- `ToolName` (binary) - Name of the tool
- `Arguments` (map) - Request arguments

**Returns**
- `{ok, map()}` - Forwarded request result
- `{error, Reason}` - Forwarding failed

**Example**
```erlang
Args = #{operation => create, customer_data => #{name => <<"John">>, email => <<"john@example.com">>}},
case elrmcp_mcp_bridge:forward_request(<<"customer_management">>, Args) of
    {ok, Result} -> io:format("Forwarded result: ~ts\n", [jsx:encode(Result)]);
    {error, Reason} -> io:format("Forwarding error: ~p\n", [Reason])
end
```

#### configure_bridge(Config)

Configure bridge settings.

**Parameters**
- `Config` (map) - Configuration map

**Returns**
- `ok` - Configuration updated
- `{error, Reason}` - Configuration failed

**Example**
```erlang
Config = #{
    craftplan_url => <<"http://localhost:9000">>,
    timeout => 50000,
    rate_limit => 50
},
elrmcp_mcp_bridge:configure_bridge(Config).
```

#### get_bridge_status()

Get bridge status and metrics.

**Returns**
- `{ok, map()}` - Bridge status

**Example**
```erlang
{ok, Status} = elrmcp_mcp_bridge:get_bridge_status(),
io:format("Status: ~ts\n", [jsx:encode(Status)]).
```

### Tool Info Structure

```erlang
tool_info() :: #{
    name := binary(),                  % Tool name
    description := binary(),           % Tool description
    input_schema := map(),             % JSON schema for input
    output_schema => map(),            % JSON schema for output
    category => binary(),              % Tool category
    version => binary()                % Tool version
}.
```

### Input Schema

```erlang
input_schema() :: #{
    type := object,
    properties := map(),
    required := [binary()],            % Required fields
    additionalProperties := boolean()
}.
```

## HTTP API

The bridge exposes an HTTP API for external access.

### Endpoints

#### POST /mcp

Handle MCP JSON-RPC requests.

**Request**
```json
{
  "jsonrpc": "2.0",
  "method": "tools/list",
  "id": "123"
}
```

**Response**
```json
{
  "jsonrpc": "2.0",
  "result": {
    "tools": [
      {
        "name": "customer_management",
        "description": "Create, read, update, and delete customer records",
        "inputSchema": {
          "type": "object",
          "properties": {
            "operation": {
              "type": "string",
              "enum": ["list", "get", "create", "update", "delete"]
            }
          },
          "required": ["operation"]
        }
      }
    ]
  },
  "id": "123"
}
```

#### GET /health

Health check endpoint.

**Response**
```json
{
  "status": "healthy",
  "server": "elrmcp-bridge",
  "version": "1.0.0",
  "timestamp": 1640995200000
}
```

#### GET /.well-known/agent-card

Agent card information.

**Response**
```json
{
  "agent": {
    "name": "elrmcp-bridge",
    "version": "1.0.0",
    "description": "elrmcp MCP Bridge",
    "protocols": ["mcp"]
  }
}
```

### Supported Methods

#### tools/list

List all available tools.

**Parameters**
None

**Response**
```json
{
  "jsonrpc": "2.0",
  "result": {
    "tools": [tool_info()]
  },
  "id": "request_id"
}
```

#### tools/call

Call a tool.

**Parameters**
```json
{
  "name": "tool_name",
  "arguments": {
    "operation": "list"
  }
}
```

**Response**
```json
{
  "jsonrpc": "2.0",
  "result": {
    "result": {}
  },
  "id": "request_id"
}
```

#### tools/get

Get tool information.

**Parameters**
```json
{
  "name": "tool_name"
}
```

**Response**
```json
{
  "jsonrpc": "2.0",
  "result": {
    "name": "tool_name",
    "description": "Tool description",
    "inputSchema": {}
  },
  "id": "request_id"
}
```

## Error Handling

### Error Codes

| Code | Message | Description |
|------|---------|-------------|
| -32601 | Method not found | Requested method doesn't exist |
| -32602 | Invalid params | Invalid parameters provided |
| -32603 | Internal error | Internal server error |
| -32700 | Parse error | Invalid JSON-RPC request |
| -32000 | Bridge error | Bridge-specific error |
| -32001 | Rate limited | Request rate exceeded |

### Error Response Format

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32000,
    "message": "Error message",
    "data": {
      "type": "error_type",
      "details": "Additional details"
    }
  },
  "id": "request_id"
}
```

### Common Errors

#### Rate Limited

```json
{
  "error": {
    "code": -32001,
    "message": "Rate limit exceeded",
    "data": {
      "type": "rate_limited",
      "retry_after": 1000
    }
  }
}
```

#### Tool Not Found

```json
{
  "error": {
    "code": -32601,
    "message": "Tool not found",
    "data": {
      "type": "tool_not_found",
      "tool_name": "unknown_tool"
    }
  }
}
```

#### Invalid Arguments

```json
{
  "error": {
    "code": -32602,
    "message": "Invalid arguments",
    "data": {
      "type": "invalid_arguments",
      "validation_errors": ["missing_field: operation"]
    }
  }
}
```

## Metrics

The bridge exposes metrics in Prometheus format at `/metrics`.

### Available Metrics

#### Counter Metrics

- `elrmcp_bridge_requests_total` - Total requests
  - Labels: `status`, `tool`
- `elrmcp_bridge_cache_hits_total` - Cache hits
  - Labels: `tool`
- `elrmcp_bridge_cache_misses_total` - Cache misses
  - Labels: `tool`
- `elrmcp_bridge_rate_limit_denied_total` - Rate limit denials
- `elrmcp_bridge_errors_total` - Total errors
  - Labels: `error_type`, `tool`

#### Gauge Metrics

- `elrmcp_bridge_active_requests` - Active requests
- `elrmcp_bridge_cache_size` - Current cache size
- `elrmcp_bridge_tokens_available` - Available rate limit tokens

#### Histogram Metrics

- `elrmcp_bridge_request_duration_seconds` - Request duration
- `elrmcp_bridge_cache_hit_duration_seconds` - Cache hit duration

### Example Metrics Output

```prometheus
# HELP elrmcp_bridge_requests_total Total number of requests
# TYPE elrmcp_bridge_requests_total counter
elrmcp_bridge_requests_total{status="success", tool="customer_management"} 100
elrmcp_bridge_requests_total{status="error", tool="order_management"} 5

# HELP elrmcp_bridge_request_duration_seconds Request duration in seconds
# TYPE elrmcp_bridge_request_duration_seconds histogram
elrmcp_bridge_request_duration_seconds_bucket{le="0.1"} 95
elrmcp_bridge_request_duration_seconds_bucket{le="1.0"} 98
elrmcp_bridge_request_duration_seconds_bucket{le="+Inf"} 100
elrmcp_bridge_request_duration_seconds_sum 50.5
elrmcp_bridge_request_duration_seconds_count 100

# HELP elrmcp_bridge_cache_size Current cache size
# TYPE elrmcp_bridge_cache_size gauge
elrmcp_bridge_cache_size 45

# HELP elrmcp_bridge_tokens_available Available rate limit tokens
# TYPE elrmcp_bridge_tokens_available gauge
elrmcp_bridge_tokens_available 85
```

## WebSocket API

The bridge supports WebSocket connections for real-time communication.

### Connection

Connect to `/ws/mcp` endpoint.

### Message Format

```json
{
  "jsonrpc": "2.0",
  "method": "tools/list",
  "id": "123"
}
```

### Subscription

Subscribe to tool events:

```json
{
  "jsonrpc": "2.0",
  "method": "tools/subscribe",
  "params": {
    "events": ["tool_called", "tool_completed", "tool_failed"]
  },
  "id": "123"
}
```

### Event Notifications

```json
{
  "jsonrpc": "2.0",
  "method": "tools/notification",
  "params": {
    "event": "tool_called",
    "tool_name": "customer_management",
    "timestamp": 1640995200000,
    "request_id": "req_123"
  }
}
```

## Rate Limiting

### Token Bucket Algorithm

The bridge uses a token bucket rate limiter with configurable parameters:

- **Rate**: Tokens added per second
- **Burst**: Maximum tokens in bucket
- **Refill**: Automatic token replenishment

### Rate Limit Headers

- `X-RateLimit-Limit`: Request limit per window
- `X-RateLimit-Remaining`: Remaining requests in window
- `X-RateLimit-Reset`: Time when window resets

### Example Response with Rate Limit

```http
HTTP/1.1 200 OK
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1640995260
Content-Type: application/json
```

## Authentication

### API Key Authentication

```erlang
elrmcp_mcp_bridge:configure_bridge(#{auth_token => <<"your-api-key">>}).
```

### JWT Authentication

```erlang
elrmcp_mcp_bridge:configure_bridge(#{auth_token => <<"your.jwt.token">>}).
```

### Custom Authentication

Implement custom authentication in the bridge configuration.