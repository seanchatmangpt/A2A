# Craftplan + elrmcp Integration Architecture

## Executive Summary

This document presents a comprehensive architecture for integrating Craftplan MCP (Model Context Protocol) with elrmcp (Local ERP MCP) through a sophisticated multi-layer MCP protocol mapping system. The design enables seamless bidirectional communication between A2A agents, Craftplan ERP, and local ERP systems via standardized MCP protocols.

## 1. Overall Integration Architecture

### 1.1 System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                            Client Layer                                               │
│         ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    │
│         │   Web Client    │    │   Mobile App    │    │   Desktop App  │    │   CLI Tool     │    │
│         └─────────┬────────┘    └─────────┬────────┘    └─────────┬────────┘    └─────────┬────────┘    │
│                  │                        │                        │                        │        │
│                  └────────────────────────┼────────────────────────┼────────────────────────┘        │
│                                             │                        │                         │
└────────────────────────────────────────────┼────────────────────────┼─────────────────────────────┘
                                              │                        │
┌─────────────────────────────────────────────▼────────────────────────▼─────────────────────────────────┐
│                                           Gateway Layer                                              │
│         ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐ │
│         │                    elrmcp Gateway (Port 8888)                                             │ │
│         │  • Protocol Router                                                                      │ │
│         │  • Load Balancer                                                                        │ │
│         │  • Authentication                                                                       │ │
│         │  • Rate Limiting                                                                        │ │
│         └─────────────────────────────────────────────────────────────────────────────────────────────────┘ │
│                                             │                                                         │
│        ┌───────────────────────────────────▼─────────────────────────────────┐  ┌─────────────────────▼─────────────────────────────────┐ │
│        │              MCP Protocol Translation Engine                        │  │           Configuration & Management                      │ │
│        │  • elrmcp → Craftplan MCP Mapping                                  │  │  • Service Discovery                                       │ │
│        │  • Craftplan MCP → elrmcp Mapping                                  │  │  • Dynamic Routing                                         │ │
│        │  • Protocol Versioning                                            │  │  • Health Monitoring                                        │ │
│        │  • Error Handling & Recovery                                      │  │  • Load Balancing Policies                                 │ │
│        └─────────────────────────────────────────────────────────────────────┘  └─────────────────────────────────────────────────────┘ │
│                                                                                                                     │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                                              │
┌────────────────────────────────────────────▼─────────────────────────────────────────────────────────────────┐
│                                           Service Layer                                                │
│         ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    │
│         │ Craftplan MCP   │    │   elrmcp        │    │   A2A Agent     │    │   Local ERP     │    │
│         │ Server          │    │   Server        │    │   Service       │    │   Integration   │    │
│         │ (Port 8090)     │    │ (Port 8765)     │    │ (Port 8080)     │    │   (Port 8766)    │    │
│         │                 │    │                 │    │                 │    │                 │    │
│         │ • Tools:        │    │ • Tools:        │    │ • Agent Skills: │    │ • MCP Adapter:  │    │
│         │   - Customer    │    │   - Inventory   │    │   - Order       │    │   - Local ERP   │    │
│         │   - Order       │    │   - Accounting  │    │   - Customer    │    │   Integration   │    │
│         │   - Inventory    │    │   - HR          │    │   - Inventory   │    │                 │    │
│         │   - Production   │    │   - Payroll     │    │   - Production  │    │                 │
│         │   - Analytics   │    │   - Reporting   │    │   - Analytics   │    │                 │
│         │   - Shipping    │    │   - Procurement │    │   - Shipping    │    │                 │
│         └─────────┬────────┘    └─────────┬────────┘    └─────────┬────────┘    └─────────┬────────┘    │
│                  │                        │                        │                        │        │
│                  └────────────────────────┼────────────────────────┼────────────────────────┘        │
│                                             │                        │                         │
└────────────────────────────────────────────┼────────────────────────┼─────────────────────────────┘
                                              │                        │
