%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A Authentication Module
%%%
%%% Provides pluggable authentication for the A2A protocol.  Supports
%%% bearer token validation, API key authentication, and custom auth
%%% backends via callback modules.
%%%
%%% An auth backend module must export:
%%%   validate_token(Token :: binary()) ->
%%%       {ok, Claims :: map()} | {error, Reason}.
%%%   check_permissions(Claims :: map(), Permissions :: [binary()]) ->
%%%       ok | {error, Reason}.
%%%
%%% When no backend is configured, authentication is bypassed (all
%%% requests are allowed).  This is useful during development but
%%% should be disabled in production.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_auth).

%% API
-export([
    authenticate/2,
    validate_token/1,
    check_permissions/2
]).

%% Configuration
-export([
    set_backend/1,
    get_backend/0,
    set_api_keys/1,
    add_api_key/2
]).

%% Behaviour for pluggable auth backends
-callback validate_token(Token :: binary()) ->
    {ok, Claims :: map()} | {error, term()}.
-callback check_permissions(Claims :: map(), Permissions :: [binary()]) ->
    ok | {error, term()}.

-optional_callbacks([check_permissions/2]).

%%====================================================================
%% Persistent configuration via application env
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Set the auth backend module.
%%
%% Pass `undefined' to disable authentication (bypass mode).
%% @end
%%--------------------------------------------------------------------
-spec set_backend(module() | undefined) -> ok.
set_backend(Module) ->
    application:set_env(beamai_a2a, auth_backend, Module).

%%--------------------------------------------------------------------
%% @doc Get the currently configured auth backend module.
%% @end
%%--------------------------------------------------------------------
-spec get_backend() -> module() | undefined.
get_backend() ->
    application:get_env(beamai_a2a, auth_backend, undefined).

%%--------------------------------------------------------------------
%% @doc Replace the set of valid API keys.
%%
%% Keys is a map of `Key => Metadata' where `Key' is the API key
%% binary and `Metadata' is an arbitrary map describing the owner.
%% @end
%%--------------------------------------------------------------------
-spec set_api_keys(map()) -> ok.
set_api_keys(Keys) when is_map(Keys) ->
    application:set_env(beamai_a2a, api_keys, Keys).

%%--------------------------------------------------------------------
%% @doc Add (or update) a single API key.
%% @end
%%--------------------------------------------------------------------
-spec add_api_key(binary(), map()) -> ok.
add_api_key(Key, Metadata) when is_binary(Key), is_map(Metadata) ->
    Keys = application:get_env(beamai_a2a, api_keys, #{}),
    application:set_env(beamai_a2a, api_keys, maps:put(Key, Metadata, Keys)).

%%====================================================================
%% Core API
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Authenticate a request given its HTTP headers.
%%
%% Extracts the `Authorization' header, determines the scheme
%% (Bearer / ApiKey), and delegates to the appropriate validator.
%%
%% Returns `{ok, Claims}' on success or `{error, Reason}'.
%%
%% `Req' is expected to be a Cowboy request object, but the function
%% also accepts a plain map with a `<<"authorization">>' key for
%% testing purposes.
%% @end
%%--------------------------------------------------------------------
-spec authenticate(term(), map()) -> {ok, map()} | {error, term()}.
authenticate(Req, Opts) ->
    AuthHeader = extract_auth_header(Req),
    case AuthHeader of
        undefined ->
            case maps:get(allow_anonymous, Opts, false) of
                true  -> {ok, #{anonymous => true}};
                false -> {error, missing_credentials}
            end;
        <<"Bearer ", Token/binary>> ->
            validate_bearer_token(Token);
        <<"bearer ", Token/binary>> ->
            validate_bearer_token(Token);
        <<"ApiKey ", Key/binary>> ->
            validate_api_key(Key);
        <<"apikey ", Key/binary>> ->
            validate_api_key(Key);
        _Other ->
            %% Try as raw API key
            validate_api_key(AuthHeader)
    end.

%%--------------------------------------------------------------------
%% @doc Validate a bearer token using the configured backend.
%%
%% If no backend is configured, returns a default claims map.
%% @end
%%--------------------------------------------------------------------
-spec validate_token(binary()) -> {ok, map()} | {error, term()}.
validate_token(Token) ->
    validate_bearer_token(Token).

%%--------------------------------------------------------------------
%% @doc Check whether the given claims satisfy the required
%% permissions.
%%
%% Delegates to the backend module if one is configured.  When no
%% backend is set, all permission checks pass.
%% @end
%%--------------------------------------------------------------------
-spec check_permissions(map(), [binary()]) -> ok | {error, term()}.
check_permissions(_Claims, []) ->
    ok;
check_permissions(Claims, Permissions) ->
    case get_backend() of
        undefined ->
            %% No backend: all permissions granted
            ok;
        Module ->
            case erlang:function_exported(Module, check_permissions, 2) of
                true  -> Module:check_permissions(Claims, Permissions);
                false -> ok
            end
    end.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Extract the Authorization header from a Cowboy request or a
%% plain map (for testing).
-spec extract_auth_header(term()) -> binary() | undefined.
extract_auth_header(Req) when is_map(Req) ->
    %% Support plain maps for testing
    case maps:get(<<"authorization">>, Req, undefined) of
        undefined ->
            %% Try cowboy_req if it looks like a Cowboy request
            try cowboy_req:header(<<"authorization">>, Req) of
                Val -> Val
            catch
                _:_ -> undefined
            end;
        Val -> Val
    end;
extract_auth_header(_) ->
    undefined.

%% @doc Validate a bearer token.
-spec validate_bearer_token(binary()) -> {ok, map()} | {error, term()}.
validate_bearer_token(Token) when byte_size(Token) =:= 0 ->
    {error, empty_token};
validate_bearer_token(Token) ->
    case get_backend() of
        undefined ->
            %% No backend configured: accept all tokens (dev mode)
            logger:warning("beamai_a2a_auth: no auth backend configured, "
                           "accepting token without validation"),
            {ok, #{
                token => Token,
                authenticated => true,
                backend => none
            }};
        Module ->
            try Module:validate_token(Token)
            catch
                Class:Reason:Stack ->
                    logger:error("Auth backend ~p:validate_token/1 failed: "
                                 "~p:~p~n~p",
                                 [Module, Class, Reason, Stack]),
                    {error, {backend_error, Reason}}
            end
    end.

%% @doc Validate an API key against the configured key set.
-spec validate_api_key(binary()) -> {ok, map()} | {error, term()}.
validate_api_key(Key) when byte_size(Key) =:= 0 ->
    {error, empty_api_key};
validate_api_key(Key) ->
    Keys = application:get_env(beamai_a2a, api_keys, #{}),
    case maps:find(Key, Keys) of
        {ok, Metadata} ->
            {ok, #{
                api_key => true,
                metadata => Metadata,
                authenticated => true
            }};
        error ->
            %% Fall back to backend if configured
            case get_backend() of
                undefined -> {error, invalid_api_key};
                Module    -> try_backend_validate(Module, Key)
            end
    end.

%% @doc Try validating via the backend as a last resort.
-spec try_backend_validate(module(), binary()) -> {ok, map()} | {error, term()}.
try_backend_validate(Module, Token) ->
    try Module:validate_token(Token)
    catch
        _:_ -> {error, invalid_credentials}
    end.
