%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL REST Handler Unit Tests
%%%
%%% Comprehensive test suite for the YAWL REST API handler module.
%%% Tests cover:
%%% - Workflow listing (GET /workflows)
%%% - Single workflow retrieval (GET /workflows/{id})
%%% - Workflow creation (POST /workflows)
%%% - Workflow update (PATCH /workflows/{id})
%%% - Workflow deletion (DELETE /workflows/{id})
%%% - Workflow actions (start, cancel, pause, resume, checkpoint)
%%% - Query parameter handling (status, pagination)
%%% - Error responses for not found, invalid input
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(test_yawl_rest_handler).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

%% State record matching the handler's internal state
-record(state, {
    method,
    workflow_id = undefined,
    action = undefined,
    content_type = undefined,
    auth_context = undefined,
    validation_errors = undefined
}).

%%====================================================================
%% Test Setup and Teardown
%%====================================================================

%% Setup function run before each test
setup() ->
    meck:new(yawl_persistence, [passthrough]),
    meck:new(yawl_orchestrator, [passthrough]),
    meck:new(yawl_request_validator, [passthrough]),
    meck:new(yawl_error_response, [passthrough]),
    meck:new(yawl_validation_schema, [passthrough]),
    meck:new(cowboy_req, [passthrough]),
    meck:new(jiffy, [passthrough]),
    ok.

%% Cleanup function run after each test
cleanup(_) ->
    meck:unload(yawl_persistence),
    meck:unload(yawl_orchestrator),
    meck:unload(yawl_request_validator),
    meck:unload(yawl_error_response),
    meck:unload(yawl_validation_schema),
    meck:unload(cowboy_req),
    meck:unload(jiffy),
    ok.

%%====================================================================
%% Generator for setup/cleanup
%%====================================================================

