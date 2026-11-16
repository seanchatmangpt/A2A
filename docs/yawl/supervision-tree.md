# YAWL Supervision Tree Implementation

## Overview

This document describes the OTP supervision tree implementation for the YAWL (Yet Another Workflow Language) workflow engine in the A2A project.

## Supervision Hierarchy

```
a2a_erl_sup (one_for_one, intensity=10, period=60)
│
├── Core Infrastructure Services
│   ├── yawl_persistence (worker)           - Mnesia-based workflow storage
│   └── a2a_task_store (worker)             - ETS-backed task storage
│
├── YAWL Core Services
│   ├── yawl_events (worker)                - Observer pattern for workflow events
│   ├── yawl_service_registry (worker)       - Service discovery and registration
│   ├── yawl_resource_manager (worker)       - Dynamic resource allocation
│   ├── yawl_orchestrator (worker)           - Workflow lifecycle management
│   ├── yawl_metrics (worker)                - Metrics collection
│   └── yawl_error_recovery (worker)         - Error recovery strategies
│
├── YAWL Supporting Services
│   ├── yawl_human_task (worker)             - Human-in-the-loop tasks
│   └── yawl_workitem_processor (worker)     - Work item processing
│
├── A2A Integration Services
│   ├── a2a_agent_card (worker)              - Agent card management
│   ├── yawl_a2a_bridge (worker)             - YAWL-A2A protocol bridge
│   ├── yawl_a2a_events (worker)             - A2A event notifications
│   ├── yawl_a2a_resource_integration (worker) - Resource integration
│   └── y_combinator_logger (worker)         - Demo logging and telemetry
│
└── Dynamic Supervisors (simple_one_for_one)
    ├── yawl_workflow_instance_sup           - Workflow instances
    │   └── [workflow_instance_1, workflow_instance_2, ...]
    │
    └── a2a_task_sup                         - A2A task state machines
        └── [task_state_1, task_state_2, ...]
```

## Restart Strategies

### Top-Level Supervisor (a2a_erl_sup)
- **Strategy**: `one_for_one`
- **Intensity**: 10 restarts
- **Period**: 60 seconds

If a child process terminates, only that process is restarted. This is appropriate for the YAWL supervision tree where components are largely independent and can recover independently.

### Dynamic Supervisors
- **Strategy**: `simple_one_for_one`
- **Intensity**: 10 restarts
- **Period**: 60 seconds

Used for workflow instances and task state machines where children are added dynamically.

## Module Files

### Core Modules

| Module | Type | Purpose |
|--------|------|---------|
| `a2a_erl_app.erl` | Application | Application startup/shutdown, Mnesia initialization |
| `a2a_erl_sup.erl` | Supervisor | Top-level supervision tree |
| `yawl_events.erl` | gen_server | Observer pattern for workflow events |
| `yawl_orchestrator.erl` | gen_server | Workflow lifecycle management |
| `yawl_persistence.erl` | gen_server | Mnesia-based persistence |
| `yawl_resource_manager.erl` | gen_server | Resource allocation |
| `yawl_workflow_instance_sup.erl` | Supervisor | Dynamic workflow instances |
| `yawl_workflow_instance.erl` | gen_statem | Workflow instance state machine |

## Application Startup Sequence

1. **Mnesia Initialization**
   - Schema is created if it doesn't exist
   - Mnesia is started
   - Tables are created by `yawl_persistence` during init

2. **Supervisor Start**
   - Top-level supervisor starts with `one_for_one` strategy
   - Core services start in order
   - Dynamic supervisors initialize with empty child lists

3. **Service Registration**
   - Services register with `yawl_service_registry`
   - Resources register with `yawl_resource_manager`
   - Event subscribers can register with `yawl_events`

4. **HTTP Server Start**
   - Cowboy HTTP listener starts
   - REST API endpoints become available

## Mnesia Schema

### Tables Created

| Table | Type | Purpose |
|-------|------|---------|
| `yawl_workflow_persist` | set | Workflow state persistence |
| `yawl_workitem_persist` | set | Work item state |
| `yawl_resource_persist` | set | Resource registration |
| `yawl_execution_history` | bag | Event history |
| `yawl_checkpoint` | set | Recovery checkpoints |
| `yawl_service_registry` | set | Service registration |
| `yawl_task_queue` | bag | Human task queue |

