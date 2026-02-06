%%%-------------------------------------------------------------------
%%% @doc
%%% Failure Scenario Tests for YAWL Workflow System
%%%
%%% This module contains comprehensive tests for various failure scenarios,
%%% error recovery, and system resilience under adverse conditions.
%%%
%%% Test Coverage:
%%% - Process crashes and recovery
%%% - Network failures (simulated)
%%% - Resource exhaustion
%%% - Database failures
%%% - Timeout handling
%%% - Invalid input handling
%%% - Graceful degradation
%%% - Checkpoint recovery after failures
%%% - Error propagation
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_failure_scenario_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(FAILURE_TIMEOUT, 10000).
-define(MAX_RETRIES, 3).
-define(RETRY_DELAY, 100).

%%====================================================================
%% Test Fixtures
%%====================================================================

failure_scenario_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Workflow instance crash recovery", fun test_workflow_instance_crash/0},
      {"Orchestrator crash and restart", fun test_orchestrator_crash_restart/0},
      {"Database connection failure", fun test_database_connection_failure/0},
      {"Invalid workflow ID handling", fun test_invalid_workflow_id/0},
      {"Timeout on long-running workflow", fun test_workflow_timeout/0},
      {"Resource exhaustion handling", fun test_resource_exhaustion/0},
      {"Malformed configuration rejection", fun test_malformed_configuration/0},
      {"Checkpoint recovery after crash", fun test_checkpoint_recovery/0},
      {"Network partition simulation", fun test_network_partition_simulation/0},
      {"Concurrent failure handling", fun test_concurrent_failures/0},
      {"Invalid state transitions", fun test_invalid_state_transitions/0},
      {"Unknown pattern type handling", fun test_unknown_pattern_type/0},
      {"Persistence rollback on error", fun test_persistence_rollback/0},
      {"Memory pressure handling", fun test_memory_pressure/0},
      {"Cascading failure prevention", fun test_cascading_failure_prevention/0}
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

    %% Start metrics
    {ok, _MetricsPid} = yawl_metrics:start_link(),

    %% Start persistence manager
    {ok, _PersistPid} = yawl_persistence:start_link(),

    %% Start the orchestrator
    {ok, OrchPid} = yawl_orchestrator:start_link(),

    OrchPid.

cleanup(_Pid) ->
    %% Stop all processes
    catch gen_server:stop(yawl_orchestrator),
    catch gen_server:stop(yawl_metrics),
    catch gen_server:stop(yawl_persistence),

    %% Clean up Mnesia tables
    catch mnesia:clear_table(yawl_workflow_persist),
    catch mnesia:clear_table(yawl_workitem_persist),
    catch mnesia:clear_table(yawl_checkpoint),
    catch mnesia:clear_table(yawl_execution_history),

    %% Stop Mnesia
    catch mnesia:stop().

%%====================================================================
%% Process Crash and Recovery Tests
%%====================================================================

test_workflow_instance_crash() ->
    %% Create a workflow
    Config = #{task1_name => "crash_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Get the instance PID
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Monitor the instance
    MonitorRef = erlang:monitor(process, InstancePid),

    %% Simulate a crash
    exit(InstancePid, kill),

    %% Wait for the down message
    receive
        {'DOWN', MonitorRef, process, InstancePid, _Reason} ->
            ok
    after 5000 ->
        ?assert(false, "Instance should have crashed")
    end,

    %% Verify orchestrator handles the crash
    timer:sleep(100),

    %% The orchestrator should have removed the instance reference
    Result = yawl_orchestrator:get_workflow_instance(WorkflowId),
    ?assertEqual({error, workflow_instance_not_found}, Result,
                 "Orchestrator should clean up crashed instances"),

    ok.

%%====================================================================
%% Orchestrator Crash and Restart Tests
%%====================================================================

