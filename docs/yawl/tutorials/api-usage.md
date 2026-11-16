# YAWL REST API Usage Tutorial

This tutorial shows how to interact with YAWL workflows through the REST API.

## API Basics

### Base URL

```
http://localhost:8081/api
```

### Content Type

All requests use JSON:

```bash
-H "Content-Type: application/json"
```

## Authentication (Optional)

If authentication is enabled:

```bash
# Get token
curl -X POST http://localhost:8081/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "secret"}'

# Use token
curl -H "Authorization: Bearer <token>" http://localhost:8081/api/workflows
```

## Workflow Management

### Create Workflow

```bash
# Sequential workflow
curl -X POST http://localhost:8081/api/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "sequential",
    "name": "order_processing",
    "description": "Process customer orders"
  }'

# Parallel split workflow
curl -X POST http://localhost:8081/api/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "parallel_split",
    "name": "parallel_checks",
    "description": "Run checks in parallel",
    "parameters": {
      "branches": 3
    }
  }'

# Exclusive choice workflow
curl -X POST http://localhost:8081/api/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "exclusive_choice",
    "name": "approval_flow",
    "description": "Route based on amount",
    "parameters": {
      "conditions": {
        "low": {"threshold": 100},
        "medium": {"threshold": 1000}
      }
    }
  }'
```

### Execute Workflow

```bash
# Start workflow execution
curl -X POST http://localhost:8081/api/workflows/{workflow_id}/execute

# Execute with parameters
curl -X POST http://localhost:8081/api/workflows/{workflow_id}/execute \
  -H "Content-Type: application/json" \
  -d '{
    "input_data": {"customer_id": "cust_123", "amount": 500}
  }'
```

### Get Workflow Status

```bash
# Get current status
curl http://localhost:8081/api/workflows/{workflow_id}/status

# Get detailed status
curl http://localhost:8081/api/workflows/{workflow_id}/details

# Get workflow history
curl http://localhost:8081/api/workflows/{workflow_id}/history
```

### Pause/Resume Workflow

```bash
# Pause workflow
curl -X POST http://localhost:8081/api/workflows/{workflow_id}/pause

# Resume workflow
curl -X POST http://localhost:8081/api/workflows/{workflow_id}/resume
```

### Cancel Workflow

```bash
# Cancel workflow
curl -X POST http://localhost:8081/api/workflows/{workflow_id}/cancel

# Cancel with reason
curl -X POST http://localhost:8081/api/workflows/{workflow_id}/cancel \
  -H "Content-Type: application/json" \
  -d '{"reason": "Customer requested cancellation"}'
```

## Task Management

### List Tasks

```bash
# List all tasks for a workflow
curl http://localhost:8081/api/workflows/{workflow_id}/tasks

# Get pending tasks
curl http://localhost:8081/api/workflows/{workflow_id}/tasks?status=pending

# Get specific task
curl http://localhost:8081/api/workflows/{workflow_id}/tasks/{task_id}
```

### Complete Task

```bash
# Complete a task
curl -X POST http://localhost:8081/api/workflows/{workflow_id}/tasks/{task_id}/complete \
  -H "Content-Type: application/json" \
  -d '{
    "result": {
      "status": "completed",
      "output": "Task completed successfully"
    }
  }'
```

### Fail Task

```bash
# Fail a task
curl -X POST http://localhost:8081/api/workflows/{workflow_id}/tasks/{task_id}/fail \
  -H "Content-Type: application/json" \
  -d '{
    "error": {
      "code": "validation_failed",
      "message": "Invalid input data"
    }
  }'
```

## Pattern Management

### List Patterns

```bash
# List all patterns
curl http://localhost:8081/api/patterns

# Get pattern info
curl http://localhost:8081/api/patterns/{pattern_name}

# Validate pattern configuration
curl -X POST http://localhost:8081/api/patterns/{pattern_name}/validate \
  -H "Content-Type: application/json" \
  -d '{
    "parameters": {"branches": 3}
  }'
```

## Resource Management

### List Resources

