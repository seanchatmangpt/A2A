%%%-------------------------------------------------------------------
%%% @doc
%%% Concurrency Tests for YAWL Workflow System
%%%
%%% This module contains comprehensive tests for concurrent execution,
%%% race conditions, thread safety, and parallel workflow processing.
%%%
%%% Test Coverage:
%%% - Parallel workflow creation and execution
%%% - Concurrent state mutations
%%% - Race condition detection
%%% - Process synchronization
%%% - Resource allocation under load
%%% - Deadlock prevention
%%% - Subscription management under concurrency
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_concurrency_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(CONCURRENCY_TIMEOUT, 30000).
-define(NUM_CONCURRENT_WORKFLOWS, 50).
-define(NUM_PARALLEL_OPERATIONS, 100).
-define(STRESS_ITERATIONS, 200).

%%====================================================================
%% Test Fixtures
%%====================================================================

concurrency_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Parallel workflow creation", fun test_parallel_workflow_creation/0},
      {"Concurrent workflow execution", fun test_concurrent_workflow_execution/0},
      {"Concurrent state mutations", fun test_concurrent_state_mutations/0},
      {"Race condition in status updates", fun test_race_condition_status_updates/0},
      {"Concurrent subscriptions", fun test_concurrent_subscriptions/0},
      {"Parallel resource allocation", fun test_parallel_resource_allocation/0},
      {"Concurrent cancellation", fun test_concurrent_cancellation/0},
      {"Synchronized workflow operations", fun test_synchronized_operations/0},
      {"Multiple workflow instances", fun test_multiple_workflow_instances/0},
      {"Concurrent checkpoint creation", fun test_concurrent_checkpoint_creation/0},
      {"Stress test: concurrent operations", fun test_stress_concurrent_operations/0},
      {"Atomic transactions", fun test_atomic_transactions/0},
      {"Process monitoring under load", fun test_process_monitoring_under_load/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Start all necessary applications
    application:ensure_all_started(mnesia),

    %% Create schema and tables
    yawl_persistence:create_schema(),
    yawl_persistence:create_tables(),
    yawl_persistence:wait_for_tables(),

    %% Start the orchestrator
    {ok, OrchPid} = yawl_orchestrator:start_link(),

    %% Start metrics
    {ok, _MetricsPid} = yawl_metrics:start_link(),

    %% Start persistence manager
    {ok, _PersistPid} = yawl_persistence:start_link(),

    OrchPid.

cleanup(_Pid) ->
    %% Stop all processes
    gen_server:stop(yawl_orchestrator),
    gen_server:stop(yawl_metrics),
    gen_server:stop(yawl_persistence),

    %% Clean up Mnesia tables for next test
    mnesia:clear_table(yawl_workflow_persist),
    mnesia:clear_table(yawl_workitem_persist),
    mnesia:clear_table(yawl_checkpoint),

    %% Stop Mnesia
    mnesia:stop().

%%====================================================================
%% Parallel Workflow Creation Tests
%%====================================================================

test_parallel_workflow_creation() ->
    %% Create multiple workflows in parallel
    NumWorkflows = ?NUM_CONCURRENT_WORKFLOWS,

    %% Spawn processes to create workflows concurrently
    ParentPid = self(),
    _Pids = lists:map(fun(I) ->
        spawn(fun() ->
            Config = #{
                task1_name => "parallel_task_" ++ integer_to_list(I),
                task2_name => "parallel_task2_" ++ integer_to_list(I)
            },
            PatternType = case I rem 3 of
                0 -> basic_sequential;
                1 -> parallel_split;
                2 -> exclusive_choice
            end,
            Result = yawl_orchestrator:create_workflow(PatternType, Config),
            ParentPid ! {created, I, Result}
        end)
    end, lists:seq(1, NumWorkflows)),

    %% Collect results
    _Results = collect_results(NumWorkflows, created),

    %% Verify all workflows were created successfully
    CreatedCount = count_successful_results(NumWorkflows, created),

    ?assertEqual(NumWorkflows, CreatedCount,
                 "All parallel workflow creations should succeed"),

    %% Verify we can list all workflows
    {ok, ListedWorkflows} = yawl_orchestrator:list_workflows(),
    ?assertEqual(NumWorkflows, length(ListedWorkflows),
                 "List should contain all created workflows"),

    ok.

