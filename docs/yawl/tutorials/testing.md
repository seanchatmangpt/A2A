# YAWL Testing Guide with HotCI

This tutorial covers testing YAWL workflows using HotCI, the continuous integration testing framework.

## HotCI Overview

HotCI is A2A's native testing framework designed for Erlang/OTP applications. It provides:

- **Fast Test Execution**: Parallel test execution
- **Isolation**: Each test runs in isolated environment
- **Coverage Analysis**: Built-in code coverage tracking
- **TDD Support**: Test-first development workflow
- **CI/CD Integration**: Easy Jenkins/GitHub Actions integration

## Test Organization

### Directory Structure

```
a2a_erl/tests/
├── unit/              # Unit tests for individual modules
│   ├── yawl_orchestrator_test.erl
│   ├── yawl_pattern_test.erl
│   └── yawl_resource_manager_test.erl
├── integration/       # Integration tests
│   ├── workflow_integration_test.erl
│   ├── rest_api_test.erl
│   └── end_to_end_test.erl
├── fixtures/          # Test data and fixtures
│   ├── workflows/
│   └── test_data/
└── ct/               # Common Test configuration
    └── ct_suite.spec
```

## Unit Testing

### Basic Unit Test

```erlang
%% File: tests/unit/yawl_orchestrator_test.erl
-module(yawl_orchestrator_test).
-include_lib("eunit/include/eunit.hrl").

%% Test workflow creation
create_workflow_test_() ->
    Config = #{pattern_type => sequential, name => <<"test">>},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
    ?assert(is_binary(WorkflowId)),
    ?assertMatch(WorkflowId, <<"seq_", _/binary>>).

%% Test pattern validation
validate_pattern_test_() ->
    ValidPattern = sequential,
    InvalidPattern = invalid_pattern,
    ?assertMatch(yawl_orchestrator:validate_pattern(ValidPattern, #{}), {ok, _}),
    ?assertMatch(yawl_orchestrator:validate_pattern(InvalidPattern, #{}), {error, _}).

%% Test workflow execution
execute_workflow_test_() ->
    Config = #{pattern_type => sequential, name => <<"test_exec">>},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
    ?assertEqual(running, maps:get(status, Status)).

%% Test workflow completion
workflow_completion_test_() ->
    Config = #{
        pattern_type => basic_sequential,
        name => <<"test_completion">>,
        steps => [step1, step2]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
    {ok, _} = yawl_orchendl_or:execute_workflow(WorkflowId),

    %% Complete all steps
    lists:foreach(fun(Step) ->
        ok = yawl_orchestrator:complete_workitem(
            WorkflowId,
            Step,
            #{result => completed}
        )
    end, [step1, step2]),

    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
    ?assertEqual(completed, maps:get(status, Status)).
```

### Testing with Mocks

```erlang
%% Mock resource manager
mock_resource_manager_test_() ->
    meck:new(yawl_resource_manager, [passthrough]),

    %% Mock successful allocation
    meck:expect(yawl_resource_manager, allocate_resource, [
        fun(_WorkitemId, _Capabilities) ->
            {ok, <<"resource_1">>, #allocation{}}
        end
    ]),

    %% Test with mocked resource manager
    Config = #{pattern_type => with_allocation, name => <<"test_mock">>},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Verify expectations
    meck:validate(yawl_resource_manager),
    ?assert(meck:.num_calls(yawl_resource_manager, allocate_resource) > 0),

    meck:unload(yawl_resource_manager).
```

## Integration Testing

### REST API Integration Test

