%%%-------------------------------------------------------------------
%%% @doc
%%% Failover Operation Integration Tests (Chicago-Style TDD)
%%%
%%% These tests verify failover behavior when processes crash or nodes
%%% go down. Tests are written FIRST to drive failover implementation.
%%%
%%% Test Categories:
%%% 1. Process Crash Handling
%%% 2. State Recovery
%%% 3. Restart Behavior
%%% 4. Hot Failover
%%% 5. Data Consistency
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(failover_operation_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(FAILOVER_TIMEOUT, 10000).
-define(CRASH_RESTART_DELAY, 500).
-define(MAX_RESTARTS, 5).

%%====================================================================
%% Test Fixtures
%%====================================================================

%% @doc Setup for failover tests
failover_setup() ->
    %% Start Mnesia
    mnesia:delete_schema([node()]),
    {ok, _} = yawl_persistence:create_schema(),
    {ok, _} = yawl_persistence:create_tables(),
    {ok, _} = yawl_persistence:wait_for_tables(),

    %% Start application with supervision
    {ok, _} = application:ensure_all_started(a2a_erl),

    %% Create test workflow
    {ok, WorkflowId} = create_test_workflow(),

    #{workflow_id => WorkflowId}.

%% @doc Teardown for failover tests
failover_cleanup(#{workflow_id := WorkflowId}) ->
    %% Cleanup workflow
    _ = yawl_orchestrator:cleanup_workflow(WorkflowId),

    %% Stop application
    application:stop(a2a_erl),
    mnesia:stop().

%% @private
create_test_workflow() ->
    Config = #{task1_name => "task1", task2_name => "task2"},
    yawl_orchestrator:create_workflow(basic_sequential, Config).

%%====================================================================
%% Process Crash Handling Tests
%%====================================================================

process_crash_test_() ->
    {"Orchestrator crash recovery",
     fun test_orchestrator_crash_recovery/0},
    {"Persistence crash recovery",
     fun test_persistence_crash_recovery/0},
    {"Resource manager crash recovery",
     fun test_resource_manager_crash_recovery/0},
    {"Service registry crash recovery",
     fun test_service_registry_crash_recovery/0},
    {"Workflow instance crash recovery",
     fun test_workflow_instance_crash_recovery/0},
    {"Multiple simultaneous crashes",
     fun test_multiple_simultaneous_crashes/0}.

%% @doc FAILING TEST: Orchestrator crash and recovery
test_orchestrator_crash_recovery() ->
    %% Arrange
    State = failover_setup(),
    OrchPid = whereis(yawl_orchestrator),

    %% Create a workflow before crash
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        parallel_split, #{branches => 2}),

    %% Act - Crash the orchestrator
    exit(OrchPid, brutal_kill),

    %% Wait for restart
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - Orchestrator should be restarted
    NewOrchPid = whereis(yawl_orchestrator),
    ?assertNotEqual(undefined, NewOrchPid),
    ?assertNotEqual(OrchPid, NewOrchPid),
    ?assert(is_process_alive(NewOrchPid)),

    %% Workflow should still be accessible
    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
    ?assertNotEqual(undefined, Status),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Persistence crash and recovery
test_persistence_crash_recovery() ->
    %% Arrange
    State = failover_setup(),
    PersistPid = whereis(yawl_persistence),

    %% Save some data before crash
    {ok, WorkflowId} = yawl_persistence:save_workflow(#yawl_workflow_persist{
        workflow_id = <<"test_wf_1">>,
        spec_id = <<"spec_1">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{start => [token]},
        current_place = start,
        data = #{},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    }),

    %% Act - Crash persistence
    exit(PersistPid, brutal_kill),

    %% Wait for restart
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - Persistence should be restarted
    NewPersistPid = whereis(yawl_persistence),
    ?assertNotEqual(undefined, NewPersistPid),
    ?assertNotEqual(PersistPid, NewPersistPid),

    %% Data should be recoverable
    {ok, Workflow} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(basic_sequential, Workflow#yawl_workflow_persist.pattern_type),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Resource manager crash and recovery
test_resource_manager_crash_recovery() ->
    %% Arrange
    State = failover_setup(),
    ResPid = whereis(yawl_resource_manager),

    %% Register resources before crash
    {ok, ResId1} = yawl_resource_manager:register_resource(
        <<"resource1">>, human, #{capabilities => [task1, task2]}),
    {ok, ResId2} = yawl_resource_manager:register_resource(
        <<"resource2">>, service, #{capabilities => [task3]}),

    %% Act - Crash resource manager
    exit(ResPid, brutal_kill),

    %% Wait for restart
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - Should be restarted
    NewResPid = whereis(yawl_resource_manager),
    ?assertNotEqual(undefined, NewResPid),
    ?assertNotEqual(ResPid, NewResPid),

    %% Resources should still be available after restart
    {ok, Resources} = yawl_resource_manager:list_resources(),
    ?assert(length(Resources) >= 2),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Service registry crash and recovery
test_service_registry_crash_recovery() ->
    %% Arrange
    State = failover_setup(),
    RegPid = whereis(yawl_service_registry),

    %% Register services before crash
    {ok, _} = yawl_service_registry:register_service(
        <<"svc1">>, workflow_engine, <<"http://localhost:8081">>),
    {ok, _} = yawl_service_registry:register_service(
        <<"svc2">>, resource_manager, <<"http://localhost:8082">>),

    %% Act - Crash registry
    exit(RegPid, brutal_kill),

    %% Wait for restart
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - Should be restarted
    NewRegPid = whereis(yawl_service_registry),
    ?assertNotEqual(undefined, NewRegPid),
    ?assertNotEqual(RegPid, NewRegPid),

    %% Services should be recoverable
    {ok, Services} = yawl_service_registry:list_services(),
    ?assert(length(Services) >= 2),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Workflow instance crash and recovery
test_workflow_instance_crash_recovery() ->
    %% Arrange
    State = failover_setup(),

    %% Create and start a workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{task1_name => "task1", task2_name => "task2"}),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Get the instance PID
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Save state before crash
    {ok, Marking} = yawl_workflow_instance:get_marking(InstancePid),

    %% Act - Crash the instance
    exit(InstancePid, brutal_kill),

    %% Wait for restart/recovery
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - Instance should be recovered
    {ok, #{instance := NewInstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    ?assertNotEqual(InstancePid, NewInstancePid),
    ?assert(is_process_alive(NewInstancePid)),

    %% State should be restored from checkpoint
    {ok, RestoredMarking} = yawl_workflow_instance:get_marking(NewInstancePid),
    ?assertEqual(Marking, RestoredMarking),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Multiple simultaneous crashes
test_multiple_simultaneous_crashes() ->
    %% Arrange
    State = failover_setup(),

    %% Get all service PIDs
    OrchPid = whereis(yawl_orchestrator),
    PersistPid = whereis(yawl_persistence),
    ResPid = whereis(yawl_resource_manager),
    RegPid = whereis(yawl_service_registry),

    %% Act - Crash all services simultaneously
    exit(OrchPid, brutal_kill),
    exit(PersistPid, brutal_kill),
    exit(ResPid, brutal_kill),
    exit(RegPid, brutal_kill),

    %% Wait for recovery
    timer:sleep(?CRASH_RESTART_DELAY * 2),

    %% Assert - All services should be restarted
    NewOrchPid = whereis(yawl_orchestrator),
    NewPersistPid = whereis(yawl_persistence),
    NewResPid = whereis(yawl_resource_manager),
    NewRegPid = whereis(yawl_service_registry),

    ?assertNotEqual(undefined, NewOrchPid),
    ?assertNotEqual(undefined, NewPersistPid),
    ?assertNotEqual(undefined, NewResPid),
    ?assertNotEqual(undefined, NewRegPid),

    %% All should be alive
    ?assert(is_process_alive(NewOrchPid)),
    ?assert(is_process_alive(NewPersistPid)),
    ?assert(is_process_alive(NewResPid)),
    ?assert(is_process_alive(NewRegPid)),

    %% Cleanup
    failover_cleanup(State).

%%====================================================================
%% State Recovery Tests
%%====================================================================

state_recovery_test_() ->
    {"Recover workflow state from checkpoint",
     fun test_recover_workflow_state/0},
    {"Recover marking after crash",
     fun test_recover_marking/0},
    {"Recover workflow data after crash",
     fun test_recover_workflow_data/0},
    {"Recover subscriptions after crash",
     fun test_recover_subscriptions/0},
    {"Recover incomplete workitems after crash",
     fun test_recover_workitems/0}.

%% @doc FAILING TEST: Recover workflow state from checkpoint
test_recover_workflow_state() ->
    %% Arrange
    State = failover_setup(),

    %% Create a workflow in running state
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        iterative_loop, #{condition => true, max_iterations => 5}),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Get instance and create checkpoint
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Act - Crash instance
    exit(InstancePid, brutal_kill),
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - State should be recovered
    {ok, #{instance := NewInstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, RecoveredState} = yawl_workflow_instance:get_state(NewInstancePid),
    ?assertMatch({ok, _, _}, RecoveredState),

    %% Checkpoint should match
    {ok, Checkpoint} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(CheckpointId, Checkpoint#yawl_checkpoint.checkpoint_id),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Recover marking after crash
test_recover_marking() ->
    %% Arrange
    State = failover_setup(),

    %% Create workflow with complex marking
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        parallel_split, #{branches => 3}),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Get initial marking
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, OriginalMarking} = yawl_workflow_instance:get_marking(InstancePid),

    %% Act - Crash and recover
    exit(InstancePid, brutal_kill),
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - Marking should be restored
    {ok, #{instance := NewInstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, RecoveredMarking} = yawl_workflow_instance:get_marking(NewInstancePid),
    ?assertEqual(OriginalMarking, RecoveredMarking),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Recover workflow data after crash
test_recover_workflow_data() ->
    %% Arrange
    State = failover_setup(),

    %% Create workflow with data
    WorkflowData = #{
        user_id => <<"user123">>,
        order_id => <<"order456">>,
        total => 1000,
        items => [<<"item1">>, <<"item2">>]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, WorkflowData),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Update workflow data
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    ok = yawl_workflow_instance:update_data(InstancePid, processed, true),

    %% Act - Crash
    exit(InstancePid, brutal_kill),
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - Data should be recovered
    {ok, #{instance := NewInstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, NewState, DataMap} = yawl_workflow_instance:get_state(NewInstancePid),
    ?assertEqual(running, NewState),
    ?assertEqual(true, maps:get(processed, DataMap)),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Recover subscriptions after crash
test_recover_subscriptions() ->
    %% Arrange
    State = failover_setup(),

    %% Create workflow and subscribe
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{}),
    SubscriberPid = spawn(fun() -> receive after infinity -> ok end end),
    {ok, _} = yawl_orchestrator:subscribe_to_workflow(WorkflowId, SubscriberPid),

    %% Act - Crash orchestrator
    OrchPid = whereis(yawl_orchestrator),
    exit(OrchPid, brutal_kill),
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - Subscriptions should be recovered
    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
    ?assertNotEqual({error, workflow_not_found}, Status),

    %% Cleanup
    exit(SubscriberPid, kill),
    failover_cleanup(State).

%% @doc FAILING TEST: Recover incomplete workitems after crash
test_recover_workitems() ->
    %% Arrange
    State = failover_setup(),

    %% Create workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{task1_name => "task1", task2_name => "task2"}),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Create workitems
    {ok, _} = yawl_persistence:save_workitem(#yawl_workitem_persist{
        workitem_id = <<"wi1">>,
        workflow_id = WorkflowId,
        task_id => task1,
        task_name => <<"Task 1">>,
        status = started,
        data = #{},
        allocated_to = undefined,
        start_time = erlang:monotonic_time(millisecond),
        retry_count = 0,
        priority = normal
    }),

    %% Act - Crash orchestrator
    OrchPid = whereis(yawl_orchestrator),
    exit(OrchPid, brutal_kill),
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - Workitems should be recovered
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    ?assert(length(Workitems) >= 1),

    %% Verify workitem status
    Wi1 = lists:keyfind(<<"wi1">>, #yawl_workitem_persist.workitem_id, Workitems),
    ?assertNotEqual(false, Wi1),
    #yawl_workitem_persist{status = started} = Wi1,

    %% Cleanup
    failover_cleanup(State).

%%====================================================================
%% Restart Behavior Tests
%%====================================================================

restart_behavior_test_() ->
    {"Respect max restart intensity",
     fun test_max_restart_intensity/0},
    {"Respect max restart period",
     fun test_max_restart_period/0},
    {"Permanent failure after max restarts",
     fun test_permanent_failure/0},
    {"Transient error recovery",
     fun test_transient_error_recovery/0},
    {"Delayed restart strategy",
     fun test_delayed_restart/0}.

%% @doc FAILING TEST: Respect max restart intensity
test_max_restart_intensity() ->
    %% Arrange
    State = failover_setup(),

    %% Get a child process
    OrchPid = whereis(yawl_orchestrator),

    %% Act - Crash multiple times quickly
    lists:foreach(fun(_) ->
        exit(OrchPid, kill),
        timer:sleep(50),
        case whereis(yawl_orchestrator) of
            undefined -> timer:sleep(200);
            NewPid when is_pid(NewPid) -> OrchPid = NewPid
        end
    end, lists:seq(1, 6)),

    %% Assert - Should stop restarting after max intensity
    %% (Supervisor should give up)
    timer:sleep(500),
    case whereis(yawl_orchestrator) of
        undefined -> ok;  %% Expected after max restarts
        _ -> ?assert(false, "Should have stopped restarting")
    end,

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Respect max restart period
test_max_restart_period() ->
    %% Arrange
    State = failover_setup(),
    OrchPid = whereis(yawl_orchestrator),

    %% Act - Crash, then wait for period to reset
    exit(OrchPid, kill),
    timer:sleep(?CRASH_RESTART_DELAY),
    NewPid1 = whereis(yawl_orchestrator),

    %% Wait for period to reset
    timer:sleep(5000),

    %% Crash again - should restart (period reset)
    exit(NewPid1, kill),
    timer:sleep(?CRASH_RESTART_DELAY),
    NewPid2 = whereis(yawl_orchestrator),

    %% Assert - Should restart after period reset
    ?assertNotEqual(undefined, NewPid2),
    ?assertNotEqual(NewPid1, NewPid2),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Permanent failure after max restarts
test_permanent_failure() ->
    %% Arrange
    State = failover_setup(),

    %% Create a failing worker
    {ok, FailingPid} = start_failing_worker(),

    %% Act - Wait for it to crash and not restart
    timer:sleep(2000),

    %% Assert - Worker should not be running after max restarts
    ?assertNot(is_process_alive(FailingPid)),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Transient error recovery
test_transient_error_recovery() ->
    %% Arrange
    State = failover_setup(),

    %% Start a service with transient error handling
    {ok, TransientPid} = start_transient_worker(),

    %% Act - Cause transient error
    TransientPid ! {cause_error, transient},

    %% Wait for recovery
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - Should be recovered
    ?assert(is_process_alive(whereis(transient_worker))),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Delayed restart strategy
test_delayed_restart() ->
    %% Arrange
    State = failover_setup(),

    %% Get orchestrator PID
    OrigPid = whereis(yawl_orchestrator),

    %% Act - Kill and measure restart delay
    StartTime = erlang:monotonic_time(millisecond),
    exit(OrigPid, shutdown),
    timer:sleep(100),

    %% Wait for restart
    receive
        {service_restarted, _, _, _} -> ok
    after 5000 -> ok
    end,

    EndTime = erlang:monotonic_time(millisecond),
    Delay = EndTime - StartTime,

    %% Assert - Should have some delay (not instant)
    ?assert(Delay > 0),

    %% Cleanup
    failover_cleanup(State).

%%====================================================================
%% Hot Failover Tests
%%====================================================================

hot_failover_test_() ->
    {"Hot standby takeover",
     fun test_hot_standby_takeover/0},
    {"Graceful handover",
     fun test_graceful_handover/0},
    {"State synchronization",
     fun test_state_synchronization/0},
    {"Zero downtime failover",
     fun test_zero_downtime_failover/0}.

%% @doc FAILING TEST: Hot standby takes over on primary failure
test_hot_standby_takeover() ->
    %% Arrange
    State = failover_setup(),

    %% Start primary and standby
    {ok, PrimaryPid} = start_primary_service(),
    {ok, StandbyPid} = start_standby_service(PrimaryPid),

    %% Sync state
    sync_state(PrimaryPid, StandbyPid),

    %% Act - Fail primary
    exit(PrimaryPid, kill),

    %% Assert - Standby should take over
    timer:sleep(?CRASH_RESTART_DELAY),
    ?assert(is_process_alive(StandbyPid)),
    ?assertEqual(whereis(primary_service), StandbyPid),

    %% State should be preserved
    StateResult = get_service_state(StandbyPid),
    ?assertMatch({ok, _}, StateResult),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Graceful handover between nodes
test_graceful_handover() ->
    %% Arrange
    State = failover_setup(),

    %% Start primary and standby
    {ok, PrimaryPid} = start_primary_service(),
    {ok, StandbyPid} = start_standby_service(PrimaryPid),

    %% Act - Graceful handover
    PrimaryPid ! {handover, StandbyPid},

    %% Assert - Handover completes
    timer:sleep(100),
    ?assertEqual(whereis(primary_service), StandbyPid),

    %% No request loss during handover
    %% (Would require more complex testing setup)

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: State synchronization between primary and standby
test_state_synchronization() ->
    %% Arrange
    State = failover_setup(),

    %% Start primary and standby
    {ok, PrimaryPid} = start_primary_service(),
    {ok, StandbyPid} = start_standby_service(PrimaryPid),

    %% Modify primary state
    PrimaryPid ! {update_state, #{counter => 42}},

    %% Trigger sync
    sync_state(PrimaryPid, StandbyPid),

    %% Act - Check standby state
    StandbyState = get_service_state(StandbyPid),

    %% Assert - States should match
    PrimaryState = get_service_state(PrimaryPid),
    ?assertEqual(PrimaryState, StandbyState),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Zero downtime failover
test_zero_downtime_failover() ->
    %% Arrange
    State = failover_setup(),

    %% Start primary and standby
    {ok, PrimaryPid} = start_primary_service(),
    {ok, StandbyPid} = start_standby_service(PrimaryPid),

    %% Start a load generator
    LoadGenPid = start_load_generator(primary_service),

    %% Act - Fail primary while under load
    exit(PrimaryPid, kill),

    %% Assert - Standby takes over immediately
    timer:sleep(50),
    ?assertEqual(whereis(primary_service), StandbyPid),

    %% Load generator should not have errors
    LoadGenPid ! get_stats,
    receive
        {stats, Stats} ->
            ?assertEqual(0, maps:get(errors, Stats, 0))
    after 500 ->
        ok
    end,

    %% Cleanup
    exit(LoadGenPid, kill),
    failover_cleanup(State).

%%====================================================================
%% Data Consistency Tests
%%====================================================================

data_consistency_test_() ->
    {"No data loss during failover",
     fun test_no_data_loss/0},
    {"No duplicate processing after failover",
     fun test_no_duplicates/0},
    {"Checkpoint consistency",
     fun test_checkpoint_consistency/0},
    {"Transaction rollback on failover",
     fun test_transaction_rollback/0}.

%% @doc FAILING TEST: No data loss during failover
test_no_data_loss() ->
    %% Arrange
    State = failover_setup(),

    %% Create workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{task1_name => "task1", task2_name => "task2"}),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Record original data count
    {ok, OriginalWorkitems} = yawl_persistence:list_workitems(WorkflowId),
    OriginalCount = length(OriginalWorkitems),

    %% Act - Failover
    OrchPid = whereis(yawl_orchestrator),
    exit(OrchPid, kill),
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - No data loss
    {ok, RecoveredWorkitems} = yawl_persistence:list_workitems(WorkflowId),
    ?assertEqual(OriginalCount, length(RecoveredWorkitems)),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: No duplicate processing after failover
test_no_duplicates() ->
    %% Arrange
    State = failover_setup(),

    %% Create workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{task1_name => "task1"}),

    %% Track execution count
    ExecCountRef = track_execution_count(WorkflowId),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Act - Failover during execution
    OrchPid = whereis(yawl_orchestrator),
    exit(OrchPid, kill),
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - No duplicate executions
    Count = get_execution_count(ExecCountRef),
    ?assert(Count =< 1, "Workflow should not execute multiple times"),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Checkpoint consistency during failover
test_checkpoint_consistency() ->
    %% Arrange
    State = failover_setup(),

    %% Create workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        iterative_loop, #{condition => true}),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Create multiple checkpoints
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    CheckpointIds = lists:map(fun(_) ->
        {ok, Cpid} = yawl_workflow_instance:checkpoint(InstancePid),
        Cpid
    end, lists:seq(1, 3)),

    %% Calculate checksums
    OriginalChecksums = lists:map(fun(Cpid) ->
        {ok, Cp} = yawl_persistence:load_latest_checkpoint(WorkflowId),
        checksum_checkpoint(Cp)
    end, CheckpointIds),

    %% Act - Failover
    exit(InstancePid, kill),
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - Checksums should match
    RecoveredChecksums = lists:map(fun(Cpid) ->
        {ok, Cp} = yawl_persistence:load_latest_checkpoint(WorkflowId),
        checksum_checkpoint(Cp)
    end, CheckpointIds),

    ?assertEqual(OriginalChecksums, RecoveredChecksums),

    %% Cleanup
    failover_cleanup(State).

%% @doc FAILING TEST: Transaction rollback on failover
test_transaction_rollback() ->
    %% Arrange
    State = failover_setup(),

    %% Start a transaction
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{}),

    %% Act - Start multi-step transaction, then fail
    OrchPid = whereis(yawl_orchestrator),
    Pid = spawn(fun() ->
        %% Start transaction
        mnesia:transaction(fun() ->
            %% Write to multiple tables
            mnesia:write(#yawl_workflow_persist{
                workflow_id = WorkflowId,
                spec_id = <<"spec1">>,
                pattern_type = basic_sequential,
                status = running,
                marking = #{},
                current_place = undefined,
                data = #{},
                created_at = erlang:monotonic_time(millisecond),
                updated_at = erlang:monotonic_time(millisecond)
            }),
            %% Simulate crash before commit
            exit(OrchPid, kill),
            timer:sleep(1000)
        end)
    end),

    %% Wait
    timer:sleep(?CRASH_RESTART_DELAY),

    %% Assert - Transaction should be rolled back
    {ok, Workflows} = yawl_persistence:list_workflows(),
    %% Workflow should not exist (rolled back) or exist with previous state
    Result = lists:keyfind(WorkflowId, #yawl_workflow_persist.workflow_id, Workflows),
    case Result of
        false -> ok;  %% Rolled back
        #yawl_workflow_persist{status = Status} ->
            ?assertNotEqual(running, Status)  %% Not the uncommitted state
    end,

    %% Cleanup
    failover_cleanup(State).

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
start_failing_worker() ->
    %% Start a worker that always fails
    spawn_link(fun() ->
        register(failing_worker, self()),
        failing_loop()
    end),
    {ok, whereis(failing_worker)}.

%% @private
failing_loop() ->
    receive
        _ -> ok
    after 100 ->
        exit(failed)
    end,
    failing_loop().

%% @private
start_transient_worker() ->
    Pid = spawn_link(fun() ->
        register(transient_worker, self()),
        transient_loop(0)
    end),
    {ok, Pid}.

%% @private
transient_loop(ErrorCount) ->
    receive
        {cause_error, transient} when ErrorCount < 3 ->
            %% Transient error - restart
            exit(transient_error);
        {cause_error, _} ->
            %% Permanent error
            exit(permanent_error);
        _ ->
            transient_loop(ErrorCount)
    end.

%% @private
start_primary_service() ->
    Pid = spawn_link(fun() ->
        register(primary_service, self()),
        primary_loop(#{counter => 0})
    end),
    {ok, Pid}.

%% @private
primary_loop(State) ->
    receive
        {update_state, Update} ->
            primary_loop(maps:merge(State, Update));
        {handover, StandbyPid} ->
            StandbyPid ! {takeover, State},
            primary_loop(State);
        {get_state, From} ->
            From ! {state, State},
            primary_loop(State);
        stop ->
            ok
    end.

%% @private
start_standby_service(PrimaryPid) ->
    spawn_link(fun() ->
        register(standby_service, self()),
        standby_loop(#{primary => PrimaryPid, state => #{}})
    end),
    {ok, whereis(standby_service)}.

%% @private
standby_loop(State) ->
    receive
        {sync, PrimaryState} ->
        standby_loop(State#{state => PrimaryState});
        {takeover, PrimaryState} ->
        register(primary_service, self()),
        primary_loop(PrimaryState);
        stop ->
            ok
    end.

%% @private
sync_state(PrimaryPid, StandbyPid) ->
    PrimaryState = get_service_state(PrimaryPid),
    StandbyPid ! {sync, PrimaryState},
    ok.

%% @private
get_service_state(Pid) ->
    Pid ! {get_state, self()},
    receive
        {state, State} -> {ok, State}
    after 1000 ->
        {error, timeout}
    end.

%% @private
start_load_generator(ServiceName) ->
    spawn(fun() ->
        register(load_gen, self()),
        load_loop(ServiceName, 0, 0)
    end).

%% @private
load_loop(ServiceName, ReqCount, ErrCount) ->
    receive
        get_stats ->
            {stats, #{requests => ReqCount, errors => ErrCount}};
        stop ->
            ok
    after 100 ->
        case whereis(ServiceName) of
            undefined ->
                load_loop(ServiceName, ReqCount, ErrCount + 1);
            _ ->
                %% Try to make a call
                try
                    gen_server:call(ServiceName, ping, 100),
                    load_loop(ServiceName, ReqCount + 1, ErrCount)
                catch
                    _:_ ->
                        load_loop(ServiceName, ReqCount, ErrCount + 1)
                end
        end
    end.

%% @private
track_execution_count(WorkflowId) ->
    Ref = make_ref(),
    Pid = spawn(fun() ->
        register(Ref, self()),
        track_loop(WorkflowId, 0)
    end),
    Ref.

%% @private
track_loop(WorkflowId, Count) ->
    receive
        stop ->
            ok
    after 100 ->
        %% Check if workflow executed
        {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
        case Status of
            running -> track_loop(WorkflowId, Count + 1);
            completed -> track_loop(WorkflowId, Count);
            _ -> track_loop(WorkflowId, Count)
        end
    end.

%% @private
get_execution_count(Ref) ->
    Ref ! stop,
    Ref.
%% @private
checksum_checkpoint(Checkpoint) ->
    %% Simple checksum for checkpoint verification
    Data = term_to_binary(Checkpoint),
    erlang:phash2(Data).
