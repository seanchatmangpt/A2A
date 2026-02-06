# YAWL Erlang SDK API Reference

## Overview

The YAWL (Yet Another Workflow Language) Erlang SDK provides a complete implementation of all 43 YAWL workflow patterns using Petri net technology. This API reference covers the core modules and their functions for workflow orchestration, persistence, logging, and error handling.

## Core Modules

### `yawl_orchestrator` - Main Workflow Orchestrator

The central module for managing YAWL workflow instances.

#### API Functions

##### Workflow Management

```erlang
%% Create a new workflow
-spec create_workflow(PatternType, Config) -> {ok, WorkflowId} | {error, Reason}
```

Creates a new workflow with the specified pattern type and configuration.

**Parameters:**
- `PatternType` - The YAWL pattern type (e.g., `basic_sequential`, `parallel_split`)
- `Config` - Configuration map with workflow parameters

**Returns:**
- `{ok, WorkflowId}` - Unique workflow identifier
- `{error, Reason}` - Error if pattern validation fails

**Example:**
```erlang
Config = #{timeout => 30000, max_retries => 3},
{ok, WorkflowId} = yawl_orchestrator:create_workflow(parallel_split, Config).
```

##### Workflow Execution

```erlang
%% Execute a workflow
-spec execute_workflow(WorkflowId) -> {ok, Status} | {error, Reason}
```

Starts or continues execution of a workflow.

**Parameters:**
- `WorkflowId` - The workflow identifier

**Returns:**
- `{ok, #{status => running, instance => InstancePid}}` - Workflow is running
- `{error, workflow_not_found}` - Workflow doesn't exist

**Example:**
```erlang
{ok, Status} = yawl_orchestrator:execute_workflow(WorkflowId),
case Status of
    #{status := running, instance := Pid} ->
        io:format("Workflow running with PID: ~p~n", [Pid])
end.
```

##### Pattern Validation

```erlang
%% Validate pattern configuration
-spec validate_pattern(PatternType, Config) -> {ok, Valid} | {error, Reason}
```

Validates if the configuration is compatible with the specified pattern type.

**Parameters:**
- `PatternType` - The YAWL pattern type
- `Config` - Configuration map

**Returns:**
- `{ok, true}` - Configuration is valid
- `{ok, false}` - Configuration is invalid
- `{error, Reason}` - Validation error

##### Workflow Status and Monitoring

```erlang
%% Get workflow status
-spec get_status(WorkflowId) -> {ok, Status} | {error, workflow_not_found}

%% List all available patterns
-spec list_patterns() -> [PatternType]

%% List all workflows
-spec list_workflows() -> {ok, [WorkflowId]}

%% Get workflow execution result
-spec get_workflow_result(WorkflowId) -> {ok, Result} | {error, workflow_not_completed}
```

##### Workflow Control

```erlang
%% Pause a running workflow
-spec pause_workflow(WorkflowId) -> {ok, ok} | {error, Reason}

%% Resume a paused workflow
-spec resume_workflow(WorkflowId) -> {ok, ok} | {error, Reason}

%% Cancel a workflow
-spec cancel_workflow(WorkflowId) -> {ok, ok} | {error, workflow_not_found}

%% Cleanup completed workflow
-spec cleanup_workflow(WorkflowId) -> {ok, ok} | {error, workflow_not_found}
```

##### Work Item Management

```erlang
%% Complete a work item
-spec complete_workitem(WorkflowId, TaskId, Result) -> ok | {error, Reason}

%% Get workflow instance PID
-spec get_workflow_instance(WorkflowId) -> {ok, InstancePid} | {error, workflow_instance_not_found}
```

##### Subscription Management

```erlang
%% Subscribe to workflow events
-spec subscribe_to_workflow(WorkflowId, SubscriberPid) -> {ok, ok} | {error, workflow_not_found}

%% Unsubscribe from workflow events
-spec unsubscribe_from_workflow(WorkflowId, SubscriberPid) -> {ok, ok} | {error, Reason}
```

#### Pattern Information

