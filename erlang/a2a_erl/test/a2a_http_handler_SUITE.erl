%%% @doc A2A HTTP Handler Test Suite
%%%
%%% Common Test suite for testing the HTTP/JSON-RPC interface.
%%% Tests all endpoints, error handling, and edge cases.
-module(a2a_http_handler_SUITE).

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
    test_send_message_success/1,
    test_send_message_invalid_json/1,
    test_send_message_invalid_params/1,
    test_send_message_continue_task/1,
    test_send_message_method_not_found/1,
    test_get_task_success/1,
    test_get_task_not_found/1,
    test_get_task_with_history_limit/1,
    test_get_task_zero_history/1,
    test_list_tasks_empty/1,
    test_list_tasks_with_filters/1,
    test_list_tasks_pagination/1,
    test_cancel_task_success/1,
    test_cancel_task_not_found/1,
    test_cancel_task_already_terminal/1,
    test_subscribe_to_task_success/1,
    test_subscribe_terminal_task/1,
    test_get_agent_card/1,
    test_get_extended_agent_card_unauthorized/1,
    test_cors_preflight/1
]).

%%% ============================================================================
%%% CT Callbacks
%%% ============================================================================

all() ->
    [
        test_send_message_success,
        test_send_message_invalid_json,
        test_send_message_invalid_params,
        test_send_message_continue_task,
        test_send_message_method_not_found,
        test_get_task_success,
        test_get_task_not_found,
        test_get_task_with_history_limit,
        test_get_task_zero_history,
        test_list_tasks_empty,
        test_list_tasks_with_filters,
        test_list_tasks_pagination,
        test_cancel_task_success,
        test_cancel_task_not_found,
        test_cancel_task_already_terminal,
        test_subscribe_to_task_success,
        test_subscribe_terminal_task,
        test_get_agent_card,
        test_get_extended_agent_card_unauthorized,
        test_cors_preflight
    ].

init_per_suite(Config) ->
    application:ensure_all_started(crypto),
    application:ensure_all_started(inets),
    application:ensure_all_started(meck),
    case application:ensure_all_started(a2a_erl) of
        {ok, _} -> Config;
        {error, {already_started, _}} -> Config;
        Error -> ct:fail("Failed to start a2a_erl application: ~p", [Error])
    end.

end_per_suite(_Config) ->
    ok = application:stop(a2a_erl),
    ok.

init_per_testcase(TestCase, Config) ->
    cleanup_all_tasks(),
    mock_cowboy_req(TestCase),
    Config.

end_per_testcase(_TestCase, _Config) ->
    unmock_cowboy_req(),
    cleanup_all_tasks(),
    ok.

%%% ============================================================================
%%% Test Cases: Message Handling
%%% ============================================================================

%% Test 1: POST /message:send with valid request creates new task
test_send_message_success(_Config) ->
    RequestBody = create_valid_send_message_request(<<"test-msg-1">>),
    Response = http_post(<<"/message:send">>, RequestBody),

    ?assertEqual(200, status_code(Response)),
    ?assertEqual(<<"application/json">>, content_type(Response)),

    JsonBody = json_decode(body(Response)),
    ?assertEqual(<<"2.0">>, maps:get(<<"jsonrpc">>, JsonBody)),
    ?assert(maps:is_key(<<"result">>, JsonBody)),
    ?assert(maps:is_key(<<"id">>, JsonBody)),

    Result = maps:get(<<"result">>, JsonBody),
    ?assert(maps:is_key(<<"task">>, Result)),
    Task = maps:get(<<"task">>, Result),
    ?assert(is_binary(maps:get(<<"id">>, Task))),
    ?assert(is_binary(maps:get(<<"contextId">>, Task))),
    ?assert(maps:is_key(<<"status">>, Task)),

    ok.

%% Test 2: POST /message:send with invalid JSON returns parse error
test_send_message_invalid_json(_Config) ->
    InvalidJson = <<"{invalid json}">>,
    Response = http_post(<<"/message:send">>, InvalidJson),

    ?assertEqual(400, status_code(Response)),
    ?assertEqual(<<"application/json">>, content_type(Response)),

    JsonBody = json_decode(body(Response)),
    ?assertEqual(<<"2.0">>, maps:get(<<"jsonrpc">>, JsonBody)),
    ?assert(maps:is_key(<<"error">>, JsonBody)),

    Error = maps:get(<<"error">>, JsonBody),
    ?assertEqual(?JSONRPC_PARSE_ERROR, maps:get(<<"code">>, Error)),

    ok.

