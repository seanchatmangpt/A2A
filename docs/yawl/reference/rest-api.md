# YAWL REST API Reference

This document provides a comprehensive reference for the YAWL (Yet Another Workflow Language) REST API. The API follows RESTful design principles and provides endpoints for workflow management, pattern queries, resource allocation, metrics, and XES export.

## Base URL

```
http://localhost:8081/api/v1
```

## Authentication

The YAWL REST API supports multiple authentication methods via the `yawl_auth_middleware`:

- **Bearer Token**: Include `Authorization: Bearer <token>` header
- **API Key**: Include `X-API-Key: <key>` header
- **Basic Auth**: Include `Authorization: Basic <credentials>` header

## CORS Support

The API supports Cross-Origin Resource Sharing (CORS) with configurable origins. Preflight OPTIONS requests are automatically handled.

## Response Format

All API responses use JSON format:

```json
{
  "status": "success",
  "data": { ... },
  "meta": {
    "timestamp": 1704067200000,
    "request_id": "req_abc123"
  }
}
```

Error responses follow this structure:

```json
{
  "error": "error_code",
  "message": "Human readable error message",
  "details": { ... }
}
```

---

## Workflows

### List Workflows

Get a paginated list of all workflows.

**Endpoint:** `GET /workflows`

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| status | string | - | Filter by status (created, running, paused, completed, cancelled, failed) |
| limit | integer | 50 | Maximum number of results |
| offset | integer | 0 | Number of results to skip |

**Response:**

```json
{
  "workflows": [
    {
      "workflow_id": "wf_20240101_abc123",
      "spec_id": "order_processing",
      "pattern_type": "parallel_sequence",
      "status": "running",
      "created_at": 1704067200000,
      "updated_at": 1704067260000,
      "metadata": {
        "current_place": "process_payment",
        "parent_workflow_id": null
      }
    }
  ],
  "total": 100,
  "returned": 50,
  "offset": 0
}
```

### Create Workflow

Create a new workflow instance.

**Endpoint:** `POST /workflows`

**Request Body:**

```json
{
  "pattern_type": "basic_sequential",
  "config": {
    "tasks": ["task1", "task2", "task3"],
    "data": { "key": "value" }
  },
  "timeout": 300000,
  "retry_policy": {
    "max_retries": 3,
    "backoff": "exponential"
  }
}
```

**Response:**

```json
{
  "workflow_id": "wf_20240101_def456",
  "status": "created",
  "message": "Workflow created successfully"
}
```

### Get Workflow

Get details of a specific workflow.

**Endpoint:** `GET /workflows/{id}`

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| id | string | Workflow ID |

**Response:**

```json
{
  "workflow_id": "wf_20240101_def456",
  "spec_id": "order_processing",
  "pattern_type": "basic_sequential",
  "status": "running",
  "marking": ["process_payment"],
  "data": { "order_id": "12345" },
  "created_at": 1704067200000,
  "updated_at": 1704067260000,
  "completed_at": null,
  "error": null
}
```

### Delete Workflow

Delete a workflow and all associated resources.

**Endpoint:** `DELETE /workflows/{id}`

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| id | string | Workflow ID |

**Response:**

```json
{
  "status": "ok",
  "message": "Workflow deleted successfully",
  "deleted": {
    "workflow_id": "wf_20240101_def456",
    "orchestrator": "orchestrator_cancelled",
    "persistence": "workflow_deleted",
    "workitems": 5,
    "checkpoints": 2,
    "history": "history_deleted",
    "resources": "resources_deallocated"
  }
}
```

### Start Workflow

Start a workflow execution.

**Endpoint:** `POST /workflows/{id}/start`

**Response:**

```json
{
  "workflow_id": "wf_20240101_def456",
  "status": "running",
  "message": "Workflow started"
}
```

### Cancel Workflow

Cancel a running workflow.

**Endpoint:** `POST /workflows/{id}/cancel`

**Response:**

```json
{
  "workflow_id": "wf_20240101_def456",
  "status": "cancelled",
  "message": "Workflow cancelled"
}
```

### Suspend Workflow

Suspend a running workflow.

**Endpoint:** `POST /workflows/{id}/suspend`

**Response:**

```json
{
  "workflow_id": "wf_20240101_def456",
  "status": "paused",
  "message": "Workflow paused"
}
```

### Resume Workflow

Resume a suspended workflow.

**Endpoint:** `POST /workflows/{id}/resume`

**Response:**

```json
{
  "workflow_id": "wf_20240101_def456",
  "status": "resumed",
  "message": "Workflow resumed"
}
```

### Get Workflow Marking