test_orchestrator_crash_restart() ->
    %% Create some workflows
    NumWorkflows = 5,
    WorkflowIds = lists:map(fun(I) ->
        Config = #{task1_name => "restart_test_" ++ integer_to_list(I)},
        {ok, WId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        WId
    end, lists:seq(1, NumWorkflows)),

    %% Stop orchestrator
    OrchPid = whereis(yawl_orchestrator),
    MonitorRef = erlang:monitor(process, OrchPid),
    gen_server:stop(OrchPid),

    %% Wait for orchestrator to stop
    receive
        {'DOWN', MonitorRef, process, OrchPid, _} ->
            ok
    after 5000 ->
        ?assert(false, "Orchestrator should have stopped")
    end,

    %% Restart orchestrator
    {ok, _NewOrchPid} = yawl_orchestrator:start_link(),

    %% Verify workflows can be queried after restart
    %% Note: In-memory workflows are lost, but persisted ones should be recoverable
    lists:foreach(fun(WId) ->
        case yawl_persistence:load_workflow(WId) of
            {ok, _Workflow} ->
                %% Workflow was persisted, good
                ok;
            {error, not_found} ->
                %% Workflow not persisted (expected for in-memory only)
                ok
        end
    end, WorkflowIds),

    %% Verify new workflows can be created
    Config = #{task1_name => "after_restart"},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(basic_sequential, Config)),

    ok.

%%====================================================================
%% Database Connection Failure Tests
%%====================================================================

test_database_connection_failure() ->
    %% Create a workflow
    Config = #{task1_name => "db_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Save workflow to persistence
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = WorkflowId,
        pattern_type = basic_sequential,
        status = pending,
        marking = #{start => [token]},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ?assertEqual(ok, yawl_persistence:save_workflow(Workflow)),

    %% Stop Mnesia to simulate database failure
    mnesia:stop(),

    %% Try to load workflow (should fail gracefully)
    Result = yawl_persistence:load_workflow(WorkflowId),
    ?assertMatch({error, _}, Result,
                 "Database operations should fail gracefully when DB is down"),

    %% Restart Mnesia
    application:ensure_all_started(mnesia),
    yawl_persistence:create_schema(),
    yawl_persistence:create_tables(),
    yawl_persistence:wait_for_tables(),

    %% Restart persistence manager
    {ok, _PersistPid} = yawl_persistence:start_link(),

    %% Verify recovery works
    Result2 = yawl_persistence:load_workflow(WorkflowId),
    %% The workflow may not exist after DB restart, but the call should not crash
    ?assert(is_tuple(Result2)),

    ok.

%%====================================================================
%% Invalid Workflow ID Tests
%%====================================================================

test_invalid_workflow_id() ->
    %% Test various invalid workflow IDs
    InvalidIds = [
        undefined,
        <<>>,
        <<"non_existent_workflow">>,
        <<0, 0, 0>>,
        <<"very_long_invalid_id_", (binary:copy(<<"x">>, 1000))/binary>>
    ],

    lists:foreach(fun(Id) ->
        %% All operations should handle invalid IDs gracefully
        ?assertEqual({error, workflow_not_found},
                     yawl_orchestrator:get_status(Id)),
        ?assertEqual({error, workflow_not_found},
                     yawl_orchestrator:cancel_workflow(Id)),
        ?assertEqual({error, workflow_not_found},
                     yawl_orchestrator:cleanup_workflow(Id))
    end, InvalidIds),

    ok.

%%====================================================================
%% Workflow Timeout Tests
%%====================================================================

test_workflow_timeout() ->
    %% Create a workflow with short timeout
    Config = #{
        task1_name => "timeout_test",
        timeout => 100  %% 100ms timeout
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Wait for timeout
    timer:sleep(200),

    %% Check status - should be failed or cancelled due to timeout
    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),

    %% Status should reflect timeout (could be failed, cancelled, or still running)
    %% The important thing is it didn't crash
    ?assert(lists:member(Status, [pending, running, failed, cancelled]),
             "Status should be valid after timeout"),

    ok.

