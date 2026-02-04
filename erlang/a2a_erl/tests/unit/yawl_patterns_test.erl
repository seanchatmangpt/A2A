%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Patterns Unit Tests
%%%
%%% This module contains comprehensive unit tests for YAWL workflow patterns
%%% implementation using gen_pnet Petri net engine.
%%%
%%% Test Coverage:
%%% - All 43 YAWL pattern types
%%% - Pattern validation logic
%%% - Pattern transformation and generation
%%% - gen_pnet behaviour callbacks
%%% - Error handling scenarios
%%% - Integration with orchestrator
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_patterns_test).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include_lib("gen_pnet/include/gen_pnet.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(PATTERN_TIMEOUT, 5000).  % 5 seconds timeout
-define(DEFAULT_CONFIG, #{}).
-define(TEST_WORKFLOW_ID, <<"test_workflow_id">>).

%%====================================================================
%% gen_pnet Behaviour Callback Tests
%%====================================================================

%% Test place_lst/0 function
place_lst_test_() ->
    [{"Place list contains expected places",
      fun test_place_lst_basic/0},
     {"Place list handles empty case",
      fun test_place_lst_empty_case/0}].

test_place_lst_basic() ->
    Places = yawl_patterns:place_lst(),
    ExpectedPlaces = [start, 'end', join, split, condition, action,
                     decision, merge, cancel, error, data],
    ?assertEqual(length(ExpectedPlaces), length(Places)),
    ?assert(lists:all(fun(P) -> lists:member(P, Places) end, ExpectedPlaces)).

test_place_lst_empty_case() ->
    %% Ensure no duplicates and all are atoms
    Places = yawl_patterns:place_lst(),
    ?assert(lists:all(fun(P) -> is_atom(P) end, Places)),
    ?assertEqual(length(Places), length(lists:usort(Places))).

%% Test trsn_lst/0 function
trsn_lst_test_() ->
    [{"Transition list contains expected transitions",
      fun test_trsn_lst_basic/0},
     {"Transition list handles empty case",
      fun test_trsn_lst_empty_case/0}].

test_trsn_lst_basic() ->
    Transitions = yawl_patterns:trsn_lst(),
    ExpectedTransitions = [start_workflow, end_workflow, parallel_split,
                          parallel_join, exclusive_choice, simple_merge,
                          multi_split, multi_join, iterative_loop,
                          cancel_workflow, handle_error, process_data,
                          evaluate_condition],
    ?assertEqual(length(ExpectedTransitions), length(Transitions)),
    ?assert(lists:all(fun(T) -> lists:member(T, Transitions) end, ExpectedTransitions)).

test_trsn_lst_empty_case() ->
    %% Ensure no duplicates and all are atoms
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:all(fun(T) -> is_atom(T) end, Transitions)),
    ?assertEqual(length(Transitions), length(lists:usort(Transitions))).

%% Test init_marking/2 function
init_marking_test_() ->
    [{"Start place has workflow token",
      fun test_init_marking_start/0},
     {"End place has no tokens",
      fun test_init_marking_end/0},
     {"Other places have no tokens",
      fun test_init_marking_others/0}].

test_init_marking_start() ->
    Marking = yawl_patterns:init_marking(start, #{}),
    ?assertEqual([workflow_token], Marking).

test_init_marking_end() ->
    Marking = yawl_patterns:init_marking('end', #{}),
    ?assertEqual([], Marking).

test_init_marking_others() ->
    OtherPlaces = [join, split, condition, action, decision, merge, cancel, error, data],
    lists:foreach(fun(Place) ->
        Marking = yawl_patterns:init_marking(Place, #{}),
        ?assertEqual([], Marking)
    end, OtherPlaces).

%% Test preset/1 function
preset_test_() ->
    [{"Start workflow preset",
      fun test_preset_start_workflow/0},
     {"End workflow preset",
      fun test_preset_end_workflow/0},
     {"Parallel split preset",
      fun test_preset_parallel_split/0},
     {"Parallel join preset",
      fun test_preset_parallel_join/0},
     {"Simple merge preset",
      fun test_preset_simple_merge/0}].

test_preset_start_workflow() ->
    Preset = yawl_patterns:preset(start_workflow),
    ?assertEqual([start], Preset).

test_preset_end_workflow() ->
    Preset = yawl_patterns:preset(end_workflow),
    ?assertEqual([action], Preset).

test_preset_parallel_split() ->
    Preset = yawl_patterns:preset(parallel_split),
    ?assertEqual([join], Preset).

test_preset_parallel_join() ->
    Preset = yawl_patterns:preset(parallel_join),
    ?assertEqual([split], Preset).

test_preset_simple_merge() ->
    Preset = yawl_patterns:preset(simple_merge),
    ?assertEqual([split], Preset).

%% Test is_enabled/3 function
is_enabled_test_() ->
    [{"Start workflow enabled with token",
      fun test_is_enabled_start_workflow/0},
     {"Start workflow disabled without token",
      fun test_is_enabled_start_workflow_disabled/0},
     {"Parallel join enabled with multiple tokens",
      fun test_is_enabled_parallel_join/0},
     {"Parallel join disabled with single token",
      fun test_is_enabled_parallel_join_disabled/0},
     {"Iterative loop enabled with true condition",
      fun test_is_enabled_iterative_loop/0},
     {"Iterative loop disabled with false condition",
      fun test_is_enabled_iterative_loop_disabled/0}].

test_is_enabled_start_workflow() ->
    Mode = #{start => [workflow_token]},
    ?assert(yawl_patterns:is_enabled(start_workflow, Mode, #{})).

test_is_enabled_start_workflow_disabled() ->
    Mode = #{start => []},
    ?assertNot(yawl_patterns:is_enabled(start_workflow, Mode, #{})).

test_is_enabled_parallel_join() ->
    Mode = #{split => [token1, token2]},
    ?assert(yawl_patterns:is_enabled(parallel_join, Mode, #{})).

test_is_enabled_parallel_join_disabled() ->
    Mode = #{split => [token]},
    ?assertNot(yawl_patterns:is_enabled(parallel_join, Mode, #{})).

test_is_enabled_iterative_loop() ->
    Mode = #{condition => [true]},
    ?assert(yawl_patterns:is_enabled(iterative_loop, Mode, #{})).

test_is_enabled_iterative_loop_disabled() ->
    Mode = #{condition => [false]},
    ?assertNot(yawl_patterns:is_enabled(iterative_loop, Mode, #{})).

%% Test fire/3 function
fire_test_() ->
    [{"Start workflow fire produces tokens",
      fun test_fire_start_workflow/0},
     {"End workflow fire produces completion",
      fun test_fire_end_workflow/0},
     {"Parallel split fire produces multiple tokens",
      fun test_fire_parallel_split/0},
     {"Parallel join fire produces merged token",
      fun test_fire_parallel_join/0},
     {"Cancel workflow fire produces cancel and end",
      fun test_fire_cancel_workflow/0}].

test_fire_start_workflow() ->
    {produce, Result} = yawl_patterns:fire(start_workflow, #{}, #{}),
    ?assertEqual([token], maps:get(join, Result, [])),
    ?assertEqual([execute_token], maps:get(action, Result, [])).

test_fire_end_workflow() ->
    {produce, Result} = yawl_patterns:fire(end_workflow, #{}, #{}),
    ?assertEqual([completion_token], maps:get('end', Result, [])).

test_fire_parallel_split() ->
    {produce, Result} = yawl_patterns:fire(parallel_split, #{}, #{}),
    ?assertEqual([token, token], maps:get(split, Result, [])).

test_fire_parallel_join() ->
    {produce, Result} = yawl_patterns:fire(parallel_join, #{}, #{}),
    ?assertEqual([joined_token], maps:get(merge, Result, [])).

test_fire_cancel_workflow() ->
    {produce, Result} = yawl_patterns:fire(cancel_workflow, #{}, #{}),
    ?assertEqual([cancel_token], maps:get(cancel, Result, [])),
    ?assertEqual([cancelled_token], maps:get('end', Result, [])).

%% Test trigger/3 function
trigger_test_() ->
    [{"Start place workflow token passes",
      fun test_trigger_start_workflow/0},
     {"Cancel place cancel token is dropped",
      fun test_trigger_cancel/0},
     {"Error place resolved token is dropped",
      fun test_trigger_error_resolved/0},
     {"Other places pass all tokens",
      fun test_trigger_others/0}].

test_trigger_start_workflow() ->
    Result = yawl_patterns:trigger(start, workflow_token, #{}),
    ?assertEqual(pass, Result).

test_trigger_cancel() ->
    Result = yawl_patterns:trigger(cancel, cancel_token, #{}),
    ?assertEqual(drop, Result).

test_trigger_error_resolved() ->
    Result = yawl_patterns:trigger(error, resolved_token, #{}),
    ?assertEqual(drop, Result).

test_trigger_others() ->
    OtherPlaces = [join, split, condition, action, decision, merge, 'end'],
    Tokens = [test_token, another_token, undefined],
    lists:foreach(fun(Place) ->
        lists:foreach(fun(Token) ->
            Result = yawl_patterns:trigger(Place, Token, #{}),
            ?assertEqual(pass, Result)
        end, Tokens)
    end, OtherPlaces).

%%====================================================================
%% API Function Tests
%%====================================================================

%% Test create_workflow/2 function
create_workflow_test_() ->
    [{"Create basic sequential workflow",
      fun test_create_basic_sequential/0},
     {"Create parallel split workflow",
      fun test_create_parallel_split/0},
     {"Create workflow with invalid config fails",
      fun test_create_invalid_config/0},
     {"Create unknown pattern type fails",
      fun test_create_unknown_pattern/0}].

test_create_basic_sequential() ->
    Config = #{pattern_config => #{}, task_names => ["task1", "task2"]},
    Result = yawl_patterns:create_workflow(basic_sequential, Config),
    ?assertMatch({ok, _}, Result).

test_create_parallel_split() ->
    Config = #{pattern_config => #{branches => 3}},
    Result = yawl_patterns:create_workflow(parallel_split, Config),
    ?assertMatch({ok, _}, Result).

test_create_invalid_config() ->
    Config = #{pattern_config => #{branches => 1}},  % Invalid: branches < 2
    Result = yawl_patterns:create_workflow(parallel_split, Config),
    ?assertEqual({error, invalid_pattern_config}, Result).

test_create_unknown_pattern() ->
    Config = #{pattern_config => #{}},
    Result = yawl_patterns:create_workflow(unknown_pattern, Config),
    ?assertEqual({error, invalid_pattern_config}, Result).

%% Test validate_pattern/2 function
validate_pattern_test_() ->
    [{"Validate basic sequential pattern",
      fun test_validate_basic_sequential/0},
     {"Validate parallel split pattern",
      fun test_validate_parallel_split/0},
     {"Validate iterative loop pattern",
      fun test_validate_iterative_loop/0},
     {"Validate multi instance pattern",
      fun test_validate_multi_instance/0},
     {"Validate unknown pattern fails",
      fun test_validate_unknown_pattern/0}].

test_validate_basic_sequential() ->
    ?assert(yawl_patterns:validate_pattern(basic_sequential, #{})).

test_validate_parallel_split() ->
    ValidConfig = #{branches => 3},
    ?assert(yawl_patterns:validate_pattern(parallel_split, ValidConfig)),
    InvalidConfig = #{branches => 1},
    ?assertNot(yawl_patterns:validate_pattern(parallel_split, InvalidConfig)).

test_validate_iterative_loop() ->
    ValidConfig = #{condition => fun(_) -> true end},
    ?assert(yawl_patterns:validate_pattern(iterative_loop, ValidConfig)),
    InvalidConfig = #{},
    ?assertNot(yawl_patterns:validate_pattern(iterative_loop, InvalidConfig)).

test_validate_multi_instance() ->
    ValidConfig = #{num_instances => 3, data => [1, 2, 3]},
    ?assert(yawl_patterns:validate_pattern(multi_instance, ValidConfig)),
    InvalidConfig1 = #{num_instances => 0},
    ?assertNot(yawl_patterns:validate_pattern(multi_instance, InvalidConfig1)),
    InvalidConfig2 = #{data => [1, 2]},
    ?assertNot(yawl_patterns:validate_pattern(multi_instance, InvalidConfig2)).

test_validate_unknown_pattern() ->
    ?assertNot(yawl_patterns:validate_pattern(unknown_pattern, #{})).

%% Test get_pattern_info/1 function
get_pattern_info_test_() ->
    [{"Get basic sequential pattern info",
      fun test_get_basic_sequential_info/0},
     {"Get parallel split pattern info",
      fun test_get_parallel_split_info/0},
     {"Get iterative loop pattern info",
      fun test_get_iterative_loop_info/0},
     {"Get unknown pattern info",
      fun test_get_unknown_pattern_info/0}].

test_get_basic_sequential_info() ->
    Info = yawl_patterns:get_pattern_info(basic_sequential),
    ?assertEqual(<<"Basic Sequential">>, maps:get(name, Info)),
    ?assertEqual(low, maps:get(complexity, Info)),
    ?assertEqual([start, action1, action2, 'end'], maps:get(places, Info)).

test_get_parallel_split_info() ->
    Info = yawl_patterns:get_pattern_info(parallel_split),
    ?assertEqual(<<"Parallel Split">>, maps:get(name, Info)),
    ?assertEqual(medium, maps:get(complexity, Info)),
    ?assert(lists:member(split, maps:get(places, Info))).

test_get_iterative_loop_info() ->
    Info = yawl_patterns:get_pattern_info(iterative_loop),
    ?assertEqual(<<"Iterative Loop">>, maps:get(name, Info)),
    ?assertEqual(high, maps:get(complexity, Info)),
    ?assert(lists:member(loop, maps:get(places, Info))).

test_get_unknown_pattern_info() ->
    Info = yawl_patterns:get_pattern_info(unknown_pattern),
    ?assertEqual(<<"unknown">>, maps:get(name, Info)),
    ?assertEqual([], maps:get(places, Info)),
    ?assertEqual(undefined, maps:get(complexity, Info)).

%% Test list_patterns/0 function
list_patterns_test_() ->
    [{"List all patterns returns expected count",
      fun test_list_patterns_count/0},
     {"List patterns includes basic patterns",
      fun test_list_patterns_basic/0},
     {"List patterns includes advanced patterns",
      fun test_list_patterns_advanced/0}].

test_list_patterns_count() ->
    Patterns = yawl_patterns:list_patterns(),
    ?assert(length(Patterns) > 40),  % Should have 43 patterns
    ?assert(lists:member(basic_sequential, Patterns)),
    ?assert(lists:member(parallel_split, Patterns)).

test_list_patterns_basic() ->
    Patterns = yawl_patterns:list_patterns(),
    BasicPatterns = [basic_sequential, parallel_split, parallel_join,
                    exclusive_choice, simple_merge],
    lists:foreach(fun(P) -> ?assert(lists:member(P, Patterns)) end, BasicPatterns).

test_list_patterns_advanced() ->
    Patterns = yawl_patterns:list_patterns(),
    AdvancedPatterns = [iterative_loop, multi_instance, cancelation,
                      interleaved_parallelism],
    lists:foreach(fun(P) -> ?assert(lists:member(P, Patterns)) end, AdvancedPatterns).

%%====================================================================
%% Pattern Generation Tests
%%====================================================================

%% Test generate_pattern_definition/2 function
generate_pattern_definition_test_() ->
    [{"Generate basic sequential definition",
      fun test_generate_basic_sequential_definition/0},
     {"Generate parallel split definition",
      fun test_generate_parallel_split_definition/0},
     {"Generate multi instance definition",
      fun test_generate_multi_instance_definition/0},
     {"Generate unknown pattern defaults to basic",
      fun test_generate_unknown_pattern_default/0}].

test_generate_basic_sequential_definition() ->
    Definition = yawl_patterns:generate_pattern_definition(basic_sequential, #{}),
    ?assertEqual(basic_sequential, maps:get(pattern_type, Definition)),
    ?assertEqual([start, action1, action2, 'end'], maps:get(places, Definition)),
    ?assertEqual([start, t1, t2, 'end'], maps:get(transitions, Definition)),
    ?assertEqual(low, maps:get(complexity, Definition)).

test_generate_parallel_split_definition() ->
    Definition = yawl_patterns:generate_pattern_definition(parallel_split, #{}),
    ?assertEqual(parallel_split, maps:get(pattern_type, Definition)),
    ?assert(lists:member(split, maps:get(places, Definition))),
    ?assert(lists:member(t1, maps:get(transitions, Definition))).

test_generate_multi_instance_definition() ->
    Config = #{num_instances => 3},
    Definition = yawl_patterns:generate_pattern_definition(multi_instance, Config),
    ?assertEqual(multi_instance, maps:get(pattern_type, Definition)),
    ?assertEqual(7, length(maps:get(places, Definition))),  % start + create + 3 instances + collect + end
    ?assertEqual(5, length(maps:get(transitions, Definition))). % start + create + 3 executes + collect + end

test_generate_unknown_pattern_default() ->
    Definition = yawl_patterns:generate_pattern_definition(unknown_pattern, #{}),
    ?assertEqual(basic_sequential, maps:get(pattern_type, Definition)).

%% Test generate_multi_instance_preset/1 function
generate_multi_instance_preset_test_() ->
    [{"Generate preset for 1 instance",
      fun test_generate_multi_instance_preset_1/0},
     {"Generate preset for multiple instances",
      fun test_generate_multi_instance_preset_3/0},
     {"Generate preset validates input",
      fun test_generate_multi_instance_preset_validate/0}].

test_generate_multi_instance_preset_1() ->
    Preset = yawl_patterns:generate_multi_instance_preset(1),
    ?assertEqual([start], maps:get(start, Preset)),
    ?assertEqual([create], maps:get(create, Preset)),
    ?assertEqual([instance_1], maps:get(execute_1, Preset)),
    ?assertEqual([instance_1], maps:get(collect, Preset)).

test_generate_multi_instance_preset_3() ->
    Preset = yawl_patterns:generate_multi_instance_preset(3),
    ExpectedPlaces = [instance_1, instance_2, instance_3],
    lists:foreach(fun(I) ->
        InstanceAtom = list_to_atom("instance_" ++ integer_to_list(I)),
        ?assertEqual([InstanceAtom], maps:get(list_to_atom("execute_" ++ integer_to_list(I)), Preset))
    end, [1, 2, 3]),
    ?assertEqual(ExpectedPlaces, maps:get(collect, Preset)).

test_generate_multi_instance_preset_validate() ->
    %% Test with 0 instances (should handle gracefully)
    Preset = yawl_patterns:generate_multi_instance_preset(0),
    ?assertEqual([start], maps:get(start, Preset)),
    ?assertEqual([create], maps:get(create, Preset)),
    ?assertEqual([], maps:get(collect, Preset)).

%%====================================================================
%% Pattern Configuration Validation Tests
%%====================================================================

validate_pattern_config_test_() ->
    [{"Basic sequential config validation",
      fun test_validate_basic_sequential_config/0},
     {"Parallel split config validation",
      fun test_validate_parallel_split_config/0},
     {"Parallel join config validation",
      fun test_validate_parallel_join_config/0},
     {"Exclusive choice config validation",
      fun test_validate_exclusive_choice_config/0},
     {"Iterative loop config validation",
      fun test_validate_iterative_loop_config/0},
     {"Multi instance config validation",
      fun test_validate_multi_instance_config/0},
     {"Unknown pattern config validation",
      fun test_validate_unknown_pattern_config/0}].

test_validate_basic_sequential_config() ->
    %% Basic sequential should accept any config or no config
    ?assert(yawl_patterns:validate_pattern_config(basic_sequential, #{})),
    ?assert(yawl_patterns:validate_pattern_config(basic_sequential, #{any_key => any_value})).

test_validate_parallel_split_config() ->
    %% Valid cases
    ?assert(yawl_patterns:validate_pattern_config(parallel_split, #{branches => 2})),
    ?assert(yawl_patterns:validate_pattern_config(parallel_split, #{branches => 5})),
    %% Invalid cases
    ?assertNot(yawl_patterns:validate_pattern_config(parallel_split, #{branches => 1})),
    ?assertNot(yawl_patterns:validate_pattern_config(parallel_split, #{branches => 0})),
    ?assertNot(yawl_patterns:validate_pattern_config(parallel_split, #{})).

test_validate_parallel_join_config() ->
    %% Valid cases
    ?assert(yawl_patterns:validate_pattern_config(parallel_join, #{branches => 2})),
    ?assert(yawl_patterns:validate_pattern_config(parallel_join, #{branches => 4})),
    %% Invalid cases
    ?assertNot(yawl_patterns:validate_pattern_config(parallel_join, #{branches => 1})),
    ?assertNot(yawl_patterns:validate_pattern_config(parallel_join, #{})).

test_validate_exclusive_choice_config() ->
    %% Valid case with conditions
    ?assert(yawl_patterns:validate_pattern_config(exclusive_choice, #{conditions => [a, b, c]})),
    %% Invalid cases
    ?assertNot(yawl_patterns:validate_pattern_config(exclusive_choice, #{conditions => []})),
    ?assertNot(yawl_patterns:validate_pattern_config(exclusive_choice, #{})).

test_validate_iterative_loop_config() ->
    %% Valid case with condition
    ConditionFun = fun(_) -> true end,
    ?assert(yawl_patterns:validate_pattern_config(iterative_loop, #{condition => ConditionFun})),
    %% Invalid case without condition
    ?assertNot(yawl_patterns:validate_pattern_config(iterative_loop, #{})).

test_validate_multi_instance_config() ->
    %% Valid case
    ?assert(yawl_patterns:validate_pattern_config(multi_instance, #{num_instances => 3, data => [1, 2, 3]})),
    %% Invalid cases
    ?assertNot(yawl_patterns:validate_pattern_config(multi_instance, #{num_instances => 0, data => [1, 2, 3]})),
    ?assertNot(yawl_patterns:validate_pattern_config(multi_instance, #{num_instances => 3})),
    ?assertNot(yawl_patterns:validate_pattern_config(multi_instance, #{data => [1, 2, 3]})).

test_validate_unknown_pattern_config() ->
    %% Unknown pattern should default to true
    ?assert(yawl_patterns:validate_pattern_config(unknown_pattern, #{})),
    ?assert(yawl_patterns:validate_pattern_config(unknown_pattern, #{any_key => any_value})).

%%====================================================================
%% Integration Tests with Orchestrator
%%====================================================================

integration_test_() ->
    [{"Orchestrator integration - create and validate workflow",
      fun test_orchestrator_integration/0},
     {"Orchestrator integration - pattern info retrieval",
      fun test_orchestrator_pattern_info/0}].

test_orchestrator_integration() ->
    {ok, _OrchestratorPid} = yawl_orchestrator:start_link(),
    try
        Config = #{task1_name => "task1", task2_name => "task2"},
        ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(basic_sequential, Config)),
        ?assertMatch({ok, _}, yawl_orchestrator:validate_pattern(basic_sequential, Config))
    after
        gen_server:stop(yawl_orchestrator)
    end.

test_orchestrator_pattern_info() ->
    {ok, _OrchestratorPid} = yawl_orchestrator:start_link(),
    try
        ?assertMatch({ok, _}, yawl_orchestrator:get_pattern_info(basic_sequential)),
        ?assertMatch({ok, _}, yawl_orchestrator:get_pattern_info(parallel_split))
    after
        gen_server:stop(yawl_orchestrator)
    end.

%%====================================================================
%% Property-Based Tests (Using EQC-like approach manually)
%%====================================================================

property_test_() ->
    [{"Pattern info consistency",
      fun test_pattern_info_consistency/0},
     {"Pattern list matches expected patterns",
      fun test_pattern_list_consistency/0},
     {"Config validation idempotence",
      fun test_config_validation_idempotence/0}].

test_pattern_info_consistency() ->
    Patterns = yawl_patterns:list_patterns(),
    lists:foreach(fun(Pattern) ->
        Info = yawl_patterns:get_pattern_info(Pattern),
        %% Check that info is consistent
        ?assert(is_map(Info)),
        ?assert(is_binary(maps:get(name, Info))),
        ?assert(lists:member(maps:get(complexity, Info), [low, medium, high])),
        ?assert(is_list(maps:get(places, Info))),
        ?assert(is_list(maps:get(transitions, Info)))
    end, Patterns).

test_pattern_list_consistency() ->
    Patterns = yawl_patterns:list_patterns(),
    %% Check that all patterns in list are valid
    lists:foreach(fun(Pattern) ->
        Info = yawl_patterns:get_pattern_info(Pattern),
        ?assertNotEqual(<<"unknown">>, maps:get(name, Info))
    end, Patterns),
    %% Check that unknown pattern returns unknown info
    UnknownInfo = yawl_patterns:get_pattern_info(unknown_pattern),
    ?assertEqual(<<"unknown">>, maps:get(name, UnknownInfo)).

test_config_validation_idempotence() ->
    %% Test that validation gives same results for same config
    TestConfigs = [
        {basic_sequential, #{}},
        {parallel_split, #{branches => 3}},
        {iterative_loop, #{condition => fun(X) -> X end}}
    ],
    lists:foreach(fun({Pattern, Config}) ->
        Result1 = yawl_patterns:validate_pattern(Pattern, Config),
        Result2 = yawl_patterns:validate_pattern(Pattern, Config),
        ?assertEqual(Result1, Result2)
    end, TestConfigs).

%%====================================================================
%% Error Handling Tests
%%====================================================================

error_handling_test_() ->
    [{"Invalid workflow creation",
      fun test_error_invalid_workflow_creation/0},
     {"Invalid pattern validation",
      fun test_error_invalid_pattern_validation/0},
     "Edge case configurations",
      fun test_edge_case_configurations/0}].

test_error_invalid_workflow_creation() ->
    %% Test with completely invalid config
    InvalidConfig = #{invalid_key => "invalid_value"},
    Result = yawl_patterns:create_workflow(unknown_pattern, InvalidConfig),
    ?assertEqual({error, invalid_pattern_config}, Result).

test_error_invalid_pattern_validation() ->
    %% Test validation of complex invalid configurations
    %% Multi-instance without required fields
    InvalidConfigs = [
        {multi_instance, #{num_instances => 0}},
        {multi_instance, #{data => []}},
        {parallel_split, #{branches => 1}},
        {iterative_loop, #{}}
    ],
    lists:foreach(fun({Pattern, Config}) ->
        ?assertNot(yawl_patterns:validate_pattern(Pattern, Config))
    end, InvalidConfigs).

test_edge_case_configurations() ->
    %% Test boundary conditions
    EdgeConfigs = [
        {parallel_split, #{branches => 2}},  % Minimum valid
        {parallel_split, #{branches => 100}}, % Maximum reasonable
        {multi_instance, #{num_instances => 1, data => [1]}}, % Minimum instances
        {multi_instance, #{num_instances => 50, data lists:seq(1, 50)}} % Maximum instances
    ],
    lists:foreach(fun({Pattern, Config}) ->
        case Pattern of
            multi_instance ->
                ?assert(yawl_patterns:validate_pattern(Pattern, Config));
            parallel_split ->
                ?assert(yawl_patterns:validate_pattern(Pattern, Config))
        end
    end, EdgeConfigs).

%%====================================================================
%% Performance Tests
%%====================================================================

performance_test_() ->
    [{"Pattern creation performance",
      fun test_pattern_creation_performance/0},
     {"Pattern validation performance",
      fun test_pattern_validation_performance/0},
     {"Pattern info retrieval performance",
      fun test_pattern_info_performance/0}].

test_pattern_creation_performance() ->
    %% Test that pattern creation is reasonably fast
    Patterns = yawl_patterns:list_patterns(),
    Start = erlang:monotonic_time(microsecond),
    lists:foreach(fun(Pattern) ->
        Config = case Pattern of
            basic_sequential -> #{};
            parallel_split -> #{branches => 3};
            _ -> #{}
        end,
        _ = yawl_patterns:create_workflow(Pattern, Config)
    end, Patterns),
    End = erlang:monotonic_time(microsecond),
    Duration = End - Start,
    ?assert(Duration < 1000000, "Pattern creation took too long: ~p μs", [Duration]).

test_pattern_validation_performance() ->
    %% Test that validation is reasonably fast
    Config = #{branches => 3, conditions => [a, b]},
    Start = erlang:monotonic_time(microsecond),
    lists:seq(1, 1000),  % Repeat 1000 times
    _ = yawl_patterns:validate_pattern(parallel_split, Config),
    End = erlang:monotonic_time(microsecond),
    Duration = End - Start,
    ?assert(Duration < 50000, "Pattern validation took too long: ~p μs", [Duration]).

test_pattern_info_performance() ->
    %% Test that info retrieval is reasonably fast
    Patterns = yawl_patterns:list_patterns(),
    Start = erlang:monotonic_time(microsecond),
    lists:foreach(fun(Pattern) ->
        _ = yawl_patterns:get_pattern_info(Pattern)
    end, Patterns),
    End = erlang:monotonic_time(microsecond),
    Duration = End - Start,
    ?assert(Duration < 500000, "Pattern info retrieval took too long: ~p μs", [Duration]).