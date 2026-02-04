# Architecture Overview

This document provides a comprehensive overview of the Craftplan MCP + A2A integration architecture. The system is designed to enable seamless integration between Model Context Protocol (MCP) servers and the Agent2Agent (A2A) Protocol for enterprise ERP systems.

## 🏗️ High-Level Architecture

### System Components Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                             Client Applications                          │
│                   (Claude Desktop, Custom Clients)                      │
└─────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         MCP Client Layer                                │
│          (Standard MCP Protocol Implementation)                         │
└─────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         MCP Server Layer                                │
│        (craftplan_mcp_server - Port 8090)                             │
└─────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      MCP-A2A Bridge Layer                              │
│            (craftplan_a2a_bridge - Translation Logic)                  │
└─────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         A2A Agent Layer                               │
│          (craftplan_a2a_server - Port 8080)                            │
└─────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         Craftplan ERP                                  │
│           (HTTP API - Craftplan System)                                │
└─────────────────────────────────────────────────────────────────────────┘
```

## 🎯 Core Components

### 1. MCP Server Layer (`craftplan_mcp_server`)
- **Purpose**: Exposes ERP capabilities as MCP tools
- **Protocol**: MCP 2024-11-05 over HTTP(S)
- **Port**: 8090
- **Responsibilities**:
  - Tool discovery and listing
  - Tool execution and parameter validation
  - Authentication and authorization
  - Request routing and response formatting

### 2. MCP-A2A Bridge (`craftplan_a2a_bridge`)
- **Purpose**: Translates MCP tools to A2A skills
- **Protocol**: Internal Erlang messaging
- **Responsibilities**:
  - Tool-to-skill mapping
  - State management across protocols
  - Error handling and recovery
  - Protocol-specific optimizations

### 3. A2A Agent Layer (`craftplan_a2a_server`)
- **Purpose**: Implements A2A protocol for agent collaboration
- **Protocol**: A2A v1.0 over HTTP(S)
- **Port**: 8080
- **Responsibilities**:
  - Agent discovery and agent cards
  - Task management and lifecycle
  - Message routing and state management
  - Streaming support (SSE)

### 4. Craftplan ERP Integration
- **Purpose**: Provides backend ERP functionality
- **Protocol**: HTTP/REST API
- **Responsibilities**:
  - Business logic execution
  - Data persistence and retrieval
  - Transaction management
  - External system integration

## 🔧 Layer Interactions

### MCP Tool Invocation Flow
1. **Client** → **MCP Server**: Tool call via MCP protocol
2. **MCP Server** → **MCP-A2A Bridge**: Translate tool to skill
3. **MCP-A2A Bridge** → **A2A Agent**: Execute as A2A task
4. **A2A Agent** → **Craftplan ERP**: Execute business logic
5. **Craftplan ERP** → **A2A Agent**: Return results
6. **A2A Agent** → **MCP-A2A Bridge**: Format as MCP response
7. **MCP-A2A Bridge** → **MCP Server**: Final MCP response
8. **MCP Server** → **Client**: Return tool result

### A2A Task Management Flow
1. **Agent Discovery**: Agents exchange Agent Cards via A2A
2. **Task Submission**: One agent submits task to another
3. **Task Processing**: Bridge translates to MCP calls
4. **State Management**: Maintains task state across protocol boundaries
5. **Streaming Updates**: Real-time progress updates via SSE
6. **Completion**: Task completion with artifacts and results

## 🔄 Protocol Translation

### MCP to A2A Mapping
```erlang
% MCP Tool Definition
mcp_tool("customer_management", #{
    description => "Manage customer records",
    input_schema => #{...},
    output_schema => #{...}
}).

% A2A Skill Definition
a2a_skill("customer_management", #{
    description => "Manage customer records",
    parameters => [...],
    capabilities => ["read", "write", "delete"]
}).

% Bridge Mapping
bridge_mapping(#{
    tool => "customer_management",
    skill => "customer_management",
    protocol => "mcp_to_a2a"
}).
```

### State Management Across Protocols
- **MCP**: Stateless tool invocations
- **A2A**: Stateful task management
- **Bridge**: Maintains task context and state persistence
- **ERP**: Business state management

## 🏗️ System Requirements

### Infrastructure Requirements
- **Erlang/OTP**: 27.0 or higher
- **Memory**: Minimum 2GB RAM, Recommended 4GB+
- **Storage**: 10GB+ for logs and temporary files
- **Network**: TCP/UDP access to ports 8080, 8090
- **Operating System**: Linux, macOS, or Windows (WSL2)

### External Dependencies
- **Craftplan ERP**: v2.0+ with REST API
- **HTTP Server**: Cowboy (included)
- **JSON Processing**: Jiffy (included)
- **Monitoring**: Built-in metrics and logging

## 🔒 Security Architecture

### Authentication Layers
1. **MCP Level**: Token-based authentication
2. **A2A Level**: OAuth 2.0 / JWT tokens
3. **ERP Level**: API key authentication
4. **Network Level**: TLS 1.3 encryption

### Authorization Patterns
- **Role-Based Access Control (RBAC)**
- **Resource-Based Permissions**
- **Multi-Tenant Isolation**
- **Protocol-Specific Scopes**

## 📊 Monitoring and Observability

### Metrics Collection
- **Request Volume**: Track MCP and A2A requests
- **Response Times**: Measure performance across layers
- **Error Rates**: Monitor failure patterns
- **Resource Usage**: CPU, memory, network I/O

### Logging Strategy
- **Structured Logging**: JSON format for all logs
- **Trace Context**: Distributed tracing support
- **Log Levels**: Debug, Info, Warning, Error, Critical
- **Log Rotation**: Automatic log management

## 🚀 Scalability Considerations

### Horizontal Scaling
- **Load Balancing**: Multiple MCP server instances
- **Session Affinity**: Sticky sessions for stateful operations
- **Database Sharding**: For large-scale deployments

### Vertical Scaling
- **Memory Management**: Erlang VM tuning
- **Connection Pooling**: Database connection optimization
- **Caching Layers**: Redis for session and data caching

## 🔧 Deployment Patterns

### Production Deployment
```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Load Balancer                                   │
└─────────────────────────────────────────────────────────────────────────┘
                                │
          ┌─────────────────────┼─────────────────────┐
          │                     │                     │
    ┌─────▼────┐         ┌─────▼────┐         ┌─────▼────┐
    │ MCP      │         │ MCP      │         │ MCP      │
    │ Server 1 │         │ Server 2 │         │ Server 3 │
    └─────────┘         └─────────┘         └─────────┘
          │                     │                     │
          └─────────────────────┼─────────────────────┘
                                │
                                ▼
    ┌─────────────────────────────────────────────────────────────────────┐
    │                       Shared Services                                │
    │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
    │  │   Redis     │  │   Database  │  │   File      │  │   Metrics   │ │
    │  │   Cluster   │  │   Cluster   │  │   Storage   │  │   Storage   │ │
    │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘ │
    └─────────────────────────────────────────────────────────────────────┘
```

### Development Deployment
- **Single Node**: All components on one machine
- **Docker Compose**: Containerized development environment
- **Hot Reload**: Live code reloading for development

This architecture provides a solid foundation for building enterprise-grade AI agent systems that can integrate with existing ERP systems while supporting advanced multi-agent collaboration scenarios.