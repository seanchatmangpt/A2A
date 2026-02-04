%%% @doc elrmcp Bridge Utilities
%%% Helper functions for bridge operations

-module(elrmcp_bridge_utils).

%% API
-export([validate_tool_name/1, sanitize_arguments/1, format_error/1]).
-export([generate_tool_id/0, parse_json_rpc/1, build_json_rpc/3]).

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Validate tool name format
-spec validate_tool_name(binary()) -> boolean().
validate_tool_name(ToolName) when is_binary(ToolName) ->
    %% Tool names should be alphanumeric with underscores
    case binary:match(ToolName, <<"[^a-zA-Z0-9_]">>, [unicode]) of
        nomatch -> true;
        _ -> false
    end;
validate_tool_name(_) ->
    false.

%% @doc Sanitize tool arguments
-spec sanitize_arguments(map()) -> map().
sanitize_arguments(Args) when is_map(Args) ->
    Sanitized = maps:fold(fun(K, V, Acc) ->
        case is_safe_value(V) of
            true ->
                maps:put(K, V, Acc);
            false ->
                Acc
        end
    end, #{}, Args),

    %% Remove empty nested maps
    remove_empty_maps(Sanitized).

%% @doc Format error messages
-spec format_error(term()) -> binary().
format_error({tool_not_found, ToolName}) ->
    iolist_to_binary([<<"Tool not found: ">>, ToolName]);
format_error({invalid_arguments, Reason}) ->
    iolist_to_binary([<<"Invalid arguments: ">>, format_term(Reason)]);
format_error({network_error, Reason}) ->
    iolist_to_binary([<<"Network error: ">>, format_term(Reason)]);
format_error({rate_limited}) ->
    <<"Rate limit exceeded">>;
format_error({mcp_error, Error}) when is_map(Error) ->
    case maps:get(<<"message">>, Error, undefined) of
        undefined ->
            iolist_to_binary([<<"MCP error: ">>, format_term(Error)]);
        Message ->
            iolist_to_binary([<<"MCP error: ">>, Message])
    end;
format_error(Reason) ->
    iolist_to_binary([<<"Error: ">>, format_term(Reason)]).

%% @doc Generate unique tool ID
-spec generate_tool_id() -> binary().
generate_tool_id() ->
    TS = integer_to_binary(erlang:system_time(millisecond)),
    UUID = uuid:uuid_to_string(uuid:uuid4()),
    <<TS/binary, "_", UUID/binary>>.

%% @doc Parse JSON-RPC request
-spec parse_json_rpc(binary() | map()) -> {ok, map()} | {error, term()}.
parse_json_rpc(Request) when is_binary(Request) ->
    try
        Decoded = jiffy:decode(Request, [return_maps]),
        {ok, Decoded}
    catch
        Error:Reason ->
            {error, {json_decode_error, {Error, Reason}}}
    end;
parse_json_rpc(Request) when is_map(Request) ->
    {ok, Request};
parse_json_rpc(_) ->
    {error, invalid_request_format}.

%% @doc Build JSON-RPC request
-spec build_json_rpc(binary(), binary(), map()) -> map().
build_json_rpc(Method, Params, Id) ->
    #{
        jsonrpc => <<"2.0">>,
        method => Method,
        params => Params,
        id => Id
    }.

%%====================================================================
%% Internal Functions
%%================================================================%%

%% @doc Check if value is safe to include in request
is_safe_value(Value) when is_binary(Value) ->
    size(Value) =< 65536;  % 64KB limit
is_safe_value(Value) when is_integer(Value) ->
    abs(Value) =< 1000000;  % ±1M limit
is_safe_value(Value) when is_boolean(Value) ->
    true;
is_safe_value(Value) when Value =:= null ->
    true;
is_safe_value(Value) when is_list(Value) ->
    case length(Value) of
        N when N > 1000 ->
            false;
        _ ->
            lists:all(fun(V) -> is_safe_value(V) end, Value)
    end;