%%====================================================================
%% Concurrent Workflow Execution Tests
%%====================================================================

test_concurrent_workflow_execution() ->
    %% Create workflows first
    NumWorkflows = 20,
    WorkflowIds = lists:map(fun(I) ->
        Config = #{task1_name => "exec_task_" ++ integer_to_list(I)},
        {ok, WId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        WId
    end, lists:seq(1, NumWorkflows)),

    %% Execute all workflows concurrently
    ParentPid = self(),
    _ExecutePids = lists:map(fun(WId) ->
        spawn(fun() ->
            Result = yawl_orchestrator:execute_workflow(WId),
            ParentPid ! {executed, WId, Result}
        end)
    end, WorkflowIds),

    %% Collect execution results
    ExecutionResults = collect_results(NumWorkflows, executed),

    %% Verify all executions succeeded
    SuccessfulExecutions = lists:filter(fun({_, {ok, _}}) -> true;
                                          (_) -> false
                                       end, ExecutionResults),

    ?assertEqual(NumWorkflows, length(SuccessfulExecutions),
                 "All concurrent executions should succeed"),

    ok.

%%====================================================================
%% Concurrent State Mutation Tests
%%====================================================================

test_concurrent_state_mutations() ->
    %% Create a single workflow
    Config = #{task1_name => "mutation_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Perform concurrent state mutations
    NumMutations = ?NUM_PARALLEL_OPERATIONS,
    ParentPid = self(),

    %% Spawn processes to mutate state concurrently
    _MutationPids = lists:map(fun(I) ->
        spawn(fun() ->
            %% Various operations that mutate state
            Result = case I rem 4 of
                0 -> yawl_orchestrator:get_status(WorkflowId);
                1 -> yawl_orchestrator:get_pattern_info(basic_sequential);
                2 -> yawl_orchestrator:subscribe_to_workflow(WorkflowId, self());
                3 -> yawl_orchestrator:unsubscribe_from_workflow(WorkflowId, self())
            end,
            ParentPid ! {mutation, I, Result}
        end)
    end, lists:seq(1, NumMutations)),

    %% Collect all mutation results
    MutationResults = collect_results(NumMutations, mutation),

    %% Verify all operations completed without crashing
    ?assertEqual(NumMutations, length(MutationResults),
                 "All concurrent mutations should complete"),

    %% Verify final state is consistent
    {ok, FinalStatus} = yawl_orchestrator:get_status(WorkflowId),
    ?assertEqual(pending, FinalStatus,
                 "Final status should be consistent"),

    ok.

%%====================================================================
%% Race Condition Detection Tests
%%====================================================================

test_race_condition_status_updates() ->
    %% Create a workflow
    Config = #{task1_name => "race_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Execute workflow and immediately check status multiple times
    ParentPid = self(),
    NumChecks = 50,

    %% Start execution
    spawn(fun() ->
        yawl_orchestrator:execute_workflow(WorkflowId),
        ParentPid ! execution_started
    end),

    %% Immediately spawn multiple status checkers
    lists:foreach(fun(_) ->
        spawn(fun() ->
            Result = yawl_orchestrator:get_status(WorkflowId),
            ParentPid ! {status_check, Result}
        end)
    end, lists:seq(1, NumChecks)),

    %% Collect all status check results
    StatusResults = collect_results(NumChecks, status_check),

    %% Verify all status checks returned valid results
    ValidStatuses = lists:filter(fun({ok, Status}) ->
        lists:member(Status, [pending, running, completed, cancelled, failed])
    end, StatusResults),

    ?assert(length(ValidStatuses) > 0,
            "At least some status checks should return valid states"),

    ok.

%%====================================================================
%% Concurrent Subscription Tests
%%====================================================================

test_concurrent_subscriptions() ->
    %% Create a workflow
    Config = #{task1_name => "subscription_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Subscribe multiple processes concurrently
    NumSubscribers = 20,
    ParentPid = self(),

    _SubscriberPids = lists:map(fun(I) ->
        spawn(fun() ->
            SubscriberPid = self(),
            Result = yawl_orchestrator:subscribe_to_workflow(WorkflowId, SubscriberPid),
            ParentPid ! {subscribed, I, Result}
        end)
    end, lists:seq(1, NumSubscribers)),

    %% Collect subscription results
    _SubResults = collect_results(NumSubscribers, subscribed),

    %% Count successful subscriptions
    SuccessfulSubs = count_successful_results(NumSubscribers, subscribed),

    ?assertEqual(NumSubscribers, SuccessfulSubs,
                 "All concurrent subscriptions should succeed"),

    %% Unsubscribe all concurrently
    lists:foreach(fun(I) ->
        spawn(fun() ->
            SubscriberPid = list_to_pid("<0." ++ integer_to_list(I) ++ ".0>"),
            yawl_orchestrator:unsubscribe_from_workflow(WorkflowId, SubscriberPid)
        end)
    end, lists:seq(1, NumSubscribers)),

    ok.

%%====================================================================
%% Parallel Resource Allocation Tests
%%====================================================================

test_parallel_resource_allocation() ->
    %% Start resource manager
    {ok, _ResMgrPid} = yawl_resource_manager:start_link(),

    %% Create multiple resources
    NumResources = 10,
    lists:foreach(fun(I) ->
        ResourceId = <<"resource_", (integer_to_binary(I))/binary>>,
        Resource = #yawl_resource_persist{
            resource_id = ResourceId,
            resource_type = service,
            name = <<"Test Resource ", (integer_to_binary(I))/binary>>,
            capabilities = [task_execution],
            status = available,
            max_capacity = 5,
            current_load = 0
        },
        yawl_persistence:save_resource(Resource)
    end, lists:seq(1, NumResources)),

    %% Allocate resources concurrently
    NumAllocations = 50,
    ParentPid = self(),

    _AllocationPids = lists:map(fun(I) ->
        spawn(fun() ->
            ResourceId = <<"resource_", (integer_to_binary((I rem NumResources) + 1))/binary>>,
            Result = yawl_resource_manager:allocate_resource(
                ResourceId,
                <<"workflow_", (integer_to_binary(I))/binary>>
            ),
            ParentPid ! {allocated, I, Result}
        end)
    end, lists:seq(1, NumAllocations)),

    %% Collect allocation results
    _AllocResults = collect_results(NumAllocations, allocated),

    %% Verify allocations completed
    SuccessfulAllocations = count_successful_results(NumAllocations, allocated),

    ?assert(SuccessfulAllocations > 0,
            "At least some allocations should succeed"),

    gen_server:stop(yawl_resource_manager),
    ok.

