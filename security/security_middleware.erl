%%% @doc Security Middleware
%%% Handles input validation, XSS prevention, CSRF protection, and other security measures

-module(security_middleware).
-export([validate_input/1, sanitize_input/1, prevent_xss/1, validate_csrf/2, add_security_headers/1]).

-include_lib("cowboy/include/cowboy_req.hrl").

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Validate input data
-spec validate_input(map()) -> ok | {error, term()}.
validate_input(Data) ->
    try
        %% Check for required fields
        validate_required_fields(Data),

        %% Validate field types
        validate_field_types(Data),

        %% Check for suspicious patterns
        validate_suspicious_patterns(Data),

        ok
    catch
        Error:Reason ->
            {error, {Error, Reason}}
    end.

%% @doc Sanitize input data
-spec sanitize_input(map()) -> map().
sanitize_input(Data) ->
    Sanitized = maps:map(fun(_Key, Value) ->
        sanitize_value(Value)
    end, Data),
    Sanitized.

%% @doc Prevent XSS attacks
-spec prevent_xss(binary() | map()) -> binary() | map().
prevent_xss(Text) when is_binary(Text) ->
    EscapeMap = #{
        $< => <<"&lt;">>,
        $> => <<"&gt;">>,
        $& => <<"&amp;">>,
        $" => <<"&quot;">>,
        $' => <<"&#39;">>
    },
    escape_text(Text, EscapeMap);
prevent_xss(Map) when is_map(Map) ->
    maps:map(fun(_Key, Value) ->
        prevent_xss(Value)
    end, Map);
prevent_xss(List) when is_list(List) ->
    lists:map(fun prevent_xss/1, List).

%% @doc Validate CSRF token
-spec validate_csrf(cowboy_req:req(), binary()) -> boolean().
validate_csrf(Req, Token) ->
    %% Get session CSRF token from cookie
    case cowboy_req:cookie(<<"csrf_token">>, Req) of
        undefined ->
            false;
        SessionToken ->
            %% Constant time comparison to prevent timing attacks
            constant_time_compare(Token, SessionToken)
    end.

%% @doc Add security headers to response
-spec add_security_headers(cowboy_req:req()) -> cowboy_req:req().
add_security_headers(Req) ->
    Headers = #{
        <<"strict-transport-security">> => <<"max-age=31536000; includeSubDomains; preload">>,
        <<"x-content-type-options">> => <<"nosniff">>,
        <<"x-frame-options">> => <<"DENY">>,
        <<"x-xss-protection">> => <<"1; mode=block">>,
        <<"content-security-policy">> => <<"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'">>,
        <<"referrer-policy">> => <<"strict-origin-when-cross-origin">>,
        <<"permissions-policy">> => <<"camera=(), microphone=(), geolocation=()">>,
        <<"access-control-allow-origin">> => <<"*">>,
        <<"access-control-allow-methods">> => <<"GET, POST, PUT, DELETE, OPTIONS">>,
        <<"access-control-allow-headers">> => <<"content-type, authorization, x-csrf-token">>
    },

    cowboy_req:merge_resp_headers(Headers, Req).

%%====================================================================
%% Internal Functions
%%====================================================================

validate_required_fields(Data) ->
    %% Define required fields for different operations
    RequiredFields = case maps:get(<<"operation">>, Data, undefined) of
        <<"create">> -> [<<"resource">>, <<"action">>];
        <<"update">> -> [<<"resource">>, <<"action">>, <<"id">>];
        <<"delete">> -> [<<"resource">>, <<"id">>];
        _ -> [<<"operation">>]
    end,

    lists:foreach(fun(Field) ->
        case maps:get(Field, Data, undefined) of
            undefined -> throw({missing_field, Field});
            _ -> ok
        end
    end, RequiredFields).

validate_field_types(Data) ->
    %% Validate types based on operation
    Operation = maps:get(<<"operation">>, Data, <<"unknown">>),

    case Operation of
        <<"create">> ->
            validate_create_fields(Data);
        <<"update">> ->
            validate_update_fields(Data);
        <<"delete">> ->
            validate_delete_fields(Data);
        _ ->
            ok
    end.

