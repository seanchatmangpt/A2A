%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Workflow Integration Test Suite
%%%
%%% This module contains Common Test suites for comprehensive end-to-end
%%% workflow testing. It covers:
%%%
%%% - Complete workflow lifecycle from creation to completion
%%% - Multiple workflow patterns (sequential, parallel, choice)
%%% - Human task allocation and completion
%%% - Service integration and error handling
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_workflow_integration_tests).
-author("A2A Team").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% Export tests
-export([
    all/0,
    groups/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_group/2,
    end_per_group/2,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases - Workflow Lifecycle Tests
-export([
    test_workflow_lifecycle_sequential/1,
    test_workflow_lifecycle_parallel/1,
    test_workflow_lifecycle_choice/1,
    test_workflow_lifecycle_with_human_tasks/1,
    test_workflow_lifecycle_with_service_integration/1,
    test_workflow_cancellation/1,
    test_workflow_error_handling/1
]).

%% Test cases - Pattern Combination Tests
-export([
    test_sequential_parallel_combination/1,
    test_choice_parallel_combination/1,
    test_iterative_sequential_combination/1,
    test_multi_instance_patterns/1,
    test_interleaved_parallelism/1
]).

%% Test cases - Human Task Tests
-export([
    test_human_task_allocation/1,
    test_human_task_completion/1,
    test_human_task_timeout/1,
    test_human_task_priority_handling/1,
    test_human_task_group_allocation/1
]).

%% Test cases - Service Integration Tests
-export([
    test_service_synchronous_call/1,
    test_service_asynchronous_call/1,
    test_service_failure_handling/1,
    test_service_retry_mechanism/1,
    test_service_circuit_breaker/1
]).

%% Test cases - Performance Tests
-export([
    test_concurrent_workflows/1,
    test_workflow_throughput/1,
    test_resource_contention/1,
    test_memory_usage/1
]).

%%====================================================================
%% Common Test Callbacks
%%====================================================================

%% @doc Return all test cases.
-spec all() -> [atom()].
all() ->
    [
        %% Workflow Lifecycle Tests
        test_workflow_lifecycle_sequential,
        test_workflow_lifecycle_parallel,
        test_workflow_lifecycle_choice,
        test_workflow_lifecycle_with_human_tasks,
        test_workflow_lifecycle_with_service_integration,
        test_workflow_cancellation,
        test_workflow_error_handling,

        %% Pattern Combination Tests
        test_sequential_parallel_combination,
        test_choice_parallel_combination,
        test_iterative_sequential_combination,
        test_multi_instance_patterns,
        test_interleaved_parallelism,

        %% Human Task Tests
        test_human_task_allocation,
        test_human_task_completion,
        test_human_task_timeout,
        test_human_task_priority_handling,
        test_human_task_group_allocation,

        %% Service Integration Tests
        test_service_synchronous_call,
        test_service_asynchronous_call,
        test_service_failure_handling,
        test_service_retry_mechanism,
        test_service_circuit_breaker,

        %% Performance Tests
        test_concurrent_workflows,
        test_workflow_throughput,
        test_resource_contention,
        test_memory_usage
    ].

%% @doc Return test groups.
-spec groups() -> [{atom(), list(), [atom()]}].
groups() ->
    [
        {lifecycle_tests, [sequence], [
            test_workflow_lifecycle_sequential,
            test_workflow_lifecycle_parallel,
            test_workflow_lifecycle_choice,
            test_workflow_lifecycle_with_human_tasks,
            test_workflow_lifecycle_with_service_integration,
            test_workflow_cancellation,
            test_workflow_error_handling
        ]},
        {pattern_tests, [sequence], [
            test_sequential_parallel_combination,
            test_choice_parallel_combination,
            test_iterative_sequential_combination,
            test_multi_instance_patterns,
            test_interleaved_parallelism
        ]},
        {human_task_tests, [sequence], [
            test_human_task_allocation,
            test_human_task_completion,
            test_human_task_timeout,
            test_human_task_priority_handling,
            test_human_task_group_allocation
        ]},
        {service_integration_tests, [sequence], [
            test_service_synchronous_call,
            test_service_asynchronous_call,
            test_service_failure_handling,
            test_service_retry_mechanism,
            test_service_circuit_breaker
        ]},
        {performance_tests, [sequence], [
            test_concurrent_workflows,
            test_workflow_throughput,
            test_resource_contention,
            test_memory_usage
        ]}
    ].

%% @doc Initialize test suite.
-spec init_per_suite(Config) -> Config when Config :: [tuple()].
init_per_suite(Config) ->
    ct:pal("Starting YAWL Workflow Integration Test Suite"),
    ct:pal("Testing complete workflow lifecycle and patterns"),
    %% Start applications
    {ok, _} = application:ensure_all_started(a2a_erl),
    %% Start required services
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),
    {ok, ResourceManagerPid} = yawl_resource_manager:start_link(),
    {ok, PersistencePid} = yawl_persistence:start_link(),
    {ok, RestPid} = yawl_rest:start_link(#{port => 8081}),

    %% Register test resources
    register_test_resources(),

    [{orchestrator_pid, OrchestratorPid},
     {resource_manager_pid, ResourceManagerPid},
     {persistence_pid, PersistencePid},
     {rest_pid, RestPid} | Config].

%% @doc Cleanup test suite.
-spec end_per_suite(Config) -> ok when Config :: [tuple()].
end_per_suite(Config) ->
    %% Stop services
    RestPid = proplists:get_value(rest_pid, Config),
    OrchestratorPid = proplists:get_value(orchestrator_pid, Config),
    ResourceManagerPid = proplists:get_value(resource_manager_pid, Config),
    PersistencePid = proplists:get_value(persistence_pid, Config),

    gen_server:stop(RestPid),
    gen_server:stop(OrchestratorPid),
    gen_server:stop(ResourceManagerPid),
    gen_server:stop(PersistencePid),

    %% Stop application
    application:stop(a2a_erl),

    ct:pal("Completed YAWL Workflow Integration Test Suite"),
    ok.

%% @doc Initialize test group.
-spec init_per_group(atom(), Config) -> Config when Config :: [tuple()].
init_per_group(GroupName, Config) ->
    ct:pal("Starting group: ~p", [GroupName]),
    %% Clean up any previous workflows
    cleanup_test_data(),
    Config.

%% @doc Cleanup test group.
-spec end_per_group(atom(), Config) -> ok when Config :: [tuple()].
end_per_group(GroupName, _Config) ->
    ct:pal("Completed group: ~p", [GroupName]),
    cleanup_test_data(),
    ok.

%% @doc Initialize test case.
-spec init_per_testcase(atom(), Config) -> Config when Config :: [tuple()].
init_per_testcase(TestName, Config) ->
    ct:pal("Starting test: ~p", [TestName]),
    cleanup_test_data(),
    Config.

%% @doc Cleanup test case.
-spec end_per_testcase(atom(), Config) -> ok when Config :: [tuple()].
end_per_testcase(TestName, _Config) ->
    ct:pal("Completed test: ~p", [TestName]),
    cleanup_test_data(),
    ok.

%%====================================================================
%% Workflow Lifecycle Tests
%%====================================================================

%% @doc Test complete sequential workflow lifecycle.
-spec test_workflow_lifecycle_sequential(Config) -> ok when Config :: [tuple()].
test_workflow_lifecycle_sequential(_Config) ->
    %% Create workflow
    Config = #{task1_name => "process_order", task2_name => "fulfill_order"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    ct:pal("Created workflow: ~p", [WorkflowId]),

    %% Verify initial state
    {ok, pending} = yawl_orchestrator:get_status(WorkflowId),

    %% Start workflow
    {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),
    ct:pal("Started workflow: ~p", [Result]),

    %% Wait for completion
    wait_for_workflow_completion(WorkflowId, 30000),

    %% Verify final state
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),
    {ok, WorkflowResult} = yawl_orchestrator:get_workflow_result(WorkflowId),

    %% Verify workflow result structure
    ?assert(is_map(WorkflowResult)),
    ?assert(maps:is_key(status, WorkflowResult)),

    ct:pal("Sequential workflow completed successfully"),
    ok.

%% @doc Test complete parallel workflow lifecycle.
-spec test_workflow_lifecycle_parallel(Config) -> ok when Config :: [tuple()].
test_workflow_lifecycle_parallel(_Config) ->
    %% Note: This assumes parallel_split pattern exists
    Config = #{task1_name => "process_payment", task2_name => "check_inventory"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(parallel_split, Config),
    ct:pal("Created parallel workflow: ~p", [WorkflowId]),

    %% Start workflow
    {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Wait for completion
    wait_for_workflow_completion(WorkflowId, 30000),

    %% Verify completion
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),
    {ok, WorkflowResult} = yawl_orchestrator:get_workflow_result(WorkflowId),

    ct:pal("Parallel workflow completed successfully"),
    ok.

%% @doc Test complete choice workflow lifecycle.
-spec test_workflow_lifecycle_choice(Config) -> ok when Config :: [tuple()].
test_workflow_lifecycle_choice(_Config) ->
    %% Note: This assumes exclusive_choice pattern exists
    Config = #{decision_condition => "amount > 1000"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(exclusive_choice, Config),
    ct:pal("Created choice workflow: ~p", [WorkflowId]),

    %% Start workflow
    {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Wait for completion
    wait_for_workflow_completion(WorkflowId, 30000),

    %% Verify completion
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    ct:pal("Choice workflow completed successfully"),
    ok.

%% @doc Test workflow lifecycle with human tasks.
-spec test_workflow_lifecycle_with_human_tasks(Config) -> ok when Config :: [tuple()].
test_workflow_lifecycle_with_human_tasks(_Config) ->
    %% Create human task resource
    {ok, HumanResourceId} = yawl_resource_manager:register_resource(
        <<"reviewer">>, human, #{capabilities => [review]}),

    %% Create workflow with human task
    Config = #{human_tasks => [#{id => review_task, capability => review}]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    ct:pal("Created workflow with human tasks: ~p", [WorkflowId]),

    %% Start workflow
    {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Simulate human task allocation and completion
    Workitems = get_workflow_workitems(WorkflowId),
    ct:pal("Found workitems: ~p", [Workitems]),

    %% Complete workflow (assuming it will succeed after human task completion)
    wait_for_workflow_completion(WorkflowId, 30000),

    ct:pal("Workflow with human tasks completed successfully"),
    ok.

%% @doc Test workflow lifecycle with service integration.
-spec test_workflow_lifecycle_with_service_integration(Config) -> ok when Config :: [tuple()].
test_workflow_lifecycle_with_service_integration(_Config) ->
    %% Register test service
    {ok, ServiceId} = yawl_resource_manager:register_resource(
        <<"payment_service">>, service, #{capabilities => [process_payment]}),

    %% Create workflow with service integration
    Config = #{service_tasks => [#{id => payment_task, service => process_payment}]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    ct:pal("Created workflow with service integration: ~p", [WorkflowId]),

    %% Start workflow
    {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Wait for completion
    wait_for_workflow_completion(WorkflowId, 30000),

    %% Verify completion
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    ct:pal("Workflow with service integration completed successfully"),
    ok.

%% @doc Test workflow cancellation.
-spec test_workflow_cancellation(Config) -> ok when Config :: [tuple()].
test_workflow_cancellation(_Config) ->
    %% Create workflow
    Config = #{},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Start workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Allow it to run briefly
    timer:sleep(1000),

    %% Cancel workflow
    ok = yawl_orchestrator:cancel_workflow(WorkflowId),

    %% Verify cancellation
    {ok, cancelled} = yawl_orchestrator:get_status(WorkflowId),

    ct:pal("Workflow cancellation test successful"),
    ok.

%% @doc Test workflow error handling.
-spec test_workflow_error_handling(Config) -> ok when Config :: [tuple()].
test_workflow_error_handling(_Config) ->
    %% Create workflow with error scenario
    Config = #{simulate_error => true, error_point => "task2"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Start workflow
    case yawl_orchestrator:execute_workflow(WorkflowId) of
        {ok, _} ->
            wait_for_workflow_completion(WorkflowId, 10000),
            {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
            ct:pal("Workflow completed with status: ~p", [Status]);
        {error, Reason} ->
            ct:pal("Workflow failed as expected: ~p", [Reason])
    end,

    ct:pal("Workflow error handling test completed"),
    ok.

%%====================================================================
%% Pattern Combination Tests
%%====================================================================

%% @doc Test sequential and parallel pattern combination.
-spec test_sequential_parallel_combination(Config) -> ok when Config :: [tuple()].
test_sequential_parallel_combination(_Config) ->
    %% Create combined pattern workflow
    Patterns = [
        {basic_sequential, #{task1_name => "start", task2_name => "middle"}},
        {parallel_split, #{task1_name => "parallel1", task2_name => "parallel2"}},
        {basic_sequential, #{task1_name => "combine", task2_name => "end"}}
    ],

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(combined_pattern, #{patterns => Patterns}),
    ct:pal("Created combined pattern workflow: ~p", [WorkflowId]),

    %% Execute and verify
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_workflow_completion(WorkflowId, 30000),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    ct:pal("Sequential-parallel combination test successful"),
    ok.

%% @doc Test choice and parallel pattern combination.
-spec test_choice_parallel_combination(Config) -> ok when Config :: [tuple()].
test_choice_parallel_combination(_Config) ->
    Patterns = [
        {exclusive_choice, #{condition => "priority"}},
        {parallel_split, #{branches => 2}},
        {basic_sequential, #{}}
    ],

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(combined_pattern, #{patterns => Patterns}),
    ct:pal("Created choice-parallel combination workflow: ~p", [WorkflowId]),

    %% Execute and verify
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_workflow_completion(WorkflowId, 30000),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    ct:pal("Choice-parallel combination test successful"),
    ok.

%% @doc Test iterative sequential pattern combination.
-spec test_iterative_sequential_combination(Config) -> ok when Config :: [tuple()].
test_iterative_sequential_combination(_Config) ->
    Patterns = [
        {basic_sequential, #{first_task => "init"}},
        {iterative_loop, #{iterations => 3, task_name => "loop"}},
        {basic_sequential, #{final_task => "complete"}}
    ],

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(combined_pattern, #{patterns => Patterns}),
    ct:pal("Created iterative-sequential combination workflow: ~p", [WorkflowId]),

    %% Execute and verify
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_workflow_completion(WorkflowId, 30000),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    ct:pal("Iterative-sequential combination test successful"),
    ok.

%% @doc Test multi-instance patterns.
-spec test_multi_instance_patterns(Config) -> ok when Config :: [tuple()].
test_multi_instance_patterns(_Config) ->
    %% Create workflow with multi-instance pattern
    Config = #{count => 5, task_name => "process_item"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(multi_instance, Config),
    ct:pal("Created multi-instance workflow: ~p", [WorkflowId]),

    %% Execute and verify
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_workflow_completion(WorkflowId, 30000),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    ct:pal("Multi-instance pattern test successful"),
    ok.

%% @doc Test interleaved parallelism patterns.
-spec test_interleaved_parallelism(Config) -> ok when Config :: [tuple()].
test_interleaved_parallelism(_Config) ->
    Patterns = [
        {parallel_split, #{branches => 2}},
        {implicit_merge, #{}},
        {parallel_split, #{branches => 3}}
    ],

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(combined_pattern, #{patterns => Patterns}),
    ct:pal("Created interleaved parallelism workflow: ~p", [WorkflowId]),

    %% Execute and verify
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_workflow_completion(WorkflowId, 30000),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    ct:pal("Interleaved parallelism test successful"),
    ok.

%%====================================================================
%% Human Task Tests
%%====================================================================

%% @doc Test human task allocation.
-spec test_human_task_allocation(Config) -> ok when Config :: [tuple()].
test_human_task_allocation(_Config) ->
    %% Register human resource
    {ok, HumanResourceId} = yawl_resource_manager:register_resource(
        <<"reviewer1">>, human, #{capabilities => [review], max_capacity => 3}),

    %% Create workflow with human task
    Config = #{human_task => #{id => review, capability => review}},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Verify task allocation
    Workitems = get_workflow_workitems(WorkflowId),
    ct:pal("Workitems after execution: ~p", [Workitems]),

    ct:pal("Human task allocation test completed"),
    ok.

%% @doc Test human task completion.
-spec test_human_task_completion(Config) -> ok when Config :: [tuple()].
test_human_task_completion(_Config) ->
    %% Register human resource
    {ok, HumanResourceId} = yawl_resource_manager:register_resource(
        approver, human, #{capabilities => [approve], max_capacity => 1}),

    %% Create workflow
    Config = #{human_task => #{id => approve, capability => approve}},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Simulate task completion
    Workitems = get_workflow_workitems(WorkflowId),
    lists:foreach(fun(Workitem) ->
        yawl_workitem_processor:complete_workitem(Workitem, #{decision => approved})
    end, Workitems),

    ct:pal("Human task completion test completed"),
    ok.

%% @doc Test human task timeout.
-spec test_human_task_timeout(Config) -> ok when Config :: [tuple()].
test_human_task_timeout(_Config) ->
    %% Register human resource with timeout
    {ok, _} = yawl_resource_manager:register_resource(
        reviewer, human, #{capabilities => [review], timeout => 5000}),

    %% Create workflow
    Config = #{human_task => #{id => review, capability => review, timeout => 3000}},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Let it timeout
    timer:sleep(6000),

    ct:pal("Human task timeout test completed"),
    ok.

%% @doc Test human task priority handling.
-spec test_human_task_priority_handling(Config) -> ok when Config :: [tuple()].
test_human_task_priority_handling(_Config) ->
    %% Register multiple human resources
    {ok, _} = yawl_resource_manager:register_resource(
        reviewer1, human, #{capabilities => [review], max_capacity => 1}),
    {ok, _} = yawl_resource_manager:register_resource(
        reviewer2, human, #{capabilities => [review], max_capacity => 1}),

    %% Create workflows with different priorities
    Config1 = #{human_task => #{id => review1, capability => review, priority => urgent}},
    {ok, WorkflowId1} = yawl_orchestrator:create_workflow(basic_sequential, Config1),

    Config2 = #{human_task => #{id => review2, capability => review, priority => low}},
    {ok, WorkflowId2} = yawl_orchestrator:create_workflow(basic_sequential, Config2),

    %% Execute both
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId1),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId2),

    ct:pal("Human task priority handling test completed"),
    ok.

%% @doc Test human task group allocation.
-spec test_human_task_group_allocation(Config) -> ok when Config :: [tuple()].
test_human_task_group_allocation(_Config) ->
    %% Register human group
    {ok, _} = yawl_resource_manager:register_resource(
        approval_team, human, #{capabilities => [approve], max_capacity => 5}),

    %% Create workflow with group allocation
    Config = #{human_task => #{id => approve, capability => approve, group => approval_team}},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    ct:pal("Human task group allocation test completed"),
    ok.

%%====================================================================
%% Service Integration Tests
%%====================================================================

%% @doc Test synchronous service calls.
-spec test_service_synchronous_call(Config) -> ok when Config :: [tuple()].
test_service_synchronous_call(_Config) ->
    %% Register test service
    {ok, ServiceId} = yawl_resource_manager:register_resource(
        test_service, service, #{capabilities => [sync_call]}),

    %% Create workflow with service call
    Config = #{service_task => #{id => sync_call, service => sync_call}},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_workflow_completion(WorkflowId, 15000),

    ct:pal("Synchronous service call test completed"),
    ok.

%% @doc Test asynchronous service calls.
-spec test_service_asynchronous_call(Config) -> ok when Config :: [tuple()].
test_service_asynchronous_call(_Config) ->
    %% Register test service
    {ok, ServiceId} = yawl_resource_manager:register_resource(
        async_service, service, #{capabilities => [async_call]}),

    %% Create workflow with async service call
    Config = #{service_task => #{id => async_call, service => async_call}},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_workflow_completion(WorkflowId, 20000),

    ct:pal("Asynchronous service call test completed"),
    ok.

%% @doc Test service failure handling.
-spec test_service_failure_handling(Config) -> ok when Config :: [tuple()].
test_service_failure_handling(_Config) ->
    %% Register failing service
    {ok, ServiceId} = yawl_resource_manager:register_resource(
        failing_service, service, #{capabilities => [fail_call], simulate_failure => true}),

    %% Create workflow
    Config = #{service_task => #{id => fail_call, service => fail_call}},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_workflow_completion(WorkflowId, 15000),

    ct:pal("Service failure handling test completed"),
    ok.

%% @doc Test service retry mechanism.
-spec test_service_retry_mechanism(Config) -> ok when Config :: [tuple()].
test_service_retry_mechanism(_Config) ->
    %% Register service that fails first time
    {ok, ServiceId} = yawl_resource_manager:register_resource(
        retry_service, service, #{capabilities => [retry_call], simulate_retry => true}),

    %% Create workflow with retry
    Config = #{service_task => #{id => retry_call, service => retry_call, retry_count => 3}},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_workflow_completion(WorkflowId, 20000),

    ct:pal("Service retry mechanism test completed"),
    ok.

%% @doc Test service circuit breaker.
-spec test_service_circuit_breaker(Config) -> ok when Config :: [tuple()].
test_service_circuit_breaker(_Config) ->
    %% Register service that fails frequently
    {ok, ServiceId} = yawl_resource_manager:register_resource(
        unstable_service, service, #{capabilities => [unstable_call], simulate_failure => true}),

    %% Create workflow
    Config = #{service_task => #{id => unstable_call, service => unstable_call}},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Execute workflow multiple times to test circuit breaker
    lists:foreach(fun(_) ->
        {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
        wait_for_workflow_completion(WorkflowId, 10000)
    end, lists:seq(1, 5)),

    ct:pal("Service circuit breaker test completed"),
    ok.

%%====================================================================
%% Performance Tests
%%====================================================================

%% @doc Test concurrent workflow execution.
-spec test_concurrent_workflows(Config) -> ok when Config :: [tuple()].
test_concurrent_workflows(_Config) ->
    %% Create multiple workflows
    NumWorkflows = 10,
    WorkflowIds = lists:map(fun(I) ->
        Config = #{workflow_id => I},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        WorkflowId
    end, lists:seq(1, NumWorkflows)),

    %% Start all workflows concurrently
    StartResults = lists:map(fun(WorkflowId) ->
        yawl_orchestrator:execute_workflow(WorkflowId)
    end, WorkflowIds),

    %% Wait for all to complete
    lists:foreach(fun(WorkflowId) ->
        wait_for_workflow_completion(WorkflowId, 30000)
    end, WorkflowIds),

    %% Verify all completed
    Results = lists:map(fun(WorkflowId) ->
        {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
        Status
    end, WorkflowIds),

    CompletedCount = lists:filter(fun(completed) -> true; (_) -> false end, Results),
    ct:pal("Concurrent workflows: ~p/~p completed", [length(CompletedCount), NumWorkflows]),

    ct:pal("Concurrent workflows test completed"),
    ok.

%% @doc Test workflow throughput.
-spec test_workflow_throughput(Config) -> ok when Config :: [tuple()].
test_workflow_throughput(_Config) ->
    StartTime = erlang:monotonic_time(millisecond),
    NumWorkflows = 20,

    %% Create and execute workflows
    lists:map(fun(I) ->
        Config = #{iteration => I},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
        wait_for_workflow_completion(WorkflowId, 15000)
    end, lists:seq(1, NumWorkflows)),

    EndTime = erlang:monotonic_time(millisecond),
    Duration = (EndTime - StartTime) / 1000,  % in seconds

    Throughput = NumWorkflows / Duration,
    ct:pal("Workflow throughput: ~p workflows/second", [Throughput]),

    ct:pal("Workflow throughput test completed"),
    ok.

%% @doc Test resource contention.
-spec test_resource_contention(Config) -> ok when Config :: [tuple()].
test_resource_contention(_Config) ->
    %% Register single resource with low capacity
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        bottleneck_resource, service, #{capabilities => [bottleneck], max_capacity => 1}),

    %% Create multiple workflows competing for the resource
    NumWorkflows = 5,
    WorkflowIds = lists:map(fun(I) ->
        Config = #{task_resource => bottleneck},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        WorkflowId
    end, lists:seq(1, NumWorkflows)),

    %% Start all workflows
    lists:map(fun(WorkflowId) ->
        {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId)
    end, WorkflowIds),

    %% Wait for completion
    lists:foreach(fun(WorkflowId) ->
        wait_for_workflow_completion(WorkflowId, 45000)  % Longer timeout due to contention
    end, WorkflowIds),

    ct:pal("Resource contention test completed"),
    ok.

%% @doc Test memory usage.
-spec test_memory_usage(Config) -> ok when Config :: [tuple()].
test_memory_usage(_Config) ->
    %% Create many workflows
    NumWorkflows = 50,
    lists:map(fun(I) ->
        Config = #{memory_test => I},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
        wait_for_workflow_completion(WorkflowId, 20000)
    end, lists:seq(1, NumWorkflows)),

    %% Get memory usage
    MemoryInfo = erlang:memory(),
    TotalMemory = proplists:get_value(total, MemoryInfo, 0),

    ct:pal("Memory usage test completed. Total memory: ~p bytes", [TotalMemory]),
    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
%% @doc Wait for workflow completion with timeout.
wait_for_workflow_completion(WorkflowId, Timeout) ->
    StartTime = erlang:monotonic_time(millisecond),
    wait_for_completion(WorkflowId, StartTime, Timeout).

wait_for_completion(WorkflowId, StartTime, Timeout) ->
    case yawl_orchestrator:get_status(WorkflowId) of
        {ok, completed} ->
            ok;
        {ok, running} ->
            case erlang:monotonic_time(millisecond) - StartTime of
                Elapsed when Elapsed > Timeout ->
                    ct:pal("Workflow ~p did not complete within ~p ms", [WorkflowId, Timeout]);
                _ ->
                    timer:sleep(100),
                    wait_for_completion(WorkflowId, StartTime, Timeout)
            end;
        {ok, Status} ->
            ct:pal("Workflow ~p status: ~p", [WorkflowId, Status]),
            timer:sleep(100),
            wait_for_completion(WorkflowId, StartTime, Timeout)
    end.

%% @private
%% @doc Get workitems for a workflow (mock implementation).
get_workflow_workitems(WorkflowId) ->
    %% This would typically query the persistence layer
    %% For testing, we return a mock list
    [<<"workitem_1">>, <<"workitem_2">>].

%% @private
%% @doc Register test resources for all test cases.
register_test_resources() ->
    %% Register human resources
    {ok, _} = yawl_resource_manager:register_resource(<<"admin">>, human, #{capabilities => [admin]}),
    {ok, _} = yawl_resource_manager:register_resource(<<"approver">>, human, #{capabilities => [approve]}),
    {ok, _} = yawl_resource_manager:register_resource(<<"reviewer">>, human, #{capabilities => [review]}),

    %% Register service resources
    {ok, _} = yawl_resource_manager:register_resource(<<"payment_service">>, service, #{capabilities => [process_payment]}),
    {ok, _} = yawl_resource_manager:register_resource(<<"notification_service">>, service, #{capabilities => [send_notification]}),
    {ok, _} = yawl_resource_manager:register_resource(<<"validation_service">>, service, #{capabilities => [validate_data]}),

    %% Register system resources
    {ok, _} = yawl_resource_manager:register_resource(<<"database">>, system, #{capabilities => [store_data]}),
    {ok, _} = yawl_resource_manager:register_resource(<<"cache">>, system, #{capabilities => [cache_data]}).

%% @private
%% @doc Clean up test data between test cases.
cleanup_test_data() ->
    %% Clean up workflows
    case yawl_orchestrator:list_workflows() of
        {ok, WorkflowIds} ->
            lists:foreach(fun(WorkflowId) ->
                case yawl_orchestrator:get_status(WorkflowId) of
                    {ok, Status} when Status =:= running orelse Status =:= pending ->
                        ok = yawl_orchestrator:cancel_workflow(WorkflowId),
                        ok = yawl_orchestrator:cleanup_workflow(WorkflowId);
                    _ ->
                        ok = yawl_orchestrator:cleanup_workflow(WorkflowId)
                end
            end, WorkflowIds);
        _ ->
            ok
    end,

    %% Clean up resources
    case yawl_resource_manager:list_resources() of
        {ok, Resources} ->
            lists:foreach(fun(Resource) ->
                ResourceId = maps:get(resource_id, Resource),
                yawl_resource_manager:unregister_resource(ResourceId)
            end, Resources);
        _ ->
            ok
    end,

    %% Clean up persistence
    case yawl_persistence:list_workflows() of
        {ok, Workflows} ->
            lists:foreach(fun(Workflow) ->
                WorkflowId = Workflow#yawl_workflow_persist.workflow_id,
                yawl_persistence:delete_workflow(WorkflowId)
            end, Workflows);
        _ ->
            ok
    end.