%% Test 3: POST /message:send with missing required fields returns invalid params
test_send_message_invalid_params(_Config) ->
    InvalidRequest = json_encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"message/send">>,
        <<"id">> => 1,
        <<"params">> => #{}
    }),

    Response = http_post(<<"/message:send">>, InvalidRequest),

    ?assertEqual(400, status_code(Response)),

    JsonBody = json_decode(body(Response)),
    ?assert(maps:is_key(<<"error">>, JsonBody)),

    Error = maps:get(<<"error">>, JsonBody),
    ?assertEqual(?JSONRPC_INVALID_PARAMS, maps:get(<<"code">>, Error)),

    ok.

%% Test 4: POST /message:send with taskId continues existing task
test_send_message_continue_task(_Config) ->
    FirstRequest = create_valid_send_message_request(<<"test-msg-4a">>),
    FirstResponse = http_post(<<"/message:send">>, FirstRequest),
    FirstBody = json_decode(body(FirstResponse)),
    FirstResult = maps:get(<<"result">>, FirstBody),
    FirstTask = maps:get(<<"task">>, FirstResult),
    TaskId = maps:get(<<"id">>, FirstTask),

    timer:sleep(200),

    ContinueRequest = create_continue_message_request(TaskId, <<"test-msg-4b">>),
    ContinueResponse = http_post(<<"/message:send">>, ContinueRequest),

    ?assertEqual(200, status_code(ContinueResponse)),

    ContinueBody = json_decode(body(ContinueResponse)),
    ?assert(maps:is_key(<<"result">>, ContinueBody)),
    ContinueResult = maps:get(<<"result">>, ContinueBody),
    ?assert(maps:is_key(<<"message">>, ContinueResult)),

    ok.

%% Test 5: POST with invalid JSON-RPC method returns method not found
test_send_message_method_not_found(_Config) ->
    InvalidMethod = json_encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"invalid/method">>,
        <<"id">> => 1,
        <<"params">> => #{}
    }),

    Response = http_post(<<"/message:send">>, InvalidMethod),

    ?assertEqual(400, status_code(Response)),

    JsonBody = json_decode(body(Response)),
    Error = maps:get(<<"error">>, JsonBody),
    ?assertEqual(?JSONRPC_METHOD_NOT_FOUND, maps:get(<<"code">>, Error)),

    ok.

%%% ============================================================================
%%% Test Cases: Task Retrieval
%%% ============================================================================

%% Test 6: GET /tasks/{id} with valid task ID returns task
test_get_task_success(_Config) ->
    SendRequest = create_valid_send_message_request(<<"test-msg-6">>),
    SendResponse = http_post(<<"/message:send">>, SendRequest),
    SendBody = json_decode(body(SendResponse)),
    TaskId = get_task_id_from_response(SendBody),

    GetPath = <<"/tasks/", TaskId/binary>>,
    GetResponse = http_get(GetPath),

    ?assertEqual(200, status_code(GetResponse)),
    ?assertEqual(<<"application/json">>, content_type(GetResponse)),

    JsonBody = json_decode(body(GetResponse)),
    ?assert(maps:is_key(<<"result">>, JsonBody)),
    Result = maps:get(<<"result">>, JsonBody),
    ?assertEqual(TaskId, maps:get(<<"id">>, Result)),

    ok.

%% Test 7: GET /tasks/{id} with non-existent task returns 404
test_get_task_not_found(_Config) ->
    FakeTaskId = <<"non-existent-task-12345">>,
    GetPath = <<"/tasks/", FakeTaskId/binary>>,
    Response = http_get(GetPath),

    ?assertEqual(404, status_code(Response)),

    JsonBody = json_decode(body(Response)),
    ?assert(maps:is_key(<<"error">>, JsonBody)),
    Error = maps:get(<<"error">>, JsonBody),
    ?assertEqual(?A2A_TASK_NOT_FOUND, maps:get(<<"code">>, Error)),

    ok.

