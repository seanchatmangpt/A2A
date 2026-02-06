%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A Middleware Pipeline
%%%
%%% Provides a composable middleware pipeline for the A2A protocol
%%% request processing.  Middlewares are executed in order; each can
%%% inspect/modify the request context, short-circuit with an error,
%%% or allow the request to proceed to the next middleware.
%%%
%%% A middleware is a function:
%%%   fun(Req :: map(), Context :: map()) ->
%%%       {ok, NewContext :: map()} |
%%%       {error, ErrorMap :: map()} |
%%%       {stop, Response :: term()}
%%%
%%% Built-in middlewares:
%%%   auth/0        - authentication via beamai_a2a_auth
%%%   rate_limit/0  - rate limiting via beamai_a2a_rate_limit
%%%   logging/0     - request logging
%%%
%%% Example:
%%%   Pipeline = beamai_a2a_middleware:chain([
%%%       beamai_a2a_middleware:logging(),
%%%       beamai_a2a_middleware:auth(),
%%%       beamai_a2a_middleware:rate_limit()
%%%   ]),
%%%   case beamai_a2a_middleware:apply(Pipeline, Req, #{}) of
%%%       {ok, Context}  -> handle_request(Req, Context);
%%%       {error, Error} -> return_error(Error)
%%%   end.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_middleware).

%% API
-export([
    apply/3,
    chain/1,
    add/2
]).

%% Built-in middleware constructors
-export([
    auth/0,
    auth/1,
    rate_limit/0,
    rate_limit/1,
    logging/0,
    logging/1,
    cors/0,
    cors/1
]).

%% Types
-type middleware() :: fun((map(), map()) ->
    {ok, map()} | {error, map()} | {stop, term()}).

-type pipeline() :: [middleware()].

-export_type([middleware/0, pipeline/0]).

