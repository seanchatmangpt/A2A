%%% @doc A2A Task State Machine Test Suite
%%%
%%% Common Test suite for testing the gen_statem task implementation.
-module(a2a_task_statem_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("../include/a2a.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    test_create_task/1,
    test_task_state_transitions/1,
    test_cancel_task/1,
    test_subscription/1,
    test_artifacts/1,
    test_terminal_state_immutable/1
]).

%%% ============================================================================
%%% CT Callbacks
%%% ============================================================================

all() ->
    [
        test_create_task,
        test_task_state_transitions,
        test_cancel_task,
        test_subscription,
        test_artifacts,
        test_terminal_state_immutable
    ].

init_per_suite(Config) ->
    %% Start required applications
    application:ensure_all_started(crypto),

    %% Start the application properly
    case application:ensure_all_started(a2a_erl) of
        {ok, _} ->
            Config;
        {error, {already_started, _}} ->
            Config;
        Error ->
            ct:fail("Failed to start a2a_erl application: ~p", [Error])
    end.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%%% ============================================================================
%%% Test Cases
%%% ============================================================================

%% Test basic task creation
test_create_task(_Config) ->
    Message = create_test_message(<<"test-001">>),

    %% Start task
    {ok, Pid} = a2a_task_statem:start_link(Message),
    ?assert(is_pid(Pid)),

    %% Get task
    {ok, Task} = a2a_task_statem:get_task(Pid),

    %% Verify task properties
    ?assert(is_binary(Task#task.id)),
    ?assert(is_binary(Task#task.context_id)),
    ?assertEqual(1, length(Task#task.history)),

    %% Verify status
    Status = Task#task.status,
    ?assert(lists:member(Status#task_status.state, [submitted, working])),

    ok.

%% Test task state transitions
test_task_state_transitions(_Config) ->
    Message = create_test_message(<<"test-002">>),

    {ok, Pid} = a2a_task_statem:start_link(Message),

    %% Wait a bit for state transitions
    timer:sleep(100),

    {ok, Task} = a2a_task_statem:get_task(Pid),
    State = (Task#task.status)#task_status.state,

    %% Task should have transitioned from submitted to working
    ?assertEqual(working, State),

    ok.

%% Test task cancellation
test_cancel_task(_Config) ->
    Message = create_test_message(<<"test-003">>),

    {ok, Pid} = a2a_task_statem:start_link(Message),

    %% Wait a bit for task to enter working state
    timer:sleep(100),

    %% Cancel the task
    {ok, CanceledTask} = a2a_task_statem:cancel_task(Pid),

    State = (CanceledTask#task.status)#task_status.state,
    ?assertEqual(canceled, State),

    %% Verify task is in terminal state
    ?assert(lists:member(State, ?TERMINAL_STATES)),

    ok.

%% Test subscription to task updates
test_subscription(_Config) ->
    Message = create_test_message(<<"test-004">>),

    {ok, Pid} = a2a_task_statem:start_link(Message),

    %% Subscribe to updates
    {ok, Ref} = a2a_task_statem:subscribe(Pid),
    ?assert(is_reference(Ref)),

    %% Cancel to trigger state change notification
    {ok, _} = a2a_task_statem:cancel_task(Pid),

    %% Should receive notification
    receive
        {a2a_task_event, _TaskId, {state_changed, canceled}} ->
            ok
    after 1000 ->
        ct:fail("Did not receive state change notification")
    end,

    ok.

%% Test adding artifacts
test_artifacts(_Config) ->
    Message = create_test_message(<<"test-005">>),

    {ok, Pid} = a2a_task_statem:start_link(Message),

    %% Wait for task to enter working state
    timer:sleep(100),

    %% Add an artifact
    Artifact = #artifact{
        artifact_id = <<"artifact-001">>,
        name = <<"Test Artifact">>,
        parts = [#part{content = {text, <<"test content">>}}]
    },
    ok = a2a_task_statem:add_artifact(Pid, Artifact),

    %% Get task and verify artifact
    {ok, Task} = a2a_task_statem:get_task(Pid),
    ?assertEqual(1, length(Task#task.artifacts)),

    [ReceivedArtifact] = Task#task.artifacts,
    ?assertEqual(<<"artifact-001">>, ReceivedArtifact#artifact.artifact_id),

    ok.

%% Test that terminal states are immutable
test_terminal_state_immutable(_Config) ->
    Message = create_test_message(<<"test-006">>),

    {ok, Pid} = a2a_task_statem:start_link(Message),

    %% Cancel to reach terminal state
    {ok, _} = a2a_task_statem:cancel_task(Pid),

    %% Try to send another message - should fail
    NewMessage = create_test_message(<<"test-006-continued">>),
    Result = a2a_task_statem:send_message(Pid, NewMessage, 1000),

    ?assertEqual({error, task_terminal}, Result),

    %% Try to cancel again - should fail
    CancelResult = a2a_task_statem:cancel_task(Pid),
    ?assertEqual({error, task_terminal}, CancelResult),

    ok.

%%% ============================================================================
%%% Helper Functions
%%% ============================================================================

create_test_message(MessageId) ->
    #message{
        message_id = MessageId,
        role = user,
        parts = [
            #part{
                content = {text, <<"Test message content">>},
                media_type = <<"text/plain">>
            }
        ]
    }.