test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
        %% Initialization tests
         {"init/2 returns cowboy_rest", fun test_init_returns_cowboy_rest/0},

         %% Allowed methods tests
         {"allowed_methods/2 for workflow list", fun test_allowed_methods_list/0},
         {"allowed_methods/2 for single workflow", fun test_allowed_methods_single/0},
         {"allowed_methods/2 for action endpoint", fun test_allowed_methods_action/0},

         %% Content types tests
         {"content_types_provided/2", fun test_content_types_provided/0},
         {"content_types_accepted/2", fun test_content_types_accepted/0},

         %% Workflow listing tests (GET /workflows)
         {"resource_exists/2 for list returns true", fun test_resource_exists_list/0},
         {"resource_exists/2 for existing workflow", fun test_resource_exists_found/0},
         {"resource_exists/2 for missing workflow", fun test_resource_exists_not_found/0},
         {"to_json/2 lists all workflows", fun test_list_workflows_all/0},
         {"to_json/2 filters by status", fun test_list_workflows_by_status/0},
         {"to_json/2 applies pagination", fun test_list_workflows_pagination/0},
         {"to_json/2 handles empty list", fun test_list_workflows_empty/0},

         %% Single workflow retrieval tests (GET /workflows/{id})
         {"to_json/2 gets single workflow", fun test_get_workflow_success/0},
         {"to_json/2 for non-existent workflow", fun test_get_workflow_not_found/0},
         {"to_json/2 gets workflow marking", fun test_get_workflow_marking/0},
         {"to_json/2 gets workflow result", fun test_get_workflow_result/0},
         {"to_json/2 gets workflow history", fun test_get_workflow_history/0},

         %% Workflow creation tests (POST /workflows)
         {"from_json/2 creates workflow", fun test_create_workflow_success/0},
         {"from_json/2 creates workflow with timeout", fun test_create_workflow_with_timeout/0},
         {"from_json/2 creates workflow with retry", fun test_create_workflow_with_retry/0},
         {"from_json/2 fails invalid pattern", fun test_create_workflow_invalid_pattern/0},

         %% Workflow update tests (PATCH /workflows/{id})
         {"from_json/2 updates workflow", fun test_update_workflow_success/0},
         {"from_json/2 update without data", fun test_update_workflow_no_data/0},

         %% Workflow deletion tests (DELETE /workflows/{id})
         {"delete_resource/2 succeeds", fun test_delete_workflow_success/0},
         {"delete_resource/2 for missing workflow", fun test_delete_workflow_not_found/0},

         %% Workflow action tests - start
         {"to_json/2 starts workflow", fun test_start_workflow_success/0},
         {"to_json/2 start non-existent workflow", fun test_start_workflow_not_found/0},

         %% Workflow action tests - cancel
         {"to_json/2 cancels workflow", fun test_cancel_workflow_success/0},
         {"to_json/2 cancel non-existent workflow", fun test_cancel_workflow_not_found/0},

         %% Workflow action tests - pause
         {"to_json/2 pauses workflow", fun test_pause_workflow_success/0},
         {"to_json/2 pause non-existent workflow", fun test_pause_workflow_not_found/0},
         {"to_json/2 suspends workflow", fun test_suspend_workflow_success/0},

         %% Workflow action tests - resume
         {"to_json/2 resumes workflow", fun test_resume_workflow_success/0},
         {"to_json/2 resume non-existent workflow", fun test_resume_workflow_not_found/0},

         %% Workflow action tests - checkpoint
         {"to_json/2 creates checkpoint", fun test_checkpoint_workflow/0},

         %% Query parameter handling tests
         {"parse_query_string empty", fun test_parse_query_string_empty/0},
         {"parse_query_string single", fun test_parse_query_string_single/0},
         {"parse_query_string multiple", fun test_parse_query_string_multiple/0},
         {"parse_query_string no value", fun test_parse_query_string_no_value/0},
         {"parse_query_string url encoded", fun test_parse_query_string_encoded/0},

         %% Error response tests
         {"is_conflict/2 for new workflow", fun test_is_conflict_new/0},
         {"is_conflict/2 for running workflow", fun test_is_conflict_running/0},
         {"is_conflict/2 for completed workflow", fun test_is_conflict_completed/0},

         %% Helper function tests
         {"workflow_to_map converts record", fun test_workflow_to_map/0},
         {"history_to_map converts record", fun test_history_to_map/0},
         {"to_binary handles binary", fun test_to_binary_binary/0},
         {"to_binary handles atom", fun test_to_binary_atom/0},
         {"to_binary handles list", fun test_to_binary_list/0},
         {"to_binary handles term", fun test_to_binary_term/0},
         {"maps_get returns default", fun test_maps_get_default/0},

         %% Unknown action test
         {"to_json/2 unknown action", fun test_unknown_action/0}
     ]
    }.

%%====================================================================
%% Initialization Tests
%%====================================================================

