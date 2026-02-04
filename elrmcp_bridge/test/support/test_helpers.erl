%%% @doc Test Helpers for elrmcp Bridge
%%% Common utilities and helpers for testing the bridge

-module(test_helpers).

%% API
-export([
    start_mock_craftplan_server/0,
    stop_mock_craftplan_server/0,
    create_test_request/3,
    validate_response/2,
    wait_for_condition/3,
    generate_test_data/1
]).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start mock Craftplan server for testing
start_mock_craftplan_server() ->
    %% This would start a mock HTTP server simulating Craftplan MCP
    %% For now, return mock data structure
    #{port => 8090, pid => undefined}.

%% @doc Stop mock Craftplan server
stop_mock_craftplan_server() ->
    %% Stop the mock server
    ok.

%% @doc Create test request
create_test_request(Method, Params, Id) ->
    #{
        jsonrpc => <<"2.0">>,
        method => Method,
        params => Params,
        id => Id
    }.

%% @doc Validate response format
validate_response(Response, ExpectedType) ->
    case Response of
        {ok, Data} when ExpectedType =:= success ->
            validate_success_response(Data);
        {error, Error} when ExpectedType =:= error ->
            validate_error_response(Error);
        _ ->
            false
    end.

%% @doc Wait for condition to be met
wait_for_condition(Fun, Timeout, Interval) ->
    wait_for_condition(Fun, Timeout, Interval, 0).

%% @doc Generate test data
generate_test_data(ToolName) ->
    case ToolName of
        <<"customer_management">> ->
            #{
                <<"customer">> => #{
                    <<"id">> => <<"cust_123">>,
                    <<"name">> => <<"Test Customer">>,
                    <<"email">> => <<"test@example.com">>
                }
            };
        <<"order_management">> ->
            #{
                <<"order">> => #{
                    <<"id">> => <<"ord_456">>,
                    <<"status">> => <<"pending">>,
                    <<"total">> => 100.0
                }
            };
        _ ->
            #{<<"result">> => <<"test_data">>}
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

wait_for_condition(Fun, _Timeout, _Interval, Attempts) when Attempts > 100 ->
    false;
wait_for_condition(Fun, Timeout, Interval, Attempts) ->
    case Fun() of
        true ->
            true;
        false when Timeout > 0 ->
            timer:sleep(Interval),
            wait_for_condition(Fun, Timeout - Interval, Interval, Attempts + 1);
        false ->
            false
    end.

validate_success_response(Response) ->
    is_map(Response) andalso
    maps:is_key(<<"result">>, Response).

validate_error_response(Error) ->
    is_map(Error) andalso
    maps:is_key(<<"code">>, Error) andalso
    maps:is_key(<<"message">>, Error).