%% Test 8: GET /tasks/{id}?historyLength=N limits history
test_get_task_with_history_limit(_Config) ->
    SendRequest = create_valid_send_message_request(<<"test-msg-8">>),
    SendResponse = http_post(<<"/message:send">>, SendRequest),
    SendBody = json_decode(body(SendResponse)),
    TaskId = get_task_id_from_response(SendBody),

    GetPath = <<"/tasks/", TaskId/binary, "?historyLength=1">>,
    GetResponse = http_get(GetPath),

    ?assertEqual(200, status_code(GetResponse)),

    JsonBody = json_decode(body(GetResponse)),
    Result = maps:get(<<"result">>, JsonBody),
    History = maps:get(<<"history">>, Result, []),
    ?assertEqual(1, length(History)),

    ok.

%% Test 9: GET /tasks/{id}?historyLength=0 returns empty history
test_get_task_zero_history(_Config) ->
    SendRequest = create_valid_send_message_request(<<"test-msg-9">>),
    SendResponse = http_post(<<"/message:send">>, SendRequest),
    SendBody = json_decode(body(SendResponse)),
    TaskId = get_task_id_from_response(SendBody),

    GetPath = <<"/tasks/", TaskId/binary, "?historyLength=0">>,
    GetResponse = http_get(GetPath),

    ?assertEqual(200, status_code(GetResponse)),

    JsonBody = json_decode(body(GetResponse)),
    Result = maps:get(<<"result">>, JsonBody),
    History = maps:get(<<"history">>, Result, []),
    ?assertEqual(0, length(History)),

    ok.

%%% ============================================================================
%%% Test Cases: Task Listing
%%% ============================================================================

%% Test 10: GET /tasks when no tasks exist returns empty list
test_list_tasks_empty(_Config) ->
    Response = http_get(<<"/tasks">>),

    ?assertEqual(200, status_code(Response)),
    ?assertEqual(<<"application/json">>, content_type(Response)),

    JsonBody = json_decode(body(Response)),
    ?assert(maps:is_key(<<"result">>, JsonBody)),
    Result = maps:get(<<"result">>, JsonBody),
    Tasks = maps:get(<<"tasks">>, Result),
    ?assertEqual(0, length(Tasks)),
    ?assertEqual(<<>>, maps:get(<<"nextPageToken">>, Result)),

    ok.

%% Test 11: GET /tasks with contextId and status filters
test_list_tasks_with_filters(_Config) ->
    Request1 = create_send_message_with_context(<<"ctx-11">>, <<"test-msg-11a">>),
    http_post(<<"/message:send">>, Request1),

    Request2 = create_send_message_with_context(<<"ctx-12">>, <<"test-msg-11b">>),
    http_post(<<"/message:send">>, Request2),

    timer:sleep(100),

    FilterPath = <<"/tasks?contextId=ctx-11">>,
    Response = http_get(FilterPath),

    ?assertEqual(200, status_code(Response)),

    JsonBody = json_decode(body(Response)),
    Result = maps:get(<<"result">>, JsonBody),
    Tasks = maps:get(<<"tasks">>, Result),
    ?assert(length(Tasks) >= 1),

    ok.

%% Test 12: GET /tasks with pageSize and pageToken pagination
test_list_tasks_pagination(_Config) ->
    lists:foreach(fun(N) ->
        MsgId = list_to_binary(io_lib:format("test-msg-12-~p", [N])),
        Request = create_valid_send_message_request(MsgId),
        http_post(<<"/message:send">>, Request)
    end, lists:seq(1, 5)),

    timer:sleep(200),

    FirstPagePath = <<"/tasks?pageSize=2">>,
    FirstResponse = http_get(FirstPagePath),

    ?assertEqual(200, status_code(FirstResponse)),

    FirstBody = json_decode(body(FirstResponse)),
    FirstResult = maps:get(<<"result">>, FirstBody),
    FirstTasks = maps:get(<<"tasks">>, FirstResult),
    ?assertEqual(2, length(FirstTasks)),
    NextToken = maps:get(<<"nextPageToken">>, FirstResult),
    ?assertNotEqual(<<>>, NextToken),

    SecondPagePath = <<"/tasks?pageSize=2&pageToken=", NextToken/binary>>,
    SecondResponse = http_get(SecondPagePath),

    ?assertEqual(200, status_code(SecondResponse)),

    ok.

