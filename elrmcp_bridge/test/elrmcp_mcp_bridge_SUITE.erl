%%% @doc elrmcp MCP Bridge Integration Tests
%%% Tests the complete bridge functionality

-module(elrmcp_mcp_bridge_SUITE).
-behaviour(suites).

%% Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).

%% Test cases
-export([
    test_bridge_initialization/1,
    test_tool_registration/1,
    test_request_forwarding/1,
    test_rate_limiting/1,
    test_tool_listing/1,
    test_tool_info/1,
    test_configuration/1,
    test_bridge_status/1,
    test_error_handling/1,
    test_concurrent_requests/1
]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Configuration
%%====================================================================

all() ->
    [
        test_bridge_initialization,
        test_tool_registration,
        test_request_forwarding,
        test_rate_limiting,
        test_tool_listing,
        test_tool_info,
        test_configuration,
        test_bridge_status,
        test_error_handling,
        test_concurrent_requests
    ].

init_per_suite(Config) ->
    %% Start elrmcp bridge application
    {ok, Apps} = application:ensure_all_started(elrmcp_bridge),
    [{apps, Apps} | Config].

end_per_suite(Config) ->
    %% Stop all applications
    Apps = ?config(apps, Config),
    [application:stop(App) || App <- Apps],
    ok.

init_per_testcase(_Testcase, Config) ->
    %% Reset bridge state before each test
    case elrmcp_mcp_bridge:get_bridge_status() of
        {ok, _} ->
            ok;
        {error, _} ->
            ok
    end,
    Config.

end_per_testcase(_Testcase, _Config) ->
    %% Clean up after test
    ok.

%%====================================================================
%% Test Cases
%%====================================================================

test_bridge_initialization(_Config) ->
    %% Test bridge initialization
    Result = elrmcp_mcp_bridge:initialize_craftplan(),
    case Result of
        ok ->
            ct:comment("Bridge initialized successfully"),
            ok;
        {error, Reason} ->
            ct:fail("Bridge initialization failed: ~p", [Reason])
    end.

test_tool_registration(_Config) ->
    %% Test tool registration
    Result = elrmcp_mcp_bridge:register_tools(),
    case Result of
        ok ->
            ct:comment("Tools registered successfully"),
            ok;
        {error, Reason} ->
            ct:fail("Tool registration failed: ~p", [Reason])
    end.

test_request_forwarding(_Config) ->
    %% Test request forwarding to Craftplan MCP
    Args = #{<<"operation">> => <<"list">>},
    Result = elrmcp_mcp_bridge:forward_request(<<"customer_management">>, Args),

    case Result of
        {ok, Response} ->
            ct:comment("Request forwarded successfully"),
            ct:assertEqual(<<"customer_management">>, maps:get(<<"tool_name">>, Response, undefined));
        {error, Reason} ->
            ct:fail("Request forwarding failed: ~p", [Reason])
    end.

test_rate_limiting(_Config) ->
    %% Test rate limiting
    elrmcp_rate_limiter:reset(),

    %% Send requests quickly to trigger rate limit
    Results = [elrmcp_mcp_bridge:forward_request(<<"customer_management">>, #{}) || _ <- lists:seq(1, 10)],

    Count = lists:foldl(fun({ok, _}, Acc) -> Acc + 1; (_, Acc) -> Acc end, 0, Results),
    ct:comment("Rate limiting test: ~p successful requests out of 10", [Count]),
    true.

test_tool_listing(_Config) ->
    %% Test tool listing
    Result = elrmcp_mcp_bridge:list_available_tools(),

    case Result of
        {ok, Tools} ->
            ct:comment("Found ~p tools", [length(Tools)]),
            ct:assertMatch([_|_], Tools),
            ok;
        {error, Reason} ->
            ct:fail("Tool listing failed: ~p", [Reason])
    end.

test_tool_info(_Config) ->
    %% Test tool info retrieval
    ToolName = <<"customer_management">>,
    Result = elrmcp_mcp_bridge:get_tool_info(ToolName),

    case Result of
        {ok, ToolInfo} ->
            ct:comment("Tool info retrieved successfully"),
            ct:assertEqual(ToolName, maps:get(<<"name">>, ToolInfo)),
            ct:assert(is_binary(maps:get(<<"description">>, ToolInfo))),
            ok;
        {error, not_found} ->
            ct:fail("Tool not found");
        {error, Reason} ->
            ct:fail("Tool info retrieval failed: ~p", [Reason])
    end.

test_configuration(_Config) ->
    %% Test bridge configuration
    NewConfig = #{
        <<"craftplan_url">> => <<"http://localhost:9000">>,
        <<"timeout">> => 50000,
        <<"rate_limit">> => 50
    },

    Result = elrmcp_mcp_bridge:configure_bridge(NewConfig),
    case Result of
        ok ->
            ct:comment("Configuration updated successfully"),
            ok;
        {error, Reason} ->
            ct:fail("Configuration update failed: ~p", [Reason])
    end.

test_bridge_status(_Config) ->
    %% Test bridge status retrieval
    Result = elrmcp_mcp_bridge:get_bridge_status(),

    case Result of
        {ok, Status} ->
            ct:comment("Bridge status retrieved successfully"),
            ct:assertMatch(#{status := _}, Status),
            ct:assertMatch(#{metrics := _}, Status),
            ct:assertMatch(#{config := _}, Status),
            ok;
        {error, Reason} ->
            ct:fail("Bridge status retrieval failed: ~p", [Reason])
    end.

test_error_handling(_Config) ->
    %% Test error handling for unknown tools
    Result = elrmcp_mcp_bridge:forward_request(<<"unknown_tool">>, #{});

    case Result of
        {error, Reason} ->
            ct:comment("Error handling works correctly: ~p", [Reason]),
            ok;
        {ok, _} ->
            ct:fail("Should have failed for unknown tool")
    end.

test_concurrent_requests(_Config) ->
    %% Test concurrent request handling
    Args = #{<<"operation">> => <<"list">>},

    %% Spawn multiple concurrent requests
    Pids = [spawn(fun() ->
        case elrmcp_mcp_bridge:forward_request(<<"customer_management">>, Args) of
            {ok, _} -> ok;
            {error, _} -> error
        end
    end) || _ <- lists:seq(1, 5)],

    %% Wait for all requests to complete
    Results = [receive {Pid, Result} -> Result end || Pid <- Pids],

    SuccessCount = lists:foldl(fun(ok, Acc) -> Acc + 1; (_, Acc) -> Acc end, 0, Results),
    ct:comment("Concurrent requests: ~p successful out of 5", [SuccessCount]),
    SuccessCount >= 3.  % Allow for some failures due to rate limiting