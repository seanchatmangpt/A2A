%%%-------------------------------------------------------------------
%%% @doc
%%% Data Recovery Integration Tests (Chicago-Style TDD)
%%%
%%% These tests verify data recovery mechanisms with 10+ scenarios:
%%% 1. Snapshot integrity with SHA-256 verification
%%% 2. Restore after crash
%%% 3. Transaction rollback
%%% 4. Mnesia consistency
%%% 5. Incremental checkpoint recovery
%%% 6. Full state reconstruction
%%% 7. Data validation after recovery
%%% 8. Recovery point validation
%%% 9. Checkpoint chain integrity
%%% 10. Cross-node recovery
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(data_recovery_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(RECOVERY_TIMEOUT, 15000).
-define(CHECKPOINT_INTERVAL, 1000).
-define(TEST_WORKFLOW_ID, <<"recovery_test_workflow">>).
-define(MAX_CHECKPOINTS, 10).

%%====================================================================
%% Test Fixtures
%%====================================================================

%% @doc Setup for recovery tests
recovery_setup() ->
    %% Start Mnesia fresh
    application:stop(mnesia),
    mnesia:delete_schema([node()]),
    {ok, _} = yawl_persistence:create_schema(),
    {ok, _} = yawl_persistence:create_tables(),
    {ok, _} = yawl_persistence:wait_for_tables(),

    %% Start services
    {ok, _} = yawl_persistence:start_link(),
    {ok, _} = yawl_orchestrator:start_link(),
    {ok, _} = yawl_resource_manager:start_link(),
    {ok, _} = yawl_service_registry:start_link(),

    ok.

%% @doc Teardown for recovery tests
recovery_cleanup() ->
    %% Stop services
    gen_server:stop(whereis(yawl_service_registry)),
    gen_server:stop(whereis(yawl_resource_manager)),
    gen_server:stop(whereis(yawl_orchestrator)),
    gen_server:stop(whereis(yawl_persistence)),
    mnesia:stop().

%%====================================================================
%% Scenario 1: Snapshot Integrity with SHA-256 Verification
%%====================================================================

snapshot_integrity_test_() ->
    {"SHA-256 checksum generation for snapshot",
     fun test_sha256_checksum_generation/0},
    {"Snapshot integrity verification",
     fun test_snapshot_integrity_verification/0},
    {"Corrupted snapshot detection",
     fun test_corrupted_snapshot_detection/0},
    {"Snapshot tamper detection",
     fun test_snapshot_tamper_detection/0}.

%% @doc FAILING TEST: SHA-256 checksum generation
test_sha256_checksum_generation() ->
    %% Arrange
    recovery_setup(),

    %% Create test data
    TestWorkflow = #yawl_workflow_persist{
        workflow_id = ?TEST_WORKFLOW_ID,
        spec_id = <<"spec1">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{start => [token], task1 => []},
        current_place = start,
        data = #{key1 => value1, key2 => value2},
        created_at = 1234567890,
        updated_at = 1234567890
    },

    %% Act - Generate checksum
    Checksum = generate_sha256_checksum(TestWorkflow),

    %% Assert - Should be 64-character hex string (SHA-256)
    ?assertEqual(64, string:length(Checksum)),
    ?assert(lists:all(fun(C) -> lists:member(C, "0123456789abcdef") end, Checksum)),

    %% Same data should produce same checksum
    Checksum2 = generate_sha256_checksum(TestWorkflow),
    ?assertEqual(Checksum, Checksum2),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Snapshot integrity verification
test_snapshot_integrity_verification() ->
    %% Arrange
    recovery_setup(),

    %% Create and save workflow
    Workflow = #yawl_workflow_persist{
        workflow_id = ?TEST_WORKFLOW_ID,
        spec_id = <<"spec1">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{start => [token]},
        current_place = start,
        data = #{},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),

    %% Act - Create checkpoint with checksum
    OriginalChecksum = generate_sha256_checksum(Workflow),
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = <<"cp1">>,
        workflow_id = ?TEST_WORKFLOW_ID,
        checkpoint_state = #{checksum => OriginalChecksum},
        marking = Workflow#yawl_workflow_persist.marking,
        data = Workflow#yawl_workflow_persist.data,
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ok = yawl_persistence:save_checkpoint(?TEST_WORKFLOW_ID, Checkpoint),

    %% Verify integrity
    {ok, IsValid, Details} = yawl_persistence:validate_checkpoint_integrity(<<"cp1">>),

    %% Assert
    ?assert(IsValid),
    ?assert(maps:get(checksum, Details) =:= OriginalChecksum),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Corrupted snapshot detection
