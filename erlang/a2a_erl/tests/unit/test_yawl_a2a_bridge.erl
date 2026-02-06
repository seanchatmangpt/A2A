%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL-A2A Bridge
%%%
%%% Tests the bidirectional bridge between YAWL workflows and A2A tasks.
%%% @end
%%%-------------------------------------------------------------------

-module(test_yawl_a2a_bridge).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").

-include("yawl_types.hrl").
-include("yawl_schema.hrl").
-include("../../include/a2a.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

%% Setup and teardown
setup() ->
    {ok, Pid} = yawl_a2a_bridge:start_link(),
    Pid.

cleanup(_Pid) ->
    yawl_a2a_bridge:stop_bridge(),
    ok.

%%====================================================================
%% State Mapping Tests
%%====================================================================

map_workitem_status_test_() ->
    [
        ?_assertEqual(?TASK_STATE_SUBMITTED,
                     yawl_a2a_bridge:map_yawl_state_to_a2a(pending)),
        ?_assertEqual(?TASK_STATE_SUBMITTED,
                     yawl_a2a_bridge:map_yawl_state_to_a2a(allocated)),
        ?_assertEqual(?TASK_STATE_WORKING,
                     yawl_a2a_bridge:map_yawl_state_to_a2a(started)),
        ?_assertEqual(?TASK_STATE_COMPLETED,
                     yawl_a2a_bridge:map_yawl_state_to_a2a(completed)),
        ?_assertEqual(?TASK_STATE_FAILED,
                     yawl_a2a_bridge:map_yawl_state_to_a2a(failed)),
        ?_assertEqual(?TASK_STATE_CANCELED,
                     yawl_a2a_bridge:map_yawl_state_to_a2a(cancelled))
    ].

map_a2a_state_to_yawl_test_() ->
    [
        ?_assertEqual(pending,
                     yawl_a2a_bridge:map_a2a_state_to_yawl(?TASK_STATE_SUBMITTED)),
        ?_assertEqual(started,
                     yawl_a2a_bridge:map_a2a_state_to_yawl(?TASK_STATE_WORKING)),
        ?_assertEqual(completed,
                     yawl_a2a_bridge:map_a2a_state_to_yawl(?TASK_STATE_COMPLETED)),
        ?_assertEqual(failed,
                     yawl_a2a_bridge:map_a2a_state_to_yawl(?TASK_STATE_FAILED)),
        ?_assertEqual(cancelled,
                     yawl_a2a_bridge:map_a2a_state_to_yawl(?TASK_STATE_CANCELED)),
        ?_assertEqual(started,
                     yawl_a2a_bridge:map_a2a_state_to_yawl(?TASK_STATE_INPUT_REQUIRED)),
        ?_assertEqual(cancelled,
                     yawl_a2a_bridge:map_a2a_state_to_yawl(?TASK_STATE_REJECTED))
    ].

is_terminal_state_test_() ->
    [
        ?_assert(yawl_a2a_bridge:is_terminal_state(?TASK_STATE_COMPLETED)),
        ?_assert(yawl_a2a_bridge:is_terminal_state(?TASK_STATE_FAILED)),
        ?_assert(yawl_a2a_bridge:is_terminal_state(?TASK_STATE_CANCELED)),
        ?_assert(yawl_a2a_bridge:is_terminal_state(?TASK_STATE_REJECTED)),
        ?_assertNot(yawl_a2a_bridge:is_terminal_state(?TASK_STATE_SUBMITTED)),
        ?_assertNot(yawl_a2a_bridge:is_terminal_state(?TASK_STATE_WORKING)),
        ?_assertNot(yawl_a2a_bridge:is_terminal_state(?TASK_STATE_INPUT_REQUIRED))
    ].

%%====================================================================
%% Task Creation Tests
%%====================================================================

create_a2a_task_from_workitem_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_Pid) ->
         [
             fun() ->
                 %% Create a test workitem
                 WorkitemId = <<"wi_123">>,
                 WorkflowId = <<"wf_456">>,
                 Workitem = #yawl_workitem_persist{
                     workitem_id = WorkitemId,
                     workflow_id = WorkflowId,
                     task_id = task1,
                     task_name = <<"Test Task">>,
                     status = pending,
                     data = #{description => <<"Test description">>},
                     priority = normal
                 },

                 %% Mock the task supervisor
                 meck:new(a2a_task_sup, [passthrough]),
                 meck:expect(a2a_task_sup, start_task, fun(_Msg, _Opts) ->
                     {ok, self()}
                 end),
                 meck:new(a2a_task_statem, [passthrough]),
                 meck:expect(a2a_task_statem, get_task, fun(_Pid) ->
                     {ok, #task{id = WorkitemId}}
                 end),

                 %% Create A2A task from workitem
                 Result = yawl_a2a_bridge:create_a2a_task_from_workitem(Workitem),

                 %% Verify result
                 ?assertMatch({ok, _TaskId, _Pid}, Result),

                 %% Clean up mocks
                 meck:unload(a2a_task_sup),
                 meck:unload(a2a_task_statem)
             end
         ]
     end}.

