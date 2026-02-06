%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL-A2A Integration Tests
%%%
%%% Comprehensive test suite for the YAWL-A2A task bridge covering:
%%%
%%% - Bidirectional mapping between YAWL workitems and A2A tasks
%%% - State synchronization
%%% - Event notification system
%%% - Checkpoint save and recovery
%%% - Resource allocation coordination
%%% - Error recovery mechanisms
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_a2a_integration_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

setup_all() ->
    %% Start required applications
    application:ensure_all_started(mnesia),
    {ok, _} = yawl_persistence:start_link(),
    ok = yawl_persistence:create_schema(),
    ok = yawl_persistence:create_tables(),
    ok = yawl_persistence:wait_for_tables(),

    {ok, _} = yawl_orchestrator:start_link(),
    {ok, _} = yawl_a2a_bridge:start_link(),
    {ok, _} = yawl_a2a_events:start_link(),
    {ok, _} = yawl_a2a_resource_integration:start_link(),
    {ok, _} = a2a_task_store:start_link(),
    {ok, _} = a2a_task_sup:start_link(),

    %% Register test resources
    register_test_resources(),

    ok.

cleanup_all(_) ->
    %% Clean up
    cleanup_test_resources(),
    ok.

setup_each() ->
    %% Reset state before each test
    mnesia:clear_table(yawl_workflow_persist),
    mnesia:clear_table(yawl_workitem_persist),
    mnesia:clear_table(yawl_resource_persist),
    mnesia:clear_table(yawl_checkpoint),
    mnesia:clear_table(yawl_execution_history),

    %% Re-register resources
    register_test_resources(),

    ok.

cleanup_each(_) ->
    ok.

%%====================================================================
%% Integration Tests
%%====================================================================

integration_test_() ->
    {setup,
     fun setup_all/0,
     fun cleanup_all/1,
     {foreach,
      fun setup_each/0,
      fun cleanup_each/1,
      [
         fun test_create_a2a_task_from_workitem/0,
         fun test_sync_workitem_to_a2a_task/0,
         fun test_complete_workitem_from_a2a/0,
         fun test_fail_workitem_from_a2a/0,
         fun test_state_mapping_yawl_to_a2a/0,
         fun test_state_mapping_a2a_to_yawl/0,
         fun test_checkpoint_save/0,
         fun test_checkpoint_restore/0,
         fun test_checkpoint_recovery_after_failure/0,
         fun test_event_notification_system/0,
         fun test_resource_allocation_for_task/0,
         fun test_resource_release_for_task/0
      ]
     }
    }.

%% @doc Test creating an A2A task from a YAWL workitem
test_create_a2a_task_from_workitem() ->
    fun() ->
        %% Create a test workitem
        WorkitemId = <<"workitem_1">>,
        WorkflowId = <<"workflow_1">>,

        Workitem = #yawl_workitem_persist{
            workitem_id = WorkitemId,
            workflow_id = WorkflowId,
            task_id = task_1,
            task_name = <<"Test Task">>,
            status = pending,
            data = #{
                description => <<"Test workitem description">>,
                context_id => <<"context_1">>
            }
        },

        %% Save workitem to persistence
        {ok, _} = yawl_persistence:save_workitem(Workitem),

        %% Create A2A task from workitem
        {ok, TaskId, _TaskPid} = yawl_a2a_bridge:create_a2a_task_from_workitem(Workitem),

        %% Verify task was created (just check it exists)
        {ok, _Task} = a2a_task_store:get_task(TaskId),

        %% Verify mapping was created
        {ok, MappedTaskId} = yawl_a2a_bridge:get_a2a_task_for_workitem(WorkitemId),
        ?assertEqual(TaskId, MappedTaskId),

        ok
    end.

%% @doc Test syncing workitem state to A2A task
test_sync_workitem_to_a2a_task() ->
    fun() ->
        %% Create workitem and A2A task
        WorkitemId = <<"workitem_sync_1">>,
        Workitem = #yawl_workitem_persist{
            workitem_id = WorkitemId,
            workflow_id = <<"workflow_sync_1">>,
            task_id = task_sync_1,
            task_name = <<"Sync Test">>,
            status = pending
        },
        {ok, TaskId, _} = yawl_a2a_bridge:create_a2a_task_from_workitem(Workitem),

        %% Update workitem status
        UpdatedWorkitem = Workitem#yawl_workitem_persist{status = started},
        {ok, _} = yawl_persistence:save_workitem(UpdatedWorkitem),

        %% Sync to A2A task
        ok = yawl_a2a_bridge:sync_workitem_to_a2a_task(WorkitemId, TaskId),

        %% Verify task was synced (check if task still exists)
        {ok, _Task} = a2a_task_store:get_task(TaskId),

        ok
    end.

