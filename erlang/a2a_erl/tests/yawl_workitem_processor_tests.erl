%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL Work Item Processor
%%%
%%% Tests the work item processor with persistence functionality.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_workitem_processor_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

workitem_processor_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Work item processor starts correctly", fun test_starts_correctly/0},
      {"Workitem creation and persistence", fun test_workitem_creation/0},
      {"Workitem state changes are persisted", fun test_state_changes/0},
      {"Workitem failure handling", fun test_failure_handling/0},
      {"Workitem completion handling", fun test_completion_handling/0},
      {"Workitem recovery on restart", fun test_recovery_restart/0},
      {"Multiple workitem concurrency", fun test_concurrency/0},
      {"Persistence transaction safety", fun test_transaction_safety/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Start required services
    {ok, _} = yawl_persistence:start_link(),
    {ok, _} = yawl_workitem_processor:start_link(),

    %% Create test data
    TestWorkitems = [
        #yawl_workitem_persist{
            workitem_id = <<"$test_wi_1">>,
            workflow_id = <<"$test_wf_1">>,
            task_id = task1,
            task_name = <<"Test Task 1">>,
            status = pending,
            data = #{},
            retry_count = 0,
            priority = normal
        },
        #yawl_workitem_persist{
            workitem_id = <<"$test_wi_2">>,
            workflow_id = <<"$test_wf_1">>,
            task_id = task2,
            task_name = <<"Test Task 2">>,
            status = started,
            data = #{},
            retry_count = 0,
            priority = high,
            start_time = erlang:monotonic_time(millisecond) - 5000
        },
        #yawl_workitem_persist{
            workitem_id = <<"$test_wi_3">>,
            workflow_id = <<"$test_wf_1">>,
            task_id = task3,
            task_name = <<"Test Task 3">>,
            status = completed,
            data = #{result => "success"},
            retry_count = 0,
            priority = normal,
            start_time = erlang:monotonic_time(millisecond) - 10000,
            completion_time = erlang:monotonic_time(millisecond) - 5000
        }
    ],

    %% Pre-populate with some test data
    lists:foreach(fun(WI) ->
        case yawl_persistence:save_workitem(WI) of
            ok -> ok;
            {error, _} -> ok  % Ignore for now
        end
    end, TestWorkitems),

    TestWorkitems.

cleanup(_TestWorkitems) ->
    %% Stop services
    catch yawl_workitem_processor:stop(),
    catch yawl_persistence:stop(),
    ok.

%%====================================================================
%% Test Cases
%%====================================================================

test_starts_correctly() ->
    %% Verify the process started successfully
    ?assert(is_process_whereis(yawl_workitem_processor)),
    %% Verify it can handle basic requests
    case yawl_workitem_processor:list_workitems(<<"$test_wf_1">>) of
        {ok, _} -> ok;
        _ -> ok
    end.