test_init_returns_cowboy_rest() ->
    Req = mock_request(),
    {cowboy_rest, _Req2, #state{}} = yawl_rest_handler:init(Req, #state{}).

%%====================================================================
%% Allowed Methods Tests
%%====================================================================

test_allowed_methods_list() ->
    Req = mock_request(),
    State = #state{workflow_id = undefined, action = undefined},
    {[<<"GET">>, <<"POST">>, <<"HEAD">>, <<"OPTIONS">>], _Req2, _State2} =
        yawl_rest_handler:allowed_methods(Req, State).

test_allowed_methods_single() ->
    Req = mock_request(),
    State = #state{workflow_id = <<"wf123">>, action = undefined},
    {[<<"GET">>, <<"DELETE">>, <<"HEAD">>, <<"OPTIONS">>, <<"PATCH">>], _Req2, _State2} =
        yawl_rest_handler:allowed_methods(Req, State).

test_allowed_methods_action() ->
    Req = mock_request(),
    State = #state{workflow_id = <<"wf123">>, action = <<"start">>},
    {[<<"POST">>, <<"HEAD">>, <<"OPTIONS">>], _Req2, _State2} =
        yawl_rest_handler:allowed_methods(Req, State).

%%====================================================================
%% Content Types Tests
%%====================================================================

test_content_types_provided() ->
    Req = mock_request(),
    State = #state{},
    {Provided, _Req2, _State2} = yawl_rest_handler:content_types_provided(Req, State),
    ?assertEqual(2, length(Provided)),
    ?assert(lists:keyfind({<<"application">>, <<"json">>, '*'}, 1, Provided)),
    ?assert(lists:keyfind({<<"application">>, <<"vnd.api+json">>, '*'}, 1, Provided)).

test_content_types_accepted() ->
    Req = mock_request(),
    State = #state{},
    {Accepted, _Req2, _State2} = yawl_rest_handler:content_types_accepted(Req, State),
    ?assertEqual(1, length(Accepted)),
    ?assert(lists:keyfind({<<"application">>, <<"json">>, '*'}, 1, Accepted)).

%%====================================================================
%% Resource Exists Tests
%%====================================================================

test_resource_exists_list() ->
    Req = mock_request(),
    State = #state{workflow_id = undefined},
    {true, _Req2, _State2} = yawl_rest_handler:resource_exists(Req, State).

test_resource_exists_found() ->
    Req = mock_request(),
    State = #state{workflow_id = <<"wf123">>},

    Workflow = #yawl_workflow_persist{
        workflow_id = <<"wf123">>,
        spec_id = <<"spec1">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{},
        current_place = start,
        data = #{},
        parent_workflow_id = undefined,
        created_at = 1000,
        updated_at = 2000,
        completed_at = undefined,
        error = undefined
    },
    meck:expect(yawl_persistence, load_workflow, fun(<<"wf123">>) -> {ok, Workflow} end),

    {true, _Req2, _State2} = yawl_rest_handler:resource_exists(Req, State).

test_resource_exists_not_found() ->
    Req = mock_request(),
    State = #state{workflow_id = <<"missing">>},

    meck:expect(yawl_persistence, load_workflow,
        fun(<<"missing">>) -> {error, not_found} end),

    {false, _Req2, _State2} = yawl_rest_handler:resource_exists(Req, State).

%%====================================================================
%% Workflow Listing Tests (GET /workflows)
%%====================================================================

test_list_workflows_all() ->
    Req = mock_request_with_qs(<<>>),
    State = #state{method = <<"GET">>, workflow_id = undefined, action = undefined},

    Workflows = [
        #yawl_workflow_persist{
            workflow_id = <<"wf1">>,
            spec_id = <<"spec1">>,
            pattern_type = basic_sequential,
            status = running,
            marking = #{},
            current_place = start,
            data = #{},
            parent_workflow_id = undefined,
            created_at = 1000,
            updated_at = 2000,
            completed_at = undefined,
            error = undefined
        },
        #yawl_workflow_persist{
            workflow_id = <<"wf2">>,
            spec_id = <<"spec2">>,
            pattern_type = parallel_split,
            status = completed,
            marking = #{},
            current_place = 'end',
            data = #{},
            parent_workflow_id = undefined,
            created_at = 1000,
            updated_at = 3000,
            completed_at = 3000,
            error = undefined
        }
    ],

    meck:expect(yawl_persistence, list_workflows, fun() -> {ok, Workflows} end),
    meck:expect(cowboy_req, qs, fun(Req) -> {<<>>, Req} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    %% Verify response structure
    ?assertMatch(#{
        workflows := [_ | _],
        total := 2,
        returned := 2,
        offset := 0
    }, jiffy:decode(JsonBody, [return_maps])).

