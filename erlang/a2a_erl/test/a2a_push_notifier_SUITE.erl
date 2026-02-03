%%% @doc A2A Push Notifier Test Suite
%%%
%%% Common Test suite for testing the push notification functionality.
%%% Tests cover synchronous and asynchronous notifications, authentication,
%%% token handling, payload building, and error scenarios.
-module(a2a_push_notifier_SUITE).

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
    test_notify_success/1,
    test_notify_http_error/1,
    test_notify_network_error/1,
    test_notify_with_authentication/1,
    test_notify_with_token/1,
    test_notify_with_both_auth_and_token/1,
    test_notify_async/1,
    test_build_payload/1,
    test_build_headers_no_auth/1,
    test_build_headers_with_auth/1
]).

%%% ============================================================================
%%% CT Callbacks
%%% ============================================================================

all() ->
    [
        test_notify_success,
        test_notify_http_error,
        test_notify_network_error,
        test_notify_with_authentication,
        test_notify_with_token,
        test_notify_with_both_auth_and_token,
        test_notify_async,
        test_build_payload,
        test_build_headers_no_auth,
        test_build_headers_with_auth
    ].

init_per_suite(Config) ->
    %% Start required applications
    application:ensure_all_started(crypto),
    application:ensure_all_started(inets),

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
    %% Ensure meck is unloaded after each test
    case whereis(meck_sup) of
        undefined -> ok;
        _ -> meck:unload()
    end,
    ok.

%%% ============================================================================
%%% Test Cases
%%% ============================================================================

%% Test successful push notification (200 OK)
test_notify_success(_Config) ->
    %% Setup mock httpc
    meck:new(httpc, [unstick, passthrough]),
    meck:expect(httpc, request, fun
        (post, _Request, _HTTPOptions, []) ->
            {ok, {{_, 200, "OK"}, [], <<"{\"status\":\"ok\"}">>}}
    end),

    %% Create test data
    Task = create_test_task(),
    Config = create_test_push_config(<<"http://example.com/webhook">>),

    %% Execute
    Result = a2a_push_notifier:notify(Config, Task),

    %% Verify
    ?assertEqual(ok, Result),

    %% Verify httpc was called correctly
    ?assert(meck:called(httpc, request, '_', 1)),

    ok.

%% Test HTTP error response (400 Bad Request)
test_notify_http_error(_Config) ->
    %% Setup mock httpc to return 400 error
    meck:new(httpc, [unstick, passthrough]),
    meck:expect(httpc, request, fun
        (post, _Request, _HTTPOptions, []) ->
            {ok, {{_, 400, "Bad Request"}, [], <<"{\"error\":\"invalid request\"}">>}}
    end),

    %% Create test data
    Task = create_test_task(),
    Config = create_test_push_config(<<"http://example.com/webhook">>),

    %% Execute
    Result = a2a_push_notifier:notify(Config, Task),

    %% Verify error returned
    ?assertEqual({error, {http_status, 400}}, Result),

    ok.

%% Test network/connection error
test_notify_network_error(_Config) ->
    %% Setup mock httpc to return network error
    meck:new(httpc, [unstick, passthrough]),
    meck:expect(httpc, request, fun
        (post, _Request, _HTTPOptions, []) ->
            {error, econnrefused}
    end),

    %% Create test data
    Task = create_test_task(),
    Config = create_test_push_config(<<"http://example.com/webhook">>),

    %% Execute
    Result = a2a_push_notifier:notify(Config, Task),

    %% Verify error returned
    ?assertEqual({error, econnrefused}, Result),

    ok.

%% Test notification with authentication header
test_notify_with_authentication(_Config) ->
    %% Setup mock httpc to capture headers
    meck:new(httpc, [unstick, passthrough]),
    meck:expect(httpc, request, fun
        (post, {_Url, Headers, _ContentType, _Body}, _HTTPOptions, []) ->
            %% Verify Authorization header
            AuthHeader = lists:keyfind("Authorization", 1, Headers),
            ?assertMatch({"Authorization", "Bearer secret-token"}, AuthHeader),
            {ok, {{_, 200, "OK"}, [], <<"{}">>}};
        (_Method, _Request, _HTTPOptions, []) ->
            {ok, {{_, 200, "OK"}, [], <<"{}">>}}
    end),

    %% Create test data with authentication
    Task = create_test_task(),
    PushConfig = #push_notification_config{
        url = <<"http://example.com/webhook">>,
        authentication = #authentication_info{
            scheme = <<"Bearer">>,
            credentials = <<"secret-token">>
        }
    },
    Config = #task_push_notification_config{
        tenant = <<"tenant-001">>,
        id = <<"config-001">>,
        task_id = Task#task.id,
        push_notification_config = PushConfig
    },

    %% Execute
    Result = a2a_push_notifier:notify(Config, Task),

    %% Verify
    ?assertEqual(ok, Result),

    ok.

