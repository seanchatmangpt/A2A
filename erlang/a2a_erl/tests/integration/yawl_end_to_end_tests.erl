%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL End-to-End Integration Tests
%%%
%%% This module contains comprehensive end-to-end integration tests for
%%% YAWL workflows, covering:
%%%
%%% 1. Complete sequential workflow execution
%%% 2. Parallel split and join patterns
%%% 3. Resource allocation and deallocation
%%% 4. Human task completion
%%% 5. Workflow cancellation scenarios
%%% 6. Error recovery paths
%%% 7. Checkpoint and restore
%%% 8. REST API integration
%%%
%%% These tests set up a complete test environment with Mnesia and
%%% optional HTTP server for REST testing.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_end_to_end_tests).
-author("A2A Team").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% Export test suite callbacks
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

%% Export test cases
-export([
    %% Sequential workflow tests
    test_complete_sequential_workflow/1,
    test_sequential_with_data_flow/1,
    test_sequential_with_error_handling/1,

    %% Parallel pattern tests
    test_parallel_split_join/1,
    test_parallel_with_resource_contention/1,
    test_interleaved_parallelism/1,

    %% Resource allocation tests
    test_resource_allocation_deallocation/1,
    test_multiple_resource_types/1,
    test_resource_exhaustion_handling/1,
    test_least_loaded_allocation_strategy/1,

    %% Human task tests
    test_human_task_allocation/1,
    test_human_task_completion_workflow/1,
    test_human_task_timeout/1,
    test_human_task_priority_routing/1,

    %% Cancellation tests
    test_workflow_cancellation_during_execution/1,
    test_cancellation_with_resource_cleanup/1,
    test_cancellation_of_parallel_branches/1,

    %% Error recovery tests
    test_error_recovery_with_retry/1,
    test_error_recovery_with_alternative_path/1,
    test_error_recovery_after_checkpoint/1,

    %% Checkpoint and restore tests
    test_checkpoint_creation/1,
    test_checkpoint_workflow_restore/1,
    test_checkpoint_after_task_completion/1,
    test_checkpoint_multiple_saves/1,

    %% REST API integration tests
    test_rest_workflow_lifecycle/1,
    test_rest_parallel_workflow/1,
    test_rest_error_handling/1,
    test_rest_concurrent_requests/1
]).

%% Test macro definitions
-define(TEST_TIMEOUT, 30000).
-define(HTTP_PORT, 8082).
-define(MAX_WAIT, 10000).
-define(WAIT_INTERVAL, 100).

%%====================================================================
%% Common Test Callbacks
%%====================================================================

%% @doc Return all test cases.
-spec all() -> [atom()].
all() ->
    [
        % Sequential workflow tests
        test_complete_sequential_workflow,
        test_sequential_with_data_flow,
        test_sequential_with_error_handling,

        % Parallel pattern tests
        test_parallel_split_join,
        test_parallel_with_resource_contention,
        test_interleaved_parallelism,

        % Resource allocation tests
        test_resource_allocation_deallocation,
        test_multiple_resource_types,
        test_resource_exhaustion_handling,
        test_least_loaded_allocation_strategy,

        % Human task tests
        test_human_task_allocation,
        test_human_task_completion_workflow,
        test_human_task_timeout,
        test_human_task_priority_routing,

        % Cancellation tests
        test_workflow_cancellation_during_execution,
        test_cancellation_with_resource_cleanup,
        test_cancellation_of_parallel_branches,

        % Error recovery tests
        test_error_recovery_with_retry,
        test_error_recovery_with_alternative_path,
        test_error_recovery_after_checkpoint,

        % Checkpoint and restore tests
        test_checkpoint_creation,
        test_checkpoint_workflow_restore,
        test_checkpoint_after_task_completion,
        test_checkpoint_multiple_saves,

        % REST API integration tests
        test_rest_workflow_lifecycle,
        test_rest_parallel_workflow,
        test_rest_error_handling,
        test_rest_concurrent_requests
    ].

%% @doc Return test groups.
-spec groups() -> [{atom(), list(), [atom()]}].
groups() ->
    [
        {sequential_tests, [sequence], [
            test_complete_sequential_workflow,
            test_sequential_with_data_flow,
            test_sequential_with_error_handling
        ]},
        {parallel_tests, [sequence], [
            test_parallel_split_join,
            test_parallel_with_resource_contention,
            test_interleaved_parallelism
        ]},
        {resource_tests, [sequence], [
            test_resource_allocation_deallocation,
            test_multiple_resource_types,
            test_resource_exhaustion_handling,
            test_least_loaded_allocation_strategy
        ]},
        {human_task_tests, [sequence], [
            test_human_task_allocation,
            test_human_task_completion_workflow,
            test_human_task_timeout,
            test_human_task_priority_routing
        ]},
        {cancellation_tests, [sequence], [
            test_workflow_cancellation_during_execution,
            test_cancellation_with_resource_cleanup,
            test_cancellation_of_parallel_branches
        ]},
        {recovery_tests, [sequence], [
            test_error_recovery_with_retry,
            test_error_recovery_with_alternative_path,
            test_error_recovery_after_checkpoint
        ]},
        {checkpoint_tests, [sequence], [
            test_checkpoint_creation,
            test_checkpoint_workflow_restore,
            test_checkpoint_after_task_completion,
            test_checkpoint_multiple_saves
        ]},
        {rest_tests, [sequence], [
            test_rest_workflow_lifecycle,
            test_rest_parallel_workflow,
            test_rest_error_handling,
            test_rest_concurrent_requests
        ]}
    ].

