# Workflow API Endpoints

Complete reference for all workflow management endpoints.

## Create Workflow

Creates a new workflow instance.

```http
POST /api/workflows
Content-Type: application/json
```

### Request Body

```json
{
  "pattern": "sequential|parallel_split|exclusive_choice|...",
  "name": "workflow_name",
  "description": "Optional description",
  "parameters": {
    "branches": 3,
    "conditions": {...}
  },
  "options": {
    "enable_checkpoint": true,
    "checkpoint_interval": 10000,
    "enable_xes": true
  }
}
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "status": "created",
  "pattern": "sequential",
  "created_at": "2024-01-01T10:00:00Z"
}
```

### Examples

```bash
# Sequential workflow
curl -X POST http://localhost:8081/api/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "sequential",
    "name": "order_processing"
  }'

# Parallel split with resource allocation
curl -X POST http://localhost:8081/api/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "parallel_split",
    "name": "parallel_checks",
    "parameters": {
      "branches": [
        {"task": "inventory_check", "capabilities": ["inventory"]},
        {"task": "credit_check", "capabilities": ["credit"]}
      ]
    }
  }'
```

## List Workflows

Lists all workflows with optional filtering.

```http
GET /api/workflows?page=1&per_page=50&status=running
```

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `page` | integer | Page number (default: 1) |
| `per_page` | integer | Items per page (default: 50) |
| `status` | string | Filter by status |
| `pattern` | string | Filter by pattern type |
| `sort_by` | string | Sort field (created_at, updated_at, name) |
| `order` | string | Sort order (asc, desc) |

### Response

```json
{
  "data": [
    {
      "workflow_id": "seq_abc123",
      "pattern": "sequential",
      "name": "order_processing",
      "status": "running",
      "created_at": "2024-01-01T10:00:00Z",
      "updated_at": "2024-01-01T10:05:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 50,
    "total": 100,
    "total_pages": 2
  }
}
```

## Get Workflow Details

Retrieves detailed information about a workflow.

```http
GET /api/workflows/{workflow_id}
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "pattern": "sequential",
  "name": "order_processing",
  "description": "Process customer orders",
  "status": "running",
  "current_step": "payment_processing",
  "progress": 60,
  "created_at": "2024-01-01T10:00:00Z",
  "started_at": "2024-01-01T10:01:00Z",
  "updated_at": "2024-01-01T10:05:00Z",
  "configuration": {...},
  "statistics": {
    "total_tasks": 5,
    "completed_tasks": 3,
    "pending_tasks": 1,
    "failed_tasks": 0
  }
}
```

## Execute Workflow

Starts execution of a workflow.

```http
POST /api/workflows/{workflow_id}/execute
Content-Type: application/json
```

### Request Body

```json
{
  "input_data": {
    "customer_id": "cust_123",
    "amount": 500,
    "items": [...]
  },
  "options": {
    "async": true,
    "timeout": 300000
  }
}
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "status": "running",
  "started_at": "2024-01-01T10:00:00Z",
  "message": "Workflow execution started"
}
```

## Pause Workflow

Pauses a running workflow.

```http
POST /api/workflows/{workflow_id}/pause
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "status": "paused",
  "paused_at": "2024-01-01T10:05:00Z"
}
```

## Resume Workflow

Resumes a paused workflow.

```http
POST /api/workflows/{workflow_id}/resume
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "status": "running",
  "resumed_at": "2024-01-01T10:06:00Z"
}
```

## Cancel Workflow

Cancels a workflow execution.

```http
POST /api/workflows/{workflow_id}/cancel
Content-Type: application/json
```

### Request Body

```json
{
  "reason": "Customer requested cancellation"
}
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "status": "cancelled",
  "cancelled_at": "2024-01-01T10:05:00Z",
  "reason": "Customer requested cancellation"
}
```

## Get Workflow Status

Retrieves current workflow status.

```http
GET /api/workflows/{workflow_id}/status
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "status": "running",
  "current_step": "task_3",
  "progress": 60,
  "steps": [
    {"name": "task_1", "status": "completed"},
    {"name": "task_2", "status": "completed"},
    {"name": "task_3", "status": "in_progress"},
    {"name": "task_4", "status": "pending"},
    {"name": "task_5", "status": "pending"}
  ],
  "timestamp": "2024-01-01T10:05:00Z"
}
```

## List Tasks

Lists all tasks for a workflow.

```http
GET /api/workflows/{workflow_id}/tasks?status=pending
```

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `status` | string | Filter by status (pending, in_progress, completed, failed) |

### Response

```json
{
  "tasks": [
    {
      "task_id": "task_1",
      "name": "validate_order",
      "status": "completed",
      "assigned_resource": "resource_1",
      "created_at": "2024-01-01T10:00:00Z",
      "completed_at": "2024-01-01T10:01:00Z"
    },
    {
      "task_id": "task_2",
      "name": "process_payment",
      "status": "pending",
      "capabilities_required": ["payment"],
      "created_at": "2024-01-01T10:01:00Z"
    }
  ]
}
```

