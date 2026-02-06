# A2A Bridge REST API Documentation

## Overview

The A2A Bridge REST API provides comprehensive access to agent management, workflow orchestration, system monitoring, and configuration management. The API follows RESTful principles and uses JSON for request and response bodies.

**Base URL:** `http://localhost:8001`
**API Version:** 1.0.0
**Default Port:** 8001

## Table of Contents

- [Authentication](#authentication)
- [Authorization](#authorization)
- [Rate Limits](#rate-limits)
- [Error Handling](#error-handling)
- [Endpoints](#endpoints)
  - [Health & Status](#health--status)
  - [Agent Management](#agent-management)
  - [Workflow Management](#workflow-management)
  - [Metrics & Monitoring](#metrics--monitoring)
  - [Configuration](#configuration)
  - [System Management](#system-management)
- [Integration Examples](#integration-examples)

---

## Authentication

The A2A Bridge API supports two authentication methods:

### 1. API Key Authentication

Include your API key in the request headers:

```http
X-API-Key: your-api-key-here
```

Alternatively, pass it as a query parameter:

```http
GET /api/endpoint?api_key=your-api-key-here
```

### 2. Bearer Token Authentication

Include a bearer token in the Authorization header:

```http
Authorization: Bearer your-token-here
```

### Authentication Configuration

Authentication can be enabled/disabled via configuration:

```json
{
  "security": {
    "auth_required": true,
    "api_key": "your-secret-key"
  }
}
```

### Getting an API Key

API keys are generated automatically on first startup. To retrieve or regenerate:

1. Check configuration file: `config/bridge.json`
2. Use environment variable: `A2A_BRIDGE_API_KEY`
3. Generate via CLI: `a2a-bridge config generate-key`

---

## Authorization

Role-based access control determines endpoint permissions:

| Role | Permissions |
|------|-------------|
| **admin** | Full access to all endpoints |
| **operator** | Read/write access to agents and workflows |
| **monitor** | Read-only access to metrics and status |
| **guest** | Access to health check only |

Authorization headers:

```http
X-User-Role: admin
X-User-ID: user-123
```

---

## Rate Limits

Rate limiting prevents API abuse and ensures fair resource allocation.

### Default Limits

- **100 requests per minute** per IP address
- **1000 max concurrent connections**
- **10MB max request payload size**

### Rate Limit Headers

Response headers indicate current rate limit status:

```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1623456789
```

### Exceeding Rate Limits

When rate limits are exceeded, the API returns:

```json
{
  "error": {
    "code": 429,
    "message": "Rate limit exceeded",
    "details": {
      "limit": 100,
      "window": "1 minute",
      "retry_after": 30
    }
  }
}
```

### Rate Limit Configuration

Customize rate limits in configuration:

```json
{
  "security": {
    "rate_limit": 100,
    "max_connections": 1000
  }
}
```

---

## Error Handling

### Standard Error Response

```json
{
  "error": {
    "code": 400,
    "message": "Invalid request parameters",
    "details": {
      "field": "agent_id",
      "reason": "Field is required"
    }
  }
}
```

### HTTP Status Codes

| Code | Description |
|------|-------------|
| 200 | OK - Request successful |
| 201 | Created - Resource created successfully |
| 400 | Bad Request - Invalid parameters |
| 401 | Unauthorized - Authentication required |
| 403 | Forbidden - Insufficient permissions |
| 404 | Not Found - Resource not found |
| 429 | Too Many Requests - Rate limit exceeded |
| 500 | Internal Server Error - Server error |
| 503 | Service Unavailable - Server overloaded |

---

## Endpoints

### Health & Status

#### GET /health

Health check endpoint for monitoring.

**Request:**
```http
GET /health HTTP/1.1
Host: localhost:8001
```

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "version": "1.0.0"
}
```

**Status Codes:** 200

---

#### GET /bridge/status

Get comprehensive bridge status and metrics.

**Request:**
```http
GET /bridge/status HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Response:**
```json
{
  "state": "running",
  "uptime": 3600.5,
  "metrics": {
    "total_messages_processed": 1543,
    "total_workflows_completed": 89,
    "total_agents_discovered": 12,
    "active_connections": 8
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 401, 500

---

### Agent Management

#### GET /agents

List all registered agents.

**Request:**
```http
GET /agents HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Query Parameters:**
- `capability` (optional) - Filter by capability
- `status` (optional) - Filter by status (active, inactive, error)
- `limit` (optional) - Max results (default: 50)
- `offset` (optional) - Pagination offset (default: 0)

**Response:**
```json
{
  "agents": [
    {
      "agent_id": "agent-001",
      "name": "Data Processor",
      "version": "2.1.0",
      "status": "active",
      "capabilities": ["data_processing", "analytics"],
      "endpoints": {
        "http": "http://agent-001:8080"
      },
      "last_seen": "2024-01-15T10:29:55Z",
      "metadata": {
        "region": "us-west-2",
        "environment": "production"
      }
    }
  ],
  "total": 12,
  "limit": 50,
  "offset": 0
}
```

**Status Codes:** 200, 401, 500

---

#### GET /agents/{agent_id}

Get details for a specific agent.

**Request:**
```http
GET /agents/agent-001 HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Response:**
```json
{
  "agent_id": "agent-001",
  "name": "Data Processor",
  "version": "2.1.0",
  "status": "active",
  "capabilities": ["data_processing", "analytics"],
  "endpoints": {
    "http": "http://agent-001:8080",
    "websocket": "ws://agent-001:8080/ws"
  },
  "registered_at": "2024-01-15T08:00:00Z",
  "last_seen": "2024-01-15T10:29:55Z",
  "health": {
    "cpu_usage": 45.2,
    "memory_usage": 62.8,
    "active_tasks": 3
  },
  "metadata": {
    "region": "us-west-2",
    "environment": "production"
  }
}
```

**Status Codes:** 200, 401, 404, 500

---

#### POST /agents

Register a new agent.

**Request:**
```http
POST /agents HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
Content-Type: application/json

{
  "agent_id": "agent-002",
  "name": "Image Processor",
  "version": "1.0.0",
  "capabilities": ["image_processing", "ocr"],
  "endpoints": {
    "http": "http://agent-002:8080"
  },
  "metadata": {
    "region": "eu-west-1",
    "environment": "production"
  }
}
```

**Response:**
```json
{
  "success": true,
  "agent_id": "agent-002",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 201, 400, 401, 500

---

#### PUT /agents/{agent_id}

Update agent information.

**Request:**
```http
PUT /agents/agent-002 HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
Content-Type: application/json

{
  "name": "Enhanced Image Processor",
  "version": "1.1.0",
  "capabilities": ["image_processing", "ocr", "face_detection"]
}
```

**Response:**
```json
{
  "success": true,
  "agent_id": "agent-002",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 400, 401, 404, 500

---

#### DELETE /agents/{agent_id}

Unregister an agent.

**Request:**
```http
DELETE /agents/agent-002 HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Response:**
```json
{
  "success": true,
  "agent_id": "agent-002",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 401, 404, 500

---

#### POST /agents/{agent_id}/messages

Send a message to an agent.

**Request:**
```http
POST /agents/agent-001/messages HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
Content-Type: application/json

{
  "message": {
    "type": "task",
    "action": "process_data",
    "payload": {
      "data_id": "dataset-123",
      "operations": ["clean", "normalize", "aggregate"]
    }
  }
}
```

**Response:**
```json
{
  "success": true,
  "agent_id": "agent-001",
  "response": {
    "status": "accepted",
    "task_id": "task-456",
    "estimated_time": 120
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 400, 401, 404, 500

---

#### GET /agents/capabilities/{capability}

Get agents by capability.

**Request:**
```http
GET /agents/capabilities/data_processing HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Response:**
```json
{
  "capability": "data_processing",
  "agents": [
    {
      "agent_id": "agent-001",
      "name": "Data Processor",
      "status": "active",
      "load": 45.2
    }
  ],
  "count": 1,
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 400, 401, 500

---

#### PUT /agents/{agent_id}/status

Update agent status.

**Request:**
```http
PUT /agents/agent-001/status HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
Content-Type: application/json

{
  "status": "inactive"
}
```

**Response:**
```json
{
  "success": true,
  "agent_id": "agent-001",
  "status": "inactive",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 400, 401, 404, 500

---

### Workflow Management

#### GET /workflows

List all workflows.

**Request:**
```http
GET /workflows HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Query Parameters:**
- `status` (optional) - Filter by status (pending, running, completed, failed, cancelled)
- `limit` (optional) - Max results (default: 50)
- `offset` (optional) - Pagination offset (default: 0)

**Response:**
```json
{
  "workflows": [
    {
      "workflow_id": "wf-001",
      "name": "Data Processing Pipeline",
      "status": "running",
      "created_at": "2024-01-15T10:00:00Z",
      "started_at": "2024-01-15T10:00:05Z",
      "tasks": {
        "total": 5,
        "completed": 3,
        "pending": 2
      },
      "progress": 60
    }
  ],
  "total": 89,
  "limit": 50,
  "offset": 0
}
```

**Status Codes:** 200, 401, 500

---

#### GET /workflows/{workflow_id}

Get workflow details.

**Request:**
```http
GET /workflows/wf-001 HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Response:**
```json
{
  "workflow_id": "wf-001",
  "name": "Data Processing Pipeline",
  "status": "running",
  "created_at": "2024-01-15T10:00:00Z",
  "started_at": "2024-01-15T10:00:05Z",
  "tasks": [
    {
      "task_id": "task-001",
      "name": "Extract Data",
      "status": "completed",
      "agent_id": "agent-001",
      "started_at": "2024-01-15T10:00:05Z",
      "completed_at": "2024-01-15T10:05:00Z",
      "duration": 295
    },
    {
      "task_id": "task-002",
      "name": "Transform Data",
      "status": "running",
      "agent_id": "agent-002",
      "started_at": "2024-01-15T10:05:05Z"
    }
  ],
  "progress": 60,
  "metadata": {
    "owner": "user-123",
    "priority": "high"
  }
}
```

**Status Codes:** 200, 401, 404, 500

---

#### POST /workflows

Start a new workflow.

**Request:**
```http
POST /workflows HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
Content-Type: application/json

{
  "workflow_config": {
    "name": "Image Processing Pipeline",
    "tasks": [
      {
        "name": "Load Images",
        "agent_capability": "image_processing",
        "action": "load",
        "parameters": {
          "source": "s3://bucket/images/"
        }
      },
      {
        "name": "Process Images",
        "agent_capability": "image_processing",
        "action": "process",
        "parameters": {
          "operations": ["resize", "compress"]
        },
        "depends_on": ["Load Images"]
      }
    ],
    "timeout": 600,
    "metadata": {
      "owner": "user-123",
      "priority": "normal"
    }
  }
}
```

**Response:**
```json
{
  "success": true,
  "workflow_id": "wf-002",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 201, 400, 401, 500

---

#### PUT /workflows/{workflow_id}/status

Update workflow status (cancel/pause/resume).

**Request:**
```http
PUT /workflows/wf-002/status HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
Content-Type: application/json

{
  "status": "cancelled"
}
```

**Response:**
```json
{
  "success": true,
  "workflow_id": "wf-002",
  "status": "cancelled",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 400, 401, 404, 500

---

#### GET /workflows/{workflow_id}/logs

Get workflow execution logs.

**Request:**
```http
GET /workflows/wf-001/logs HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Query Parameters:**
- `level` (optional) - Filter by log level (DEBUG, INFO, WARNING, ERROR)
- `limit` (optional) - Max results (default: 100)

**Response:**
```json
{
  "workflow_id": "wf-001",
  "logs": [
    {
      "timestamp": "2024-01-15T10:00:05Z",
      "level": "INFO",
      "message": "Workflow started",
      "component": "workflow-orchestrator"
    },
    {
      "timestamp": "2024-01-15T10:00:06Z",
      "level": "DEBUG",
      "message": "Task 'Extract Data' assigned to agent-001",
      "component": "task-executor"
    }
  ],
  "count": 45,
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 401, 404, 500

---

### Metrics & Monitoring

#### GET /metrics

Get system metrics.

**Request:**
```http
GET /metrics HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Response:**
```json
{
  "bridge_metrics": {
    "total_messages_processed": 15432,
    "total_workflows_completed": 892,
    "total_agents_discovered": 12,
    "active_connections": 8,
    "uptime": 86400.5
  },
  "protocol_metrics": {
    "messages_sent": 7821,
    "messages_received": 7611,
    "errors": 23,
    "average_latency_ms": 45.2
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 401, 500

---

#### GET /system/info

Get system information.

**Request:**
```http
GET /system/info HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Response:**
```json
{
  "bridge": {
    "state": "running",
    "uptime": 86400.5,
    "total_messages_processed": 15432,
    "total_workflows_completed": 892,
    "total_agents_discovered": 12
  },
  "system": {
    "platform": "Linux-5.10.0-x86_64",
    "python_version": "3.11.4",
    "cpu_count": 8,
    "memory_total": 16842752000,
    "memory_available": 8421376000,
    "disk_usage": 45.2
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 401, 500

---

#### GET /system/logs

Get system logs.

**Request:**
```http
GET /system/logs HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Query Parameters:**
- `level` (optional) - Filter by log level
- `component` (optional) - Filter by component
- `limit` (optional) - Max results (default: 100)
- `since` (optional) - ISO timestamp to fetch logs since

**Response:**
```json
{
  "logs": [
    {
      "timestamp": "2024-01-15T10:30:00Z",
      "level": "INFO",
      "message": "Agent agent-001 registered successfully",
      "component": "agent-manager"
    },
    {
      "timestamp": "2024-01-15T10:29:55Z",
      "level": "DEBUG",
      "message": "Health check passed",
      "component": "api-server"
    }
  ],
  "count": 1234,
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 401, 500

---

### Configuration

#### GET /config

Get current configuration.

**Request:**
```http
GET /config HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Response:**
```json
{
  "bridge": {
    "host": "localhost",
    "port": 8001,
    "debug": false,
    "development": false
  },
  "system": {
    "host": "localhost",
    "port": 8001,
    "debug": false,
    "max_connections": 1000,
    "timeout": 30,
    "enable_cors": true,
    "auth_required": true
  },
  "security": {
    "allowed_origins": ["*"],
    "max_connections": 1000,
    "rate_limit": 100,
    "enable_cors": true,
    "ssl_enabled": false,
    "auth_required": true
  },
  "transport": {
    "type": "websocket",
    "websocket_url": "ws://localhost:8080",
    "sse_url": "http://localhost:8081",
    "max_connections": 100,
    "connection_timeout": 30,
    "message_timeout": 60,
    "heartbeat_interval": 30
  }
}
```

**Status Codes:** 200, 401, 500

---

#### PUT /config/{key}

Update configuration value.

**Request:**
```http
PUT /config/debug HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
Content-Type: application/json

{
  "value": true
}
```

**Response:**
```json
{
  "success": true,
  "key": "debug",
  "value": true,
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 400, 401, 500

---

#### POST /system/config/export

Export current configuration.

**Request:**
```http
POST /system/config/export HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
```

**Response:**
```json
{
  "bridge_config": {
    "host": "localhost",
    "port": 8001,
    "security": { },
    "transport": { },
    "agent": { },
    "workflow": { }
  },
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 401, 500

---

#### POST /system/config/import

Import new configuration.

**Request:**
```http
POST /system/config/import HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
Content-Type: application/json

{
  "config": {
    "security": {
      "rate_limit": 200,
      "max_connections": 2000
    }
  }
}
```

**Response:**
```json
{
  "success": true,
  "message": "Configuration imported successfully",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 400, 401, 500

---

### System Management

#### POST /system/shutdown

Gracefully shutdown the system.

**Request:**
```http
POST /system/shutdown HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
Authorization: Bearer admin-token
```

**Response:**
```json
{
  "success": true,
  "message": "System shutdown initiated",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 401, 403, 500

---

#### POST /system/restart

Restart the system.

**Request:**
```http
POST /system/restart HTTP/1.1
Host: localhost:8001
X-API-Key: your-api-key
Authorization: Bearer admin-token
```

**Response:**
```json
{
  "success": true,
  "message": "System restarted successfully",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Status Codes:** 200, 401, 403, 500

---

## Integration Examples

### Python Example

```python
import requests
import json

class A2ABridgeClient:
    def __init__(self, base_url="http://localhost:8001", api_key=None):
        self.base_url = base_url
        self.api_key = api_key
        self.session = requests.Session()
        if api_key:
            self.session.headers.update({"X-API-Key": api_key})

    def health_check(self):
        """Check API health"""
        response = self.session.get(f"{self.base_url}/health")
        return response.json()

    def list_agents(self, capability=None, status=None):
        """List all agents"""
        params = {}
        if capability:
            params["capability"] = capability
        if status:
            params["status"] = status

        response = self.session.get(
            f"{self.base_url}/agents",
            params=params
        )
        return response.json()

    def register_agent(self, agent_data):
        """Register a new agent"""
        response = self.session.post(
            f"{self.base_url}/agents",
            json=agent_data
        )
        return response.json()

    def send_agent_message(self, agent_id, message):
        """Send message to an agent"""
        response = self.session.post(
            f"{self.base_url}/agents/{agent_id}/messages",
            json={"message": message}
        )
        return response.json()

    def start_workflow(self, workflow_config):
        """Start a new workflow"""
        response = self.session.post(
            f"{self.base_url}/workflows",
            json={"workflow_config": workflow_config}
        )
        return response.json()

    def get_workflow_status(self, workflow_id):
        """Get workflow status"""
        response = self.session.get(
            f"{self.base_url}/workflows/{workflow_id}"
        )
        return response.json()

    def get_metrics(self):
        """Get system metrics"""
        response = self.session.get(f"{self.base_url}/metrics")
        return response.json()

# Usage example
if __name__ == "__main__":
    # Initialize client
    client = A2ABridgeClient(
        base_url="http://localhost:8001",
        api_key="your-api-key-here"
    )

    # Check health
    health = client.health_check()
    print(f"API Status: {health['status']}")

    # Register an agent
    agent = {
        "agent_id": "python-agent-001",
        "name": "Python Data Processor",
        "version": "1.0.0",
        "capabilities": ["data_processing", "analytics"],
        "endpoints": {
            "http": "http://python-agent:8080"
        },
        "metadata": {
            "language": "python",
            "framework": "fastapi"
        }
    }
    result = client.register_agent(agent)
    print(f"Agent registered: {result['agent_id']}")

    # Start a workflow
    workflow = {
        "name": "Data Processing Pipeline",
        "tasks": [
            {
                "name": "Load Data",
                "agent_capability": "data_processing",
                "action": "load",
                "parameters": {"source": "database"}
            },
            {
                "name": "Process Data",
                "agent_capability": "analytics",
                "action": "analyze",
                "depends_on": ["Load Data"]
            }
        ],
        "timeout": 300
    }
    result = client.start_workflow(workflow)
    workflow_id = result["workflow_id"]
    print(f"Workflow started: {workflow_id}")

    # Monitor workflow
    import time
    while True:
        status = client.get_workflow_status(workflow_id)
        print(f"Workflow status: {status['status']} ({status['progress']}%)")

        if status['status'] in ['completed', 'failed', 'cancelled']:
            break

        time.sleep(5)

    # Get metrics
    metrics = client.get_metrics()
    print(f"Total workflows completed: {metrics['bridge_metrics']['total_workflows_completed']}")
```

---

### JavaScript/Node.js Example

```javascript
const axios = require('axios');

class A2ABridgeClient {
    constructor(baseUrl = 'http://localhost:8001', apiKey = null) {
        this.baseUrl = baseUrl;
        this.apiKey = apiKey;

        this.client = axios.create({
            baseURL: baseUrl,
            headers: apiKey ? { 'X-API-Key': apiKey } : {},
            timeout: 30000
        });

        // Add response interceptor for error handling
        this.client.interceptors.response.use(
            response => response.data,
            error => {
                if (error.response) {
                    throw new Error(
                        `API Error ${error.response.status}: ${error.response.data.error.message}`
                    );
                }
                throw error;
            }
        );
    }

    async healthCheck() {
        return await this.client.get('/health');
    }

    async listAgents(options = {}) {
        return await this.client.get('/agents', { params: options });
    }

    async registerAgent(agentData) {
        return await this.client.post('/agents', agentData);
    }

    async sendAgentMessage(agentId, message) {
        return await this.client.post(
            `/agents/${agentId}/messages`,
            { message }
        );
    }

    async startWorkflow(workflowConfig) {
        return await this.client.post('/workflows', { workflow_config: workflowConfig });
    }

    async getWorkflowStatus(workflowId) {
        return await this.client.get(`/workflows/${workflowId}`);
    }

    async cancelWorkflow(workflowId) {
        return await this.client.put(
            `/workflows/${workflowId}/status`,
            { status: 'cancelled' }
        );
    }

    async getMetrics() {
        return await this.client.get('/metrics');
    }
}

// Usage example
(async () => {
    const client = new A2ABridgeClient(
        'http://localhost:8001',
        'your-api-key-here'
    );

    try {
        // Check health
        const health = await client.healthCheck();
        console.log(`API Status: ${health.status}`);

        // Register agent
        const agent = {
            agent_id: 'node-agent-001',
            name: 'Node.js Service',
            version: '1.0.0',
            capabilities: ['api_integration', 'data_transformation'],
            endpoints: {
                http: 'http://node-agent:3000'
            },
            metadata: {
                language: 'javascript',
                runtime: 'node.js'
            }
        };
        const registerResult = await client.registerAgent(agent);
        console.log(`Agent registered: ${registerResult.agent_id}`);

        // Start workflow
        const workflow = {
            name: 'API Integration Pipeline',
            tasks: [
                {
                    name: 'Fetch Data',
                    agent_capability: 'api_integration',
                    action: 'fetch',
                    parameters: { url: 'https://api.example.com/data' }
                },
                {
                    name: 'Transform Data',
                    agent_capability: 'data_transformation',
                    action: 'transform',
                    depends_on: ['Fetch Data']
                }
            ],
            timeout: 600
        };

        const workflowResult = await client.startWorkflow(workflow);
        const workflowId = workflowResult.workflow_id;
        console.log(`Workflow started: ${workflowId}`);

        // Monitor workflow
        const checkStatus = async () => {
            const status = await client.getWorkflowStatus(workflowId);
            console.log(`Workflow status: ${status.status} (${status.progress}%)`);

            if (['completed', 'failed', 'cancelled'].includes(status.status)) {
                console.log('Workflow finished!');
                return;
            }

            setTimeout(checkStatus, 5000);
        };

        await checkStatus();

        // Get final metrics
        const metrics = await client.getMetrics();
        console.log(
            `Total workflows: ${metrics.bridge_metrics.total_workflows_completed}`
        );

    } catch (error) {
        console.error('Error:', error.message);
    }
})();
```

---

### cURL Examples

#### Health Check
```bash
curl -X GET http://localhost:8001/health
```

#### Register Agent
```bash
curl -X POST http://localhost:8001/agents \
  -H "X-API-Key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "agent_id": "curl-agent-001",
    "name": "cURL Test Agent",
    "version": "1.0.0",
    "capabilities": ["testing"],
    "endpoints": {
      "http": "http://localhost:9000"
    }
  }'
```

#### List Agents
```bash
curl -X GET "http://localhost:8001/agents?capability=testing&limit=10" \
  -H "X-API-Key: your-api-key"
```

#### Start Workflow
```bash
curl -X POST http://localhost:8001/workflows \
  -H "X-API-Key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "workflow_config": {
      "name": "Test Workflow",
      "tasks": [
        {
          "name": "Test Task",
          "agent_capability": "testing",
          "action": "test"
        }
      ]
    }
  }'
```

#### Get Metrics
```bash
curl -X GET http://localhost:8001/metrics \
  -H "X-API-Key: your-api-key"
```

---

### Go Example

```go
package main

import (
    "bytes"
    "encoding/json"
    "fmt"
    "io/ioutil"
    "net/http"
    "time"
)

type A2ABridgeClient struct {
    BaseURL    string
    APIKey     string
    HTTPClient *http.Client
}

func NewA2ABridgeClient(baseURL, apiKey string) *A2ABridgeClient {
    return &A2ABridgeClient{
        BaseURL: baseURL,
        APIKey:  apiKey,
        HTTPClient: &http.Client{
            Timeout: 30 * time.Second,
        },
    }
}

func (c *A2ABridgeClient) doRequest(method, path string, body interface{}) ([]byte, error) {
    var reqBody []byte
    var err error

    if body != nil {
        reqBody, err = json.Marshal(body)
        if err != nil {
            return nil, err
        }
    }

    req, err := http.NewRequest(method, c.BaseURL+path, bytes.NewBuffer(reqBody))
    if err != nil {
        return nil, err
    }

    req.Header.Set("Content-Type", "application/json")
    if c.APIKey != "" {
        req.Header.Set("X-API-Key", c.APIKey)
    }

    resp, err := c.HTTPClient.Do(req)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    respBody, err := ioutil.ReadAll(resp.Body)
    if err != nil {
        return nil, err
    }

    if resp.StatusCode >= 400 {
        return nil, fmt.Errorf("API error %d: %s", resp.StatusCode, string(respBody))
    }

    return respBody, nil
}

func (c *A2ABridgeClient) HealthCheck() (map[string]interface{}, error) {
    data, err := c.doRequest("GET", "/health", nil)
    if err != nil {
        return nil, err
    }

    var result map[string]interface{}
    err = json.Unmarshal(data, &result)
    return result, err
}

func (c *A2ABridgeClient) RegisterAgent(agent map[string]interface{}) (map[string]interface{}, error) {
    data, err := c.doRequest("POST", "/agents", agent)
    if err != nil {
        return nil, err
    }

    var result map[string]interface{}
    err = json.Unmarshal(data, &result)
    return result, err
}

func (c *A2ABridgeClient) StartWorkflow(workflow map[string]interface{}) (map[string]interface{}, error) {
    payload := map[string]interface{}{
        "workflow_config": workflow,
    }

    data, err := c.doRequest("POST", "/workflows", payload)
    if err != nil {
        return nil, err
    }

    var result map[string]interface{}
    err = json.Unmarshal(data, &result)
    return result, err
}

func main() {
    client := NewA2ABridgeClient("http://localhost:8001", "your-api-key")

    // Health check
    health, err := client.HealthCheck()
    if err != nil {
        panic(err)
    }
    fmt.Printf("API Status: %v\n", health["status"])

    // Register agent
    agent := map[string]interface{}{
        "agent_id": "go-agent-001",
        "name":     "Go Service",
        "version":  "1.0.0",
        "capabilities": []string{"backend_processing"},
        "endpoints": map[string]string{
            "http": "http://go-agent:8080",
        },
    }

    result, err := client.RegisterAgent(agent)
    if err != nil {
        panic(err)
    }
    fmt.Printf("Agent registered: %v\n", result["agent_id"])

    // Start workflow
    workflow := map[string]interface{}{
        "name": "Go Processing Pipeline",
        "tasks": []map[string]interface{}{
            {
                "name":              "Process Data",
                "agent_capability":  "backend_processing",
                "action":            "process",
            },
        },
    }

    workflowResult, err := client.StartWorkflow(workflow)
    if err != nil {
        panic(err)
    }
    fmt.Printf("Workflow started: %v\n", workflowResult["workflow_id"])
}
```

---

## WebSocket Integration

For real-time updates, connect to the WebSocket endpoint:

```javascript
const ws = new WebSocket('ws://localhost:8080?api_key=your-api-key');

ws.onopen = () => {
    console.log('Connected to A2A Bridge');

    // Subscribe to events
    ws.send(JSON.stringify({
        type: 'subscribe',
        channels: ['agents', 'workflows', 'metrics']
    }));
};

ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    console.log('Received:', data);

    switch(data.type) {
        case 'agent.registered':
            console.log('New agent:', data.agent_id);
            break;
        case 'workflow.completed':
            console.log('Workflow completed:', data.workflow_id);
            break;
        case 'metrics.update':
            console.log('Metrics updated:', data.metrics);
            break;
    }
};

ws.onerror = (error) => {
    console.error('WebSocket error:', error);
};

ws.onclose = () => {
    console.log('Disconnected from A2A Bridge');
};
```

---

## Best Practices

### 1. Error Handling
Always handle errors gracefully and implement retry logic:

```python
import time
from requests.exceptions import RequestException

def retry_request(func, max_retries=3, delay=1):
    for attempt in range(max_retries):
        try:
            return func()
        except RequestException as e:
            if attempt == max_retries - 1:
                raise
            print(f"Attempt {attempt + 1} failed: {e}. Retrying...")
            time.sleep(delay * (attempt + 1))
```

### 2. Rate Limit Handling
Respect rate limits and implement backoff:

```python
def handle_rate_limit(response):
    if response.status_code == 429:
        retry_after = int(response.headers.get('X-RateLimit-Reset', 60))
        print(f"Rate limited. Waiting {retry_after} seconds...")
        time.sleep(retry_after)
        return True
    return False
```

### 3. Connection Pooling
Use connection pooling for better performance:

```python
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry

session = requests.Session()
retry = Retry(total=3, backoff_factor=0.5)
adapter = HTTPAdapter(max_retries=retry, pool_connections=10, pool_maxsize=10)
session.mount('http://', adapter)
session.mount('https://', adapter)
```

### 4. Async Operations
Use async/await for concurrent operations:

```python
import asyncio
import aiohttp

async def fetch_multiple_agents(agent_ids):
    async with aiohttp.ClientSession() as session:
        tasks = [
            fetch_agent(session, agent_id)
            for agent_id in agent_ids
        ]
        return await asyncio.gather(*tasks)

async def fetch_agent(session, agent_id):
    async with session.get(
        f'http://localhost:8001/agents/{agent_id}',
        headers={'X-API-Key': 'your-api-key'}
    ) as response:
        return await response.json()
```

---

## Support

For issues, questions, or feature requests:

- **Documentation:** https://a2a-bridge.readthedocs.io
- **GitHub Issues:** https://github.com/your-org/a2a-bridge/issues
- **Email:** support@a2a-bridge.example.com
- **Slack:** #a2a-bridge-support

---

## Changelog

### Version 1.0.0 (2024-01-15)
- Initial API release
- Agent management endpoints
- Workflow orchestration
- Metrics and monitoring
- Configuration management
- WebSocket support
- Rate limiting
- API key authentication

---

**Last Updated:** 2024-01-15
**API Version:** 1.0.0
