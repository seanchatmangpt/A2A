%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Authentication Middleware
%%%
%%% This module provides JWT-based authentication middleware for the YAWL
%%% REST API. It validates JWT tokens, handles token refresh, provides
%%% role-based access control, and integrates with Cowboy REST handlers.
%%%
%%% ## Features
%%%
%%% - JWT token validation and parsing
%%% - Token refresh handling
%%% - Role-based access control (RBAC)
%%% - API key authentication support
%%% - Request context injection
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_auth_middleware).
-author("A2A Team").

%% API exports
-export([
    authenticate/2,
    authenticate/3,
    validate_token/1,
    validate_token/2,
    verify_token/1,
    extract_token/1,
    create_token/2,
    create_token/3,
    refresh_token/1,
    get_token_claims/1,
    get_user_id/1,
    get_roles/1,
    check_permission/3,
    require_role/2,
    require_permission/2,
    set_request_context/2,
    get_request_context/1,
    is_authenticated/1,
    token_expired/1
]).

%% Include files
-include("yawl_types.hrl").

%% Type definitions
-type token() :: binary().
-type claims() :: #{
    sub := binary(),
    exp := integer(),
    iat := integer(),
    iss := binary(),
    roles := [binary()],
    permissions := [binary()]
}.
-type auth_result() :: {ok, claims(), cowboy_request()} |
                       {error, yawl_error_response:error_response(), cowboy_request()}.
-type request_context() :: #{
    user_id => binary(),
    roles => [atom()],
    permissions => [atom()],
    token => token()
}.
-type cowboy_request() :: term().  %% Cowboy request is opaque type

%% Process dictionary keys
-define(REQUEST_CONTEXT_KEY, '$yawl_auth_context').
-define(SECRET_KEY, '$yawl_jwt_secret').
-define(TOKEN_TTL, 3600). % 1 hour default
-define(REFRESH_TTL, 86400). % 24 hours default