┌─────────────────────────────────────────────▼────────────────────────▼─────────────────────────────────┐
│                                           Infrastructure Layer                                         │
│         ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐ │
│         │                  Service Mesh (Istio/Linkerd)                                             │ │
│         │  • Traffic Management                                                                    │ │
│         │  • Service Discovery                                                                      │ │
│         │  • Security (mTLS, RBAC)                                                                 │ │
│         │  • Observability (Metrics, Tracing, Logging)                                              │ │
│         └─────────────────────────────────────────────────────────────────────────────────────────────────┘ │
│                                             │                                                         │
│        ┌───────────────────────────────────▼─────────────────────────────────┐  ┌─────────────────────▼─────────────────────────────────┐ │
│        │                      Data Layer                                    │  │              External Integrations                         │ │
│        │  • PostgreSQL (Primary DB)                                        │  │  • Email Service (SMTP)                                     │ │
│        │  • Redis (Cache, Session)                                         │  │  • SMS Service (Twilio)                                    │ │
│        │  • MinIO (File Storage)                                           │  │  • Payment Gateway (Stripe/PayPal)                          │ │
│        │  • Message Queue (RabbitMQ)                                        │  │  • External APIs (3rd Party Services)                       │ │
│        └─────────────────────────────────────────────────────────────────────┘  └─────────────────────────────────────────────────────┘ │
│                                                                                                                     │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Multi-Layer MCP Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                      Client Applications                                     │
└─────────────────────────────┬─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼─────────────────────────────────────────────────────────────┐
│                              elrmcp Gateway (8888)                                        │
│  • Unified Entry Point                                                                     │
│  • Protocol Translation                                                                   │
│  • Load Balancing & Routing                                                               │
│  • Authentication & Authorization                                                        │
│  • Rate Limiting & Throttling                                                              │
│  • Monitoring & Observability                                                              │
└─────────────────────────────┬─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼─────────────────────────────────────────────────────────────┐
│                       MCP Protocol Mapping Layer                                           │
│  elrmcp → Craftplan Mapping                                                             │
│  └─────────────────────────────────────────────────────────────────────────────────────┐   │
│  │  • Tool Translation: local_erp_customer → customer_management                      │   │
│  │  • Resource Translation: local_erp_order → order_management                         │   │
│  │  • Protocol Adaptation: JSON-RPC → MCP JSON-RPC                                    │   │
│  │  • Error Translation: HTTP Errors → MCP Errors                                     │   │
│  └─────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                             │
│  Craftplan MCP → elrmcp Mapping                                                         │
│  └─────────────────────────────────────────────────────────────────────────────────────┐   │
│  │  • Tool Translation: customer_management → local_erp_customer                      │   │
│  │  • Resource Translation: order_management → local_erp_order                       │   │
│  │  • Protocol Adaptation: MCP JSON-RPC → JSON-RPC                                  │   │
│  │  • Error Translation: MCP Errors → HTTP Errors                                    │   │
│  └─────────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────┬─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼─────────────────────────────────────────────────────────────┐
│                         Backend Services                                                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │ Craftplan MCP   │  │   elrmcp        │  │   A2A Agent     │  │   Local ERP     │     │
│  │ Server (8090)   │  │   Server       │  │   Service       │  │   Integration   │     │
│  │                 │  │   (8765)       │  │   (8080)        │  │   (8766)       │     │
│  │ • MCP Tools:    │  │ • MCP Tools:   │  │ • Agent Skills: │  │ • MCP Adapter:  │     │
│  │   - Customer    │  │   - Inventory  │  │   - Order       │  │   - Local ERP   │     │
│  │   - Order      │  │   - Accounting │  │   - Customer    │  │   Integration   │     │
│  │   - Inventory   │  │   - HR         │  │   - Inventory   │  │                 │     │
│  │   - Production  │  │   - Payroll    │  │   - Production  │  │                 │     │
│  │   - Analytics   │  │   - Reporting  │  │   - Analytics   │  │                 │     │
│  │   - Shipping    │  │   - Procurement│  │   - Shipping    │  │                 │     │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘     │
└─────────────────────────────┬─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼─────────────────────────────────────────────────────────────┐
│                       Shared Infrastructure                                                │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │ PostgreSQL      │  │   Redis        │  │   MinIO         │  │   RabbitMQ     │     │
│  │ (Primary DB)   │  │   (Cache)      │  │   (Storage)     │  │   (Messages)   │     │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘     │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

## 2. MCP Protocol Mapping Design

### 2.1 Protocol Translation Overview

The MCP protocol mapping layer serves as the central nervous system of the integration, translating between different MCP dialects and protocols:

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                               MCP Protocol Mapping Engine                                    │
└─────────────────────────────┬─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼─────────────────────────────────────────────────────────────┐
│                             Protocol Router                                                │
│  • Determines which mapping to apply based on:                                            │
│    - Source/destination systems                                                           │
│    - Protocol versions                                                                    │
│    - Tool compatibility                                                                  │
│    - User permissions                                                                     │
└─────────────────────────────┬─────────────────────────────────────────────────────────────┘
                              │
         ┌─────────────────────┼─────────────────────┼─────────────────────┼─────────────────────┐
         │                     │                     │                     │                     │
┌────────▼─────────┐  ┌────────▼─────────┐  ┌────────▼─────────┐  ┌────────▼─────────┐
│ elrmcp → Craftplan│  │ Craftplan → elrmcp│  │ A2A → MCP Tools  │  │ MCP → A2A Skills │
│  Mapping        │  │  Mapping        │  │  Translation     │  │  Translation     │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                     │                     │                     │
         └─────────────────────┼─────────────────────┼─────────────────────┘
                              │                     │
                    ┌─────────▼─────────┐  ┌─────────▼─────────┐
                    │   Protocol Store  │  │   Translation     │
                    │   (Versioned)     │  │   Cache           │
                    └───────────────────┘  └───────────────────┘
