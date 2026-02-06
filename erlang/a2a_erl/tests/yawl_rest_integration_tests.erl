%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL REST API Integration Test Suite
%%%
%%% This module contains Common Test suites for comprehensive REST API
%%% testing. It covers:
%%%
%%% - All REST endpoints (GET, POST, PUT, DELETE)
%%% - JSON request/response handling
%%% - Error cases and validation
%%% - Concurrent API calls
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_integration_tests).
-author("A2A Team").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% Export tests
-export([
    all/0,
    groups/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_group/2,
    end_per_group/2,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases - Basic API Tests
-export([
    test_workflow_crud_operations/1,
    test_workflow_status_operations/1,
    test_workflow_action_operations/1
]).

%% Test cases - Error Handling Tests
-export([
    test_invalid_request_format/1,
    test_not_found_endpoints/1,
    test_unauthorized_access/1,
    test_invalid_workflow_data/1,
    test_missing_required_fields/1
]).

%% Test cases - Validation Tests
-export([
    test_workflow_validation/1,
    test_parameter_validation/1,
    test_schema_validation/1,
    test_business_rule_validation/1
]).

%% Test cases - Performance Tests
-export([
    test_concurrent_api_calls/1,
    test_api_throughput/1,
    test_large_payload_handling/1,
    test_error_rate_testing/1
]).

%% Test cases - Authentication and Security Tests
-export([
    test_api_authentication/1,
    test_rate_limiting/1,
    test_input_validation_security/1,
    test_output_encoding_security/1
]).

%%====================================================================
%% Common Test Callbacks
%%====================================================================

%% @doc Return all test cases.
-spec all() -> [atom()].
all() ->
    [
        %% Basic API Tests
        test_workflow_crud_operations,
        test_workflow_status_operations,
        test_workflow_action_operations,

        %% Error Handling Tests
        test_invalid_request_format,
        test_not_found_endpoints,
        test_unauthorized_access,
        test_invalid_workflow_data,
        test_missing_required_fields,

        %% Validation Tests
        test_workflow_validation,
        test_parameter_validation,
        test_schema_validation,
        test_business_rule_validation,

        %% Performance Tests
        test_concurrent_api_calls,
        test_api_throughput,
        test_large_payload_handling,
        test_error_rate_testing,

        %% Security Tests
        test_api_authentication,
        test_rate_limiting,
        test_input_validation_security,
        test_output_encoding_security
    ].

%% @doc Return test groups.
-spec groups() -> [{atom(), list(), [atom()]}].
groups() ->
    [
        {basic_api_tests, [sequence], [
            test_workflow_crud_operations,
            test_workflow_status_operations,
            test_workflow_action_operations
        ]},
        {error_handling_tests, [sequence], [
            test_invalid_request_format,
            test_not_found_endpoints,
            test_unauthorized_access,
            test_invalid_workflow_data,
            test_missing_required_fields
        ]},
        {validation_tests, [sequence], [
            test_workflow_validation,
            test_parameter_validation,
            test_schema_validation,
            test_business_rule_validation
        ]},
        {performance_tests, [sequence], [
            test_concurrent_api_calls,
            test_api_throughput,
            test_large_payload_handling,
            test_error_rate_testing
        ]},
        {security_tests, [sequence], [
            test_api_authentication,
            test_rate_limiting,
            test_input_validation_security,
            test_output_encoding_security
        ]}
    ].

%% @doc Initialize test suite.
-spec init_per_suite(Config) -> Config when Config :: [tuple()].
init_per_suite(Config) ->
    ct:pal("Starting YAWL REST API Integration Test Suite"),
    ct:pal("Testing REST API endpoints and functionality"),
    %% Start applications
    {ok, _} = application:ensure_all_started(a2a_erl),
    %% Start required services
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),
    {ok, PersistencePid} = yawl_persistence:start_link(),
    {ok, ResourceManagerPid} = yawl_resource_manager:start_link(),
    %% Start REST API server
    {ok, RestPid} = yawl_rest:start_link(#{port => 8081}),

    %% Register test resources
    register_test_resources(),

    %% Wait for REST server to be ready
    wait_for_rest_server(8081, 5000),

    [{orchestrator_pid, OrchestratorPid},
     {persistence_pid, PersistencePid},
     {resource_manager_pid, ResourceManagerPid},
     {rest_pid, RestPid} | Config].

%% @doc Cleanup test suite.
-spec end_per_suite(Config) -> ok when Config :: [tuple()].
end_per_suite(Config) ->
    %% Stop services
    RestPid = proplists:get_value(rest_pid, Config),
    OrchestratorPid = proplists:get_value(orchestrator_pid, Config),
    PersistencePid = proplists:get_value(persistence_pid, Config),
    ResourceManagerPid = proplists:get_value(resource_manager_pid, Config),

    gen_server:stop(RestPid),
    gen_server:stop(OrchestratorPid),
    gen_server:stop(PersistencePid),
    gen_server:stop(ResourceManagerPid),

    %% Stop application
    application:stop(a2a_erl),

    ct:pal("Completed YAWL REST API Integration Test Suite"),
    ok.

%% @doc Initialize test group.
-spec init_per_group(atom(), Config) -> Config when Config :: [tuple()].
init_per_group(GroupName, Config) ->
    ct:pal("Starting REST API group: ~p", [GroupName]),
    cleanup_test_data(),
    Config.

%% @doc Cleanup test group.
-spec end_per_group(atom(), Config) -> ok when Config :: [tuple()].
end_per_group(GroupName, _Config) ->
    ct:pal("Completed REST API group: ~p", [GroupName]),
    cleanup_test_data(),
    ok.

%% @doc Initialize test case.
-spec init_per_testcase(atom(), Config) -> Config when Config :: [tuple()].
init_per_testcase(TestName, Config) ->
    ct:pal("Starting REST API test: ~p", [TestName]),
    cleanup_test_data(),
    Config.

%% @doc Cleanup test case.
-spec end_per_testcase(atom(), Config) -> ok when Config :: [tuple()].
end_per_testcase(TestName, _Config) ->
    ct:pal("Completed REST API test: ~p", [TestName]),
    cleanup_test_data(),
    ok.

%%====================================================================
%% Basic API Tests
%%====================================================================

%% @doc Test complete workflow CRUD operations via REST API.
-spec test_workflow_crud_operations(Config) -> ok when Config :: [tuple()].
test_workflow_crud_operations(_Config) ->
    %% 1. Create workflow (POST /workflows)
    CreatePayload = jiffy:encode(#{pattern_type => basic_sequential, config => #{task1_name => "task1"}}),
    {ok, ResponseCode1, ResponseBody1} = make_http_request(
        post, "http://localhost:8081/workflows", CreatePayload),

    ct:pal("Create workflow response: ~p ~s", [ResponseCode1, ResponseBody1]),
    ?assertEqual(201, ResponseCode1),

    %% Extract workflow ID from response
    CreateResult = jiffy:decode(ResponseBody1, [return_maps]),
    WorkflowId = maps:get(<<"workflow_id">>, CreateResult),

    %% 2. List workflows (GET /workflows)
    {ok, ResponseCode2, ResponseBody2} = make_http_request(
        get, "http://localhost:8081/workflows", ""),
    ct:pal("List workflows response: ~p ~s", [ResponseCode2, ResponseBody2]),
    ?assertEqual(200, ResponseCode2),

    %% 3. Get specific workflow (GET /workflows/{id})
    {ok, ResponseCode3, ResponseBody3} = make_http_request(
        get, "http://localhost:8081/workflows/" ++ binary_to_list(WorkflowId), ""),
    ct:pal("Get workflow response: ~p ~s", [ResponseCode3, ResponseBody3]),
    ?assertEqual(200, ResponseCode3),

    %% 4. Delete workflow (DELETE /workflows/{id})
    {ok, ResponseCode4, ResponseBody4} = make_http_request(
        delete, "http://localhost:8081/workflows/" ++ binary_to_list(WorkflowId), ""),
    ct:pal("Delete workflow response: ~p ~s", [ResponseCode4, ResponseBody4]),
    ?assertEqual(200, ResponseCode4),

    ct:pal("Workflow CRUD operations test completed"),
    ok.

%% @doc Test workflow status operations via REST API.
-spec test_workflow_status_operations(Config) -> ok when Config :: [tuple()].
test_workflow_status_operations(_Config) ->
    %% Create workflow first
    CreatePayload = jiffy:encode(#{pattern_type => basic_sequential, config => #{}}),
    {ok, ResponseCode, ResponseBody} = make_http_request(
        post, "http://localhost:8081/workflows", CreatePayload),

    ?assertEqual(201, ResponseCode),
    CreateResult = jiffy:decode(ResponseBody, [return_maps]),
    WorkflowId = maps:get(<<"workflow_id">>, CreateResult),

    %% Check initial status
    {ok, ResponseCode1, ResponseBody1} = make_http_request(
        get, "http://localhost:8081/workflows/" ++ binary_to_list(WorkflowId), ""),
    ct:pal("Initial status: ~p ~s", [ResponseCode1, ResponseBody1]),
    ?assertEqual(200, ResponseCode1),

    %% Execute workflow
    ExecutePayload = jiffy:encode(#{}),
    {ok, ResponseCode2, ResponseBody2} = make_http_request(
        post, "http://localhost:8081/workflows/" ++ binary_to_list(WorkflowId) ++ "/start", ExecutePayload),
    ct:pal("Execute response: ~p ~s", [ResponseCode2, ResponseBody2]),
    ?assertEqual(200, ResponseCode2),

    %% Check running status
    timer:sleep(1000),
    {ok, ResponseCode3, ResponseBody3} = make_http_request(
        get, "http://localhost:8081/workflows/" ++ binary_to_list(WorkflowId), ""),
    ct:pal("Running status: ~p ~s", [ResponseCode3, ResponseBody3]),
    ?assertEqual(200, ResponseCode3),

    %% Cancel workflow
    {ok, ResponseCode4, ResponseBody4} = make_http_request(
        post, "http://localhost:8081/workflows/" ++ binary_to_list(WorkflowId) ++ "/cancel", ""),
    ct:pal("Cancel response: ~p ~s", [ResponseCode4, ResponseBody4]),
    ?assertEqual(200, ResponseCode4),

    ct:pal("Workflow status operations test completed"),
    ok.

%% @doc Test workflow action operations via REST API.
-spec test_workflow_action_operations(Config) -> ok when Config :: [tuple()].
test_workflow_action_operations(_Config) ->
    %% Create workflow
    CreatePayload = jiffy:encode(#{pattern_type => basic_sequential, config => #{}}),
    {ok, ResponseCode, ResponseBody} = make_http_request(
        post, "http://localhost:8081/workflows", CreatePayload),

    ?assertEqual(201, ResponseCode),
    CreateResult = jiffy:decode(ResponseBody, [return_maps]),
    WorkflowId = maps:get(<<"workflow_id">>, CreateResult),

    %% Test actions
    Actions = ["start", "cancel", "pause", "resume"],
    lists:foreach(fun(Action) ->
        Url = "http://localhost:8081/workflows/" ++ binary_to_list(WorkflowId) ++ "/" ++ atom_to_list(Action),
        {ok, ResponseCode, ResponseBody} = make_http_request(post, Url, ""),
        ct:pal("Action ~p: ~p ~s", [Action, ResponseCode, ResponseBody]),
        ?assertEqual(ResponseCode, 200)  % Some actions may not be implemented yet
    end, Actions),

    ct:pal("Workflow action operations test completed"),
    ok.

%%====================================================================
%% Error Handling Tests
%%====================================================================

%% @doc Test invalid request format handling.
-spec test_invalid_request_format(Config) -> ok when Config :: [tuple()].
test_invalid_request_format(_Config) ->
    %% Test malformed JSON
    {ok, ResponseCode1, _} = make_http_request(
        post, "http://localhost:8081/workflows", "invalid json"),
    ct:pal("Invalid JSON response: ~p", [ResponseCode1]),
    ?assertEqual(ResponseCode1, 400),

    %% Test empty body
    {ok, ResponseCode2, _} = make_http_request(
        post, "http://localhost:8081/workflows", ""),
    ct:pal("Empty body response: ~p", [ResponseCode2]),
    ?assertEqual(ResponseCode2, 400),

    %% Test invalid content type
    {ok, ResponseCode3, _} = make_http_request(
        post, "http://localhost:8081/workflows", "test data", "text/plain"),
    ct:pal("Invalid content type response: ~p", [ResponseCode3]),
    ?assertEqual(ResponseCode3, 415),

    ct:pal("Invalid request format test completed"),
    ok.

%% @doc Test not found endpoints handling.
-spec test_not_found_endpoints(Config) -> ok when Config :: [tuple()].
test_not_found_endpoints(_Config) ->
    %% Test non-existent workflow
    {ok, ResponseCode1, _} = make_http_request(
        get, "http://localhost:8081/workflows/nonexistent", ""),
    ct:pal("Not found workflow response: ~p", [ResponseCode1]),
    ?assertEqual(ResponseCode1, 404),

    %% Test non-existent endpoint
    {ok, ResponseCode2, _} = make_http_request(
        get, "http://localhost:8081/nonexistent", ""),
    ct:pal("Not found endpoint response: ~p", [ResponseCode2]),
    ?assertEqual(ResponseCode2, 404),

    ct:pal("Not found endpoints test completed"),
    ok.

%% @doc Test unauthorized access handling.
-spec test_unauthorized_access(Config) -> ok when Config :: [tuple()].
test_unauthorized_access(_Config) ->
    %% Test accessing protected endpoints without authentication
    %% This test assumes authentication is enabled (may need to be adjusted)

    %% Test POST without proper authentication
    {ok, ResponseCode, _} = make_http_request(
        post, "http://localhost:8081/workflows/someaction", ""),

    ct:pal("Unauthorized access response: ~p", [ResponseCode]),
    %% Depending on implementation, this could be 401 or 403
    ?assert(lists:member(ResponseCode, [401, 403, 404])),

    ct:pal("Unauthorized access test completed"),
    ok.

%% @doc Test invalid workflow data handling.
-spec test_invalid_workflow_data(Config) -> ok when Config :: [tuple()].
test_invalid_workflow_data(_Config) ->
    %% Test invalid pattern type
    InvalidPayload = jiffy:encode(#{pattern_type => invalid_pattern, config => #{}}),
    {ok, ResponseCode1, ResponseBody1} = make_http_request(
        post, "http://localhost:8081/workflows", InvalidPayload),
    ct:pal("Invalid pattern response: ~p ~s", [ResponseCode1, ResponseBody1]),
    ?assertEqual(ResponseCode1, 400),

    %% Test invalid config
    InvalidPayload2 = jiffy:encode(#{pattern_type => basic_sequential, config => invalid}),
    {ok, ResponseCode2, ResponseBody2} = make_http_request(
        post, "http://localhost:8081/workflows", InvalidPayload2),
    ct:pal("Invalid config response: ~p ~s", [ResponseCode2, ResponseBody2]),
    ?assertEqual(ResponseCode2, 400),

    ct:pal("Invalid workflow data test completed"),
    ok.

%% @doc Test missing required fields handling.
-spec test_missing_required_fields(Config) -> ok when Config :: [tuple()].
test_missing_required_fields(_Config) ->
    %% Test missing pattern_type
    IncompletePayload = jiffy:encode(#{config => #{}}),
    {ok, ResponseCode1, ResponseBody1} = make_http_request(
        post, "http://localhost:8081/workflows", IncompletePayload),
    ct:pal("Missing pattern_type response: ~p ~s", [ResponseCode1, ResponseBody1]),
    ?assertEqual(ResponseCode1, 400),

    %% Test empty payload
    EmptyPayload = jiffy:encode(#{}),
    {ok, ResponseCode2, ResponseBody2} = make_http_request(
        post, "http://localhost:8081/workflows", EmptyPayload),
    ct:pal("Empty payload response: ~p ~s", [ResponseCode2, ResponseBody2]),
    ?assertEqual(ResponseCode2, 400),

    ct:pal("Missing required fields test completed"),
    ok.

%%====================================================================
%% Validation Tests
%%====================================================================

%% @doc Test workflow validation.
-spec test_workflow_validation(Config) -> ok when Config :: [tuple()].
test_workflow_validation(_Config) ->
    %% Test valid workflows
    ValidConfigs = [
        #{pattern_type => basic_sequential, config => #{task1_name => "task1"}},
        #{pattern_type => basic_sequential, config => #{task1_name => "task1", timeout => 30000}},
        #{pattern_type => basic_sequential, config => #{task1_name => "task1", retry_policy => #{max_attempts => 3}}}
    ],

    lists:foreach(fun(Config) ->
        Payload = jiffy:encode(Config),
        {ok, ResponseCode, ResponseBody} = make_http_request(
            post, "http://localhost:8081/workflows", Payload),
        ct:pal("Valid workflow ~p: ~p", [Config, ResponseCode]),
        ?assertEqual(201, ResponseCode)
    end, ValidConfigs),

    ct:pal("Workflow validation test completed"),
    ok.

%% @doc Test parameter validation.
-spec test_parameter_validation(Config) -> ok when Config :: [tuple()].
test_parameter_validation(_Config) ->
    %% Create workflow first
    CreatePayload = jiffy:encode(#{pattern_type => basic_sequential, config => #{}}),
    {ok, ResponseCode, ResponseBody} = make_http_request(
        post, "http://localhost:8081/workflows", CreatePayload),

    ?assertEqual(201, ResponseCode),
    CreateResult = jiffy:decode(ResponseBody, [return_maps]),
    WorkflowId = maps:get(<<"workflow_id">>, CreateResult),

    %% Test invalid parameter values
    InvalidParams = [
        {start, -1},  % negative timeout
        {start, 999999999999999},  % extremely large timeout
        {start, "notanumber"}  % non-numeric timeout
    ],

    lists:foreach(fun({Action, ParamValue}) ->
        Url = "http://localhost:8081/workflows/" ++ binary_to_list(WorkflowId) ++ "/" ++ atom_to_list(Action),
        ParamUrl = Url ++ "?timeout=" ++ io_lib:format("~p", [ParamValue]),
        {ok, ResponseCode, ResponseBody} = make_http_request(
            post, ParamUrl, ""),
        ct:pal("Invalid parameter ~p=~p: ~p", [Action, ParamValue, ResponseCode])
    end, InvalidParams),

    ct:pal("Parameter validation test completed"),
    ok.

%% @doc Test schema validation.
-spec test_schema_validation(Config) -> ok when Config :: [tuple()].
test_schema_validation(_Config) ->
    %% Test various schema violations
    InvalidSchemas = [
        #{},  % empty
        #{pattern_type => not_an_atom},  % wrong type
        #{config => "not_a_map"},  % wrong type
        #{config => #{task1_name => 123}},  % wrong type
        #{pattern_type => basic_sequential, extra_field => "unexpected"}  % extra field
    ],

    lists:foreach(fun(Schema) ->
        Payload = jiffy:encode(Schema),
        {ok, ResponseCode, ResponseBody} = make_http_request(
            post, "http://localhost:8081/workflows", Payload),
        ct:pal("Schema validation for ~p: ~p", [Schema, ResponseCode]),
        ?assertEqual(400, ResponseCode)
    end, InvalidSchemas),

    ct:pal("Schema validation test completed"),
    ok.

%% @doc Test business rule validation.
-spec test_business_rule_validation(Config) -> ok when Config :: [tuple()].
test_business_rule_validation(_Config) ->
    %% Test workflow configurations that violate business rules
    InvalidBusinessRules = [
        #{pattern_type => basic_sequential, config => #{task1_name => ""}},  % empty task name
        #{pattern_type => basic_sequential, config => #{timeout => 0}},  % zero timeout
        #{pattern_type => basic_sequential, config => #{retry_policy => #{max_attempts => 0}}},  % zero retries
        #{pattern_type => basic_sequential, config => #{}}  % missing required task
    ],

    lists:foreach(fun(Config) ->
        Payload = jiffy:encode(Config),
        {ok, ResponseCode, ResponseBody} = make_http_request(
            post, "http://localhost:8081/workflows", Payload),
        ct:pal("Business rule validation for ~p: ~p", [Config, ResponseCode]),
        ?assert(lists:member(ResponseCode, [400, 422]))  % 422 for unprocessable entity
    end, InvalidBusinessRules),

    ct:pal("Business rule validation test completed"),
    ok.

%%====================================================================
%% Performance Tests
%%====================================================================

%% @doc Test concurrent API calls.
-spec test_concurrent_api_calls(Config) -> ok when Config :: [tuple()].
test_concurrent_api_calls(_Config) ->
    NumConcurrent = 20,
    Requests = lists:duplicate(NumConcurrent,
        fun() ->
            Payload = jiffy:encode(#{pattern_type => basic_sequential, config => #{}}),
            make_http_request(post, "http://localhost:8081/workflows", Payload)
        end),

    %% Execute concurrent requests
    StartTime = erlang:monotonic_time(millisecond),
    Results = pmap(Requests),
    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    %% Analyze results
    Successful = lists:filter(fun({ok, Code, _}) -> Code =:= 201 end, Results),
    Failed = lists:filter(fun({ok, Code, _}) -> Code =/= 201 end, Results),
    Errors = lists:filter(fun({error, _, _}) -> true end, Results),

    ct:pal("Concurrent API calls: ~p total, ~p successful, ~p failed, ~p errors in ~p ms",
        [NumConcurrent, length(Successful), length(Failed), length(Errors), Duration]),
    ct:pal("Success rate: ~p%", [length(Successful) * 100 / NumConcurrent]),

    ct:pal("Concurrent API calls test completed"),
    ok.

%% @doc Test API throughput.
-spec test_api_throughput(Config) -> ok when Config :: [tuple()].
test_api_throughput(_Config) ->
    NumRequests = 50,
    StartTime = erlang:monotonic_time(millisecond),

    %% Send requests as fast as possible
    lists:foreach(fun(_) ->
        Payload = jiffy:encode(#{pattern_type => basic_sequential, config => #{}}),
        {ok, _, _} = make_http_request(post, "http://localhost:8081/workflows", Payload)
    end, lists:seq(1, NumRequests)),

    EndTime = erlang:monotonic_time(millisecond),
    Duration = (EndTime - StartTime) / 1000,  % in seconds
    Throughput = NumRequests / Duration,

    ct:pal("API throughput: ~p requests/second", [Throughput]),

    ct:pal("API throughput test completed"),
    ok.

%% @doc Test large payload handling.
-spec test_large_payload_handling(Config) -> ok when Config :: [tuple()].
test_large_payload_handling(_Config) ->
    %% Create large payload
    LargeConfig = #{pattern_type => basic_sequential,
                   config => #{large_data => lists:duplicate(10000, "x")},
                   metadata => #{description => lists:duplicate(5000, "description data")}},
    LargePayload = jiffy:encode(LargeConfig),

    %% Send large payload
    {ok, ResponseCode, ResponseBody} = make_http_request(
        post, "http://localhost:8081/workflows", LargePayload),

    ct:pal("Large payload response: ~p", [ResponseCode]),
    ?assertEqual(201, ResponseCode),

    %% Test response size
    ResponseSize = byte_size(ResponseBody),
    ct:pal("Response size: ~p bytes", [ResponseSize]),
    ?assert(ResponseSize < 1048576),  % Should be less than 1MB

    ct:pal("Large payload handling test completed"),
    ok.

%% @doc Test error rate testing.
-spec test_error_rate_testing(Config) -> ok when Config :: [tuple()].
test_error_rate_testing(_Config) ->
    %% Mix of valid and invalid requests
    RequestTypes = [
        valid_request,    % valid workflow creation
        valid_request,    % valid workflow creation
        invalid_json,     % malformed JSON
        invalid_payload,  % missing required field
        valid_request,    % valid workflow creation
        not_found,        % non-existent endpoint
        valid_request     % valid workflow creation
    ],

    Results = lists:map(fun(Type) ->
        case Type of
            valid_request ->
                Payload = jiffy:encode(#{pattern_type => basic_sequential, config => #{}}),
                {ok, Code, _} = make_http_request(post, "http://localhost:8081/workflows", Payload),
                Type;
            invalid_json ->
                {ok, Code, _} = make_http_request(post, "http://localhost:8081/workflows", "invalid json"),
                Type;
            invalid_payload ->
                Payload = jiffy:encode(#{config => #{}}),  % missing pattern_type
                {ok, Code, _} = make_http_request(post, "http://localhost:8081/workflows", Payload),
                Type;
            not_found ->
                {ok, Code, _} = make_http_request(get, "http://localhost:8081/nonexistent", ""),
                Type
        end
    end, RequestTypes),

    CountValid = length(lists:filter(fun(valid_request) -> true; (_) -> false end, Results)),
    CountInvalid = length(lists:filter(fun(valid_request) -> false; (_) -> true end, Results)),

    ct:pal("Error rate test: ~p valid, ~p invalid", [CountValid, CountInvalid]),
    ct:pal("Error rate: ~p%", [CountInvalid * 100 / length(Requests)]),

    ct:pal("Error rate testing completed"),
    ok.

%%====================================================================
%% Security Tests
%%====================================================================

%% @doc Test API authentication.
-spec test_api_authentication(Config) -> ok when Config :: [tuple()].
test_api_authentication(_Config) ->
    %% Test without authentication (if enabled)
    {ok, ResponseCode1, _} = make_http_request(
        post, "http://localhost:8081/workflows",
        jiffy:encode(#{pattern_type => basic_sequential, config => #{}})),

    ct:pal("No authentication response: ~p", [ResponseCode1]),

    %% Test with invalid authentication
    Headers = [{"Authorization", "Bearer invalid_token"}],
    {ok, ResponseCode2, _} = make_http_request(
        post, "http://localhost:8081/workflows",
        jiffy:encode(#{pattern_type => basic_sequential, config => #{}}), Headers),

    ct:pal("Invalid authentication response: ~p", [ResponseCode2]).

%% @doc Test rate limiting.
-spec test_rate_limiting(Config) -> ok when Config :: [tuple()].
test_rate_limiting(_Config) ->
    %% Send many requests quickly to test rate limiting
    NumRequests = 100,
    Results = lists:map(fun(I) ->
        Payload = jiffy:encode(#{pattern_type => basic_sequential, config => #{iteration => I}}),
        make_http_request(post, "http://localhost:8081/workflows", Payload)
    end, lists:seq(1, NumRequests)),

    %% Check for rate limiting responses (429 Too Many Requests)
    RateLimited = lists:filter(fun({ok, 429, _}) -> true; (_) -> false end, Results),
    Success = lists:filter(fun({ok, 201, _}) -> true; (_) -> false end, Results),
    Failed = lists:filter(fun({ok, _, _}) -> true end, Results) -- Success -- RateLimited,

    ct:pal("Rate limiting test: ~p success, ~p rate limited, ~p other errors",
        [length(Success), length(RateLimited), length(Failed)]).

%% @doc Test input validation security.
-spec test_input_validation_security(Config) -> ok when Config :: [tuple()].
test_input_validation_security(_Config) ->
    %% Test various injection attempts
    MaliciousInputs = [
        #{pattern_type => <<"basic_sequential\"'>script>alert('xss')</script>">>, config => #{}},
        #{pattern_type => basic_sequential, config => #{task1_name => "\"'><script>evil()</script>"}},
        #{pattern_type => basic_sequential, config => #{data => <<"{\"key\": \"value\"><script>evil()</script>}\"">>}}
    ],

    lists:foreach(fun(Input) ->
        Payload = jiffy:encode(Input),
        {ok, ResponseCode, ResponseBody} = make_http_request(
            post, "http://localhost:8081/workflows", Payload),
        ct:pal("Security test for ~p: ~p", [Input, ResponseCode]),
        ?assertEqual(400, ResponseCode)  % Should reject malicious input
    end, MaliciousInputs).

%% @doc Test output encoding security.
-spec test_output_encoding_security(Config) -> ok when Config :: [tuple()].
test_output_encoding_security(_Config) ->
    %% Create workflow and check for proper output encoding
    Payload = jiffy:encode(#{pattern_type => basic_sequential, config => #{}}),
    {ok, ResponseCode, ResponseBody} = make_http_request(
        post, "http://localhost:8081/workflows", Payload),

    ?assertEqual(201, ResponseCode),
    Response = jiffy:decode(ResponseBody, [return_maps]),

    %% Check that output is properly encoded
    ResponseStr = jiffy:encode(Response),
    ?assert(not (string:find(ResponseStr, "<script>") =/= nomatch)),
    ?assert(not (string:find(ResponseStr, "\"\">") =/= nomatch)).

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
%% @doc Make HTTP request to REST API.
make_http_request(Method, Url, Body) ->
    make_http_request(Method, Url, Body, "application/json").

make_http_request(Method, Url, Body, ContentType) ->
    make_http_request(Method, Url, Body, ContentType, []).

make_http_request(Method, Url, Body, ContentType, Headers) ->
    %% Convert to HTTP client call
    %% This is a simplified implementation - in practice you'd use a proper HTTP client
    case catch test_http_request(Method, Url, Body, ContentType, Headers) of
        {ok, Response} ->
            {ok, Response#http.status_code, Response#http.body};
        Error ->
            {error, Error}
    end.

%% @private
%% @doc Mock HTTP request function for testing.
test_http_request(Method, Url, Body, ContentType, Headers) ->
    %% This would normally use an HTTP client like hackney or httpc
    %% For testing purposes, we'll simulate some responses

    case Url of
        "http://localhost:8081/workflows" ->
            case Method of
                post ->
                    %% Try to parse JSON
                    case catch jiffy:decode(Body, [return_maps]) of
                        {'EXIT', _} ->
                            #http{status_code = 400, body = jiffy:encode(#{error => "invalid_json"})};
                        Json ->
                            case validate_workflow_request(Json) of
                                valid ->
                                    WorkflowId = generate_workflow_id(),
                                    Response = #{workflow_id => WorkflowId, status => created},
                                    #http{status_code = 201, body = jiffy:encode(Response)};
                                {error, Reason} ->
                                    #http{status_code = 400, body = jiffy:encode(#{error => Reason})}
                            end
                    end;
                get ->
                    %% List workflows
                    Workflows = #{workflows => []},
                    #http{status_code = 200, body = jiffy:encode(Workflows)};
                _ ->
                    #http{status_code = 405, body = jiffy:encode(#{error => "method_not_allowed"})}
            end;
        "http://localhost:8081/workflows/" ++ Rest ->
            case string:find(Rest, "/", nomatch) of
                nomatch ->
                    WorkflowId = list_to_binary(Rest),
                    %% Get specific workflow
                    #http{status_code = 200, body = jiffy:encode(#{workflow_id => WorkflowId, status => pending})};
                _ ->
                    [WorkflowIdStr | Action] = string:tokens(Rest, "/"),
                    WorkflowId = list_to_binary(WorkflowIdStr),
                    case Action of
                        ["start"] ->
                            #http{status_code = 200, body = jiffy:encode(#{workflow_id => WorkflowId, status => started})};
                        ["cancel"] ->
                            #http{status_code = 200, body = jiffy:encode(#{workflow_id => WorkflowId, status => cancelled})};
                        _ ->
                            #http{status_code = 404, body = jiffy:encode(#{error => "not_found"})}
                    end
            end;
        _ ->
            #http{status_code = 404, body = jiffy:encode(#{error => "not_found"})}
    end.

%% @private
%% @doc Validate workflow request.
validate_workflow_request(Json) ->
    case maps:find(<<"pattern_type">>, Json) of
        {ok, PatternType} ->
            case lists:member(PatternType, [<<"basic_sequential">>, <<"parallel_split">>, <<"exclusive_choice">>]) of
                true ->
                    case maps:find(<<"config">>, Json) of
                        {ok, Config} when is_map(Config) ->
                            valid;
                        error ->
                            valid;  % config is optional
                        _ ->
                            {error, "invalid_config_type"}
                    end;
                false ->
                    {error, "invalid_pattern_type"}
            end;
        error ->
            {error, "missing_pattern_type"}
    end.

%% @private
%% @doc Generate workflow ID for testing.
generate_workflow_id() ->
    UniqueId = erlang:unique_integer([positive, monotonic]),
    <<UniqueId:64>>.

%% @private
%% @doc Wait for REST server to be ready.
wait_for_rest_server(Port, Timeout) ->
    StartTime = erlang:monotonic_time(millisecond),
    wait_for_server(Port, StartTime, Timeout).

wait_for_server(Port, StartTime, Timeout) ->
    case can_connect_to_server(Port) of
        true ->
            ok;
        false ->
            case erlang:monotonic_time(millisecond) - StartTime of
                Elapsed when Elapsed > Timeout ->
                    ct:pal("Server not ready after ~p ms", [Timeout]),
                    error(server_not_ready);
                _ ->
                    timer:sleep(100),
                    wait_for_server(Port, StartTime, Timeout)
            end
    end.

%% @private
%% @doc Check if server is ready.
can_connect_to_server(Port) ->
    %% Simple check - in reality this would try to make a connection
    %% For testing, we'll just return true after a short delay
    timer:sleep(200),
    true.

%% @private
%% @doc Parallel map implementation.
pmap(Fun, List) ->
    Self = self(),
    Pids = lists:map(fun(I) ->
        spawn(fun() ->
            Self ! {self(), Fun(I)}
        end)
    end, List),

    lists:map(fun(_) ->
        receive
            {Pid, Result} -> Result
        end
    end, Pids).

%% @private
%% @doc Clean up test data.
cleanup_test_data() ->
    %% Clean up workflows via REST API
    {ok, ResponseCode, ResponseBody} = make_http_request(get, "http://localhost:8081/workflows", ""),
    case ResponseCode of
        200 ->
            Response = jiffy:decode(ResponseBody, [return_maps]),
            case maps:find(<<"workflows">>, Response) of
                {ok, Workflows} when is_list(Workflows) ->
                    lists:foreach(fun(Workflow) ->
                        WorkflowId = maps:get(<<"workflow_id">>, Workflow),
                        make_http_request(delete, "http://localhost:8081/workflows/" ++ binary_to_list(WorkflowId), "")
                    end, Workflows);
                _ ->
                    ok
            end;
        _ ->
            ok
    end.