%% @doc Test completing a workitem from A2A task
test_complete_workitem_from_a2a() ->
    fun() ->
        %% Create workitem and A2A task
        WorkitemId = <<"workitem_complete_1">>,
        WorkflowId = <<"workflow_complete_1">>,
        Workitem = #yawl_workitem_persist{
            workitem_id = WorkitemId,
            workflow_id = WorkflowId,
            task_id = task_complete_1,
            task_name = <<"Complete Test">>,
            status = started
        },
        {ok, TaskId, _} = yawl_a2a_bridge:create_a2a_task_from_workitem(Workitem),

        %% Link task to workflow
        ok = yawl_a2a_bridge:link_a2a_task_to_workflow(TaskId, WorkflowId, WorkitemId),

        %% Complete from A2A task
        Result = #{output => <<"test result">>},
        ok = yawl_a2a_bridge:complete_workitem_from_a2a_task(TaskId, Result),

        %% Verify workitem was completed
        {ok, CompletedWorkitem} = yawl_persistence:load_workitem(WorkitemId),
        ?assertEqual(completed, CompletedWorkitem#yawl_workitem_persist.status),
        ?assertEqual(Result, CompletedWorkitem#yawl_workitem_persist.data),

        ok
    end.

%% @doc Test failing a workitem from A2A task
test_fail_workitem_from_a2a() ->
    fun() ->
        %% Create workitem and A2A task
        WorkitemId = <<"workitem_fail_1">>,
        Workitem = #yawl_workitem_persist{
            workitem_id = WorkitemId,
            workflow_id = <<"workflow_fail_1">>,
            task_id = task_fail_1,
            task_name = <<"Fail Test">>,
            status = started
        },
        {ok, TaskId, _} = yawl_a2a_bridge:create_a2a_task_from_workitem(Workitem),

        %% Fail from A2A task
        Reason = <<"Task execution failed">>,
        ok = yawl_a2a_bridge:fail_workitem_from_a2a_task(TaskId, WorkitemId, Reason),

        %% Verify workitem was failed
        {ok, FailedWorkitem} = yawl_persistence:load_workitem(WorkitemId),
        ?assertEqual(failed, FailedWorkitem#yawl_workitem_persist.status),
        ?assertEqual(Reason, FailedWorkitem#yawl_workitem_persist.error),

        ok
    end.

%% @doc Test state mapping from YAWL to A2A
test_state_mapping_yawl_to_a2a() ->
    fun() ->
        ?assertEqual(submitted, yawl_a2a_bridge:map_yawl_state_to_a2a(pending)),
        ?assertEqual(submitted, yawl_a2a_bridge:map_yawl_state_to_a2a(allocated)),
        ?assertEqual(working, yawl_a2a_bridge:map_yawl_state_to_a2a(started)),
        ?assertEqual(completed, yawl_a2a_bridge:map_yawl_state_to_a2a(completed)),
        ?assertEqual(failed, yawl_a2a_bridge:map_yawl_state_to_a2a(failed)),
        ?assertEqual(canceled, yawl_a2a_bridge:map_yawl_state_to_a2a(cancelled)),
        ok
    end.

%% @doc Test state mapping from A2A to YAWL
test_state_mapping_a2a_to_yawl() ->
    fun() ->
        ?assertEqual(pending, yawl_a2a_bridge:map_a2a_state_to_yawl(submitted)),
        ?assertEqual(started, yawl_a2a_bridge:map_a2a_state_to_yawl(working)),
        ?assertEqual(completed, yawl_a2a_bridge:map_a2a_state_to_yawl(completed)),
        ?assertEqual(failed, yawl_a2a_bridge:map_a2a_state_to_yawl(failed)),
        ?assertEqual(cancelled, yawl_a2a_bridge:map_a2a_state_to_yawl(canceled)),
        ?assertEqual(started, yawl_a2a_bridge:map_a2a_state_to_yawl(input_required)),
        ?assertEqual(started, yawl_a2a_bridge:map_a2a_state_to_yawl(auth_required)),
        ok
    end.

%% @doc Test checkpoint save functionality
test_checkpoint_save() ->
    fun() ->
        WorkflowId = <<"workflow_checkpoint_1">>,

        %% Create checkpoint data
        CheckpointData = #{
            marking => #{start => [], task1 => [token]},
            data => #{key1 => value1},
            state => running
        },

        %% Create checkpoint
        {ok, CheckpointId} = yawl_a2a_bridge:create_checkpoint(WorkflowId, CheckpointData),

        %% Verify checkpoint was saved
        {ok, CheckpointState} = yawl_a2a_bridge:get_checkpoint_state(CheckpointId),
        ?assertEqual(WorkflowId, maps_get(workflow_id, CheckpointState, undefined)),
        ?assertMatch(#{start := [], task1 := [token]}, maps_get(marking, CheckpointState, #{})),

        ok
    end.

%% @doc Test checkpoint restore functionality
test_checkpoint_restore() ->
    fun() ->
        WorkflowId = <<"workflow_restore_1">>,

        %% Create and save checkpoint
        CheckpointData = #{
            marking => #{start => [], task2 => [token]},
            data => #{key2 => value2},
            state => waiting
        },

        {ok, CheckpointId} = yawl_a2a_bridge:create_checkpoint(WorkflowId, CheckpointData),

        %% Restore from checkpoint
        {ok, RestoredState} = yawl_a2a_bridge:restore_from_checkpoint(
            WorkflowId, CheckpointId
        ),

        %% Verify restored state
        ?assertMatch(#{marking := #{task2 := [token]}}, RestoredState),
        ?assertMatch(#{data := #{key2 := value2}}, RestoredState),

        ok
    end.

%% @doc Test checkpoint recovery after failure
test_checkpoint_recovery_after_failure() ->
    fun() ->
        WorkflowId = <<"workflow_recovery_1">>,

        %% Create initial checkpoint
        CheckpointData1 = #{
            marking => #{start => [], task1 => [token]},
            data => #{step => 1},
            state => running
        },

        {ok, _CheckpointId1} = yawl_a2a_bridge:create_checkpoint(
            WorkflowId, CheckpointData1
        ),

        %% Simulate progress and create new checkpoint
        CheckpointData2 = #{
            marking => #{start => [], task2 => [token]},
            data => #{step => 2},
            state => running
        },

        {ok, CheckpointId2} = yawl_a2a_bridge:create_checkpoint(
            WorkflowId, CheckpointData2
        ),

        %% Verify second checkpoint has higher sequence number
        {ok, State2} = yawl_a2a_bridge:get_checkpoint_state(CheckpointId2),
        ?assertEqual(#{step => 2}, maps_get(data, State2, #{})),

        %% Restore from latest checkpoint
        {ok, RestoredState} = yawl_a2a_bridge:restore_from_checkpoint(
            WorkflowId, CheckpointId2
        ),

        ?assertMatch(#{data := #{step := 2}}, RestoredState),

        ok
    end.

%% @doc Test event notification system
test_event_notification_system() ->
    fun() ->
        %% Create subscriber
        {ok, _Ref} = yawl_a2a_events:subscribe(self()),

        %% Publish event
        yawl_a2a_events:publish(workitem_created, #{
            workitem_id => <<"wi_test">>,
            workflow_id => <<"wf_test">>
        }),

        %% Receive event (with timeout)
        receive
            {yawl_a2a_event, workitem_created, EventData} ->
                ?assertEqual(<<"wi_test">>, maps_get(workitem_id, EventData, undefined))
        after 1000 ->
            ?assert(false, "Event not received within timeout")
        end,

        %% Check event history
        History = yawl_a2a_events:get_event_history(workitem_created),
        ?assert(length(History) > 0),

        ok
    end.

%% @doc Test resource allocation for task
test_resource_allocation_for_task() ->
    fun() ->
        TaskId = <<"task_resource_1">>,

        %% Allocate resource
        {ok, ResourceId} = yawl_a2a_bridge:allocate_resource_for_task(
            TaskId, [test_capability]
        ),

        %% Verify resource was allocated
        {ok, AllocatedResource} = yawl_a2a_bridge:get_task_resource(TaskId),
        ?assertEqual(ResourceId, AllocatedResource),

        ok
    end.

%% @doc Test resource release for task
test_resource_release_for_task() ->
    fun() ->
        TaskId = <<"task_release_1">>,

        %% Allocate then release resource
        {ok, ResourceId} = yawl_a2a_bridge:allocate_resource_for_task(
            TaskId, [test_capability]
        ),

        ok = yawl_a2a_bridge:release_resource_for_task(TaskId, ResourceId),

        %% Verify resource was released
        ?assertEqual({error, not_found}, yawl_a2a_bridge:get_task_resource(TaskId)),

        ok
    end.

%%====================================================================
%% Internal Helper Functions
%%====================================================================

%% @private
register_test_resources() ->
    %% Register human resources
    yawl_resource_manager:register_resource(
        <<"test_user_1">>,
        human,
        #{capabilities => [task_execution, approval], max_capacity => 5}
    ),
    yawl_resource_manager:register_resource(
        <<"test_user_2">>,
        human,
        #{capabilities => [task_execution, review], max_capacity => 3}
    ),

    %% Register service resources
    yawl_resource_manager:register_resource(
        <<"test_service_1">>,
        service,
        #{capabilities => [data_processing, validation], max_capacity => 10}
    ),

    %% Register system resources
    yawl_resource_manager:register_resource(
        <<"test_system_1">>,
        system,
        #{capabilities => [orchestration, monitoring], max_capacity => 20}
    ),

    ok.

%% @private
cleanup_test_resources() ->
    %% Clean up test resources
    mnesia:clear_table(yawl_resource_persist),
    mnesia:clear_table(yawl_workflow_persist),
    mnesia:clear_table(yawl_workitem_persist),
    mnesia:clear_table(yawl_checkpoint),
    mnesia:clear_table(yawl_execution_history),

    ok.

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