```erlang
%% Get detailed pattern information
-spec get_pattern_info(PatternType) -> {ok, PatternInfo} | {error, pattern_not_found}
```

Returns detailed information about a pattern including complexity, required parameters, and structure.

**Pattern Info Structure:**
```erlang
#{name => <<"Pattern Name">>,
  complexity => low | medium | high,
  places => [PlaceName],
  transitions => [TransitionName],
  required_params => [ParamName],
  optional_params => [ParamName]}
```

### `yawl_xes_logger` - XES Event Logging

Implements IEEE 1849-2016 XES standard for workflow event logging.

#### Log Lifecycle Management

```erlang
%% Start the logger
-spec start_link() -> {ok, pid()} | {error, term()}
-spec start_link(Name) -> {ok, pid()} | {error, term()}

%% Stop the logger
-spec stop() -> ok

%% Create a new log
-spec new_log() -> {ok, LogId}
-spec new_log(Metadata) -> {ok, LogId}

%% Get log by ID
-spec get_log(LogId) -> {ok, Log} | {error, not_found}

%% List all logs
-spec list_logs() -> [{LogId, Log}]

%% Delete a log
-spec delete_log(LogId) -> ok | {error, not_found}
```

#### Pattern Event Logging

```erlang
%% Log pattern execution start
-spec log_pattern_start(LogId, PatternType, PatternId) -> ok

%% Log pattern execution completion
-spec log_pattern_complete(LogId, PatternType, PatternId, Result) -> ok
```

#### Work Item Logging

```erlang
%% Log work item start
-spec log_workitem_start(LogId, WorkitemId, TaskId) -> ok

%% Log work item completion
-spec log_workitem_complete(LogId, WorkitemId, TaskId, Result) -> ok
```

#### Case Logging

```erlang
%% Log case start
-spec log_case_start(LogId, CaseId) -> ok

%% Log case completion
-spec log_case_complete(LogId, CaseId, Stats) -> ok
```

#### Generic Event Logging

```erlang
%% Log a generic event
-spec log_event(LogId, ConceptName, LifecycleTransition, Data) -> ok
-spec log_event(LogId, ConceptName, LifecycleTransition, Data, CaseId) -> ok
```

#### XES Export

```erlang
%% Export log to XES XML file
-spec export_xes(LogId) -> {ok, FilePath} | {error, Reason}
-spec export_xes(LogId, OutputDir) -> {ok, FilePath} | {error, Reason}

%% Export log as XES string
-spec export_xes_to_string(LogId) -> {ok, XESString} | {error, Reason}
```

### `yawl_error_codes` - Error Handling

Centralized error code registry for consistent error reporting.

#### Error Information

```erlang
%% Get error details
-spec error_info(ErrorCode) -> ErrorInfo

%% Get error code atom
-spec error_code(ErrorCode) -> ErrorCode

%% Get HTTP status code
-spec http_status(ErrorCode) -> pos_integer()

%% Get error message
-spec error_message(ErrorCode) -> binary()

%% Get error category
-spec error_category(ErrorCode) -> error_category()
```

#### Error Formatting

```erlang
%% Format error as map
-spec format_error(ErrorCode) -> map()
-spec format_error(ErrorCode, Details) -> map()
-spec format_error(ErrorCode, CustomMessage, Details) -> map()
```

#### Error Management

```erlang
%% Get all error codes
-spec all_error_codes() -> [error_code()]

%% Get errors by category
-spec errors_by_category(Category) -> [error_code()]

%% Check error type
-spec is_client_error(ErrorCode) -> boolean()
-spec is_server_error(ErrorCode) -> boolean()
```

#### Error Categories

- **validation** (400) - Request validation errors
- **authentication** (401) - Authentication failures
- **authorization** (403) - Permission failures
- **not_found** (404) - Resource not found
- **conflict** (409) - Resource conflict
- **rate_limit** (429) - Rate limiting
- **server_error** (500) - Internal server errors
- **service_unavailable** (503) - Service unavailable

### `yawl_persistence` - Data Persistence

Mnesia-based persistence layer for workflow data.

