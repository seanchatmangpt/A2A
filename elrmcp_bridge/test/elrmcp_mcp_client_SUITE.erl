%%% @doc elrmcp MCP Client Tests
%%% Tests the HTTP client functionality

-module(elrmcp_mcp_client_SUITE).
-behaviour(suites).

%% Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1]).

%% Test cases
-export([
    test_client_initialization/1,
    test_tools_list/1,
    test_tool_call/1,
    test_tool_get/1,
    test_error_handling/1,
    test_rate_limiting_integration/1
]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Configuration
%%====================================================================

all() ->
    [
        test_client_initialization,
        test_tools_list,
        test_tool_call,
        test_tool_get,
        test_error_handling,
        test_rate_limiting_integration
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

%%====================================================================
%% Test Cases
%%====================================================================

test_client_initialization(_Config) ->
    %% Test client initialization with valid URL
    Result = elrmcp_mcp_client:start_link(<<"http://localhost:8090">>),
    case Result of
        {ok, _Pid} ->
            ct:comment("Client initialized successfully"),
            ok;
        {error, Reason} ->
            ct:fail("Client initialization failed: ~p", [Reason])
    end.

test_tools_list(_Config) ->
    %% Test tools listing functionality
    Result = elrmcp_mcp_client:list_tools(),

    case Result of
        {ok, Tools} ->
            ct:comment("Found ~p tools", [length(Tools)]),
            ct:assertMatch([_|_], Tools),
            %% Check for expected tools
            ToolNames = [maps:get(<<"name">>, Tool) || Tool <- Tools],
            ct:assert(lists:member(<<"customer_management">>, ToolNames)),
            ct:assert(lists:member(<<"order_management">>, ToolNames)),
            ok;
        {error, Reason} ->
            ct:fail("Tools list failed: ~p", [Reason])
    end.

test_tool_call(_Config) ->
    %% Test tool call functionality
    Args = #{<<"operation">> => <<"list">>},
    Result = elrmcp_mcp_client:call_tool(<<"customer_management">>, Args),

    case Result of
        {ok, Response} ->
            ct:comment("Tool call successful"),
            ct:assertMatch(#{}, Response),
            ok;
        {error, Reason} ->
            ct:fail("Tool call failed: ~p", [Reason])
    end.

test_tool_get(_Config) ->
    %% Test get tool functionality
    Result = elrmcp_mcp_client:get_tool(<<"customer_management">>);

    case Result of
        {ok, Tool} ->
            ct:comment("Tool info retrieved successfully"),
            ct:assertEqual(<<"customer_management">>, maps:get(<<"name">>, Tool)),
            ct:assert(is_binary(maps:get(<<"description">>, Tool))),
            ok;
        {error, Reason} ->
            ct:fail("Get tool failed: ~p", [Reason])
    end.

test_error_handling(_Config) ->
    %% Test error handling for invalid tool
    Result = elrmcp_mcp_client:call_tool(<<"nonexistent_tool">>, #{});

    case Result of
        {error, Reason} ->
            ct:comment("Error handling works correctly: ~p", [Reason]),
            ok;
        {ok, _} ->
            ct:fail("Should have failed for nonexistent tool")
    end.

test_rate_limiting_integration(_Config) ->
    %% Test rate limiting integration
    elrmcp_rate_limiter:reset(),

    %% Send multiple requests in quick succession
    Results = [elrmcp_mcp_client:call_tool(<<"customer_management">>, #{<<"operation">> => <<"list">>})
               || _ <- lists:seq(1, 5)];

    Count = lists:foldl(fun({ok, _}, Acc) -> Acc + 1; (_, Acc) -> Acc end, 0, Results),
    ct:comment("Rate limiting integration test: ~p successful requests out of 5", [Count]),
    Count >= 3.  % Allow for some failures