test_list_workflows_by_status() ->
    Req = mock_request_with_qs(<<"status=running">>),
    State = #state{method = <<"GET">>, workflow_id = undefined, action = undefined},

    RunningWorkflows = [
        #yawl_workflow_persist{
            workflow_id = <<"wf1">>,
            spec_id = <<"spec1">>,
            pattern_type = basic_sequential,
            status = running,
            marking = #{},
            current_place = start,
            data = #{},
            parent_workflow_id = undefined,
            created_at = 1000,
            updated_at = 2000,
            completed_at = undefined,
            error = undefined
        }
    ],

    meck:expect(yawl_persistence, list_workflows_by_status,
        fun(running) -> {ok, RunningWorkflows} end),
    meck:expect(cowboy_req, qs, fun(Req) -> {<<"status=running">>, Req} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(1, maps:get(total, Response)),
    ?assertEqual(1, maps:get(returned, Response)).

test_list_workflows_pagination() ->
    Req = mock_request_with_qs(<<"limit=1&offset=0">>),
    State = #state{method = <<"GET">>, workflow_id = undefined, action = undefined},

    AllWorkflows = [
        #yawl_workflow_persist{
            workflow_id = <<"wf1">>,
            spec_id = <<"spec1">>,
            pattern_type = basic_sequential,
            status = running,
            marking = #{},
            current_place = start,
            data = #{},
            parent_workflow_id = undefined,
            created_at = 1000,
            updated_at = 2000,
            completed_at = undefined,
            error = undefined
        },
        #yawl_workflow_persist{
            workflow_id = <<"wf2">>,
            spec_id = <<"spec2">>,
            pattern_type = parallel_split,
            status = completed,
            marking = #{},
            current_place = 'end',
            data = #{},
            parent_workflow_id = undefined,
            created_at = 1000,
            updated_at = 3000,
            completed_at = 3000,
            error = undefined
        }
    ],

    meck:expect(yawl_persistence, list_workflows, fun() -> {ok, AllWorkflows} end),
    meck:expect(cowboy_req, qs, fun(Req) -> {<<"limit=1&offset=0">>, Req} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(2, maps:get(total, Response)),
    ?assertEqual(1, maps:get(returned, Response)),
    ?assertEqual(0, maps:get(offset, Response)).

test_list_workflows_empty() ->
    Req = mock_request_with_qs(<<>>),
    State = #state{method = <<"GET">>, workflow_id = undefined, action = undefined},

    meck:expect(yawl_persistence, list_workflows, fun() -> {ok, []} end),
    meck:expect(cowboy_req, qs, fun(Req) -> {<<>>, Req} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(0, maps:get(total, Response)),
    ?assertEqual([], maps:get(workflows, Response)).

%%====================================================================
%% Single Workflow Retrieval Tests (GET /workflows/{id})
%%====================================================================

test_get_workflow_success() ->
    Req = mock_request(),
    State = #state{method = <<"GET">>, workflow_id = <<"wf123">>, action = undefined},

    Workflow = #yawl_workflow_persist{
        workflow_id = <<"wf123">>,
        spec_id = <<"spec1">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{start => [token]},
        current_place = start,
        data = #{},
        parent_workflow_id = undefined,
        created_at = 1000,
        updated_at = 2000,
        completed_at = undefined,
        error = undefined
    },

    meck:expect(yawl_persistence, load_workflow, fun(<<"wf123">>) -> {ok, Workflow} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)),
    ?assertEqual(<<"spec1">>, maps:get(spec_id, Response)),
    ?assertEqual(basic_sequential, maps:get(pattern_type, Response)),
    ?assertEqual(running, maps:get(status, Response)).

test_get_workflow_not_found() ->
    Req = mock_request(),
    State = #state{method = <<"GET">>, workflow_id = <<"missing">>, action = undefined},

    meck:expect(yawl_persistence, load_workflow,
        fun(<<"missing">>) -> {error, not_found} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"workflow_not_found">>, maps:get(error, Response)),
    ?assertEqual(<<"missing">>, maps:get(workflow_id, Response)).