%% Test notification with X-A2A-Token header
test_notify_with_token(_Config) ->
    %% Setup mock httpc to capture headers
    meck:new(httpc, [unstick, passthrough]),
    meck:expect(httpc, request, fun
        (post, {_Url, Headers, _ContentType, _Body}, _HTTPOptions, []) ->
            %% Verify X-A2A-Token header
            TokenHeader = lists:keyfind("X-A2A-Token", 1, Headers),
            ?assertMatch({"X-A2A-Token", "my-webhook-token"}, TokenHeader),
            {ok, {{_, 200, "OK"}, [], <<"{}">>}};
        (_Method, _Request, _HTTPOptions, []) ->
            {ok, {{_, 200, "OK"}, [], <<"{}">>}}
    end),

    %% Create test data with token
    Task = create_test_task(),
    PushConfig = #push_notification_config{
        url = <<"http://example.com/webhook">>,
        token = <<"my-webhook-token">>
    },
    Config = #task_push_notification_config{
        tenant = <<"tenant-001">>,
        id = <<"config-001">>,
        task_id = Task#task.id,
        push_notification_config = PushConfig
    },

    %% Execute
    Result = a2a_push_notifier:notify(Config, Task),

    %% Verify
    ?assertEqual(ok, Result),

    ok.

%% Test notification with both authentication and token headers
test_notify_with_both_auth_and_token(_Config) ->
    %% Setup mock httpc to capture both headers
    meck:new(httpc, [unstick, passthrough]),
    meck:expect(httpc, request, fun
        (post, {_Url, Headers, _ContentType, _Body}, _HTTPOptions, []) ->
            %% Verify both headers present
            AuthHeader = lists:keyfind("Authorization", 1, Headers),
            TokenHeader = lists:keyfind("X-A2A-Token", 1, Headers),
            ?assertMatch({"Authorization", "Basic dXNlcjpwYXNz"}, AuthHeader),
            ?assertMatch({"X-A2A-Token", "webhook-token"}, TokenHeader),
            {ok, {{_, 200, "OK"}, [], <<"{}">>}};
        (_Method, _Request, _HTTPOptions, []) ->
            {ok, {{_, 200, "OK"}, [], <<"{}">>}}
    end),

    %% Create test data with both auth and token
    Task = create_test_task(),
    PushConfig = #push_notification_config{
        url = <<"http://example.com/webhook">>,
        token = <<"webhook-token">>,
        authentication = #authentication_info{
            scheme = <<"Basic">>,
            credentials = <<"dXNlcjpwYXNz">>  % base64 encoded "user:pass"
        }
    },
    Config = #task_push_notification_config{
        tenant = <<"tenant-001">>,
        id = <<"config-001">>,
        task_id = Task#task.id,
        push_notification_config = PushConfig
    },

    %% Execute
    Result = a2a_push_notifier:notify(Config, Task),

    %% Verify
    ?assertEqual(ok, Result),

    ok.

%% Test async notification returns immediately
test_notify_async(_Config) ->
    %% Setup mock httpc with delay
    meck:new(httpc, [unstick, passthrough]),
    meck:expect(httpc, request, fun
        (post, _Request, _HTTPOptions, []) ->
            %% Simulate network delay
            timer:sleep(100),
            {ok, {{_, 200, "OK"}, [], <<"{}">>}}
    end),

    %% Create test data
    Task = create_test_task(),
    Config = create_test_push_config(<<"http://example.com/webhook">>),

    %% Measure execution time
    StartTime = erlang:monotonic_time(millisecond),
    Result = a2a_push_notifier:notify_async(Config, Task),
    EndTime = erlang:monotonic_time(millisecond),
    Elapsed = EndTime - StartTime,

    %% Should return immediately (well under 100ms delay)
    ?assertEqual(ok, Result),
    ?assert(Elapsed < 50, "Async notification should return immediately, took ~p ms", [Elapsed]),

    %% Wait for async process to complete
    timer:sleep(150),

    %% Verify httpc was called
    ?assert(meck:called(httpc, request, '_', 1)),

    ok.

