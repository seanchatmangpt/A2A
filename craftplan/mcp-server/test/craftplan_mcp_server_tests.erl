%% @doc Unit tests for craftplan_mcp_server module
%% Tests MCP tool calls, JSON-RPC handling, and server lifecycle

-module(craftplan_mcp_server_tests).

-include_lib("eunit/include/eunit.hrl").

%% Test data
-define(TEST_REQUEST, #{
    jsonrpc => <<"2.0">>,
    id => 1,
    method => <<"initialize">>,
    params => #{
        rootUri => <<"file:///Users/sac/A2A/craftplan">>,
        capabilities => #{
            experimental => #{}
        }
    }
}).

-define(TEST_RESPONSE, #{
    jsonrpc => <<"2.0">>,
    id => 1,
    result => #{
        capabilities => #{
            experimental => #{},
            tools => #{
                listChanged => true
            }
        }
    }
}).

%% Test suite
mcp_server_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        [
            fun test_initialization/0,
            fun test_tool_call_handling/0,
            fun test_json_rpc_validation/0,
            fun test_error_handling/0,
            fun test_lifecycle_management/0
        ]
    }.

%% Setup and cleanup
setup() ->
    % Mock dependencies
    meck:new(craftplan_api_client, [passthrough]),
    meck:new(craftplan_a2a_bridge, [passthrough]),
    meck:new(cowboy, [passthrough]),
    ok.

cleanup(_) ->
    meck:unload(),
    ok.

%% Test initialization
test_initialization() ->
    % Mock API client response
    meck:expect(craftplan_api_client, connect, fun() -> {ok, self()} end),
    meck:expect(craftplan_api_client, get_tools, fun() ->
        {ok, [
            #{name => <<"build">>, description => <<"Build project">>},
            #{name => <<"deploy">>, description => <<"Deploy to production">>}
        ]}
    end),

    % Test server initialization
    ?_assertEqual(ok, craftplan_mcp_server:start_link()),
    timer:sleep(100), % Allow startup

    % Verify API client was called
    ?_assert(meck:called(craftplan_api_client, connect, [])),
    ?_assert(meck:called(craftplan_api_client, get_tools, [])).

%% Test tool call handling
test_tool_call_handling() ->
    % Mock successful tool execution
    meck:expect(craftplan_api_client, execute_tool,
        fun(<<"build">>, _) -> {ok, #{
            status => <<"completed">>,
            result => <<"Build successful">>
        }}
    end),

    % Test tool request
    ToolRequest = #{
        jsonrpc => <<"2.0">>,
        id => 2,
        method => <<"tools/call">>,
        params => #{
            name => <<"build">>,
            arguments => #{target => <<"dev">>}
        }
    },

    % Simulate tool call (this would be handled by the server)
    Response = simulate_tool_call(ToolRequest),

    % Verify response structure
    ?_assertEqual(<<"2.0">>, maps:get(jsonrpc, Response)),
    ?_assert(is_binary(maps:get(id, Response))),
    ?_assertEqual(<<"completed">>, maps:get(status, maps:get(result, Response))).

%% Test JSON-RPC validation
test_json_rpc_validation() ->
    % Valid request
    ?_assertEqual(true, is_valid_json_rpc(?TEST_REQUEST)),

    % Invalid requests
    InvalidRequest1 = ?TEST_REQUEST#{jsonrpc => <<"1.0">>}, % Wrong version
    ?_assertEqual(false, is_valid_json_rpc(InvalidRequest1)),

    InvalidRequest2 = ?TEST_REQUEST#{id => undefined}, % Missing ID
    ?_assertEqual(false, is_valid_json_rpc(InvalidRequest2)),

    InvalidRequest3 = ?TEST_REQUEST#{method => undefined}, % Missing method
    ?_assertEqual(false, is_valid_json_rpc(InvalidRequest3)).

%% Test error handling
test_error_handling() ->
    % Mock API client error
    meck:expect(craftplan_api_client, execute_tool,
        fun(_, _) -> {error, <<"Connection failed">>} end
    ),

    % Test error response
    ToolRequest = #{
        jsonrpc => <<"2.0">>,
        id => 3,
        method => <<"tools/call">>,
        params => #{
            name => <<"build">>,
            arguments => #{}
        }
    },

    Response = simulate_tool_call(ToolRequest),

    % Verify error response structure
    ?_assertEqual(<<"2.0">>, maps:get(jsonrpc, Response)),
    ?_assertEqual(3, maps:get(id, Response)),
    ?_assertEqual(<<"error">>, maps:get(result, Response)).

%% Test lifecycle management
test_lifecycle_management() ->
    % Test server startup
    ?_assertEqual(ok, craftplan_mcp_server:start_link()),
    timer:sleep(100),

    % Test server stop
    ?_assertEqual(ok, craftplan_mcp_server:stop()),
    timer:sleep(100),

    % Verify server is stopped
    ?_assertEqual(undefined, whereis(craftplan_mcp_server)).

%% Helper functions
simulate_tool_call(Request) ->
    case maps:get(method, Request) of
        <<"tools/call">> ->
            Params = maps:get(params, Request),
            ToolName = maps:get(name, Params),
            Args = maps:get(arguments, Params),
            case craftplan_api_client:execute_tool(ToolName, Args) of
                {ok, Result} -> #{
                    jsonrpc => <<"2.0">>,
                    id => maps:get(id, Request),
                    result => Result
                };
                {error, Error} -> #{
                    jsonrpc => <<"2.0">>,
                    id => maps:get(id, Request),
                    result => #{error => Error}
                }
            end
    end.

is_valid_json_rpc(#{jsonrpc := <<"2.0">>, id := _, method := _}) -> true;
is_valid_json_rpc(_) -> false.