test_get_workflow_marking() ->
    Req = mock_request(),
    State = #state{method = <<"GET">>, workflow_id = <<"wf123">>, action = <<"marking">>},

    Workflow = #yawl_workflow_persist{
        workflow_id = <<"wf123">>,
        spec_id = <<"spec1">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{start => [token], task1 => []},
        current_place = start,
        data = #{},
        parent_workflow_id = undefined,
        created_at = 1000,
        updated_at = 2000,
        completed_at = undefined,
        error = undefined
    },

    meck:expect(yawl_persistence, load_workflow, fun(<<"wf123">>) -> {ok, Workflow} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)),
    ?assertMatch(#{start := [token], task1 := []}, maps:get(marking, Response)).

test_get_workflow_result() ->
    Req = mock_request(),
    State = #state{method = <<"GET">>, workflow_id = <<"wf123">>, action = <<"result">>},

    meck:expect(yawl_orchestrator, get_workflow_result,
        fun(<<"wf123">>) -> {ok, #{status => completed, output => 42}} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)),
    ?assertMatch(#{status := completed, output := 42}, maps:get(result, Response)).

test_get_workflow_history() ->
    Req = mock_request(),
    State = #state{method = <<"GET">>, workflow_id = <<"wf123">>, action = <<"history">>},

    History = [
        #yawl_execution_history{
            history_id = <<"h1">>,
            workflow_id = <<"wf123">>,
            workitem_id = undefined,
            event_type = workflow_started,
            event_data = #{},
            timestamp = 1000,
            source = rest_api
        },
        #yawl_execution_history{
            history_id = <<"h2">>,
            workflow_id = <<"wf123">>,
            workitem_id = <<"wi1">>,
            event_type = workitem_completed,
            event_data = #{task => task1},
            timestamp = 2000,
            source = orchestrator
        }
    ],

    meck:expect(yawl_persistence, get_workflow_history,
        fun(<<"wf123">>) -> {ok, History} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)),
    ?assertEqual(2, maps:get(total, Response)),
    ?assertMatch([#{event_type := workflow_started}, #{event_type := workitem_completed}],
                 maps:get(history, Response)).

%%====================================================================
%% Workflow Creation Tests (POST /workflows)
%%====================================================================

test_create_workflow_success() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = undefined},

    Data = #{
        <<"pattern_type">> => basic_sequential,
        <<"config">> => #{}
    },

    meck:expect(yawl_request_validator, validate_request,
        fun(_Req, workflow_create) -> {ok, Data, Req} end),
    meck:expect(yawl_orchestrator, create_workflow,
        fun(basic_sequential, _) -> {ok, <<"wf123">>} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:from_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)),
    ?assertEqual(created, maps:get(status, Response)),
    ?assertEqual(<<"Workflow created successfully">>, maps:get(message, Response)).

test_create_workflow_with_timeout() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = undefined},

    Data = #{
        <<"pattern_type">> => basic_sequential,
        <<"config">> => #{},
        <<"timeout">> => 60000
    },

    meck:expect(yawl_request_validator, validate_request,
        fun(_Req, workflow_create) -> {ok, Data, Req} end),
    meck:expect(yawl_orchestrator, create_workflow,
        fun(basic_sequential, Config) ->
            ?assertEqual(60000, maps:get(timeout, Config)),
            {ok, <<"wf123">>}
        end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:from_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)).

test_create_workflow_with_retry() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = undefined},

    Data = #{
        <<"pattern_type">> => basic_sequential,
        <<"config">> => #{},
        <<"retry_policy">> => #{max_attempts => 3, delay => 1000}
    },

    meck:expect(yawl_request_validator, validate_request,
        fun(_Req, workflow_create) -> {ok, Data, Req} end),
    meck:expect(yawl_orchestrator, create_workflow,
        fun(basic_sequential, Config) ->
            ?assertMatch(#{max_attempts := 3, delay := 1000}, maps:get(retry_policy, Config)),
            {ok, <<"wf123">>}
        end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:from_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)).

