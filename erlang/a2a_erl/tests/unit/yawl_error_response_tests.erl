%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Error Response Unit Tests
%%%
%%% Test suite for the error response formatter module.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_error_response_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Generators
%%====================================================================

format_error_test_() ->
    ErrorResponse = yawl_error_response:format_error(validation_failed),
    [
     ?_assertEqual(true, (maps:get(error, ErrorResponse))),
     ?_assertEqual(<<"validation_failed">>, (maps:get(error_code, ErrorResponse))),
     ?_assertEqual(<<"validation">>, (maps:get(error_category, ErrorResponse))),
     ?_assertEqual(400, (maps:get(http_status, ErrorResponse))),
     ?_assert(maps:is_key(<<"message">>, ErrorResponse)),
     ?_assert(maps:is_key(<<"timestamp">>, ErrorResponse)),
     ?_assert(maps:is_key(<<"request_id">>, ErrorResponse))
    ].

format_error_with_details_test_() ->
    Details = #{field => <<"pattern_type">>, value => <<"invalid">>},
    ErrorResponse = yawl_error_response:format_error(invalid_field_value, Details),
    ?_assertEqual(<<"invalid_field_value">>, (maps:get(error_code, ErrorResponse))),
    ?_assert(maps:is_key(<<"details">>, ErrorResponse)).

format_validation_error_test_() ->
    Field = <<"pattern_type">>,
    Errors = [<<"Invalid pattern type">>, <<"Must be an atom">>],
    ErrorResponse = yawl_error_response:format_validation_error(Field, Errors),
    ?_assertEqual(<<"validation_failed">>, (maps:get(error_code, ErrorResponse))),
    ?_assertEqual(Field, (maps:get(field, (maps:get(details, ErrorResponse))))).

format_auth_error_test_() ->
    Details = #{token => <<"expired">>},
    ErrorResponse = yawl_error_response:format_auth_error(token_expired, Details),
    ?_assertEqual(<<"token_expired">>, (maps:get(error_code, ErrorResponse))),
    ?_assertEqual(<<"authentication">>, (maps:get(error_category, ErrorResponse))),
    ?_assertEqual(401, (maps:get(http_status, ErrorResponse))).

format_not_found_error_test_() ->
    ResourceType = <<"workflow">>,
    Details = #{workflow_id => <<"12345">>},
    ErrorResponse = yawl_error_response:format_not_found_error(ResourceType, Details),
    ?_assertEqual(<<"workflow_not_found">>, (maps:get(error_code, ErrorResponse))),
    ?_assertEqual(<<"not_found">>, (maps:get(error_category, ErrorResponse))),
    ?_assertEqual(404, (maps:get(http_status, ErrorResponse))).

format_conflict_error_test_() ->
    ConflictType = <<"workflow">>,
    Details = #{reason => <<"already_running">>},
    ErrorResponse = yawl_error_response:format_conflict_error(ConflictType, Details),
    ?_assertEqual(<<"conflict">>, (maps:get(error_category, ErrorResponse))),
    ?_assertEqual(409, (maps:get(http_status, ErrorResponse))).

to_json_test_() ->
    ErrorResponse = yawl_error_response:format_error(validation_failed),
    Json = yawl_error_response:to_json(ErrorResponse),
    ?_assert(is_binary(Json)),
    ?_assertEqual(<<${>>, (binary:at(Json, 0))),
    ?_assertEqual(<<$}>>, (binary:at(Json, byte_size(Json) - 1))).

request_id_test_() ->
    RequestId = yawl_error_response:get_request_id(),
    ?_assert(is_binary(RequestId)),
    ?_assert(byte_size(RequestId) > 0).

set_request_id_test_() ->
    TestId = <<"test-request-id-12345">>,
    ?assertEqual(ok, yawl_error_response:set_request_id(TestId)),
    ?assertEqual(TestId, yawl_error_response:get_request_id()).

timestamp_test_() ->
    ErrorResponse = yawl_error_response:format_error(validation_failed),
    Timestamp = maps:get(<<"timestamp">>, ErrorResponse),
    ?_assert(is_binary(Timestamp)),
    ?assertEqual(<<$T>>, (binary:at(Timestamp, 10))),
    ?assertEqual(<<$Z>>, (binary:at(Timestamp, byte_size(Timestamp) - 1))).

format_rate_limit_error_test_() ->
    RetryAfter = 3600,
    Details = #{limit => 100, window => <<"1h">>},
    ErrorResponse = yawl_error_response:format_rate_limit_error(RetryAfter, Details),
    ?_assertEqual(<<"rate_limit_exceeded">>, (maps:get(error_code, ErrorResponse))),
    ?_assertEqual(429, (maps:get(http_status, ErrorResponse))),
    ?_assertEqual(RetryAfter, (maps:get(retry_after, (maps:get(details, ErrorResponse))))).