Get the current marking (state) of a workflow.

**Endpoint:** `GET /workflows/{id}/marking`

**Response:**

```json
{
  "workflow_id": "wf_20240101_def456",
  "marking": ["process_payment", "send_notification"],
  "tokens": {
    "process_payment": 1,
    "send_notification": 1
  }
}
```

### Get Workflow History

Get the execution history of a workflow.

**Endpoint:** `GET /workflows/{id}/history`

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| limit | integer | 100 | Maximum number of history entries |

**Response:**

```json
{
  "workflow_id": "wf_20240101_def456",
  "history": [
    {
      "history_id": "hist_001",
      "workflow_id": "wf_20240101_def456",
      "workitem_id": "wi_001",
      "event_type": "start",
      "event_data": { "task": "validate_order" },
      "timestamp": 1704067200000,
      "source": "orchestrator"
    }
  ],
  "total": 50
}
```

### Stream Workflow Events (SSE)

Stream real-time workflow events using Server-Sent Events.

**Endpoint:** `GET /workflows/{id}/events`

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| event_types | string | all | Comma-separated event types to filter |
| since | integer | - | Timestamp to start streaming from (ms) |
| heartbeat | integer | 30 | Heartbeat interval in seconds |

**Event Types:**

- `workflow_start` - Workflow execution started
- `workflow_complete` - Workflow execution completed
- `workflow_cancel` - Workflow execution cancelled
- `workflow_error` - Workflow execution error
- `task_start` - Task execution started
- `task_complete` - Task execution completed
- `task_fail` - Task execution failed
- `marking_change` - Workflow marking changed
- `resource_allocated` - Resource allocated to task
- `resource_deallocated` - Resource deallocated

**Example:**

```javascript
const es = new EventSource('/workflows/wf_123/events');

es.addEventListener('task_complete', (e) => {
    const data = JSON.parse(e.data);
    console.log('Task completed:', data);
});
```

---

## Patterns

### List Patterns

List all available workflow patterns.

**Endpoint:** `GET /patterns`

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| category | string | - | Filter by pattern category |

**Response:**

```json
{
  "patterns": [
    {
      "id": "basic_sequential",
      "name": "Basic Sequence",
      "category": "control_flow",
      "description": "Simple sequential execution of tasks",
      "places": ["start", "end"],
      "transitions": ["start->end"],
      "parameters": {
        "tasks": {
          "type": "list",
          "required": true,
          "description": "List of task IDs to execute sequentially"
        }
      }
    }
  ],
  "total": 25
}
```

### Get Pattern

Get detailed information about a specific pattern.

**Endpoint:** `GET /patterns/{type}`

**Response:**

```json
{
  "id": "parallel_sequence",
  "name": "Parallel Sequence",
  "category": "control_flow",
  "description": "Execute multiple branches in parallel then synchronize",
  "places": ["start", "parallel", "end"],
  "transitions": [
    "start->parallel",
    "parallel->end"
  ],
  "parameters": {
    "branches": {
      "type": "list",
      "required": true,
      "description": "List of branch definitions"
    }
  },
  "examples": [
    {
      "name": "Order Processing",
      "config": {
        "branches": [
          ["validate_payment", "charge_payment"],
          ["check_inventory", "reserve_items"]
        ]
      }
    }
  ]
}
```

### List Pattern Categories

List all pattern categories.

**Endpoint:** `GET /patterns/categories`

**Response:**

```json
{
  "categories": [
    {
      "id": "control_flow",
      "name": "Control Flow",
      "description": "Basic workflow control patterns",
      "patterns": ["basic_sequential", "parallel_split", "synchronization"]
    },
    {
      "id": "resource",
      "name": "Resource Patterns",
      "description": "Resource allocation and management",
      "patterns": ["role_based", "resource_allocation"]
    }
  ]
}
```

### Get Patterns by Category

Get patterns within a specific category.

**Endpoint:** `GET /patterns/{category}`

**Response:**

```json
{
  "category": "control_flow",
  "patterns": [
    { "id": "basic_sequential", "name": "Basic Sequence" },
    { "id": "parallel_split", "name": "Parallel Split" }
  ]
}
```

### Validate Pattern

Validate a pattern configuration.

**Endpoint:** `POST /patterns/validate`

**Request Body:**

```json
{
  "pattern_type": "parallel_sequence",
  "config": {
    "branches": [
      ["task1", "task2"],
      ["task3", "task4"]
    ]
  }
}
```

**Response:**

```json
{
  "valid": true,
  "warnings": [],
  "validated_config": { ... }
}
```

---

## Resources

### List Resources

List all available resources.