test_create_workflow_invalid_pattern() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = undefined},

    Data = #{
        <<"pattern_type">> => invalid_pattern,
        <<"config">> => #{}
    },

    meck:expect(yawl_request_validator, validate_request,
        fun(_Req, workflow_create) -> {ok, Data, Req} end),
    meck:expect(yawl_orchestrator, create_workflow,
        fun(invalid_pattern, _) -> {error, {unknown_pattern, invalid_pattern}} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:from_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assert(maps:is_key(error, Response)).

%%====================================================================
%% Workflow Update Tests (PATCH /workflows/{id})
%%====================================================================

test_update_workflow_success() ->
    Req = mock_request(),
    State = #state{method = <<"PATCH">>, workflow_id = <<"wf123">>},

    Data = #{<<"data">> => #{key => <<"value">>}},

    meck:expect(yawl_request_validator, validate_request,
        fun(_Req, workflow_update) -> {ok, Data, Req} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:from_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"not_implemented">>, maps:get(error, Response)).

test_update_workflow_no_data() ->
    Req = mock_request(),
    State = #state{method = <<"PATCH">>, workflow_id = <<"wf123">>},

    Data = #{},

    meck:expect(yawl_request_validator, validate_request,
        fun(_Req, workflow_update) -> {ok, Data, Req} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:from_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"no_data">>, maps:get(error, Response)).

%%====================================================================
%% Workflow Deletion Tests (DELETE /workflows/{id})
%%====================================================================

test_delete_workflow_success() ->
    Req = mock_request(),
    State = #state{workflow_id = <<"wf123">>},

    meck:expect(yawl_orchestrator, cleanup_workflow,
        fun(<<"wf123">>) -> ok end),
    meck:expect(cowboy_req, reply,
        fun(200, _Headers, _Body, Req) -> Req end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {true, _Req2, _State2} = yawl_rest_handler:delete_resource(Req, State).

test_delete_workflow_not_found() ->
    Req = mock_request(),
    State = #state{workflow_id = <<"missing">>},

    meck:expect(yawl_orchestrator, cleanup_workflow,
        fun(<<"missing">>) -> {error, workflow_not_found} end),
    meck:expect(cowboy_req, reply,
        fun(404, _Headers, _Body, Req) -> Req end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {false, _Req2, _State2} = yawl_rest_handler:delete_resource(Req, State).

%%====================================================================
%% Workflow Action Tests - Start
%%====================================================================

test_start_workflow_success() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"wf123">>, action = <<"start">>},

    meck:expect(yawl_orchestrator, execute_workflow,
        fun(<<"wf123">>) -> {ok, #{status => running}} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)),
    ?assertEqual(running, maps:get(status, Response)),
    ?assertEqual(<<"Workflow started">>, maps:get(message, Response)).

test_start_workflow_not_found() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"missing">>, action = <<"start">>},

    meck:expect(yawl_orchestrator, execute_workflow,
        fun(<<"missing">>) -> {error, workflow_not_found} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"workflow_not_found">>, maps:get(error, Response)),
    ?assertEqual(<<"missing">>, maps:get(workflow_id, Response)).

%%====================================================================
%% Workflow Action Tests - Cancel
%%====================================================================

test_cancel_workflow_success() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"wf123">>, action = <<"cancel">>},

    meck:expect(yawl_orchestrator, cancel_workflow,
        fun(<<"wf123">>) -> ok end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)),
    ?assertEqual(cancelled, maps:get(status, Response)),
    ?assertEqual(<<"Workflow cancelled">>, maps:get(message, Response)).

test_cancel_workflow_not_found() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"missing">>, action = <<"cancel">>},

    meck:expect(yawl_orchestrator, cancel_workflow,
        fun(<<"missing">>) -> {error, workflow_not_found} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"workflow_not_found">>, maps:get(error, Response)).

%%====================================================================
%% Workflow Action Tests - Pause/Suspend
%%====================================================================

test_pause_workflow_success() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"wf123">>, action = <<"pause">>},

    meck:expect(yawl_orchestrator, pause_workflow,
        fun(<<"wf123">>) -> ok end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)),
    ?assertEqual(paused, maps:get(status, Response)),
    ?assertEqual(<<"Workflow paused">>, maps:get(message, Response)).

test_pause_workflow_not_found() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"missing">>, action = <<"pause">>},

    meck:expect(yawl_orchestrator, pause_workflow,
        fun(<<"missing">>) -> {error, workflow_not_found} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assert(maps:is_key(error, Response)).

test_suspend_workflow_success() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"wf123">>, action = <<"suspend">>},

    meck:expect(yawl_orchestrator, pause_workflow,
        fun(<<"wf123">>) -> ok end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)),
    ?assertEqual(paused, maps:get(status, Response)).