```

### 2.2 Tool Mapping Schema

```erlang
-record(mcp_tool_mapping, {
    id :: binary(),
    source_system :: craftplan | elrmcp | a2a,
    target_system :: craftplan | elrmcp | a2a,
    source_tool :: binary(),
    target_tool :: binary(),
    mapping_type :: direct | composite | transformation,
    transformation_rules :: map(),
    version :: binary(),
    created_at :: binary(),
    updated_at :: binary()
}).

%% Example mappings
-define(MAPPINGS, [
    #mcp_tool_mapping{
        id = "customer_001",
        source_system = elrmcp,
        target_system = craftplan,
        source_tool = "local_erp_customer",
        target_tool = "customer_management",
        mapping_type = "direct",
        transformation_rules = #{
            "customer_id" => "id",
            "customer_name" => "name",
            "contact_email" => "email",
            "contact_phone" => "phone",
            "address" => "address"
        },
        version = "1.0.0"
    },
    #mcp_tool_mapping{
        id = "order_002",
        source_system = craftplan,
        target_system = elrmcp,
        source_tool = "order_management",
        target_tool = "local_erp_order",
        mapping_type = "transformation",
        transformation_rules = #{
            "order_data" => "order",
            "customer_id" => "customer_id",
            "items" => "order_items",
            "total_amount" => "amount"
        },
        version = "1.0.0"
    }
]).
```

### 2.3 Bidirectional Communication Flow

```mermaid
sequenceDiagram
    participant Client as Client Application
    participant Gateway as elrmcp Gateway (8888)
    participant Mapper as MCP Protocol Mapper
    participant Craftplan as Craftplan MCP (8090)
    participant elrmcpS as elrmcp Server (8765)
    participant A2A as A2A Agent (8080)

    Client->>Gateway: Request with elrmcp tool
    Gateway->>Mapper: elrmcp → Craftplan mapping
    Mapper->>Craftplan: Translated MCP tool call
    Craftplan->>Mapper: MCP response
    Mapper->>Gateway: elrmcp-formatted response
    Gateway->>Client: elrmcp response

    Client->>Gateway: Request with Craftplan tool
    Gateway->>Mapper: Craftplan → elrmcp mapping
    Mapper->>elrmcpS: Translated MCP tool call
    elrmcpS->>Mapper: MCP response
    Mapper->>Gateway: Craftplan-formatted response
    Gateway->>Client: Craftplan response

    Client->>Gateway: A2A task submission
    Gateway->>A2A: Direct A2A protocol
    A2A->>Craftplan: MCP tool call (via mapping)
    Craftplan->>A2A: MCP response
    A2A->>Client: A2A task result

    Client->>Gateway: MCP tool request for A2A
    Gateway->>Mapper: MCP → A2A skill mapping
    Mapper->>A2A: A2A task submission
    A2A->>Mapper: A2A response
    Mapper->>Gateway: MCP-formatted response
    Gateway->>Client: MCP tool response
```

## 3. Component Interactions

### 3.1 elrmcp ↔ Craftplan MCP Server

```mermaid
sequenceDiagram
    participant Client as Client Application
    participant Gateway as elrmcp Gateway
    participant Mapper as MCP Mapper
    participant elrmcpS as elrmcp Server
    participant Craftplan as Craftplan MCP Server
    participant CraftplanAPI as Craftplan Backend

    %% elrmcp → Craftplan flow
    Client->>Gateway: {"jsonrpc":"2.0","method":"tools/call","params":{"name":"local_erp_customer","arguments":{"operation":"list","limit":50}},"id":1}
    Gateway->>Mapper: Request elrmcp→Craftplan mapping
    Mapper->>Gateway: Map to "customer_management"
    Gateway->>Craftplan: {"jsonrpc":"2.0","method":"tools/call","params":{"name":"customer_management","arguments":{"operation":"list","limit":50}},"id":1}
    Craftplan->>CraftplanAPI: Call customer_management API
    CraftplanAPI->>Craftplan: Return customer data
    Craftplan->>Gateway: {"jsonrpc":"2.0","result":{"customers":[...]},"id":1}
    Gateway->>Client: {"jsonrpc":"2.0","result":{"customers":[...]},"id":1}

    %% Craftplan → elrmcp flow
    Client->>Gateway: {"jsonrpc":"2.0","method":"tools/call","params":{"name":"order_management","arguments":{"operation":"create","order_data":{...}}},"id":2}
    Gateway->>Mapper: Request Craftplan→elrmcp mapping
    Mapper->>Gateway: Map to "local_erp_order"
    Gateway->>elrmcpS: {"jsonrpc":"2.0","method":"tools/call","params":{"name":"local_erp_order","arguments":{"operation":"create","order":{...}}},"id":2}
    elrmcpS->>elrmcpS: Process local ERP order
    elrmcpS->>Gateway: {"jsonrpc":"2.0","result":{"order_id":"12345"},"id":2}
    Gateway->>Client: {"jsonrpc":"2.0","result":{"order_id":"12345"},"id":2}