### Table Storage

- **disc_copies**: Workflow, workitem, resource, service registry, task queue
- **disc_only_copies**: Checkpoints (large data, infrequent access)
- **ram_copies**: None (all data is persisted)

## Process Monitoring

All gen_servers and gen_statems monitor their child processes using `erlang:monitor(process, Pid)`. When a monitored process exits:

1. A `{'DOWN', MonitorRef, process, Pid, Info}` message is received
2. The supervisor's restart strategy determines the response
3. For `one_for_one`, only the terminated child is restarted
4. For `simple_one_for_one`, dynamic children can be restarted individually

## Event System

The `yawl_events` module implements the Observer pattern:

- **Subscribe**: Processes can subscribe to specific event types
- **Emit**: Services emit events for significant occurrences
- **History**: Events are stored in memory and optionally persisted

### Event Types

| Event | Description |
|-------|-------------|
| `workflow_created` | New workflow definition created |
| `workflow_started` | Workflow execution started |
| `workflow_completed` | Workflow finished successfully |
| `workflow_failed` | Workflow failed with error |
| `workflow_cancelled` | Workflow was cancelled |
| `task_started` | Task within workflow started |
| `task_completed` | Task completed successfully |
| `checkpoint_created` | Recovery checkpoint created |
| `resource_allocated` | Resource allocated to work item |
| `resource_released` | Resource released from work item |

## Graceful Shutdown

On application stop:

1. HTTP listener stops accepting new connections
2. Running requests are allowed to complete (timeout: 5000ms)
3. Supervisors terminate children in reverse order
4. Mnesia is stopped by the persistence supervisor
5. All in-memory data is flushed to disk

## Testing

Unit tests are provided in `tests/unit/yawl_supervision_tests.erl`:

```erlang
%% Run all supervision tests
erl -pa ebin -eval "eunit:test(yawl_supervision_tests, [verbose])"
```

### Test Coverage

- Supervisor starts all children correctly
- Proper restart strategies (one_for_one, simple_one_for_one)
- All core YAWL services are running
- YAWL events module is available
- Workflow instances can be started dynamically
- Process monitoring handles DOWN messages
- Restart intensity and period are configured
- Mnesia tables are created
- Supervision tree structure matches specification

## Error Handling

### Restart Intensity

If more than 10 restarts occur within 60 seconds for a child:
- The supervisor shuts down all children
- The application terminates
- Manual intervention is required to restart

### Permanent vs Temporary

- **permanent** processes are always restarted (core services)
- **temporary** processes are not restarted on normal exit (workflow instances)
- **transient** processes are restarted only on abnormal exit

## Configuration

Application environment variables (can be set in `sys.config`):

```erlang
{a2a_erl, [
    {port, 8080},                          % HTTP port
    {mnesia_dir, "data/mnesia"},           % Mnesia data directory
    {max_history_size, 10000},             % Event history size
    {checkpoint_interval, 60000},          % Checkpoint interval (ms)
    {max_concurrent_workflows, 100}        % Max concurrent workflows
]}.
```

## Deployment

### Development

```bash
cd erlang/a2a_erl
rebar3 shell
```

### Production

```bash
rebar3 release
rel/a2a_erl/bin/a2a_erl start
```

## Troubleshooting

### Mnesia Won't Start

1. Check if another node is using the schema: `erl -sname debug -mnesia dir:"\"/path/to/mnesia\""`
2. Delete the schema and restart: `rm -rf Mnesia.*`
3. Ensure proper permissions on the Mnesia directory

### Supervisor Restarts Looping

1. Check logs for error messages
2. Verify configuration is correct
3. Ensure dependencies (Mnesia, ports) are available
4. Check system resources (memory, file descriptors)

### Workflow Instances Not Starting

1. Verify `yawl_workflow_instance_sup` is running
2. Check Mnesia tables are accessible
3. Review `yawl_orchestrator` logs for errors
4. Ensure workflow definition is valid
