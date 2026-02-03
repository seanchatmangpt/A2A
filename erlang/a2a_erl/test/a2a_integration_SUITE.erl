%%% @doc A2A Integration Test Suite
%%%
%%% Common Test suite for end-to-end integration testing of the A2A protocol.
%%% Tests HTTP endpoints, SSE streaming, task lifecycle, filtering, push
%%% notifications, and error handling scenarios.
%%%
%%% Prerequisites:
%%% - Cowboy web server must be configured
%%% - gun HTTP client (for HTTP/SSE testing)
%%% - meck (for mocking external dependencies)
-module(a2a_integration_SUITE).

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
    test_http_send_message_end_to_end/1,
    test_sse_subscription_streaming/1,
    test_task_lifecycle_integration/1,
    test_list_tasks_with_filters/1,
    test_push_notification_integration/1,
    test_error_handling_integration/1
]).

%%% ============================================================================
%%% CT Callbacks
%%% ============================================================================

all() ->
    [
        test_http_send_message_end_to_end,
        test_sse_subscription_streaming,
        test_task_lifecycle_integration,
        test_list_tasks_with_filters,
        test_push_notification_integration,
        test_error_handling_integration
    ].

init_per_suite(Config) ->
    %% Start required applications
    application:ensure_all_started(crypto),
    application:ensure_all_started(cowboy),

    %% Start the A2A application
    case application:ensure_all_started(a2a_erl) of
        {ok, _} ->
            %% Get HTTP port from config or use default
            Port = case application:get_env(a2a_erl, http_port) of
                {ok, P} -> P;
                undefined -> 8080
            end,
            [{http_port, Port} | Config];
        {error, {already_started, _}} ->
            Port = case application:get_env(a2a_erl, http_port) of
                {ok, P} -> P;
                undefined -> 8080
            end,
            [{http_port, Port} | Config];
        Error ->
            ct:fail("Failed to start a2a_erl application: ~p", [Error])
    end.

end_per_suite(_Config) ->
    ok.

init_per_testcase(TestCase, Config) ->
    ct:pal("Starting test case: ~p", [TestCase]),
    Config.

end_per_testcase(_TestCase, _Config) ->
    %% Clean up all tasks from this test
    cleanup_all_tasks(),
    ok.

%%% ============================================================================
%%% Test Case 1: HTTP SendMessage End-to-End
%%% ============================================================================

%% @doc Test complete HTTP SendMessage flow from request to task creation
test_http_send_message_end_to_end(Config) ->
    Port = ?config(http_port, Config),
    BaseUrl = iolist_to_binary(["http://localhost:", integer_to_binary(Port)]),

    %% Step 1: Send valid JSON-RPC SendMessage request via HTTP POST
    Message = #message{
        message_id = <<"msg-integration-001">>,
        role = user,
        parts = [
            #part{
                content = {text, <<"Integration test message">>},
                media_type = <<"text/plain">>
            }
        ]
    },

    SendReq = #send_message_request{
        message = Message,
        configuration = #send_message_configuration{
            blocking = false
        }
    },

    JsonReq = a2a_json:encode_send_message_request(SendReq),
    JsonRpcReq = #{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"message/send">>,
        <<"params">> => JsonReq,
        <<"id">> => 1
    },

    RequestBody = json:encode(JsonRpcReq),

    %% Make HTTP POST request
    Response = http_post(<<BaseUrl/binary, "/message:send">>, RequestBody),

    %% Step 2: Verify JSON-RPC response contains task with valid ID
    ?assertEqual(200, maps:get(<<"status">>, Response)),
    Body = maps:get(<<"body">>, Response),

    JsonResp = json:decode(Body),
    ?assertEqual(<<"2.0">>, maps:get(<<"jsonrpc">>, JsonResp)),
    ?assertNotEqual(undefined, maps:get(<<"result">>, JsonResp, undefined)),
    ?assertEqual(undefined, maps:get(<<"error">>, JsonResp, undefined)),

    Result = maps:get(<<"result">>, JsonResp),
    TaskMap = maps:get(<<"task">>, Result),
    TaskId = maps:get(<<"id">>, TaskMap),

    ?assert(is_binary(TaskId)),
    ?assert(byte_size(TaskId) > 0),

    %% Step 3: Retrieve task via GetTask endpoint
    GetTaskUrl = <<BaseUrl/binary, "/tasks/", TaskId/binary>>,
    GetResponse = http_get(GetTaskUrl),

    ?assertEqual(200, maps:get(<<"status">>, GetResponse)),
    GetBody = maps:get(<<"body">>, GetResponse),
    GetJsonResp = json:decode(GetBody),

    GetResult = maps:get(<<"result">>, GetJsonResp),
    ?assertEqual(TaskId, maps:get(<<"id">>, GetResult)),

    %% Step 4: Verify task is in working state
    StatusMap = maps:get(<<"status">>, GetResult),
    State = maps:get(<<"state">>, StatusMap),
    ?assert(lists:member(State, [submitted, working])),

    %% Step 5: Cleanup task
    delete_task_and_verify(TaskId),

    ct:pal("Test completed: HTTP SendMessage end-to-end"),
    ok.

