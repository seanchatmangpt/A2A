# Craftplan MCP + A2A Superpowers

This integration adds **Model Context Protocol (MCP)** and **Agent-to-Agent (A2A)** capabilities to Craftplan ERP, enabling:

1. **AI Assistant Integration** - AI assistants can call MCP tools to interact with Craftplan
2. **Multi-Agent Workflows** - Craftplan can collaborate with other business agents
3. **HotCI Support** - Hot code upgrades without downtime

## What's New

### MCP Server (Port 8090)

Exposes Craftplan ERP capabilities as standard MCP tools:

| Tool | Description |
|------|-------------|
| `customer_management` | Create/read/update/delete customers |
| `order_management` | Process orders, cancel, fulfill |
| `inventory_management` | Check stock, adjust levels |
| `production_planning` | Create and track production orders |
| `analytics` | Generate business reports |
| `shipping` | Create shipments, track packages |

### A2A Agent (Port 8080)

Enables agent-to-agent collaboration with:

- **Task submission** via JSON-RPC
- **Real-time updates** via Server-Sent Events (SSE)
- **Agent discovery** via Agent Card at `/.well-known/agent-card`
- **Delegation support** for multi-agent workflows

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AI Assistant / User                       │
└────────────────────────┬────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
┌───────▼────────┐  ┌────▼──────────┐  ┌─▼──────────────────┐
│  MCP Endpoint  │  │  A2A Endpoint │  │  HTTP API          │
│  (tool calls)  │  │  (tasks)      │  │  (direct access)   │
│  Port 8090     │  │  Port 8080    │  │  Port 4000         │
└───────┬────────┘  └────┬──────────┘  └─┬──────────────────┘
        │                │                │
        └────────────────┼────────────────┘
                         │
               ┌─────────▼─────────┐
               │   Craftplan      │
               │   ERP Backend    │
               │   (Phoenix/Elixir)│
               └───────────────────┘
```

## Quick Start

### 1. Generate Secrets

```bash
cd craftplan
./generate-secrets.sh
```

### 2. Deploy Stack

```bash
./deploy.sh up
```

### 3. Verify Services

```bash
# Check MCP Server
curl http://localhost:8090/health
curl http://localhost:8090/.well-known/agent-card

# Check A2A Agent
curl http://localhost:8080/health
curl http://localhost:8080/.well-known/agent-card

# List MCP tools
curl -X POST http://localhost:8090/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
```

## Usage Examples

### MCP Tool Call - Create Order

```json
POST /mcp
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "order_management",
    "arguments": {
      "operation": "create",
      "order_data": {
        "customer_id": "cust_123",
        "items": [
          {"product_id": "prod_456", "quantity": 2}
        ]
      }
    }
  },
  "id": 1
}
```

### A2A Task Submission

```json
POST /a2a
{
  "jsonrpc": "2.0",
  "method": "task.submit",
  "params": {
    "task_type": "inventory_management",
    "params": {
      "operation": "check_stock",
      "product_id": "prod_456"
    }
  },
  "id": 1
}
```

### Multi-Agent Collaboration

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Shop Manager   │────▶│  Craftplan ERP  │────▶│  Supplier Agent │
│  (User/Assistant)│     │  (A2A Agent)   │     │  (External)     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌─────────────────┐
                        │  Shipping Agent │
                        │  (External)     │
                        └─────────────────┘
```

1. User submits "low stock" alert to Craftplan
2. Craftplan A2A agent discovers Supplier agent
3. Craftplan delegates reordering to Supplier agent
4. Shipping agent handles fulfillment
5. Real-time updates via SSE

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CRAFTPLAN_API_URL` | `http://craftplan:4000/api` | Craftplan backend API |
| `CRAFTPLAN_API_TOKEN` | | API authentication token |
| `MCP_PORT` | `8090` | MCP server port |
| `A2A_PORT` | `8080` | A2A agent port |
| `AGENT_ID` | `craftplan-erp-agent` | A2A agent identifier |
| `LOG_LEVEL` | `info` | Logging verbosity |

## Scaling

```bash
# Scale MCP servers
docker service scale craftplan_craftplan-mcp-server=3

# Scale A2A agents
docker service scale craftplan_craftplan-a2a-agent=2
```

## HotCI Upgrades

Both services support zero-downtime upgrades:

```bash
# Deploy new version
docker service update --image craftplan-mcp:1.1.0 craftplan_craftplan-mcp-server

# Automatic rollback if issues detected
docker service update --rollback craftplan_craftplan-mcp-server
```

## Monitoring

Metrics available at `/metrics`:

- `craftplan_mcp_tool_calls_total` - Total tool invocations
- `craftplan_mcp_tool_duration_seconds` - Tool execution time
- `craftplan_a2a_tasks_total` - Total tasks submitted
- `craftplan_a2a_tasks_active` - Currently running tasks

## File Structure

```
craftplan/
├── docker-compose.stack.yml    # Updated with MCP/A2A services
├── mcp-server/                 # MCP Server implementation
│   ├── src/
│   │   ├── craftplan_mcp_server.erl
│   │   ├── craftplan_api_client.erl
│   │   ├── craftplan_a2a_bridge.erl
│   │   └── ...
│   ├── Dockerfile
│   └── rebar.config
├── a2a-agent/                  # A2A Agent implementation
│   ├── src/
│   │   ├── craftplan_a2a_server.erl
│   │   ├── craftplan_task_handler.erl
│   │   └── ...
│   ├── Dockerfile
│   └── rebar.config
├── agent-card/
│   └── agent-card.json         # Agent discovery metadata
├── ontology/
│   └── craftplan-mcp.ttl       # RDF ontology for code generation
└── docs/
    └── MCP_A2A_INTEGRATION.md  # Detailed documentation
```

## Building from Source

### MCP Server

```bash
cd craftplan/mcp-server
rebar3 compile
rebar3 release
./_build/default/rel/craftplan_mcp/bin/craftplan_mcp foreground
```

### A2A Agent

```bash
cd craftplan/a2a-agent
rebar3 compile
rebar3 release
./_build/default/rel/craftplan_a2a/bin/craftplan_a2a foreground
```

## Code Generation with GGen

Generate Craftplan MCP + A2A code from ontology:

```bash
cd ggen
ggen generate craftplan --output ../craftplan/generated
```

## Troubleshooting

### MCP Server Issues

```bash
# Check logs
docker logs craftplan_craftplan-mcp-server

# Test health endpoint
curl -v http://localhost:8090/health

# Check connectivity to Craftplan backend
docker exec craftplan-mcp-server ping craftplan
```

### A2A Agent Issues

```bash
# Check logs
docker logs craftplan_craftplan-a2a-agent

# Verify agent card
curl http://localhost:8080/.well-known/agent-card | jq

# Check task status
curl -X POST http://localhost:8080/a2a \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"task.list","id":1}'
```

## References

- [MCP Specification](https://modelcontextprotocol.io/)
- [A2A Specification](../docs/specification.md)
- [Craftplan Documentation](https://github.com/puemos/craftplan)
- [HotCI Documentation](../vendors/HotCI/README.md)
- [GGen Documentation](../ggen/README.md)

## License

This integration follows the same license as Craftplan (AGPLv3).