## Get Task Details

Retrieves details of a specific task.

```http
GET /api/workflows/{workflow_id}/tasks/{task_id}
```

### Response

```json
{
  "task_id": "task_2",
  "name": "process_payment",
  "status": "in_progress",
  "capabilities_required": ["payment"],
  "assigned_resource": "payment_service",
  "input_data": {...},
  "output_data": null,
  "created_at": "2024-01-01T10:01:00Z",
  "started_at": "2024-01-01T10:02:00Z"
}
```

## Complete Task

Marks a task as completed.

```http
POST /api/workflows/{workflow_id}/tasks/{task_id}/complete
Content-Type: application/json
```

### Request Body

```json
{
  "result": {
    "status": "completed",
    "output": "Payment processed successfully",
    "data": {
      "transaction_id": "txn_123",
      "amount": 500.00
    }
  }
}
```

### Response

```json
{
  "task_id": "task_2",
  "status": "completed",
  "completed_at": "2024-01-01T10:03:00Z"
}
```

## Fail Task

Marks a task as failed.

```http
POST /api/workflows/{workflow_id}/tasks/{task_id}/fail
Content-Type: application/json
```

### Request Body

```json
{
  "error": {
    "code": "payment_declined",
    "message": "Payment was declined by provider",
    "details": {
      "provider": "stripe",
      "reason": "insufficient_funds"
    }
  }
}
```

### Response

```json
{
  "task_id": "task_2",
  "status": "failed",
  "failed_at": "2024-01-01T10:03:00Z",
  "error": {...}
}
```

## Allocate Task Resource

Allocates a resource to a task.

```http
POST /api/workflows/{workflow_id}/tasks/{task_id}/allocate
Content-Type: application/json
```

### Request Body

```json
{
  "capabilities": ["payment"],
  "strategy": "least_loaded",
  "preferences": {
    "priority": "high"
  }
}
```

### Response

```json
{
  "task_id": "task_2",
  "resource_id": "payment_service_1",
  "allocated_at": "2024-01-01T10:02:00Z"
}
```

## Release Task Resource

Releases a resource from a task.

```http
POST /api/workflows/{workflow_id}/tasks/{task_id}/release
Content-Type: application/json
```

### Request Body

```json
{
  "resource_id": "payment_service_1",
  "result": {
    "success": true
  }
}
```

### Response

```json
{
  "task_id": "task_2",
  "resource_id": "payment_service_1",
  "released_at": "2024-01-01T10:03:00Z"
}
```

## Get Workflow History

Retrieves workflow execution history.

```http
GET /api/workflows/{workflow_id}/history
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "history": [
    {
      "event": "workflow_created",
      "timestamp": "2024-01-01T10:00:00Z",
      "details": {...}
    },
    {
      "event": "workflow_started",
      "timestamp": "2024-01-01T10:01:00Z",
      "details": {...}
    },
    {
      "event": "task_completed",
      "timestamp": "2024-01-01T10:02:00Z",
      "details": {
        "task_id": "task_1",
        "name": "validate_order"
      }
    }
  ]
}
```

## Export XES Log

Exports workflow log in XES format.

```http
GET /api/workflows/{workflow_id}/xes
```

### Response

```xml
<?xml version="1.0" encoding="UTF-8"?>
<log xmlns="http://www.xes-standard.org/">
  <trace>
    <string key="concept:name" value="seq_abc123"/>
    <event>
      <string key="concept:name" value="workflow_created"/>
      <date key="time:timestamp" value="2024-01-01T10:00:00Z"/>
    </event>
  </trace>
</log>
```

## Get Workflow Metrics

Retrieves workflow metrics.

```http
GET /api/workflows/{workflow_id}/metrics
```

### Response

```json
{
  "workflow_id": "seq_abc123",
  "metrics": {
    "execution_time": 300000,
    "total_tasks": 5,
    "completed_tasks": 4,
    "failed_tasks": 0,
    "average_task_time": 60000,
    "resource_utilization": 0.8
  }
}
```

## Event Streaming

Subscribes to workflow events.

```http
GET /api/workflows/{workflow_id}/events/stream
```

Or via WebSocket:

```ws
WS /api/workflows/{workflow_id}/events/ws
```

### Event Types

| Event | Description |
|-------|-------------|
| `workflow_created` | Workflow created |
| `workflow_started` | Workflow execution started |
| `task_created` | New task created |
| `task_started` | Task execution started |
| `task_completed` | Task completed |
| `task_failed` | Task failed |
| `workflow_completed` | Workflow completed |
| `workflow_failed` | Workflow failed |
| `workflow_cancelled` | Workflow cancelled |

---

Next: [Research Endpoints](research-endpoints.md) | [Back to Overview](overview.md)