%%====================================================================
%% Pipeline execution
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Execute a middleware pipeline against a request.
%%
%% `Pipeline' is a list of middleware functions (see `chain/1').
%% `Req' is the incoming request (typically a JSON-RPC decoded map).
%% `Context' is the initial context map (accumulated state).
%%
%% Each middleware receives the request and the current context,
%% returning `{ok, NewContext}' to proceed, or `{error, ErrorMap}'
%% / `{stop, Response}' to halt the pipeline.
%% @end
%%--------------------------------------------------------------------
-spec apply(pipeline(), map(), map()) ->
    {ok, map()} | {error, map()} | {stop, term()}.
apply([], _Req, Context) ->
    {ok, Context};
apply([Middleware | Rest], Req, Context) ->
    try Middleware(Req, Context) of
        {ok, NewContext} ->
            apply(Rest, Req, NewContext);
        {error, _} = Error ->
            Error;
        {stop, _} = Stop ->
            Stop
    catch
        Class:Reason:Stack ->
            logger:error("Middleware failed: ~p:~p~n~p",
                         [Class, Reason, Stack]),
            {error, #{
                <<"code">>    => -32603,
                <<"message">> => <<"Internal middleware error">>
            }}
    end.

%%--------------------------------------------------------------------
%% @doc Create a pipeline from a list of middleware functions.
%%
%% This is a thin wrapper that validates and returns the list.
%% @end
%%--------------------------------------------------------------------
-spec chain([middleware()]) -> pipeline().
chain(Middlewares) when is_list(Middlewares) ->
    Middlewares.

%%--------------------------------------------------------------------
%% @doc Append a middleware to an existing pipeline.
%% @end
%%--------------------------------------------------------------------
-spec add(pipeline(), middleware()) -> pipeline().
add(Pipeline, Middleware) when is_list(Pipeline), is_function(Middleware, 2) ->
    Pipeline ++ [Middleware].

%%====================================================================
%% Built-in middlewares
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Authentication middleware.
%%
%% Delegates to `beamai_a2a_auth:authenticate/2'.  On success, adds
%% `auth_claims' to the context.  On failure, returns a JSON-RPC
%% auth-required error.
%% @end
%%--------------------------------------------------------------------
-spec auth() -> middleware().
auth() ->
    auth(#{}).

-spec auth(map()) -> middleware().
auth(Opts) ->
    fun(Req, Context) ->
        case beamai_a2a_auth:authenticate(Req, Opts) of
            {ok, Claims} ->
                {ok, Context#{auth_claims => Claims}};
            {error, Reason} ->
                logger:info("Authentication failed: ~p", [Reason]),
                {error, #{
                    <<"code">>    => -32004,
                    <<"message">> => <<"Authentication required">>
                }}
        end
    end.

%%--------------------------------------------------------------------
%% @doc Rate-limiting middleware.
%%
%% Extracts a client identifier from the context (from auth claims
%% or a fallback IP key) and checks the rate limiter.
%% @end
%%--------------------------------------------------------------------
-spec rate_limit() -> middleware().
rate_limit() ->
    rate_limit(#{}).

-spec rate_limit(map()) -> middleware().
rate_limit(_Opts) ->
    fun(Req, Context) ->
        ClientId = extract_client_id(Req, Context),
        Method = maps:get(<<"method">>, Req, <<"default">>),
        case beamai_a2a_rate_limit:check(ClientId, Method) of
            allow ->
                {ok, Context};
            {deny, RetryAfterMs} ->
                {error, #{
                    <<"code">>    => -32005,
                    <<"message">> => <<"Rate limit exceeded">>,
                    <<"data">>    => #{
                        <<"retryAfterMs">> => RetryAfterMs
                    }
                }}
        end
    end.

%%--------------------------------------------------------------------
%% @doc Logging middleware.
%%
%% Logs the incoming request method and id at info level.
%% @end
%%--------------------------------------------------------------------
-spec logging() -> middleware().
logging() ->
    logging(#{level => info}).

-spec logging(map()) -> middleware().
logging(Opts) ->
    Level = maps:get(level, Opts, info),
    fun(Req, Context) ->
        Method = maps:get(<<"method">>, Req, <<"unknown">>),
        Id = maps:get(<<"id">>, Req, null),
        logger:log(Level, "beamai_a2a request: method=~s id=~p",
                   [Method, Id]),
        {ok, Context}
    end.

%%--------------------------------------------------------------------
%% @doc CORS middleware.
%%
%% Adds CORS-related keys to the context so the HTTP handler can
%% include appropriate headers in the response.
%% @end
%%--------------------------------------------------------------------
-spec cors() -> middleware().
cors() ->
    cors(#{
        allow_origin => <<"*">>,
        allow_methods => <<"GET, POST, OPTIONS">>,
        allow_headers => <<"content-type, authorization">>,
        max_age => <<"86400">>
    }).

-spec cors(map()) -> middleware().
cors(CorsConfig) ->
    fun(_Req, Context) ->
        {ok, Context#{cors => CorsConfig}}
    end.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Extract a client identifier for rate limiting.
%%
%% Tries, in order: auth_claims.api_key_id, auth_claims.subject,
%% context.client_ip, and falls back to <<"anonymous">>.
-spec extract_client_id(map(), map()) -> binary().
extract_client_id(_Req, #{auth_claims := Claims}) ->
    case maps:get(api_key_id, Claims, undefined) of
        undefined ->
            case maps:get(subject, Claims, undefined) of
                undefined -> maps:get(token, Claims, <<"authenticated">>);
                Sub when is_binary(Sub) -> Sub;
                Sub -> beamai_a2a_utils:to_binary(Sub)
            end;
        KeyId when is_binary(KeyId) -> KeyId;
        KeyId -> beamai_a2a_utils:to_binary(KeyId)
    end;
extract_client_id(_Req, #{client_ip := IP}) when is_binary(IP) ->
    IP;
extract_client_id(_Req, _Context) ->
    <<"anonymous">>.
