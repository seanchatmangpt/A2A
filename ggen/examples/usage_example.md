# A2A ggen System Usage Examples

This document provides practical examples of using the ggen-based code generation system.

## Quick Start

### 1. Run the Comprehensive Demo

```bash
# Compile the system
make compile

# Run comprehensive demo
make demo-comprehensive

# Or using the script
./scripts/run_demo.sh demo all
```

### 2. Run Specific Scenarios

```bash
# Basic scenario
make scenario-basic

# Advanced scenario
make scenario-advanced

# Using scripts
./scripts/run_scenario.sh basic
./scripts/run_scenario.sh advanced
```

### 3. Test Generated Code

```bash
# Run all tests
make test

# Test specific scenarios
make test-all-scenarios

# Using script
./scripts/run_demo.sh test all
```

## Generated Code Examples

### Basic Scenario Output

After running `make scenario-basic`, the following files are generated in `generated/basic/`:

```erlang
% a2a_task_worker.erl
-module(a2a_task_worker).
-behaviour(gen_server).

-export([
    start_link/0,
    execute_task/1,
    get_status/0
]).

-record(state, {
    ets_table :: ets:tid() | undefined,
    max_retries :: integer(),
    metrics :: map(),
    stats :: map()
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

execute_task(TaskData) ->
    gen_server:call(?MODULE, execute_task_request(TaskData)).

get_status() ->
    gen_server:call(?MODULE, get_status_request).
```

### Advanced Scenario Output

After running `make scenario-advanced`, complex modules like `a2a_workflow_orchestrator` are generated:

```erlang
% a2a_workflow_orchestrator.erl
-module(a2a_workflow_orchestrator).
-behaviour(gen_statem).

-export([
    start_link/2,
    get_workflow_status/0,
    execute_workflow/0,
    rollback_workflow/0
]).

-record(state, {
    workflow_id :: string(),
    workflow_state :: map(),
    dependency_graph :: digraph(),
    max_retries :: integer(),
    timeout :: integer(),
    hotci_monitor :: pid(),
    hotci_metrics :: map(),
    rollback_timer :: reference()
}).

init(Args) ->
    State = init_state(#state{}, Args),
    {ok, idle, State}.
```

## Cloud Infrastructure Examples

### Dockerfile Generation

```dockerfile
# generated/cloud/Dockerfile
FROM erlang:27-alpine AS builder

RUN apk add --no-cache git make curl
WORKDIR /app
COPY rebar3 /usr/local/bin/
COPY rebar.config config src include /app/
RUN rebar3 compile

FROM erlang:27-alpine
RUN addgroup -g 1001 -S appuser && \
    adduser -S appuser -u 1001
WORKDIR /app
COPY --from=builder --chown=appuser:appuser /app/_build/prod/rel/a2a_erl /app
COPY --from=builder --chown=appuser:appuser /app/config /app/config
RUN chown -R appuser:appuser /app && mkdir -p /app/log /app/data
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
CMD ["/app/bin/a2a_erl", "foreground"]
```

### Kubernetes Deployment

```yaml
# generated/cloud/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: a2a-erl
  namespace: a2a-system
  labels:
    app: a2a-erl
    component: application
spec:
  replicas: 3
  selector:
    matchLabels:
      app: a2a-erl
  template:
    metadata:
      labels:
        app: a2a-erl
        component: application
    spec:
      serviceAccountName: a2a-service-account
      containers:
      - name: a2a-erl
        image: ghcr.io/a2a/a2a_erl:v1.0.0
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
```

## HotCI Integration Examples

### HotCI-Enabled Module

```erlang
% generated/hotci/a2a_hotci_manager.erl
-module(a2a_hotci_manager).
-behaviour(gen_server).

-export([
    start_link/0,
    run_upgrade_test/0,
    run_consistency_check/0,
    trigger_rollback/1
]).

-record(state, {
    test_suites :: map(),
    test_results :: map(),
    upgrade_history :: list(),
    consistency_checks :: list(),
    hotci_monitor :: pid(),
    hotci_metrics :: map()
}).

start_hotci_monitor() ->
    case whereis(hotci_monitor) of
        undefined ->
            {ok, Pid} = a2a_hotci_monitor:start(),
            Pid;
        Pid ->
            Pid
    end.
```

## Configuration Examples

### sys.config

```erlang
% generated/basic/sys.config
{a2a_erl, [
    {http_port, 8080},
    {enable_sse, true},
    {enable_metrics, true},
    {log_level, info},
    {log_dir, "/var/log/a2a_erl"},
    {max_connections, 1000},
    {connection_timeout, 30000}
]}.
```

### rebar3.config

```erlang
% generated/basic/rebar3.config
{deps, [jiffy, cowboy, lager, jsx]}.
{erl_opts, [debug_info, warnings_as_errors]}.
{xref_checks, [undefined_functions, deprecated_functions]}.
{dialyzer_opts, [{warnings, [unmatched_returns, error_handling]}]}.
```

## Testing Examples

### EUnit Tests

```erlang
% Generated test code
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

start_stop_test() ->
    {ok, Pid} = start_link(),
    unlink(Pid),
    exit(Pid, kill),
    ok.

execute_task_test() ->
    {ok, _} = start_link(),
    ?assertEqual(ok, execute_task(#task{id = "test"})),
    ok.
-endif.
```

## Advanced Usage

### Custom Scenario Generation

```erlang
% Define custom module
CustomModule = #{
    module_name => "my_custom_module",
    behaviour_type => "gen_server",
    hotci_enabled => true,
    properties => [
        #{name => "custom_config", type => "string()", default => "default"}
    ],
    exported_functions => [
        #{name => "my_function", args => ["Arg1"]}
    ]
},

% Generate custom module
ggen_generator:generate(erlang, #{
    output_dir => "custom_output/",
    modules => [CustomModule]
}).
```

### Batch Generation

```bash
# Generate multiple scenarios
make generate-all

# Validate all generated code
./scripts/run_demo.sh validate

# Run comprehensive tests
make test-all-scenarios
```

## Performance Considerations

### Generation Speed

- The system generates code at approximately 100 modules per minute
- Memory usage is optimized with streaming generation
- Parallel generation is supported for large projects

### Best Practices

1. **Use scenario-based generation** for consistent results
2. **Validate generated code** before deployment
3. **Use templates** for customization
4. **Leverage HotCI** for safe updates
5. **Monitor performance** of generated systems

## Troubleshooting

### Common Issues

1. **Compilation errors**: Check Erlang syntax in generated modules
2. **Missing dependencies**: Ensure all required packages are installed
3. **Template errors**: Validate template syntax and structure
4. **Configuration issues**: Verify paths and permissions

### Debug Mode

```bash
# Enable verbose output
make demo V=1

# Run with debug logging
./scripts/run_demo.sh demo all 2>&1 | tee demo.log
```

## Next Steps

1. **Explore the generated code** in the `generated/` directory
2. **Customize templates** for your specific needs
3. **Create your own scenarios** using the provided examples
4. **Integrate with your CI/CD pipeline**
5. **Extend with custom generators** for additional languages

---

For more information, see the comprehensive documentation in `docs/README_DEMO.md`.