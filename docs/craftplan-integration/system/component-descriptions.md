# Component Descriptions

This document provides detailed descriptions of each component in the Craftplan MCP + A2A integration system, including their responsibilities, interfaces, and implementation details.

## 📦 Core Components

### 1. MCP Server (`craftplan_mcp_server`)

#### Overview
The MCP Server is the entry point for tool-based interactions. It exposes Craftplan ERP capabilities as MCP-compliant tools that can be discovered and used by AI agents.

#### Key Responsibilities
- **Tool Management**: Register, discover, and execute MCP tools
- **Protocol Handling**: Implement MCP 2024-11-05 specification
- **Authentication**: Handle authentication and authorization
- **Request Routing**: Route tool calls to appropriate handlers
- **Response Formatting**: Format responses according to MCP specification

#### Configuration
```erlang
%% craftplan_mcp_app.config
{
    port, 8090,
    host, "0.0.0.0",
    tools, [
        "customer_management",
        "order_management",
        "inventory_management",
        "production_planning",
        "analytics",
        "shipping"
    ],
    api_url, "http://localhost:4000/api",
    auth_token, "your-api-token",
    max_connections, 100,
    heartbeat_interval, "30s"
}
```

#### Available Tools
| Tool Name | Description | Operations |
|-----------|-------------|------------|
| `customer_management` | Manage customer records | list, get, create, update, delete |
| `order_management` | Manage orders | list, get, create, update, cancel, fulfill, refund |
| `inventory_management` | Manage products and inventory | list_products, get_product, create_product, update_product, check_stock, adjust_stock, low_stock_report, movement_history |
| `production_planning` | Plan and track production | list_orders, create_order, update_status, schedule, get_materials, record_production, quality_check |
| `analytics` | Generate business reports | sales_summary, revenue, inventory_value, production_efficiency, customer_metrics, product_performance, order_status_breakdown |
| `shipping` | Process shipments | create_shipment, track, list_carriers, get_rates, update_tracking, process_return |

#### API Endpoints
- `POST /mcp/list-tools` - List all available tools
- `POST /mcp/call-tool` - Execute a tool call
- `GET /health` - Health check endpoint
- `GET /metrics` - Metrics and monitoring data

### 2. A2A Agent (`craftplan_a2a_server`)

#### Overview
The A2A Agent implements the Agent2Agent Protocol to enable collaboration between AI agents. It maintains state and manages tasks that span multiple interactions.

#### Key Responsibilities
- **Agent Discovery**: Implement Agent Card exchange and discovery
- **Task Management**: Handle task lifecycle and state management
- **Message Routing**: Route messages between agents
- **Streaming Support**: Provide Server-Sent Events for real-time updates
- **State Persistence**: Maintain task state across interactions

#### Configuration
```erlang
%% craftplan_a2a_app.config
{
    port, 8080,
    host, "0.0.0.0",
    agent_id, "craftplan-erp-agent",
    agent_name, "Craftplan ERP Agent",
    skills, [
        "customer_management",
        "order_management",
        "inventory_management",
        "production_planning",
        "analytics",
        "shipping"
    ],
    max_concurrent_tasks, 50,
    task_timeout, "5m",
    sse_timeout, "30s"
}
```

#### Agent Capabilities
- **Multi-Tenant Support**: Handle multiple organizational contexts
- **Hot Code Upgrade**: Support runtime upgrades without downtime
- **Streaming**: Real-time progress updates
- **Collaboration**: Work with other agents on complex tasks

#### API Endpoints
- `POST /a2a/submit-task` - Submit a new task
- `GET /a2a/tasks/{task_id}` - Get task status and details
- `POST /a2a/tasks/{task_id}/cancel` - Cancel a task
- `GET /a2a/agent-card` - Get agent card
- `GET /a2a/stream/{task_id}` - SSE stream for task updates

### 3. MCP-A2A Bridge (`craftplan_a2a_bridge`)

#### Overview
The MCP-A2A Bridge is the translation layer that converts MCP tool calls to A2A skill invocations and manages the state between these two protocols.

#### Key Responsibilities
- **Protocol Translation**: Convert MCP tools to A2A skills
- **State Management**: Maintain context across protocol boundaries
- **Error Handling**: Handle and translate errors between protocols
- **Performance Optimization**: Cache and optimize cross-protocol calls
- **Monitoring**: Track bridge performance and usage

#### Tool-Skill Mapping
```erlang
%% Internal mapping
-define(TOOL_SKILL_MAP, #{
    <<"customer_management">> => <<"customer_management">>,
    <<"order_management">> => <<"order_management">>,
    <<"inventory_management">> => <<"inventory_management">>,
    <<"production_planning">> => <<"production_planning">>,
    <<"analytics">> => <<"analytics">>,
    <<"shipping">> => <<"shipping">>
}).
```

#### State Management
- **Task Context**: Maintain task state during execution
- **Session Persistence**: Preserve session data across requests
- **Cache Management**: Cache frequently accessed data
- **Cleanup**: Automatically clean up stale sessions

#### API Methods
- `register_skills/0` - Register all MCP tools as A2A skills
- `tool_to_skill/1` - Convert MCP tool name to A2A skill name
- `skill_to_tool/1` - Convert A2A skill name to MCP tool name
- `handle_a2a_task/2` - Handle A2A task execution

## 🔌 Support Components

### 4. API Client (`craftplan_api_client`)

#### Overview
The API Client handles communication with the Craftplan ERP system, providing a standardized interface for all business operations.

#### Key Responsibilities
- **HTTP Client**: Manage HTTP connections to ERP system
- **Authentication**: Handle API key and token authentication
- **Request Handling**: Format and send requests to ERP
- **Response Processing**: Parse and validate ERP responses
- **Error Handling**: Handle and translate ERP errors