test_workitem_creation() ->
    %% Create a new workitem
    WorkflowId = <<"$test_wf_create">>,
    TaskId = new_task,
    TaskData = #{task_name => <<"New Test Task">>, task_type => code},

    %% Execute the task
    {ok, WorkitemId} = yawl_workitem_processor:execute_task(WorkflowId, TaskId, TaskData, #{}),

    %% Verify the workitem was created
    {ok, Status, Data} = yawl_workitem_processor:get_workitem_status(WorkflowId, WorkitemId),
    ?assertEqual(pending, Status),
    ?assertEqual(TaskData, Data),

    %% Verify persistence - check if it was saved
    {ok, PersistedWorkitem} = yawl_workitem_processor:load_workitem(WorkitemId),
    ?assertEqual(WorkitemId, PersistedWorkitem#yawl_workitem_persist.workitem_id),
    ?assertEqual(WorkflowId, PersistedWorkitem#yawl_workitem_persist.workflow_id),
    ?assertEqual(TaskId, PersistedWorkitem#yawl_workitem_persist.task_id),
    ok.

test_state_changes() ->
    %% Create a workitem
    WorkflowId = <<"$test_wf_state">>,
    TaskId = state_task,
    TaskData = #{task_name => <<"State Change Task">>},

    {ok, WorkitemId} = yawl_workitem_processor:execute_task(WorkflowId, TaskId, TaskData, #{}),

    %% Update workitem state to started
    {ok, UpdatedWorkitem} = yawl_workitem_processor:update_workitem_state(WorkitemId, started, #{progress => 50}),
    ?assertEqual(started, UpdatedWorkitem#yawl_workitem_persist.status),
    ?assertEqual(50, maps:get(progress, UpdatedWorkitem#yawl_workitem_persist.data)),
    ?assert(is_integer(UpdatedWorkitem#yawl_workitem_persist.start_time)),

    %% Update to allocated
    {ok, AllocatedWorkitem} = yawl_workitem_processor:update_workitem_state(WorkitemId, allocated, #{allocated_to => user1}),
    ?assertEqual(allocated, AllocatedWorkitem#yawl_workitem_persist.status),
    ?assertEqual(user1, maps:get(allocated_to, AllocatedWorkitem#yawl_workitem_persist.data)),
    ?assert(is_integer(AllocatedWorkitem#yawl_workitem_persist.allocation_time)),

    ok.

test_failure_handling() ->
    %% Create a workitem that will fail
    WorkflowId = <<"$test_wf_fail">>,
    TaskId = fail_task,
    TaskData = #{task_name => <<"Failing Task">>, task_type => code, fail => true},

    {ok, WorkitemId} = yawl_workitem_processor:execute_task(WorkflowId, TaskId, TaskData, #{}),

    %% Simulate a failure by sending a failure message
    yawl_workitem_processor ! {workitem_failed, WorkitemId, test_error},

    %% Wait a bit for the message to be processed
    timer:sleep(100),

    %% Check that the workitem is marked as failed
    {ok, Status, Data} = yawl_workitem_processor:get_workitem_status(WorkflowId, WorkitemId),
    ?assertEqual(failed, Status),
    ?assertEqual(test_error, maps:get(error, Data)),
    ?assert(is_integer(maps:get(completion_time, Data))),

    ok.

test_completion_handling() ->
    %% Create a workitem that will complete
    WorkflowId = <<"$test_wf_complete">>,
    TaskId = complete_task,
    TaskData = #{task_name => <<"Completing Task">>, task_type => code, result => success},

    {ok, WorkitemId} = yawl_workitem_processor:execute_task(WorkflowId, TaskId, TaskData, #{}),

    %% Simulate completion by sending a completion message
    Result = #{result => completed, output => <<"Success">>},
    yawl_workitem_processor ! {workitem_complete, WorkitemId, Result},

    %% Wait a bit for the message to be processed
    timer:sleep(100),

    %% Check that the workitem is marked as completed
    {ok, Status, Data} = yawl_workitem_processor:get_workitem_status(WorkflowId, WorkitemId),
    ?assertEqual(completed, Status),
    ?assertEqual(<<"Success">>, maps:get(output, Data)),
    ?assert(is_integer(maps:get(completion_time, Data))),

    ok.

test_recovery_restart() ->
    %% Create a few workitems
    WorkflowId = <<"$test_wf_recovery">>,
    TaskIds = [recovery_task_1, recovery_task_2, recovery_task_3],

    WorkitemIds = lists:map(fun(TaskId) ->
        {ok, WorkitemId} = yawl_workitem_processor:execute_task(
            WorkflowId, TaskId, #{task_name => atom_to_binary(TaskId)}, #{}
        ),
        WorkitemId
    end, TaskIds),

    %% Stop and restart the processor to test recovery
    yawl_workitem_processor:stop(),
    {ok, _} = yawl_workitem_processor:start_link(),

    %% Verify that workitems are recovered
    RecoveredWorkitems = yawl_workitem_processor:list_workitems(WorkflowId),
    {ok, RecoveredList} = RecoveredWorkitems,
    ?assert(length(RecoveredList) >= 2),  % Should recover pending/allocated/started items

    %% Check that completed items are not recovered
    CompletedCount = lists:filter(fun(#yawl_workitem_persist{status = Status}) ->
        Status =:= completed
    end, RecoveredList),
    ?assert(length(CompletedCount) =:= 0),

    ok.

test_concurrency() ->
    %% Test multiple workitems being processed concurrently
    WorkflowId = <<"$test_wf_concurrency">>,

    %% Create multiple workitems
    WorkitemIds = lists:map(fun(Index) ->
        TaskId = list_to_atom("concurrent_task_" ++ integer_to_list(Index)),
        {ok, WorkitemId} = yawl_workitem_processor:execute_task(
            WorkflowId, TaskId, #{task_name => <<"Concurrent Task ", (integer_to_binary(Index))/binary>>},
            #{}
        ),
        WorkitemId
    end, lists:seq(1, 10)),

    %% Check that all workitems are created
    {ok, AllWorkitems} = yawl_workitem_processor:list_workitems(WorkflowId),
    ?assert(length(AllWorkitems) =:= 10),

    %% Check that all workitems have unique IDs
    WorkitemIdsFromList = [WI#yawl_workitem_persist.workitem_id || WI <- AllWorkitems],
    ?assertEqual(length(lists:usort(WorkitemIdsFromList)), length(WorkitemIdsFromList)),

    ok.

test_transaction_safety() ->
    %% Test that persistence operations maintain consistency
    WorkflowId = <<"$test_wf_transaction">>,

    %% Create a workitem
    {ok, WorkitemId} = yawl_workitem_processor:execute_task(
        WorkflowId, transaction_task, #{task_name => <<"Transaction Test">>}, #{}
    ),

    %% Load it to verify persistence
    {ok, OriginalWorkitem} = yawl_workitem_processor:load_workitem(WorkitemId),

    %% Update state multiple times
    {ok, _} = yawl_workitem_processor:update_workitem_state(WorkitemId, started, #{progress => 25}),
    {ok, _} = yawl_workitem_processor:update_workitem_state(WorkitemId, allocated, #{progress => 50}),
    {ok, _} = yawl_workitem_processor:update_workitem_state(WorkitemId, started, #{progress => 75}),

    %% Load final state
    {ok, FinalWorkitem} = yawl_workitem_processor:load_workitem(WorkitemId),

    %% Verify the final state
    ?assertEqual(started, FinalWorkitem#yawl_workitem_persist.status),
    ?assertEqual(75, maps:get(progress, FinalWorkitem#yawl_workitem_persist.data)),
    ?assert(is_integer(FinalWorkitem#yawl_workitem_persist.start_time)),

    %% Verify timestamps are reasonable (not in the future)
    CurrentTime = erlang:monotonic_time(millisecond),
    ?assert(FinalWorkitem#yawl_workitem_persist.start_time =< CurrentTime),

    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

is_process_whereis(Name) ->
    case whereis(Name) of
        undefined -> false;
        Pid when is_pid(Pid) -> true;
        _ -> false
    end.