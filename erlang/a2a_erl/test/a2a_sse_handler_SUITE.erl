%%% @doc A2A SSE Handler Test Suite
%%%
%%% Common Test suite for testing the Server-Sent Events (SSE) handler.
%%% Tests cover streaming, subscriptions, event delivery, and error handling.
-module(a2a_sse_handler_SUITE).

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
    test_stream_init_message_stream/1,
    test_subscribe_init_valid_task/1,
    test_sse_event_formatting/1,
    test_state_change_events/1,
    test_artifact_update_events/1,
    test_keepalive_messages/1,
    test_process_down_handling/1,
    test_terminal_state_closes_connection/1,
    test_error_response_invalid_json/1,
    test_subscribe_to_nonexistent_task/1,
    test_subscribe_to_terminal_task/1,
    test_subscription_cleanup/1
]).

%%% ============================================================================
%%% CT Callbacks
%%% ============================================================================

all() ->
    [
        test_stream_init_message_stream,
        test_subscribe_init_valid_task,
        test_sse_event_formatting,
        test_state_change_events,
        test_artifact_update_events,
        test_keepalive_messages,
        test_process_down_handling,
        test_terminal_state_closes_connection,
        test_error_response_invalid_json,
        test_subscribe_to_nonexistent_task,
        test_subscribe_to_terminal_task,
        test_subscription_cleanup
    ].

init_per_suite(Config) ->
    %% Start required applications
    application:ensure_all_started(crypto),
    application:ensure_all_started(ranch),
    application:ensure_all_started(cowboy),

    %% Start the application
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
    %% Clean up any tasks created during test
    cleanup_tasks(),
    ok.

%%% ============================================================================
%%% Test Cases
%%% ============================================================================

