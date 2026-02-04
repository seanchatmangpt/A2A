%% @doc Unit tests for craftplan_api_client module
%% Tests HTTP client functionality, API calls, and error handling

-module(craftplan_api_client_tests).

-include_lib("eunit/include/eunit.hrl").

%% Test data
-define(TEST_URL, <<"https://api.craftplan.example.com/v1">>).
-define(TEST_HEADERS, #{
    <<"content-type">> => <<"application/json">>,
    <<"authorization">> => <<"Bearer test-token">>
}).
-define(TEST_TOOLS_RESPONSE, #{
    tools => [
        #{name => <<"build">>, description => <<"Build project">>},
        #{name => <<"deploy">>, description => <<"Deploy to production">>}
    ]
}).
-define(TEST_EXECUTE_REQUEST, #{
    tool => <<"build">>,
    arguments => #{target => <<"dev">>}
}).
-define(TEST_EXECUTE_RESPONSE, #{
    status => <<"completed">>,
    result => <<"Build successful in 2m 30s">>
}).

%% Test suite
api_client_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        [
            fun test_connect/0,
            fun test_get_tools/0,
            fun test_execute_tool/0,
            fun test_http_error_handling/0,
            fun test_authentication/0,
            fun test_retry_logic/0
        ]
    }.

%% Setup and cleanup
setup() ->
    % Mock HTTP client
    meck:new(hackney, [passthrough]),
    meck:new(jiffy, [passthrough]),
    ok.

cleanup(_) ->
    meck:unload(),
    ok.

%% Test connection
test_connect() ->
    % Mock successful connection
    meck:expect(hackney, request,
        fun(get, Url, Headers, <<>>, _) ->
            case Url of
                <<?TEST_URL/binary, "/tools">> ->
                    Body = jiffy:encode(?TEST_TOOLS_RESPONSE),
                    {ok, 200, Headers, Body};
                _ ->
                    {error, <<"Not found">>}
            end
        end
    ),

    % Test connection
    {ok, Pid} = craftplan_api_client:connect(?TEST_URL, ?TEST_HEADERS),
    ?_assert(is_pid(Pid)).

%% Test get tools
test_get_tools() ->
    % Mock successful response
    meck:expect(hackney, request,
        fun(get, _, _, _, _) ->
            Body = jiffy:encode(?TEST_TOOLS_RESPONSE),
            {ok, 200, [], Body}
        end
    ),

    % Test tools retrieval
    {ok, Tools} = craftplan_api_client:get_tools(?TEST_URL, ?TEST_HEADERS),

    % Verify response structure
    ?_assertEqual(2, length(Tools)),
    ?_assertEqual(<<"build">>, maps:get(name, lists:nth(1, Tools))),
    ?_assertEqual(<<"deploy">>, maps:get(name, lists:nth(2, Tools))).

%% Test execute tool
test_execute_tool() ->
    % Mock successful execution
    meck:expect(hackney, request,
        fun(post, _, _, Body, _) ->
            Request = jiffy:decode(Body),
            case maps:get(<<"tool">>, Request) of
                <<"build">> ->
                    Response = jiffy:encode(?TEST_EXECUTE_RESPONSE),
                    {ok, 200, [], Response};
                _ ->
                    {error, <<"Unknown tool">>}
            end
        end
    ),

    % Test tool execution
    {ok, Result} = craftplan_api_client:execute_tool(
        ?TEST_URL, ?TEST_HEADERS, <<"build">>, #{target => <<"dev">>}
    ),

    % Verify response
    ?_assertEqual(<<"completed">>, maps:get(status, Result)),
    ?_assertEqual(<<"Build successful in 2m 30s">>, maps:get(result, Result)).

%% Test HTTP error handling
test_http_error_handling() ->
    % Mock HTTP error response
    meck:expect(hackney, request,
        fun(_, _, _, _, _) ->
            {error, <<"Connection timeout">>}
        end
    ),

    % Test error handling
    {error, Error} = craftplan_api_client:get_tools(?TEST_URL, ?TEST_HEADERS),
    ?_assertEqual(<<"Connection timeout">>, Error).

%% Test authentication
test_authentication() ->
    % Test with different auth methods
    HeadersWithoutAuth = #{<<"content-type">> => <<"application/json">>},
    AuthHeaders = ?TEST_HEADERS,

    % Mock 401 response without auth
    meck:expect(hackney, request,
        fun(get, _, _, _, _) ->
            {ok, 401, [], <<"Unauthorized">>}
        end
    ),

    {error, Error1} = craftplan_api_client:get_tools(?TEST_URL, HeadersWithoutAuth),
    ?_assertEqual(<<"Unauthorized">>, Error1),

    % Mock 200 response with auth
    meck:expect(hackney, request,
        fun(get, _, _, _, _) ->
            Body = jiffy:encode(?TEST_TOOLS_RESPONSE),
            {ok, 200, [], Body}
        end
    ),

    {ok, Tools} = craftplan_api_client:get_tools(?TEST_URL, AuthHeaders),
    ?_assertEqual(2, length(Tools)).

%% Test retry logic
test_retry_logic() ->
    % Mock transient failure followed by success
    RetryCount = 0,
    meck:expect(hackney, request,
        fun(_, _, _, _, _) ->
            if RetryCount =< 2 ->
                {error, <<"Connection failed">>};
            true ->
                Body = jiffy:encode(?TEST_TOOLS_RESPONSE),
                {ok, 200, [], Body}
            end
        end
    ),

    % Test with retry logic (simulated)
    {ok, Tools} = craftplan_api_client:get_tools_with_retry(
        ?TEST_URL, ?TEST_HEADERS, 3
    ),

    % Verify eventual success
    ?_assertEqual(2, length(Tools)).

%% Integration helper function
make_api_call(Method, Url, Headers, Body) ->
    % Simulate making API calls
    case Method of
        get ->
            case Url of
                <<?TEST_URL/binary, "/tools">> ->
                    BodyResp = jiffy:encode(?TEST_TOOLS_RESPONSE),
                    {ok, 200, Headers, BodyResp};
                _ ->
                    {error, <<"Not found">>}
            end;
        post ->
            case Body of
                <<"{\"tool\":\"build\",\"arguments\":{\"target\":\"dev\"}}">> ->
                    Response = jiffy:encode(?TEST_EXECUTE_RESPONSE),
                    {ok, 200, Headers, Response};
                _ ->
                    {error, <<"Invalid request">>}
            end
    end.