**Endpoint:** `GET /resources`

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| type | string | - | Filter by resource type |
| status | string | - | Filter by status (available, allocated) |

**Response:**

```json
{
  "resources": [
    {
      "resource_id": "res_001",
      "type": "human",
      "name": "Order Processor",
      "capabilities": ["process_order", "validate_payment"],
      "status": "available",
      "properties": {
        "max_concurrent": 5
      }
    }
  ],
  "total": 10
}
```

### Allocate Resource

Allocate a resource to a workitem.

**Endpoint:** `POST /resources/allocate`

**Request Body:**

```json
{
  "workitem_id": "wi_001",
  "resource_type": "human",
  "capabilities": ["process_order"],
  "priority": "high"
}
```

**Response:**

```json
{
  "allocation_id": "alloc_001",
  "resource_id": "res_001",
  "workitem_id": "wi_001",
  "status": "allocated",
  "expires_at": 1704070800000
}
```

### Deallocate Resource

Release an allocated resource.

**Endpoint:** `POST /resources/deallocate`

**Request Body:**

```json
{
  "allocation_id": "alloc_001"
}
```

**Response:**

```json
{
  "status": "ok",
  "message": "Resource deallocated"
}
```

### Get Resource

Get details of a specific resource.

**Endpoint:** `GET /resources/{id}`

**Response:**

```json
{
  "resource_id": "res_001",
  "type": "human",
  "name": "Order Processor",
  "capabilities": ["process_order", "validate_payment"],
  "status": "allocated",
  "current_allocation": {
    "workitem_id": "wi_001",
    "allocated_at": 1704067200000
  },
  "properties": {
    "max_concurrent": 5
  }
}
```

---

## Tasks

### List Tasks

List all tasks (workitems).

**Endpoint:** `GET /tasks`

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| status | string | - | Filter by status |
| workflow_id | string | - | Filter by workflow |
| limit | integer | 50 | Maximum number of results |
| offset | integer | 0 | Number of results to skip |

**Response:**

```json
{
  "tasks": [
    {
      "workitem_id": "wi_001",
      "workflow_id": "wf_001",
      "task_id": "process_order",
      "task_name": "Process Order",
      "status": "pending",
      "data": { "order_id": "12345" },
      "priority": "normal",
      "created_at": 1704067200000
    }
  ],
  "total": 100,
  "returned": 50,
  "offset": 0
}
```

### Create Task

Create a new task (workitem).

**Endpoint:** `POST /tasks`

**Request Body:**

```json
{
  "workflow_id": "wf_001",
  "task_name": "Process Order",
  "task_id": "process_order",
  "priority": "high",
  "data": {
    "order_id": "12345"
  }
}
```

**Response:**

```json
{
  "workitem_id": "wi_001",
  "task_id": "process_order",
  "status": "created",
  "message": "Task created and queued"
}
```

### Get Task

Get details of a specific task.

**Endpoint:** `GET /tasks/{id}`

**Response:**

```json
{
  "workitem_id": "wi_001",
  "workflow_id": "wf_001",
  "task_id": "process_order",
  "task_name": "Process Order",
  "status": "in_progress",
  "data": { "order_id": "12345" },
  "allocated_to": {
    "resource_id": "res_001",
    "allocated_at": 1704067260000
  },
  "start_time": 1704067260000,
  "priority": "high"
}
```

### Complete Task

Mark a task as completed.

**Endpoint:** `POST /tasks/{id}/complete`

**Request Body:**

```json
{
  "workitem_id": "wi_001",
  "workflow_id": "wf_001",
  "result": {
    "status": "success",
    "output": { "processed": true }
  }
}
```

**Response:**

```json
{
  "task_id": "process_order",
  "workitem_id": "wi_001",
  "status": "completed",
  "completion_time": 1704067320000,
  "result": { "status": "success" }
}
```

### Claim Task

Claim a task for execution.

**Endpoint:** `POST /tasks/{id}/claim`

**Request Body:**

```json
{
  "assignee": "user_123"
}
```

**Response:**

```json
{
  "workitem_id": "wi_001",
  "status": "claimed",
  "claimed_by": "user_123",
  "claimed_at": 1704067320000
}
```

### Reassign Task

Reassign a task to a different resource.

**Endpoint:** `POST /tasks/{id}/reassign`

**Request Body:**

```json
{
  "to_resource": "res_002",
  "reason": "Original resource unavailable"
}
```

**Response:**

```json
{
  "workitem_id": "wi_001",
  "status": "reassigned",
  "from_resource": "res_001",
  "to_resource": "res_002",
  "reassigned_at": 1704067320000
}
```

---

## Metrics