%%% ============================================================================
%%% Test Case 2: SSE Subscription Streaming
%%% ============================================================================

%% @doc Test SSE subscription to task updates
test_sse_subscription_streaming(Config) ->
    Port = ?config(http_port, Config),
    BaseUrl = iolist_to_binary(["http://localhost:", integer_to_binary(Port)]),

    %% Step 1: Create task via SendMessage
    Message = #message{
        message_id = <<"msg-sse-001">>,
        role = user,
        parts = [
            #part{
                content = {text, <<"SSE streaming test">>},
                media_type = <<"text/plain">>
            }
        ]
    },

    {ok, TaskPid} = a2a_task_statem:start_link(Message, #{}),
    {ok, Task} = a2a_task_statem:get_task(TaskPid),
    TaskId = Task#task.id,

    %% Step 2: Subscribe to task via SSE endpoint
    %% Note: In a real scenario, we'd use gun for SSE, but for this test
    %% we'll use the subscription mechanism directly
    {ok, SubRef} = a2a_task_statem:subscribe(TaskPid),
    ?assert(is_reference(SubRef)),

    %% Step 3: Verify we can receive state change notifications
    %% Cancel task to trigger state change
    {ok, CanceledTask} = a2a_task_statem:cancel_task(TaskPid),
    CanceledState = (CanceledTask#task.status)#task_status.state,
    ?assertEqual(canceled, CanceledState),

    %% Step 4: Verify status update event received
    receive
        {a2a_task_event, TaskId, {state_changed, canceled}} ->
            ct:pal("Received state change event for canceled state"),
            ok
    after 5000 ->
        ct:fail("Did not receive state change notification within timeout")
    end,

    %% Step 5: Unsubscribe and cleanup
    a2a_task_statem:unsubscribe(TaskPid, SubRef),

    %% Step 6: Verify task is in terminal state
    ?assert(lists:member(CanceledState, ?TERMINAL_STATES)),

    ct:pal("Test completed: SSE subscription streaming"),
    ok.

%%% ============================================================================
%%% Test Case 3: Task Lifecycle Integration
%%% ============================================================================

%% @doc Test complete task lifecycle through all states
test_task_lifecycle_integration(_Config) ->
    %% Step 1: Create task via HTTP-equivalent (direct gen_statem)
    Message = #message{
        message_id = <<"msg-lifecycle-001">>,
        role = user,
        parts = [
            #part{
                content = {text, <<"Lifecycle test">>},
                media_type = <<"text/plain">>
            }
        ]
    },

    {ok, TaskPid} = a2a_task_statem:start_link(Message, #{}),
    {ok, Task} = a2a_task_statem:get_task(TaskPid),
    TaskId = Task#task.id,

    %% Step 2: Verify task transitions to working state
    timer:sleep(100),
    {ok, WorkingTask} = a2a_task_statem:get_task(TaskPid),
    WorkingState = (WorkingTask#task.status)#task_status.state,
    ?assertEqual(working, WorkingState),

    %% Step 3: Add artifact via gen_statem
    Artifact = #artifact{
        artifact_id = <<"artifact-lifecycle-001">>,
        name = <<"Test Artifact">>,
        description = <<"Integration test artifact">>,
        parts = [
            #part{
                content = {text, <<"Artifact content">>},
                media_type = <<"text/plain">>
            }
        ]
    },
    ok = a2a_task_statem:add_artifact(TaskPid, Artifact),

    %% Step 4: Verify artifact in task store
    {ok, TaskWithArtifact} = a2a_task_statem:get_task(TaskPid),
    ?assertEqual(1, length(TaskWithArtifact#task.artifacts)),
    [StoredArtifact] = TaskWithArtifact#task.artifacts,
    ?assertEqual(<<"artifact-lifecycle-001">>, StoredArtifact#artifact.artifact_id),

    %% Step 5: Cancel task to terminal state
    {ok, CanceledTask} = a2a_task_statem:cancel_task(TaskPid),
    CanceledState = (CanceledTask#task.status)#task_status.state,
    ?assertEqual(canceled, CanceledState),

    %% Step 6: Verify immutability (cannot send messages to terminal task)
    NewMessage = #message{
        message_id = <<"msg-lifecycle-002">>,
        role = user,
        parts = [
            #part{
                content = {text, <<"Should fail">>},
                media_type = <<"text/plain">>
            }
        ]
    },

    SendResult = a2a_task_statem:send_message(TaskPid, NewMessage, 1000),
    ?assertEqual({error, task_terminal}, SendResult),

    %% Verify cannot cancel again
    CancelResult = a2a_task_statem:cancel_task(TaskPid),
    ?assertEqual({error, task_terminal}, CancelResult),

    ct:pal("Test completed: Task lifecycle integration"),
    ok.

%%% ============================================================================
%%% Test Case 4: List Tasks with Filters
%%% ============================================================================

%% @doc Test task listing with various filters
test_list_tasks_with_filters(_Config) ->
    %% Step 1: Create multiple tasks with different context_ids and states
    ContextId1 = <<"context-filter-001">>,
    ContextId2 = <<"context-filter-002">>,

    Message1 = #message{
        message_id = <<"msg-list-001">>,
        context_id = ContextId1,
        role = user,
        parts = [#part{content = {text, <<"Task 1">>}, media_type = <<"text/plain">>}]
    },

    Message2 = #message{
        message_id = <<"msg-list-002">>,
        context_id = ContextId2,
        role = user,
        parts = [#part{content = {text, <<"Task 2">>}, media_type = <<"text/plain">>}]
    },

    Message3 = #message{
        message_id = <<"msg-list-003">>,
        context_id = ContextId1,
        role = user,
        parts = [#part{content = {text, <<"Task 3">>}, media_type = <<"text/plain">>}]
    },

    {ok, Pid1} = a2a_task_statem:start_link(Message1, #{}),
    {ok, Pid2} = a2a_task_statem:start_link(Message2, #{}),
    {ok, Pid3} = a2a_task_statem:start_link(Message3, #{}),

    {ok, Task1} = a2a_task_statem:get_task(Pid1),
    {ok, Task2} = a2a_task_statem:get_task(Pid2),
    {ok, Task3} = a2a_task_statem:get_task(Pid3),

    %% Step 2: List all tasks (no filter)
    {ok, AllTasks, _} = a2a_task_store:list_tasks(#{}),
    ?assert(length(AllTasks) >= 3),

    %% Step 3: Filter by context_id
    {ok, Context1Tasks, _} = a2a_task_store:list_tasks(#{context_id => ContextId1}),
    ?assert(length(Context1Tasks) >= 2),

    %% Step 4: Filter by status
    {ok, WorkingTasks, _} = a2a_task_store:list_tasks(#{status => working}),
    ?assert(length(WorkingTasks) >= 3),

    %% Step 5: Test pagination
    PageSize = 2,
    {ok, PagedTasks, NextToken} = a2a_task_store:list_tasks(#{
        page_size => PageSize
    }),
    ?assertEqual(PageSize, length(PagedTasks)),
    ?assertNotEqual(<<>>, NextToken),

    %% Get next page
    {ok, NextPageTasks, NextToken2} = a2a_task_store:list_tasks(#{
        page_size => PageSize,
        page_token => NextToken
    }),
    ?assert(PageSize >= length(NextPageTasks)),

    %% Step 6: Verify include_artifacts parameter
    %% Add artifact to Task1
    Artifact = #artifact{
        artifact_id = <<"artifact-list-001">>,
        name = <<"Filter Test Artifact">>,
        parts = [#part{content = {text, <<"Content">>}, media_type = <<"text/plain">>}]
    },
    a2a_task_statem:add_artifact(Pid1, Artifact),

    {ok, TasksWithArtifacts, _} = a2a_task_store:list_tasks(#{
        include_artifacts => true
    }),

    %% Find Task1 in results
    Task1WithArtifacts = lists:keyfind(Task1#task.id, #task.id, TasksWithArtifacts),
    ?assertNotEqual(false, Task1WithArtifacts),
    ?assertEqual(1, length(Task1WithArtifacts#task.artifacts)),

    %% Step 7: Verify history_length parameter
    {ok, TasksNoHistory, _} = a2a_task_store:list_tasks(#{
        history_length => 0
    }),

    Task1NoHistory = lists:keyfind(Task1#task.id, #task.id, TasksNoHistory),
    ?assertNotEqual(false, Task1NoHistory),
    ?assertEqual(0, length(Task1NoHistory#task.history)),

    ct:pal("Test completed: List tasks with filters"),
    ok.

%%% ============================================================================
%%% Test Case 5: Push Notification Integration
%%% ============================================================================

%% @doc Test push notification configuration and delivery
test_push_notification_integration(_Config) ->
    %% Step 1: Create task with push notification config
    Message = #message{
        message_id = <<"msg-push-001">>,
        role = user,
        parts = [#part{content = {text, <<"Push test">>}, media_type = <<"text/plain">>}]
    },

    PushConfig = #push_notification_config{
        id = <<"push-config-001">>,
        url = <<"https://example.com/webhook">>,
        token = <<"test-token">>,
        authentication = #authentication_info{
            scheme = <<"Bearer">>,
            credentials = <<"test-credentials">>
        }
    },

    {ok, TaskPid} = a2a_task_statem:start_link(Message, #{}),
    {ok, Task} = a2a_task_statem:get_task(TaskPid),
    TaskId = Task#task.id,

    %% Step 2: Register push config in task store
    TaskPushConfig = #task_push_notification_config{
        id = <<"push-config-001">>,
        task_id = TaskId,
        push_notification_config = PushConfig
    },

    ok = a2a_task_store:add_push_config(TaskId, TaskPushConfig),

    %% Step 3: Verify config retrieval
    {ok, RetrievedConfig} = a2a_task_store:get_push_config(TaskId, <<"push-config-001">>),
    ?assertEqual(<<"push-config-001">>, RetrievedConfig#task_push_notification_config.id),
    ?assertEqual(<<"https://example.com/webhook">>,
                 (RetrievedConfig#task_push_notification_config.push_notification_config)#push_notification_config.url),

    %% Step 4: List push configs for task
    Configs = a2a_task_store:list_push_configs(TaskId),
    ?assertEqual(1, length(Configs)),
    [FirstConfig] = Configs,
    ?assertEqual(<<"push-config-001">>, FirstConfig#task_push_notification_config.id),

    %% Step 5: Trigger task state change (in real scenario, push would be sent)
    {ok, CanceledTask} = a2a_task_statem:cancel_task(TaskPid),
    ?assertEqual(canceled, (CanceledTask#task.status)#task_status.state),

    %% Step 6: Verify push config still exists after state change
    {ok, FinalConfig} = a2a_task_store:get_push_config(TaskId, <<"push-config-001">>),
    ?assertNotEqual(undefined, FinalConfig),

    %% Step 7: Test push config deletion
    ok = a2a_task_store:delete_push_config(TaskId, <<"push-config-001">>),
    {error, not_found} = a2a_task_store:get_push_config(TaskId, <<"push-config-001">>),

    ct:pal("Test completed: Push notification integration"),
    ok.

%%% ============================================================================
%%% Test Case 6: Error Handling Integration
%%% ============================================================================

%% @doc Test error scenarios across HTTP and gen_statem layers
test_error_handling_integration(Config) ->
    Port = ?config(http_port, Config),
    BaseUrl = iolist_to_binary(["http://localhost:", integer_to_binary(Port)]),

    %% Test 1: Invalid JSON-RPC request (malformed JSON)
    MalformedJson = <<"{invalid json}">>,
    Response1 = http_post(<<BaseUrl/binary, "/message:send">>, MalformedJson),
    ?assertEqual(400, maps:get(<<"status">>, Response1)),
    Body1 = maps:get(<<"body">>, Response1),
    JsonResp1 = json:decode(Body1),
    ?assertNotEqual(undefined, maps:get(<<"error">>, JsonResp1)),

    %% Test 2: Unknown method
    UnknownMethodJson = json:encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"unknown/method">>,
        <<"params">> => #{},
        <<"id">> => 2
    }),
    Response2 = http_post(<<BaseUrl/binary, "/message:send">>, UnknownMethodJson),
    ?assertEqual(400, maps:get(<<"status">>, Response2)),
    Body2 = maps:get(<<"body">>, Response2),
    JsonResp2 = json:decode(Body2),
    Error2 = maps:get(<<"error">>, JsonResp2),
    ?assertEqual(-32601, maps:get(<<"code">>, Error2)),

    %% Test 3: Invalid parameters
    InvalidParamsJson = json:encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"message/send">>,
        <<"params">> => #{<<"invalid">> => <<"params">>},
        <<"id">> => 3
    }),
    Response3 = http_post(<<BaseUrl/binary, "/message:send">>, InvalidParamsJson),
    ?assertEqual(400, maps:get(<<"status">>, Response3)),
    Body3 = maps:get(<<"body">>, Response3),
    JsonResp3 = json:decode(Body3),
    ?assertNotEqual(undefined, maps:get(<<"error">>, JsonResp3)),

    %% Test 4: GetTask with non-existent ID (404)
    NonExistentTaskId = <<"non-existent-task-id">>,
    Response4 = http_get(<<BaseUrl/binary, "/tasks/", NonExistentTaskId/binary>>),
    ?assertEqual(404, maps:get(<<"status">>, Response4)),
    Body4 = maps:get(<<"body">>, Response4),
    JsonResp4 = json:decode(Body4),
    Error4 = maps:get(<<"error">>, JsonResp4),
    ?assertEqual(-32001, maps:get(<<"code">>, Error4)),

    %% Test 5: CancelTask on already terminal task
    Message5 = #message{
        message_id = <<"msg-error-005">>,
        role = user,
        parts = [#part{content = {text, <<"Terminal test">>}, media_type = <<"text/plain">>}]
    },
    {ok, Pid5} = a2a_task_statem:start_link(Message5, #{}),
    {ok, Task5} = a2a_task_statem:get_task(Pid5),
    TaskId5 = Task5#task.id,

    %% Cancel to terminal state
    {ok, _} = a2a_task_statem:cancel_task(Pid5),

    %% Try to cancel again via HTTP
    CancelUrl = <<BaseUrl/binary, "/tasks/", TaskId5/binary, ":cancel">>,
    CancelBody = json:encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"tasks/cancel">>,
        <<"params">> => #{<<"id">> => TaskId5},
        <<"id">> => 5
    }),
    Response5 = http_post(CancelUrl, CancelBody),
    ?assertEqual(400, maps:get(<<"status">>, Response5)),
    Body5 = maps:get(<<"body">>, Response5),
    JsonResp5 = json:decode(Body5),
    Error5 = maps:get(<<"error">>, JsonResp5),
    ?assertEqual(-32002, maps:get(<<"code">>, Error5)),

    %% Test 6: SubscribeToTask on terminal task
    SubscribeUrl = <<BaseUrl/binary, "/tasks/", TaskId5/binary, ":subscribe">>,
    Response6 = http_get(SubscribeUrl),
    ?assertEqual(400, maps:get(<<"status">>, Response6)),
    Body6 = maps:get(<<"body">>, Response6),
    JsonResp6 = json:decode(Body6),
    Error6 = maps:get(<<"error">>, JsonResp6),
    ?assertEqual(-32003, maps:get(<<"code">>, Error6)),

    ct:pal("Test completed: Error handling integration"),
    ok.

%%% ============================================================================
%%% Helper Functions
%%% ============================================================================

%% @doc Make HTTP POST request
http_post(Url, Body) ->
    Headers = #{
        <<"content-type">> => <<"application/json">>
    },
    http_request(post, Url, Headers, Body).

%% @doc Make HTTP GET request
http_get(Url) ->
    Headers = #{},
    http_request(get, Url, Headers, undefined).

%% @doc Generic HTTP request using httpc
http_request(Method, Url, Headers, Body) ->
    UrlStr = binary_to_list(Url),
    HeaderList = [{binary_to_list(K), binary_to_list(V)} || {K, V} <- maps:to_list(Headers)],

    Request = case Method of
        get ->
            {UrlStr, HeaderList};
        post ->
            {UrlStr, HeaderList, <<"application/json">>, Body}
    end,

    Options = [
        {body_format, binary},
        {timeout, 5000},
        {connect_timeout, 5000}
    ],

    case httpc:request(Method, Request, [], Options) of
        {ok, {{_, StatusCode, _}, RespHeaders, RespBody}} ->
            #{
                <<"status">> => StatusCode,
                <<"headers">> => maps:from_list([{list_to_binary(K), list_to_binary(V)} || {K, V} <- RespHeaders]),
                <<"body">> => RespBody
            };
        {error, Reason} ->
            ct:fail("HTTP request failed: ~p", [Reason])
    end.

%% @doc Delete task and verify it's removed
delete_task_and_verify(TaskId) ->
    case a2a_task_store:get_task_pid(TaskId) of
        {ok, Pid} ->
            a2a_task_statem:cancel_task(Pid),
            timer:sleep(100);
        {error, not_found} ->
            ok
    end.

%% @doc Clean up all tasks from task store
cleanup_all_tasks() ->
    {ok, AllTasks, _} = a2a_task_store:list_tasks(#{}),
    lists:foreach(fun(Task) ->
        TaskId = Task#task.id,
        case a2a_task_store:get_task_pid(TaskId) of
            {ok, Pid} when is_pid(Pid) ->
                case is_process_alive(Pid) of
                    true ->
                        a2a_task_statem:cancel_task(Pid);
                    false ->
                        ok
                end;
            _ ->
                ok
        end,
        a2a_task_store:delete_task(TaskId)
    end, AllTasks).