%%% ============================================================================
%%% Test Cases: Task Cancellation
%%% ============================================================================

%% Test 13: POST /tasks/{id}:cancel on active task succeeds
test_cancel_task_success(_Config) ->
    SendRequest = create_valid_send_message_request(<<"test-msg-13">>),
    SendResponse = http_post(<<"/message:send">>, SendRequest),
    SendBody = json_decode(body(SendResponse)),
    TaskId = get_task_id_from_response(SendBody),

    timer:sleep(100),

    CancelPath = <<"/tasks/", TaskId/binary, ":cancel">>,
    CancelResponse = http_post(CancelPath, <<>>),

    ?assertEqual(200, status_code(CancelResponse)),

    CancelBody = json_decode(body(CancelResponse)),
    Result = maps:get(<<"result">>, CancelBody),
    Status = maps:get(<<"status">>, Result),
    ?assertEqual(<<"TASK_STATE_CANCELED">>, maps:get(<<"state">>, Status)),

    ok.

%% Test 14: POST /tasks/{id}:cancel on non-existent task returns 404
test_cancel_task_not_found(_Config) ->
    FakeTaskId = <<"fake-task-14">>,
    CancelPath = <<"/tasks/", FakeTaskId/binary, ":cancel">>,
    Response = http_post(CancelPath, <<>>),

    ?assertEqual(404, status_code(Response)),

    JsonBody = json_decode(body(Response)),
    Error = maps:get(<<"error">>, JsonBody),
    ?assertEqual(?A2A_TASK_NOT_FOUND, maps:get(<<"code">>, Error)),

    ok.

%% Test 15: POST /tasks/{id}:cancel on terminal task returns error
test_cancel_task_already_terminal(_Config) ->
    SendRequest = create_valid_send_message_request(<<"test-msg-15">>),
    SendResponse = http_post(<<"/message:send">>, SendRequest),
    SendBody = json_decode(body(SendResponse)),
    TaskId = get_task_id_from_response(SendBody),

    timer:sleep(500),

    CancelPath = <<"/tasks/", TaskId/binary, ":cancel">>,
    CancelResponse = http_post(CancelPath, <<>>),

    ?assertEqual(400, status_code(CancelResponse)),

    CancelBody = json_decode(body(CancelResponse)),
    Error = maps:get(<<"error">>, CancelBody),
    ?assertEqual(?A2A_TASK_ALREADY_TERMINAL, maps:get(<<"code">>, Error)),

    ok.

%%% ============================================================================
%%% Test Cases: Subscription & Streaming
%%% ============================================================================

%% Test 16: GET /tasks/{id}:subscribe on active task returns SSE info
test_subscribe_to_task_success(_Config) ->
    SendRequest = create_valid_send_message_request(<<"test-msg-16">>),
    SendResponse = http_post(<<"/message:send">>, SendRequest),
    SendBody = json_decode(body(SendResponse)),
    TaskId = get_task_id_from_response(SendBody),

    SubscribePath = <<"/tasks/", TaskId/binary, ":subscribe">>,
    Response = http_get(SubscribePath),

    ?assertEqual(200, status_code(Response)),

    JsonBody = json_decode(body(Response)),
    Result = maps:get(<<"result">>, JsonBody),
    ?assertEqual(TaskId, maps:get(<<"taskId">>, Result)),
    ?assert(maps:is_key(<<"message">>, Result)),

    ok.

%% Test 17: GET /tasks/{id}:subscribe on terminal task returns error
test_subscribe_terminal_task(_Config) ->
    SendRequest = create_valid_send_message_request(<<"test-msg-17">>),
    SendResponse = http_post(<<"/message:send">>, SendRequest),
    SendBody = json_decode(body(SendResponse)),
    TaskId = get_task_id_from_response(SendBody),

    timer:sleep(500),

    SubscribePath = <<"/tasks/", TaskId/binary, ":subscribe">>,
    Response = http_get(SubscribePath),

    ?assertEqual(400, status_code(Response)),

    JsonBody = json_decode(body(Response)),
    Error = maps:get(<<"error">>, JsonBody),
    ?assertEqual(?A2A_UNSUPPORTED_OPERATION, maps:get(<<"code">>, Error)),

    ok.

