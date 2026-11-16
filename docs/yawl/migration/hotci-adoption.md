# HotCI Adoption Guide

This guide explains how to adopt HotCI for continuous integration testing of YAWL workflows.

## Overview

HotCI is a lightweight, high-performance testing framework for Erlang/OTP applications. It provides:
- Fast test execution with parallel test runners
- Built-in coverage reporting
- Property-based testing integration
- Test discovery and organization
- CI/CD integration

## Installation

### Adding HotCI to Your Project

Add HotCI to your `rebar.config`:

```erlang
{deps, [
    {hotci, {git, "https://github.com/hotci/hotci.git", {branch, "main"}}}
]}.
```

For production YAWL deployments, HotCI is included as a submodule in `vendors/HotCI`.

## HotCI Configuration

### hotci.config

Create a `hotci.config` file in your project root:

```erlang
%% HotCI Configuration for YAWL
{hotci, [
    %% Test directories
    {test_dirs, [
        "tests/unit",
        "tests/integration",
        "tests/property"
    ]},

    %% Parallel execution
    {parallel, true},
    {max_parallel, 4},

    %% Coverage
    {coverage, true},
    {coverage_threshold, 80},
    {coverage_apps, [a2a_erl]},

    %% Test patterns
    {include_patterns, ["*_tests.erl", "*_SUITE.erl"]},
    {exclude_patterns, ["*_disabled_tests.erl"]},

    %% Output
    {verbose, true},
    {output_dir, "_build/test/hotci"},

    %% Pre-test hooks
    {pre_test_hooks, [
        {shell, "scripts/pre-test.sh"}
    ]},

    %% Post-test hooks
    {post_test_hooks, [
        {shell, "scripts/post-test.sh"}
    ]}
]}.
```

### Shell Scripts

**scripts/pre-test.sh:**
```bash
#!/bin/bash
set -e

echo "Preparing YAWL test environment..."

# Start Mnesia for tests
erl -noshell -eval "
    application:load(mnesia),
    mnesia:create_schema([node()]),
    init:stop()
"

# Clean test databases
rm -rf Mnesia.* test_*.db

echo "Test environment ready"
```

**scripts/post-test.sh:**
```bash
#!/bin/bash
set -e

echo "Processing test results..."

# Generate HTML coverage report
rebar3 covertool generate

# Run quality checks
rebar3 dialyzer
rebar3 xref

echo "Test processing complete"
```

## Test Organization

### Directory Structure

```
erlang/a2a_erl/
├── tests/
│   ├── unit/                   # Unit tests
│   │   ├── yawl_orchestrator_tests.erl
│   │   ├── yawl_pattern_engine_tests.erl
│   │   └── y_combinator_tests.erl
│   ├── integration/            # Integration tests
│   │   ├── workflow_lifecycle_tests.erl
│   │   └── rest_api_tests.erl
│   └── property/               # Property-based tests
│       ├── workflow_properties.erl
│       └── resource_properties.erl
```

### Unit Test Example

```erlang
-module(yawl_orchestrator_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("yawl_types.hrl").

%% Test fixtures
setup() ->
    {ok, Pid} = yawl_orchestrator:start_link(),
    Pid.

cleanup(Pid) ->
    gen_server:stop(Pid).

%% Generator
orchestrator_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"create workflow", fun create_workflow/0},
      {"execute workflow", fun execute_workflow/0},
      {"cancel workflow", fun cancel_workflow/0}
     ]}.

%% Individual test
create_workflow() ->
    Config = #{
        pattern_type => sequential,
        name => <<"test_workflow">>,
        description => <<"Test workflow for unit testing">>
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
    ?assert(is_binary(WorkflowId)),
    ?assertMatch(<<"seq_", _/binary>>, WorkflowId).

execute_workflow() ->
    Config = #{
        pattern_type => sequential,
        name => <<"execute_test">>
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
    ok = yawl_orchestrator:execute_workflow(WorkflowId),

    {ok, Status} = yawl_orchestrator:workflow_status(WorkflowId),
    ?assertMatch(#workflow_status{status := running}, Status).

cancel_workflow() ->
    Config = #{
        pattern_type => sequential,
        name => <<"cancel_test">>
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
    ok = yawl_orchestrator:cancel_workflow(WorkflowId),

    {ok, Status} = yawl_orchestrator:workflow_status(WorkflowId),
    ?assertMatch(#workflow_status{status := cancelled}, Status).
```

### Integration Test Example

```erlang
-module(workflow_lifecycle_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

%% Suite callback
suite() ->
    [{timetrap, {seconds, 30}}].

%% Init per suite
init_per_suite(Config) ->
    {ok, _} = application:ensure_all_started(a2a_erl),
    Config.

%% End per suite
end_per_suite(_Config) ->
    application:stop(a2a_erl),
    ok.

%% Test cases
create_execute_complete_test(_Config) ->
    %% Create workflow
    Config = #{
        pattern_type => sequential,
        name => <<"lifecycle_test">>,
        parameters => #{
            steps => [
                #{task => step1, timeout => 5000},
                #{task => step2, timeout => 5000}
            ]
        }
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),

    %% Execute
    {ok, running} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Wait for first task
    timer:sleep(100),
    {ok, [Task1]} = yawl_orchestrator:get_pending_tasks(WorkflowId),
    ok = yawl_orchestrator:complete_task(WorkflowId, Task1, #{result => ok}),

    %% Wait for second task
    timer:sleep(100),
    {ok, [Task2]} = yawl_orchestrator:get_pending_tasks(WorkflowId),
    ok = yawl_orchestrator:complete_task(WorkflowId, Task2, #{result => ok}),

    %% Verify completion
    timer:sleep(100),
    {ok, completed} = yawl_orchestrator:workflow_status(WorkflowId),
    ?assertEqual(completed, completed).
```