```

### 3.2 Craftplan MCP ↔ A2A Agent

```mermaid
sequenceDiagram
    participant User as User/Assistant
    participant A2A as A2A Agent
    participant Mapper as MCP Mapper
    participant Craftplan as Craftplan MCP Server
    participant CraftplanAPI as Craftplan Backend

    %% A2A task → MCP tool
    User->>A2A: Submit task: "Process order for customer X"
    A2A->>A2A: Parse task requirements
    A2A->>Mapper: Request A2A→MCP mapping
    Mapper->>A2A: Map to "order_management" tool
    A2A->>Craftplan: {"jsonrpc":"2.0","method":"tools/call","params":{"name":"order_management","arguments":{"operation":"create","order_data":{...}}},"id":1}
    Craftplan->>CraftplanAPI: Create order
    CraftplanAPI->>Craftplan: Order created successfully
    Craftplan->>A2A: {"jsonrpc":"2.0","result":{"order_id":"12345"},"id":1}
    A2A->>A2A: Store task result
    A2A->>User: Task completed: Order created (ID: 12345)

    %% MCP tool → A2A skill
    User->>Craftplan: Call "inventory_management" tool
    Craftplan->>Mapper: Request MCP→A2A mapping
    Mapper->>Craftplan: Map to "inventory_management" skill
    Craftplan->>A2A: {"jsonrpc":"2.0","method":"task.submit","params":{"task_type":"inventory_management","params":{"operation":"check_stock","product_id":"ABC"}},"id":2}
    A2A->>A2A: Process inventory task
    A2A->>Craftplan: {"jsonrpc":"2.0","result":{"stock_level":45},"id":2}
    Craftplan->>User: Return inventory data
```

### 3.3 A2A Agent ↔ elrmcp (Multi-Agent Workflows)

```mermaid
sequenceDiagram
    participant ShopManager as Shop Manager Agent
    participant Craftplan as Craftplan A2A Agent
    participant Gateway as elrmcp Gateway
    Mapper as MCP Mapper
    participant elrmcpS as elrmcp Server
    participant SupplierAgent as Supplier Agent

    %% Multi-agent workflow
    ShopManager->>Craftplan: "Check stock for product ABC"
    Craftplan->>Craftplan: Map to inventory_management
    Craftplan->>elrmcpS: MCP tool call via gateway
    elrmcpS->>elrmcpS: Check local inventory
    elrmcpS->>Craftplan: Low stock alert
    Craftplan->>Craftplan: "Reorder from supplier"
    Craftplan->>SupplierAgent: A2A task delegation
    SupplierAgent->>SupplierAgent: Process reorder
    SupplierAgent->>Craftplan: Supplier confirmation
    Craftplan->>ShopManager: Stock replenishment in progress

    %% Real-time updates via SSE
    Craftplan->>ShopManager: Event: stock_update
    Craftplan->>SupplierAgent: Event: order_created
    SupplierAgent->>Craftplan: Event: order_shipped
    Craftplan->>ShopManager: Event: order_received
```

### 3.4 Client → elrmcp → Craftplan Data Flow

```mermaid
flowchart TD
    A[Client Application] --> B[elrmcp Gateway<br/>8888]
    B --> C{Protocol Router}

    C --> D[elrmcp → Craftplan Mapping]
    C --> E[Craftplan → elrmcp Mapping]
    C --> F[A2A → MCP Tools Mapping]
    C --> G[MCP → A2A Skills Mapping]

    D --> H[Craftplan MCP Server<br/>8090]
    E --> I[elrmcp Server<br/>8765]
    F --> J[A2A Agent Service<br/>8080]
    G --> J

    H --> K[Craftplan Backend<br/>4000]
    I --> L[Local ERP System<br/>8766]
    J --> K
    J --> L

    K --> H
    L --> I
    H --> D
    I --> E
    J --> F
    J --> G

    D --> B
    E --> B
    F --> B
    G --> B

    B --> A
```

## 4. Architecture Diagrams

### 4.1 System Architecture Overview

```mermaid
graph TB
    subgraph "Client Layer"
        WC[Web Client]
        MC[Mobile Client]
        DC[Desktop Client]
        CLI[CLI Tool]
    end

    subgraph "Gateway Layer"
        GW[elrmcp Gateway<br/>8888]
        PR[Protocol Router]
        MT[Translation Engine]
    end

    subgraph "Service Layer"
        CP[Craftplan MCP<br/>8090]
        ER[elrmcp Server<br/>8765]
        A2[A2A Agent<br/>8080]
        LE[Local ERP<br/>8766]
    end

    subgraph "Infrastructure Layer"
        PG[(PostgreSQL)]
        RD[(Redis)]
        MO[(MinIO)]
        RM[(RabbitMQ)]
    end

    WC --> GW
    MC --> GW
    DC --> GW
    CLI --> GW

    GW --> PR
    PR --> MT
    MT --> CP
    MT --> ER
    MT --> A2
    MT --> LE

    CP --> PG
    ER --> PG
    A2 --> PG
    LE --> PG

    CP --> RD
    ER --> RD
    A2 --> RD
    LE --> RD

    CP --> MO
    ER --> MO
    A2 --> MO
    LE --> MO

    CP --> RM
    ER --> RM
    A2 --> RM
    LE --> RM
