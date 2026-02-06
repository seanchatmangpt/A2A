%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A JSON-RPC 2.0 Protocol Implementation
%%%
%%% Implements the JSON-RPC 2.0 specification for the A2A protocol,
%%% including request parsing (single and batch), structural
%%% validation, and response/error construction.
%%%
%%% Standard error codes:
%%%   -32700  Parse error
%%%   -32600  Invalid request
%%%   -32601  Method not found
%%%   -32602  Invalid params
%%%   -32603  Internal error
%%%
%%% A2A-specific error codes:
%%%   -32001  Task not found
%%%   -32002  Task not cancelable (already terminal)
%%%   -32003  Unsupported operation
%%%   -32004  Authentication required
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_jsonrpc).

%% API
-export([
    decode/1,
    encode_result/2,
    encode_error/3,
    encode_error/4,
    validate/1,
    batch/1
]).

%% Error helpers
-export([
    parse_error/0,
    parse_error/1,
    invalid_request/0,
    invalid_request/1,
    method_not_found/0,
    method_not_found/1,
    invalid_params/0,
    invalid_params/1,
    internal_error/0,
    internal_error/1,
    task_not_found/0,
    task_not_found/1,
    task_not_cancelable/0,
    unsupported_operation/0,
    auth_required/0
]).

%% Standard JSON-RPC error codes
-define(PARSE_ERROR,      -32700).
-define(INVALID_REQUEST,  -32600).
-define(METHOD_NOT_FOUND, -32601).
-define(INVALID_PARAMS,   -32602).
-define(INTERNAL_ERROR,   -32603).

%% A2A-specific error codes
-define(TASK_NOT_FOUND,        -32001).
-define(TASK_NOT_CANCELABLE,   -32002).
-define(UNSUPPORTED_OPERATION, -32003).
-define(AUTH_REQUIRED,         -32004).

%%====================================================================
%% Core API
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Decode a JSON-RPC request from a binary payload.
%%
%% Returns `{ok, Request}' for a single request, `{batch, Requests}'
%% for a batch (JSON array), or `{error, ErrorMap}' on parse failure.
%%
%% Each successfully decoded request is returned as a map with keys:
%%   jsonrpc, method, params, id
%% @end
%%--------------------------------------------------------------------
-spec decode(binary()) ->
    {ok, map()} | {batch, [map() | {error, map()}]} | {error, map()}.
decode(Json) when is_binary(Json) ->
    try json:decode(Json) of
        List when is_list(List) ->
            %% Batch request
            Decoded = [decode_single(Item) || Item <- List],
            {batch, Decoded};
        Map when is_map(Map) ->
            decode_single(Map);
        _Other ->
            {error, make_error_obj(?INVALID_REQUEST, <<"Invalid Request">>)}
    catch
        _:_ ->
            {error, make_error_obj(?PARSE_ERROR, <<"Parse error">>)}
    end;
decode(_) ->
    {error, make_error_obj(?PARSE_ERROR, <<"Parse error">>)}.

%%--------------------------------------------------------------------
%% @doc Encode a successful JSON-RPC result response as a binary.
%%
%% `Id' is the request id (binary, integer, or null).
%% `Result' is the result value (any JSON-encodable term).
%% @end
%%--------------------------------------------------------------------
-spec encode_result(term(), term()) -> binary().
encode_result(Id, Result) ->
    iolist_to_binary(json:encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"result">> => Result,
        <<"id">> => Id
    })).

%%--------------------------------------------------------------------
%% @doc Encode a JSON-RPC error response as a binary.
%%
%% `Id' may be null for responses to unparseable requests.
%% @end
%%--------------------------------------------------------------------
-spec encode_error(term(), integer(), binary()) -> binary().
encode_error(Id, Code, Message) ->
    encode_error(Id, Code, Message, undefined).

%%--------------------------------------------------------------------
%% @doc Encode a JSON-RPC error response with optional data field.
%% @end
%%--------------------------------------------------------------------
-spec encode_error(term(), integer(), binary(), term()) -> binary().
encode_error(Id, Code, Message, Data) ->
    ErrorObj = make_error_obj(Code, Message, Data),
    iolist_to_binary(json:encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"error">> => ErrorObj,
        <<"id">> => Id
    })).

