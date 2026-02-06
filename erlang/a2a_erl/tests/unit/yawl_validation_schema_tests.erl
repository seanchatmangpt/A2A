%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Validation Schema Unit Tests
%%%
%%% Test suite for the validation schema module.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_validation_schema_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Generators
%%====================================================================

validate_workflow_create_test_() ->
    ValidData = #{
        <<"pattern_type">> => basic_sequential,
        <<"config">> => #{task1_name => <<"task1">>},
        <<"timeout">> => 30000,
        <<"retry_policy">> => #{max_attempts => 3}
    },
    Result = yawl_validation_schema:validate_workflow_create(ValidData),
    ?_assertMatch({ok, _}, Result).

validate_workflow_create_missing_required_test_() ->
    InvalidData = #{config => #{}},
    Result = yawl_validation_schema:validate_workflow_create(InvalidData),
    ?_assertMatch({error, _}, Result),
    case Result of
        {error, Errors} ->
            ?_assert(lists:any(fun(E) ->
                binary:part(E, 0, byte_size(<<"pattern_type">>)) =:= <<"pattern_type">>
            end, Errors));
        _ ->
            ?_assert(false)
    end.

validate_workflow_create_invalid_pattern_test_() ->
    InvalidData = #{<<"pattern_type">> => invalid_pattern},
    Result = yawl_validation_schema:validate_workflow_create(InvalidData),
    ?_assertMatch({error, _}, Result).

validate_workflow_create_invalid_timeout_test_() ->
    InvalidData = #{
        <<"pattern_type">> => basic_sequential,
        <<"timeout">> => -100
    },
    Result = yawl_validation_schema:validate_workflow_create(InvalidData),
    ?_assertMatch({error, _}, Result).

validate_resource_create_test_() ->
    ValidData = #{
        <<"name">> => <<"test-resource">>,
        <<"type">> => human,
        <<"capabilities">> => [skill1, skill2],
        <<"max_capacity">> => 10
    },
    Result = yawl_validation_schema:validate_resource_create(ValidData),
    ?_assertMatch({ok, _}, Result).

validate_resource_create_missing_name_test_() ->
    InvalidData = #{
        <<"type">> => human
    },
    Result = yawl_validation_schema:validate_resource_create(InvalidData),
    ?_assertMatch({error, _}, Result).

validate_resource_create_invalid_capacity_test_() ->
    InvalidData = #{
        <<"name">> => <<"test">>,
        <<"type">> => human,
        <<"max_capacity">> => 0
    },
    Result = yawl_validation_schema:validate_resource_create(InvalidData),
    ?_assertMatch({error, _}, Result).

validate_task_create_test_() ->
    ValidData = #{
        <<"workflow_id">> <<"workflow-123">>,
        <<"task_name">> <<"test task">>,
        <<"priority">> => high
    },
    Result = yawl_validation_schema:validate_task_create(ValidData),
    ?_assertMatch({ok, _}, Result).

validate_task_create_missing_workflow_test_() ->
    InvalidData = #{
        <<"task_name">> <<"test task">>
    },
    Result = yawl_validation_schema:validate_task_create(InvalidData),
    ?_assertMatch({error, _}, Result).

validate_task_complete_test_() ->
    ValidData = #{
        <<"workitem_id">> <<"workitem-123">>,
        <<"result">> => #{status => completed},
        <<"comments">> <<"Task completed successfully">>
    },
    Result = yawl_validation_schema:validate_task_complete(ValidData),
    ?_assertMatch({ok, _}, Result).

validate_task_complete_missing_workitem_test_() ->
    InvalidData = #{result => #{}},
    Result = yawl_validation_schema:validate_task_complete(InvalidData),
    ?_assertMatch({error, _}, Result).

validate_query_params_workflow_list_test_() ->
    ValidParams = #{
        <<"status">> => running,
        <<"limit">> => 50,
        <<"offset">> => 0
    },
    Result = yawl_validation_schema:validate_query_params(workflow_list, ValidParams),
    ?_assertMatch({ok, _}, Result).

validate_query_params_invalid_limit_test_() ->
    InvalidParams = #{<<"limit">> => 2000},
    Result = yawl_validation_schema:validate_query_params(workflow_list, InvalidParams),
    ?_assertMatch({error, _}, Result).

validate_enum_test_() ->
    ?_assertMatch({ok, pending}, yawl_validation_schema:validate_enum(<<"status">>, <<"pending">>, [pending, running, completed])),
    ?_assertMatch({error, _}, yawl_validation_schema:validate_enum(<<"status">>, <<"invalid">>, [pending, running])).

validate_range_test_() ->
    ?_assertMatch({ok, 50}, yawl_validation_schema:validate_range(<<"limit">>, 50, 1, 100)),
    ?_assertMatch({error, _}, yawl_validation_schema:validate_range(<<"limit">>, 0, 1, 100)),
    ?_assertMatch({error, _}, yawl_validation_schema:validate_range(<<"limit">>, 101, 1, 100)).

validate_field_type_test_() ->
    ?_assertMatch({ok, <<"test">>}, yawl_validation_schema:validate_field_type(<<"name">>, <<"test">>, binary)),
    ?_assertMatch({ok, test}, yawl_validation_schema:validate_field_type(<<"status">>, test, atom)),
    ?_assertMatch({ok, 42}, yawl_validation_schema:validate_field_type(<<"count">>, 42, integer)),
    ?_assertMatch({ok, 3.14}, yawl_validation_schema:validate_field_type(<<"ratio">>, 3.14, float)),
    ?_assertMatch({error, _}, yawl_validation_schema:validate_field_type(<<"status">>, <<"invalid">>, {atom, [pending, running]})).

validate_schema_test_() ->
    Schema = #{
        required => [<<"name">>],
        optional => [{<<"age">>, 0}],
        types => #{<<"name">> => binary, <<"age">> => integer},
        constraints => #{<<"name">> => fun(V) -> byte_size(V) > 0 end}
    },
    ?_assertMatch({ok, #{<<"name">> := <<"Bob">>, <<"age">> := 30}},
        yawl_validation_schema:validate_schema(Schema, #{<<"name">> => <<"Bob">>, <<"age">> => 30})),
    ?_assertMatch({ok, #{<<"name">> := <<"Bob">>, <<"age">> := 0}},
        yawl_validation_schema:validate_schema(Schema, #{<<"name">> => <<"Bob">>})),
    ?_assertMatch({error, _}, yawl_validation_schema:validate_schema(Schema, #{})).

is_valid_url_test_() ->
    ?_assertEqual(true, yawl_validation_schema:is_valid_url(<<"http://example.com">>)),
    ?_assertEqual(true, yawl_validation_schema:is_valid_url(<<"https://example.com/path">>)),
    ?_assertEqual(false, yawl_validation_schema:is_valid_url(<<"not-a-url">>)),
    ?_assertEqual(false, yawl_validation_schema:is_valid_url(<<"ftp://example.com">>)),
    ?_assertEqual(false, yawl_validation_schema:is_valid_url(<<>>)).
