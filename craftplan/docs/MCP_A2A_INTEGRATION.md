# Craftplan MCP + A2A Integration

This document describes the Model Context Protocol (MCP) and Agent-to-Agent (A2A) integration for Craftplan ERP.

## Overview

The integration adds two new services to the Craftplan stack:

1. **Craftplan MCP Server** - Exposes ERP capabilities as MCP tools
2. **Craftplan A2A Agent** - Enables agent-to-agent collaboration via A2A protocol

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AI Assistant / User                       │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │   Discovery      │
                    │ (Agent Card)     │
                    └─────────┬─────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
┌───────▼────────┐   ┌───────▼──────────┐   ┌────▼─────────┐
│  MCP Protocol  │   │   A2A Protocol   │   │    HTTP API   │
│  (tool calls)  │   │ (agent collab)   │   │  (direct)     │
└───────┬────────┘   └───────┬──────────┘   └────┬─────────┘
        │                     │                     │
┌───────▼────────┐   ┌───────▼──────────┐   ┌────▼─────────┐
│  MCP Server    │   │   A2A Agent      │   │  Craftplan   │
│  (8090)        │◄──┤   (8080)         │◄──│  Phoenix App │
│  - Tools       │   │  - Tasks         │   │  (4000)      │
│  - Resources   │   │  - Messages      │   │  - Business  │
└───────┬────────┘   └───────┬──────────┘   └────┬─────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │   PostgreSQL      │
                    │   MinIO           │
                    │   Redis           │
                    └───────────────────┘
```

## MCP Tools

The MCP server exposes the following tools:

### customer_management
- **Operations**: list, get, create, update, delete
- **Description**: Manage customer records
- **Input**: `{"operation": "list", "limit": 50}`

### order_management
- **Operations**: list, get, create, update, cancel, fulfill
- **Description**: Create and manage orders
- **Input**: `{"operation": "create", "order_data": {...}}`

### inventory_management
- **Operations**: list_products, get_product, check_stock, adjust_stock
- **Description**: Manage products and inventory
- **Input**: `{"operation": "check_stock", "product_id": "..."}`

### production_planning
- **Operations**: list_orders, create_order, update_status, schedule
- **Description**: Plan and track production
- **Input**: `{"operation": "create_order", "order_data": {...}}`

### analytics
- **Operations**: sales_summary, revenue, inventory_value, production_efficiency
- **Description**: Generate business reports
- **Input**: `{"report_type": "sales_summary", "date_range": {...}}`

### shipping
- **Operations**: create_shipment, track, list_carriers, get_rates
- **Description**: Process shipments and tracking
- **Input**: `{"operation": "track", "tracking_number": "..."}`

## A2A Skills

The A2A agent exposes the same capabilities as skills for agent collaboration:

| Skill | Description | Collaboration Use Case |
|-------|-------------|----------------------|
| customer_management | Customer CRUD | Share customer data with sales agents |
| order_management | Order processing | Coordinate with fulfillment agents |
| inventory_management | Stock control | Alert suppliers when stock is low |
| production_planning | Production scheduling | Coordinate with manufacturing agents |
| analytics | Reporting | Provide data to analytics agents |
| shipping | Fulfillment | Coordinate with logistics agents |

## Usage Examples

### MCP Tool Call

```json
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
{
  "jsonrpc": "2.0",
  "method": "task.submit",
  "params": {
    "task_type": "order_management",
    "params": {
      "operation": "create",
      "order_data": {...}
    }
  },
  "id": 1
}
```

### Multi-Agent Workflow

```erlang
%% Agent A (Shop Manager) submits task to Craftplan
{ok, TaskId} = craftplan_a2a_server:submit_task(
    <<"order_management">>,
    #{<<"operation">> => <<"create">>, order_data => {...}}
),

%% Craftplan processes and notifies via SSE
%% Agent B (Fulfillment) gets notified and handles shipping
```

## Deployment

### Quick Start

```bash
cd craftplan
./generate-secrets.sh
./deploy.sh up
```

### Access Points

| Service | URL | Description |
|---------|-----|-------------|
| Craftplan | http://localhost:4000 | Main ERP application |
| MCP Server | http://localhost:8090 | MCP endpoint |
| MCP Health | http://localhost:8090/health | Health check |
| A2A Agent | http://localhost:8080/a2a | A2A endpoint |
| A2A Health | http://localhost:8080/health | Health check |
| SSE Stream | http://localhost:8080/sse | Real-time events |
| Agent Card | http://localhost:8080/.well-known/agent-card | Discovery |

## Environment Variables

```bash
# MCP Server
CRAFTPLAN_API_URL=http://craftplan:4000/api
CRAFTPLAN_API_TOKEN=
MCP_PORT=8090

# A2A Agent
A2A_PORT=8080
MCP_SERVER_URL=http://craftplan-mcp-server:8090/mcp
AGENT_ID=craftplan-erp-agent
```

## Scaling

```bash
# Scale MCP servers
./deploy.sh scale craftplan-mcp-server=3

# Scale A2A agents
./deploy.sh scale craftplan-a2a-agent=2
```

## HotCI Support

Both MCP Server and A2A Agent support hot code upgrades via HotCI:

```bash
# Trigger upgrade (from new release)
docker service update craftplan_craftplan-mcp-server --image craftplan-mcp:1.1.0

# Automatic rollback on failure (after 5 minutes)
docker service update craftplan_craftplan-mcp-server --rollback
```

## Monitoring

Metrics are exposed at `/metrics` on both services:

- `craftplan_mcp_tool_calls_total` - Total tool invocations
- `craftplan_mcp_tool_duration_seconds` - Tool execution time
- `craftplan_a2a_tasks_total` - Total tasks submitted
- `craftplan_a2a_task_duration_seconds` - Task processing time

## Security

### Authentication

Both services support Bearer token authentication:

```bash
curl -H "Authorization: Bearer $TOKEN" http://localhost:8090/mcp
```

### TLS/TLS

Enable via Traefik labels:

```yaml
labels:
  - "traefik.http.routers.craftplan-mcp.tls=true"
  - "traefik.http.routers.craftplan-mcp.tls.certresolver=letsencrypt"
```

## Development

### Building

```bash
# Build MCP server
cd mcp-server
rebar3 compile
rebar3 release

# Build A2A agent
cd ../a2a-agent
rebar3 compile
rebar3 release
```

### Testing

```bash
# Run tests
rebar3 ct

# Run with coverage
rebar3 cover --verbose
```

## Troubleshooting

### MCP Server not responding

```bash
# Check health
curl http://localhost:8090/health

# View logs
docker logs craftplan_craftplan-mcp-server
```

### A2A Agent not connecting

```bash
# Check agent status
curl http://localhost:8080/health

# View agent card
curl http://localhost:8080/.well-known/agent-card
```

### Connection issues between services

```bash
# Check network
docker network inspect craftplan_craftplan_network

# Test connectivity
docker exec craftplan-mcp-server ping craftplan
```

## References

- [MCP Specification](https://modelcontextprotocol.io/)
- [A2A Specification](https://a2a.com/specification)
- [Craftplan Documentation](https://github.com/puemos/craftplan)
- [HotCI Documentation](../vendors/HotCI/README.md)