%%% ============================================================================
%%% Test Cases: Agent Card
%%% ============================================================================

%% Test 18: GET /.well-known/agent-card.json returns agent card
test_get_agent_card(_Config) ->
    Response = http_get(<<"/.well-known/agent-card.json">>),

    ?assertEqual(200, status_code(Response)),
    ?assertEqual(<<"application/json">>, content_type(Response)),

    JsonBody = json_decode(body(Response)),
    ?assert(is_binary(maps:get(<<"name">>, JsonBody))),
    ?assert(is_binary(maps:get(<<"description">>, JsonBody))),
    ?assert(is_binary(maps:get(<<"version">>, JsonBody))),
    ?assert(maps:is_key(<<"supportedInterfaces">>, JsonBody)),
    ?assert(maps:is_key(<<"capabilities">>, JsonBody)),
    ?assert(maps:is_key(<<"skills">>, JsonBody)),

    ok.

%% Test 19: GET /extendedAgentCard without auth returns 401
test_get_extended_agent_card_unauthorized(_Config) ->
    Response = http_get(<<"/extendedAgentCard">>),

    ?assertEqual(401, status_code(Response)),

    JsonBody = json_decode(body(Response)),
    ?assert(maps:is_key(<<"error">>, JsonBody)),
    Error = maps:get(<<"error">>, JsonBody),
    ?assertEqual(?A2A_AUTHENTICATION_REQUIRED, maps:get(<<"code">>, Error)),

    ok.

%%% ============================================================================
%%% Test Cases: CORS & Routing
%%% ============================================================================

%% Test 20: OPTIONS request returns proper CORS headers
test_cors_preflight(_Config) ->
    Response = http_options(<<"/message:send">>),

    ?assertEqual(204, status_code(Response)),

    Headers = headers(Response),
    ?assert(maps:is_key(<<"access-control-allow-origin">>, Headers)),
    ?assertEqual(<<"*">>, maps:get(<<"access-control-allow-origin">>, Headers)),

    ?assert(maps:is_key(<<"access-control-allow-methods">>, Headers)),
    AllowMethods = maps:get(<<"access-control-allow-methods">>, Headers),
    ?assertNotEqual(<<>>, AllowMethods),

    ok.

%%% ============================================================================
%%% Helper Functions
%%% ============================================================================

create_valid_send_message_request(MessageId) ->
    Params = #{
        <<"message">> => #{
            <<"messageId">> => MessageId,
            <<"role">> => <<"ROLE_USER">>,
            <<"parts">> => [
                #{
                    <<"text">> => <<"Test message content">>,
                    <<"mediaType">> => <<"text/plain">>
                }
            ]
        }
    },
    json_encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"message/send">>,
        <<"id">> => 1,
        <<"params">> => Params
    }).

create_continue_message_request(TaskId, MessageId) ->
    Params = #{
        <<"message">> => #{
            <<"messageId">> => MessageId,
            <<"taskId">> => TaskId,
            <<"role">> => <<"ROLE_USER">>,
            <<"parts">> => [
                #{
                    <<"text">> => <<"Continue task">>,
                    <<"mediaType">> => <<"text/plain">>
                }
            ]
        }
    },
    json_encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"message/send">>,
        <<"id">> => 2,
        <<"params">> => Params
    }).

create_send_message_with_context(ContextId, MessageId) ->
    Params = #{
        <<"message">> => #{
            <<"messageId">> => MessageId,
            <<"contextId">> => ContextId,
            <<"role">> => <<"ROLE_USER">>,
            <<"parts">> => [
                #{
                    <<"text">> => <<"Test with context">>,
                    <<"mediaType">> => <<"text/plain">>
                }
            ]
        }
    },
    json_encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"method">> => <<"message/send">>,
        <<"id">> => 1,
        <<"params">> => Params
    }).

get_task_id_from_response(JsonBody) ->
    Result = maps:get(<<"result">>, JsonBody),
    Task = maps:get(<<"task">>, Result),
    maps:get(<<"id">>, Task).