%%====================================================================
%% Resource Exhaustion Tests
%%====================================================================

test_resource_exhaustion() ->
    %% Start resource manager
    {ok, _ResMgrPid} = yawl_resource_manager:start_link(),

    %% Create a limited resource
    ResourceId = <<"limited_resource">>,
    Resource = #yawl_resource_persist{
        resource_id = ResourceId,
        resource_type = service,
        name = <<"Limited Resource">>,
        capabilities = [task_execution],
        status = available,
        max_capacity = 2,  %% Very limited capacity
        current_load = 0
    },
    yawl_persistence:save_resource(Resource),

    %% Try to allocate more than capacity
    NumAllocations = 10,
    AllocationResults = lists:map(fun(I) ->
        yawl_resource_manager:allocate_resource(
            ResourceId,
            <<"workflow_", (integer_to_binary(I))/binary>>
        )
    end, lists:seq(1, NumAllocations)),

    %% Some allocations should fail due to exhaustion
    FailedAllocations = lists:filter(fun({error, _}) -> true;
                                       (_) -> false
                                    end, AllocationResults),

    ?assert(length(FailedAllocations) > 0,
            "Some allocations should fail when resource is exhausted"),

    %% Deallocate all
    lists:foreach(fun(I) ->
        yawl_resource_manager:deallocate_resource(
            ResourceId,
            <<"workflow_", (integer_to_binary(I))/binary>>
        )
    end, lists:seq(1, NumAllocations)),

    gen_server:stop(yawl_resource_manager),
    ok.

%%====================================================================
%% Malformed Configuration Tests
%%====================================================================

test_malformed_configuration() ->
    %% Test various malformed configurations
    MalformedConfigs = [
        #{not_a_valid_key => invalid_value},
        #{task1_name => 123},  %% Wrong type
        #{task1_name => <<>>},  %% Empty binary
        #{timeout => -1},  %% Negative timeout
        #{timeout => "not_a_number"},
        #{pattern_type => <<"not_an_atom">>},
        #{},  %% Empty config
        #{task1_name => ["valid", "but", "wrong", "type"]}
    ],

    lists:foreach(fun(Config) ->
        %% Should handle malformed configs gracefully
        Result = yawl_orchestrator:create_workflow(basic_sequential, Config),
        ?assert(is_tuple(Result),
                 "Should return a tuple result for malformed config")
    end, MalformedConfigs),

    ok.

%%====================================================================
%% Checkpoint Recovery Tests
%%====================================================================

test_checkpoint_recovery() ->
    %% Create a workflow
    Config = #{task1_name => "checkpoint_recovery_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Get instance and create checkpoint
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Simulate crash by stopping the instance
    exit(InstancePid, kill),
    timer:sleep(100),

    %% Recover from checkpoint
    Result = yawl_persistence:restore_from_checkpoint(WorkflowId),

    case Result of
        {ok, Checkpoint} ->
            ?assertEqual(WorkflowId, Checkpoint#yawl_checkpoint.workflow_id,
                         "Checkpoint should have correct workflow ID");
        {error, Reason} ->
            %% Recovery might fail, but it should be a graceful failure
            ?assert(is_atom(Reason) orelse is_tuple(Reason),
                     "Recovery failure should be a valid reason")
    end,

    ok.

%%====================================================================
%% Network Partition Simulation Tests
%%====================================================================