## Property-Based Testing

### PropEr Integration

```erlang
-module(workflow_properties).
-include_lib("proper/include/proper.hrl").
-include_lib("yawl_types.hrl").

%% Property: Sequential workflow maintains order
prop_sequential_order() ->
    ?FORALL(Tasks, list(atom()),
        begin
            Config = #{
                pattern_type => sequential,
                name => <<"prop_test">>,
                parameters => #{tasks => Tasks}
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
            {ok, running} = yawl_orchestrator:execute_workflow(WorkflowId),

            %% Execute all tasks in order
            Executed = execute_all_tasks(WorkflowId, Tasks),
            Executed =:= Tasks
        end).

%% Property: Parallel split creates all branches
prop_parallel_split_branches() ->
    ?FORALL(BranchCount, range(1, 10),
        begin
            Config = #{
                pattern_type => parallel_split,
                name => <<"parallel_prop">>,
                parameters => #{branches => BranchCount}
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
            {ok, running} = yawl_orchestrator:execute_workflow(WorkflowId),

            {ok, Tasks} = yawl_orchestrator:get_all_tasks(WorkflowId),
            length(Tasks) =:= BranchCount
        end).

%% Helper function
execute_all_tasks(_WorkflowId, []) ->
    [];
execute_all_tasks(WorkflowId, [Task | Rest]) ->
    {ok, [CurrentTask]} = yawl_orchestrator:get_pending_tasks(WorkflowId),
    ok = yawl_orchestrator:complete_task(WorkflowId, CurrentTask, #{}),
    [Task | execute_all_tasks(WorkflowId, Rest)].

%% Run properties
run_properties() ->
    proper:module(?MODULE, [{numtests, 100}, long_result]).
```

## Running Tests

### Command Line

```bash
# Run all tests with HotCI
rebar3 hotci

# Run specific test directory
rebar3 hotci --dir tests/unit

# Run with coverage
rebar3 hotci --cover

# Run property tests
rebar3 hotci --property

# Run with verbose output
rebar3 hotci --verbose
```

### Interactive Shell

```erlang
# Start shell with HotCI loaded
rebar3 shell

# Run tests from shell
hotci:run_all().
hotci:run_suite(unit).
hotci:run_module(yawl_orchestrator_tests).

# Get coverage report
hotci:coverage().
```

## CI/CD Integration

### GitHub Actions

```yaml
name: YAWL Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        otp: ['25', '26', '27']

    steps:
      - uses: actions/checkout@v3

      - uses: erlef/setup-beam@v1
        with:
          otp-version: ${{ matrix.otp }}
          rebar3-version: latest

      - name: Cache deps
        uses: actions/cache@v3
        with:
          path: |
            _build
            ~/.cache/rebar3
          key: ${{ runner.os }}-erlang-${{ matrix.otp }}-${{ hashFiles('**/rebar.lock') }}

      - name: Compile
        run: rebar3 compile

      - name: Run HotCI tests
        run: rebar3 hotci

      - name: Upload coverage
        uses: actions/upload-artifact@v3
        with:
          name: coverage-${{ matrix.otp }}
          path: _build/test/cover/
```

### GitLab CI

```yaml
stages:
  - test
  - coverage

variables:
  REBAR_DEPS_DIR: "_build/deps"

test:erlang:
  stage: test
  image: erlang:26
  script:
    - rebar3 compile
    - rebar3 hotci
  artifacts:
    paths:
      - _build/test/
    expire_in: 1 day

coverage:report:
  stage: coverage
  image: erlang:26
  dependencies:
    - test:erlang
  script:
    - rebar3 cover
    - rebar3 covertool generate
  coverage: '/\d+\.\d+%/'

```

## Best Practices

### 1. Test Isolation

Each test should be independent and not rely on other tests:

```erlang
%% Good: Independent setup
independent_test() ->
    {ok, WorkflowId} = setup_workflow(),
    result = execute_test(WorkflowId),
    cleanup_workflow(WorkflowId).

%% Bad: Relies on external state
dependent_test() ->
    %% Assumes workflow_1 exists from previous test
    ?assertEqual(running, get_status(workflow_1)).
```

### 2. Descriptive Names

Use descriptive test names that explain what is being tested:

```erlang
%% Good: Descriptive
"parallel workflow creates all branches"
"resource allocation respects capabilities"

%% Bad: Vague
"test 1"
"test parallel"
```

### 3. Assertions

Use specific assertions:

```erlang
%% Good: Specific
?assertEqual(WorkflowId, <<"seq_", _/binary>>),
?assertMatch(#workflow_status{status := running}, Status).

%% Bad: Generic
?assert(WorkflowId =/= undefined).
```

### 4. Test Data

Use realistic test data:

```erlang
real_workflow_config() ->
    #{
        pattern_type => exclusive_choice,
        name => <<"approval_flow">>,
        parameters => #{
            conditions => [
                #{name => low_value, threshold => 100},
                #{name => high_value, threshold => 1000}
            ]
        }
    }.
```

## Troubleshooting

### Issue: Tests Fail Randomly

**Cause:** Tests may be timing-dependent or sharing state.

**Solution:**
- Add proper delays for async operations
- Ensure each test cleans up its state
- Use unique IDs for each test

### Issue: Coverage Below Threshold

**Cause:** Not all code paths are tested.

**Solution:**
- Add tests for error cases
- Test edge cases and boundary conditions
- Use property-based testing for combinatorial cases

### Issue: HotCI Not Found

**Cause:** HotCI dependency not installed.

**Solution:**
```bash
rebar3 deps
rebar3 compile
```

---

Next: [Back to Migration](../migration/) | [Testing Tutorial](../tutorials/testing.md)