%%--------------------------------------------------------------------
%% @doc Validate the structural correctness of a decoded JSON-RPC
%% request map.
%%
%% Checks:
%%   - `jsonrpc' is `<<"2.0">>'
%%   - `method' is a non-empty binary
%%   - `params', if present, is a map or list
%%   - `id', if present, is a binary, integer, or null
%%
%% Returns `ok' or `{error, Reason}'.
%% @end
%%--------------------------------------------------------------------
-spec validate(map()) -> ok | {error, binary()}.
validate(#{<<"jsonrpc">> := Version}) when Version =/= <<"2.0">> ->
    {error, <<"Invalid jsonrpc version">>};
validate(#{<<"method">> := Method}) when not is_binary(Method);
                                         byte_size(Method) =:= 0 ->
    {error, <<"Method must be a non-empty string">>};
validate(#{<<"params">> := Params})
  when not is_map(Params), not is_list(Params) ->
    {error, <<"Params must be an object or array">>};
validate(#{<<"id">> := Id})
  when not is_binary(Id), not is_integer(Id), Id =/= null ->
    {error, <<"Id must be a string, number, or null">>};
validate(#{<<"method">> := _}) ->
    ok;
validate(_) ->
    {error, <<"Missing required field: method">>}.

%%--------------------------------------------------------------------
%% @doc Encode a batch of JSON-RPC responses as a single JSON array.
%%
%% `Responses' is a list of already-encoded binaries. Notifications
%% (requests without id) should not produce a response; pass an empty
%% list to get `<<"[]">>' back.
%% @end
%%--------------------------------------------------------------------
-spec batch([binary()]) -> binary().
batch([]) ->
    <<"[]">>;
batch(Responses) when is_list(Responses) ->
    %% Each element is an already-encoded JSON binary; wrap in array
    Inner = lists:join(<<",">>, Responses),
    iolist_to_binary([<<"[">>, Inner, <<"]">>]).

%%====================================================================
%% Convenience error constructors
%%====================================================================

%% @doc Parse error: invalid JSON.
-spec parse_error() -> map().
parse_error() ->
    make_error_obj(?PARSE_ERROR, <<"Parse error">>).

-spec parse_error(term()) -> map().
parse_error(Data) ->
    make_error_obj(?PARSE_ERROR, <<"Parse error">>, Data).

%% @doc Invalid request: not a valid JSON-RPC request object.
-spec invalid_request() -> map().
invalid_request() ->
    make_error_obj(?INVALID_REQUEST, <<"Invalid Request">>).

-spec invalid_request(term()) -> map().
invalid_request(Data) ->
    make_error_obj(?INVALID_REQUEST, <<"Invalid Request">>, Data).

%% @doc Method not found.
-spec method_not_found() -> map().
method_not_found() ->
    make_error_obj(?METHOD_NOT_FOUND, <<"Method not found">>).

-spec method_not_found(binary()) -> map().
method_not_found(Method) ->
    make_error_obj(?METHOD_NOT_FOUND,
                   <<"Method not found: ", Method/binary>>).

%% @doc Invalid params.
-spec invalid_params() -> map().
invalid_params() ->
    make_error_obj(?INVALID_PARAMS, <<"Invalid params">>).

-spec invalid_params(term()) -> map().
invalid_params(Data) ->
    make_error_obj(?INVALID_PARAMS, <<"Invalid params">>, Data).

%% @doc Internal error.
-spec internal_error() -> map().
internal_error() ->
    make_error_obj(?INTERNAL_ERROR, <<"Internal error">>).

-spec internal_error(term()) -> map().
internal_error(Data) ->
    make_error_obj(?INTERNAL_ERROR, <<"Internal error">>, Data).

%% @doc A2A: Task not found.
-spec task_not_found() -> map().
task_not_found() ->
    make_error_obj(?TASK_NOT_FOUND, <<"Task not found">>).

-spec task_not_found(binary()) -> map().
task_not_found(TaskId) ->
    make_error_obj(?TASK_NOT_FOUND,
                   <<"Task not found: ", TaskId/binary>>).

%% @doc A2A: Task already in terminal state.
-spec task_not_cancelable() -> map().
task_not_cancelable() ->
    make_error_obj(?TASK_NOT_CANCELABLE,
                   <<"Task already in terminal state">>).

%% @doc A2A: Operation not supported.
-spec unsupported_operation() -> map().
unsupported_operation() ->
    make_error_obj(?UNSUPPORTED_OPERATION,
                   <<"Unsupported operation">>).

%% @doc A2A: Authentication required.
-spec auth_required() -> map().
auth_required() ->
    make_error_obj(?AUTH_REQUIRED, <<"Authentication required">>).

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Decode a single JSON-RPC request from a parsed JSON map.
-spec decode_single(map()) -> {ok, map()} | {error, map()}.
decode_single(Map) when is_map(Map) ->
    Request = #{
        <<"jsonrpc">> => maps:get(<<"jsonrpc">>, Map, <<"2.0">>),
        <<"method">>  => maps:get(<<"method">>, Map, undefined),
        <<"params">>  => maps:get(<<"params">>, Map, #{}),
        <<"id">>      => maps:get(<<"id">>, Map, undefined)
    },
    case validate(Request) of
        ok    -> {ok, Request};
        Error -> Error
    end;
decode_single(_) ->
    {error, make_error_obj(?INVALID_REQUEST, <<"Invalid Request">>)}.

%% @doc Construct a JSON-RPC error object map.
-spec make_error_obj(integer(), binary()) -> map().
make_error_obj(Code, Message) ->
    #{<<"code">> => Code, <<"message">> => Message}.

-spec make_error_obj(integer(), binary(), term()) -> map().
make_error_obj(Code, Message, undefined) ->
    make_error_obj(Code, Message);
make_error_obj(Code, Message, Data) ->
    #{<<"code">> => Code, <<"message">> => Message, <<"data">> => Data}.