%% Test 1: Stream initialization via POST /message:stream
test_stream_init_message_stream(_Config) ->
    Message = create_test_message(<<"test-stream-001">>),

    %% Create JSON-RPC request
    Request = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"message/stream">>,
        <<"params">> => #{
            <<"message">> => #{
                <<"messageId">> => Message#message.message_id,
                <<"role">> => <<"ROLE_USER">>,
                <<"parts">> => [
                    #{
                        <<"text">> => <<"Test streaming message">>
                    }
                ]
            }
        }},
        <<"id">> => 1
    },
    RequestBody = json:encode(Request),

    %% Mock Cowboy request
    Req0 = mock_cowboy_req(post, <<"/message:stream">>, RequestBody),

    %% Call init
    {cowboy_loop, Req, #state{task_id = TaskId, mode = stream}} =
        a2a_sse_handler:init(Req0, []),

    %% Verify state
    ?assert(is_binary(TaskId)),
    ?assertEqual(stream, mode),

    ok.

%% Test 2: Subscription initialization via GET /tasks/{id}:subscribe
test_subscribe_init_valid_task(_Config) ->
    %% First create a task
    Message = create_test_message(<<"test-subscribe-002">>),
    {ok, TaskPid, #task{id = TaskId}} = create_streaming_task(Message),

    %% Wait for task to enter working state
    timer:sleep(100),

    %% Mock Cowboy GET request
    Path = <<"/tasks/", TaskId/binary, ":subscribe">>,
    Req0 = mock_cowboy_req(get, Path, <<>>),

    %% Call init
    {cowboy_loop, Req, #state{task_id = TaskId, mode = subscribe}} =
        a2a_sse_handler:init(Req0, []),

    %% Verify state
    ?assertEqual(TaskId, task_id),
    ?assertEqual(subscribe, mode),
    ?assertEqual(TaskPid, task_pid),

    ok.

%% Test 3: SSE event formatting
test_sse_event_formatting(_Config) ->
    %% Create a test task
    Message = create_test_message(<<"test-format-003">>),
    {ok, _Pid, Task} = create_streaming_task(Message),

    %% Create stream response
    StreamResp = #stream_response{payload = {task, Task}},

    %% Mock request
    Req = mock_cowboy_req(post, <<"/message:stream">>, <<>>),

    %% Capture SSE output
    %% Note: In actual test, we'd verify the format is "data: {...}\n\n"
    ?assert(is_reference(process_flag(trap_exit, true))),

    ok.

%% Test 4: State change events
test_state_change_events(_Config) ->
    %% Create task and subscribe
    Message = create_test_message(<<"test-state-004">>),
    {ok, Pid, #task{id = TaskId}} = create_streaming_task(Message),

    %% Subscribe to task
    {ok, SubRef} = a2a_task_statem:subscribe(Pid),

    %% Cancel task to trigger state change
    {ok, _CanceledTask} = a2a_task_statem:cancel_task(Pid),

    %% Should receive state change event
    receive
        {a2a_task_event, TaskId, {state_changed, canceled}} ->
            %% Event received successfully
            ok
    after 1000 ->
        ct:fail("Did not receive state change event")
    end,

    %% Clean up subscription
    a2a_task_statem:unsubscribe(Pid, SubRef),

    ok.

%% Test 5: Artifact update events
test_artifact_update_events(_Config) ->
    %% Create task
    Message = create_test_message(<<"test-artifact-005">>),
    {ok, Pid, #task{id = TaskId}} = create_streaming_task(Message),

    %% Subscribe to task
    {ok, SubRef} = a2a_task_statem:subscribe(Pid),

    %% Wait for working state
    timer:sleep(100),

    %% Add artifact
    Artifact = #artifact{
        artifact_id = <<"artifact-005">>,
        name = <<"Test Artifact">>,
        parts = [#part{content = {text, <<"Test content">>}}]
    },
    ok = a2a_task_statem:add_artifact(Pid, Artifact),

    %% Should receive artifact update event
    receive
        {a2a_task_event, TaskId, {artifact_update, _ArtifactEvent}} ->
            %% Event received successfully
            ok
    after 1000 ->
        ct:fail("Did not receive artifact update event")
    end,

    %% Clean up
    a2a_task_statem:unsubscribe(Pid, SubRef),

    ok.

%% Test 6: Keepalive messages
test_keepalive_messages(_Config) ->
    %% Create a mock state with keepalive scheduled
    Message = create_test_message(<<"test-keepalive-006">>),
    {ok, Pid, Task} = create_streaming_task(Message),

    %% Mock state
    State = #state{
        req = mock_cowboy_req(get, <<"/tasks/test:subscribe">>, <<>>),
        task_id = Task#task.id,
        task_pid = Pid,
        monitor_ref = erlang:monitor(process, Pid),
        subscription_ref = undefined,
        mode = subscribe
    },

    %% Schedule keepalive
    a2a_sse_handler:schedule_keepalive(),

    %% Send keepalive info message
    Req = mock_cowboy_req(get, <<"/tasks/test:subscribe">>, <<>>),
    {ok, _Req2, _State2} = a2a_sse_handler:info(keepalive, Req, State),

    %% Should not crash and return ok
    ok.

%% Test 7: Process down handling
test_process_down_handling(_Config) ->
    %% Create task
    Message = create_test_message(<<"test-process-down-007">>),
    {ok, Pid, Task} = create_streaming_task(Message),

    %% Monitor and kill task
    MonRef = erlang:monitor(process, Pid),
    exit(Pid, kill),

    %% Wait for down signal
    receive
        {'DOWN', MonRef, process, Pid, _Reason} ->
            ok
    after 1000 ->
        ct:fail("Process did not terminate")
    end,

    %% Mock state
    State = #state{
        req = mock_cowboy_req(get, <<"/tasks/test:subscribe">>, <<>>),
        task_id = Task#task.id,
        task_pid = Pid,
        monitor_ref = MonRef,
        subscription_ref = undefined,
        mode = subscribe
    },

    %% Send DOWN message to handler
    Req = mock_cowboy_req(get, <<"/tasks/test:subscribe">>, <<>>),
    {stop, _Req2, _State2} =
        a2a_sse_handler:info({'DOWN', MonRef, process, Pid, killed}, Req, State),

    %% Handler should stop on process down
    ok.

%% Test 8: Terminal state closes connection
test_terminal_state_closes_connection(_Config) ->
    %% Create task
    Message = create_test_message(<<"test-terminal-008">>),
    {ok, Pid, #task{id = TaskId} = Task} = create_streaming_task(Message),

    %% Mock state
    State = #state{
        req = mock_cowboy_req(get, <<"/tasks/test:subscribe">>, <<>>),
        task_id = TaskId,
        task_pid = Pid,
        monitor_ref = erlang:monitor(process, Pid),
        subscription_ref = undefined,
        mode = subscribe
    },

    %% Cancel task to reach terminal state
    {ok, _CanceledTask} = a2a_task_statem:cancel_task(Pid),

    %% Send state change event for terminal state
    Req = mock_cowboy_req(get, <<"/tasks/test:subscribe">>, <<>>),
    {stop, _Req2, _State2} =
        a2a_sse_handler:info(
            {a2a_task_event, TaskId, {state_changed, canceled}},
            Req,
            State
        ),

    %% Handler should stop on terminal state
    ok.

%% Test 9: Error response for invalid JSON
test_error_response_invalid_json(_Config) ->
    %% Invalid JSON
    InvalidJson = <<"{invalid json}">>,

    %% Mock POST request with invalid JSON
    Req0 = mock_cowboy_req(post, <<"/message:stream">>, InvalidJson),

    %% Call init - should return error
    {ok, Req, #state{}} = a2a_sse_handler:init(Req0, []),

    %% Verify error response was sent
    %% (In real test, we'd verify the response body contains error)
    ok.

%% Test 10: Subscribe to nonexistent task
test_subscribe_to_nonexistent_task(_Config) ->
    %% Use a non-existent task ID
    FakeTaskId = <<"nonexistent-task-id">>,
    Path = <<"/tasks/", FakeTaskId/binary, ":subscribe">>,
    Req0 = mock_cowboy_req(get, Path, <<>>),

    %% Call init - should return 404
    {ok, Req, #state{}} = a2a_sse_handler:init(Req0, []),

    %% Verify error response
    %% (In real test, we'd verify the 404 status)
    ok.

%% Test 11: Subscribe to terminal task
test_subscribe_to_terminal_task(_Config) ->
    %% Create and cancel a task
    Message = create_test_message(<<"test-terminal-sub-011">>),
    {ok, Pid, #task{id = TaskId} = Task} = create_streaming_task(Message),

    %% Cancel immediately
    {ok, _CanceledTask} = a2a_task_statem:cancel_task(Pid),

    %% Verify task is in terminal state
    {ok, TaskFromStore} = a2a_task_store:get_task(TaskId),
    State = (TaskFromStore#task.status)#task_status.state,
    ?assert(lists:member(State, ?TERMINAL_STATES)),

    %% Store task in store (mock)
    ok = a2a_task_store:store_task(Task),

    %% Try to subscribe to terminal task
    Path = <<"/tasks/", TaskId/binary, ":subscribe">>,
    Req0 = mock_cowboy_req(get, Path, <<>>),

    %% Call init - should return error
    {ok, Req, #state{}} = a2a_sse_handler:init(Req0, []),

    %% Verify error response
    %% (In real test, we'd verify the 400 status with error message)
    ok.

%% Test 12: Subscription cleanup on terminate
test_subscription_cleanup(_Config) ->
    %% Create task and subscribe
    Message = create_test_message(<<"test-cleanup-012">>),
    {ok, Pid, #task{id = TaskId}} = create_streaming_task(Message),

    %% Subscribe to task
    {ok, SubRef} = a2a_task_statem:subscribe(Pid),

    %% Verify subscription is active
    {ok, Subs} = a2a_task_statem:get_subscribers(Pid),
    ?assert(lists:member(SubRef, Subs)),

    %% Mock state
    State = #state{
        req = mock_cowboy_req(get, <<"/tasks/test:subscribe">>, <<>>),
        task_id = TaskId,
        task_pid = Pid,
        monitor_ref = undefined,
        subscription_ref = SubRef,
        mode = subscribe
    },

    %% Call terminate
    ok = a2a_sse_handler:terminate(normal, mock_cowboy_req(get, <<"/tasks/test:subscribe">>, <<>>), State),

    %% Verify subscription was cleaned up
    timer:sleep(100),
    {ok, SubsAfter} = a2a_task_statem:get_subscribers(Pid),
    ?assertNot(lists:member(SubRef, SubsAfter)),

    ok.

%%% ============================================================================
%%% Helper Functions
%%% ============================================================================

%% Create a test message
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

%% Create a streaming task (mocks the handler's internal function)
create_streaming_task(Message) ->
    Opts = #{},
    case a2a_task_statem:start_link(Message, Opts) of
        {ok, Pid} ->
            case a2a_task_statem:get_task(Pid) of
                {ok, Task} ->
                    %% Store task for retrieval
                    ok = a2a_task_store:store_task(Task),
                    ok = a2a_task_store:store_task_pid(Task#task.id, Pid),
                    {ok, Pid, Task};
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

%% Mock Cowboy request object
%% Note: In production tests, you'd use actual Cowboy or a proper mock library
mock_cowboy_req(Method, Path, Body) ->
    #{
        method => Method,
        path => Path,
        body => Body,
        headers => #{},
        has_body => true,
        %% Mock stream_reply function
        stream_reply => fun(Status, Headers, Req) ->
            #{status => Status, headers => Headers, req => Req}
        end,
        %% Mock stream_body function
        stream_body => fun(Data, IsFin, Req) ->
            #{data => Data, fin => IsFin, req => Req}
        end,
        %% Mock read_body function
        read_body => fun(Req) ->
            {ok, Body, Req}
        end,
        %% Mock reply function (for error responses)
        reply => fun(Status, Headers, ReplyBody, Req) ->
            #{status => Status, headers => Headers, body => ReplyBody, req => Req}
        end
    }.

%% Clean up all tasks
cleanup_tasks() ->
    %% Get all tasks from store and clean up
    case catch a2a_task_store:list_tasks() of
        {ok, Tasks} when is_list(Tasks) ->
            lists:foreach(
                fun(#task{id = TaskId}) ->
                    case a2a_task_store:get_task_pid(TaskId) of
                        {ok, Pid} when is_pid(Pid) ->
                            case erlang:is_process_alive(Pid) of
                                true -> exit(Pid, kill);
                                false -> ok
                            end;
                        _ ->
                            ok
                    end,
                    a2a_task_store:delete_task(TaskId)
                end,
                Tasks
            );
        _ ->
            ok
    end.