```erlang
%% File: tests/integration/rest_api_test.erl
-module(rest_api_test).
-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

%% Test suite
all() ->
    [
        {suite, [], [
            {testcase, create_workflow_via_api, []},
            {testcase, execute_workflow_via_api, []},
            {testcase, complete_task_via_api, []}
        ]}
    ].

%% Setup and teardown
init_per_suite(Config) ->
    application:ensure_all_started([a2a_erl]),
    {ok, _} = yawl_rest_api:start(),
    Config.

end_per_suite(_Config) ->
    ok = yawl_rest_api:stop(),
    application:stop(a2a_erl),
    ok.

%% Test create workflow via REST API
create_workflow_via_api(_Config) ->
    Url = "/api/workflows",
    Body = #{
        pattern => <<"sequential">>,
        name => <<"api_test_workflow">>
    },
    {ok, 201, _, Response} = yawl_rest_api:request(post, Url, Body),
    ?assert(maps:get(<<"status">>, Response) =:= <<"created">>),
    ?assert(maps:get(<<"workflow_id">>, Response) =/= undefined).

%% Test execute workflow via REST API
execute_workflow_via_api(_Config) ->
    %% First create a workflow
    {ok, 201, _, CreateResponse} = yawl_rest_api:request(
        post,
        "/api/workflows",
        #{pattern => <<"sequential">>, name => <<"execute_test">>}
    ),
    WorkflowId = maps:get(<<"workflow_id">>, CreateResponse),

    %% Execute workflow
    Url2 = "/api/workflows/" ++ binary_to_list(WorkflowId) ++ "/execute",
    {ok, 200, _, ExecuteResponse} = yawl_rest_api:request(post, Url2, #{}),
    ?assert(maps:get(<<"status">>, ExecuteResponse) =:= <<"running">>).

%% Test complete task via REST API
complete_task_via_api(_Config) ->
    %% Create and execute workflow
    {ok, 201, _, CreateResponse} = yawl_rest_api:request(
        post,
        "/api/workflows",
        #{pattern => <<"sequential">>, name => <<"task_test">>}
    ),
    WorkflowId = maps:get(<<"workflow_id">>, CreateResponse),

    %% Execute workflow
    {ok, 200, _, _} = yawl_rest_api:request(
        post,
        "/api/workflows/" ++ binary_to_list(WorkflowId) ++ "/execute",
        #{}
    ),

    %% Get tasks
    {ok, 200, _, TasksResponse} = yawl_rest_api:request(
        get,
        "/api/workflows/" ++ binary_to_list(WorkflowId) ++ "/tasks",
        #{}
    ),
    Tasks = maps:get(<<"tasks">>, TasksResponse, []),

    %% Complete first task
    [FirstTask | _] = Tasks,
    TaskId = maps:get(<<"task_id">>, FirstTask),
    TaskUrl = "/api/workflows/" ++ binary_to_list(WorkflowId) ++
              "/tasks/" ++ binary_to_list(TaskId) ++ "/complete",

    {ok, 200, _, _} = yawl_rest_api:request(
        post,
        TaskUrl,
        #{result => #{status => completed}}
    ).
```

### End-to-End Workflow Test

```erlang
%% File: tests/integration/e2e_workflow_test.erl
-module(e2e_workflow_test).
-include_lib("eunit/include/eunit.hrl").

%% Complete workflow test
e2e_order_processing_test_() ->
    %% Create order processing workflow
    Config = #{
        pattern_type => parallel_split,
        name => <<"e2e_order_test">>,
        parameters => #{
            branches => 3,
            branch_config => [
                #{
                    task => inventory_check,
                    capabilities => [inventory],
                    timeout => 30000
                },
                #{
                    task => credit_check,
                    capabilities => [credit],
                    timeout => 30000
                },
                #{
                    task => fraud_check,
                    capabilities => [fraud],
                    timeout => 30000
                }
            ]
        }
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Simulate parallel task completion
    Tasks = get_workflow_tasks(WorkflowId),
    ?assert(length(Tasks) =:= 3),

    %% Complete all tasks
    lists:foreach(fun(Task) ->
        complete_task_simulated(Task)
    end, Tasks),

    %% Verify completion
    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
    ?assertEqual(completed, maps:get(status, Status)).

get_workflow_tasks(WorkflowId) ->
    {ok, Tasks} = yawl_orchestrator:get_workflow_tasks(WorkflowId),
    Tasks.

complete_task_simulated(Task) ->
    WorkitemId = maps:get(<<"workitem_id">>, Task),
    Result = #{result => ok, duration_ms => 100},
    ok = yawl_orchestrator:complete_workitem(
        maps:get(<<"workflow_id">>, Task),
        WorkitemId,
        Result
    ).
```

## HotCI Configuration

### rebar3.config Setup