#### Database Management

```erlang
%% Create Mnesia schema
-spec create_schema() -> ok | {error, term()}

%% Create all tables
-spec create_tables() -> ok | {error, term()}

%% Wait for tables to be ready
-spec wait_for_tables() -> ok | {timeout, [atom()]} | {error, term()}

%% Backup tables to file
-spec backup_tables(Destination) -> ok | {error, term()}
```

#### Workflow Persistence

```erlang
%% Save workflow state
-spec save_workflow(Workflow) -> ok | {error, Reason}

%% Load workflow state
-spec load_workflow(WorkflowId) -> {ok, Workflow} | {error, Reason}

%% Delete workflow
-spec delete_workflow(WorkflowId) -> ok | {error, Reason}

%% Archive workflow
-spec archive_workflow(WorkflowId) -> ok | {error, Reason}

%% List workflows
-spec list_workflows() -> {ok, [Workflow]}
-spec list_workflows_by_status(Status) -> {ok, [Workflow]}
```

#### Work Item Persistence

```erlang
%% Save work item
-spec save_workitem(Workitem) -> ok | {error, Reason}

%% Load work item
-spec load_workitem(WorkitemId) -> {ok, Workitem} | {error, Reason}

%% Delete work item
-spec delete_workitem(WorkitemId) -> ok | {error, Reason}

%% List work items for workflow
-spec list_workitems(WorkflowId) -> {ok, [Workitem]}

%% Update work item status
-spec update_workitem_status(WorkitemId, Status) -> ok | {error, Reason}
```

#### Resource Persistence

```erlang
%% Save resource
-spec save_resource(Resource) -> ok | {error, Reason}

%% Load resource
-spec load_resource(ResourceId) -> {ok, Resource} | {error, Reason}

%% Delete resource
-spec delete_resource(ResourceId) -> ok | {error, Reason}

%% List resources
-spec list_resources() -> {ok, [Resource]}
-spec list_resources_by_type(Type) -> {ok, [Resource]}
-spec list_available_resources() -> {ok, [Resource]}
```

#### Checkpoint and Recovery

```erlang
%% Save checkpoint
-spec save_checkpoint(WorkflowId, Checkpoint) -> ok | {error, Reason}

%% Load latest checkpoint
-spec load_latest_checkpoint(WorkflowId) -> {ok, Checkpoint} | {error, not_found}

%% List checkpoints
-spec list_checkpoints(WorkflowId) -> {ok, [Checkpoint]}

%% Delete checkpoint
-spec delete_checkpoint(CheckpointId) -> ok | {error, Reason}

%% Restore from checkpoint
-spec restore_from_checkpoint(WorkflowId) -> {ok, Checkpoint} | {error, Reason}

%% Rollback to checkpoint
-spec rollback_to_checkpoint(WorkflowId, CheckpointId) -> ok | {error, Reason}

%% List recovery points
-spec list_recovery_points(WorkflowId) -> {ok, [map()]} | {error, Reason}

%% Validate checkpoint integrity
-spec validate_checkpoint_integrity(CheckpointId) -> {ok, Valid, Details} | {error, Reason}

%% Cleanup old checkpoints
-spec cleanup_old_checkpoints(WorkflowId, KeepCount) -> {ok, DeletedCount} | {error, Reason}
```

#### Periodic Checkpoints

```erlang
%% Enable periodic checkpoints
-spec enable_periodic_checkpoints(IntervalMs) -> ok | {error, term()}

%% Disable periodic checkpoints
-spec disable_periodic_checkpoints() -> ok

%% Set checkpoint interval
-spec set_checkpoint_interval(IntervalMs) -> ok
```

### `yawl_cpn` - Colored Petri Nets

Advanced CPN support with Python integration.

#### Color Set Management

```erlang
%% Create color set
-spec create_color_set(Name, Type) -> local_color_set()
-spec create_color_set(Name, TypeSpec) -> local_color_set()
```

#### Token Management

