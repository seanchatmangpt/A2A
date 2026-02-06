%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Request Validator Middleware
%%%
%%% This module provides request validation middleware for the YAWL REST API.
%%% It validates JSON requests using jiffy, validates request schemas,
%%% checks required fields, and provides detailed error responses.
%%%
%%% ## Usage
%%%
%%% ```erlang
%%% %% In your Cowboy handler:
%%% init(Req, State) ->
%%%     case yawl_request_validator:validate_request(Req, workflow_create) of
%%%         {ok, ValidatedData, Req1} ->
%%%             {cowboy_rest, Req1, State#{data => ValidatedData}};
%%%         {error, ErrorResponse, Req1} ->
%%%             {ok, Req1, State#{error => ErrorResponse}}
%%%     end.
%%% ```
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_request_validator).
-author("A2A Team").

%% API exports
-export([
    validate_request/2,
    validate_request/3,
    validate_json_body/1,
    validate_json_body/2,
    validate_query_params/2,
    validate_headers/2,
    validate_binding/3,
    sanitize_input/1,
    sanitize_input/2,
    max_body_size/0,
    set_max_body_size/1
]).

%% Include files
-include("yawl_types.hrl").

%% Type definitions
-type cowboy_request() :: term().  %% Cowboy request is opaque type
-type request_validation_result() :: {ok, map(), cowboy_request()} |
                                    {error, yawl_error_response:error_response(), cowboy_request()}.
-type request_schema() :: workflow_create | workflow_update |
                          resource_create | resource_update |
                          task_create | task_complete |
                          service_register | service_update.