validate_create_fields(Data) ->
    %% Validate resource type
    ResourceType = maps:get(<<"resource">>, Data, <<"unknown">>),

    case ResourceType of
        <<"customer">> ->
            validate_customer_fields(maps:get(<<"data">>, Data, #{}));
        <<"order">> ->
            validate_order_fields(maps:get(<<"data">>, Data, #{}));
        <<"inventory">> ->
            validate_inventory_fields(maps:get(<<"data">>, Data, #{}));
        _ ->
            ok
    end.

validate_update_fields(Data) ->
    %% ID must be valid
    Id = maps:get(<<"id">>, Data, <<"">>),
    case validate_id(Id) of
        true -> ok;
        false -> throw({invalid_id, Id})
    end.

validate_delete_fields(Data) ->
    %% ID must be valid
    Id = maps:get(<<"id">>, Data, <<"">>),
    case validate_id(Id) of
        true -> ok;
        false -> throw({invalid_id, Id})
    end.

validate_customer_fields(Data) ->
    %% Validate customer-specific fields
    Email = maps:get(<<"email">>, Data, <<"">>),
    case validate_email(Email) of
        true -> ok;
        false -> throw({invalid_email, Email})
    end.

validate_order_fields(Data) ->
    %% Validate order-specific fields
    Amount = maps:get(<<"amount">>, Data, 0),
    case Amount >= 0 of
        true -> ok;
        false -> throw({invalid_amount, Amount})
    end.

validate_inventory_fields(Data) ->
    %% Validate inventory-specific fields
    Quantity = maps:get(<<"quantity">>, Data, 0),
    case Quantity >= 0 of
        true -> ok;
        false -> throw({invalid_quantity, Quantity})
    end.

validate_suspicious_patterns(Data) ->
    %% Check for SQL injection patterns
    check_sql_injection(Data),

    %% Check for command injection patterns
    check_command_injection(Data),

    %% Check for path traversal patterns
    check_path_traversal(Data).

check_sql_injection(Data) ->
    Patterns = [
        <<"';">>,
        <<"--">>,
        <<"' OR '1'='1'">>,
        <<"DROP TABLE">>,
        <<"INSERT INTO">>,
        <<"DELETE FROM">>,
        <<"UPDATE.*SET">>,
        <<"UNION SELECT">>
    ],

    lists:foreach(fun(Pattern) ->
        case contains_pattern(Data, Pattern) of
            true -> throw(sql_injection_attempt);
            false -> ok
        end
    end, Patterns).

check_command_injection(Data) &&
    Patterns = [
        <<";">>,
        <<"&&">>,
        <<"||">>,
        |"$(">>,
        <<"|">>,
        <<"`">>,
        <<"\\"/bin/sh">>,
        <<"\\"/bin/bash">>
    ],

    lists:foreach(fun(Pattern) ->
        case contains_pattern(Data, Pattern) of
            true -> throw(command_injection_attempt);
            false -> ok
        end
    end, Patterns).

check_path_traversal(Data) ->
    Patterns = [
        <<"../">>,
        <<"..\\">>,
        <>/etc/passwd">>,
        <>windows/system32">>,
        <>var/log">>
    ],

    lists:foreach(fun(Pattern) ->
        case contains_pattern(Data, Pattern) of
            true -> throw(path_traversal_attempt);
            false -> ok
        end
    end, Patterns).

contains_pattern(Data, Pattern) ->
    BinaryData = json_encode(Data),
    case re:run(BinaryData, Pattern, [caseless]) of
        match -> true;
        nomatch -> false
    end.

sanitize_value(Value) when is_binary(Value) ->
    %% Remove null bytes
    Sanitized = binary:replace(Value, <<0>>, <<>>),

    %% Control characters except tab, newline, carriage return
    RemovedCtrl = binary:replace(Sanitized, <<"\x01\x02\x03\x04\x05\x06\x07\x08\x0b\x0c\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f">>, <<>>),

    %% Normalize whitespace
    Normalized = re:replace(RemovedCtrl, <<"[\\s\\t\\n\\r]+">>, <<" ">, [global, {return, binary}]),

    Normalized;
sanitize_value(Value) when is_map(Value) ->
    maps:map(fun(_Key, V) -> sanitize_value(V) end, Value);
sanitize_value(Value) when is_list(Value) ->
    lists:map(fun sanitize_value/1, Value);
sanitize_value(Value) ->
    Value.

escape_text(Text, EscapeMap) ->
    escape_text(Text, EscapeMap, <<>>).

escape_text(<<>>, _EscapeMap, Result) ->
    Result;
escape_text(<<Char/utf8, Rest/binary>>, EscapeMap, Result) ->
    case maps:get(Char, EscapeMap, Char) of
        Char when is_integer(Char) ->
            escape_text(Rest, EscapeMap, <<Result/binary, Char/utf8>>);
        Escaped ->
            escape_text(Rest, EscapeMap, <<Result/binary, Escaped/binary>>)
    end.

validate_id(Id) when is_binary(Id) ->
    Length = byte_size(Id),
    Length >= 8 andalso Length =< 64 andalso
    re:run(Id, "^[a-zA-Z0-9_-]+$") =/= nomatch.

validate_email(Email) when is_binary(Email) ->
    Pattern = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$",
    re:run(Email, Pattern, [{capture, none}]) =/= nomatch.

json_encode(Data) ->
    try
        jiffy:encode(Data)
    catch
        _:_ -> <<"">>
    end.

constant_time_compare(<<>>, <<>>) ->
    true;
constant_time_compare(B1, B2) when byte_size(B1) =:= byte_size(B2) ->
    constant_time_compare(B1, B2, 0, 0);
constant_time_compare(_, _) ->
    false.

constant_time_compare(<<H1/utf8, T1/binary>>, <<H2/utf8, T2/binary>>, Sum, C) ->
    NewSum = Sum + (H1 bxor H2),
    constant_time_compare(T1, T2, NewSum, C + 1);
constant_time_compare(<<>>, <<>>, Sum, _) when Sum =:= 0 ->
    true;
constant_time_compare(<<>>, <<>>, _, _) ->
    false.