```erlang
%% Create timed token
-spec create_timed_token(Data, Timestamp) -> local_colored_token()

%% Get token colors at place
-spec get_token_colors(NetMod, Place) -> [local_colored_token()]
```

#### Transition Firing

```erlang
%% Fire transition with colored tokens
-spec fire_transition_with_color(NetMod, Transition, Marking) -> {ok, NewMarking} | {error, Reason}

%% Evaluate guard expression
-spec evaluate_guard(Guard, Marking) -> boolean()
```

#### JSON Export/Import

```erlang
%% Export workflow to JSON
-spec export_workflow_json(NetMod) -> map()

%% Import workflow from JSON
-spec import_workflow_json(JSON) -> {ok, NetMod} | {error, Reason}

%% Convert to CPN JSON
-spec workflow_to_cpn_json(NetMod) -> binary()

%% Convert CPN JSON to workflow
-spec cpn_json_to_workflow(JSON) -> map()
```

#### Python Bridge

```erlang
%% Call PM4Py function
-spec call_pm4py(Function, Args) -> {ok, Result} | {error, Reason}

%% Process discovery
-spec process_discovery(XESLog) -> {ok, Model} | {error, Reason}

%% Trace alignment
-spec align_traces(XESLog, Model) -> {ok, Result} | {error, Reason}

%% Stochastic replay
-spec stochastic_replay(XESLog, Model) -> {ok, Result} | {error, Reason}
```

#### LLM Integration

```erlang
%% Format workflow for LLM consumption
-spec llm_format_workflow(NetMod) -> binary()

%% Parse LLM-generated workflow
-spec parse_llm_workflow(JSON) -> {ok, Workflow} | {error, Reason}

%% Validate CPN JSON
-spec validate_cpn_json(JSON) -> {ok, JSON} | {error, Reason}
```

## Data Types

### Workflow Types

```erlang
-record(yawl_workflow, {
    workflow_id :: binary(),
    pattern_type :: atom(),
    status :: pending | running | paused | completed | cancelled | failed,
    config :: map(),
    marking :: map(),
    current_place :: atom() | undefined,
    start_time :: integer(),
    end_time :: integer() | undefined,
    metadata :: map()
}).

-record(yawl_workflow_config, {
    pattern_type :: atom(),
    parameters :: map(),
    timeout :: integer(),
    retry_policy :: map()
}).
```

### Persistence Records

```erlang
-record(yawl_workflow_persist, {
    workflow_id :: binary(),
    spec_id :: binary(),
    pattern_type :: atom(),
    status :: atom(),
    marking :: map(),
    current_place :: atom() | undefined,
    data :: map(),
    parent_workflow_id :: binary() | undefined,
    created_at :: integer(),
    updated_at :: integer(),
    completed_at :: integer() | undefined,
    error :: term() | undefined
}).

-record(yawl_workitem_persist, {
    workitem_id :: binary(),
    workflow_id :: binary(),
    task_id :: binary(),
    task_name :: binary(),
    status :: atom(),
    data :: map(),
    allocated_to :: binary() | undefined,
    allocation_time :: integer() | undefined,
    start_time :: integer() | undefined,
    completion_time :: integer() | undefined,
    error :: term() | undefined,
    retry_count :: integer(),
    priority :: atom()
}).
```

### XES Types

```erlang
-record(xes_log, {
    log_id :: binary(),
    trace_id :: binary(),
    started_at :: integer(),
    events :: list(),
    metadata :: map()
}).

-record(xes_event, {
    event_id :: binary(),
    timestamp :: integer(),
    case_id :: binary() | undefined,
    concept :: map(),
    lifecycle :: map(),
    data :: map()
}).
```

## Error Handling

All API functions return `{ok, Result}` or `{error, Reason}` tuples. Use `yawl_error_codes` to get detailed error information:

```erlang
case yawl_orchestrator:create_workflow(invalid_pattern, #{}) of
    {error, Reason} ->
        ErrorInfo = yawl_error_codes:error_info(Reason),
        io:format("Error: ~s~n", [maps:get(message, ErrorInfo)])
end.
```

## Configuration

### Application Environment