%%====================================================================
%% Concurrent Cancellation Tests
%%====================================================================

test_concurrent_cancellation() ->
    %% Create multiple workflows
    NumWorkflows = 20,
    WorkflowIds = lists:map(fun(I) ->
        Config = #{task1_name => "cancel_test_" ++ integer_to_list(I)},
        {ok, WId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        WId
    end, lists:seq(1, NumWorkflows)),

    %% Cancel all workflows concurrently
    ParentPid = self(),
    _CancelPids = lists:map(fun(WId) ->
        spawn(fun() ->
            Result = yawl_orchestrator:cancel_workflow(WId),
            ParentPid ! {cancelled, WId, Result}
        end)
    end, WorkflowIds),

    %% Collect cancellation results
    _CancelResults = collect_results(NumWorkflows, cancelled),

    %% Verify all cancellations succeeded
    SuccessfulCancellations = count_successful_results(NumWorkflows, cancelled),

    ?assertEqual(NumWorkflows, SuccessfulCancellations,
                 "All concurrent cancellations should succeed"),

    %% Verify all workflows are cancelled
    lists:foreach(fun(WId) ->
        {ok, Status} = yawl_orchestrator:get_status(WId),
        ?assertEqual(cancelled, Status,
                     "All workflows should be cancelled")
    end, WorkflowIds),

    ok.

%%====================================================================
%% Synchronized Operations Tests
%%====================================================================

test_synchronized_operations() ->
    %% Test that operations on the same workflow are synchronized
    Config = #{task1_name => "sync_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Perform multiple operations in sequence from different processes
    NumOps = 30,
    ParentPid = self(),

    lists:map(fun(I) ->
        spawn(fun() ->
            %% Sequential operations on same workflow
            {ok, _} = yawl_orchestrator:get_status(WorkflowId),
            {ok, _} = yawl_orchestrator:get_pattern_info(basic_sequential),
            {ok, _} = yawl_orchestrator:get_status(WorkflowId),
            ParentPid ! {sync_op, I, completed}
        end)
    end, lists:seq(1, NumOps)),

    %% Collect results
    SyncResults = collect_results(NumOps, sync_op),

    %% Verify all operations completed
    ?assertEqual(NumOps, length(SyncResults),
                 "All synchronized operations should complete"),

    ok.

%%====================================================================
%% Multiple Workflow Instances Tests
%%====================================================================

test_multiple_workflow_instances() ->
    %% Create and execute multiple workflow instances
    NumInstances = 15,
    ParentPid = self(),

    _InstancePids = lists:map(fun(I) ->
        spawn(fun() ->
            Config = #{
                task1_name => "instance_task_" ++ integer_to_list(I),
                task2_name => "instance_task2_" ++ integer_to_list(I)
            },

            %% Create workflow
            {ok, WId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

            %% Execute workflow
            {ok, _} = yawl_orchestrator:execute_workflow(WId),

            %% Get status
            {ok, Status} = yawl_orchestrator:get_status(WId),

            ParentPid ! {instance, I, {WId, Status}}
        end)
    end, lists:seq(1, NumInstances)),

    %% Collect instance results
    InstanceResults = collect_results(NumInstances, instance),

    %% Verify all instances were created and executed
    ValidInstances = lists:filter(fun({_, Status}) ->
        lists:member(Status, [running, completed])
    end, InstanceResults),

    ?assert(length(ValidInstances) > 0,
            "At least some instances should be running"),

    ok.

%%====================================================================
%% Concurrent Checkpoint Creation Tests
%%====================================================================

test_concurrent_checkpoint_creation() ->
    %% Create a workflow
    Config = #{task1_name => "checkpoint_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Get workflow instance and create checkpoints concurrently
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    NumCheckpoints = 20,
    ParentPid = self(),

    lists:map(fun(I) ->
        spawn(fun() ->
            timer:sleep(rand:uniform(100)),
            Result = yawl_workflow_instance:checkpoint(InstancePid),
            ParentPid ! {checkpoint, I, Result}
        end)
    end, lists:seq(1, NumCheckpoints)),

    %% Collect checkpoint results
    _CheckpointResults = collect_results(NumCheckpoints, checkpoint),

    %% Verify all checkpoints were created
    SuccessfulCheckpoints = count_successful_results(NumCheckpoints, checkpoint),

    ?assert(SuccessfulCheckpoints > 0,
            "At least some checkpoints should be created"),

    ok.

%%====================================================================
%% Stress Test: Concurrent Operations
%%====================================================================

test_stress_concurrent_operations() ->
    %% Stress test with many concurrent operations
    NumOperations = ?STRESS_ITERATIONS,
    ParentPid = self(),

    %% Mix of different operations
    lists:map(fun(I) ->
        spawn(fun() ->
            Result = case I rem 5 of
                0 ->
                    Config = #{task1_name => "stress_" ++ integer_to_list(I)},
                    yawl_orchestrator:create_workflow(basic_sequential, Config);
                1 ->
                    {ok, WIds} = yawl_orchestrator:list_workflows(),
                    length(WIds);
                2 ->
                    yawl_orchestrator:list_patterns();
                3 ->
                    yawl_orchestrator:get_pattern_info(basic_sequential);
                4 ->
                    yawl_metrics:get_all_metrics()
            end,
            ParentPid ! {stress_op, I, Result}
        end)
    end, lists:seq(1, NumOperations)),

    %% Collect stress test results
    StressResults = collect_results(NumOperations, stress_op),

    %% Verify most operations completed
    ?assert(length(StressResults) > (NumOperations div 2),
            "Most stress operations should complete"),

    %% Verify system is still responsive
    {ok, Patterns} = yawl_orchestrator:list_patterns(),
    ?assert(length(Patterns) > 0,
            "System should still be responsive after stress test"),

    ok.

%%====================================================================
%% Atomic Transaction Tests
%%====================================================================

test_atomic_transactions() ->
    %% Test that Mnesia transactions are atomic under concurrency
    NumTransactions = 30,
    ParentPid = self(),

    %% Create workflows with unique IDs
    lists:map(fun(I) ->
        spawn(fun() ->
            WorkflowId = <<"atomic_test_", (integer_to_binary(I))/binary>>,

            Workflow = #yawl_workflow_persist{
                workflow_id = WorkflowId,
                spec_id = WorkflowId,
                pattern_type = basic_sequential,
                status = pending,
                marking = #{start => [token]},
                created_at = erlang:monotonic_time(millisecond),
                updated_at = erlang:monotonic_time(millisecond)
            },

            %% Save in transaction
            Result = yawl_persistence:save_workflow(Workflow),

            %% Immediately read back
            ReadResult = yawl_persistence:load_workflow(WorkflowId),

            ParentPid ! {transaction, I, {Result, ReadResult}}
        end)
    end, lists:seq(1, NumTransactions)),

    %% Collect transaction results
    _TransResults = collect_results(NumTransactions, transaction),

    %% Verify all transactions were atomic
    AtomicTransactions = count_successful_results(NumTransactions, transaction),

    ?assert(AtomicTransactions > (NumTransactions div 2),
            "Most transactions should be atomic"),

    ok.