%% Test payload building and JSON structure
test_build_payload(_Config) ->
    %% Create test task with various states
    Task = #task{
        id = <<"task-123">>,
        context_id = <<"context-456">>,
        status = #task_status{
            state = working,
            timestamp = 1698765432000,
            message = undefined
        },
        artifacts = [],
        history = [],
        metadata = #{<<"key">> => <<"value">>}
    },

    %% Build payload (internal function, so we test via notify)
    meck:new(httpc, [unstick, passthrough]),
    meck:expect(httpc, request, fun
        (post, {_Url, _Headers, _ContentType, Payload}, _HTTPOptions, []) ->
            %% Decode and verify payload
            PayloadMap = json:decode(Payload),

            %% Verify JSON-RPC structure
            ?assertEqual(<<"2.0">>, maps:get(<<"jsonrpc">>, PayloadMap)),
            ?assertEqual(<<"task/statusUpdate">>, maps:get(<<"method">>, PayloadMap)),

            %% Verify params
            Params = maps:get(<<"params">>, PayloadMap),
            ?assertEqual(<<"task-123">>, maps:get(<<"taskId">>, Params)),
            ?assertEqual(<<"context-456">>, maps:get(<<"contextId">>, Params)),

            %% Verify status encoding
            Status = maps:get(<<"status">>, Params),
            ?assertEqual(<<"TASK_STATE_WORKING">>, maps:get(<<"state">>, Status)),

            %% Verify metadata
            ?assertEqual(#{<<"key">> => <<"value">>}, maps:get(<<"metadata">>, Params)),

            {ok, {{_, 200, "OK"}, [], <<"{}">>}}
    end),

    Config = create_test_push_config(<<"http://example.com/webhook">>),
    a2a_push_notifier:notify(Config, Task),

    ok.

%% Test headers building without authentication
test_build_headers_no_auth(_Config) ->
    %% Setup mock to verify headers
    meck:new(httpc, [unstick, passthrough]),
    meck:expect(httpc, request, fun
        (post, {_Url, Headers, _ContentType, _Body}, _HTTPOptions, []) ->
            %% Should only have Content-Type header
            ?assertEqual(1, length(Headers)),
            ?assertMatch({"Content-Type", "application/json"}, lists:keyfind("Content-Type", 1, Headers)),

            %% Should NOT have auth or token headers
            ?assertEqual(false, lists:keyfind("Authorization", 1, Headers)),
            ?assertEqual(false, lists:keyfind("X-A2A-Token", 1, Headers)),

            {ok, {{_, 200, "OK"}, [], <<"{}">>}}
    end),

    %% Create config without auth or token
    Task = create_test_task(),
    PushConfig = #push_notification_config{
        url = <<"http://example.com/webhook">>
    },
    Config = #task_push_notification_config{
        tenant = <<"tenant-001">>,
        id = <<"config-001">>,
        task_id = Task#task.id,
        push_notification_config = PushConfig
    },

    a2a_push_notifier:notify(Config, Task),

    ok.

%% Test headers building with authentication
test_build_headers_with_auth(_Config) ->
    %% Test with scheme only (no credentials)
    meck:new(httpc, [unstick, passthrough]),
    meck:expect(httpc, request, fun
        (post, {_Url, Headers, _ContentType, _Body}, _HTTPOptions, []) ->
            AuthHeader = lists:keyfind("Authorization", 1, Headers),
            ?assertMatch({"Authorization", "Bearer"}, AuthHeader),
            {ok, {{_, 200, "OK"}, [], <<"{}">>}}
    end),

    Task = create_test_task(),
    PushConfig = #push_notification_config{
        url = <<"http://example.com/webhook">>,
        authentication = #authentication_info{
            scheme = <<"Bearer">>,
            credentials = undefined
        }
    },
    Config = #task_push_notification_config{
        tenant = <<"tenant-001">>,
        id = <<"config-001">>,
        task_id = Task#task.id,
        push_notification_config = PushConfig
    },

    a2a_push_notifier:notify(Config, Task),

    ok.

%%% ============================================================================
%%% Helper Functions
%%% ============================================================================

%% @doc Create a test task record
create_test_task() ->
    #task{
        id = <<"test-task-001">>,
        context_id = <<"test-context-001">>,
        status = #task_status{
            state = working,
            timestamp = erlang:system_time(millisecond),
            message = undefined
        },
        artifacts = [],
        history = [],
        metadata = #{}
    }.

%% @doc Create a test push notification config
create_test_push_config(Url) ->
    PushConfig = #push_notification_config{
        url = Url
    },
    #task_push_notification_config{
        tenant = <<"tenant-001">>,
        id = <<"config-001">>,
        task_id = <<"test-task-001">>,
        push_notification_config = PushConfig
    }.
