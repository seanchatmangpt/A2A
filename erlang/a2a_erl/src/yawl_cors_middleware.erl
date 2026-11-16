%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL CORS Middleware
%%%
%%% This module provides Cross-Origin Resource Sharing (CORS) middleware
%%% for the YAWL REST API. It handles preflight OPTIONS requests and adds
%%% appropriate CORS headers to all responses.
%%%
%%% ## Configuration
%%%
%%% Configure CORS in your application environment:
%%% ```
%%% {yawl_cors, [
%%%     {allowed_origins, ["*"]},  % or ["https://example.com"]
%%%     {allowed_methods, ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]},
%%%     {allowed_headers, ["Content-Type", "Authorization"]},
%%%     {exposed_headers, ["X-Request-ID"]},
%%%     {max_age, 3600},
%%%     {allow_credentials, false}
%%% ]}
%%% ```
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_cors_middleware).
-author("A2A Team").

%% Cowboy middleware callbacks
-export([execute/2]).

%% Type definitions
-type cors_config() :: #{
    allowed_origins => [binary()] | '*',
    allowed_methods => [binary()],
    allowed_headers => [binary()],
    exposed_headers => [binary()],
    max_age => non_neg_integer(),
    allow_credentials => boolean()
}.
-type cowboy_request() :: term().
-type env() :: map().

%%====================================================================
%%% Cowboy Middleware Callback
%%====================================================================

%% @doc Execute CORS middleware
-spec execute(cowboy_request(), env()) -> {ok, cowboy_request(), env()}.
execute(Req, Env) ->
    CorsConfig = get_cors_config(),

    case is_preflight_request(Req) of
        true ->
            %% Handle preflight OPTIONS request
            Req2 = add_cors_headers(Req, CorsConfig),
            %% Respond immediately to preflight
            Req3 = cowboy_req:reply(200, #{}, <<>>, Req2),
            {ok, Req3, Env};
        false ->
            %% Add CORS headers to all other requests
            Req2 = add_cors_headers(Req, CorsConfig),
            {ok, Req2, Env}
    end.

%%====================================================================
%%% Internal Functions
%%====================================================================

%% @private
%% @doc Check if this is a CORS preflight request
-spec is_preflight_request(cowboy_request()) -> boolean().
is_preflight_request(Req) ->
    Method = cowboy_req:method(Req),
    Origin = cowboy_req:header(<<"origin">>, Req),
    RequestMethod = cowboy_req:header(<<"access-control-request-method">>, Req),

    Method =:= <<"OPTIONS">> andalso
    Origin =/= undefined andalso
    RequestMethod =/= undefined.

%% @private
%% @doc Add CORS headers to the request
-spec add_cors_headers(cowboy_request(), cors_config()) -> cowboy_request().
add_cors_headers(Req, CorsConfig) ->
    %% Get the origin from the request
    RequestOrigin = cowboy_req:header(<<"origin">>, Req),

    %% Determine allowed origin
    AllowedOrigin = case maps:get(allowed_origins, CorsConfig) of
        '*' ->
            <<"*">>;
        AllowedOrigins when is_list(AllowedOrigins) ->
            case lists:member(RequestOrigin, AllowedOrigins) of
                true -> RequestOrigin;
                false -> hd(AllowedOrigins)
            end
    end,

    %% Build headers
    Headers = #{
        <<"access-control-allow-origin">> => AllowedOrigin,
        <<"access-control-allow-methods">> =>
            method_list_to_binary(maps:get(allowed_methods, CorsConfig)),
        <<"access-control-allow-headers">> =>
            header_list_to_binary(maps:get(allowed_headers, CorsConfig)),
        <<"access-control-expose-headers">> =>
            header_list_to_binary(maps:get(exposed_headers, CorsConfig, [])),
        <<"access-control-max-age">> =>
            integer_to_binary(maps:get(max_age, CorsConfig, 3600))
    },

    %% Add credentials header if configured
    Headers2 = case maps:get(allow_credentials, CorsConfig, false) of
        true -> Headers#{<<"access-control-allow-credentials">> => <<"true">>};
        false -> Headers
    end,

    %% Set all headers on the request
    lists:foldl(fun({K, V}, AccReq) ->
        cowboy_req:set_resp_header(K, V, AccReq)
    end, Req, maps:to_list(Headers2)).

%% @private
%% @doc Get CORS configuration from application environment
-spec get_cors_config() -> cors_config().
get_cors_config() ->
    DefaultConfig = #{
        allowed_origins => <<"*">>,
        allowed_methods => [<<"GET">>, <<"POST">>, <<"PUT">>, <<"DELETE">>,
                          <<"PATCH">>, <<"OPTIONS">>],
        allowed_headers => [<<"Content-Type">>, <<"Authorization">>,
                           <<"X-Request-ID">>],
        exposed_headers => [<<"X-Request-ID">>],
        max_age => 3600,
        allow_credentials => false
    },

    case application:get_env(yawl, cors_config) of
        {ok, Config} when is_map(Config) ->
            maps:merge(DefaultConfig, Config);
        {ok, Config} when is_list(Config) ->
            %% Legacy list format - convert to map
            proplist_to_map(Config, DefaultConfig);
        undefined ->
            DefaultConfig
    end.

%% @private
proplist_to_map(Config, Default) ->
    maps:fold(fun(K, V, Acc) ->
        case lists:keyfind(K, 1, Config) of
            {K, Value} -> Acc#{K => Value};
            false -> Acc#{K => V}
        end
    end, #{}, Default).

%% @private
method_list_to_binary(Methods) ->
    iolist_to_binary(lists:join(<<", ">>, [atom_to_binary(M, utf8) || M <- Methods])).

%% @private
header_list_to_binary(Headers) ->
    iolist_to_binary(lists:join(<<", ">>, [H || H <- Headers])).