```

### 4.2 Data Flow Diagram

```mermaid
graph LR
    subgraph "External Systems"
        APP[Applications]
        AI[AI Assistants]
    end

    subgraph "elrmcp Gateway"
        GW[Gateway<br/>8888]
        AUTH[Auth Service]
        ROUTER[Router]
        TRANS[Translation]
    end

    subgraph "Backend Services"
        MCP[Craftplan MCP<br/>8090]
        ERP[elrmcp Server<br/>8765]
        A2A[A2A Agent<br/>8080]
        LOCAL[Local ERP<br/>8766]
    end

    subgraph "Data Layer"
        DB[(PostgreSQL)]
        CACHE[(Redis)]
        MQ[(Message Queue)]
    end

    APP --> GW
    AI --> GW

    GW --> AUTH
    AUTH --> ROUTER
    ROUTER --> TRANS

    TRANS --> MCP
    TRANS --> ERP
    TRANS --> A2A
    TRANS --> LOCAL

    MCP --> DB
    ERP --> DB
    A2A --> DB
    LOCAL --> DB

    MCP --> CACHE
    ERP --> CACHE
    A2A --> CACHE
    LOCAL --> CACHE

    MCP --> MQ
    ERP --> MQ
    A2A --> MQ
    LOCAL --> MQ
```

### 4.3 Component Interaction Diagram

```mermaid
sequenceDiagram
    participant Client as Client Application
    participant Gateway as elrmcp Gateway
    participant Auth as Auth Service
    participant Router as Protocol Router
    participant Mapper as Translation Engine
    participant Craftplan as Craftplan MCP
    participant elrmcp as elrmcp Server
    participant A2A as A2A Agent
    participant Local as Local ERP

    Client->>Gateway: Request with auth token
    Gateway->>Auth: Validate token
    Auth->>Gateway: Authenticated
    Gateway->>Router: Route request
    Router->>Mapper: Translation needed
    Mapper->>Craftplan: Translated request
    Craftplan->>Local: Local ERP integration
    Local->>Craftplan: Response
    Craftplan->>Mapper: Translated response
    Mapper->>Router: Processed response
    Router->>Gateway: Return response
    Gateway->>Client: Final response
```

## 5. Extensibility Design

### 5.1 Plugin Architecture

```ermaid
graph TB
    subgraph "Core System"
        GW[Gateway Core]
        MAP[Mapping Engine]
        REG[Registry]
    end

    subgraph "Plugin System"
        P1[Plugin 1<br/>elrmcp Connector]
        P2[Plugin 2<br/>Craftplan Connector]
        P3[Plugin 3<br/>A2A Connector]
        P4[Plugin 4<br/>Custom Tools]
    end

    subgraph "External Systems"
        S1[SAP Integration]
        S2[Salesforce Integration]
        S3[Custom ERP]
    end

    GW --> REG
    MAP --> REG
    REG --> P1
    REG --> P2
    REG --> P3
    REG --> P4

    P1 --> S1
    P2 --> S2
    P3 --> S3
```

### 5.2 Configurable Routing System

```ermaid
graph TD
    subgraph "Routing Configuration"
        RC[Routing Config]
        RL[Rule Engine]
        LD[Load Balancer]
    end

    subgraph "Route Types"
        RT1[Static Routes]
        RT2[Dynamic Routes]
        RT3[Weighted Routes]
        RT4[Fallback Routes]
    end

    subgraph "Services"
        S1[Craftplan MCP]
        S2[elrmcp Server]
        S3[A2A Agent]
        S4[Local ERP]
    end

    RC --> RL
    RL --> LD

    LD --> RT1
    LD --> RT2
    LD --> RT3
    LD --> RT4

    RT1 --> S1
    RT2 --> S2
    RT3 --> S3
    RT4 --> S4
```

### 5.3 Dynamic Tool Registration

```ermaid
graph TB
    subgraph "Tool Registry"
        TR[Tool Registry]
        DISC[Discovery Service]
        REG[Registration Service]
    end

    subgraph "Tools"
        T1[Customer Management]
        T2[Order Management]
        T3[Inventory Management]
        T4[Analytics]
        T5[Custom Tools]
    end

    subgraph "Systems"
        CP[Craftplan]
        ERP[elrmcp]
        A2A[A2A]
        EXT[External]
    end

    TR --> DISC
    TR --> REG

    DISC --> CP
    DISC --> ERP
    DISC --> A2A
    DISC --> EXT

    REG --> T1
    REG --> T2
    REG --> T3
    REG --> T4
    REG --> T5

    T1 --> CP
    T2 --> ERP
    T3 --> A2A
    T4 --> EXT
    T5 --> EXT
