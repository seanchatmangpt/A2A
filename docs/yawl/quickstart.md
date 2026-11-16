# Quick Start: YAWL in 5 Minutes

This guide will get you up and running with the A2A YAWL implementation in just 5 minutes.

## Prerequisites

- Erlang/OTP 25+ installed
- `rebar3` build tool
- Git (to clone the repository)

## Step 1: Clone and Setup

```bash
# Clone the repository
git clone https://github.com/your-org/a2a.git
cd a2a

# Navigate to the Erlang component
cd erlang/a2a_erl

# Install dependencies
rebar3 deps

# Build the project
rebar3 compile
```

## Step 2: Start YAWL Server

```bash
# Start the YAWL system in the background
rebar3 shell start > yawl.log 2>&1 &
YAWL_PID=$!

# Verify the server is running
sleep 2
curl -s http://localhost:8081/health | jq .
```

## Step 3: Create Your First Workflow

```bash
# Create a sequential workflow
curl -X POST http://localhost:8081/api/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "sequential",
    "name": "my-first-workflow",
    "description": "A simple sequential workflow"
  }'

# Response:
# {
#   "workflow_id": "seq_12345",
#   "status": "created",
#   "message": "Workflow created successfully"
# }
```

## Step 4: Execute the Workflow

```bash
# Execute the workflow
curl -X POST http://localhost:8081/api/workflows/seq_12345/execute

# Response:
# {
#   "workflow_id": "seq_12345",
#   "status": "running",
#   "message": "Workflow execution started"
# }
```

## Step 5: Check Workflow Status

```bash
# Get workflow status
curl http://localhost:8081/api/workflows/seq_12345/status

# Response:
# {
#   "workflow_id": "seq_12345",
#   "status": "running",
#   "current_step": "task_1",
#   "progress": 33,
#   "created_at": "2024-01-01T10:00:00Z",
#   "updated_at": "2024-01-01T10:00:30Z"
# }
```

## Step 6: Complete a Task

```bash
# Complete the current task
curl -X POST http://localhost:8081/api/workflows/seq_12345/tasks/task_1/complete \
  -H "Content-Type: application/json" \
  -d '{
    "result": {
      "status": "completed",
      "output": "Task completed successfully"
    }
  }'

# Response:
# {
#   "workflow_id": "seq_12345",
#   "status": "running",
#   "current_step": "task_2",
#   "progress": 66
# }
```

## Step 7: View Available Patterns

```bash
# List all available patterns
curl http://localhost:8081/api/patterns

# Response will include all 43 patterns:
# {
#   "patterns": [
#     {"id": "sequential", "name": "Sequence", "category": "basic"},
#     {"id": "parallel", "name": "Parallel Split", "category": "basic"},
#     {"id": "exclusive_choice", "name": "Exclusive Choice", "category": "basic"},
#     ...
#   ]
# }
```

## Step 8: Clean Up

```bash
# Stop the YAWL server
kill $YAWL_PID

# Wait for graceful shutdown
wait $YAWL_PID 2>/dev/null
```

## 9. Erlang API Examples

For those who prefer direct Erlang API usage:

### Start the Erlang Shell

```bash
# Start the Erlang shell with the YAWL application
rebar3 shell
```

### Create and Execute a Workflow

```erlang
% In the Erlang shell
1> Config = #{pattern => "sequential",
             name => "my-erlang-workflow",
             description => "Sequential workflow via Erlang API"}.
2> {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config).
3> {ok, _Instance} = yawl_orchestrator:execute_workflow(WorkflowId).
4> {ok, Status} = yawl_orchestrator:get_status(WorkflowId).
5> io:format("Workflow status: ~p~n", [Status]).
```

## Next Steps

Congratulations! You've successfully:

1. ✅ Installed and started YAWL
2. ✅ Created your first workflow via REST API
3. ✅ Executed the workflow
4. ✅ Completed tasks
5. ✅ Listed available patterns
6. ✅ Seen both REST API and Erlang API examples

### What's Next?

- **Learn Patterns**: Explore the [43 YAWL patterns](patterns/)
- **Business Workflows**: See real-world examples in [business/](business/)
- **REST API**: Complete API reference in [api/](api/)
- **Erlang Development**: Learn to create custom workflows in [tutorials/](tutorials/)

## Common Issues

### Port Already in Use
```bash
# Check if port 8081 is already in use
lsof -i :8081

# If needed, change the port in config/app.config
```

### Dependencies Not Found
```bash
# Clean and reinstall dependencies
rebar3 clean
rebar3 deps
rebar3 compile
```

### Workflow Stuck
```bash
# Check workflow logs
tail -f yawl.log

# Check workflow details
curl http://localhost:8081/api/workflows/{id}/details
```

---

Need more help? Check the [full documentation](index.md) or explore the [tutorials](tutorials/).