```bash
# List all resources
curl http://localhost:8081/api/resources

# Filter by type
curl http://localhost:8081/api/resources?type=human

# Filter by capability
curl http://localhost:8081/api/resources?capability=approval

# Get resource details
curl http://localhost:8081/api/resources/{resource_id}
```

### Register Resource

```bash
# Register human resource
curl -X POST http://localhost:8081/api/resources \
  -H "Content-Type: application/json" \
  -d '{
    "resource_id": "john_doe",
    "type": "human",
    "name": "John Doe",
    "capabilities": ["approval", "review"],
    "max_capacity": 5
  }'

# Register service resource
curl -X POST http://localhost:8081/api/resources \
  -H "Content-Type: application/json" \
  -d '{
    "resource_id": "payment_service",
    "type": "service",
    "name": "Payment Gateway",
    "capabilities": ["payment_processing"],
    "endpoint": "https://api.payment.com/v1"
  }'
```

### Resource Allocation

```bash
# Allocate resource for task
curl -X POST http://localhost:8081/api/workflows/{workflow_id}/tasks/{task_id}/allocate \
  -H "Content-Type: application/json" \
  -d '{
    "capabilities": ["approval"],
    "strategy": "least_loaded"
  }'

# Release resource
curl -X POST http://localhost:8081/api/workflows/{workflow_id}/tasks/{task_id}/release \
  -H "Content-Type: application/json" \
  -d '{
    "resource_id": "resource_123",
    "result": {"success": true}
  }'
```

## Monitoring and Events

### Get Metrics

```bash
# System metrics
curl http://localhost:8081/api/metrics

# Workflow metrics
curl http://localhost:8081/api/workflows/{workflow_id}/metrics

# Resource metrics
curl http://localhost:8081/api/resources/metrics
```

### Event Stream

```bash
# Subscribe to workflow events (WebSocket)
curl -i -N \
  -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  -H "Host: localhost:8081" \
  -H "Origin: http://localhost:8081" \
  http://localhost:8081/api/workflows/{workflow_id}/events

# Get event log
curl http://localhost:8081/api/workflows/{workflow_id}/events
```

## XES Export

### Export Workflow Log

```bash
# Export as XES XML
curl http://localhost:8081/api/workflows/{workflow_id}/xes

# Export with format options
curl -X POST http://localhost:8081/api/workflows/{workflow_id}/xes/export \
  -H "Content-Type: application/json" \
  -d '{
    "format": "xes",
    "include_system_events": true
  }'
```

## Error Handling

### Error Response Format

All errors follow this format:

```json
{
  "error_code": "workflow_not_found",
  "error_category": "not_found",
  "message": "The specified workflow does not exist",
  "http_status": 404,
  "timestamp": "2024-01-01T10:00:00Z",
  "details": {
    "workflow_id": "invalid_id",
    "suggestion": "Check the workflow ID or create a new workflow"
  }
}
```

### Common Errors

| Error Code | HTTP Status | Description |
|-----------|-------------|-------------|
| `validation_failed` | 400 | Invalid request data |
| `workflow_not_found` | 404 | Workflow doesn't exist |
| `invalid_pattern` | 400 | Pattern type is invalid |
| `allocation_failed` | 500 | No resources available |

## Advanced Examples

### Multi-Instance Workflow

```bash
# Create workflow with multiple instances
curl -X POST http://localhost:8081/api/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "multi_instance",
    "name": "batch_processing",
    "parameters": {
      "num_instances": 5,
      "data": [1, 2, 3, 4, 5]
    }
  }'
```

### Complex Workflow with Options

```bash
# Parallel split with resource allocation
curl -X POST http://localhost:8081/api/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "parallel_split",
    "name": "complex_parallel",
    "description": "Parallel workflow with resource allocation",
    "parameters": {
      "branches": [
        {
          "task": "inventory_check",
          "capabilities": ["inventory"],
          "timeout": 30000
        },
        {
          "task": "credit_check",
          "capabilities": ["credit"],
          "timeout": 30000
        },
        {
          "task": "fraud_check",
          "capabilities": ["fraud"],
          "timeout": 30000
        }
      ]
    },
    "options": {
      "enable_checkpoint": true,
      "checkpoint_interval": 10000,
      "enable_xes": true
    }
  }'
```