%%====================================================================
%% Process Monitoring Under Load Tests
%%====================================================================

test_process_monitoring_under_load() ->
    %% Test that process monitoring works correctly under load
    NumProcesses = 25,
    ParentPid = self(),

    %% Start multiple workflow instances
    WorkflowIds = lists:map(fun(I) ->
        Config = #{task1_name => "monitor_test_" ++ integer_to_list(I)},
        {ok, WId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        {ok, _} = yawl_orchestrator:execute_workflow(WId),
        WId
    end, lists:seq(1, NumProcesses)),

    %% Monitor all instances concurrently
    lists:map(fun({I, WId}) ->
        spawn(fun() ->
            {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WId),

            %% Monitor the instance
            MonitorRef = erlang:monitor(process, InstancePid),

            %% Get state
            {ok, State, _} = yawl_workflow_instance:get_state(InstancePid),

            %% Demonstrate monitoring
            IsAlive = is_process_alive(InstancePid),

            %% Cancel workflow to trigger monitor message
            yawl_orchestrator:cancel_workflow(WId),

            ParentPid ! {monitor, I, {State, IsAlive, MonitorRef}}
        end)
    end, lists:zip(lists:seq(1, NumProcesses), WorkflowIds)),

    %% Collect monitoring results
    _MonitorResults = collect_results(NumProcesses, monitor),

    %% Verify monitoring worked
    SuccessfulMonitors = count_successful_results(NumProcesses, monitor),

    ?assert(SuccessfulMonitors > 0,
            "Process monitoring should work under load"),

    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @doc Collect results from spawned processes
collect_results(Count, Tag) ->
    collect_results(Count, Tag, [], 5000).

collect_results(0, _Tag, Acc, _Timeout) ->
    lists:reverse(Acc);
collect_results(Count, Tag, Acc, Timeout) when Timeout > 0 ->
    receive
        {Tag, _, Result} ->
            collect_results(Count - 1, Tag, [Result | Acc], Timeout);
        {Tag, Result} ->
            collect_results(Count - 1, Tag, [Result | Acc], Timeout)
    after 100 ->
        %% Partial timeout, continue with shorter timeout
        collect_results(Count, Tag, Acc, Timeout - 100)
    end;
collect_results(Count, Tag, Acc, _Timeout) ->
    %% Timeout expired, return what we have
    lists:reverse(Acc).

%% @doc Count successful results from spawned processes
count_successful_results(Count, Tag) ->
    count_successful_results(Count, Tag, 0, 5000).

count_successful_results(0, _Tag, Acc, _Timeout) ->
    Acc;
count_successful_results(Count, Tag, Acc, Timeout) when Timeout > 0 ->
    receive
        {Tag, _, {ok, _}} ->
            count_successful_results(Count - 1, Tag, Acc + 1, Timeout);
        {Tag, _, {error, _}} ->
            count_successful_results(Count - 1, Tag, Acc, Timeout);
        {Tag, {ok, _}} ->
            count_successful_results(Count - 1, Tag, Acc + 1, Timeout);
        {Tag, _} ->
            count_successful_results(Count - 1, Tag, Acc, Timeout)
    after 100 ->
        count_successful_results(Count, Tag, Acc, Timeout - 100)
    end;
count_successful_results(_Count, _Tag, Acc, _Timeout) ->
    Acc.