```erlang
{plugins, [
    {rebar3_proper, ".*", [
        {cover_opts, #{coverage_criterion => coverage_line, cover_filter_rules_modules => [yawl]}}
    ]},
    {rebar3_eunit, ".*", [
        {eunit_opts, [
            {cover_opts, #{coverage_criterion => coverage_line, cover_filter_rules_modules => [yawl]}}
        ]}
    ]}
]}.
```

### rebar3.compiler Configuration

```erlang
{erl_opts, [debug_info]}.
{deps, [
    {meck, ".*", {git, "https://github.com/eproxus/meck.git", {branch, "main"}}}
]}.
```

### Common Test Configuration

```erlang
%% File: tests/ct/ct_suite.spec
{suite, [
    {foreach, [
        {yawl_orchestrator_SUITE, [
            {yield, [], [{timetrap, {ms, 5000}}, [
                {tc, tc_create_workflow},
                {tc, tc_execute_workflow},
                {tc, tc_complete_workflow},
                {tc, tc_pause_resume_workflow}
            ]]}
        ]},
        {yawl_patterns_SUITE, [
            {yield, [], [{timetrap, {ms, 5000}}, [
                {tc, tc_basic_patterns},
                {tc, tc_advanced_patterns},
                {tc, tc_cancellation_patterns}
            ]]}
        ]}
    ]}.
```

### Test Suite Implementation

```erlang
%% File: tests/integration/yawl_patterns_SUITE.erl
-module(yawl_patterns_SUITE).
-include_lib("common_test/include/ct.hrl").

all() -> [
    {suite, [], [
        {testcase, tc_basic_patterns, []},
        {testcase, tc_advanced_patterns, []},
        {testcase, tc_cancellation_patterns, []}
    ]}
].

%% Setup
init_per_suite(Config) ->
    application:ensure_all_started([a2a_erl]),
    Config.

end_per_suite(_Config) ->
    application:stop(a2a_erl),
    ok.

%% Test basic patterns
tc_basic_patterns(_Config) ->
    Patterns = [
        basic_sequential,
        parallel_split,
        parallel_join,
        exclusive_choice,
        simple_merge
    ],
    lists:foreach(fun(Pattern) ->
        test_pattern(Pattern)
    end, Patterns).

test_pattern(Pattern) ->
    Config = #{
        pattern_type => Pattern,
        name => list_to_binary(atom_to_list(Pattern) ++ "_test")
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
    {ok, _} = yawl_orchendl_or:execute_workflow(WorkflowId),

    %% Verify workflow is running
    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
    ?assertEqual(running, maps:get(status, Status)),

    %% Clean up
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId).

%% Test advanced patterns
tc_advanced_patterns(_Config) ->
    %% Test interleaved parallelism
    test_interleaved_parallelism(),
    %% Test deferred choice
    test_deferred_choice().

test_interleaved_parallelism() ->
    Config = #{
        pattern_type => interleaved_parallelism,
        name => <<"interleaved_test">>,
        parameters => #{
            tasks => [task_a, task_b, task_c]
        }
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Complete all tasks in any order
    Tasks = get_workflow_tasks(WorkflowId),
    ?assert(length(Tasks) =:= 3),

    %% Complete in different order
    [{_, Task2}, {_, Task3}, {_, Task1}] = Tasks,
    ok = yawl_orchestrator:complete_workitem(
        WorkflowId, Task2, #{result => ok}
    ),
    ok = yawl_orchestrator:complete_workitem(
        WorkflowId, Task3, #{result => ok}
    ),
    ok = yawl_orchestrator:complete_workitem(
        WorkflowId, Task1, #{result => ok}
    ),

    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
    ?assertEqual(completed, maps:get(status, Status)).
```

## Running Tests

### Run All Tests

```bash
# Unit tests only
rebar3 eunit

# Common tests
rebar3 ct

# All tests with coverage
rebar3 ct
rebar3 cover
```

### Run Specific Tests

```bash
# Specific module unit tests
rebar3 eunit --module=yawl_orchestrator

# Specific test suite
rebar3 ct --suite=yawl_patterns_SUITE

# Specific test case
rebar3 ct --suite=yawl_orchestrator_SUITE --case=tc_create_workflow
```

### Coverage Analysis

```bash
# Generate coverage report
rebar3 cover

# Open coverage report
open coverage/index.html
```

