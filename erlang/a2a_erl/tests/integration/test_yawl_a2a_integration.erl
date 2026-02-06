%%%-------------------------------------------------------------------
%%% @doc
%%% Integration Tests for YAWL-A2A Task Integration
%%%
%%% These tests verify the end-to-end integration between YAWL workflows
%%% and A2A tasks including:
%%%
%%% - Workitem to A2A task creation
%%% - State synchronization
%%% - Resource allocation
%%% - Task completion and workflow continuation
%%% - Event notifications
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(test_yawl_a2a_integration).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").

-include("yawl_types.hrl").
-include("yawl_schema.hrl").
-include("../../include/a2a.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

setup_all() ->
    %% Start YAWL components
    {ok, _} = yawl_persistence:start_link(),
    ok = yawl_persistence:create_tables(),
    ok = yawl_persistence:wait_for_tables(),

    {ok, _} = yawl_orchestrator:start_link(),
    {ok, _} = yawl_a2a_bridge:start_link(),
    {ok, _} = yawl_a2a_events:start_link(),
    {ok, _} = yawl_a2a_resource_integration:start_link(),
    {ok, _} = a2a_task_store:start_link(),
    {ok, _} = a2a_task_sup:start_link(),
    ok.

cleanup_all(_) ->
    %% Stop components in reverse order
    a2a_task_sup:stop_task(whereis(a2a_task_statem)),
    a2a_task_store:unregister_task(<<"test_task">>),
    yawl_a2a_resource_integration:stop_bridge(),
    yawl_a2a_events:stop_bridge(),
    yawl_a2a_bridge:stop_bridge(),
    gen_server:stop(yawl_orchestrator),
    gen_server:stop(yawl_persistence),
    ok.

%%====================================================================
%% Integration Tests
%%====================================================================

integration_test_() ->
    {setup,
     fun setup_all/0,
     fun cleanup_all/1,
     fun(_) ->
         [
             fun workflow_to_task_to_workflow/0,
             fun resource_allocation_integration/0,
             fun event_notification_flow/0,
             fun checkpoint_recovery_integration/0,
             fun multi_task_workflow/0
         ]
     end}.

%% @doc Test complete workflow: YAWL -> A2A -> YAWL
workflow_to_task_to_workflow() ->
    %% Create a YAWL workflow
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential,
        #{data => #{test_data => <<"value">>}}
    ),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Get workitems created by workflow
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    ?assert(length(Workitems) > 0),

    %% Create A2A task for first workitem
    [FirstWorkitem | _] = Workitems,
    WorkitemId = FirstWorkitem#yawl_workitem_persist.workitem_id,

    {ok, TaskId, _TaskPid} = yawl_a2a_bridge:create_a2a_task_from_workitem(
        FirstWorkitem, #{}
    ),

    %% Verify mapping
    {ok, MappedTaskId} = yawl_a2a_bridge:get_a2a_task_for_workitem(WorkitemId),
    ?assertEqual(TaskId, MappedTaskId),

    %% Complete the A2A task
    Result = #{output => <<"test_output">>},
    ok = yawl_a2a_bridge:complete_workitem_from_a2a_task(TaskId, Result),

    %% Verify workitem was completed
    {ok, CompletedWorkitem} = yawl_persistence:load_workitem(WorkitemId),
    ?assertEqual(completed, CompletedWorkitem#yawl_workitem_persist.status),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),
    ok.

%% @doc Test resource allocation between systems
resource_allocation_integration() ->
    WorkitemId = <<"wi_resource_test">>,
    TaskId = <<"task_resource_test">>,

    %% Create workitem
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = <<"wf_resource">>,
        task_id = task1,
        task_name = <<"Resource Test Task">>,
        status = pending,
        data = #{task_type => human, capabilities => [human_task]},
        priority = normal
    },
    ok = yawl_persistence:save_workitem(Workitem),

    %% Register a test resource
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        <<"Test Human">>,
        human,
        #{capabilities => [human_task], max_capacity => 5}
    ),

    %% Allocate resource for workitem
    {ok, AllocatedResourceId} = yawl_a2a_resource_integration:allocate_for_workitem(
        Workitem
    ),
    ?assertEqual(ResourceId, AllocatedResourceId),

    %% Verify allocation in integration
    {ok, WorkitemResourceId} = yawl_a2a_resource_integration:get_workitem_resource(
        WorkitemId
    ),
    ?assertEqual(ResourceId, WorkitemResourceId),

    %% Link to A2A task
    ok = yawl_a2a_bridge:link_a2a_task_to_workflow(
        TaskId, Workitem#yawl_workitem_persist.workflow_id, WorkitemId
    ),

    %% Allocate resource for task
    {ok, TaskResourceId} = yawl_a2a_bridge:allocate_resource_for_task(
        TaskId, [human_task]
    ),

    %% Sync resource state to A2A
    {ok, ResourceState} = yawl_a2a_resource_integration:sync_resource_to_a2a(
        TaskResourceId
    ),
    ?assertMatch(#{status := _, load := _}, ResourceState),

    %% Release resource
    ok = yawl_a2a_resource_integration:release_for_workitem(WorkitemId),

    %% Cleanup
    ok = yawl_resource_manager:unregister_resource(ResourceId),
    ok.

%% @doc Test event notification flow
event_notification_flow() ->
    %% Create event subscriber
    Subscriber = self(),
    {ok, _Ref} = yawl_a2a_events:subscribe(Subscriber),

    %% Create a workitem
    WorkitemId = <<"wi_event_test">>,
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = <<"wf_event">>,
        task_id = task1,
        task_name = <<"Event Test Task">>,
        status = pending,
        data = #{},
        priority = normal
    },
    ok = yawl_persistence:save_workitem(Workitem),

    %% Publish workitem created event
    yawl_a2a_events:publish(workitem_created, #{
        workitem_id => WorkitemId,
        workflow_id => Workitem#yawl_workitem_persist.workflow_id
    }),

    %% Receive event (with timeout)
    receive
        {yawl_a2a_event, workitem_created, EventData} ->
            ?assertEqual(WorkitemId, maps:get(workitem_id, EventData))
    after 1000 ->
        ?assert(false, "Event not received within timeout")
    end,

    %% Check event history
    History = yawl_a2a_events:get_event_history(workitem_created),
    ?assert(length(History) > 0),

    %% Unsubscribe
    ok = yawl_a2a_events:unsubscribe(Subscriber),
    ok.