```

### 5.4 Load Balancing and Scaling

```mermaid
graph TB
    subgraph "Load Balancer"
        LB[Load Balancer<br/>8888]
        MON[Monitoring]
        SCALE[Auto-scaling]
    end

    subgraph "Service Pool"
        S1[Craftplan MCP 1]
        S2[Craftplan MCP 2]
        S3[Craftplan MCP 3]
        S4[elrmcp Server 1]
        S5[elrmcp Server 2]
        S6[A2A Agent 1]
        S7[A2A Agent 2]
        S8[Local ERP 1]
    end

    LB --> MON
    MON --> SCALE

    LB --> S1
    LB --> S2
    LB --> S3
    LB --> S4
    LB --> S5
    LB --> S6
    LB --> S7
    LB --> S8

    SCALE --> S1
    SCALE --> S2
    SCALE --> S3
    SCALE --> S4
    SCALE --> S5
    SCALE --> S6
    SCALE --> S7
    SCALE --> S8
```

## 6. Implementation Guidelines

### 6.1 Core Components Implementation

#### 6.1.1 elrmcp Gateway (Erlang/OTP)

```erlang
%% Gateway application entry point
-module(elrmcp_gateway).
-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) ->
    %% Start core services
    ok = ensure_started(mnesia),
    ok = ensure_started(cowboy),
    ok = ensure_started(elrmcp_auth),
    ok = ensure_started(elrmcp_router),
    ok = ensure_started(elrmcp_translation),

    %% Start HTTP server
    Port = application:get_env(elrmcp_gateway, port, 8888),
    {ok, _} = cowboy:start_clear(http, [{port, Port}], #{
        env => #{dispatch => init_routes()}
    }),

    elrmcp_gateway_sup:start_link().

stop(_State) ->
    ok.

%% Route initialization
init_routes() ->
    cowboy_router:compile([
        {'_', [
            {"/mcp", mcp_handler, []},
            {"/health", health_handler, []},
            {"/metrics", metrics_handler, []},
            {"/.well-known/agent-card", agent_card_handler, []}
        ]}
    ]).
```

#### 6.1.2 MCP Translation Engine

```erlang
%% Protocol translation engine
-module(elrmcp_translation).
-export([translate/3, get_mapping/2]).

%% Main translation function
translate(SourceSystem, TargetSystem, Request) ->
    case get_mapping(SourceSystem, TargetSystem, Request) of
        {ok, Mapping} ->
            translate_request(Request, Mapping);
        {error, not_found} ->
            {error, mapping_not_found}
    end.

%% Get mapping configuration
get_mapping(SourceSystem, TargetSystem, Request) ->
    Tool = extract_tool_name(Request),
    case mcp_registry:get_mapping(SourceSystem, TargetSystem, Tool) of
        {ok, Mapping} ->
            {ok, Mapping};
        {error, not_found} ->
            create_dynamic_mapping(SourceSystem, TargetSystem, Tool)
    end.
```

### 6.2 Configuration Management

#### 6.2.1 Environment Configuration

```yaml
# config/elrmcp_gateway.yaml
gateway:
  port: 8888
  host: "0.0.0.0"
  ssl: false

authentication:
  enabled: true
  type: "jwt"
  secret: "${JWT_SECRET}"
  token_ttl: 3600

routing:
  default_target: "craftplan"
  timeout: 30000
  retries: 3

translation:
  cache_ttl: 300
  auto_discovery: true

monitoring:
  enabled: true
  metrics_port: 8889
  logging_level: "info"

services:
  craftplan:
    host: "craftplan-mcp"
    port: 8090
    timeout: 10000

  elrmcp:
    host: "elrmcp-server"
    port: 8765
    timeout: 10000

  a2a:
    host: "a2a-agent"
    port: 8080
    timeout: 10000

  local_erp:
    host: "local-erp"
    port: 8766
    timeout: 10000
```

#### 6.2.2 Dynamic Configuration

```erlang
%% Dynamic configuration management
-module(elrmcp_config).
-export([get_value/2, update_value/3, load_config/1]).

%% Get configuration value
get_value(Key, Default) ->
    case application:get_env(elrmcp_gateway, Key) of
        undefined -> Default;
        {ok, Value} -> Value
    end.

%% Update configuration value
update_value(Key, Value, Persist) ->
    application:set_env(elrmcp_gateway, Key, Value),
    case Persist of
        true ->
            save_config(Key, Value);
        false ->
            ok
    end.

%% Load configuration from file
load_config(ConfigFile) ->
    case file:read_file(ConfigFile) of
        {ok, Content} ->
            Config = yaml:decode(Content),
            lists:foreach(fun({K, V}) ->
                application:set_env(elrmcp_gateway, K, V)
            end, Config),
            ok;
        {error, _} ->
            error
    end.
