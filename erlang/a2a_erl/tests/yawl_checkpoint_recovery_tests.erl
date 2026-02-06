%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL Checkpoint Recovery
%%%
%%% Tests checkpoint creation, persistence, and recovery functionality.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_checkpoint_recovery_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

checkpoint_recovery_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Create checkpoint and save to persistence", fun test_checkpoint_creation/0},
      {"Save multiple checkpoints and retrieve latest", fun test_multiple_checkpoints/0},
      {"Restore workflow from checkpoint", fun test_restore_from_checkpoint/0},
      {"Workflow instance restart from checkpoint", fun test_workflow_restart/0},
      {"Checkpoint recovery error handling", fun test_checkpoint_error_handling/0},
      {"Checkpoint at critical workflow points", fun test_critical_point_checkpoints/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Create unique Mnesia directory for this test run
    TestDir = "/tmp/yawl_checkpoint_recovery_test_" ++ integer_to_list(erlang:unique_integer()),
    application:stop(mnesia),
    ok = filelib:ensure_dir(TestDir ++ "/"),
    application:set_env(mnesia, dir, TestDir),
    yawl_persistence:create_schema(),
    mnesia:start(),
    {ok, _} = yawl_persistence:create_tables(),
    ok = yawl_persistence:wait_for_tables(),
    {ok, _} = yawl_persistence:start_link(),
    TestDir.

cleanup(TestDir) ->
    yawl_persistence:stop(),
    mnesia:stop(),
    application:unset_env(mnesia, dir),
    %% Clean up test directory
    case file:del_dir_r(TestDir) of
        ok -> ok;
        {error, _} -> ok
    end.

%%====================================================================
%% Test Cases
%%====================================================================

test_checkpoint_creation() ->
    WorkflowId = <<"$test_checkpoint_wf">>,

    %% Create test data
    TestMarking = #{start => [token], task1 => []},
    TestData = #{workflow_key => "workflow_value"},

    CheckpointId = <<"$checkpoint_1">>,
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = CheckpointId,
        workflow_id = WorkflowId,
        checkpoint_state = #{test_data => "state"},
        marking = TestMarking,
        data = TestData,
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },

    %% Save checkpoint
    ?assertEqual(ok, yawl_persistence:save_checkpoint(WorkflowId, Checkpoint)),

    %% Verify checkpoint was saved
    {ok, LoadedCheckpoint} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(CheckpointId, LoadedCheckpoint#yawl_checkpoint.checkpoint_id),
    ?assertEqual(WorkflowId, LoadedCheckpoint#yawl_checkpoint.workflow_id),
    ?assertEqual(TestMarking, LoadedCheckpoint#yawl_checkpoint.marking),
    ?assertEqual(TestData, LoadedCheckpoint#yawl_checkpoint.data),
    ok.

test_multiple_checkpoints() ->
    WorkflowId = <<"$test_multiple_cp_wf">>,

    %% Create first checkpoint
    Checkpoint1 = #yawl_checkpoint{
        checkpoint_id = <<"$cp_1">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{step => 1},
        marking = #{start => [token]},
        data = #{step => 1},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ?assertEqual(ok, yawl_persistence:save_checkpoint(WorkflowId, Checkpoint1)),

    %% Create second checkpoint
    Checkpoint2 = #yawl_checkpoint{
        checkpoint_id = <<"$cp_2">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{step => 2},
        marking = #{start => [token], task1 => [token]},
        data = #{step => 2, result => "task1_completed"},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 2
    },
    ?assertEqual(ok, yawl_persistence:save_checkpoint(WorkflowId, Checkpoint2)),

    %% Create third checkpoint
    Checkpoint3 = #yawl_checkpoint{
        checkpoint_id = <<"$cp_3">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{step => 3},
        marking = #{task1 => [], task2 => [token]},
        data = #{step => 3, task1_result => "completed"},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 3
    },
    ?assertEqual(ok, yawl_persistence:save_checkpoint(WorkflowId, Checkpoint3)),

    %% Verify we get the latest checkpoint
    {ok, LatestCheckpoint} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(<<"$cp_3">>, LatestCheckpoint#yawl_checkpoint.checkpoint_id),
    ?assertEqual(3, LatestCheckpoint#yawl_checkpoint.sequence_num),

    %% Verify we can list all checkpoints
    {ok, AllCheckpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assertEqual(3, length(AllCheckpoints)),

    %% Verify sequence order
    SortedCheckpoints = lists:sort(fun(A, B) ->
        A#yawl_checkpoint.sequence_num =< B#yawl_checkpoint.sequence_num
    end, AllCheckpoints),
    ?assertEqual(1, lists:nth(1, SortedCheckpoints)#yawl_checkpoint.sequence_num),
    ?assertEqual(3, lists:nth(3, SortedCheckpoints)#yawl_checkpoint.sequence_num),
    ok.

test_restore_from_checkpoint() ->
    WorkflowId = <<"$test_restore_wf">>,

    %% Create initial workflow
    InitialWorkflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"test_spec">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{start => [token]},
        data = #{initial => true},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ?assertEqual(ok, yawl_persistence:save_workflow(InitialWorkflow)),

    %% Create checkpoint with different state
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = <<"$restore_checkpoint">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{step => "mid_workflow"},
        marking = #{task1 => [token]},
        data = #{progress => "50%", task1_started => true},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ?assertEqual(ok, yawl_persistence:save_checkpoint(WorkflowId, Checkpoint)),

    %% Restore from checkpoint
    {ok, RestoredCheckpoint} = yawl_persistence:restore_from_checkpoint(WorkflowId),

    %% Verify checkpoint data
    ?assertEqual(<<"$restore_checkpoint">>, RestoredCheckpoint#yawl_checkpoint.checkpoint_id),
    ?assertEqual(#{task1 => [token]}, RestoredCheckpoint#yawl_checkpoint.marking),
    ?assertEqual(#{progress => "50%", task1_started => true}, RestoredCheckpoint#yawl_checkpoint.data),

    %% Verify workflow was updated
    {ok, RestoredWorkflow} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(#{task1 => [token]}, RestoredWorkflow#yawl_workflow_persist.marking),
    ?assertEqual(#{progress => "50%", task1_started => true}, RestoredWorkflow#yawl_workflow_persist.data),
    ?assertEqual(running, RestoredWorkflow#yawl_workflow_persist.status),
    ok.

test_workflow_restart() ->
    WorkflowId = <<"$test_restart_wf">>,
    Config = #{
        pattern_type => basic_sequential,
        workflow_data => #{initial_data => "test_value"}
    },

    %% Start workflow instance
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Create initial checkpoint
    {ok, CheckpointId1} = yawl_workflow_instance:checkpoint(Pid),
    ?assert(is_binary(CheckpointId1)),

    %% Simulate some workflow state changes
    {ok, idle, _State1} = yawl_workflow_instance:get_state(Pid),
    ok = yawl_workflow_instance:start_workflow(Pid),

    %% Create another checkpoint after starting
    {ok, CheckpointId2} = yawl_workflow_instance:checkpoint(Pid),
    ?assert(is_binary(CheckpointId2)),
    ?assertNotEqual(CheckpointId1, CheckpointId2),

    %% Restart from checkpoint
    ?assertEqual(ok, yawl_workflow_instance:restart_from_checkpoint(Pid, WorkflowId)),

    %% Verify workflow state after restart
    {ok, State, StateData} = yawl_workflow_instance:get_state(Pid),
    ?assertEqual(State, running),
    ?assert(maps:is_key(workflow_id, StateData)),
    ?assertEqual(WorkflowId, maps:get(workflow_id, StateData)),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

test_checkpoint_error_handling() ->
    %% Test restoring from non-existent workflow
    WorkflowId = <<"$nonexistent_wf">>,
    {error, no_checkpoint_found} = yawl_persistence:restore_from_checkpoint(WorkflowId),

    %% Test checkpoint creation with invalid data
    InvalidCheckpoint = #yawl_checkpoint{
        checkpoint_id = <<"$invalid_cp">>,
        workflow_id = <<>>,
        checkpoint_state = #{},
        marking = #{},
        data = #{},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ?assertMatch({error, _}, yawl_persistence:save_checkpoint(<<>>, InvalidCheckpoint)),

    %% Test checkpoint deletion
    NonExistentCheckpointId = <<"$nonexistent_cp">>,
    ?assertEqual(ok, yawl_persistence:delete_checkpoint(NonExistentCheckpointId)),
    ok.

test_critical_point_checkpoints() ->
    WorkflowId = <<"$critical_points_wf">>,

    %% Create workflow with sequential pattern
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{critical_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Initial checkpoint in idle state
    {ok, InitialCheckpoint} = yawl_workflow_instance:checkpoint(Pid),

    %% Start workflow
    ok = yawl_workflow_instance:start_workflow(Pid),

    %% Checkpoint after starting
    {ok, RunningCheckpoint} = yawl_workflow_instance:checkpoint(Pid),

    %% Simulate task completion
    {ok, _Marking} = yawl_workflow_instance:complete_task(Pid, task1, #{result => "completed"}),

    %% Checkpoint after task completion
    {ok, CompletedCheckpoint} = yawl_workflow_instance:checkpoint(Pid),

    %% Verify checkpoints are different
    ?assertNotEqual(InitialCheckpoint, RunningCheckpoint),
    ?assertNotEqual(RunningCheckpoint, CompletedCheckpoint),

    %% Verify data persistence
    {ok, WorkflowState} = yawl_workflow_instance:get_state(Pid),
    ?assert(maps:is_key(completed_tasks, WorkflowState)),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% Periodic Checkpoint Tests
%%====================================================================

test_periodic_checkpoint_creation() ->
    WorkflowId = <<"$periodic_cp_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{periodic_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Enable periodic checkpoints with short interval
    Interval = 100,  %% 100ms for testing
    {ok, _} = yawl_persistence:enable_periodic_checkpoints(Interval),

    %% Start workflow
    ok = yawl_workflow_instance:start_workflow(Pid),

    %% Wait for periodic checkpoint to be created
    timer:sleep(150),

    %% Verify checkpoint was created
    {ok, Checkpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assert(length(Checkpoints) > 0),

    %% Cleanup
    yawl_persistence:disable_periodic_checkpoints(),
    gen_statem:stop(Pid),
    ok.

test_periodic_checkpoint_disabled() ->
    WorkflowId = <<"$periodic_disabled_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{periodic_disabled_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Ensure periodic checkpoints are disabled
    yawl_persistence:disable_periodic_checkpoints(),

    %% Start workflow
    ok = yawl_workflow_instance:start_workflow(Pid),

    %% Wait
    timer:sleep(150),

    %% Create manual checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(Pid),

    %% Verify only manual checkpoint exists
    {ok, Checkpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assertEqual(1, length(Checkpoints)),
    ?assertEqual(CheckpointId, (hd(Checkpoints))#yawl_checkpoint.checkpoint_id),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% Rollback Recovery Tests
%%====================================================================

test_rollback_to_checkpoint() ->
    WorkflowId = <<"$rollback_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{rollback_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Create initial checkpoint
    {ok, CheckpointId1} = yawl_workflow_instance:checkpoint(Pid),

    %% Start workflow
    ok = yawl_workflow_instance:start_workflow(Pid),

    %% Complete a task
    {ok, _Marking} = yawl_workflow_instance:complete_task(Pid, task1, #{result => "completed"}),

    %% Create second checkpoint
    {ok, CheckpointId2} = yawl_workflow_instance:checkpoint(Pid),

    %% Simulate error by completing another task
    {ok, _Marking2} = yawl_workflow_instance:complete_task(Pid, task2, #{result => "error"}),

    %% Rollback to first checkpoint
    ?assertEqual(ok, yawl_persistence:rollback_to_checkpoint(WorkflowId, CheckpointId1)),

    %% Restart workflow from checkpoint
    ?assertEqual(ok, yawl_workflow_instance:restart_from_checkpoint(Pid, WorkflowId)),

    %% Verify state was rolled back
    {ok, _State, StateData} = yawl_workflow_instance:get_state(Pid),
    ?assert(maps:is_key(workflow_id, StateData)),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

test_rollback_nonexistent_checkpoint() ->
    WorkflowId = <<"$rollback_nonexistent_wf">>,
    NonExistentCheckpointId = <<"$nonexistent_cp">>,

    %% Attempt rollback to non-existent checkpoint
    Result = yawl_persistence:rollback_to_checkpoint(WorkflowId, NonExistentCheckpointId),
    ?assertMatch({error, checkpoint_not_found}, Result),

    ok.

%%====================================================================
%% Recovery Points Tests
%%====================================================================

test_list_recovery_points() ->
    WorkflowId = <<"$recovery_points_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{recovery_points_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Create multiple checkpoints
    {ok, CP1} = yawl_workflow_instance:checkpoint(Pid),
    ok = yawl_workflow_instance:start_workflow(Pid),
    {ok, CP2} = yawl_workflow_instance:checkpoint(Pid),
    {ok, _} = yawl_workflow_instance:complete_task(Pid, task1, #{result => "done"}),
    {ok, CP3} = yawl_workflow_instance:checkpoint(Pid),

    %% List recovery points
    {ok, RecoveryPoints} = yawl_persistence:list_recovery_points(WorkflowId),
    ?assert(length(RecoveryPoints) >= 3),

    %% Verify recovery points are sorted by sequence (newest first)
    ?assertEqual(CP3, maps:get(checkpoint_id, hd(RecoveryPoints))),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

test_cleanup_old_checkpoints() ->
    WorkflowId = <<"$cleanup_checkpoints_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{cleanup_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Create multiple checkpoints
    {ok, _CP1} = yawl_workflow_instance:checkpoint(Pid),
    ok = yawl_workflow_instance:start_workflow(Pid),
    {ok, _CP2} = yawl_workflow_instance:checkpoint(Pid),
    {ok, _} = yawl_workflow_instance:complete_task(Pid, task1, #{result => "done"}),
    {ok, _CP3} = yawl_workflow_instance:checkpoint(Pid),
    {ok, _} = yawl_workflow_instance:complete_task(Pid, task2, #{result => "done2"}),
    {ok, _CP4} = yawl_workflow_instance:checkpoint(Pid),
    {ok, _} = yawl_workflow_instance:complete_task(Pid, task3, #{result => "done3"}),
    {ok, _CP5} = yawl_workflow_instance:checkpoint(Pid),

    %% Keep only 2 most recent checkpoints
    {ok, DeletedCount} = yawl_persistence:cleanup_old_checkpoints(WorkflowId, 2),
    ?assert(DeletedCount >= 3),

    %% Verify only 2 checkpoints remain
    {ok, RemainingCheckpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assertEqual(2, length(RemainingCheckpoints)),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% Checkpoint Integrity Tests
%%====================================================================

test_validate_checkpoint_integrity() ->
    WorkflowId = <<"$integrity_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{integrity_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Create checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(Pid),

    %% Validate checkpoint integrity
    {ok, IsValid, Checks} = yawl_persistence:validate_checkpoint_integrity(CheckpointId),
    ?assert(IsValid),
    ?assert(maps:get(has_workflow_id, Checks)),
    ?assert(maps:get(has_marking, Checks)),
    ?assert(maps:get(has_sequence, Checks)),
    ?assert(maps:get(has_timestamp, Checks)),
    ?assert(maps:get(data_integrity, Checks)),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

test_validate_nonexistent_checkpoint() ->
    NonExistentCheckpointId = <<"$nonexistent_integrity_cp">>,

    %% Attempt to validate non-existent checkpoint
    Result = yawl_persistence:validate_checkpoint_integrity(NonExistentCheckpointId),
    ?assertMatch({error, checkpoint_not_found}, Result),

    ok.

%%====================================================================
%% Recovery Status Tests
%%====================================================================

test_get_recovery_status() ->
    WorkflowId = <<"$recovery_status_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{recovery_status_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Create checkpoint
    {ok, _CheckpointId} = yawl_workflow_instance:checkpoint(Pid),

    %% Get recovery status
    {ok, Status} = yawl_persistence:get_recovery_status(WorkflowId),
    ?assert(maps:is_key(status, Status)),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% System Crash Recovery Tests
%%====================================================================

test_recovery_after_system_crash() ->
    WorkflowId = <<"$crash_recovery_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{crash_recovery_test => true}
    },

    %% Start workflow
    {ok, Pid1} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Start workflow
    ok = yawl_workflow_instance:start_workflow(Pid1),

    %% Create checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(Pid1),

    %% Complete a task
    {ok, _Marking} = yawl_workflow_instance:complete_task(Pid1, task1, #{result => "crash_test"}),

    %% Simulate system crash by stopping the process
    gen_statem:stop(Pid1),

    %% Create new workflow instance (simulating restart)
    {ok, Pid2} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Restart from checkpoint
    ?assertEqual(ok, yawl_workflow_instance:restart_from_checkpoint(Pid2, WorkflowId)),

    %% Verify state was recovered
    {ok, _State, StateData} = yawl_workflow_instance:get_state(Pid2),
    ?assertEqual(WorkflowId, maps:get(workflow_id, StateData, undefined)),

    %% Cleanup
    gen_statem:stop(Pid2),
    ok.

%%====================================================================
%% Concurrent Recovery Tests
%%====================================================================

test_concurrent_checkpoint_creation() ->
    WorkflowId = <<"$concurrent_cp_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{concurrent_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Create multiple checkpoints concurrently
    CheckpointResults = lists:map(fun(_) ->
        spawn_monitor(fun() ->
            yawl_workflow_instance:checkpoint(Pid)
        end)
    end, lists:seq(1, 5)),

    %% Wait for all checkpoints to complete
    timer:sleep(100),

    %% Verify all checkpoints were created
    {ok, Checkpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assert(length(Checkpoints) >= 1),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

test_concurrent_rollback_operations() ->
    WorkflowId = <<"$concurrent_rollback_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{concurrent_rollback_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Create initial checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(Pid),

    %% Start multiple concurrent rollback operations
    %% (This tests that the system handles concurrent recovery requests)
    RollbackResults = lists:map(fun(_) ->
        spawn(fun() ->
            yawl_persistence:rollback_to_checkpoint(WorkflowId, CheckpointId)
        end)
    end, lists:seq(1, 3)),

    %% Wait for operations to complete
    timer:sleep(100),

    %% Verify system is still functional
    {ok, _State, _StateData} = yawl_workflow_instance:get_state(Pid),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% Data Consistency Tests
%%====================================================================

test_checkpoint_data_consistency() ->
    WorkflowId = <<"$data_consistency_wf">>,

    %% Create workflow with complex data
    ComplexData = #{
        nested_map => #{
            level1 => #{
                level2 => #{value => "deep"}
            }
        },
        list_values => [1, 2, 3, 4, 5],
        mixed_types => #{
            integer => 42,
            float => 3.14,
            binary => <<"test">>,
            atom => test_atom
        }
    },

    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => ComplexData
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Create checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(Pid),

    %% Load checkpoint and verify data
    {ok, Checkpoint} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(CheckpointId, Checkpoint#yawl_checkpoint.checkpoint_id),

    CheckpointData = Checkpoint#yawl_checkpoint.data,
    ?assertEqual(<<"deep">>, maps:get(value, maps:get(level2,
        maps:get(level1, maps:get(nested_map, CheckpointData))))),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

test_recovery_preserves_workflow_history() ->
    WorkflowId = <<"$history_preservation_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{history_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Perform some operations
    ok = yawl_workflow_instance:start_workflow(Pid),
    {ok, _} = yawl_workflow_instance:complete_task(Pid, task1, #{result => "task1_done"}),

    %% Create checkpoint
    {ok, _CheckpointId} = yawl_workflow_instance:checkpoint(Pid),

    %% Perform more operations
    {ok, _} = yawl_workflow_instance:complete_task(Pid, task2, #{result => "task2_done"}),

    %% Rollback to checkpoint
    {ok, Checkpoint} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ok = yawl_persistence:rollback_to_checkpoint(WorkflowId, Checkpoint#yawl_checkpoint.checkpoint_id),

    %% Restart from checkpoint
    ok = yawl_workflow_instance:restart_from_checkpoint(Pid, WorkflowId),

    %% Verify workflow history was preserved
    {ok, History} = yawl_persistence:get_workflow_history(WorkflowId),
    ?assert(length(History) > 0),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

%%====================================================================
%% Performance Tests
%%====================================================================

test_checkpoint_performance() ->
    WorkflowId = <<"$perf_cp_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{performance_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Measure checkpoint creation time
    NumCheckpoints = 10,
    Start = erlang:monotonic_time(microsecond),

    lists:foreach(fun(_) ->
        {ok, _} = yawl_workflow_instance:checkpoint(Pid)
    end, lists:seq(1, NumCheckpoints)),

    End = erlang:monotonic_time(microsecond),
    Duration = End - Start,
    AvgTime = Duration / NumCheckpoints,

    %% Average checkpoint creation should be fast (< 10ms)
    ?assert(AvgTime < 10000),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.

test_recovery_performance() ->
    WorkflowId = <<"$perf_recovery_wf">>,

    %% Create workflow
    Config = #{
        pattern_type => basic_sequential,
        initial_marking => #{start => [workflow_token]},
        workflow_data => #{recovery_performance_test => true}
    },

    %% Start workflow
    {ok, Pid} = yawl_workflow_instance:start_link(WorkflowId, Config),

    %% Create checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(Pid),

    %% Measure recovery time
    Start = erlang:monotonic_time(microsecond),

    ok = yawl_persistence:rollback_to_checkpoint(WorkflowId, CheckpointId),
    ok = yawl_workflow_instance:restart_from_checkpoint(Pid, WorkflowId),

    End = erlang:monotonic_time(microsecond),
    Duration = End - Start,

    %% Recovery should be fast (< 50ms)
    ?assert(Duration < 50000),

    %% Cleanup
    gen_statem:stop(Pid),
    ok.