## Test-Driven Development Workflow

### TDD Cycle with HotCI

```bash
# 1. Write failing test
# 2. Run test (should fail)
rebar3 eunit --module=yawl_orchestrator

# 3. Implement minimal code to pass
# 4. Run test (should pass)
rebar3 eunit --module=yawl_orchestrator

# 5. Refactor
# 6. Run tests again (ensure still passing)
rebar3 eunit --module=yawl_orchestrator

# 7. Repeat for next feature
```

### Example TDD Session

```bash
# 1. Write test first
%% Test: Create workflow with invalid pattern
create_invalid_pattern_test_() ->
    Config = #{pattern_type => invalid, name => <<"invalid_test">>},
    ?assertMatch(yawl_orchestrator:create_workflow(Config), {error, _}).

# 2. Run test - fails
rebar3 eunit --module=yawl_orchestrator
# Test fails: function_clause error

# 3. Add pattern validation
%% In yawl_orchestrator.erl
validate_pattern(Pattern, _Config) ->
    case lists:member(Pattern, ?VALID_PATTERNS) of
        true -> {ok, valid};
        false -> {error, {invalid_pattern, Pattern}}
    end.

# 4. Run test - passes
rebar3 eunit --module=yawl_orchestrator
# All tests pass!

# 5. Add more edge cases
create_invalid_pattern_test_() ->
    ?assertMatch(yawl_orchestrator:create_workflow(
        #{pattern_type => undefined, name => <<"test">>}
    ), {error, _}),
    ?assertMatch(yawl_orchestrator:create_workflow(
        #{pattern_type => "", name => <<"test">>}
    ), {error, _}).

# 6. Run all tests - still passing
rebar3 eunit --module=yawl_orchestrator
```

## Property-Based Testing

### Using PropEr for Property Testing

```erlang
%% File: tests/prop/yawl_orchestrator_proper.erl
-module(yawl_orchestrator_proper).
-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").

%% Property: Workflow creation succeeds with valid config
prop_create_workflow_valid() ->
    ?FORALL(Config, valid_workflow_config(),
        begin
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),
            is_binary(WorkflowId) andalso
            lists:prefix(<<"seq_">>, WorkflowId) orelse
            lists:prefix(<<"par_">>, WorkflowId)
        end
    end).

%% Generator for valid configs
valid_workflow_config() ->
    ?LET(Pattern, oneof([
        basic_sequential, parallel_split, exclusive_choice,
        simple_merge, parallel_join
    ])),
    ?LET(Name, binary(10)),
    #{
        pattern_type => Pattern,
        name => <<"test_", Name/binary>>,
        parameters => generate_parameters(Pattern)
    }).

generate_parameters(Pattern) ->
    case Pattern of
        parallel_split ->
            #{branches => choose(1, 5), timeout => choose(1000, 60000)};
        exclusive_choice ->
            #{conditions => [
                #{threshold => choose(0, 1000)}
            ]};
        _ ->
            #{}
    end.

%% Property: Workflow status transitions are valid
prop_status_transitions_valid() ->
    ?FORALL({WorkflowId, Events}, workflow_events(),
        begin
            execute_events(WorkflowId, Events),
            is_valid_status_sequence(get_status_history(WorkflowId))
        end
    end).

workflow_events() ->
    ?LET(EventStream, list(event_gen:event_stream(
        [{workflow_created, 0.5},
         {workflow_started, 0.3},
         {workflow_paused, 0.1},
         {workflow_resumed, 0.1},
         {workflow_completed, 0.3},
         {workflow_failed, 0.05},
         {workflow_cancelled, 0.05}
    ])),
    listseq:map(fun({Type, _}) -> Type end, EventStream)).

is_valid_status_sequence(StatusHistory) ->
    ValidTransitions = #{
        undefined => [created],
        created => [running],
        running => [paused, completed, failed, cancelled],
        paused => [running, cancelled],
        completed => [],
        failed => [],
        cancelled => []
    },
    lists:all(fun({From, To}) ->
        Allowed = maps:get(From, ValidTransitions, []),
        lists:member(To, Allowed)
    end, get_status_transitions(StatusHistory)).
```

### Running Property Tests