is_safe_value(Value) when is_map(Value) ->
    case maps:size(Value) of
        N when N > 100 ->
            false;
        _ ->
            maps:fold(fun(_K, V, Acc) -> Acc and is_safe_value(V) end, true, Value)
    end;
is_safe_value(_) ->
    false.

%% @doc remove empty nested maps
remove_empty_maps(Map) when is_map(Map) ->
    maps:fold(fun(K, V, Acc) ->
        case V of
            V when is_map(V) ->
                CleanV = remove_empty_maps(V),
                case maps:size(CleanV) of
                    0 -> Acc;
                    _ -> maps:put(K, CleanV, Acc)
                end;
            _ ->
                maps:put(K, V, Acc)
        end
    end, #{}, Map).

%% @doc Format term for error messages
format_term(Term) ->
    case io_lib:format("~p", [Term]) of
        "[]" -> <<"[]">>;
        "{}" -> <<"{}">>;
        [_, $_ | _] = List when is_list(List) ->
            try
                list_to_binary(List)
            catch
                _ -> iolist_to_binary(io_lib:format("~p", [Term]))
            end;
        _ ->
            iolist_to_binary(io_lib:format("~p", [Term]))
    end.

%%====================================================================
%% Unit Tests
%%====================================================================

-ifdef(TEST).
validate_tool_name_test() ->
    ?assert(validate_tool_name(<<"customer_management">>)),
    ?assert(validate_tool_name(<<"customer_management_123">>)),
    ?assert(validate_tool_name(<<"test_tool">>)),
    ?assertNot(validate_tool_name(<<"customer-management">>)),
    ?assertNot(validate_tool_name(<<"customer management">>)),
    ?assertNot(validate_tool_name(123)),
    ok.

sanitize_arguments_test() ->
    Args = #{
        <<"customer_id">> => <<"123">>,
        <<"customer_data">> => #{<<"name">> => <<"Test">>},
        <<"binary_data">> => <<"very_long_binary_data_that_exceeds_limit">>,
        <<"large_list">> => lists:duplicate(1001, <<"item">>)
    },

    Sanitized = sanitize_arguments(Args),
    ?assert(maps:is_key(<<"customer_id">>, Sanitized)),
    ?assert(maps:is_key(<<"customer_data">>, Sanitized)),
    ?assertNot(maps:is_key(<<"binary_data">>, Sanitized)),
    ?assertNot(maps:is_key(<<"large_list">>, Sanitized)),
    ok.

format_error_test() ->
    ?assertEqual(<<"Tool not found: test">>, format_error({tool_not_found, <<"test">>})),
    ?assertEqual(<<"Invalid arguments: bad_arg">>, format_error({invalid_arguments, bad_arg})),
    ?assertEqual(<<"Network error: timeout">>, format_error({network_error, timeout})),
    ?assertEqual(<<"Rate limit exceeded">>, format_error({rate_limited})),
    ok.

generate_tool_id_test() ->
    Id1 = generate_tool_id(),
    Id2 = generate_tool_id(),
    ?assertNotEqual(Id1, Id2),
    ?assert(is_binary(Id1)),
    ?assert(is_binary(Id2)),
    ok.

parse_json_rpc_test() ->
    Json = <<"{\"jsonrpc\": \"2.0\", \"method\": \"tools/list\", \"id\": \"123\"}">>,
    ?assertEqual({ok, #{jsonrpc := <<"2.0">>, method := <<"tools/list">>, id := <<"123">>}}, parse_json_rpc(Json)),

    ValidMap = #{jsonrpc => <<"2.0">>, method => <<"tools/list">>},
    ?assertEqual({ok, ValidMap}, parse_json_rpc(ValidMap)),

    ?assertEqual({error, invalid_request_format}, parse_json_rpc(123)),
    ok.

build_json_rpc_test() ->
    Result = build_json_rpc(<<"tools/list">>, #{}, <<"123">>),
    Expected = #{
        jsonrpc => <<"2.0">>,
        method => <<"tools/list">>,
        params => #{},
        id => <<"123">>
    },
    ?assertEqual(Expected, Result),
    ok.
-endif.