### Cancelled Pattern Example

```bash
# Workflow with cancellation
curl -X POST http://localhost:8081/api/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "cancellation_scope",
    "name": "with_timeout",
    "parameters": {
      "timeout": 60000,
      "cancellation_scope": "all"
    }
  }'
```

## Testing with Scripts

### Bash Script Example

```bash
#!/bin/bash
# workflow_test.sh

BASE_URL="http://localhost:8081/api"

echo "Creating workflow..."
RESPONSE=$(curl -s -X POST $BASE_URL/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "sequential",
    "name": "test_workflow"
  }')

WORKFLOW_ID=$(echo $RESPONSE | jq -r '.workflow_id')
echo "Created workflow: $WORKFLOW_ID"

echo "Executing workflow..."
curl -s -X POST $BASE_URL/workflows/$WORKFLOW_ID/execute

echo "Waiting for completion..."
sleep 5

echo "Checking status..."
curl -s $BASE_URL/workflows/$WORKFLOW_ID/status | jq .

echo "Cleaning up..."
curl -s -X DELETE $BASE_URL/workflows/$WORKFLOW_ID
```

### Python Example

```python
import requests
import json

BASE_URL = "http://localhost:8081/api"

# Create workflow
response = requests.post(
    f"{BASE_URL}/workflows",
    json={
        "pattern": "sequential",
        "name": "python_workflow",
        "description": "Created from Python"
    }
)
workflow_id = response.json()["workflow_id"]

# Execute workflow
requests.post(f"{BASE_URL}/workflows/{workflow_id}/execute")

# Check status
status = requests.get(f"{BASE_URL}/workflows/{workflow_id}/status")
print(f"Status: {status.json()}")

# Complete all tasks
tasks = status.json()["tasks"]
for task in tasks:
    if task["status"] == "pending":
        requests.post(
            f"{BASE_URL}/workflows/{workflow_id}/tasks/{task['id']}/complete",
            json={"result": {"status": "completed"}}
        )
```

### Node.js Example

```javascript
const axios = require('axios');

const BASE_URL = 'http://localhost:8081/api';

async function runWorkflow() {
    // Create workflow
    const { data } = await axios.post(`${BASE_URL}/workflows`, {
        pattern: 'parallel_split',
        name: 'nodejs_workflow',
        parameters: { branches: 3 }
    });

    const workflowId = data.workflow_id;
    console.log(`Created workflow: ${workflowId}`);

    // Execute workflow
    await axios.post(`${BASE_URL}/workflows/${workflowId}/execute`);

    // Poll for completion
    let status = 'running';
    while (status === 'running' || status === 'pending') {
        await sleep(1000);
        const { data: statusData } = await axios.get(
            `${BASE_URL}/workflows/${workflowId}/status`
        );
        status = statusData.status;
        console.log(`Status: ${status}, Progress: ${statusData.progress}%`);
    }

    console.log('Workflow completed!');
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

runWorkflow().catch(console.error);
```

## Best Practices

### 1. Always Handle Responses

```bash
# Good: Check response status
curl -w "\n" http://localhost:8081/api/workflows/{id}

# Better: Use jq for pretty output
curl http://localhost:8081/api/workflows/{id} | jq .
```

### 2. Use Timeouts for Long Operations

```bash
# Set timeout for long-running workflows
curl --max-time 300 http://localhost:8081/api/workflows/{id}/execute
```

### 3. Implement Retry Logic

```bash
# Retry with exponential backoff
for i in {1..3}; do
  if curl -f http://localhost:8081/api/workflows/{id}/status; then
    break
  fi
  sleep $((2 ** i))
done
```

### 4. Monitor Events

```bash
# Subscribe to events for real-time updates
curl -N http://localhost:8081/api/workflows/{id}/events/stream
```

---

Next: [Patterns Deep Dive](patterns-deep-dive.md) | [Back to Quick Start](../quickstart.md)