```bash
# Run property tests
rebar3 proper

# Run specific property
rebar3 proper -m yawl_orchestrator_proper

# Run with more tests
rebar3 proper -n 1000
```

## Continuous Integration with HotCI

### CI Configuration

```yaml
# .github/workflows/ci.yml
name: YAWL CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Install Erlang
        uses: erlang-solutions/erlang-o-tp@v1
        with:
          otp-version: 25

      - name: Cache rebar3 deps
        id: cache-deps
        uses: actions/cache@v3
        with:
          path: ~/.cache/rebar3/cache
          key: ${{ runner.os }}-rebar3-deps-${{ hashFiles('**/rebar.lock') }}

      - name: Install dependencies
        run: rebar3 deps

      - name: Compile
        run: rebar3 compile

      - name: Run unit tests
        run: rebar3 eunit

      - name: Run common tests
        run: rebar3 ct

      - name: Generate coverage
        run: rebar3 cover

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          file: ./_build/test/cover/eunit.coverdata
```

## Testing Best Practices

### 1. Test Isolation

```erlang
%% Setup per test
init_per_test() ->
    {ok, Pid} = yawl_orchestrator:start_link(),
    {Pid, #state{config = TestConfig}}.

%% Cleanup per test
end_per_test(_Pid) ->
    gen_server:stop(Pid),
    %% Verify cleanup
    ?assertNot(whereis(yawl_orchestrator)).
```

### 2. Use Test Generators

```erlang
%% Generate test data
generate_test_workitems(Count) ->
    [generate_workitem(N) || N <- lists:seq(1, Count)].

generate_workitem(N) ->
    #{
        workitem_id => list_to_binary("workitem_" ++ integer_to_list(N)),
        task_name => list_to_binary("task_" ++ integer_to_list(N)),
        data => #{index => N}
    }.
```

### 3. Assert Effect, Not Implementation

```erlang
%% Good: Test behavior
workflow_retries_on_failure_test_() ->
    Config = #{
        pattern_type => sequential,
        name => <<"retry_test">>,
        retry_policy => #{max_retries => 3}
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Config),

    %% Simulate failures and recovery
    simulate_failures(WorkflowId, 2),

    %% Should eventually complete
    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
    ?assertEqual(completed, maps:get(status, Status)).

%% Avoid: Testing implementation details
bad_test() ->
    %% Testing internal state rather than behavior
    {ok, State} = get_internal_state(WorkflowId),
    ?assert(State#state.retry_count =:= 2).
```

### 4. Mock External Dependencies

```erlang
%% Mock database operations
mock_database_test_() ->
    meck:new(yawl_persistence, [no_history]),

    meck:expect(yawl_persistence, save_workflow, [
        fun(Workflow) ->
            ?assertMatch(Workflow#yawl_workflow.workflow_id, <<"mock_", _/binary>>),
            {ok, WorkflowId}
        end
    ]),

    %% Test with mocked persistence
    Config = #{pattern_type => sequential, name => <<"mock_test">>},
    {ok, _WorkflowId} = yawl_orchestrator:create_workflow(Config),

    %% Verify persistence was called
    ?assert(meck:called(yawl_persistence, save_workflow, '_')),
    meck:validate(yawl_persistence).
```

## Debugging Tests

### Enable Debug Output

```bash
# Run tests with debug output
rebar3 ct -v

# Run specific test with verbose
rebar3 ct --suite=yawl_orchestrator_SUITE -v
```

### Interactive Testing

```erlang
# Start interactive test shell
rebar3 ct --shell

# In shell, run specific test
ct:run(yawl_orchestrator_SUITE, tc_create_workflow).

# Run all tests in suite
ct:run(yawl_orchestrator_SUITE).
```

## Test Coverage Goals

YAWL aims for 80%+ code coverage across all modules:

| Module | Target Coverage |
|-------|----------------|
| Core | 90%+ |
| Patterns | 85%+ |
| Resource Manager | 85%+ |
| Event System | 80%+ |
| REST API | 80%+ |

### Check Coverage

```bash
# Full coverage report
rebar3 cover

# Module-specific coverage
rebar3 cover --coveralls=yawl_orchestrator
```

---

Next: [Research Features](../research/) | [Back to Tutorials](../tutorials/)
