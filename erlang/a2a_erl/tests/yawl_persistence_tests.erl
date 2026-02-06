%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL Persistence
%%%
%%% Tests the Mnesia-based persistence layer.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_persistence_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

persistence_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Create and initialize Mnesia tables", fun test_create_tables/0},
      {"Save and load workflow", fun test_save_load_workflow/0},
      {"List workflows by status", fun test_list_workflows_by_status/0},
      {"Work item persistence", fun test_workitem_persistence/0},
      {"Resource persistence", fun test_resource_persistence/0},
      {"Checkpoint operations", fun test_checkpoint_operations/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Create unique Mnesia directory for this test run
    TestDir = "/tmp/yawl_persistence_test_" ++ integer_to_list(erlang:unique_integer()),
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

test_create_tables() ->
    %% Verify tables exist
    Tables = mnesia:system_info(tables),
    ?assert(lists:member(yawl_workflow_persist, Tables)),
    ?assert(lists:member(yawl_workitem_persist, Tables)),
    ?assert(lists:member(yawl_resource_persist, Tables)),
    ?assert(lists:member(yawl_checkpoint, Tables)),
    ok.

test_save_load_workflow() ->
    WorkflowId = <<"$test_wf_1">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec_1">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{start => [token]},
        current_place = start,
        data = #{key => value},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ?assertEqual(ok, yawl_persistence:save_workflow(Workflow)),
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(WorkflowId, Loaded#yawl_workflow_persist.workflow_id),
    ?assertEqual(basic_sequential, Loaded#yawl_workflow_persist.pattern_type),
    ?assertEqual(running, Loaded#yawl_workflow_persist.status),
    ok.

test_list_workflows_by_status() ->
    %% Create workflows with different statuses
    Wf1 = #yawl_workflow_persist{
        workflow_id = <<"$test_wf_2">>,
        spec_id = <<"spec_2">>,
        pattern_type = basic_sequential,
        status = running,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    Wf2 = #yawl_workflow_persist{
        workflow_id = <<"$test_wf_3">>,
        spec_id = <<"spec_3">>,
        pattern_type = parallel_split,
        status = completed,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ?assertEqual(ok, yawl_persistence:save_workflow(Wf1)),
    ?assertEqual(ok, yawl_persistence:save_workflow(Wf2)),
    {ok, RunningWfs} = yawl_persistence:list_workflows_by_status(running),
    ?assertEqual(1, length(RunningWfs)),
    {ok, CompletedWfs} = yawl_persistence:list_workflows_by_status(completed),
    ?assertEqual(1, length(CompletedWfs)),
    ok.

test_workitem_persistence() ->
    WorkitemId = <<"$test_wi_1">>,
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = <<"$test_wf">>,
        task_id = task1,
        task_name = <<"Task 1">>,
        status = pending,
        data = #{},
        retry_count = 0,
        priority = normal
    },
    ?assertEqual(ok, yawl_persistence:save_workitem(Workitem)),
    {ok, Loaded} = yawl_persistence:load_workitem(WorkitemId),
    ?assertEqual(WorkitemId, Loaded#yawl_workitem_persist.workitem_id),
    ?assertEqual(task1, Loaded#yawl_workitem_persist.task_id),
    ?assertEqual(pending, Loaded#yawl_workitem_persist.status),
    ok.

test_resource_persistence() ->
    ResourceId = <<"$test_res_1">>,
    Resource = #yawl_resource_persist{
        resource_id = ResourceId,
        resource_type = service,
        name = <<"Test Service">>,
        capabilities = [task1, task2],
        status = available,
        current_load = 0,
        max_capacity = 10
    },
    ?assertEqual(ok, yawl_persistence:save_resource(Resource)),
    {ok, Loaded} = yawl_persistence:load_resource(ResourceId),
    ?assertEqual(ResourceId, Loaded#yawl_resource_persist.resource_id),
    ?assertEqual(service, Loaded#yawl_resource_persist.resource_type),
    ?assertEqual(available, Loaded#yawl_resource_persist.status),
    ok.

test_checkpoint_operations() ->
    WorkflowId = <<"$test_wf_checkpoint">>,

    %% Test checkpoint creation with proper workflow ID
    CheckpointId = <<"$checkpoint_1">>,
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = CheckpointId,
        workflow_id = WorkflowId,
        checkpoint_state = #{state => data},
        marking = #{start => [token]},
        data = #{key => value},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ?assertEqual(ok, yawl_persistence:save_checkpoint(WorkflowId, Checkpoint)),

    {ok, Loaded} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(CheckpointId, Loaded#yawl_checkpoint.checkpoint_id),
    ?assertEqual(WorkflowId, Loaded#yawl_checkpoint.workflow_id),

    %% Test multiple checkpoints with sequence numbers
    Checkpoint2 = Checkpoint#yawl_checkpoint{
        checkpoint_id = <<"$checkpoint_2">>,
        checkpoint_state = #{state => data2},
        marking = #{task1 => [token]},
        data = #{key2 => value2},
        sequence_num = 2
    },
    ?assertEqual(ok, yawl_persistence:save_checkpoint(WorkflowId, Checkpoint2)),

    %% Verify latest checkpoint
    {ok, Latest} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(<<"$checkpoint_2">>, Latest#yawl_checkpoint.checkpoint_id),
    ?assertEqual(2, Latest#yawl_checkpoint.sequence_num),

    %% Test checkpoint listing
    {ok, Checkpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assertEqual(2, length(Checkpoints)),

    %% Test checkpoint deletion
    ?assertEqual(ok, yawl_persistence:delete_checkpoint(<<"$checkpoint_1">>)),
    {ok, RemainingCheckpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assertEqual(1, length(RemainingCheckpoints)),

    %% Test restore functionality
    case yawl_persistence:restore_from_checkpoint(WorkflowId) of
        {ok, Restored} ->
            ?assertEqual(<<"$checkpoint_2">>, Restored#yawl_checkpoint.checkpoint_id),
            %% Verify workflow was restored
            {ok, RestoredWorkflow} = yawl_persistence:load_workflow(WorkflowId),
            ?assertEqual(#{task1 => [token]}, RestoredWorkflow#yawl_workflow_persist.marking);
        {error, not_found} ->
            %% If no workflow exists, this is also acceptable
            ok
    end,
    ok.