%% Mock cowboy_req functions using meck
mock_cowboy_req(_TestCase) ->
    meck:new(cowboy_req, [no_link, passthrough]),

    %% Mock method/1
    meck:expect(cowboy_req, method, fun(Req) ->
        maps:get(method, Req)
    end),

    %% Mock path/1
    meck:expect(cowboy_req, path, fun(Req) ->
        maps:get(path, Req)
    end),

    %% Mock parse_qs/1
    meck:expect(cowboy_req, parse_qs, fun(Req) ->
        maps:get(qs, Req, [])
    end),

    %% Mock read_body/1
    meck:expect(cowboy_req, read_body, fun(Req) ->
        Body = maps:get(body, Req, <<>>),
        {ok, Body, Req}
    end),

    %% Mock header/2
    meck:expect(cowboy_req, header, fun(Name, Req) ->
        Headers = maps:get(headers, Req, #{}),
        maps:get(Name, Headers, undefined)
    end),

    %% Mock reply/4
    meck:expect(cowboy_req, reply, fun(Status, Headers, Body, Req) ->
        Req#{resp_status => Status, resp_headers => Headers, resp_body => Body}
    end),

    %% Mock match_qs/2
    meck:expect(cowboy_req, match_qs, fun(_Spec, Req) ->
        Qs = maps:get(qs, Req, []),
        lists:foldl(fun({K, V}, Acc) ->
            Acc#{K => V}
        end, #{}, Qs)
    end),

    ok.

unmock_cowboy_req() ->
    meck:unload(cowboy_req).

http_post(Path, Body) ->
    {PathOnly, Qs} = split_path_qs(Path),

    Req = #{
        method => <<"POST">>,
        path => PathOnly,
        qs => Qs,
        body => Body,
        headers => #{}
    },

    case a2a_http_handler:init(Req, []) of
        {ok, RespReq, _State} ->
            #{status => maps:get(resp_status, RespReq, 200),
              headers => maps:get(resp_headers, RespReq, #{}),
              body => maps:get(resp_body, RespReq, <<>>)}
    end.

http_get(Path) ->
    {PathOnly, Qs} = split_path_qs(Path),

    Req = #{
        method => <<"GET">>,
        path => PathOnly,
        qs => Qs,
        body => <<>>,
        headers => #{}
    },

    case a2a_http_handler:init(Req, []) of
        {ok, RespReq, _State} ->
            #{status => maps:get(resp_status, RespReq, 200),
              headers => maps:get(resp_headers, RespReq, #{}),
              body => maps:get(resp_body, RespReq, <<>>)}
    end.

http_options(Path) ->
    {PathOnly, _Qs} = split_path_qs(Path),

    Req = #{
        method => <<"OPTIONS">>,
        path => PathOnly,
        qs => [],
        body => <<>>,
        headers => #{}
    },

    case a2a_http_handler:init(Req, []) of
        {ok, RespReq, _State} ->
            #{status => maps:get(resp_status, RespReq, 200),
              headers => maps:get(resp_headers, RespReq, #{}),
              body => maps:get(resp_body, RespReq, <<>>)}
    end.

split_path_qs(Path) ->
    case binary:split(Path, <<"?">>) of
        [P, Qs] -> {P, parse_qs_string(Qs)};
        [P] -> {P, []}
    end.

parse_qs_string(Qs) ->
    Parts = binary:split(Qs, <<"&">>, [global]),
    lists:map(fun(Part) ->
        case binary:split(Part, <<"=">>) of
            [Key, Value] -> {Key, Value};
            [Key] -> {Key, <<>>}
        end
    end, Parts).

status_code(Response) -> maps:get(status, Response).

body(Response) -> maps:get(body, Response).

headers(Response) -> maps:get(headers, Response).

content_type(Response) ->
    Headers = headers(Response),
    maps:get(<<"content-type">>, Headers, undefined).

json_encode(Term) -> json:encode(Term).

json_decode(Json) -> json:decode(Json).

cleanup_all_tasks() ->
    case ets:info(a2a_tasks) of
        undefined -> ok;
        _ ->
            Tasks = ets:tab2list(a2a_tasks),
            lists:foreach(fun({TaskId, _Task}) ->
                a2a_task_store:delete_task(TaskId)
            end, Tasks)
    end.