%%====================================================================
%% Workflow Action Tests - Resume
%%====================================================================

test_resume_workflow_success() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"wf123">>, action = <<"resume">>},

    meck:expect(yawl_orchestrator, resume_workflow,
        fun(<<"wf123">>) -> ok end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)),
    ?assertEqual(resumed, maps:get(status, Response)),
    ?assertEqual(<<"Workflow resumed">>, maps:get(message, Response)).

test_resume_workflow_not_found() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"missing">>, action = <<"resume">>},

    meck:expect(yawl_orchestrator, resume_workflow,
        fun(<<"missing">>) -> {error, workflow_not_found} end),
    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assert(maps:is_key(error, Response)).

%%====================================================================
%% Workflow Action Tests - Checkpoint
%%====================================================================

test_checkpoint_workflow() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"wf123">>, action = <<"checkpoint">>},

    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"not_implemented">>, maps:get(error, Response)),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Response)).

%%====================================================================
%% Query Parameter Handling Tests
%%====================================================================

test_parse_query_string_empty() ->
    ?assertEqual(#{}, yawl_rest_handler:parse_query_string(<<>>)).

test_parse_query_string_single() ->
    Result = yawl_rest_handler:parse_query_string(<<"status=running">>),
    ?assertEqual(<<"running">>, maps:get(<<"status">>, Result)).

test_parse_query_string_multiple() ->
    Result = yawl_rest_handler:parse_query_string(<<"status=running&limit=10">>),
    ?assertEqual(<<"running">>, maps:get(<<"status">>, Result)),
    ?assertEqual(<<"10">>, maps:get(<<"limit">>, Result)).

test_parse_query_string_no_value() ->
    Result = yawl_rest_handler:parse_query_string(<<"verbose&debug=true">>),
    ?assertEqual(true, maps:get(<<"verbose">>, Result)),
    ?assertEqual(<<"true">>, maps:get(<<"debug">>, Result)).

test_parse_query_string_encoded() ->
    Result = yawl_rest_handler:parse_query_string(<<"name=Hello%20World">>),
    ?assertEqual(<<"Hello World">>, maps:get(<<"name">>, Result)).

%%====================================================================
%% Error Response Tests
%%====================================================================

test_is_conflict_new() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = undefined},

    {false, _Req2, _State2} = yawl_rest_handler:is_conflict(Req, State).

test_is_conflict_running() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"wf123">>},

    Workflow = #yawl_workflow_persist{
        workflow_id = <<"wf123">>,
        spec_id = <<"spec1">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{},
        current_place = start,
        data = #{},
        parent_workflow_id = undefined,
        created_at = 1000,
        updated_at = 2000,
        completed_at = undefined,
        error = undefined
    },

    meck:expect(yawl_persistence, load_workflow, fun(<<"wf123">>) -> {ok, Workflow} end),

    {true, _Req2, _State2} = yawl_rest_handler:is_conflict(Req, State).

test_is_conflict_completed() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"wf123">>},

    Workflow = #yawl_workflow_persist{
        workflow_id = <<"wf123">>,
        spec_id = <<"spec1">>,
        pattern_type = basic_sequential,
        status = completed,
        marking = #{},
        current_place = 'end',
        data = #{},
        parent_workflow_id = undefined,
        created_at = 1000,
        updated_at = 3000,
        completed_at = 3000,
        error = undefined
    },

    meck:expect(yawl_persistence, load_workflow, fun(<<"wf123">>) -> {ok, Workflow} end),

    {false, _Req2, _State2} = yawl_rest_handler:is_conflict(Req, State).

%%====================================================================
%% Helper Function Tests
%%====================================================================