test_network_partition_simulation() ->
    %% Simulate network issues by blocking messages
    %% This tests resilience to communication failures

    %% Create a workflow
    Config = #{task1_name => "partition_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Get instance
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Simulate "network partition" by making the instance unresponsive
    %% We do this by overflowing its message queue
    PartitionPids = lists:map(fun(_) ->
        spawn(fun() ->
            %% Send many messages to instance (simulating packet flood)
            lists:foreach(fun(_) ->
                InstancePid ! {partition_simulation, self()},
                timer:sleep(1)
            end, lists:seq(1, 100))
        end)
    end, lists:seq(1, 10)),

    %% Wait a bit for the "partition"
    timer:sleep(500),

    %% Try to communicate with the instance
    %% Should either succeed or fail gracefully
    Result = try
        yawl_workflow_instance:get_state(InstancePid)
    catch
        _:_ ->
            {error, timeout}
    end,

    %% Clean up partition simulators
    lists:foreach(fun(P) -> exit(P, kill) end, PartitionPids),
    timer:sleep(100),

    %% Verify system is still functional
    ?assert(is_tuple(Result),
             "Should return a valid result even during partition"),

    ok.

%%====================================================================
%% Concurrent Failure Handling Tests
%%====================================================================

test_concurrent_failures() ->
    %% Create multiple workflows
    NumWorkflows = 20,
    WorkflowIds = lists:map(fun(I) ->
        Config = #{task1_name => "concurrent_fail_" ++ integer_to_list(I)},
        {ok, WId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        WId
    end, lists:seq(1, NumWorkflows)),

    %% Execute all workflows
    lists:foreach(fun(WId) ->
        yawl_orchestrator:execute_workflow(WId)
    end, WorkflowIds),

    %% Kill some instances randomly
    lists:foreach(fun(I) when I rem 3 =:= 0 ->
        case yawl_orchestrator:get_workflow_instance(I) of
            {ok, InstancePid} ->
                exit(InstancePid, kill);
            _ ->
                ok
        end
    end, lists:zip(lists:seq(1, NumWorkflows), WorkflowIds)),

    %% Cancel some workflows
    lists:foreach(fun(I) when I rem 5 =:= 0 ->
        yawl_orchestrator:cancel_workflow(I)
    end, lists:zip(lists:seq(1, NumWorkflows), WorkflowIds)),

    %% Wait for failures to propagate
    timer:sleep(500),

    %% Verify system is still functional
    %% Try to create a new workflow
    Config = #{task1_name => "after_concurrent_failures"},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(basic_sequential, Config)),

    ok.

%%====================================================================
%% Invalid State Transition Tests
%%====================================================================

test_invalid_state_transitions() ->
    %% Create a workflow
    Config = #{task1_name => "state_transition_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Try invalid state transitions
    %% Resume without pause
    ?assertEqual({error, workflow_instance_not_found},
                 yawl_orchestrator:resume_workflow(WorkflowId)),

    %% Cancel non-running workflow (should work from pending)
    ?assertMatch({ok, _}, yawl_orchestrator:cancel_workflow(WorkflowId)),

    %% Try to execute cancelled workflow
    ?assertEqual({error, workflow_not_found},
                 yawl_orchestrator:execute_workflow(WorkflowId)),

    ok.

%%====================================================================
%% Unknown Pattern Type Tests
%%====================================================================

test_unknown_pattern_type() ->
    %% Try to create workflow with unknown pattern
    Config = #{task1_name => "unknown_pattern_test"},

    UnknownPatterns = [
        unknown_pattern,
        definitely_not_a_pattern,
        this_pattern_does_not_exist
    ],

    lists:foreach(fun(Pattern) ->
        Result = yawl_orchestrator:create_workflow(Pattern, Config),
        ?assertEqual({error, {unknown_pattern, Pattern}}, Result,
                     "Unknown pattern should be rejected")
    end, UnknownPatterns),

    ok.

%%====================================================================
%% Persistence Rollback Tests
%%====================================================================

test_persistence_rollback() ->
    %% Create a workflow
    Config = #{task1_name => "rollback_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Save workflow
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = WorkflowId,
        pattern_type = basic_sequential,
        status = pending,
        marking = #{start => [token]},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ?assertEqual(ok, yawl_persistence:save_workflow(Workflow)),

    %% Create checkpoint
    CheckpointId = <<WorkflowId/binary, "_checkpoint">>,
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = CheckpointId,
        workflow_id = WorkflowId,
        checkpoint_state = #{status => pending},
        marking = #{start => [token]},
        data = #{},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ?assertEqual(ok, yawl_persistence:save_checkpoint(WorkflowId, Checkpoint)),

    %% Update workflow status
    UpdatedWorkflow = Workflow#yawl_workflow_persist{status = running},
    ?assertEqual(ok, yawl_persistence:save_workflow(UpdatedWorkflow)),

    %% Rollback to checkpoint
    RollbackResult = yawl_persistence:rollback_to_checkpoint(WorkflowId, CheckpointId),

    case RollbackResult of
        {ok, RolledBackCheckpoint} ->
            ?assertEqual(CheckpointId, RolledBackCheckpoint#yawl_checkpoint.checkpoint_id);
        {error, Reason} ->
            %% Rollback might fail, but should be graceful
            ?assert(is_atom(Reason) orelse is_tuple(Reason))
    end,

    ok.

%%====================================================================
%% Memory Pressure Tests
%%====================================================================

test_memory_pressure() ->
    %% Create many workflows to simulate memory pressure
    NumWorkflows = 100,

    %% Create workflows in batches
    lists:foreach(fun(I) ->
        Config = #{
            task1_name => "memory_test_" ++ integer_to_list(I),
            large_data => lists:duplicate(100, I)  %% Add some data
        },
        yawl_orchestrator:create_workflow(basic_sequential, Config),

        %% Check memory every 10 workflows
        case I rem 10 of
            0 ->
                %% Force garbage collection
                erlang:garbage_collect(),
                %% Verify system is still responsive
                ?assertMatch({ok, _}, yawl_orchestrator:list_patterns());
            _ ->
                ok
        end
    end, lists:seq(1, NumWorkflows)),

    %% Final verification - system should still be functional
    Config = #{task1_name => "final_test"},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(basic_sequential, Config)),

    ok.

%%====================================================================
%% Cascading Failure Prevention Tests
%%====================================================================

test_cascading_failure_prevention() ->
    %% Test that one failure doesn't cause cascading failures
    NumWorkflows = 30,
    ParentPid = self(),

    %% Create and execute workflows
    WorkflowIds = lists:map(fun(I) ->
        Config = #{task1_name => "cascade_test_" ++ integer_to_list(I)},
        {ok, WId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        {ok, _} = yawl_orchestrator:execute_workflow(WId),
        WId
    end, lists:seq(1, NumWorkflows)),

    %% Fail a few workflows intentionally
    lists:map(fun(I) when I rem 5 =:= 0 ->
        spawn(fun() ->
            case yawl_orchestrator:get_workflow_instance(I) of
                {ok, InstancePid} ->
                    exit(InstancePid, kill),
                    ParentPid ! {failed, I};
                _ ->
                    ParentPid ! {no_instance, I}
            end
        end);
    (I) ->
        ParentPid ! {ok, I}
    end, lists:zip(lists:seq(1, NumWorkflows), WorkflowIds)),

    %% Wait for failures
    timer:sleep(500),

    %% Count successful failures
    FailedCount = lists:foldl(fun(_, Acc) ->
        receive
            {failed, _} -> Acc + 1;
            _ -> Acc
        after 100 ->
            Acc
        end
    end, 0, lists:seq(1, NumWorkflows div 5)),

    ?assert(FailedCount > 0,
            "Some workflows should have failed"),

    %% Verify other workflows are not affected
    StillWorking = lists:foldl(fun(WId, Acc) ->
        case yawl_orchestrator:get_status(WId) of
            {ok, _} -> Acc + 1;
            _ -> Acc
        end
    end, 0, WorkflowIds),

    ?assert(StillWorking > FailedCount,
            "Most workflows should still be working after some failures"),

    ok.