%% Process dictionary keys
-define(MAX_BODY_SIZE, '$yawl_max_body_size').
-define(DEFAULT_MAX_BODY_SIZE, 10485760). % 10MB

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Validate a request against a schema.
-spec validate_request(cowboy_request(), request_schema()) -> request_validation_result().
validate_request(Req, Schema) ->
    validate_request(Req, Schema, #{}).

%% @doc Validate a request against a schema with options.
-spec validate_request(cowboy_request(), request_schema(), map()) -> request_validation_result().
validate_request(Req, Schema, Options) ->
    %% Check content type first
    case validate_content_type(Req) of
        {error, ErrorResponse, Req1} ->
            {error, ErrorResponse, Req1};
        {ok, Req1} ->
            %% Read and validate body
            case validate_json_body(Req1, Options) of
                {error, ErrorResponse, Req2} ->
                    {error, ErrorResponse, Req2};
                {ok, BodyData, Req2} ->
                    %% Validate against schema
                    case yawl_validation_schema:validate(Schema, BodyData) of
                        {ok, ValidatedData} ->
                            {ok, ValidatedData, Req2};
                        {error, ValidationErrors} ->
                            ErrorResponse = yawl_error_response:format_validation_error(
                                BodyData, ValidationErrors
                            ),
                            {error, ErrorResponse, Req2}
                    end
            end
    end.

%% @doc Validate JSON request body.
-spec validate_json_body(cowboy_request()) -> request_validation_result().
validate_json_body(Req) ->
    validate_json_body(Req, #{}).

%% @doc Validate JSON request body with options.
-spec validate_json_body(cowboy_request(), map()) -> request_validation_result().
validate_json_body(Req, Options) ->
    %% Check body size
    case check_body_size(Req) of
        {error, ErrorResponse, Req1} ->
            {error, ErrorResponse, Req1};
        {ok, Req1} ->
            %% Read body
            {ok, Body, Req2} = cowboy_req:read_body(Req1),

            %% Check if body is empty
            case Body of
                <<>> ->
                    case maps:get(allow_empty, Options, false) of
                        true ->
                            {ok, #{}, Req2};
                        false ->
                            ErrorResponse = yawl_error_response:format_error(
                                missing_required_field,
                                #{field => <<"body">>}
                            ),
                            {error, ErrorResponse, Req2}
                    end;
                _ ->
                    %% Parse JSON
                    try
                        Data = jiffy:decode(Body, [return_maps]),
                        SanitizedData = case maps:get(sanitize, Options, true) of
                            true -> sanitize_input(Data);
                            false -> Data
                        end,
                        {ok, SanitizedData, Req2}
                    catch
                        throw:{error, _} ->
                            ErrorResponse = yawl_error_response:format_error(
                                invalid_json,
                                #{details => <<"Malformed JSON in request body">>}
                            ),
                            {error, ErrorResponse, Req2}
                    end
            end
    end.

%% @doc Validate query parameters.
-spec validate_query_params(cowboy_request(), atom()) ->
    {ok, map(), cowboy_request()} | {error, yawl_error_response:error_response(), cowboy_request()}.
validate_query_params(Req, SchemaName) ->
    QS = cowboy_req:qs(Req),
    Params = parse_query_params(QS),

    case yawl_validation_schema:validate({query_params, SchemaName}, Params) of
        {ok, ValidatedParams} ->
            {ok, ValidatedParams, Req};
        {error, ValidationErrors} ->
            ErrorResponse = yawl_error_response:format_error(
                invalid_field_value,
                #{errors => ValidationErrors, location => <<"query">>}
            ),
            {error, ErrorResponse, Req}
    end.

%% @doc Validate request headers.
-spec validate_headers(cowboy_request(), [{binary(), fun((binary()) -> boolean())}]) ->
    {ok, cowboy_request()} | {error, yawl_error_response:error_response(), cowboy_request()}.
validate_headers(Req, RequiredHeaders) ->
    validate_headers_loop(Req, RequiredHeaders, []).

%% @doc Validate a path binding.
-spec validate_binding(cowboy_request(), binary(), atom()) ->
    {ok, term(), cowboy_request()} | {error, yawl_error_response:error_response(), cowboy_request()}.
validate_binding(Req, BindingKey, ExpectedType) ->
    BindingValue = cowboy_req:binding(BindingKey, Req),
    case BindingValue of
        undefined ->
            ErrorResponse = yawl_error_response:format_error(
                missing_required_field,
                #{field => BindingKey, location => <<"path">>}
            ),
            {error, ErrorResponse, Req};
        Value when is_binary(Value) ->
            case convert_binding_type(Value, ExpectedType) of
                {ok, Converted} ->
                    {ok, Converted, Req};
                {error, _} ->
                    ErrorResponse = yawl_error_response:format_error(
                        invalid_field_type,
                        #{field => BindingKey,
                          expected_type => atom_to_binary(ExpectedType, utf8),
                          location => <<"path">>}
                    ),
                    {error, ErrorResponse, Req}
            end
    end.

%% @doc Sanitize input data to prevent injection attacks.
-spec sanitize_input(map()) -> map().
sanitize_input(Data) when is_map(Data) ->
    sanitize_input(Data, [strip_xss, trim_whitespace]).

%% @doc Sanitize input data with specified options.
-spec sanitize_input(map(), [atom()]) -> map().
sanitize_input(Data, Options) when is_map(Data) ->
    maps:map(fun(_Key, Value) ->
        sanitize_value(Value, Options)
    end, Data).

%% @doc Get the maximum allowed body size.
-spec max_body_size() -> pos_integer().
max_body_size() ->
    case get(?MAX_BODY_SIZE) of
        undefined -> ?DEFAULT_MAX_BODY_SIZE;
        Size when is_integer(Size) -> Size
    end.

%% @doc Set the maximum allowed body size.
-spec set_max_body_size(pos_integer()) -> ok.
set_max_body_size(Size) when is_integer(Size), Size > 0 ->
    put(?MAX_BODY_SIZE, Size),
    ok.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
%% @doc Validate content type header.
-spec validate_content_type(cowboy_request()) ->
    {ok, cowboy_request()} | {error, yawl_error_response:error_response(), cowboy_request()}.
validate_content_type(Req) ->
    case cowboy_req:header(<<"content-type">>, Req) of
        undefined ->
            %% Accept requests without content type for GET/HEAD
            Method = cowboy_req:method(Req),
            case Method of
                <<"GET">> -> {ok, Req};
                <<"HEAD">> -> {ok, Req};
                _ ->
                    ErrorResponse = yawl_error_response:format_error(
                        unsupported_media_type,
                        #{expected => <<"application/json">>}
                    ),
                    {error, ErrorResponse, Req}
            end;
        ContentType ->
            %% Extract MIME type (ignore charset and other parameters)
            [Mime | _] = binary:split(ContentType, <<";">>),
            NormalizedMime = string:trim(Mime),
            case NormalizedMime of
                <<"application/json">> -> {ok, Req};
                <<"application/vnd.api+json">> -> {ok, Req};
                _ ->
                    ErrorResponse = yawl_error_response:format_error(
                        unsupported_media_type,
                        #{received => NormalizedMime,
                          expected => <<"application/json">>}
                    ),
                    {error, ErrorResponse, Req}
            end
    end.

%% @private
%% @doc Check if request body size exceeds limit.
-spec check_body_size(cowboy_request()) ->
    {ok, cowboy_request()} | {error, yawl_error_response:error_response(), cowboy_request()}.
check_body_size(Req) ->
    case cowboy_req:header(<<"content-length">>, Req) of
        undefined ->
            %% Can't check size without content-length, will check during read
            {ok, Req};
        ContentLength ->
            case binary_to_integer(ContentLength) of
                Size when is_integer(Size) ->
                    MaxSize = max_body_size(),
                    case Size > MaxSize of
                        true ->
                            ErrorResponse = yawl_error_response:format_error(
                                request_too_large,
                                #{max_size => MaxSize, actual_size => Size}
                            ),
                            {error, ErrorResponse, Req};
                        false ->
                            {ok, Req}
                    end;
                _ ->
                    %% Invalid content-length header
                    ErrorResponse = yawl_error_response:format_error(
                        invalid_field_value,
                        #{field => <<"content-length">>}
                    ),
                    {error, ErrorResponse, Req}
            end
    end.

%% @private
%% @doc Parse query parameters into a map.
-spec parse_query_params(binary()) -> map().
parse_query_params(<<>>) ->
    #{};
parse_query_params(QS) ->
    Pairs = binary:split(QS, <<"&">>, [global]),
    lists:foldl(fun(Pair, Acc) ->
        case binary:split(Pair, <<"=">>) of
            [Key, Value] ->
                DecodedKey = uri_string:unquote(Key),
                DecodedValue = uri_string:unquote(Value),
                Acc#{DecodedKey => DecodedValue};
            [Key] ->
                DecodedKey = uri_string:unquote(Key),
                Acc#{DecodedKey => true}
        end
    end, #{}, Pairs).

%% @private
%% @doc Loop to validate required headers.
-spec validate_headers_loop(cowboy_request(), [{binary(), fun()}], [binary()]) ->
    {ok, cowboy_request()} | {error, yawl_error_response:error_response(), cowboy_request()}.
validate_headers_loop(Req, [], []) ->
    {ok, Req};
validate_headers_loop(Req, [], Missing) ->
    ErrorResponse = yawl_error_response:format_error(
        missing_required_field,
        #{fields => Missing, location => <<"headers">>}
    ),
    {error, ErrorResponse, Req};
validate_headers_loop(Req, [{HeaderName, ValidateFun} | Rest], Missing) ->
    HeaderValue = cowboy_req:header(HeaderName, Req),
    case HeaderValue of
        undefined ->
            validate_headers_loop(Req, Rest, [HeaderName | Missing]);
        Value ->
            case ValidateFun(Value) of
                true ->
                    validate_headers_loop(Req, Rest, Missing);
                false ->
                    ErrorResponse = yawl_error_response:format_error(
                        invalid_field_value,
                        #{field => HeaderName, location => <<"headers">>}
                    ),
                    {error, ErrorResponse, Req}
            end
    end.

%% @private
%% @doc Convert binding to expected type.
-spec convert_binding_type(binary(), atom()) -> {ok, term()} | {error, term()}.
convert_binding_type(Value, binary) ->
    {ok, Value};
convert_binding_type(Value, atom) ->
    try {ok, binary_to_existing_atom(Value, utf8)}
    catch error:badarg -> {error, invalid_atom}
    end;
convert_binding_type(Value, integer) ->
    try {ok, binary_to_integer(Value)}
    catch error:badarg -> {error, invalid_integer}
    end;
convert_binding_type(Value, float) ->
    try {ok, binary_to_float(Value)}
    catch error:badarg -> {error, invalid_float}
    end;
convert_binding_type(_Value, _Type) ->
    {error, unsupported_type}.

%% @private
%% @doc Sanitize a value based on options.
-spec sanitize_value(term(), [atom()]) -> term().
sanitize_value(Value, _Options) when is_number(Value) ->
    Value;
sanitize_value(Value, _Options) when is_boolean(Value) ->
    Value;
sanitize_value(Value, _Options) when is_atom(Value) ->
    Value;
sanitize_value(Value, Options) when is_binary(Value) ->
    Sanitized = lists:foldl(fun
        (strip_xss, Acc) -> strip_xss_patterns(Acc);
        (trim_whitespace, Acc) -> string:trim(Acc);
        (_, Acc) -> Acc
    end, Value, Options),
    Sanitized;
sanitize_value(List, Options) when is_list(List) ->
    [sanitize_value(Elem, Options) || Elem <- List];
sanitize_value(Map, Options) when is_map(Map) ->
    maps:map(fun(_K, V) -> sanitize_value(V, Options) end, Map);
sanitize_value(Value, _Options) ->
    Value.

%% @private
%% @doc Strip XSS patterns from binary.
-spec strip_xss_patterns(binary()) -> binary().
strip_xss_patterns(Input) ->
    %% Remove dangerous script tags and event handlers
    DangerousPatterns = [
        <<"<script">>,
        <<"</script">>,
        <<"javascript:">>,
        <<"onerror=">>,
        <<"onload=">>,
        <<"onclick=">>,
        <<"onmouseover=">>
    ],
    lists:foldl(fun(Pattern, Acc) ->
        re:replace(Acc, Pattern, <<"">>, [global, {return, binary}, caseless])
    end, Input, DangerousPatterns).