test_workflow_to_map() ->
    Workflow = #yawl_workflow_persist{
        workflow_id = <<"wf123">>,
        spec_id = <<"spec1">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{start => [token]},
        current_place = start,
        data = #{},
        parent_workflow_id = undefined,
        created_at = 1000,
        updated_at = 2000,
        completed_at = undefined,
        error = undefined
    },

    Result = yawl_rest_handler:workflow_to_map(Workflow),

    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Result)),
    ?assertEqual(<<"spec1">>, maps:get(spec_id, Result)),
    ?assertEqual(basic_sequential, maps:get(pattern_type, Result)),
    ?assertEqual(running, maps:get(status, Result)),
    ?assertEqual(1000, maps:get(created_at, Result)),
    ?assertEqual(2000, maps:get(updated_at, Result)),
    ?assertMatch(#{current_place := start}, maps:get(metadata, Result)).

test_history_to_map() ->
    History = #yawl_execution_history{
        history_id = <<"h1">>,
        workflow_id = <<"wf123">>,
        workitem_id = <<"wi1">>,
        event_type = workitem_started,
        event_data = #{task => task1},
        timestamp = 1000,
        source = orchestrator
    },

    Result = yawl_rest_handler:history_to_map(History),

    ?assertEqual(<<"h1">>, maps:get(history_id, Result)),
    ?assertEqual(<<"wf123">>, maps:get(workflow_id, Result)),
    ?assertEqual(<<"wi1">>, maps:get(workitem_id, Result)),
    ?assertEqual(workitem_started, maps:get(event_type, Result)),
    ?assertMatch(#{task := task1}, maps:get(event_data, Result)),
    ?assertEqual(1000, maps:get(timestamp, Result)).

test_to_binary_binary() ->
    ?assertEqual(<<"test">>, yawl_rest_handler:to_binary(<<"test">>)).

test_to_binary_atom() ->
    ?assertEqual(<<"test">>, yawl_rest_handler:to_binary(test)).

test_to_binary_list() ->
    ?assertEqual(<<"test">>, yawl_rest_handler:to_binary("test")).

test_to_binary_term() ->
    Result = yawl_rest_handler:to_binary({complex, term}),
    ?assert(is_binary(Result)).

test_maps_get_default() ->
    Map = #{key => <<"value">>},
    ?assertEqual(<<"value">>, yawl_rest_handler:maps_get(key, Map, undefined)),
    ?assertEqual(default, yawl_rest_handler:maps_get(missing, Map, default)).

%%====================================================================
%% Unknown Action Test
%%====================================================================

test_unknown_action() ->
    Req = mock_request(),
    State = #state{method = <<"POST">>, workflow_id = <<"wf123">>, action = <<"unknown">>},

    meck:expect(jiffy, encode, fun(Map) -> term_to_binary(Map) end),

    {JsonBody, _Req2, _State2} = yawl_rest_handler:to_json(Req, State),

    Response = jiffy:decode(JsonBody, [return_maps]),
    ?assertEqual(<<"unknown_action">>, maps:get(error, Response)),
    ?assertEqual(<<"unknown">>, maps:get(action, Response)).

%%====================================================================
%% Mock Functions
%%====================================================================

%% Create a mock Cowboy request
mock_request() ->
    meck:new(cowboy_req, [passthrough]),
    meck:expect(cowboy_req, method, fun(_Req) -> <<"GET">> end),
    meck:expect(cowboy_req, binding, fun(_Key, _Req) -> undefined end),
    meck:expect(cowboy_req, qs, fun(Req) -> {<<>>, Req} end),
    meck:expect(cowboy_req, reply, fun(_Status, _Headers, _Body, Req) -> Req end),
    #{}.

%% Create a mock Cowboy request with query string
mock_request_with_qs(QS) ->
    meck:new(cowboy_req, [passthrough]),
    meck:expect(cowboy_req, method, fun(_Req) -> <<"GET">> end),
    meck:expect(cowboy_req, binding, fun(_Key, _Req) -> undefined end),
    meck:expect(cowboy_req, qs, fun(Req) -> {QS, Req} end),
    meck:expect(cowboy_req, reply, fun(_Status, _Headers, _Body, Req) -> Req end),
    #{}.
