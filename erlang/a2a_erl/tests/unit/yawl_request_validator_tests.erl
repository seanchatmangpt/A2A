%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Request Validator Unit Tests
%%%
%%% Test suite for the request validator middleware module.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_request_validator_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%% Mock Cowboy request record for testing
-record(cowboy_req, {
    method = <<"GET">>,
    body = <<>>,
    headers = #{},
    qs = <<>>
}).

%%====================================================================
%% Test Generators
%%====================================================================

%% Helper to create a mock request
create_mock_req(Method, Body, Headers, Qs) ->
    #cowboy_req{
        method = Method,
        body = Body,
        headers = Headers,
        qs = Qs
    }.

validate_json_body_valid_test() ->
    ValidJson = <<"{\"pattern_type\": \"basic_sequential\", \"config\": {}}">>,
    Req = create_mock_req(<<"POST">>, ValidJson, #{<<"content-type">> => <<"application/json">>}, <<>>),
    Result = yawl_request_validator:validate_json_body(Req),
    ?assertMatch({ok, _, _}, Result).

validate_json_body_invalid_test() ->
    InvalidJson = <<"{invalid json}">>,
    Req = create_mock_req(<<"POST">>, InvalidJson, #{<<"content-type">> => <<"application/json">>}, <<>>),
    Result = yawl_request_validator:validate_json_body(Req),
    ?assertMatch({error, _, _}, Result).

validate_json_body_empty_test() ->
    Req = create_mock_req(<<"POST">>, <<>>, #{<<"content-type">> => <<"application/json">>}, <<>>),
    Result = yawl_request_validator:validate_json_body(Req),
    ?assertMatch({error, _, _}, Result).

validate_json_body_empty_allowed_test() ->
    Req = create_mock_req(<<"POST">>, <<>>, #{<<"content-type">> => <<"application/json">>}, <<>>),
    Result = yawl_request_validator:validate_json_body(Req, #{allow_empty => true}),
    ?assertMatch({ok, #{}, _}, Result).

validate_query_params_test() ->
    Params = #{<<"status">> => <<"running">>, <<"limit">> => <<"50">>},
    Result = yawl_validation_schema:validate_query_params(workflow_list, Params),
    ?assertMatch({ok, _}, Result).

validate_query_params_invalid_limit_test() ->
    Params = #{<<"limit">> => <<"2000">>},
    Result = yawl_validation_schema:validate_query_params(workflow_list, Params),
    ?assertMatch({error, _}, Result).

validate_field_type_binary_test() ->
    ?assertMatch({ok, <<"test">>}, yawl_validation_schema:validate_field_type(<<"name">>, <<"test">>, binary)).

validate_field_type_atom_test() ->
    ?assertMatch({ok, test}, yawl_validation_schema:validate_field_type(<<"status">>, test, atom)).

validate_field_type_integer_test() ->
    ?assertMatch({ok, 42}, yawl_validation_schema:validate_field_type(<<"count">>, 42, integer)).

validate_field_type_map_test() ->
    ?assertMatch({ok, #{}}, yawl_validation_schema:validate_field_type(<<"data">>, #{}, map)).

validate_field_type_list_test() ->
    ?assertMatch({ok, []}, yawl_validation_schema:validate_field_type(<<"items">>, [], list)).

validate_field_type_invalid_test() ->
    ?assertMatch({error, _}, yawl_validation_schema:validate_field_type(<<"status">>, 123, binary)).

validate_enum_valid_test() ->
    ?assertMatch({ok, pending}, yawl_validation_schema:validate_enum(<<"status">>, <<"pending">>, [pending, running])).

validate_enum_invalid_test() ->
    ?assertMatch({error, _}, yawl_validation_schema:validate_enum(<<"status">>, <<"invalid">>, [pending, running])).

validate_range_valid_test() ->
    ?assertMatch({ok, 50}, yawl_validation_schema:validate_range(<<"limit">>, 50, 1, 100)).

validate_range_below_min_test() ->
    ?assertMatch({error, _}, yawl_validation_schema:validate_range(<<"limit">>, 0, 1, 100)).

validate_range_above_max_test() ->
    ?assertMatch({error, _}, yawl_validation_schema:validate_range(<<"limit">>, 101, 1, 100)).

sanitize_input_xss_test() ->
    Malicious = <<"<script>alert('xss')</script>">>,
    Sanitized = yawl_request_validator:sanitize_input(Malicious),
    ?assertNotEqual(Malicious, Sanitized),
    ?assertEqual(<<>>, binary:match(Sanitized, <<"script">>)).

sanitize_input_map_test() ->
    Input = #{<<"name">> => <<"<script>alert('xss')</script>">>, <<"age">> => 25},
    Sanitized = yawl_request_validator:sanitize_input(Input),
    ?assertEqual(25, maps:get(<<"age">>, Sanitized)),
    ?assertNotEqual(<<"<script>alert('xss')</script>">>, maps:get(<<"name">>, Sanitized)).

sanitize_input_list_test() ->
    Input = [<<"<script>alert('xss')</script>">>, <<"normal">>],
    Sanitized = yawl_request_validator:sanitize_input(Input),
    ?assertEqual(2, length(Sanitized)).

max_body_size_test() ->
    DefaultSize = yawl_request_validator:max_body_size(),
    ?assert(is_integer(DefaultSize)),
    ?assert(DefaultSize > 0).

set_max_body_size_test() ->
    ?assertEqual(ok, yawl_request_validator:set_max_body_size(2048)),
    ?assertEqual(2048, yawl_request_validator:max_body_size()),
    %% Reset to default
    ?assertEqual(ok, yawl_request_validator:set_max_body_size(10485760)).