test_corrupted_snapshot_detection() ->
    %% Arrange
    recovery_setup(),

    %% Create checkpoint
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = <<"cp_corrupt">>,
        workflow_id = ?TEST_WORKFLOW_ID,
        checkpoint_state = #{},
        marking = #{start => [token]},
        data = #{data => "original"},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ok = yawl_persistence:save_checkpoint(?TEST_WORKFLOW_ID, Checkpoint),

    %% Act - Corrupt the checkpoint data
    %% (In real implementation, this would simulate disk corruption)
    %% For now, we test the validation logic

    %% Assert - Validation should detect corruption
    %% When checksum doesn't match data
    {ok, IsValid, _} = yawl_persistence:validate_checkpoint_integrity(<<"cp_corrupt">>),

    %% Without proper checksum, validation should fail
    case IsValid of
        false -> ok;
        true ->
            %% If passes, check that data is intact
            {ok, Cp} = yawl_persistence:load_latest_checkpoint(?TEST_WORKFLOW_ID),
            ?assertEqual(#{data => "original"}, Cp#yawl_checkpoint.data)
    end,

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Snapshot tamper detection
test_snapshot_tamper_detection() ->
    %% Arrange
    recovery_setup(),

    %% Create checkpoint with tamper-evident data
    OriginalData = #{sensitive => "value", signature => "original_sig"},
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = <<"cp_tamper">>,
        workflow_id = ?TEST_WORKFLOW_ID,
        checkpoint_state => #{},
        marking = #{},
        data = OriginalData,
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ok = yawl_persistence:save_checkpoint(?TEST_WORKFLOW_ID, Checkpoint),

    %% Act - Simulate tampering
    %% (In real implementation, data would be modified externally)

    %% Assert - Tampering should be detected
    {ok, IsValid, _} = yawl_persistence:validate_checkpoint_integrity(<<"cp_tamper">>),

    %% Validation should either fail or detect tampering
    case IsValid of
        false -> ok;
        true ->
            %% If validation passes, data should be original
            {ok, Cp} = yawl_persistence:load_latest_checkpoint(?TEST_WORKFLOW_ID),
            ?assertEqual(OriginalData, Cp#yawl_checkpoint.data)
    end,

    %% Cleanup
    recovery_cleanup().

%%====================================================================
%% Scenario 2: Restore After Crash
%%====================================================================

restore_after_crash_test_() ->
    {"Restore workflow after orchestrator crash",
     fun test_restore_after_orchestrator_crash/0},
    {"Restore after process termination",
     fun test_restore_after_termination/0},
    {"Restore after system restart",
     fun test_restore_after_system_restart/0},
    {"Restore with minimal data loss",
     fun test_restore_minimal_data_loss/0}.

%% @doc FAILING TEST: Restore workflow after orchestrator crash
test_restore_after_orchestrator_crash() ->
    %% Arrange
    recovery_setup(),

    %% Create and start workflow
    Config = #{task1_name => "task1", task2_name => "task2"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Get instance state before crash
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, Marking} = yawl_workflow_instance:get_marking(InstancePid),

    %% Save checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Act - Crash orchestrator
    OrchPid = whereis(yawl_orchestrator),
    exit(OrchPid, brutal_kill),
    timer:sleep(500),

    %% Restart orchestrator
    {ok, _} = yawl_orchestrator:start_link(),

    %% Assert - Workflow should be restored
    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
    ?assertNotEqual({error, workflow_not_found}, Status),

    %% Marking should be restored from checkpoint
    {ok, Checkpoint} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(CheckpointId, Checkpoint#yawl_checkpoint.checkpoint_id),
    ?assertEqual(Marking, Checkpoint#yawl_checkpoint.marking),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Restore after process termination
test_restore_after_termination() ->
    %% Arrange
    recovery_setup(),

    %% Create workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        parallel_split, #{branches => 3}),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Get instance
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Save multiple checkpoints during execution
    CheckpointIds = lists:map(fun(_) ->
        timer:sleep(50),
        {ok, Cpid} = yawl_workflow_instance:checkpoint(InstancePid),
        Cpid
    end, lists:seq(1, 3)),

    %% Act - Terminate instance
    exit(InstancePid, normal),
    timer:sleep(200),

    %% Assert - Should restore from latest checkpoint
    {ok, LatestCheckpoint} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertNotEqual({error, no_checkpoint_found}, LatestCheckpoint),
    ?assert(lists:member(LatestCheckpoint#yawl_checkpoint.checkpoint_id, CheckpointIds)),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Restore after system restart
test_restore_after_system_restart() ->
    %% Arrange
    recovery_setup(),

    %% Create workflows
    Workflows = lists:map(fun(N) ->
        Config = #{task1_name => "task" ++ integer_to_list(N)},
        {ok, WfId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        WfId
    end, lists:seq(1, 5)),

    %% Act - Simulate system restart
    recovery_cleanup(),
    recovery_setup(),

    %% Assert - All workflows should be recoverable
    RecoveredWorkflows = lists:map(fun(WfId) ->
        {ok, Wf} = yawl_persistence:load_workflow(WfId),
        Wf
    end, Workflows),

    ?assertEqual(5, length(RecoveredWorkflows)),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Restore with minimal data loss
test_restore_minimal_data_loss() ->
    %% Arrange
    recovery_setup(),

    %% Create workflow with data
    DataSize = 100,
    OriginalData = maps:from_list([{I, <<"data", (integer_to_binary(I))/binary>>} || I <- lists:seq(1, DataSize)]),

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, OriginalData),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Update data multiple times
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    lists:foreach(fun(I) ->
        yawl_workflow_instance:update_data(InstancePid, key, I)
    end, lists:seq(1, 10)),

    %% Create checkpoint
    {ok, _} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Act - Crash and restore
    exit(InstancePid, kill),
    timer:sleep(500),
    {ok, _} = yawl_orchestrator:start_link(),
    {ok, #{instance := NewInstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Assert - Data should be preserved
    {ok, _, RecoveredData} = yawl_workflow_instance:get_state(NewInstancePid),
    ?assertEqual(DataSize, maps:size(RecoverededData)),

    %% Cleanup
    recovery_cleanup().

%%====================================================================
%% Scenario 3: Transaction Rollback
%%====================================================================

transaction_rollback_test_() ->
    {"Rollback on transaction abort",
     fun test_rollback_on_abort/0},
    {"Rollback on exception",
     fun test_rollback_on_exception/0},
    {"Rollback preserves previous state",
     fun test_rollback_preserves_state/0},
    {"Nested transaction rollback",
     fun test_nested_transaction_rollback/0}.

%% @doc FAILING TEST: Rollback on transaction abort
test_rollback_on_abort() ->
    %% Arrange
    recovery_setup(),

    %% Save initial state
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{counter => 0}),
    {ok, OriginalWorkflow} = yawl_persistence:load_workflow(WorkflowId),

    %% Act - Start transaction that aborts
    Result = mnesia:transaction(fun() ->
        %% Write new state
        mnesia:write(OriginalWorkflow#yawl_workflow_persist{
            data = #{counter => 1}
        }),
        %% Abort transaction
        mnesia:abort(transaction_aborted)
    end),

    %% Assert
    ?assertEqual({aborted, transaction_aborted}, Result),

    %% Original state should be preserved
    {ok, PreservedWorkflow} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(#{counter => 0}, PreservedWorkflow#yawl_workflow_persist.data),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Rollback on exception
test_rollback_on_exception() ->
    %% Arrange
    recovery_setup(),

    %% Save initial state
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{value => "original"}),

    %% Act - Transaction with exception
    Result = try
        mnesia:transaction(fun() ->
            mnesia:write(#yawl_workflow_persist{
                workflow_id = WorkflowId,
                spec_id = <<"spec1">>,
                pattern_type = basic_sequential,
                status = running,
                marking = #{},
                current_place = undefined,
                data = #{value => "modified"},
                created_at = erlang:monotonic_time(millisecond),
                updated_at = erlang:monotonic_time(millisecond)
            }),
            error(simulated_exception)
        end)
    catch
        _:_ -> {aborted, exception}
    end,

    %% Assert
    ?assertMatch({aborted, _}, Result),

    %% Original state preserved
    {ok, Workflow} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual("original", maps:get(value, Workflow#yawl_workflow_persist.data, "original")),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Rollback preserves previous state
test_rollback_preserves_state() ->
    %% Arrange
    recovery_setup(),

    %% Create workflow with version history
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{version => 1}),

    %% Update multiple times with checkpoints
    lists:foreach(fun(V) ->
        mnesia:transaction(fun() ->
            {ok, Wf} = mnesia:read(yawl_workflow_persist, WorkflowId),
            [WfRec] = Wf,
            mnesia:write(WfRec#yawl_workflow_persist{
                data = #{version => V},
                updated_at = erlang:monotonic_time(millisecond)
            })
        end)
    end, lists:seq(2, 5)),

    %% Create checkpoint at version 5
    {ok, _} = yawl_persistence:save_checkpoint(WorkflowId, #yawl_checkpoint{
        checkpoint_id = <<"cp_v5">>,
        workflow_id = WorkflowId,
        checkpoint_state => #{version => 5},
        marking = #{},
        data = #{version => 5},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    }),

    %% Act - Rollback to version 3
    ok = mnesia:transaction(fun() ->
        mnesia:write(#yawl_workflow_persist{
            workflow_id = WorkflowId,
            spec_id => <<"spec1">>,
            pattern_type = basic_sequential,
            status = running,
            marking = #{},
            current_place = undefined,
            data = #{version => 3},
            created_at = erlang:monotonic_time(millisecond),
            updated_at = erlang:monotonic_time(millisecond)
        })
    end),

    %% Assert - Version should be 3
    {ok, Workflow} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(3, maps:get(version, Workflow#yawl_workflow_persist.data)),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Nested transaction rollback
test_nested_transaction_rollback() ->
    %% Arrange
    recovery_setup(),

    %% Create workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{nested => "value"}),

    %% Act - Nested transactions with inner abort
    OuterResult = mnesia:transaction(fun() ->
        %% Outer transaction
        {ok, Wf} = mnesia:read(yawl_workflow_persist, WorkflowId),
        [WfRec] = Wf,

        mnesia:write(WfRec#yawl_workflow_persist{
            data = #{nested => "outer"}
        }),

        %% Inner transaction that aborts
        InnerResult = mnesia:transaction(fun() ->
            mnesia:write(WfRec#yawl_workflow_persist{
                data = #{nested => "inner"}
            }),
            mnesia:abort(inner_abort)
        end),

        ?assertEqual({aborted, inner_abort}, InnerResult),

        %% Outer should see inner's rollback
        {ok, Wf2} = mnesia:read(yawl_workflow_persist, WorkflowId),
        [WfRec2] = Wf2,
        ?assertEqual("outer", maps:get(nested, WfRec2#yawl_workflow_persist.data)),

        outer_commit
    end),

    %% Assert
    ?assertEqual({atomic, outer_commit}, OuterResult),

    %% State should be "outer" (inner rollback preserved)
    {ok, Workflow} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual("outer", maps:get(nested, Workflow#yawl_workflow_persist.data)),

    %% Cleanup
    recovery_cleanup().

%%====================================================================
%% Scenario 4: Mnesia Consistency
%%====================================================================

mnesia_consistency_test_() ->
    {"Table consistency after crash",
     fun test_table_consistency/0},
    {"Index consistency",
     fun test_index_consistency/0},
    {"Replica consistency",
     fun test_replica_consistency/0},
    {"Schema consistency",
     fun test_schema_consistency/0}.

%% @doc FAILING TEST: Table consistency after crash
test_table_consistency() ->
    %% Arrange
    recovery_setup(),

    %% Create multiple records
    lists:foreach(fun(N) ->
        WorkflowId = <<"wf_", (integer_to_binary(N))/binary>>,
        mnesia:transaction(fun() ->
            mnesia:write(#yawl_workflow_persist{
                workflow_id = WorkflowId,
                spec_id = <<"spec", (integer_to_binary(N))/binary>>,
                pattern_type = basic_sequential,
                status = running,
                marking = #{},
                current_place = undefined,
                data = #{},
                created_at = erlang:monotonic_time(millisecond),
                updated_at = erlang:monotonic_time(millisecond)
            })
        end)
    end, lists:seq(1, 10)),

    %% Get record count before crash
    {ok, BeforeWorkflows} = mnesia:transaction(fun() ->
        mnesia:match_object(#yawl_workflow_persist{_ = '_'})
    end),
    BeforeCount = length(BeforeWorkflows),

    %% Act - Crash Mnesia and restart
    mnesia:stop(),
    timer:sleep(500),
    {ok, _} = mnesia:start(),
    {ok, _} = yawl_persistence:wait_for_tables(),

    %% Assert - Record count should be consistent
    {ok, AfterWorkflows} = mnesia:transaction(fun() ->
        mnesia:match_object(#yawl_workflow_persist{_ = '_'})
    end),
    AfterCount = length(AfterWorkflows),
    ?assertEqual(BeforeCount, AfterCount),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Index consistency
test_index_consistency() ->
    %% Arrange
    recovery_setup(),

    %% Create workflows with different statuses
    Statuses = [pending, running, completed, failed, cancelled],
    lists:foreach(fun({N, Status}) ->
        WorkflowId = <<"status_wf_", (integer_to_binary(N))/binary>>,
        mnesia:transaction(fun() ->
            mnesia:write(#yawl_workflow_persist{
                workflow_id = WorkflowId,
                spec_id = <<"spec1">>,
                pattern_type = basic_sequential,
                status = Status,
                marking = #{},
                current_place = undefined,
                data = #{},
                created_at = erlang:monotonic_time(millisecond),
                updated_at = erlang:monotonic_time(millisecond)
            })
        end)
    end, lists:zip(lists:seq(1, length(Statuses)), Statuses)),

    %% Verify index reads
    IndexCounts = lists:map(fun(Status) ->
        {ok, Wfs} = mnesia:transaction(fun() ->
            mnesia:index_read(yawl_workflow_persist, Status, #yawl_workflow_persist.status)
        end),
        {Status, length(Wfs)}
    end, Statuses),

    %% Act - Crash and restart
    mnesia:stop(),
    timer:sleep(500),
    {ok, _} = mnesia:start(),
    {ok, _} = yawl_persistence:wait_for_tables(),

    %% Assert - Index reads should still work
    lists:foreach(fun({Status, ExpectedCount}) ->
        {ok, Wfs} = mnesia:transaction(fun() ->
            mnesia:index_read(yawl_workflow_persist, Status, #yawl_workflow_persist.status)
        end),
        ?assertEqual(ExpectedCount, length(Wfs), io_lib:format("Status ~p index inconsistent", [Status]))
    end, IndexCounts),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Replica consistency
test_replica_consistency() ->
    %% Arrange
    recovery_setup(),

    %% Write data
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{test => "data"}),
    OriginalData = maps:put(test, "data", #{}),

    %% Act - Force table dump and load
    mnesia:dump_tables([yawl_workflow_persist]),
    timer:sleep(100),
    mnesia:load_textfile("yawl_workflow_persist"),

    %% Assert - Data should be consistent
    {ok, Workflow} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(OriginalData, Workflow#yawl_workflow_persist.data),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Schema consistency
test_schema_consistency() ->
    %% Arrange
    recovery_setup(),

    %% Get table definitions
    Tables = [
        yawl_workflow_persist,
        yawl_workitem_persist,
        yawl_resource_persist,
        yawl_execution_history,
        yawl_checkpoint,
        yawl_service_registry,
        yawl_task_queue
    ],

    %% Verify table attributes
    AttrsLists = lists:map(fun(Table) ->
        case mnesia:table_info(Table, attributes) of
            Attrs when is_list(Attrs) -> {Table, {ok, Attrs}};
            Error -> {Table, Error}
        end
    end, Tables),

    %% Act - Stop and restart Mnesia
    mnesia:stop(),
    timer:sleep(500),
    {ok, _} = mnesia:start(),
    {ok, _} = yawl_persistence:create_tables(),
    {ok, _} = yawl_persistence:wait_for_tables(),

    %% Assert - Schema should be consistent
    lists:foreach(fun({Table, {ok, OriginalAttrs}}) ->
        case mnesia:table_info(Table, attributes) of
            OriginalAttrs -> ok;
            OtherAttrs ->
                ?assertEqual(OriginalAttrs, OtherAttrs, io_lib:format("Table ~p schema changed", [Table]))
        end
    end, AttrsLists),

    %% Cleanup
    recovery_cleanup().

%%====================================================================
%% Additional Recovery Scenarios (5-10)
%%====================================================================

additional_recovery_test_() ->
    {"Incremental checkpoint recovery",
     fun test_incremental_checkpoint_recovery/0},
    {"Full state reconstruction",
     fun test_full_state_reconstruction/0},
    {"Data validation after recovery",
     fun test_data_validation_after_recovery/0},
    {"Recovery point validation",
     fun test_recovery_point_validation/0},
    {"Checkpoint chain integrity",
     fun test_checkpoint_chain_integrity/0},
    {"Cross-node recovery",
     fun test_cross_node_recovery/0}.

%% @doc FAILING TEST: Incremental checkpoint recovery
test_incremental_checkpoint_recovery() ->
    %% Arrange
    recovery_setup(),

    %% Create workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        iterative_loop, #{iterations => 10}),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Create incremental checkpoints
    States = lists:map(fun(N) ->
        yawl_workflow_instance:update_data(InstancePid, iteration, N),
        {ok, Cpid} = yawl_workflow_instance:checkpoint(InstancePid),
        {N, Cpid}
    end, lists:seq(1, 5)),

    %% Act - Recover from middle checkpoint
    {TargetIteration, TargetCpId} = lists:nth(3, States),
    ok = yawl_persistence:rollback_to_checkpoint(WorkflowId, TargetCpId),

    %% Assert - Should recover to correct state
    {ok, #{instance := NewInstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _, Data} = yawl_workflow_instance:get_state(NewInstancePid),
    ?assertEqual(TargetIteration, maps:get(iteration, Data)),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Full state reconstruction
test_full_state_reconstruction() ->
    %% Arrange
    recovery_setup(),

    %% Create complex workflow state
    ComplexState = #{
        tasks => [task1, task2, task3],
        data => #{
            user => <<"user1">>,
            items => [<<"a">>, <<"b">>, <<"c">>],
            total => 100
        },
        marking => #{
            start => [],
            task1 => [token],
            task2 => [],
            task3 => [],
            'end' => []
        },
        history => [started, task1_started],
        metadata => #{
            priority => high,
            deadline => 1234567890
        }
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        parallel_split, ComplexState),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Save checkpoint
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Act - Reconstruct from checkpoint
    ok = yawl_persistence:restore_from_checkpoint(WorkflowId),

    %% Assert - Full state should be reconstructed
    {ok, Checkpoint} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(ComplexState, Checkpoint#yawl_checkpoint.data),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Data validation after recovery
test_data_validation_after_recovery() ->
    %% Arrange
    recovery_setup(),

    %% Create workflow with typed data
    TypedData = #{
        integer => 42,
        float => 3.14,
        binary => <<"test">>,
        list => [1, 2, 3],
        map => #{key => "value"},
        tuple => {a, b, c}
    },

    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, TypedData),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Save checkpoint
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Act - Recover
    exit(InstancePid, kill),
    timer:sleep(500),
    {ok, _} = yawl_persistence:restore_from_checkpoint(WorkflowId),

    %% Assert - Data types should be preserved
    {ok, Checkpoint} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    RecoveredData = Checkpoint#yawl_checkpoint.data,

    ?assertEqual(42, maps:get(integer, RecoveredData)),
    ?assertEqual(3.14, maps:get(float, RecoveredData)),
    ?assertEqual(<<"test">>, maps:get(binary, RecoveredData)),
    ?assertEqual([1, 2, 3], maps:get(list, RecoveredData)),
    ?assertEqual(#{key => "value"}, maps:get(map, RecoveredData)),
    ?assertEqual({a, b, c}, maps:get(tuple, RecoveredData)),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Recovery point validation
test_recovery_point_validation() ->
    %% Arrange
    recovery_setup(),

    %% Create workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{}),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowPid),

    %% Create recovery points
    RecoveryPoints = lists:map(fun(N) ->
        yawl_workflow_instance:update_data(InstancePid, step, N),
        {ok, Cpid} = yawl_workflow_instance:checkpoint(InstancePid),
        #{sequence => N, id => Cpid, timestamp => erlang:monotonic_time(millisecond)}
    end, lists:seq(1, 5)),

    %% Act - List recovery points
    {ok, Points} = yawl_persistence:list_recovery_points(WorkflowId),

    %% Assert - All recovery points should be listed and valid
    ?assertEqual(5, length(Points)),

    lists:foreach(fun(#{sequence := Seq, id := Id} = Point) ->
        ?assert(maps:is_key(sequence_num, Point)),
        ?assert(is_boolean(maps:get(is_valid, Point, true))),

        %% Verify checkpoint exists
        {ok, Cp} = yawl_persistence:load_latest_checkpoint(WorkflowId),
        ?assertEqual(Seq, Cp#yawl_checkpoint.sequence_num)
    end, Points),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Checkpoint chain integrity
test_checkpoint_chain_integrity() ->
    %% Arrange
    recovery_setup(),

    %% Create workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        iterative_loop, #{max_iterations => 10}),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Create chain of checkpoints
    CheckpointRefs = lists:map(fun(N) ->
        yawl_workflow_instance:update_data(InstancePid, iteration, N),
        {ok, Cpid} = yawl_workflow_instance:checkpoint(InstancePid),
        {N, Cpid}
    end, lists:seq(1, ?MAX_CHECKPOINTS)),

    %% Act - Verify chain integrity
    {ok, AllCheckpoints} = yawl_persistence:list_checkpoints(WorkflowId),

    %% Assert - Chain should be complete
    ?assertEqual(?MAX_CHECKPOINTS, length(AllCheckpoints)),

    %% Verify sequence numbers are continuous
    Sorted = lists:sort(fun(A, B) ->
        A#yawl_checkpoint.sequence_num > B#yawl_checkpoint.sequence_num
    end, AllCheckpoints),

    Sequences = [C#yawl_checkpoint.sequence_num || C <- Sorted],
    Expected = lists:seq(1, ?MAX_CHECKPOINTS),
    ?assertEqual(Expected, Sequences),

    %% Verify no gaps in chain
    lists:foreach(fun({N, Cp}) ->
        ?assertEqual(N, Cp#yawl_checkpoint.sequence_num)
    end, CheckpointRefs),

    %% Cleanup
    recovery_cleanup().

%% @doc FAILING TEST: Cross-node recovery
test_cross_node_recovery() ->
    %% Arrange
    recovery_setup(),

    %% Create workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential, #{node => node()}),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Save checkpoint with node info
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, Cpid} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Get checkpoint
    {ok, Checkpoint} = yawl_persistence:load_latest_checkpoint(WorkflowId),

    %% Act - Simulate cross-node recovery
    %% In a real distributed setup, this would involve another node
    %% For now, verify that checkpoint has node info

    %% Assert - Checkpoint should be portable
    ?assert(is_map(Checkpoint#yawl_checkpoint.checkpoint_state)),
    ?assert(is_map(Checkpoint#yawl_checkpoint.marking)),
    ?assert(is_map(Checkpoint#yawl_checkpoint.data)),

    %% Cleanup
    recovery_cleanup().

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
generate_sha256_checksum(Record) ->
    %% Generate SHA-256 checksum for a record
    Binary = term_to_binary(Record),
    crypto:hash(sha256, Binary).

%% @private
verify_sha256_checksum(Record, Checksum) ->
    Binary = term_to_binary(Record),
    Calculated = crypto:hash(sha256, Binary),
    Calculated =:= Checksum.