### Get Metrics

Get system metrics.

**Endpoint:** `GET /metrics`

**Response:**

```json
{
  "system": {
    "uptime": 86400,
    "memory_used": 524288000,
    "memory_available": 2097152000,
    "cpu_usage": 45.5
  },
  "workflows": {
    "total": 1000,
    "running": 50,
    "completed": 900,
    "failed": 25,
    "cancelled": 25
  },
  "tasks": {
    "pending": 100,
    "in_progress": 50,
    "completed": 10000,
    "failed": 50
  },
  "resources": {
    "total": 100,
    "available": 75,
    "allocated": 25
  }
}
```

### Get Performance Metrics

Get detailed performance metrics.

**Endpoint:** `GET /metrics/performance`

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| period | string | 1h | Time period (1h, 24h, 7d) |

**Response:**

```json
{
  "period": "1h",
  "workflow_metrics": {
    "avg_execution_time": 5000,
    "p50_execution_time": 3000,
    "p95_execution_time": 15000,
    "p99_execution_time": 30000,
    "throughput": 100,
    "success_rate": 99.5
  },
  "task_metrics": {
    "avg_execution_time": 1000,
    "p50_execution_time": 500,
    "p95_execution_time": 5000,
    "p99_execution_time": 10000,
    "throughput": 500
  },
  "resource_utilization": {
    "avg_utilization": 75.5,
    "peak_utilization": 95.0
  }
}
```

---

## XES Export

### Export Workflow as XES

Export a workflow's execution log in XES format.

**Endpoint:** `GET /xes/workflows/{workflow_id}`

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| format | string | json | Response format (json, xml) |
| include_trace | boolean | true | Include trace information |

**Response (JSON):**

```json
{
  "workflow_id": "wf_001",
  "format": "xes",
  "log": "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<log xmlns=\"http://www.xes-standard.org/\" version=\"1.0\">...",
  "events": 50
}
```

### Export All Workflows as XES

Export all workflows in XES format.

**Endpoint:** `GET /xes`

**Query Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| format | string | json | Response format (json, xml) |
| status | string | - | Filter by workflow status |

**Response:**

```json
{
  "workflows": [
    {
      "workflow_id": "wf_001",
      "xes_log": "..."
    }
  ],
  "total": 10
}
```

---

## Health

### Health Check

Check the health status of the API.

**Endpoint:** `GET /health`

**Response:**

```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": 1704067200000,
  "components": {
    "database": "healthy",
    "orchestrator": "healthy",
    "persistence": "healthy"
  }
}
```

---

## Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `validation_failed` | 400 | Request validation failed |
| `workflow_not_found` | 404 | Workflow not found |
| `task_not_found` | 404 | Task not found |
| `resource_not_found` | 404 | Resource not found |
| `workflow_running` | 409 | Cannot modify running workflow |
| `internal_server_error` | 500 | Internal server error |

---

## Rate Limiting

The API implements rate limiting per client:

- **Default limit**: 1000 requests per hour
- **Burst limit**: 100 requests per minute

Rate limit headers are included in all responses:

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 950
X-RateLimit-Reset: 1704070800
```

---

## WebSocket Support

For real-time updates, the API supports WebSocket connections:

**Endpoint:** `WS /workflows/{id}/ws`

Connect using WebSocket protocol for bidirectional event streaming.

---

## SDK Examples

### cURL

```bash
# Create workflow
curl -X POST http://localhost:8081/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "pattern_type": "basic_sequential",
    "config": {"tasks": ["task1", "task2"]}
  }'

# Get workflow status
curl http://localhost:8081/workflows/wf_001

# Stream events
curl -N http://localhost:8081/workflows/wf_001/events
```

### Python

```python
import requests

# Create workflow
response = requests.post('http://localhost:8081/workflows', json={
    'pattern_type': 'basic_sequential',
    'config': {'tasks': ['task1', 'task2']}
})
workflow = response.json()
print(workflow['workflow_id'])
```

### JavaScript

```javascript
// Create workflow
const response = await fetch('/workflows', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
        pattern_type: 'basic_sequential',
        config: {tasks: ['task1', 'task2']}
    })
});
const workflow = await response.json();
console.log(workflow.workflow_id);

// Stream events
const es = new EventSource(`/workflows/${workflow.workflow_id}/events`);
es.addEventListener('task_complete', (e) => {
    console.log('Task completed:', JSON.parse(e.data));
});
```

---

## Changelog

### Version 1.0.0
- Initial release
- Workflow CRUD operations
- Pattern queries
- Resource management
- Task operations
- Metrics and monitoring
- XES export
- SSE event streaming
- CORS support
