%%% @doc Authentication System
%%% Handles JWT token authentication, API key management, and session management

-module(security_auth).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([authenticate/2, validate_token/1, generate_token/2, refresh_token/1]).
-export([create_api_key/2, revoke_api_key/1, validate_api_key/1]).
-export([start_session/2, end_session/1, validate_session/1]).
-export([get_user_permissions/1, check_permission/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(JWT_SECRET, application:get_env(craftplan_mcp, jwt_secret, "default-secret-key")).
-define(TOKEN_EXPIRY, 3600). % 1 hour
-define(REFRESH_TOKEN_EXPIRY, 86400). % 24 hours
-define(MAX_SESSIONS_PER_USER, 10).
-define(API_KEY_PREFIX, "cpk_").

-record(state, {
    tokens :: map(),
    api_keys :: map(),
    sessions :: map(),
    users :: map()
}).

-record(user, {
    id :: binary(),
    username :: binary(),
    email :: binary(),
    password_hash :: binary(),
    role :: binary(),
    permissions :: [binary()],
    created_at :: integer(),
    last_login :: integer() | undefined
}).

-record(token, {
    id :: binary(),
    user_id :: binary(),
    type :: access | refresh,
    expires_at :: integer(),
    issued_at :: integer(),
    jti :: binary()
}).

-record(api_key, {
    id :: binary(),
    user_id :: binary(),
    key :: binary(),
    name :: binary(),
    permissions :: [binary()],
    created_at :: integer(),
    expires_at :: integer() | undefined,
    last_used :: integer() | undefined,
    is_active :: boolean()
}).

-record(session, {
    id :: binary(),
    user_id :: binary(),
    token_id :: binary(),
    ip_address :: binary(),
    user_agent :: binary(),
    created_at :: integer(),
    last_accessed :: integer(),
    expires_at :: integer(),
    is_active :: boolean()
}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

%% @doc Authenticate user with username/password
-spec authenticate(binary(), binary()) -> {ok, map()} | {error, term()}.
authenticate(Username, Password) ->
    gen_server:call(?SERVER, {authenticate, Username, Password}).

%% @doc Validate JWT token
-spec validate_token(binary()) -> {ok, map()} | {error, term()}.
validate_token(Token) ->
    gen_server:call(?SERVER, {validate_token, Token}).

%% @doc Generate JWT token for user
-spec generate_token(binary(), binary()) -> {ok, binary()}.
generate_token(UserId, TokenType) ->
    gen_server:call(?SERVER, {generate_token, UserId, TokenType}).

%% @doc Refresh JWT token
-spec refresh_token(binary()) -> {ok, binary()} | {error, term()}.
refresh_token(RefreshToken) ->
    gen_server:call(?SERVER, {refresh_token, RefreshToken}).

%% @doc Create API key for user
-spec create_api_key(binary(), binary()) -> {ok, map()}.
create_api_key(UserId, Name) ->
    gen_server:call(?SERVER, {create_api_key, UserId, Name}).

%% @doc Revoke API key
-spec revoke_api_key(binary()) -> ok.
revoke_api_key(ApiKeyId) ->
    gen_server:call(?SERVER, {revoke_api_key, ApiKeyId}).

%% @doc Validate API key
-spec validate_api_key(binary()) -> {ok, map()} | {error, term()}.
validate_api_key(Key) ->
    gen_server:call(?SERVER, {validate_api_key, Key}).

%% @doc Start user session
-spec start_session(binary(), map()) -> {ok, binary()}.
start_session(UserId, Metadata) ->
    gen_server:call(?SERVER, {start_session, UserId, Metadata}).

%% @doc End user session
-spec end_session(binary()) -> ok.
end_session(SessionId) ->
    gen_server:call(?SERVER, {end_session, SessionId}).

%% @doc Validate session
-spec validate_session(binary()) -> {ok, map()} | {error, term()}.
validate_session(SessionId) ->
    gen_server:call(?SERVER, {validate_session, SessionId}).

%% @doc Get user permissions
-spec get_user_permissions(binary()) -> {ok, [binary()]}.
get_user_permissions(UserId) ->
    gen_server:call(?SERVER, {get_user_permissions, UserId}).

%% @doc Check if user has permission
-spec check_permission(binary(), binary(), binary()) -> boolean().
check_permission(UserId, Resource, Action) ->
    gen_server:call(?SERVER, {check_permission, UserId, Resource, Action}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    %% Initialize with default admin user for testing
    AdminUser = #user{
        id = <<"admin">>,
        username = <<"admin">>,
        email = <<"admin@craftplan.com">>,
        password_hash = crypto:hash(sha256, <<"admin_password">>),
        role = <<"admin">>,
        permissions = [<<"*">>],
        created_at = os:system_time(second),
        last_login = undefined
    },

    State = #state{
        tokens = #{},
        api_keys = #{},
        sessions = #{},
        users = #{<<"admin">> => AdminUser}
    },

    %% Start cleanup process
    erlang:send_after(60000, self(), cleanup_expired_items),

    {ok, State}.

handle_call({authenticate, Username, Password}, _From, State) ->
    case maps:get(Username, State#state.users, undefined) of
        undefined ->
            {reply, {error, invalid_credentials}, State};
        User ->
            PasswordHash = crypto:hash(sha256, Password),
            case User#user.password_hash =:= PasswordHash of
                true ->
                    %% Update last login
                    UpdatedUser = User#user{last_login = os:system_time(second)},
                    NewState = State#state{users = maps:put(Username, UpdatedUser, State#state.users)},

                    %% Generate tokens
                    AccessToken = generate_token_binary(User#user.id, access),
                    RefreshToken = generate_token_binary(User#user.id, refresh),

                    TokenRecord = #token{
                        id = generate_id(),
                        user_id = User#user.id,
                        type = access,
                        expires_at = os:system_time(second) + ?TOKEN_EXPIRY,
                        issued_at = os:system_time(second),
                        jti = generate_id()
                    },

                    RefreshRecord = #token{
                        id = generate_id(),
                        user_id = User#user.id,
                        type = refresh,
                        expires_at = os:system_time(second) + ?REFRESH_TOKEN_EXPIRY,
                        issued_at = os:system_time(second),
                        jti = generate_id()
                    },

                    UpdatedState = NewState#state{
                        tokens = maps:put(TokenRecord#token.id, TokenRecord,
                                       maps:put(RefreshRecord#token.id, RefreshRecord, State#state.tokens))
                    },

                    Response = #{
                        access_token => AccessToken,
                        refresh_token => RefreshToken,
                        expires_in => ?TOKEN_EXPIRY,
                        token_type => <<"Bearer">>,
                        user => #{
                            id => User#user.id,
                            username => User#user.username,
                            email => User#user.email,
                            role => User#user.role
                        }
                    },
                    {reply, {ok, Response}, UpdatedState};
                false ->
                    {reply, {error, invalid_credentials}, State}
            end
    end;

handle_call({validate_token, Token}, _From, State) ->
    case verify_token(Token) of
        {ok, Payload} ->
            Jti = maps:get(<<"jti">>, Payload),
            case maps:get(Jti, State#state.tokens, undefined) of
                TokenRecord when TokenRecord#token.expires_at >= os:system_time(second) ->
                    Response = #{
                        user_id => TokenRecord#token.user_id,
                        type => TokenRecord#token.type,
                        expires_at => TokenRecord#token.expires_at,
                        permissions => get_user_permissions_internal(TokenRecord#token.user_id, State)
                    },
                    {reply, {ok, Response}, State};
                _ ->
                    {reply, {error, invalid_token}, State}
            end;
        {error, _} ->
            {reply, {error, invalid_token}, State}
    end;

handle_call({generate_token, UserId, TokenType}, _From, State) ->
    Token = generate_token_binary(UserId, TokenType),
    TokenRecord = #token{
        id = generate_id(),
        user_id = UserId,
        type = TokenType,
        expires_at = os:system_time(second) + case TokenType of
            access -> ?TOKEN_EXPIRY;
            refresh -> ?REFRESH_TOKEN_EXPIRY
        end,
        issued_at = os:system_time(second),
        jti = generate_id()
    },

    NewState = State#state{
        tokens = maps:put(TokenRecord#token.id, TokenRecord, State#state.tokens)
    },

    {reply, {ok, Token}, NewState};

handle_call({refresh_token, RefreshToken}, _From, State) ->
    case verify_token(RefreshToken) of
        {ok, Payload} ->
            Jti = maps:get(<<"jti">>, Payload),
            case maps:get(Jti, State#state.tokens, undefined) of
                TokenRecord when TokenRecord#token.type =:= refresh,
                                TokenRecord#token.expires_at >= os:system_time(second) ->
                    %% Generate new access token
                    NewAccessToken = generate_token_binary(TokenRecord#token.user_id, access),

                    AccessTokenRecord = #token{
                        id = generate_id(),
                        user_id = TokenRecord#token.user_id,
                        type = access,
                        expires_at = os:system_time(second) + ?TOKEN_EXPIRY,
                        issued_at = os:system_time(second),
                        jti = generate_id()
                    },

                    NewState = State#state{
                        tokens = maps:put(AccessTokenRecord#token.id, AccessTokenRecord,
                                        maps:remove(Jti, State#state.tokens))
                    },

                    Response = #{
                        access_token => NewAccessToken,
                        expires_in => ?TOKEN_EXPIRY,
                        token_type => <<"Bearer">>
                    },
                    {reply, {ok, Response}, NewState};
                _ ->
                    {reply, {error, invalid_token}, State}
            end;
        {error, _} ->
            {reply, {error, invalid_token}, State}
    end;

handle_call({create_api_key, UserId, Name}, _From, State) ->
    ApiKeyId = generate_id(),
    ApiKey = generate_api_key(),

    ApiKeyRecord = #api_key{
        id = ApiKeyId,
        user_id = UserId,
        key = ApiKey,
        name = Name,
        permissions = get_user_permissions_internal(UserId, State),
        created_at = os:system_time(second),
        expires_at => undefined, % Never expires by default
        last_used => undefined,
        is_active = true
    },

    NewState = State#state{
        api_keys = maps:put(ApiKeyId, ApiKeyRecord, State#state.api_keys)
    },

    Response = #{
        api_key_id => ApiKeyId,
        key => ApiKey,
        name => Name,
        permissions => ApiKeyRecord#api_key.permissions,
        created_at => ApiKeyRecord#api_key.created_at
    },

    {reply, {ok, Response}, NewState};

handle_call({revoke_api_key, ApiKeyId}, _From, State) ->
    ApiKeyRecord = maps:get(ApiKeyId, State#state.api_keys, undefined),
    case ApiKeyRecord of
        undefined ->
            {reply, {error, not_found}, State};
        _ ->
            UpdatedKey = ApiKeyRecord#api_key{is_active = false},
            NewState = State#state{
                api_keys = maps:put(ApiKeyId, UpdatedKey, State#state.api_keys)
            },
            {reply, ok, NewState}
    end;

handle_call({validate_api_key, Key}, _From, State) ->
    case find_api_key_by_key(Key, State) of
        {ok, ApiKeyRecord} when ApiKeyRecord#api_key.is_active ->
            %% Update last used
            UpdatedKey = ApiKeyRecord#api_key{last_used = os:system_time(second)},
            NewState = State#state{
                api_keys = maps:put(ApiKeyRecord#api_key.id, UpdatedKey, State#state.api_keys)
            },

            Response = #{
                user_id => ApiKeyRecord#api_key.user_id,
                permissions => ApiKeyRecord#api_key.permissions,
                last_used => UpdatedKey#api_key.last_used
            },
            {reply, {ok, Response}, NewState};
        {ok, _} ->
            {reply, {error, invalid_key}, State};
        {error, not_found} ->
            {reply, {error, invalid_key}, State}
    end;

handle_call({start_session, UserId, Metadata}, _From, State) ->
    %% Check max sessions per user
    UserSessions = maps:filter(fun(_, Session) ->
        Session#session.user_id =:= UserId andalso Session#session.is_active
    end, State#state.sessions),

    case maps:size(UserSessions) >= ?MAX_SESSIONS_PER_USER of
        true ->
            {reply, {error, max_sessions_exceeded}, State};
        false ->
            SessionId = generate_id(),
            TokenId = generate_id(),

            SessionRecord = #session{
                id = SessionId,
                user_id = UserId,
                token_id = TokenId,
                ip_address = maps:get(ip_address, Metadata, <<"unknown">>),
                user_agent = maps:get(user_agent, Metadata, <<"unknown">>),
                created_at = os:system_time(second),
                last_accessed = os:system_time(second),
                expires_at = os:system_time(second) + ?TOKEN_EXPIRY,
                is_active = true
            },

            %% Create associated token
            TokenRecord = #token{
                id = TokenId,
                user_id = UserId,
                type = access,
                expires_at = SessionRecord#session.expires_at,
                issued_at = SessionRecord#session.created_at,
                jti = generate_id()
            },

            NewState = State#state{
                sessions = maps:put(SessionId, SessionRecord, State#state.sessions),
                tokens = maps:put(TokenId, TokenRecord, State#state.tokens)
            },

            {reply, {ok, SessionId}, NewState}
    end;

handle_call({end_session, SessionId}, _From, State) ->
    case maps:get(SessionId, State#state.sessions, undefined) of
        undefined ->
            {reply, ok, State};
        Session ->
            UpdatedSession = Session#session{is_active = false},
            NewState = State#state{
                sessions = maps:put(SessionId, UpdatedSession, State#state.sessions)
            },
            {reply, ok, NewState}
    end;

handle_call({validate_session, SessionId}, _From, State) ->
    case maps:get(SessionId, State#state.sessions, undefined) of
        Session when Session#session.is_active andalso
                    Session#session.expires_at >= os:system_time(second) ->
            %% Update last accessed
            UpdatedSession = Session#session{last_accessed = os:system_time(second)},
            NewState = State#state{
                sessions = maps:put(SessionId, UpdatedSession, State#state.sessions)
            },

            Response = #{
                user_id => Session#session.user_id,
                ip_address => Session#session.ip_address,
                user_agent => Session#session.user_agent,
                last_accessed => UpdatedSession#session.last_accessed,
                expires_at => Session#session.expires_at
            },
            {reply, {ok, Response}, NewState};
        _ ->
            {reply, {error, invalid_session}, State}
    end;

handle_call({get_user_permissions, UserId}, _From, State) ->
    Permissions = get_user_permissions_internal(UserId, State),
    {reply, {ok, Permissions}, State};

handle_call({check_permission, UserId, Resource, Action}, _From, State) ->
    Permissions = get_user_permissions_internal(UserId, State),
    HasPermission = check_permission_internal(Permissions, Resource, Action),
    {reply, HasPermission, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(cleanup_expired_items, State) ->
    Now = os:system_time(second),

    %% Clean expired tokens
    ActiveTokens = maps:filter(fun(_, Token) ->
        Token#token.expires_at >= Now
    end, State#state.tokens),

    %% Clean expired sessions
    ActiveSessions = maps:filter(fun(_, Session) ->
        Session#session.expires_at >= Now andalso Session#session.is_active
    end, State#state.sessions),

    %% Clean inactive API keys (older than 90 days)
    OldKeys = maps:filter(fun(_, Key) ->
        not Key#api_key.is_active andalso Key#api_key.created_at < Now - 7776000
    end, State#state.api_keys),

    NewState = State#state{
        tokens = ActiveTokens,
        sessions = ActiveSessions,
        api_keys = maps:without(maps:keys(OldKeys), State#state.api_keys)
    },

    %% Schedule next cleanup
    erlang:send_after(60000, self(), cleanup_expired_items),

    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

generate_token_binary(UserId, Type) ->
    Payload = #{
        sub => UserId,
        iat => os:system_time(second),
        exp => os:system_time(second) + case Type of
            access -> ?TOKEN_EXPIRY;
            refresh -> ?REFRESH_TOKEN_EXPIRY
        end,
        jti => generate_id(),
        type => Type
    },

    Secret = ?JWT_SECRET,
    SignedPayload = jose_jws:sign(Payload, #{
        alg => <<"HS256">>,
        key => Secret
    }),

    jose_jws:compact(SignedPayload).

verify_token(Token) ->
    try
        {_, Payload} = jose_jws:compact_verify(Token, ?JWT_SECRET),
        {ok, Payload}
    catch
        _:_ -> {error, invalid_token}
    end.

generate_id() ->
    crypto:strong_rand_bytes(16).

generate_api_key() ->
    <<?API_KEY_PREFIX/binary, (crypto:strong_rand_bytes(32))/binary>>.

find_api_key_by_key(Key, State) ->
    case maps:filter(fun(_, ApiKey) ->
        ApiKey#api_key.key =:= Key andalso ApiKey#api_key.is_active
    end, State#state.api_keys) of
        #{Id := ApiKeyRecord} -> {ok, ApiKeyRecord};
        _ -> {error, not_found}
    end.

get_user_permissions_internal(UserId, State) ->
    case maps:get(UserId, State#state.users, undefined) of
        undefined -> [];
        User -> User#user.permissions
    end.

check_permission_internal(Permissions, Resource, Action) ->
    lists:any(fun(Perm) ->
        Perm =:= <<"*">> orelse
        Perm =<< (iolist_to_binary([Resource, $:, Action]))/binary >>
    end, Permissions).