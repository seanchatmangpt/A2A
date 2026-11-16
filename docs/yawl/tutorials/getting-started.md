# Getting Started with YAWL

This tutorial will have you running your first YAWL workflow in just 5 minutes.

## Prerequisites Check

Before starting, ensure you have:

- Erlang/OTP 25+ installed
- `rebar3` build tool installed
- Git (to clone the repository)

Let's verify:

```bash
# Check Erlang version (should be 25+)
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell

# Check rebar3
rebar3 version
```

## Step 1: Clone and Build (2 minutes)

```bash
# Navigate to project and build
cd /Users/sac/A2A/erlang/a2a_erl

# Install dependencies
rebar3 deps

# Build the project
rebar3 compile

# Run tests to verify
rebar3 ct
```

Expected output: Tests should pass with all pattern demonstrations successful.

## Step 2: Start YAWL Server (1 minute)

```bash
# Start the YAWL server in the background
rebar3 shell &
YAWL_PID=$!

# Verify the server is running
sleep 2
curl -s http://localhost:8081/health | jq .
```

Expected response:
```json
{"status":"ok","service":"yawl","version":"1.0.0"}
```

## Step 3: Create Your First Workflow (1 minute)

Let's create a simple sequential workflow:

```bash
curl -X POST http://localhost:8081/api/workflows \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "sequential",
    "name": "my-first-workflow",
    "description": "A simple sequential workflow demo"
  }'
```

Expected response:
```json
{
  "workflow_id": "seq_12345",
  "status": "created",
  "message": "Workflow created successfully"
}
```

## Step 4: Execute the Workflow (1 minute)

```bash
# Execute the workflow (replace seq_12345 with your workflow_id)
curl -X POST http://localhost:8081/api/workflows/seq_12345/execute
```

Expected response:
```json
{
  "workflow_id": "seq_12345",
  "status": "running",
  "message": "Workflow execution started"
}
```

## Step 5: Check Workflow Status

```bash
# Get workflow status
curl http://localhost:8081/api/workflows/seq_12345/status
```

Expected response:
```json
{
  "workflow_id": "seq_12345",
  "status": "running",
  "current_step": "task_1",
  "progress": 33,
  "created_at": "2024-01-01T10:00:00Z",
  "updated_at": "2024-01-01T10:00:30Z"
}
```

## Step 6: Complete a Task

```bash
# Complete the first task
curl -X POST http://localhost:8081/api/workflows/seq_12345/tasks/task_1/complete \
  -H "Content-Type: application/json" \
  -d '{
    "result": {
      "status": "completed",
      "output": "Task 1 completed successfully"
    }
  }'
```

## Step 7: Explore Available Patterns

```bash
# List all available patterns
curl http://localhost:8081/api/patterns
```

This will show all 43 YAWL patterns available:
- Basic: sequence, parallel_split, exclusive_choice, simple_merge
- Advanced: interleaved, deferred_choice, milestone
- Cancellation: 18 different cancellation patterns
- Resource: 6 resource allocation patterns
- Time-based: 4 timing patterns

## Step 8: Clean Up

```bash
# Stop the YAWL server
kill $YAWL_PID

# Or stop from Erlang shell
rebar3 shell
> q().
```

## What We Accomplished

Congratulations! In just 5 minutes you:

1. Verified your Erlang environment
2. Built the YAWL system
3. Started the YAWL server
4. Created your first workflow
5. Executed a workflow
6. Completed a task
7. Explored available patterns

## Next Steps

Now that you have YAWL running:

1. **Learn Patterns**: Explore the [43 YAWL patterns](../patterns/)
2. **Try Complex Workflows**: Create parallel and choice-based workflows
3. **Business Examples**: See real-world examples in [business/](../business/)
4. **REST API**: Learn the complete API in [api/](../api/)
5. **Erlang Development**: Build custom workflows in Erlang

## Common Issues

### Port Already in Use

```bash
# Check what's using port 8081
lsof -i :8081

# Kill the process or change port in config
```

### Dependencies Not Found

```bash
# Clean and rebuild
rebar3 clean
rebar3 deps
rebar3 compile
```

### Tests Fail

```bash
# Check test logs
rebar3 ct --verbose
```

---

Continue to: [Erlang Introduction](tutorials/erlang-intro.md) | [Architecture](../architecture.md)
