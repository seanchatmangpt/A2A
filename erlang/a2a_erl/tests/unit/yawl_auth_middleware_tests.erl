%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Auth Middleware Unit Tests
%%%
%%% Test suite for the JWT authentication middleware module.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_auth_middleware_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Setup and Teardown
%%====================================================================

setup() ->
    %% Set a test secret key
    yawl_auth_middleware:set_secret_key(<<"test-secret-key-for-unit-tests">>),
    ok.

cleanup(_) ->
    %% Reset secret key
    yawl_auth_middleware:set_secret_key(<<"test-secret-key-for-unit-tests">>),
    ok.

%%====================================================================
%% Test Generators
%%====================================================================

create_token_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        UserId = <<"user-123">>,
        Roles = [admin, user],
        Token = yawl_auth_middleware:create_token(UserId, Roles),
        ?_assert(is_binary(Token)),
        ?_assertEqual(3, length(binary:split(Token, <<$.>>)))  % Header.Payload.Signature
    end}.

create_token_with_options_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        UserId = <<"user-456">>,
        Roles = [viewer],
        Options = #{ttl => 7200, issuer => <<"test-issuer">>},
        Token = yawl_auth_middleware:create_token(UserId, Roles, Options),
        ?_assert(is_binary(Token)),
        {ok, Claims} = yawl_auth_middleware:verify_token(Token),
        ?_assertEqual(<<"test-issuer">>, (maps:get(<<"iss">>, Claims))),
        ?_assertEqual(UserId, (maps:get(<<"sub">>, Claims)))
    end}.

verify_token_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        UserId = <<"user-789">>,
        Roles = [],
        Token = yawl_auth_middleware:create_token(UserId, Roles),
        ?_assertMatch({ok, _}, yawl_auth_middleware:verify_token(Token)),
        {ok, Claims} = yawl_auth_middleware:verify_token(Token),
        ?_assertEqual(UserId, (maps:get(<<"sub">>, Claims)))
    end}.

verify_token_invalid_signature_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        InvalidToken = <<"invalid.token.here">>,
        ?_assertMatch({error, _}, yawl_auth_middleware:verify_token(InvalidToken))
    end}.

validate_token_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        UserId = <<"user-999">>,
        Roles = [user],
        Token = yawl_auth_middleware:create_token(UserId, Roles),
        ?_assertMatch({ok, _}, yawl_auth_middleware:validate_token(Token))
    end}.

validate_token_expired_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        %% Create a token that's already expired
        UserId = <<"user-expired">>,
        Roles = [],
        Options = #{ttl => -1},  %% Negative TTL means expired
        Token = yawl_auth_middleware:create_token(UserId, Roles, Options),
        ?_assertEqual({error, token_expired}, yawl_auth_middleware:validate_token(Token))
    end}.

get_user_id_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        UserId = <<"user-111">>,
        Roles = [],
        Token = yawl_auth_middleware:create_token(UserId, Roles),
        {ok, Claims} = yawl_auth_middleware:verify_token(Token),
        ?_assertEqual(UserId, yawl_auth_middleware:get_user_id(Claims))
    end}.

get_roles_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        Roles = [admin, moderator, user],
        Token = yawl_auth_middleware:create_token(<<"user-222">>, Roles),
        {ok, Claims} = yawl_auth_middleware:verify_token(Token),
        RetrievedRoles = yawl_auth_middleware:get_roles(Claims),
        ?_assertEqual(3, length(RetrievedRoles)),
        ?_assert(lists:member(<<"admin">>, RetrievedRoles))
    end}.

check_permission_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        Permissions = [<<"workflow:read">>, <<"workflow:write">>],
        Token = yawl_auth_middleware:create_token(<<"user-333">>, [], #{permissions => Permissions}),
        {ok, Claims} = yawl_auth_middleware:verify_token(Token),
        ?_assertEqual(true, yawl_auth_middleware:check_permission(Claims, <<"workflow">>, <<"read">>)),
        ?_assertEqual(true, yawl_auth_middleware:check_permission(Claims, <<"workflow">>, <<"write">>)),
        ?_assertEqual(false, yawl_auth_middleware:check_permission(Claims, <<"workflow">>, <<"delete">>))
    end}.

check_permission_wildcard_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        Permissions = [<<"*">>],
        Token = yawl_auth_middleware:create_token(<<"user-444">>, [], #{permissions => Permissions}),
        {ok, Claims} = yawl_auth_middleware:verify_token(Token),
        ?_assertEqual(true, yawl_auth_middleware:check_permission(Claims, <<"anything">>, <<"any-action">>))
    end}.

check_permission_resource_wildcard_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        Permissions = [<<"workflow:*">>],
        Token = yawl_auth_middleware:create_token(<<"user-555">>, [], #{permissions => Permissions}),
        {ok, Claims} = yawl_auth_middleware:verify_token(Token),
        ?_assertEqual(true, yawl_auth_middleware:check_permission(Claims, <<"workflow">>, <<"any-action">>)),
        ?_assertEqual(false, yawl_auth_middleware:check_permission(Claims, <<"resource">>, <<"read">>))
    end}.

token_expired_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        %% Create a token with 1 second TTL and wait
        Token = yawl_auth_middleware:create_token(<<"user-666">>, [], #{ttl => 1}),
        timer:sleep(1100),  %% Wait 1.1 seconds
        {ok, Claims} = yawl_auth_middleware:verify_token(Token),
        ?_assertEqual(true, yawl_auth_middleware:token_expired(Claims))
    end}.

token_not_expired_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        %% Create a token with 3600 second TTL
        Token = yawl_auth_middleware:create_token(<<"user-777">>, [], #{ttl => 3600}),
        {ok, Claims} = yawl_auth_middleware:verify_token(Token),
        ?_assertEqual(false, yawl_auth_middleware:token_expired(Claims))
    end}.

refresh_token_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(_) ->
        UserId = <<"user-888">>,
        Roles = [user],
        OldToken = yawl_auth_middleware:create_token(UserId, Roles, #{ttl => 3600}),
        ?_assertMatch({ok, _}, yawl_auth_middleware:refresh_token(OldToken)),
        {ok, NewToken} = yawl_auth_middleware:refresh_token(OldToken),
        ?_assert(is_binary(NewToken)),
        ?_assertNotEqual(OldToken, NewToken)
    end}.

encode_base64url_test_() ->
    Input = <<"test data">>,
    Encoded = yawl_auth_middleware:encode_base64url(Input),
    [?_assert(is_binary(Encoded)),
     ?_assertEqual(nomatch, binary:match(Encoded, <<$+>>)),
     ?_assertEqual(nomatch, binary:match(Encoded, <<$/>>)),
     ?_assertEqual(0, byte_size(Encoded) rem 4)].

decode_base64url_test_() ->
    Input = <<"test data">>,
    Encoded = yawl_auth_middleware:encode_base64url(Input),
    Decoded = yawl_auth_middleware:decode_base64url(Encoded),
    [?_assertEqual(Input, Decoded)].