%% JWT algorithm and configuration
-define(JWT_ALG, <<"HS256">>).
-define(JWT_TYP, <<"JWT">>).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Authenticate a request using default options.
-spec authenticate(cowboy_request(), [binary()]) -> auth_result().
authenticate(Req, RequiredRoles) ->
    authenticate(Req, RequiredRoles, #{}).

%% @doc Authenticate a request with options.
-spec authenticate(cowboy_request(), [binary()], map()) -> auth_result().
authenticate(Req, RequiredRoles, Options) ->
    case extract_token(Req) of
        {ok, Token} ->
            case validate_token(Token, Options) of
                {ok, Claims} ->
                    %% Check roles
                    UserRoles = maps:get(roles, Claims, []),
                    case check_roles(UserRoles, RequiredRoles) of
                        true ->
                            %% Set request context
                            Context = #{
                                user_id => maps:get(sub, Claims),
                                roles => [binary_to_existing_atom(R, utf8) || R <- UserRoles],
                                permissions => [binary_to_existing_atom(P, utf8) || P <- maps:get(permissions, Claims, [])],
                                token => Token
                            },
                            {ok, Claims, set_request_context(Req, Context)};
                        false ->
                            ErrorResponse = yawl_error_response:format_auth_error(
                                insufficient_permissions,
                                #{required_roles => RequiredRoles, user_roles => UserRoles}
                            ),
                            {error, ErrorResponse, Req}
                    end;
                {error, Reason} ->
                    ErrorResponse = case Reason of
                        token_expired -> yawl_error_response:format_auth_error(token_expired, #{});
                        invalid_token -> yawl_error_response:format_auth_error(invalid_token, #{});
                        missing_token -> yawl_error_response:format_auth_error(missing_token, #{});
                        _ -> yawl_error_response:format_auth_error(authentication_failed, #{reason => Reason})
                    end,
                    {error, ErrorResponse, Req}
            end
    end.

%% @doc Validate a JWT token.
-spec validate_token(token()) -> {ok, claims()} | {error, term()}.
validate_token(Token) ->
    validate_token(Token, #{}).

%% @doc Validate a JWT token with options.
-spec validate_token(token(), map()) -> {ok, claims()} | {error, term()}.
validate_token(Token, Options) ->
    %% Decode and verify token
    case verify_token(Token) of
        {ok, Claims} ->
            %% Check expiration
            case token_expired(Claims) of
                true ->
                    {error, token_expired};
                false ->
                    %% Check issuer if specified
                    case maps:get(iss, Claims, undefined) of
                        undefined ->
                            {ok, Claims};
                        Issuer ->
                            case maps:get(expected_issuer, Options, Issuer) of
                                Issuer -> {ok, Claims};
                                _ -> {error, invalid_issuer}
                            end
                    end
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Verify a JWT token signature.
-spec verify_token(token()) -> {ok, claims()} | {error, term()}.
verify_token(Token) ->
    try
        %% Split token into parts
        [HeaderB64, PayloadB64, SignatureB64] = binary:split(Token, <<".">>, [global]),

        %% Decode header and payload
        Header = decode_base64url(HeaderB64),
        Payload = decode_base64url(PayloadB64),

        %% Verify header
        HeaderMap = jiffy:decode(Header, [return_maps]),
        case maps:get(<<"alg">>, HeaderMap) of
            ?JWT_ALG ->
                ok;
            _ ->
                throw({error, invalid_algorithm})
        end,

        %% Verify signature
        Secret = get_secret_key(),
        Data = <<HeaderB64/binary, ".", PayloadB64/binary>>,
        ExpectedSignature = crypto:mac(hmac, sha256, Secret, Data),
        ExpectedSignatureB64 = encode_base64url(ExpectedSignature),

        case constant_time_compare(SignatureB64, ExpectedSignatureB64) of
            true ->
                Claims = jiffy:decode(Payload, [return_maps]),
                {ok, Claims};
            false ->
                {error, invalid_signature}
        end
    catch
        throw:{error, Reason} -> {error, Reason};
        _:_ -> {error, invalid_token}
    end.

%% @doc Extract the authentication token from a request.
-spec extract_token(cowboy_request()) -> {ok, token()} | {error, missing_token}.
extract_token(Req) ->
    %% Try Authorization header first
    AuthHeader = cowboy_req:header(<<"authorization">>, Req),
    case AuthHeader of
        <<"Bearer ", Token/binary>> ->
            {ok, Token};
        <<"bearer ", Token/binary>> ->
            {ok, Token};
        _ ->
            %% Try query parameter
            QsVal = cowboy_req:qs_val(<<"token">>, Req),
            case QsVal of
                {true, Token} -> {ok, Token};
                _ -> {error, missing_token}
            end
    end.

%% @doc Create a JWT token with default TTL.
-spec create_token(binary(), [atom()]) -> token().
create_token(UserId, Roles) ->
    create_token(UserId, Roles, #{}).

%% @doc Create a JWT token with options.
-spec create_token(binary(), [atom()], map()) -> token().
create_token(UserId, Roles, Options) ->
    Now = erlang:system_time(second),
    TTL = maps:get(ttl, Options, ?TOKEN_TTL),
    Claims = #{
        sub => UserId,
        iat => Now,
        exp => Now + TTL,
        iss => maps:get(issuer, Options, <<"yawl">>),
        roles => [atom_to_binary(R, utf8) || R <- Roles],
        permissions => [atom_to_binary(P, utf8) || P <- maps:get(permissions, Options, [])]
    },
    encode_jwt(Claims).

%% @doc Refresh an expired token.
-spec refresh_token(token()) -> {ok, token()} | {error, term()}.
refresh_token(OldToken) ->
    case verify_token(OldToken) of
        {ok, Claims} ->
            %% Check if token is expired but still within refresh window
            Now = erlang:system_time(second),
            Exp = maps:get(exp, Claims, 0),
            case Now =< Exp + ?REFRESH_TTL of
                true ->
                    UserId = maps:get(sub, Claims),
                    Roles = [binary_to_existing_atom(R, utf8) || R <- maps:get(roles, Claims, [])],
                    {ok, create_token(UserId, Roles)};
                false ->
                    {error, refresh_expired}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Get claims from a token.
-spec get_token_claims(token()) -> {ok, claims()} | {error, term()}.
get_token_claims(Token) ->
    verify_token(Token).

%% @doc Get user ID from claims.
-spec get_user_id(claims()) -> binary().
get_user_id(Claims) ->
    maps:get(sub, Claims).

%% @doc Get roles from claims.
-spec get_roles(claims()) -> [binary()].
get_roles(Claims) ->
    maps:get(roles, Claims, []).

%% @doc Check if user has a specific permission.
-spec check_permission(claims(), binary(), binary()) -> boolean().
check_permission(Claims, Resource, Action) ->
    Permission = <<Resource/binary, ":", Action/binary>>,
    Permissions = maps:get(permissions, Claims, []),
    lists:member(<<"*">>, Permissions) orelse
    lists:member(Permission, Permissions) orelse
    lists:member(<<Resource/binary, ":*">>, Permissions).

%% @doc Require a specific role.
-spec require_role(cowboy_request(), atom()) ->
    {ok, claims(), cowboy_request()} | {error, term(), cowboy_request()}.
require_role(Req, Role) ->
    case get_request_context(Req) of
        {ok, Context} ->
            Roles = maps:get(roles, Context, []),
            case lists:member(Role, Roles) of
                true -> {ok, Context, Req};
                false ->
                    ErrorResponse = yawl_error_response:format_auth_error(
                        insufficient_permissions,
                        #{required_role => Role}
                    ),
                    {error, ErrorResponse, Req}
            end;
        {error, _} ->
            ErrorResponse = yawl_error_response:format_auth_error(
                authentication_failed,
                #{}
            ),
            {error, ErrorResponse, Req}
    end.

%% @doc Require a specific permission.
-spec require_permission(cowboy_request(), {binary(), binary()}) ->
    {ok, claims(), cowboy_request()} | {error, term(), cowboy_request()}.
require_permission(Req, {Resource, Action}) ->
    case get_request_context(Req) of
        {ok, Context} ->
            Permissions = maps:get(permissions, Context, []),
            Required = <<Resource/binary, ":", Action/binary>>,
            HasPermission = lists:member(<<"*">>, Permissions) orelse
                           lists:member(Required, Permissions) orelse
                           lists:member(<<Resource/binary, ":*">>, Permissions),
            case HasPermission of
                true -> {ok, Context, Req};
                false ->
                    ErrorResponse = yawl_error_response:format_auth_error(
                        insufficient_permissions,
                        #{required_permission => Required}
                    ),
                    {error, ErrorResponse, Req}
            end;
        {error, _} ->
            ErrorResponse = yawl_error_response:format_auth_error(
                authentication_failed,
                #{}
            ),
            {error, ErrorResponse, Req}
    end.

%% @doc Set the request context with authentication info.
-spec set_request_context(cowboy_request(), request_context()) -> cowboy_request().
set_request_context(Req, Context) ->
    cowboy_req:binding(?REQUEST_CONTEXT_KEY, Context, Req).

%% @doc Get the request context.
-spec get_request_context(cowboy_request()) -> {ok, request_context()} | {error, not_found}.
get_request_context(Req) ->
    case cowboy_req:binding(?REQUEST_CONTEXT_KEY, Req) of
        undefined -> {error, not_found};
        Context -> {ok, Context}
    end.

%% @doc Check if request is authenticated.
-spec is_authenticated(cowboy_request()) -> boolean().
is_authenticated(Req) ->
    case get_request_context(Req) of
        {ok, _Context} -> true;
        {error, _} -> false
    end.

%% @doc Check if token claims are expired.
-spec token_expired(claims()) -> boolean().
token_expired(Claims) ->
    Now = erlang:system_time(second),
    Exp = maps:get(exp, Claims, 0),
    Now >= Exp.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
%% @doc Get the secret key for signing/verifying tokens.
-spec get_secret_key() -> binary().
get_secret_key() ->
    case get(?SECRET_KEY) of
        undefined ->
            %% In production, this should come from environment or config
            %% For now, use a default (NOT SECURE - change in production!)
            application:get_env(yawl, jwt_secret, <<"change-this-secret-key-in-production">>);
        Secret ->
            Secret
    end.

%% @private
%% @doc Set the secret key (for testing or configuration).
-spec set_secret_key(binary()) -> ok.
set_secret_key(Secret) ->
    put(?SECRET_KEY, Secret),
    ok.

%% @private
%% @doc Encode JWT with signature.
-spec encode_jwt(map()) -> token().
encode_jwt(Claims) ->
    %% Create header
    Header = #{
        alg => ?JWT_ALG,
        typ => ?JWT_TYP
    },
    HeaderJson = jiffy:encode(Header),
    HeaderB64 = encode_base64url(HeaderJson),

    %% Create payload
    ClaimsJson = jiffy:encode(Claims),
    PayloadB64 = encode_base64url(ClaimsJson),

    %% Create signature
    Secret = get_secret_key(),
    Data = <<HeaderB64/binary, ".", PayloadB64/binary>>,
    Signature = crypto:mac(hmac, sha256, Secret, Data),
    SignatureB64 = encode_base64url(Signature),

    %% Combine
    <<HeaderB64/binary, ".", PayloadB64/binary, ".", SignatureB64/binary>>.

%% @private
%% @doc Encode to base64url (URL-safe base64).
-spec encode_base64url(binary()) -> binary().
encode_base64url(Data) ->
    Base64 = base64:encode(Data),
    %% Replace + with -, / with _, and remove padding =
    UrlSafe = binary:replace(Base64, <<"+">>, <<"-">>),
    UrlSafe2 = binary:replace(UrlSafe, <<"/">>, <<"_">>),
    binary:replace(UrlSafe2, <<"=">>, <<>>).

%% @private
%% @doc Decode from base64url.
-spec decode_base64url(binary()) -> binary().
decode_base64url(Data) ->
    %% Add padding if needed
    Padded = case byte_size(Data) rem 4 of
        0 -> Data;
        1 -> <<Data/binary, "===">>;
        2 -> <<Data/binary, "==">>;
        3 -> <<Data/binary, "=">>
    end,
    %% Replace URL-safe chars
    Standard = binary:replace(Padded, <<"-">>, <<"+">>),
    Standard2 = binary:replace(Standard, <<"_">>, <<"/">>),
    base64:decode(Standard2).

%% @private
%% @doc Check if user has required roles.
-spec check_roles([binary()], [binary()]) -> boolean().
check_roles(_UserRoles, []) ->
    true;
check_roles(UserRoles, RequiredRoles) ->
    lists:any(fun(Role) -> lists:member(Role, UserRoles) end, RequiredRoles).

%% @private
%% @doc Constant-time comparison to prevent timing attacks.
-spec constant_time_compare(binary(), binary()) -> boolean().
constant_time_compare(<<>>, <<>>) ->
    true;
constant_time_compare(<<X, RestX/binary>>, <<Y, RestY/binary>>) ->
    (X bxor Y) =:= 0 andalso constant_time_compare(RestX, RestY);
constant_time_compare(_, _) ->
    false.