#### Configuration
```erlang
%% API client configuration
{
    base_url, "http://localhost:4000/api",
    timeout, 30000,
    max_retries, 3,
    retry_delay, 1000,
    auth_header, "X-API-Key",
    api_token, "your-token"
}
```

#### Supported Operations
- **Customer Operations**: CRUD operations on customer data
- **Order Operations**: Order creation, management, and processing
- **Inventory Operations**: Product and stock management
- **Production Operations**: Production planning and tracking
- **Analytics Operations**: Report generation and data analysis
- **Shipping Operations**: Shipment tracking and processing

### 5. Task Handler (`craftplan_task_handler`)

#### Overview
The Task Handler manages individual task execution, including state transitions, progress tracking, and result compilation.

#### Key Responsibilities
- **Task Lifecycle**: Manage task states (submitted, working, completed, etc.)
- **Progress Tracking**: Update task progress and status
- **Error Recovery**: Handle task failures and retry logic
- **Result Compilation**: Collect and format task results
- **Logging**: Track task execution details

#### Task States
```erlang
-record(task, {
    id :: binary(),                    % Unique task identifier
    status :: submitted | working | input_required | auth_required | completed | failed | canceled,
    task_type :: binary(),             % Type of task
    created_at :: integer(),          % Creation timestamp
    updated_at :: integer(),          % Last update timestamp
    artifacts :: list(map()),         % Generated artifacts
    messages :: list(map()),          % Communication messages
    state :: term()                   % Task-specific state
}).
```

#### Task Operations
- `submit_task/2` - Submit a new task for execution
- `get_task/1` - Retrieve task details and status
- `cancel_task/1` - Cancel a running task
- `update_task_state/2` - Update task state and progress
- `add_artifact/3` - Add artifact to task results

### 6. Agent Card (`craftplan_agent_card`)

#### Overview
The Agent Card provides standardized information about the agent's capabilities and configuration, enabling agent discovery and negotiation.

#### Key Responsibilities
- **Capability Description**: Describe agent skills and abilities
- **Connection Information**: Provide connection details
- **Configuration Parameters**: Share runtime configuration
- **Authentication Requirements**: Specify auth requirements
- **Service Level Information**: Define performance expectations

#### Agent Card Structure
```json
{
    "agent_id": "craftplan-erp-agent",
    "agent_name": "Craftplan ERP Agent",
    "version": "1.0.0",
    "capabilities": [
        "customer_management",
        "order_management",
        "inventory_management",
        "production_planning",
        "analytics",
        "shipping"
    ],
    "connection": {
        "protocol": "a2a",
        "host": "localhost",
        "port": 8080,
        "path": "/a2a"
    },
    "authentication": {
        "type": "token",
        "endpoint": "/auth"
    },
    "performance": {
        "max_concurrent_tasks": 50,
        "average_response_time": "2s",
        "uptime": "99.9%"
    }
}
```

### 7. SSE Handler (`craftplan_sse_handler`)

#### Overview
The SSE Handler manages Server-Sent Events for real-time communication, providing live updates on task progress and system status.

#### Key Responsibilities
- **Connection Management**: Handle SSE client connections
- **Event Broadcasting**: Broadcast events to connected clients
- **Message Formatting**: Format events according to SSE specification
- **Connection Lifecycle**: Manage connection establishment and termination
- **Error Handling**: Handle connection errors and timeouts

#### Event Types
- `task_progress` - Task execution progress updates
- `task_completed` - Task completion notifications
- `task_failed` - Task failure notifications
- `system_status` - System status updates
- `heartbeat` - Periodic connection health checks

## 📊 Additional Components

### 8. Task Supervisor (`craftplan_task_sup`)

#### Overview
The Task Supervisor manages the pool of task handler processes, ensuring proper resource allocation and fault tolerance.

#### Key Responsibilities
- **Process Management**: Start, monitor, and restart task handlers
- **Resource Allocation**: Distribute tasks across available processes
- **Load Balancing**: Balance task load across workers
- **Fault Tolerance**: Handle process failures and recovery
- **Performance Monitoring**: Track task handler performance

### 9. Application Supervisor (`craftplan_a2a_sup`)

#### Overview
The Application Supervisor manages the overall application lifecycle, including all child processes and their dependencies.

#### Key Responsibilities
- **Process Hierarchy**: Manage the OTP process hierarchy
- **Dependency Management**: Ensure proper startup order
- **Health Monitoring**: Monitor child process health
- **Graceful Shutdown**: Handle application shutdown gracefully
- **Configuration Management**: Manage application configuration

### 10. Metrics Collection

#### Overview
The Metrics Collection component provides comprehensive monitoring and observability for the entire system.

#### Key Responsibilities
- **Request Metrics**: Track request volume and response times
- **Task Metrics**: Monitor task execution and completion rates
- **Error Metrics**: Track error rates and failure patterns
- **Resource Metrics**: Monitor CPU, memory, and network usage
- **Business Metrics**: Track business-specific KPIs

## 🔧 Configuration Management

### 11. Configuration System

#### Overview
The Configuration System manages all configuration parameters, supporting environment-specific settings and runtime updates.

#### Key Responsibilities
- **Configuration Loading**: Load configuration from files and environment
- **Environment Support**: Support different environments (dev, staging, prod)
- **Runtime Updates**: Allow configuration updates without restart
- **Validation**: Validate configuration parameters
- **Secret Management**: Handle sensitive configuration securely

Each component is designed to work together seamlessly while maintaining clear separation of concerns. This modular architecture allows for easy maintenance, scaling, and extension of the system.