%%====================================================================
%% Linking Tests
%%====================================================================

link_task_to_workflow_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_Pid) ->
         [
             fun() ->
                 TaskId = <<"task_123">>,
                 WorkflowId = <<"wf_456">>,
                 WorkitemId = <<"wi_789">>,

                 %% Link task to workflow
                 Result = yawl_a2a_bridge:link_a2a_task_to_workflow(
                     TaskId, WorkflowId, WorkitemId
                 ),

                 ?assertEqual(ok, Result),

                 %% Verify mapping exists
                 {ok, MappedWorkflow} = yawl_a2a_bridge:get_workflow_for_a2a_task(TaskId),
                 ?assertEqual(WorkflowId, MappedWorkflow),

                 {ok, MappedTask} = yawl_a2a_bridge:get_a2a_task_for_workitem(WorkitemId),
                 ?assertEqual(TaskId, MappedTask)
             end
         ]
     end}.

%%====================================================================
%% Checkpoint Tests
%%====================================================================

checkpoint_operations_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_Pid) ->
         [
             fun() ->
                 WorkflowId = <<"wf_123">>,
                 CheckpointData = #{
                     marking => #{start => [token]},
                     data => #{key => value}
                 },

                 %% Mock persistence
                 meck:new(yawl_persistence, [passthrough]),
                 meck:expect(yawl_persistence, save_checkpoint, fun(_WfId, _Cp) -> ok end),
                 meck:expect(yawl_persistence, load_latest_checkpoint, fun(_WfId) ->
                     {ok, #yawl_checkpoint{
                         checkpoint_id = <<"cp_1">>,
                         workflow_id = WorkflowId,
                         marking = #{start => [token]},
                         data = #{key => value},
                         timestamp = 12345,
                         sequence_num = 1
                     }}
                 end),

                 %% Create checkpoint
                 CreateResult = yawl_a2a_bridge:create_checkpoint(WorkflowId, CheckpointData),
                 ?assertMatch({ok, _CheckpointId}, CreateResult),

                 %% Restore checkpoint
                 {ok, CheckpointId} = CreateResult,
                 RestoreResult = yawl_a2a_bridge:restore_from_checkpoint(WorkflowId, CheckpointId),
                 ?assertMatch({ok, _StateMap}, RestoreResult),

                 %% Get checkpoint state
                 StateResult = yawl_a2a_bridge:get_checkpoint_state(CheckpointId),
                 ?assertMatch({ok, _StateMap}, StateResult),

                 meck:unload(yawl_persistence)
             end
         ]
     end}.

%%====================================================================
%% Event Subscription Tests
%%====================================================================

event_subscription_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_Pid) ->
         [
             fun() ->
                 EntityId = <<"entity_123">>,

                 %% Subscribe to events
                 {ok, Ref} = yawl_a2a_bridge:subscribe_to_workitem_events(EntityId),
                 ?assert(is_reference(Ref)),

                 %% Unsubscribe
                 ?assertEqual(ok, yawl_a2a_bridge:unsubscribe_from_events(Ref))
             end
         ]
     end}.