%% @doc Test checkpoint recovery with A2A tasks
checkpoint_recovery_integration() ->
    WorkflowId = <<"wf_checkpoint_test">>,

    %% Create workflow with checkpoint data
    CheckpointData = #{
        marking => #{start => [token], task1 => []},
        data => #{key => <<"checkpoint_value">>},
        task_mappings => #{task1 => <<"a2a_task_123">>}
    },

    %% Save checkpoint
    {ok, CheckpointId} = yawl_a2a_bridge:create_checkpoint(WorkflowId, CheckpointData),

    %% Restore checkpoint
    {ok, RestoredState} = yawl_a2a_bridge:restore_from_checkpoint(
        WorkflowId, CheckpointId
    ),

    %% Verify restored state
    ?assertEqual(#{start => [token], task1 => []}, maps_get(marking, RestoredState, #{})),
    ?assertEqual(<<"checkpoint_value">>, maps_get(key, maps_get(data, RestoredState, #{}), <<>>)),

    %% Verify task mappings were preserved
    Mappings = maps_get(task_mappings, RestoredState, #{}),
    ?assertEqual(<<"a2a_task_123">>, maps_get(task1, Mappings, undefined)),

    ok.

%% @doc Test workflow with multiple A2A tasks
multi_task_workflow() ->
    WorkflowId = <<"wf_multi_task">>,

    %% Create workflow with multiple tasks
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(
        basic_sequential,
        #{
            data => #{
                tasks => [task1, task2, task3]
            }
        }
    ),

    %% Execute workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Create workitems for each task
    TaskIds = [task1, task2, task3],
    WorkitemIds = lists:map(fun(TaskId) ->
        WorkitemId = <<"wi_", (atom_to_binary(TaskId))/binary>>,
        Workitem = #yawl_workitem_persist{
            workitem_id = WorkitemId,
            workflow_id = WorkflowId,
            task_id = TaskId,
            task_name = <<"Task ", (atom_to_binary(TaskId))/binary>>,
            status = pending,
            data = #{task_type => service},
            priority = normal
        },
        ok = yawl_persistence:save_workitem(Workitem),
        WorkitemId
    end, TaskIds),

    %% Create A2A tasks for all workitems
    lists:map(fun(WorkitemId) ->
        {ok, Workitem} = yawl_persistence:load_workitem(WorkitemId),
        {ok, _TaskId, _Pid} = yawl_a2a_bridge:create_a2a_task_from_workitem(
            Workitem, #{}
        )
    end, WorkitemIds),

    %% Verify all mappings exist
    lists:foreach(fun(WorkitemId) ->
        {ok, _TaskId} = yawl_a2a_bridge:get_a2a_task_for_workitem(WorkitemId)
    end, WorkitemIds),

    %% Complete tasks in order
    lists:foreach(fun(WorkitemId) ->
        {ok, TaskId} = yawl_a2a_bridge:get_a2a_task_for_workitem(WorkitemId),
        ok = yawl_a2a_bridge:complete_workitem_from_a2a_task(
            TaskId, #{result => <<"done">>}
        )
    end, WorkitemIds),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),
    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
