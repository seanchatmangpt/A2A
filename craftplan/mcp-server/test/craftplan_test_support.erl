%% @doc Test support module for Craftplan MCP server
%% Provides common test utilities and mock data

-module(craftplan_test_support).

-export([
    create_mock_request/1,
    create_mock_response/1,
    create_test_tool/2,
    create_test_context/1,
    mock_api_response/2,
    mock_server_response/2,
    generate_test_id/0,
    setup_mock_environment/0,
    cleanup_mock_environment/0
]).

%% Mock data generation
create_mock_request(Method) ->
    create_mock_request(Method, #{}).

create_mock_request(Method, Params) ->
    #{
        jsonrpc => <<"2.0">>,
        id => generate_test_id(),
        method => Method,
        params => Params
    }.

create_mock_response(Id, Result) ->
    #{
        jsonrpc => <<"2.0">>,
        id => Id,
        result => Result
    }.

create_test_tool(Name, Description) ->
    #{
        name => list_to_binary(Name),
        description => list_to_binary(Description),
        inputSchema => #{
            type => <<"object">>,
            properties => #{
                target => #{
                    type => <<"string">>,
                    enum => [<<"dev">>, <<"prod">>]
                }
            },
            required => [<<"target">>]
        }
    }.

create_test_context(Extra) ->
    #{
        agent_id => <<"test-agent">>,
        session_id => generate_test_id(),
        timestamp => erlang:system_time(millisecond)
    } %% Extra ++ Extra.

%% Mock response generation
mock_api_response(success, Data) ->
    {ok, Data};
mock_api_response(error, Reason) ->
    {error, Reason};
mock_api_response(timeout, _) ->
    {error, timeout}.

mock_server_response(success, Data) ->
    {ok, Data};
mock_server_response(error, Reason) ->
    {error, Reason}.

%% Test ID generation
generate_test_id() ->
    integer_to_binary(erlang:system_time(millisecond)).

%% Mock environment setup
setup_mock_environment() ->
    % Mock external dependencies
    meck:new(craftplan_api_client, [passthrough]),
    meck:new(craftplan_a2a_bridge, [passthrough]),
    meck:new(gen_server, [passthrough]),
    meck:new(cowboy, [passthrough]),

    % Set up common mock behaviors
    meck:expect(craftplan_api_client, connect, fun() -> {ok, self()} end),
    meck:expect(gen_server, start_link, fun(module, _Args, _Options) -> {ok, self()} end),

    ok.

cleanup_mock_environment() ->
    meck:unload(),
    ok.