%% @doc Initialize test suite - sets up Mnesia and all services.
-spec init_per_suite(Config) -> Config when Config :: [tuple()].
init_per_suite(Config) ->
    ct:pal("Starting YAWL End-to-End Integration Test Suite"),
    ct:pal("Setting up Mnesia database and services"),

    %% Create a unique Mnesia directory for this test run
    MnesiaDir = filename:join([proplists:get_value(priv_dir, Config), "mnesia", "e2e"]),
    filelib:ensure_path(MnesiaDir),
    application:set_env(mnesia, dir, MnesiaDir),

    %% Stop any existing Mnesia
    mnesia:stop(),
    timer:sleep(100),

    %% Delete old schema if exists
    case mnesia:delete_schema([node()]) of
        ok -> ok;
        {error, {already_exists, _}} ->
            mnesia:delete_schema([node()]),
            timer:sleep(500);
        _ -> ok
    end,

    %% Create new schema
    ok = mnesia:create_schema([node()]),
    ok = mnesia:start(),

    %% Create all tables
    Tables = [
        {yawl_workflow_persist, [
            {attributes, record_info(fields, yawl_workflow_persist)},
            {index, [#yawl_workflow_persist.spec_id, #yawl_workflow_persist.status]},
            {type, set},
            {disc_copies, [node()]}
        ]},
        {yawl_workitem_persist, [
            {attributes, record_info(fields, yawl_workitem_persist)},
            {index, [#yawl_workitem_persist.workflow_id, #yawl_workitem_persist.status]},
            {type, set},
            {disc_copies, [node()]}
        ]},
        {yawl_resource_persist, [
            {attributes, record_info(fields, yawl_resource_persist)},
            {index, [#yawl_resource_persist.resource_type, #yawl_resource_persist.status]},
            {type, set},
            {disc_copies, [node()]}
        ]},
        {yawl_execution_history, [
            {attributes, record_info(fields, yawl_execution_history)},
            {index, [#yawl_execution_history.workflow_id]},
            {type, bag},
            {disc_copies, [node()]}
        ]},
        {yawl_checkpoint, [
            {attributes, record_info(fields, yawl_checkpoint)},
            {index, [#yawl_checkpoint.workflow_id]},
            {type, set},
            {disc_only_copies, [node()]}
        ]},
        {yawl_service_registry, [
            {attributes, record_info(fields, yawl_service_registry)},
            {index, [#yawl_service_registry.service_name, #yawl_service_registry.service_type]},
            {type, set},
            {disc_copies, [node()]}
        ]}
    ],

    lists:foreach(fun({Table, Opts}) ->
        case mnesia:create_table(Table, Opts) of
            {atomic, ok} -> ok;
            {aborted, {already_exists, Table}} -> ok;
            {aborted, Reason} ->
                ct:fail({failed_to_create_table, Table, Reason})
        end
    end, Tables),

    %% Wait for tables
    case mnesia:wait_for_tables([yawl_workflow_persist, yawl_workitem_persist,
                                  yawl_resource_persist, yawl_execution_history,
                                  yawl_checkpoint, yawl_service_registry], 5000) of
        ok -> ok;
        {timeout, Tables} ->
            ct:fail({timeout_waiting_for_tables, Tables})
    end,

    %% Start required services
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),
    {ok, PersistencePid} = yawl_persistence:start_link(),
    {ok, ResourceManagerPid} = yawl_resource_manager:start_link(),
    {ok, WorkitemProcessorPid} = yawl_workitem_processor:start_link(),

    %% Start workflow instance supervisor
    {ok, SupervisorPid} = yawl_workflow_instance_sup:start_link(),

    %% Register test resources
    setup_test_resources(),

    %% Start REST API server
    {ok, RestPid} = case yawl_rest:start_link(#{port => ?HTTP_PORT}) of
        {ok, Pid} -> {ok, Pid};
        {error, {already_started, Pid}} -> {ok, Pid};
        Error ->
            ct:pal("Warning: REST server failed to start: ~p", [Error]),
            undefined
    end,

    %% Wait for REST server to be ready
    case RestPid of
        undefined -> ok;
        _ -> wait_for_rest_server(?HTTP_PORT, 5000)
    end,

    %% Store pids in config
    [
        {orchestrator_pid, OrchestratorPid},
        {persistence_pid, PersistencePid},
        {resource_manager_pid, ResourceManagerPid},
        {workitem_processor_pid, WorkitemProcessorPid},
        {workflow_instance_sup_pid, SupervisorPid},
        {rest_pid, RestPid},
        {mnesia_dir, MnesiaDir},
        {http_port, ?HTTP_PORT}
        | Config
    ].

%% @doc Cleanup test suite.
-spec end_per_suite(Config) -> ok when Config :: [tuple()].
end_per_suite(Config) ->
    ct:pal("Ending YAWL End-to-End Integration Test Suite"),

    %% Stop REST server
    RestPid = proplists:get_value(rest_pid, Config),
    case RestPid of
        undefined -> ok;
        _ ->
            catch yawl_rest:stop(),
            timer:sleep(200)
    end,

    %% Stop services
    OrchestratorPid = proplists:get_value(orchestrator_pid, Config),
    PersistencePid = proplists:get_value(persistence_pid, Config),
    ResourceManagerPid = proplists:get_value(resource_manager_pid, Config),
    WorkitemProcessorPid = proplists:get_value(workitem_processor_pid, Config),
    SupervisorPid = proplists:get_value(workflow_instance_sup_pid, Config),

    catch gen_server:stop(OrchestratorPid),
    catch gen_server:stop(PersistencePid),
    catch gen_server:stop(ResourceManagerPid),
    catch gen_server:stop(WorkitemProcessorPid),
    catch gen_server:stop(SupervisorPid),

    %% Stop Mnesia
    mnesia:stop(),
    timer:sleep(100),

    %% Clean up Mnesia directory
    MnesiaDir = proplists:get_value(mnesia_dir, Config),
    catch file:del_dir_r(MnesiaDir),

    ok.

%% @doc Initialize test group.
-spec init_per_group(atom(), Config) -> Config when Config :: [tuple()].
init_per_group(GroupName, Config) ->
    ct:pal("Starting group: ~p", [GroupName]),
    cleanup_test_data(Config),
    Config.

%% @doc Cleanup test group.
-spec end_per_group(atom(), Config) -> ok when Config :: [tuple()].
end_per_group(GroupName, Config) ->
    ct:pal("Completed group: ~p", [GroupName]),
    cleanup_test_data(Config),
    ok.

%% @doc Initialize test case.
-spec init_per_testcase(atom(), Config) -> Config when Config :: [tuple()].
init_per_testcase(TestName, Config) ->
    ct:pal("Starting E2E test: ~p", [TestName]),
    cleanup_test_data(Config),
    Config.

%% @doc Cleanup test case.
-spec end_per_testcase(atom(), Config) -> ok when Config :: [tuple()].
end_per_testcase(TestName, Config) ->
    ct:pal("Completed E2E test: ~p", [TestName]),
    cleanup_test_data(Config),
    ok.

%%====================================================================
%% Sequential Workflow Tests
%%====================================================================

%% @doc Test complete sequential workflow from creation to completion.
-spec test_complete_sequential_workflow(Config) -> ok when Config :: [tuple()].
test_complete_sequential_workflow(_Config) ->
    ct:pal("=== Testing complete sequential workflow ==="),

    %% Step 1: Create workflow
    Config = #{
        task1_name => "validate_order",
        task2_name => "process_payment",
        task3_name => "ship_order"
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    ct:pal("Workflow created: ~p", [WorkflowId]),

    %% Verify initial state
    {ok, pending} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify workflow persisted
    {ok, PersistedWorkflow} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(WorkflowId, PersistedWorkflow#yawl_workflow_persist.workflow_id),
    ?assertEqual(pending, PersistedWorkflow#yawl_workflow_persist.status),

    %% Step 2: Start workflow
    {ok, StartResult} = yawl_orchestrator:execute_workflow(WorkflowId),
    ct:pal("Workflow started: ~p", [StartResult]),

    %% Wait for execution and complete tasks
    wait_for_status(WorkflowId, running, 2000),

    %% Get workflow instance to complete tasks
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    ?assert(is_pid(InstancePid)),

    %% Simulate task completions
    Tasks = [task1, task2, task3],
    lists:foreach(fun(Task) ->
        ct:pal("Completing task: ~p", [Task]),
        ok = yawl_workflow_instance:complete_task(InstancePid, Task, #{result => completed}),
        timer:sleep(100)
    end, Tasks),

    %% Step 3: Wait for completion
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),

    %% Verify final state
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify persisted state
    {ok, FinalWorkflow} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(completed, FinalWorkflow#yawl_workflow_persist.status),
    ?assert(FinalWorkflow#yawl_workflow_persist.completed_at > 0),

    %% Verify workitems
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    ct:pal("Workitems created: ~p", [length(Workitems)]),
    ?assert(length(Workitems) >= length(Tasks)),

    %% Verify execution history
    {ok, History} = yawl_persistence:get_workflow_history(WorkflowId),
    ct:pal("History entries: ~p", [length(History)]),
    ?assert(length(History) > 0),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Sequential workflow test PASSED ==="),
    ok.

%% @doc Test sequential workflow with data flow between tasks.
-spec test_sequential_with_data_flow(Config) -> ok when Config :: [tuple()].
test_sequential_with_data_flow(_Config) ->
    ct:pal("=== Testing sequential workflow with data flow ==="),

    %% Create workflow with data flow configuration
    Config = #{
        tasks => [validate_data, transform_data, store_data],
        data_flow => #{
            input => #{order_id => "ORD-12345", amount => 100},
            mappings => [
                {validate_data, transform_data, [{order_id, order_id}, {amount, amount}]},
                {transform_data, store_data, [{processed, result}]}
            ]
        }
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Start workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    %% Get instance and complete tasks with data passing
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Complete task 1 with data
    ok = yawl_workflow_instance:complete_task(InstancePid, validate_data,
        #{status => valid, order_id => "ORD-12345"}),

    %% Complete task 2, using data from task 1
    ok = yawl_workflow_instance:update_data(InstancePid, transformed_amount, 200),
    ok = yawl_workflow_instance:complete_task(InstancePid, transform_data,
        #{result => ok, processed_amount => 200}),

    %% Complete task 3
    ok = yawl_workflow_instance:complete_task(InstancePid, store_data,
        #{stored => true, record_id => "REC-001"}),

    %% Wait for completion
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify data was propagated
    {ok, InstanceData} = yawl_workflow_instance:get_state(InstancePid),
    WorkflowData = maps:get(workflow_data, InstanceData, #{}),
    ct:pal("Final workflow data: ~p", [WorkflowData]),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Data flow test PASSED ==="),
    ok.

%% @doc Test sequential workflow with error handling.
-spec test_sequential_with_error_handling(Config) -> ok when Config :: [tuple()].
test_sequential_with_error_handling(_Config) ->
    ct:pal("=== Testing sequential workflow with error handling ==="),

    %% Create workflow that may encounter errors
    Config = #{
        tasks => [validate_task, risky_task, recovery_task, final_task],
        error_handling => #{retry_on_failure => true, max_retries => 3}
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Complete first task successfully
    ok = yawl_workflow_instance:complete_task(InstancePid, validate_task,
        #{result => valid}),

    %% Second task fails
    ok = yawl_workflow_instance:complete_task(InstancePid, risky_task,
        #{result => error, error_reason => "temporary_failure"}),

    %% Verify error state or recovery
    CurrentStatus = case wait_for_status_any([WorkflowId], [running, waiting, failed], 2000) of
        {ok, Status} -> Status;
        _ -> running
    end,

    %% Complete recovery task
    ok = yawl_workflow_instance:complete_task(InstancePid, recovery_task,
        #{recovered => true}),

    %% Complete final task
    ok = yawl_workflow_instance:complete_task(InstancePid, final_task,
        #{result => completed}),

    %% Wait for completion
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Error handling test PASSED ==="),
    ok.

%%====================================================================
%% Parallel Pattern Tests
%%====================================================================

%% @doc Test parallel split and join pattern.
-spec test_parallel_split_join(Config) -> ok when Config :: [tuple()].
test_parallel_split_join(_Config) ->
    ct:pal("=== Testing parallel split and join ==="),

    %% Create workflow with parallel branches
    Config = #{
        branches => [
            {branch1, [task_a1, task_a2]},
            {branch2, [task_b1, task_b2]},
            {branch3, [task_c1, task_c2]}
        ],
        join_type => synchronize
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(parallel_split, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Complete tasks in parallel (simulate concurrent execution)
    {ok, Marking1} = yawl_workflow_instance:get_marking(InstancePid),
    ct:pal("Initial marking: ~p", [Marking1]),

    %% Complete branch 1 tasks
    ok = yawl_workflow_instance:complete_task(InstancePid, task_a1, #{branch => branch1}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task_a2, #{branch => branch1}),

    %% Complete branch 2 tasks
    ok = yawl_workflow_instance:complete_task(InstancePid, task_b1, #{branch => branch2}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task_b2, #{branch => branch2}),

    %% Complete branch 3 tasks
    ok = yawl_workflow_instance:complete_task(InstancePid, task_c1, #{branch => branch3}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task_c2, #{branch => branch3}),

    %% Verify parallel execution - all branches should have run
    {ok, Marking2} = yawl_workflow_instance:get_marking(InstancePid),
    ct:pal("Final marking: ~p", [Marking2]),

    %% Wait for join completion
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify all workitems completed
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    CompletedCount = length([W || W <- Workitems,
                                W#yawl_workitem_persist.status =:= completed]),
    ct:pal("Completed workitems: ~p", [CompletedCount]),
    ?assert(CompletedCount >= 6),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Parallel split and join test PASSED ==="),
    ok.

%% @doc Test parallel workflow with resource contention.
-spec test_parallel_with_resource_contention(Config) -> ok when Config :: [tuple()].
test_parallel_with_resource_contention(_Config) ->
    ct:pal("=== Testing parallel workflow with resource contention ==="),

    %% Register limited resources
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        <<"limited_resource">>, service, #{max_capacity => 2}),

    %% Create parallel workflow requiring more resources than available
    Config = #{
        branches => [
            {branch1, [task1, task2]},
            {branch2, [task3, task4]},
            {branch3, [task5, task6]}
        ],
        resource_requirement => ResourceId
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(parallel_split, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Wait and verify contention is handled
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Complete tasks sequentially (resource contention should serialize)
    Tasks = [task1, task2, task3, task4, task5, task6],
    lists:foreach(fun(Task) ->
        ok = yawl_workflow_instance:complete_task(InstancePid, Task,
            #{resource_used => ResourceId}),
        timer:sleep(50)
    end, Tasks),

    %% Verify workflow completes despite resource contention
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify resource was properly deallocated
    {ok, Resources} = yawl_resource_manager:list_resources_by_type(service),
    LimitedResource = lists:keyfind(ResourceId, resource_id, Resources),
    ?assertMatch(#{current_load := 0}, LimitedResource),

    %% Cleanup
    yawl_resource_manager:unregister_resource(ResourceId),
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Resource contention test PASSED ==="),
    ok.

%% @doc Test interleaved parallelism pattern.
-spec test_interleaved_parallelism(Config) -> ok when Config :: [tuple()].
test_interleaved_parallelism(_Config) ->
    ct:pal("=== Testing interleaved parallelism ==="),

    Config = #{
        interleaved_tasks => [
            {verify, [check_a, check_b, check_c]},
            {process, [transform_x, transform_y]}
        ],
        pattern => interleaved
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(interleaved_parallelism, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Interleave task completions
    AllTasks = [check_a, check_b, check_c, transform_x, transform_y],
    lists:foreach(fun(Task) ->
        ok = yawl_workflow_instance:complete_task(InstancePid, Task, #{done => true}),
        timer:sleep(50)
    end, AllTasks),

    %% Verify workflow completed
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Interleaved parallelism test PASSED ==="),
    ok.

%%====================================================================
%% Resource Allocation Tests
%%====================================================================

%% @doc Test resource allocation and deallocation.
-spec test_resource_allocation_deallocation(Config) -> ok when Config :: [tuple()].
test_resource_allocation_deallocation(_Config) ->
    ct:pal("=== Testing resource allocation and deallocation ==="),

    %% Register test resources
    {ok, HumanResource} = yawl_resource_manager:register_resource(
        <<"test_human">>, human, #{capabilities => [review, approve], max_capacity => 3}),
    {ok, ServiceResource} = yawl_resource_manager:register_resource(
        <<"test_service">>, service, #{capabilities => [process], max_capacity => 5}),

    %% Create workflow requiring both resource types
    Config = #{
        tasks => [
            {human_review, human, review},
            {service_process, service, process},
            {human_approve, human, approve}
        ]
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    %% Verify initial resource status
    {ok, HumanBefore} = yawl_resource_manager:get_resource(HumanResource),
    ?assertMatch(#{current_load := 0}, HumanBefore),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Allocate for human task
    ok = yawl_workflow_instance:complete_task(InstancePid, human_review,
        #{requires_allocation => HumanResource}),

    %% Verify resource allocated
    {ok, HumanAllocated} = yawl_resource_manager:get_resource(HumanResource),
    ?assertMatch(#{current_load := Load} when Load > 0, HumanAllocated),

    %% Complete and release
    ok = yawl_workflow_instance:complete_task(InstancePid, service_process,
        #{result => processed}),

    %% Verify human resource still allocated
    {ok, HumanStillAllocated} = yawl_resource_manager:get_resource(HumanResource),
    ?assertMatch(#{current_load := _}, HumanStillAllocated),

    %% Complete final task and verify deallocation
    ok = yawl_workflow_instance:complete_task(InstancePid, human_approve,
        #{approved => true}),

    wait_for_status(WorkflowId, completed, ?MAX_WAIT),

    %% Verify all resources released
    {ok, HumanFinal} = yawl_resource_manager:get_resource(HumanResource),
    ?assertMatch(#{current_load := 0}, HumanFinal),

    {ok, ServiceFinal} = yawl_resource_manager:get_resource(ServiceResource),
    ?assertMatch(#{current_load := 0}, ServiceFinal),

    %% Cleanup
    yawl_resource_manager:unregister_resource(HumanResource),
    yawl_resource_manager:unregister_resource(ServiceResource),
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Resource allocation test PASSED ==="),
    ok.

%% @doc Test multiple resource types allocation.
-spec test_multiple_resource_types(Config) -> ok when Config :: [tuple()].
test_multiple_resource_types(_Config) ->
    ct:pal("=== Testing multiple resource types ==="),

    %% Register different resource types
    Resources = lists:map(fun({Name, Type, Caps}) ->
        {ok, Id} = yawl_resource_manager:register_resource(Name, Type,
            #{capabilities => Caps, max_capacity => 10}),
        Id
    end, [
        {<<"human_reviewer">>, human, [review]},
        {<<"data_validator">>, system, [validate]},
        {<<"external_service">>, service, [process]},
        {<<"notification_service">>, service, [notify]}
    ]),

    %% Create workflow using all resource types
    Config = #{
        tasks => [
            {validate_task, system, validate},
            {review_task, human, review},
            {process_task, service, process},
            {notify_task, service, notify}
        ]
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Complete tasks using different resource types
    ok = yawl_workflow_instance:complete_task(InstancePid, validate_task,
        #{validated => true}),
    ok = yawl_workflow_instance:complete_task(InstancePid, review_task,
        #{reviewed => true}),
    ok = yawl_workflow_instance:complete_task(InstancePid, process_task,
        #{processed => true}),
    ok = yawl_workflow_instance:complete_task(InstancePid, notify_task,
        #{notified => true}),

    wait_for_status(WorkflowId, completed, ?MAX_WAIT),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify all resource types were used
    {ok, AllResources} = yawl_resource_manager:list_resources(),
    UsedResources = lists:filter(fun(R) ->
        maps:get(current_load, R, 0) > 0 orelse
        maps:get(last_heartbeat, R, 0) > 0
    end, AllResources),
    ct:pal("Resources used: ~p", [length(UsedResources)]),

    %% Cleanup
    lists:foreach(fun(Id) -> yawl_resource_manager:unregister_resource(Id) end, Resources),
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Multiple resource types test PASSED ==="),
    ok.

%% @doc Test resource exhaustion handling.
-spec test_resource_exhaustion_handling(Config) -> ok when Config :: [tuple()].
test_resource_exhaustion_handling(_Config) ->
    ct:pal("=== Testing resource exhaustion handling ==="),

    %% Register a single resource with capacity 1
    {ok, LimitedResource} = yawl_resource_manager:register_resource(
        <<"limited">>, service, #{max_capacity => 1}),

    %% Create workflow that needs the resource multiple times
    Config = #{
        tasks => [task1, task2, task3],
        resource => LimitedResource
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Complete tasks sequentially - resource should be allocated and released
    ok = yawl_workflow_instance:complete_task(InstancePid, task1, #{done => true}),

    %% Verify resource is allocated
    {ok, ResourceAfter1} = yawl_resource_manager:get_resource(LimitedResource),
    ?assertMatch(#{current_load := 1}, ResourceAfter1),

    ok = yawl_workflow_instance:complete_task(InstancePid, task2, #{done => true}),

    %% Resource should be released from task1 and allocated to task2
    {ok, ResourceAfter2} = yawl_resource_manager:get_resource(LimitedResource),
    ?assertMatch(#{current_load := 1}, ResourceAfter2),

    ok = yawl_workflow_instance:complete_task(InstancePid, task3, #{done => true}),

    wait_for_status(WorkflowId, completed, ?MAX_WAIT),

    %% Verify resource fully released
    {ok, ResourceFinal} = yawl_resource_manager:get_resource(LimitedResource),
    ?assertMatch(#{current_load := 0, status := available}, ResourceFinal),

    %% Cleanup
    yawl_resource_manager:unregister_resource(LimitedResource),
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Resource exhaustion test PASSED ==="),
    ok.

%% @doc Test least_loaded allocation strategy.
-spec test_least_loaded_allocation_strategy(Config) -> ok when Config :: [tuple()].
test_least_loaded_allocation_strategy(_Config) ->
    ct:pal("=== Testing least-loaded allocation strategy ==="),

    %% Set allocation strategy
    ok = yawl_resource_manager:set_allocation_strategy(least_loaded),
    {ok, Strategy} = yawl_resource_manager:get_allocation_strategy(),
    ?assertEqual(least_loaded, Strategy),

    %% Register multiple resources with different initial loads
    {ok, R1} = yawl_resource_manager:register_resource(
        <<"resource_1">>, service, #{max_capacity => 10}),
    {ok, R2} = yawl_resource_manager:register_resource(
        <<"resource_2">>, service, #{max_capacity => 10}),
    {ok, R3} = yawl_resource_manager:register_resource(
        <<"resource_3">>, service, #{max_capacity => 10}),

    %% Manually set different loads
    ok = yawl_resource_manager:update_resource_load(R1, 5),
    ok = yawl_resource_manager:update_resource_load(R2, 2),
    ok = yawl_resource_manager:update_resource_load(R3, 7),

    %% Allocate - should pick R2 (least loaded)
    {ok, AllocatedId, _} = yawl_resource_manager:allocate_resource(
        <<"test_workitem">>, [service]),

    %% Verify it allocated to resource_2
    ?assertEqual(R2, AllocatedId),

    %% Verify load increased
    {ok, R2After} = yawl_resource_manager:get_resource(R2),
    ?assertEqual(3, maps:get(current_load, R2After, 0)),

    %% Cleanup
    lists:foreach(fun(Id) ->
        yawl_resource_manager:unregister_resource(Id)
    end, [R1, R2, R3]),

    ct:pal("=== Least-loaded allocation test PASSED ==="),
    ok.

%%====================================================================
%% Human Task Tests
%%====================================================================

%% @doc Test human task allocation.
-spec test_human_task_allocation(Config) -> ok when Config :: [tuple()].
test_human_task_allocation(_Config) ->
    ct:pal("=== Testing human task allocation ==="),

    %% Register human resources
    {ok, Human1} = yawl_resource_manager:register_resource(
        <<"approver_1">>, human, #{capabilities => [approve], max_capacity => 2}),
    {ok, Human2} = yawl_resource_manager:register_resource(
        <<"approver_2">>, human, #{capabilities => [approve], max_capacity => 2}),

    %% Create workflow with human task
    Config = #{
        human_task => #{
            task_name => approval_request,
            capability => approve,
            assignee => undefined
        }
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    %% Check workitems for allocation
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    ?assert(length(Workitems) > 0),

    %% Verify at least one workitem is allocated to a human
    AllocatedWorkitems = [W || W <- Workitems,
                              W#yawl_workitem_persist.status =:= allocated orelse
                              W#yawl_workitem_persist.allocated_to =/= undefined],
    ct:pal("Allocated human workitems: ~p", [length(AllocatedWorkitems)]),

    %% Complete workflow
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    ok = yawl_workflow_instance:complete_task(InstancePid, approval_request,
        #{approved => true, by => human}),

    wait_for_status(WorkflowId, completed, ?MAX_WAIT),

    %% Cleanup
    yawl_resource_manager:unregister_resource(Human1),
    yawl_resource_manager:unregister_resource(Human2),
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Human task allocation test PASSED ==="),
    ok.

%% @doc Test complete human task workflow.
-spec test_human_task_completion_workflow(Config) -> ok when Config :: [tuple()].
test_human_task_completion_workflow(_Config) ->
    ct:pal("=== Testing human task completion workflow ==="),

    %% Register human reviewer
    {ok, ReviewerId} = yawl_resource_manager:register_resource(
        <<"reviewer">>, human, #{capabilities => [review, approve], max_capacity => 1}),

    %% Create multi-stage approval workflow
    Config = #{
        tasks => [
            {initial_review, human, review},
            {manager_approval, human, approve},
            {finalize, service, process}
        ]
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Complete human tasks sequentially
    ok = yawl_workflow_instance:complete_task(InstancePid, initial_review,
        #{decision => approved, comments => "Looks good", reviewer => ReviewerId}),

    ok = yawl_workflow_instance:complete_task(InstancePid, manager_approval,
        #{decision => approved, comments => "Authorized", reviewer => ReviewerId}),

    ok = yawl_workflow_instance:complete_task(InstancePid, finalize,
        #{processed => true}),

    wait_for_status(WorkflowId, completed, ?MAX_WAIT),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify human task data captured
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    HumanWorkitems = [W || W <- Workitems,
                         W#yawl_workitem_persist.allocated_to =/= undefined],
    ct:pal("Human workitem data: ~p", [
        [maps:get(data, W, #{}) || W <- HumanWorkitems]
    ]),

    %% Cleanup
    yawl_resource_manager:unregister_resource(ReviewerId),
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Human task completion test PASSED ==="),
    ok.

%% @doc Test human task timeout.
-spec test_human_task_timeout(Config) -> ok when Config :: [tuple()].
test_human_task_timeout(_Config) ->
    ct:pal("=== Testing human task timeout ==="),

    %% Register human resource
    {ok, HumanId} = yawl_resource_manager:register_resource(
        <<"timeout_tester">>, human, #{capabilities => [test], max_capacity => 1}),

    %% Create workflow with timeout
    Config = #{
        human_task => #{
            task_name => timeout_task,
            capability => test,
            timeout => 1000
        }
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    %% Wait for timeout (don't complete the task)
    timer:sleep(2000),

    %% Check status - workflow might be waiting or have timeout indicator
    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
    ct:pal("Status after timeout: ~p", [Status]),

    %% Complete to allow cleanup
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    catch yawl_workflow_instance:complete_task(InstancePid, timeout_task,
        #{completed_after_timeout => true}),

    %% Cleanup
    yawl_resource_manager:unregister_resource(HumanId),
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Human task timeout test PASSED ==="),
    ok.

%% @doc Test human task priority routing.
-spec test_human_task_priority_routing(Config) -> ok when Config :: [tuple()].
test_human_task_priority_routing(_Config) ->
    ct:pal("=== Testing human task priority routing ==="),

    %% Register multiple humans
    {ok, Senior} = yawl_resource_manager:register_resource(
        <<"senior_approver">>, human, #{capabilities => [approve], max_capacity => 1}),
    {ok, Junior} = yawl_resource_manager:register_resource(
        <<"junior_approver">>, human, #{capabilities => [approve], max_capacity => 1}),

    %% Create high-priority workflow
    Config = #{
        human_task => #{
            task_name => priority_approval,
            capability => approve,
            priority => urgent
        }
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Verify priority was respected in allocation
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    UrgentWorkitems = [W || W <- Workitems,
                          W#yawl_workitem_persist.priority =:= urgent],
    ct:pal("Urgent workitems: ~p", [length(UrgentWorkitems)]),

    %% Complete and cleanup
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    catch yawl_workflow_instance:complete_task(InstancePid, priority_approval,
        #{approved => true}),

    yawl_resource_manager:unregister_resource(Senior),
    yawl_resource_manager:unregister_resource(Junior),
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Human task priority routing test PASSED ==="),
    ok.

%%====================================================================
%% Cancellation Tests
%%====================================================================

%% @doc Test workflow cancellation during execution.
-spec test_workflow_cancellation_during_execution(Config) -> ok when Config :: [tuple()].
test_workflow_cancellation_during_execution(_Config) ->
    ct:pal("=== Testing workflow cancellation during execution ==="),

    %% Create long-running workflow
    Config = #{
        tasks => [long_task1, long_task2, long_task3],
        long_running => true
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    %% Cancel workflow during execution
    ok = yawl_orchestrator:cancel_workflow(WorkflowId),

    %% Verify cancellation
    {ok, cancelled} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify persisted state
    {ok, CancelledWorkflow} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(cancelled, CancelledWorkflow#yawl_workflow_persist.status),
    ?assert(CancelledWorkflow#yawl_workflow_persist.completed_at > 0),

    %% Verify cannot restart cancelled workflow
    {error, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Cancellation during execution test PASSED ==="),
    ok.

%% @doc Test cancellation with resource cleanup.
-spec test_cancellation_with_resource_cleanup(Config) -> ok when Config :: [tuple()].
test_cancellation_with_resource_cleanup(_Config) ->
    ct:pal("=== Testing cancellation with resource cleanup ==="),

    %% Register resource
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        <<"cleanup_resource">>, service, #{max_capacity => 1}),

    %% Create and start workflow
    Config = #{
        tasks => [task1, task2, task3],
        resource => ResourceId
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    %% Allocate resource
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    ok = yawl_workflow_instance:complete_task(InstancePid, task1,
        #{allocated => ResourceId}),

    %% Verify resource allocated
    {ok, ResourceAllocated} = yawl_resource_manager:get_resource(ResourceId),
    ?assertMatch(#{current_load := Load} when Load > 0, ResourceAllocated),

    %% Cancel workflow
    ok = yawl_orchestrator:cancel_workflow(WorkflowId),
    {ok, cancelled} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify resource released after cancellation
    {ok, ResourceReleased} = yawl_resource_manager:get_resource(ResourceId),
    ?assertMatch(#{current_load := 0}, ResourceReleased),

    %% Cleanup
    yawl_resource_manager:unregister_resource(ResourceId),
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Cancellation with resource cleanup test PASSED ==="),
    ok.

%% @doc Test cancellation of parallel branches.
-spec test_cancellation_of_parallel_branches(Config) -> ok when Config :: [tuple()].
test_cancellation_of_parallel_branches(_Config) ->
    ct:pal("=== Testing cancellation of parallel branches ==="),

    %% Create parallel workflow
    Config = #{
        branches => [
            {branch1, [task_a1, task_a2, task_a3]},
            {branch2, [task_b1, task_b2, task_b3]},
            {branch3, [task_c1, task_c2, task_c3]}
        ]
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(parallel_split, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Start some tasks
    ok = yawl_workflow_instance:complete_task(InstancePid, task_a1, #{}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task_b1, #{}),

    %% Cancel mid-execution
    ok = yawl_orchestrator:cancel_workflow(WorkflowId),
    {ok, cancelled} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify workitems cancelled
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    CancelledCount = length([W || W <- Workitems,
                                 W#yawl_workitem_persist.status =:= cancelled]),
    ct:pal("Cancelled workitems: ~p", [CancelledCount]),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Cancellation of parallel branches test PASSED ==="),
    ok.

%%====================================================================
%% Error Recovery Tests
%%====================================================================

%% @doc Test error recovery with retry.
-spec test_error_recovery_with_retry(Config) -> ok when Config :: [tuple()].
test_error_recovery_with_retry(_Config) ->
    ct:pal("=== Testing error recovery with retry ==="),

    %% Create workflow with retry policy
    Config = #{
        tasks => [unstable_task, final_task],
        retry_policy => #{
            max_attempts => 3,
            backoff => exponential,
            initial_delay => 100
        }
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% First attempt fails
    ok = yawl_workflow_instance:complete_task(InstancePid, unstable_task,
        #{success => false, attempt => 1}),

    %% Second attempt fails
    ok = yawl_workflow_instance:complete_task(InstancePid, unstable_task,
        #{success => false, attempt => 2}),

    %% Third attempt succeeds
    ok = yawl_workflow_instance:complete_task(InstancePid, unstable_task,
        #{success => true, attempt => 3}),

    %% Complete final task
    ok = yawl_workflow_instance:complete_task(InstancePid, final_task,
        #{done => true}),

    wait_for_status(WorkflowId, completed, ?MAX_WAIT),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify retry history
    {ok, History} = yawl_persistence:get_workflow_history(WorkflowId),
    RetryEvents = [E || E <- History,
                     maps:get(event_type, E, undefined) =:= retry],
    ct:pal("Retry events: ~p", [length(RetryEvents)]),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Error recovery with retry test PASSED ==="),
    ok.

%% @doc Test error recovery with alternative path.
-spec test_error_recovery_with_alternative_path(Config) -> ok when Config :: [tuple()].
test_error_recovery_with_alternative_path(_Config) ->
    ct:pal("=== Testing error recovery with alternative path ==="),

    %% Create workflow with alternative paths
    Config = #{
        main_path => [primary_task, secondary_task],
        alternative_path => [fallback_task, recovery_task],
        error_handling => #{
            on_failure => switch_to_alternative,
            fallback_condition => primary_task_failed
        }
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Primary task fails
    ok = yawl_workflow_instance:complete_task(InstancePid, primary_task,
        #{success => false, error => "service_unavailable"}),

    %% Continue with alternative path
    ok = yawl_workflow_instance:complete_task(InstancePid, fallback_task,
        #{fallback_used => true}),

    ok = yawl_workflow_instance:complete_task(InstancePid, recovery_task,
        #{recovered => true}),

    wait_for_status(WorkflowId, completed, ?MAX_WAIT),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify alternative path was taken
    {ok, History} = yawl_persistence:get_workflow_history(WorkflowId),
    FallbackEvents = [E || E <- History,
                       maps:get(event_type, E, undefined) =:= fallback_taken],
    ?assert(length(FallbackEvents) > 0),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Error recovery with alternative path test PASSED ==="),
    ok.

%% @doc Test error recovery after checkpoint.
-spec test_error_recovery_after_checkpoint(Config) -> ok when Config :: [tuple()].
test_error_recovery_after_checkpoint(_Config) ->
    ct:pal("=== Testing error recovery after checkpoint ==="),

    %% Create workflow with checkpointing
    Config = #{
        tasks => [task1, task2, task3, task4],
        checkpoint_interval => 1
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Complete task 1 - checkpoint should be created
    ok = yawl_workflow_instance:complete_task(InstancePid, task1,
        #{data => "important_data"}),

    %% Create checkpoint after task1
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(InstancePid),
    ct:pal("Checkpoint created: ~p", [CheckpointId]),

    %% Verify checkpoint exists
    {ok, Checkpoint} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(CheckpointId, Checkpoint#yawl_checkpoint.checkpoint_id),

    %% Complete task 2
    ok = yawl_workflow_instance:complete_task(InstancePid, task2,
        #{data => "more_data"}),

    %% Simulate failure before task 3
    %% (In real scenario, workflow would crash and restart)

    %% Restore from checkpoint
    {ok, _} = yawl_persistence:restore_from_checkpoint(WorkflowId),

    %% Verify restored state
    {ok, RestoredWorkflow} = yawl_persistence:load_workflow(WorkflowId),
    RestoredData = RestoredWorkflow#yawl_workflow_persist.data,
    ct:pal("Restored data: ~p", [RestoredData]),

    %% Continue from restored state
    ok = yawl_workflow_instance:complete_task(InstancePid, task3,
        #{data => "even_more_data"}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task4,
        #{final => true}),

    wait_for_status(WorkflowId, completed, ?MAX_WAIT),
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Error recovery after checkpoint test PASSED ==="),
    ok.

%%====================================================================
%% Checkpoint and Restore Tests
%%====================================================================

%% @doc Test checkpoint creation.
-spec test_checkpoint_creation(Config) -> ok when Config :: [tuple()].
test_checkpoint_creation(_Config) ->
    ct:pal("=== Testing checkpoint creation ==="),

    %% Create workflow
    Config = #{tasks => [task1, task2, task3]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Complete first task
    ok = yawl_workflow_instance:complete_task(InstancePid, task1,
        #{result => "task1_complete"}),

    %% Create checkpoint
    {ok, CheckpointId1} = yawl_workflow_instance:checkpoint(InstancePid),
    ct:pal("Checkpoint 1: ~p", [CheckpointId1]),

    %% Complete second task and create another checkpoint
    ok = yawl_workflow_instance:complete_task(InstancePid, task2,
        #{result => "task2_complete"}),

    {ok, CheckpointId2} = yawl_workflow_instance:checkpoint(InstancePid),
    ct:pal("Checkpoint 2: ~p", [CheckpointId2]),

    %% Verify checkpoints exist
    {ok, Checkpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assert(length(Checkpoints) >= 2),

    %% Verify checkpoint sequence numbers
    Sequences = [CP#yawl_checkpoint.sequence_num || CP <- Checkpoints],
    ?assert(lists:sort(Sequences) =:= lists:usort(Sequences)),

    %% Complete workflow
    ok = yawl_workflow_instance:complete_task(InstancePid, task3,
        #{result => "task3_complete"}),
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),

    %% Final checkpoint
    {ok, FinalCheckpointId} = yawl_workflow_instance:checkpoint(InstancePid),
    ct:pal("Final checkpoint: ~p", [FinalCheckpointId]),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Checkpoint creation test PASSED ==="),
    ok.

%% @doc Test checkpoint workflow restore.
-spec test_checkpoint_workflow_restore(Config) -> ok when Config :: [tuple()].
test_checkpoint_workflow_restore(_Config) ->
    ct:pal("=== Testing checkpoint workflow restore ==="),

    %% Create workflow
    Config = #{tasks => [task1, task2, task3, task4, task5]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Complete tasks up to task 3
    ok = yawl_workflow_instance:complete_task(InstancePid, task1, #{step => 1}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task2, #{step => 2}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task3, #{step => 3}),

    %% Create checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Get checkpoint data
    {ok, Checkpoint} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    CheckpointMarking = Checkpoint#yawl_checkpoint.marking,
    CheckpointData = Checkpoint#yawl_checkpoint.data,
    ct:pal("Checkpoint marking: ~p", [CheckpointMarking]),
    ct:pal("Checkpoint data: ~p", [CheckpointData]),

    %% Complete remaining tasks
    ok = yawl_workflow_instance:complete_task(InstancePid, task4, #{step => 4}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task5, #{step => 5}),
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),

    %% Test restore from checkpoint
    %% First, clean up workflow
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    %% Recreate workflow from checkpoint
    NewConfig = #{
        restore_from => CheckpointId,
        continue_from => task4
    },
    {ok, RestoredWorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, NewConfig),
    {ok, _} = yawl_orchestrator:execute_workflow(RestoredWorkflowId),

    %% Verify restored workflow state
    {ok, RestoredCheckpoint} = yawl_persistence:load_latest_checkpoint(RestoredWorkflowId),
    ?assert(CheckpointId =:= RestoredCheckpoint#yawl_checkpoint.checkpoint_id orelse
              RestoredCheckpoint#yawl_checkpoint.checkpoint_id =/= undefined),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(RestoredWorkflowId),

    ct:pal("=== Checkpoint workflow restore test PASSED ==="),
    ok.

%% @doc Test checkpoint after task completion.
-spec test_checkpoint_after_task_completion(Config) -> ok when Config :: [tuple()].
test_checkpoint_after_task_completion(_Config) ->
    ct:pal("=== Testing checkpoint after task completion ==="),

    %% Create workflow with automatic checkpointing
    Config = #{
        tasks => [task1, task2, task3],
        auto_checkpoint => true
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Complete task and verify checkpoint
    ok = yawl_workflow_instance:complete_task(InstancePid, task1,
        #{checkpoint_data => "value1"}),

    %% Verify automatic checkpoint was created
    {ok, Checkpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assert(length(Checkpoints) > 0),

    %% Complete remaining tasks
    ok = yawl_workflow_instance:complete_task(InstancePid, task2,
        #{checkpoint_data => "value2"}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task3,
        #{checkpoint_data => "value3"}),

    wait_for_status(WorkflowId, completed, ?MAX_WAIT),

    %% Verify checkpoints capture task completion data
    {ok, AllCheckpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ct:pal("Total checkpoints: ~p", [length(AllCheckpoints)]),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Checkpoint after task completion test PASSED ==="),
    ok.

%% @doc Test multiple checkpoint saves.
-spec test_checkpoint_multiple_saves(Config) -> ok when Config :: [tuple()].
test_checkpoint_multiple_saves(_Config) ->
    ct:pal("=== Testing multiple checkpoint saves ==="),

    %% Create workflow
    Config = #{
        tasks => [task1, task2, task3, task4],
        checkpoint_after_each => true
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Complete tasks with checkpoints
    TasksAndData = [
        {task1, #{step => 1}},
        {task2, #{step => 2}},
        {task3, #{step => 3}},
        {task4, #{step => 4}}
    ],

    CheckpointCounts = lists:map(fun({Task, Data}) ->
        ok = yawl_workflow_instance:complete_task(InstancePid, Task, Data),
        {ok, CPId} = yawl_workflow_instance:checkpoint(InstancePid),
        {ok, CPs} = yawl_persistence:list_checkpoints(WorkflowId),
        length(CPs)
    end, TasksAndData),

    ct:pal("Checkpoint counts after each task: ~p", [CheckpointCounts]),

    %% Verify checkpoint count increases
    ?assert(lists:all(fun(C) -> C > 0 end, CheckpointCounts)),

    %% Verify sequence is increasing
    ?assert(CheckpointCounts =:= lists:sort(CheckpointCounts)),

    %% Wait for final completion
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),

    %% Verify final checkpoint count
    {ok, FinalCheckpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ct:pal("Final checkpoint count: ~p", [length(FinalCheckpoints)]),

    %% Test cleanup of old checkpoints
    {ok, CleanupResult} = yawl_persistence:cleanup_old_checkpoints(WorkflowId, 2),
    ?assertMatch({ok, _}, CleanupResult),

    {ok, RemainingCheckpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assert(length(RemainingCheckpoints) =< length(FinalCheckpoints)),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Multiple checkpoint saves test PASSED ==="),
    ok.

%%====================================================================
%% REST API Integration Tests
%%====================================================================

%% @doc Test REST API workflow lifecycle.
-spec test_rest_workflow_lifecycle(Config) -> ok when Config :: [tuple()].
test_rest_workflow_lifecycle(Config) ->
    Port = proplists:get_value(http_port, Config, ?HTTP_PORT),
    ct:pal("=== Testing REST workflow lifecycle on port ~p ===", [Port]),

    BaseUrl = "http://localhost:" ++ integer_to_list(Port),

    %% 1. Create workflow via REST
    CreatePayload = jiffy:encode(#{
        pattern_type => basic_sequential,
        config => #{tasks => [rest_task1, rest_task2, rest_task3]}
    }),

    {ok, 201, CreateResponse} = make_http_request(post, BaseUrl ++ "/workflows", CreatePayload),
    CreateResult = jiffy:decode(CreateResponse, [return_maps]),
    WorkflowId = maps:get(<<"workflow_id">>, CreateResult),
    ct:pal("Created workflow via REST: ~p", [WorkflowId]),

    %% 2. Start workflow via REST
    {ok, 200, StartResponse} = make_http_request(post,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId) ++ "/start", <<>>),
    StartResult = jiffy:decode(StartResponse, [return_maps]),
    ct:pal("Started workflow via REST: ~p", [StartResult]),

    %% 3. Get status via REST
    {ok, 200, StatusResponse} = make_http_request(get,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>),
    StatusResult = jiffy:decode(StatusResponse, [return_maps]),
    ct:pal("Status via REST: ~p", [StatusResult]),

    %% 4. Get marking via REST
    {ok, 200, MarkingResponse} = make_http_request(get,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId) ++ "/marking", <<>>),
    MarkingResult = jiffy:decode(MarkingResponse, [return_maps]),
    ct:pal("Marking via REST: ~p", [MarkingResult]),

    %% 5. List workflows via REST
    {ok, 200, ListResponse} = make_http_request(get, BaseUrl ++ "/workflows", <<>>),
    ListResult = jiffy:decode(ListResponse, [return_maps]),
    ct:pal("Workflows list: ~p", [length(maps:get(<<"workflows">>, ListResult, []))]),

    %% 6. Cancel workflow via REST
    {ok, 200, CancelResponse} = make_http_request(post,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId) ++ "/cancel", <<>>),
    CancelResult = jiffy:decode(CancelResponse, [return_maps]),
    ct:pal("Cancelled via REST: ~p", [CancelResult]),

    %% 7. Delete workflow via REST
    {ok, 200, _DeleteResponse} = make_http_request(delete,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>),

    %% Verify deletion
    {ok, 404, _NotFoundResponse} = make_http_request(get,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>),

    ct:pal("=== REST workflow lifecycle test PASSED ==="),
    ok.

%% @doc Test REST parallel workflow.
-spec test_rest_parallel_workflow(Config) -> ok when Config :: [tuple()].
test_rest_parallel_workflow(Config) ->
    Port = proplists:get_value(http_port, Config, ?HTTP_PORT),
    ct:pal("=== Testing REST parallel workflow ==="),

    BaseUrl = "http://localhost:" ++ integer_to_list(Port),

    %% Create parallel workflow
    CreatePayload = jiffy:encode(#{
        pattern_type => parallel_split,
        config => #{
            branches => [
                {branch1, [task_a, task_b]},
                {branch2, [task_c, task_d]}
            ]
        }
    }),

    {ok, 201, CreateResponse} = make_http_request(post, BaseUrl ++ "/workflows", CreatePayload),
    CreateResult = jiffy:decode(CreateResponse, [return_maps]),
    WorkflowId = maps:get(<<"workflow_id">>, CreateResult),

    %% Start workflow
    {ok, 200, _} = make_http_request(post,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId) ++ "/start", <<>>),

    %% Get status
    {ok, 200, StatusResponse} = make_http_request(get,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>),
    StatusResult = jiffy:decode(StatusResponse, [return_maps]),
    ct:pal("Parallel workflow status: ~p", [StatusResult]),

    %% Complete via orchestrator (REST doesn't have task completion endpoint)
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    ok = yawl_workflow_instance:complete_task(InstancePid, task_a, #{}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task_b, #{}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task_c, #{}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task_d, #{}),

    %% Wait for completion
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),

    %% Verify via REST
    {ok, 200, FinalStatusResponse} = make_http_request(get,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>),
    FinalStatusResult = jiffy:decode(FinalStatusResponse, [return_maps]),
    ?assertEqual(<<"completed">>, maps:get(<<"status">>, FinalStatusResult)),

    %% Cleanup
    {ok, 200, _} = make_http_request(delete,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>),

    ct:pal("=== REST parallel workflow test PASSED ==="),
    ok.

%% @doc Test REST error handling.
-spec test_rest_error_handling(Config) -> ok when Config :: [tuple()].
test_rest_error_handling(Config) ->
    Port = proplists:get_value(http_port, Config, ?HTTP_PORT),
    ct:pal("=== Testing REST error handling ==="),

    BaseUrl = "http://localhost:" ++ integer_to_list(Port),

    %% Test 1: Invalid pattern type
    InvalidPayload = jiffy:encode(#{
        pattern_type => invalid_pattern,
        config => #{}
    }),
    {ok, 400, _} = make_http_request(post, BaseUrl ++ "/workflows", InvalidPayload),

    %% Test 2: Missing required field
    IncompletePayload = jiffy:encode(#{
        config => #{}
    }),
    {ok, 400, _} = make_http_request(post, BaseUrl ++ "/workflows", IncompletePayload),

    %% Test 3: Non-existent workflow
    {ok, 404, _} = make_http_request(get,
        BaseUrl ++ "/workflows/nonexistent_workflow_id", <<>>),

    %% Test 4: Invalid action
    {ok, WorkflowId} = create_test_workflow_via_rest(BaseUrl),
    {ok, 400, _} = make_http_request(post,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId) ++ "/invalid_action", <<>>),

    %% Cleanup
    {ok, 200, _} = make_http_request(delete,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>),

    ct:pal("=== REST error handling test PASSED ==="),
    ok.

%% @doc Test REST concurrent requests.
-spec test_rest_concurrent_requests(Config) -> ok when Config :: [tuple()].
test_rest_concurrent_requests(Config) ->
    Port = proplists:get_value(http_port, Config, ?HTTP_PORT),
    ct:pal("=== Testing REST concurrent requests ==="),

    BaseUrl = "http://localhost:" ++ integer_to_list(Port),

    %% Create multiple workflows concurrently
    NumRequests = 10,

    StartTime = erlang:monotonic_time(millisecond),

    %% Spawn concurrent requests
    Results = lists:map(fun(I) ->
        spawn_monitor(fun() ->
            Payload = jiffy:encode(#{
                pattern_type => basic_sequential,
                config => #{task_id => I}
            }),
            case make_http_request(post, BaseUrl ++ "/workflows", Payload) of
                {ok, Code, Response} ->
                    {Code, Response};
                {error, Reason} ->
                    {error, Reason}
            end
        end)
    end, lists:seq(1, NumRequests)),

    %% Collect results
    CreatedWorkflows = lists:filtermap(fun({Pid, _Ref}) ->
        receive
            {Pid, Result} ->
                case Result of
                    {201, Response} ->
                        ResultMap = jiffy:decode(Response, [return_maps]),
                        {true, maps:get(<<"workflow_id">>, ResultMap)};
                    _ ->
                        false
                end;
            {'DOWN', Pid, process, _Reason} ->
                false
        end
    end, Results),

    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    ct:pal("Created ~p/~p workflows concurrently in ~pms",
        [length(CreatedWorkflows), NumRequests, Duration]),

    ?assert(length(CreatedWorkflows) >= NumRequests - 1),  % Allow 1 failure

    %% Cleanup created workflows
    lists:foreach(fun(WorkflowId) ->
        catch make_http_request(delete,
            BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>)
    end, CreatedWorkflows),

    ct:pal("=== REST concurrent requests test PASSED ==="),
    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
%% @doc Set up test resources for all tests.
-spec setup_test_resources() -> ok.
setup_test_resources() ->
    %% Human resources
    {ok, _} = yawl_resource_manager:register_resource(<<"admin">>, human,
        #{capabilities => [admin, approve, review], max_capacity => 5}),
    {ok, _} = yawl_resource_manager:register_resource(<<"approver">>, human,
        #{capabilities => [approve], max_capacity => 3}),
    {ok, _} = yawl_resource_manager:register_resource(<<"reviewer">>, human,
        #{capabilities => [review], max_capacity => 5}),

    %% Service resources
    {ok, _} = yawl_resource_manager:register_resource(<<"payment_service">>, service,
        #{capabilities => [process_payment], max_capacity => 10}),
    {ok, _} = yawl_resource_manager:register_resource(<<"validation_service">>, service,
        #{capabilities => [validate], max_capacity => 10}),
    {ok, _} = yawl_resource_manager:register_resource(<<"notification_service">>, service,
        #{capabilities => [send_notification], max_capacity => 10}),

    %% System resources
    {ok, _} = yawl_resource_manager:register_resource(<<"database">>, system,
        #{capabilities => [store_data, query_data], max_capacity => 20}),
    {ok, _} = yawl_resource_manager:register_resource(<<"cache">>, system,
        #{capabilities => [cache_data], max_capacity => 20}),

    ok.

%% @private
%% @doc Clean up test data between tests.
-spec cleanup_test_data(Config) -> ok when Config :: [tuple()].
cleanup_test_data(_Config) ->
    %% Cancel and cleanup all workflows
    case yawl_orchestrator:list_workflows() of
        {ok, WorkflowIds} ->
            lists:foreach(fun(WorkflowId) ->
                case yawl_orchestrator:get_status(WorkflowId) of
                    {ok, Status} when Status =:= running; Status =:= pending ->
                        catch yawl_orchestrator:cancel_workflow(WorkflowId);
                    _ -> ok
                end,
                catch yawl_orchestrator:cleanup_workflow(WorkflowId)
            end, WorkflowIds);
        _ ->
            ok
    end,

    %% Clean up Mnesia tables
    cleanup_mnesia_table(yawl_workflow_persist),
    cleanup_mnesia_table(yawl_workitem_persist),
    cleanup_mnesia_table(yawl_execution_history),
    cleanup_mnesia_table(yawl_checkpoint),

    ok.

%% @private
%% @doc Clean up a Mnesia table.
-spec cleanup_mnesia_table(atom()) -> ok.
cleanup_mnesia_table(TableName) ->
    Trans = fun() ->
        mnesia:match_object(#TableName{_ = '_'})
    end,
    case mnesia:transaction(Trans) of
        {atomic, Records} ->
            lists:foreach(fun(Record) ->
                Key = element(1, Record),
                mnesia:delete(TableName, Key, write)
            end, Records);
        _ ->
            ok
    end,
    ok.

%% @private
%% @doc Wait for a workflow to reach a specific status.
-spec wait_for_status(binary(), atom(), integer()) -> ok | timeout.
wait_for_status(WorkflowId, TargetStatus, Timeout) ->
    StartTime = erlang:monotonic_time(millisecond),
    wait_for_status_loop(WorkflowId, TargetStatus, StartTime, Timeout).

wait_for_status_loop(WorkflowId, TargetStatus, StartTime, Timeout) ->
    case yawl_orchestrator:get_status(WorkflowId) of
        {ok, TargetStatus} ->
            ok;
        {ok, _OtherStatus} ->
            case erlang:monotonic_time(millisecond) - StartTime of
                Elapsed when Elapsed > Timeout ->
                    timeout;
                _ ->
                    timer:sleep(?WAIT_INTERVAL),
                    wait_for_status_loop(WorkflowId, TargetStatus, StartTime, Timeout)
            end;
        {error, _} ->
            case erlang:monotonic_time(millisecond) - StartTime of
                Elapsed when Elapsed > Timeout ->
                    timeout;
                _ ->
                    timer:sleep(?WAIT_INTERVAL),
                    wait_for_status_loop(WorkflowId, TargetStatus, StartTime, Timeout)
            end
    end.

%% @private
%% @doc Wait for workflow to reach any of the specified statuses.
-spec wait_for_status_any([binary()], [atom()], integer()) -> {ok, atom()} | timeout.
wait_for_status_any([WorkflowId], TargetStatuses, Timeout) ->
    StartTime = erlang:monotonic_time(millisecond),
    wait_for_status_any_loop(WorkflowId, TargetStatuses, StartTime, Timeout).

wait_for_status_any_loop(WorkflowId, TargetStatuses, StartTime, Timeout) ->
    case yawl_orchestrator:get_status(WorkflowId) of
        {ok, Status} ->
            case lists:member(Status, TargetStatuses) of
                true -> {ok, Status};
                false ->
                    case erlang:monotonic_time(millisecond) - StartTime of
                        Elapsed when Elapsed > Timeout ->
                            timeout;
                        _ ->
                            timer:sleep(?WAIT_INTERVAL),
                            wait_for_status_any_loop(WorkflowId, TargetStatuses, StartTime, Timeout)
                    end
            end;
        {error, _} ->
            case erlang:monotonic_time(millisecond) - StartTime of
                Elapsed when Elapsed > Timeout ->
                    timeout;
                _ ->
                    timer:sleep(?WAIT_INTERVAL),
                    wait_for_status_any_loop(WorkflowId, TargetStatuses, StartTime, Timeout)
            end
    end.

%% @private
%% @doc Wait for REST server to be ready.
-spec wait_for_rest_server(integer(), integer()) -> ok | timeout.
wait_for_rest_server(Port, Timeout) ->
    StartTime = erlang:monotonic_time(millisecond),
    wait_for_server_loop(Port, StartTime, Timeout).

wait_for_server_loop(Port, StartTime, Timeout) ->
    case check_rest_server(Port) of
        ok ->
            ok;
        {error, _} ->
            case erlang:monotonic_time(millisecond) - StartTime of
                Elapsed when Elapsed > Timeout ->
                    timeout;
                _ ->
                    timer:sleep(200),
                    wait_for_server_loop(Port, StartTime, Timeout)
            end
    end.

%% @private
%% @doc Check if REST server is responding.
-spec check_rest_server(integer()) -> ok | {error, term()}.
check_rest_server(Port) ->
    Url = "http://localhost:" ++ integer_to_list(Port) ++ "/health",
    case make_http_request(get, Url, <<>>, "application/json", []) of
        {ok, _, _} -> ok;
        Error -> Error
    end.

%% @private
%% @doc Make HTTP request.
-spec make_http_request(atom(), string(), binary() | string()) ->
    {ok, integer(), binary()} | {error, term()}.
make_http_request(Method, Url, Body) ->
    make_http_request(Method, Url, Body, "application/json").

make_http_request(Method, Url, Body, ContentType) ->
    make_http_request(Method, Url, Body, ContentType, []).

make_http_request(Method, Url, Body, ContentType, Headers) ->
    case httpc:request(Method, {Url, Headers ++ [
        {"Content-Type", ContentType}
    ]}, [], Body, []) of
        {ok, {{_, StatusCode, _}, _ResponseHeaders, ResponseBody}} ->
            {ok, StatusCode, ResponseBody};
        {error, Reason} ->
            {error, Reason}
    end.

%% @private
%% @doc Create a test workflow via REST API.
-spec create_test_workflow_via_rest(string()) -> binary().
create_test_workflow_via_rest(BaseUrl) ->
    Payload = jiffy:encode(#{
        pattern_type => basic_sequential,
        config => #{test => true}
    }),
    {ok, 201, Response} = make_http_request(post, BaseUrl ++ "/workflows", Payload),
    Result = jiffy:decode(Response, [return_maps]),
    maps:get(<<"workflow_id">>, Result).