%%====================================================================
%% Resource Allocation Tests
%%====================================================================

resource_allocation_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_Pid) ->
         [
             fun() ->
                 TaskId = <<"task_123">>,
                 Capabilities = [human_task],

                 %% Mock resource manager
                 meck:new(yawl_resource_manager, [passthrough]),
                 meck:expect(yawl_resource_manager, allocate_resource, fun(_TId, _Caps) ->
                     {ok, <<"res_456">>, #{resource_id => <<"res_456">>}}
                 end),
                 meck:expect(yawl_resource_manager, release_resource, fun(_TId, _RId) ->
                     ok
                 end),

                 %% Allocate resource
                 AllocResult = yawl_a2a_bridge:allocate_resource_for_task(TaskId, Capabilities),
                 ?assertMatch({ok, _ResourceId}, AllocResult),

                 %% Get resource for task
                 {ok, _ResourceId} = yawl_a2a_bridge:get_task_resource(TaskId),

                 %% Release resource
                 {ok, ResourceId} = AllocResult,
                 ?assertEqual(ok, yawl_a2a_bridge:release_resource_for_task(TaskId, ResourceId)),

                 meck:unload(yawl_resource_manager)
             end
         ]
     end}.

%%====================================================================
%% Completion Tests
%%====================================================================

workitem_completion_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_Pid) ->
         [
             fun() ->
                 TaskId = <<"task_123">>,
                 Result = #{output => <<"success">>},

                 %% Link task first
                 WorkitemId = <<"wi_456">>,
                 WorkflowId = <<"wf_789">>,
                 yawl_a2a_bridge:link_a2a_task_to_workflow(TaskId, WorkflowId, WorkitemId),

                 %% Mock persistence and orchestrator
                 meck:new(yawl_persistence, [passthrough]),
                 meck:expect(yawl_persistence, list_workitems, fun(_WfId) ->
                     {ok, [#yawl_workitem_persist{
                         workitem_id = WorkitemId,
                         data = #{a2a_task_id => TaskId}
                     }]}
                 end),
                 meck:expect(yawl_persistence, load_workitem, fun(_WiId) ->
                     {ok, #yawl_workitem_persist{
                         workitem_id = WorkitemId,
                         workflow_id = WorkflowId,
                         status = started,
                         data = #{}
                     }}
                 end),
                 meck:expect(yawl_persistence, save_workitem, fun(_Wi) -> ok end),

                 %% Complete workitem from A2A task
                 Result = yawl_a2a_bridge:complete_workitem_from_a2a_task(TaskId, Result),
                 ?assertEqual(ok, Result),

                 meck:unload(yawl_persistence)
             end
         ]
     end}.

%%====================================================================
%% Failure Tests
%%====================================================================

workitem_failure_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_Pid) ->
         [
             fun() ->
                 TaskId = <<"task_123">>,
                 WorkitemId = <<"wi_456">>,
                 Reason = task_timeout,

                 %% Mock persistence
                 meck:new(yawl_persistence, [passthrough]),
                 meck:expect(yawl_persistence, load_workitem, fun(_WiId) ->
                     {ok, #yawl_workitem_persist{
                         workitem_id = WorkitemId,
                         workflow_id = <<"wf_789">>,
                         status = started
                     }}
                 end),
                 meck:expect(yawl_persistence, save_workitem, fun(_Wi) -> ok end),

                 %% Fail workitem from A2A task
                 Result = yawl_a2a_bridge:fail_workitem_from_a2a_task(
                     TaskId, WorkitemId, Reason
                 ),
                 ?assertEqual(ok, Result),

                 meck:unload(yawl_persistence)
             end
         ]
     end}.

%%====================================================================
%% Helper Functions
%%====================================================================

%% Mock helper to create test workitems
create_test_workitem(WorkitemId, WorkflowId) ->
    #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = WorkflowId,
        task_id = task1,
        task_name = <<"Test Task">>,
        status = pending,
        data = #{description => <<"Test workitem">>},
        priority = normal
    }.

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
