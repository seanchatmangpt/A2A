%% @doc Test support module for Craftplan A2A agent
%% Provides common test utilities and mock data

-module(craftplan_test_support).

-export([
    create_mock_task/1,
    create_mock_context/1,
    create_mock_result/2,
    mock_agent_response/2,
    mock_task_handler/2,
    generate_test_id/0,
    setup_mock_environment/0,
    cleanup_mock_environment/0
]).

%% Mock data generation
create_mock_task(Type) ->
    create_mock_task(Type, #{}).

create_mock_task(Type, ExtraParams) ->
    BaseParams = #{
        id => generate_test_id(),
        type => list_to_binary(Type),
        parameters => #{target => <<"dev">>},
        priority => <<"high">>,
        timeout => 300000
    },
    maps:merge(BaseParams, ExtraParams).

create_mock_context(Extra) ->
    #{
        agent_id => <<"craftplan-a2a">>,
        session_id => generate_test_id(),
        user_id => <<"test-user">>,
        timestamp => erlang:system_time(millisecond)
    } %% ++ Extra.

create_mock_result(Status, Data) ->
    #{
        id => generate_test_id(),
        status => list_to_binary(Status),
        result => Data,
        timestamp => erlang:system_time(millisecond)
    }.

%% Mock response generation
mock_agent_response(success, Data) ->
    {ok, Data};
mock_agent_response(error, Reason) ->
    {error, Reason};
mock_agent_response(not_found, _) ->
    {error, not_found}.

mock_task_handler(success, Task) ->
    {ok, Task#{status => <<"completed">>}};
mock_task_handler(error, Reason) ->
    {error, Reason}.

%% Test ID generation
generate_test_id() ->
    integer_to_binary(erlang:system_time(millisecond)).

%% Mock environment setup
setup_mock_environment() ->
    % Mock external dependencies
    meck:new(a2a_handler, [passthrough]),
    meck:new(craftplan_agent_card, [passthrough]),
    meck:new(gen_server, [passthrough]),
    meck:new(timer, [passthrough]),

    % Set up common mock behaviors
    meck:expect(a2a_handler, connect, fun(Uri) -> {ok, self()} end),
    meck:expect(gen_server, start_link, fun(module, _Args, _Options) -> {ok, self()} end),
    meck:expect(timer, send_after, fun(_Delay, Pid, Message) -> Pid ! Message, ok end),

    ok.

cleanup_mock_environment() ->
    meck:unload(),
    ok.