```

### 6.3 Error Handling and Recovery

#### 6.3.1 Error Handling Strategy

```erlang
%% Comprehensive error handling
-module(elrmcp_error).
-export([handle_error/2, recover/1]).

%% Main error handler
handle_error({error, Reason}, Context) ->
    %% Log error with context
    error_logger:error_msg("Error in context ~p: ~p~n", [Context, Reason]),

    %% Apply recovery strategy
    case recover(Reason) of
        {ok, Recovery} ->
            Recovery;
        {error, permanent} ->
            {error, Reason}
    end.

%% Recovery strategies
recover({timeout, _}) ->
    %% Retry with exponential backoff
    {ok, retry};

recover({connection_failed, _}) ->
    %% Reconnect to service
    {ok, reconnect};

recover({invalid_mapping, _}) ->
    %% Create new mapping
    {ok, remap};

recover({unknown_system, _}) ->
    %% Use fallback system
    {ok, fallback}.
```

### 6.4 Testing Strategy

#### 6.4.1 Unit Testing

```erlang
%% Unit tests for translation engine
-module(elrmcp_translation_tests).
-include_lib("eunit/include/eunit.hrl").

translation_test() ->
    Request = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"tools/call">>,
        <<"params">> => #{
            <<"name">> => <<"local_erp_customer">>,
            <<"arguments">> => #{
                <<"operation">> => <<"list">>,
                <<"limit">> => 50
            }
        }
    },

    {ok, Result} = elrmcp_translation:translate(elrmcp, craftplan, Request),
    ?assertEqual(<<"customer_management">>,
                maps:get(<<"name">>, maps:get(<<"params">>, Result))).
```

#### 6.4.2 Integration Testing

```erlang
%% Integration test for full workflow
-module(elrmcp_integration_tests).
-include_lib("eunit/include/eunit.hrl").

full_workflow_test() ->
    %% Start test services
    {ok, _} = start_test_services(),

    %% Create test client
    Client = create_test_client(),

    %% Execute test workflow
    Result = execute_test_workflow(Client),

    %% Verify results
    ?assertEqual(<<"success">>, maps:get(<<"status">>, Result)),

    %% Cleanup
    cleanup_test_services().
```

### 6.5 Deployment Strategy

#### 6.5.1 Docker Compose Deployment

```yaml
# docker-compose.yml
version: '3.8'

services:
  elrmcp-gateway:
    image: craftplan/elrmcp-gateway:latest
    ports:
      - "8888:8888"
      - "8889:8889"
    environment:
      - ENVIRONMENT=production
      - LOG_LEVEL=info
      - JWT_SECRET=${JWT_SECRET}
    depends_on:
      - craftplan-mcp
      - elrmcp-server
      - a2a-agent
    networks:
      - craftplan-network

  craftplan-mcp:
    image: craftplan/mcp-server:latest
    ports:
      - "8090:8090"
    environment:
      - CRAFTPLAN_API_URL=http://craftplan:4000/api
      - CRAFTPLAN_API_TOKEN=${CRAFTPLAN_TOKEN}
    networks:
      - craftplan-network

  elrmcp-server:
    image: craftplan/elrmcp-server:latest
    ports:
      - "8765:8765"
    environment:
      - LOCAL_ERP_URL=http://local-erp:8766
      - LOCAL_ERP_TOKEN=${ERP_TOKEN}
    networks:
      - craftplan-network

  a2a-agent:
    image: craftplan/a2a-agent:latest
    ports:
      - "8080:8080"
    environment:
      - AGENT_ID=craftplan-connector
      - MCP_SERVER_URL=http://elrmcp-gateway:8888/mcp
    networks:
      - craftplan-network

networks:
  craftplan-network:
    driver: bridge
```

#### 6.5.2 Kubernetes Deployment

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elrmcp-gateway
spec:
  replicas: 3
  selector:
    matchLabels:
      app: elrmcp-gateway
  template:
    metadata:
      labels:
        app: elrmcp-gateway
    spec:
      containers:
      - name: elrmcp-gateway
        image: craftplan/elrmcp-gateway:latest
        ports:
        - containerPort: 8888
        - containerPort: 8889
        env:
        - name: ENVIRONMENT
          value: "production"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: elrmcp-gateway-service
spec:
  selector:
    app: elrmcp-gateway
  ports:
  - port: 8888
    targetPort: 8888
  - port: 8889
    targetPort: 8889
  type: LoadBalancer
```

## 7. Monitoring and Observability

### 7.1 Metrics Collection

```mermaid
graph TB
    subgraph "Metrics Collection"
        MC[Metrics Collector]
        PROM[Prometheus]
        GRAF[Grafana]
    end

    subgraph "Services"
        GW[Gateway]
        MCP[Craftplan MCP]
        ERP[elrmcp Server]
        A2A[A2A Agent]
    end

    GW --> MC
    MCP --> MC
    ERP --> MC
    A2A --> MC

    MC --> PROM
    PROM --> GRAF
```