```erlang
%% Default configuration
[
    {yawl, [
        {max_concurrent_workflows, 100},
        {default_timeout, 30000},
        {enable_metrics, true},
        {enable_logging, true},
        {xes_output_dir, "xes_logs"},
        {checkpoint_interval, 60000}
    ]}
].
```

### Pattern Configuration Examples

```erlang
%% Parallel Split
ParallelConfig = #{
    branches => 4,
    timeout => 30000,
    retry_policy => #{max_retries => 3, delay => 1000}
}.

%% Exclusive Choice
ChoiceConfig = #{
    conditions => [
        fun(X) -> X > 0 end,
        fun(X) -> X < 100 end
    ],
    default_branch => 1
}.

%% Multi-Instance
MultiInstanceConfig = #{
    num_instances => 5,
    data => [{id, 1}, {id, 2}, {id, 3}],
    parallel => true,
    completion_condition => fun(Instances) -> length(Instances) >= 3 end
}.
```

## Usage Examples

### Basic Workflow Creation

```erlang
%% Start the orchestrator
{ok, _} = yawl_orchestrator:start_link().

%% Create workflow
Config = #{timeout => 30000, priority => normal},
{ok, WorkflowId} = yawl_orchestrator:create_workflow(parallel_split, Config).

%% Execute workflow
{ok, Status} = yawl_orchestrator:execute_workflow(WorkflowId).

%% Monitor completion
timer:sleep(5000),
case yawl_orchestrator:get_status(WorkflowId) of
    {ok, completed} ->
        {ok, Result} = yawl_orchestrator:get_workflow_result(WorkflowId);
    {ok, Status} ->
        io:format("Status: ~p~n", [Status])
end.
```

### Event Logging Integration

```erlang
%% Start XES logger
{ok, _} = yawl_xes_logger:start_link().

%% Create log for workflow
{ok, LogId} = yawl_xes_logger:new_log(#{workflow_id => WorkflowId}).

%% Log workflow events
yawl_xes_logger:log_pattern_start(LogId, parallel_split, WorkflowId).
yawl_xes_logger:log_workitem_start(LogId, WorkitemId, TaskId).

%% Export to XES file
{ok, XesFile} = yawl_xes_logger:export_xes(LogId, "/path/to/logs").
```

### Persistence and Recovery

```erlang
%% Enable periodic checkpoints
yawl_persistence:enable_periodic_checkpoints(30000).

%% Manual checkpoint
Checkpoint = #{marking => Marking, data => Data, timestamp => erlang:monotonic_time()},
yawl_persistence:save_checkpoint(WorkflowId, Checkpoint).

%% Restore from checkpoint
case yawl_persistence:restore_from_checkpoint(WorkflowId) of
    {ok, Checkpoint} ->
        io:format("Restored from checkpoint: ~p~n", [Checkpoint]);
    {error, Reason} ->
        io:format("Restore failed: ~p~n", [Reason])
end.
```

## Performance Considerations

1. **Pattern Caching**: Frequently accessed patterns are cached in memory
2. **Batch Operations**: Use bulk operations for multiple workflows
3. **Checkpoint Strategy**: Balance frequency vs. performance impact
4. **Connection Pooling**: Reuse database connections for better performance
5. **Async Operations**: Use `gen_server:cast` for non-critical operations

## Testing

Run the comprehensive test suite:

```erlang
%% Unit tests
rebar3 eunit --module yawl_orchestrator
rebar3 eunit --module yawl_xes_logger
rebar3 eunit --module yawl_error_codes
rebar3 eunit --module yawl_persistence
rebar3 eunit --module yawl_cpn

%% Integration tests
rebar3 ct
```

## Best Practices

1. **Error Handling**: Always check return values and handle errors appropriately
2. **Resource Management**: Clean up completed workflows with `cleanup_workflow/1`
3. **Monitoring**: Use event logging for audit trails and debugging
4. **Configuration**: Validate patterns before creating workflows
5. **Security**: Validate all input parameters to prevent injection attacks
6. **Performance**: Monitor workflow metrics and optimize as needed