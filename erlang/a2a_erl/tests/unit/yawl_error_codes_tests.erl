%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Error Codes Unit Tests
%%%
%%% Test suite for the error code registry module.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_error_codes_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Generators
%%====================================================================

error_info_test_() ->
    [
     ?_assertEqual(400, (yawl_error_codes:http_status(validation_failed))),
     ?_assertEqual(validation, (yawl_error_codes:error_category(validation_failed))),
     ?_assertEqual(<<"Request validation failed">>, (yawl_error_codes:error_message(validation_failed))),
     ?_assertEqual(validation_failed, (yawl_error_codes:error_code(validation_failed)))
    ].

not_found_errors_test_() ->
    [
     ?_assertEqual(404, (yawl_error_codes:http_status(workflow_not_found))),
     ?_assertEqual(404, (yawl_error_codes:http_status(resource_not_found))),
     ?_assertEqual(404, (yawl_error_codes:http_status(task_not_found))),
     ?_assertEqual(not_found, (yawl_error_codes:error_category(workflow_not_found)))
    ].

authentication_errors_test_() ->
    [
     ?_assertEqual(401, (yawl_error_codes:http_status(authentication_failed))),
     ?_assertEqual(401, (yawl_error_codes:http_status(invalid_token))),
     ?_assertEqual(401, (yawl_error_codes:http_status(token_expired))),
     ?_assertEqual(authentication, (yawl_error_codes:error_category(authentication_failed)))
    ].

authorization_errors_test_() ->
    [
     ?_assertEqual(403, (yawl_error_codes:http_status(insufficient_permissions))),
     ?_assertEqual(403, (yawl_error_codes:http_status(access_denied))),
     ?_assertEqual(authorization, (yawl_error_codes:error_category(insufficient_permissions)))
    ].

conflict_errors_test_() ->
    [
     ?_assertEqual(409, (yawl_error_codes:http_status(workflow_conflict))),
     ?_assertEqual(409, (yawl_error_codes:http_status(resource_conflict))),
     ?_assertEqual(conflict, (yawl_error_codes:error_category(workflow_conflict)))
    ].

server_errors_test_() ->
    [
     ?_assertEqual(500, (yawl_error_codes:http_status(internal_server_error))),
     ?_assertEqual(500, (yawl_error_codes:http_status(orchestration_error))),
     ?_assertEqual(500, (yawl_error_codes:http_status(persistence_error))),
     ?_assertEqual(server_error, (yawl_error_codes:error_category(internal_server_error)))
    ].

format_error_test_() ->
    ErrorResponse = yawl_error_codes:format_error(validation_failed),
    [
     ?_assertEqual(true, (is_map(ErrorResponse))),
     ?_assert(maps:is_key(<<"error_code">>, ErrorResponse)),
     ?_assert(maps:is_key(<<"error_category">>, ErrorResponse)),
     ?_assert(maps:is_key(<<"message">>, ErrorResponse)),
     ?_assert(maps:is_key(<<"http_status">>, ErrorResponse))
    ].

format_error_with_details_test_() ->
    Details = #{field => <<"pattern_type">>, expected => <<"atom">>},
    ErrorResponse = yawl_error_codes:format_error(invalid_field_type, Details),
    ?_assertEqual(400, (maps:get(<<"http_status">>, ErrorResponse))),
    ?_assert(maps:is_key(<<"details">>, ErrorResponse)).

format_error_with_custom_message_test_() ->
    CustomMessage = <<"Custom error message">>,
    ErrorResponse = yawl_error_codes:format_error(validation_failed, CustomMessage),
    ?_assertEqual(CustomMessage, (maps:get(<<"message">>, ErrorResponse))).

is_client_error_test_() ->
    [
     ?_assertEqual(true, (yawl_error_codes:is_client_error(validation_failed))),
     ?_assertEqual(true, (yawl_error_codes:is_client_error(authentication_failed))),
     ?_assertEqual(true, (yawl_error_codes:is_client_error(workflow_not_found))),
     ?_assertEqual(false, (yawl_error_codes:is_client_error(internal_server_error)))
    ].

is_server_error_test_() ->
    [
     ?_assertEqual(false, (yawl_error_codes:is_server_error(validation_failed))),
     ?_assertEqual(false, (yawl_error_codes:is_server_error(authentication_failed))),
     ?_assertEqual(true, (yawl_error_codes:is_server_error(internal_server_error))),
     ?_assertEqual(true, (yawl_error_codes:is_server_error(orchestration_error)))
    ].

all_error_codes_test_() ->
    AllCodes = yawl_error_codes:all_error_codes(),
    ?_assert(lists:member(validation_failed, AllCodes)),
    ?_assert(lists:member(workflow_not_found, AllCodes)),
    ?_assert(lists:member(internal_server_error, AllCodes)),
    ?_assert(length(AllCodes) > 30).

errors_by_category_test_() ->
    ValidationErrors = yawl_error_codes:errors_by_category(validation),
    ?_assert(lists:member(validation_failed, ValidationErrors)),
    ?_assert(lists:member(invalid_json, ValidationErrors)),
    ?_assert(lists:member(missing_required_field, ValidationErrors)),

    AuthErrors = yawl_error_codes:errors_by_category(authentication),
    ?_assert(lists:member(authentication_failed, AuthErrors)),
    ?_assert(lists:member(invalid_token, AuthErrors)).

unknown_error_test_() ->
    Info = yawl_error_codes:error_info(unknown_error),
    ?_assertEqual(server_error, (maps:get(category, Info))),
    ?_assertEqual(500, (maps:get(http_status, Info))).