### 7.2 Logging Strategy

```ermaid
graph TB
    subgraph "Logging System"
        APP[Application Logs]
        LOG[Log Aggregator]
        ES[Elasticsearch]
        KIB[Kibana]
    end

    subgraph "Services"
        GW[Gateway]
        MCP[Craftplan MCP]
        ERP[elrmcp Server]
        A2A[A2A Agent]
    end

    GW --> APP
    MCP --> APP
    ERP --> APP
    A2A --> APP

    APP --> LOG
    LOG --> ES
    ES --> KIB
```

### 7.3 Distributed Tracing

```mermaid
graph TB
    subgraph "Tracing System"
        TRACER[Tracer]
        JAE[Jaeger]
        UI[UI]
    end

    subgraph "Requests"
        REQ1[Request 1]
        REQ2[Request 2]
        REQ3[Request 3]
    end

    subgraph "Services"
        GW[Gateway]
        MCP[Craftplan MCP]
        ERP[elrmcp Server]
        A2A[A2A Agent]
    end

    REQ1 --> TRACER
    REQ2 --> TRACER
    REQ3 --> TRACER

    TRACER --> GW
    TRACER --> MCP
    TRACER --> ERP
    TRACER --> A2A

    TRACER --> JAE
    JAE --> UI
```

## 8. Security Considerations

### 8.1 Authentication and Authorization

```mermaid
graph TB
    subgraph "Authentication Flow"
        USER[User]
        AUTH[Auth Service]
        GW[Gateway]
        SVC[Service]
    end

    USER --> AUTH
    AUTH --> GW
    GW --> SVC

    subgraph "Authorization Types"
        JWT[JWT Tokens]
        OAUTH[OAuth2]
        API[API Keys]
        RBAC[RBAC]
    end

    AUTH --> JWT
    AUTH --> OAUTH
    AUTH --> API
    AUTH --> RBAC
```

### 8.2 Data Security

```mermaid
graph TB
    subgraph "Data Security"
        DATA[Data]
        ENC[Encryption]
        MASK[Data Masking]
        LOG[Access Logs]
    end

    DATA --> ENC
    DATA --> MASK
    DATA --> LOG

    subgraph "Protection Levels"
        AT[At Rest]
        IN[In Transit]
        USE[In Use]
    end

    ENC --> AT
    ENC --> IN
    ENC --> USE
```

## 9. Performance Optimization

### 9.1 Caching Strategy

```mermaid
graph TB
    subgraph "Caching Layer"
        CACHE[Redis Cache]
        L1[L1 Cache]
        L2[L2 Cache]
    end

    subgraph "Services"
        GW[Gateway]
        MCP[Craftplan MCP]
        ERP[elrmcp Server]
    end

    GW --> CACHE
    MCP --> CACHE
    ERP --> CACHE

    CACHE --> L1
    L1 --> L2
```

### 9.2 Performance Metrics

```mermaid
graph TB
    subgraph "Performance Metrics"
        LAT[Latency]
        THR[Throughput]
        ERR[Error Rate]
        AVAIL[Availability]
    end

    subgraph "Targets"
        T1[< 100ms]
        T2[> 1000 req/s]
        T3[< 0.1%]
        T4[> 99.9%]
    end

    LAT --> T1
    THR --> T2
    ERR --> T3
    AVAIL --> T4
```

## 10. Conclusion

This comprehensive architecture design provides a robust, scalable, and extensible foundation for integrating Craftplan MCP with elrmcp. The multi-layer MCP protocol mapping system enables seamless bidirectional communication while maintaining protocol compatibility and extensibility.

### 10.1 Key Benefits

1. **Unified Access**: Single gateway for all ERP systems
2. **Protocol Translation**: Automatic mapping between different MCP implementations
3. **Scalability**: Horizontal scaling with load balancing
4. **Extensibility**: Plugin architecture for new integrations
5. **Observability**: Comprehensive monitoring and logging
6. **Security**: Multi-layer security with authentication and encryption
7. **Performance**: Caching and optimization strategies

### 10.2 Implementation Roadmap

1. **Phase 1**: Core gateway and basic routing (2-3 weeks)
2. **Phase 2**: MCP translation engine and mapping (3-4 weeks)
3. **Phase 3**: Integration with existing services (2-3 weeks)
4. **Phase 4**: Monitoring and observability (1-2 weeks)
5. **Phase 5**: Performance optimization and testing (2-3 weeks)

### 10.3 Success Criteria

- < 100ms average response time
- 99.9% availability
- < 0.1% error rate
- Support for 1000+ concurrent requests
- Zero-downtime deployments
- Comprehensive monitoring coverage

This architecture provides a solid foundation for building a sophisticated integration platform that can evolve with changing business requirements and technology landscapes.