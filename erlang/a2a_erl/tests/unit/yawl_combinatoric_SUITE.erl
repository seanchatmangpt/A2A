%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Combinatoric Test Suite
%%%
%%% Comprehensive test suite for combinatorial testing of YAWL
%%% workflow patterns across various business scenarios.
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_combinatoric_SUITE).
-author("A2A Team").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

%% Test Server callbacks
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    test_sequential_combinations/1,
    test_parallel_combinations/1,
    test_nested_combinations/1,
    test_order_processing_scenario/1,
    test_document_workflow_scenario/1,
    test_data_pipeline_scenario/1,
    test_edge_case_resource_contention/1,
    test_edge_case_deep_nesting/1,
    test_performance_high_load/1,
    test_performance_sustained_load/1,
    test_error_scenario_recovery/1,
    test_error_scenario_cancellation/1,
    test_pattern_validity/1,
    test_resource_allocation/1,
    test_business_rules/1,
    test_combination_matrix/1
]).

%% Test records
-record(test_state, {
    combinatoric_pid,
    scenario_pid,
    validation_pid,
    test_results = []
}).

%%====================================================================
%% Test Server Callbacks
%%====================================================================

all() ->
    [
        test_sequential_combinations,
        test_parallel_combinations,
        test_nested_combinations,
        test_order_processing_scenario,
        test_document_workflow_scenario,
        test_data_pipeline_scenario,
        test_edge_case_resource_contention,
        test_edge_case_deep_nesting,
        test_performance_high_load,
        test_performance_sustained_load,
        test_error_scenario_recovery,
        test_error_scenario_cancellation,
        test_pattern_validity,
        test_resource_allocation,
        test_business_rules,
        test_combination_matrix
    ].

init_per_suite(Config) ->
    %% Initialize test suite
    {ok, CombinatoricPid} = yawl_combinatoric_test:start_link(),
    State = #test_state{combinatoric_pid = CombinatoricPid},
    [{test_state, State} | Config].

end_per_suite(Config) ->
    %% Cleanup test suite
    State = proplists:get_value(test_state, Config),
    gen_server:stop(State#test_state.combinatoric_pid),
    ok.

init_per_testcase(TestCase, Config) ->
    %% Initialize individual test case
    ct:pal("Starting test case: ~p", [TestCase]),
    Config.

end_per_testcase(_TestCase, Config) ->
    %% Cleanup individual test case
    ok.

%%====================================================================
%% Sequential Combination Tests
%%====================================================================

test_sequential_combinations(Config) ->
    %% Test sequential pattern combinations
    State = proplists:get_value(test_state, Config),

    Patterns = [basic_sequential, exclusive_choice, simple_merge],
    {ok, Combinations, _} = yawl_combinatoric_test:generate_pattern_combinations(Patterns, 2),

    ?assert(length(Combinations) > 0),
    ?assert(lists:all(fun(C) -> length(C) =:= 2 end, Combinations)),

    %% Validate each combination
    lists:foreach(fun(Combo) ->
        Valid = yawl_combinatoric_test:validate_combination(Combo, #{}),
        ?assert(Valid)
    end, Combinations).

%%====================================================================
%% Parallel Combination Tests
%%====================================================================

test_parallel_combinations(Config) ->
    %% Test parallel pattern combinations
    Patterns = [parallel_split, parallel_join, simple_merge],
    {ok, Combinations, _} = yawl_combinatoric_test:generate_pattern_combinations(Patterns, 2),

    %% Verify parallel combinations
    ?assert(length(Combinations) > 0),

    %% Test parallel split and join pair
    ParallelPair = [{parallel_split, #{branches => 3}}, {parallel_join, #{branches => 3}}],
    ?assert(yawl_combinatoric_test:validate_combination(ParallelPair, #{})).

%%====================================================================
%% Nested Combination Tests
%%====================================================================

test_nested_combinations(Config) ->
    %% Test nested pattern combinations
    Patterns = [parallel_split, exclusive_choice, iterative_loop],

    %% Generate nested combinations
    NestedCombos = yawl_combinatoric_test:generate_nested_combinations(Patterns, 2),

    ?assert(length(NestedCombos) > 0),

    %% Validate nested structure
    lists:foreach(fun(Combo) ->
        case Combo of
            #{nested := _, depth := _} -> ok;
            _ -> ?assert(false, "Invalid nested combination structure")
        end
    end, NestedCombos).

%%====================================================================
%% Business Scenario Tests
%%====================================================================

test_order_processing_scenario(Config) ->
    %% Test order processing business scenario
    Scenario = yawl_scenario_generator:generate_business_scenario(order_processing, #{}),

    %% Verify scenario structure
    ?assertEqual(order_processing, maps:get(business_domain, Scenario)),
    ?assert(lists:member(scenario_id, maps:keys(Scenario))),
    ?assert(lists:member(pattern_combination, maps:keys(Scenario))),
    ?assert(lists:member(resource_allocations, maps:keys(Scenario))),
    ?assert(lists:member(business_rules, maps:keys(Scenario))),

    %% Validate scenario
    ?assert(yawl_scenario_generator:validate_scenario(Scenario)).

test_document_workflow_scenario(Config) ->
    %% Test document workflow business scenario
    Scenario = yawl_scenario_generator:generate_business_scenario(document_workflow, #{}),

    %% Verify document workflow specifics
    ?assertEqual(document_workflow, maps:get(business_domain, Scenario)),
    ?assert(length(maps:get(pattern_combination, Scenario)) >= 4),

    %% Check for required patterns in document workflow
    Patterns = [P || {P, _} <- maps:get(pattern_combination, Scenario)],
    ?assert(lists:member(exclusive_choice, Patterns)).

test_data_pipeline_scenario(Config) ->
    %% Test data pipeline business scenario
    Scenario = yawl_scenario_generator:generate_business_scenario(data_pipeline, #{}),

    %% Verify data pipeline structure
    ?assertEqual(data_pipeline, maps:get(business_domain, Scenario)),
    ?assert(maps:get(complexity, Scenario) =:= medium orelse
            maps:get(complexity, Scenario) =:= high),

    %% Verify high volume data handling
    Metadata = maps:get(metadata, Scenario),
    ?assertEqual("very_high", maps:get(data_volume, Metadata)).

%%====================================================================
%% Edge Case Tests
%%====================================================================

test_edge_case_resource_contention(Config) ->
    %% Test resource contention edge case
    Scenario = yawl_scenario_generator:generate_edge_case_scenario(order_processing, #{}),

    %% Verify edge case characteristics
    ?assertEqual(edge_case, maps:get(type, Scenario)),
    ?assert(maps:get(complexity, Scenario) =:= high),

    %% Check for resource contention configuration
    TestParams = maps:get(test_parameters, Scenario),
    ?assert(maps:get(resource_contention, TestParams)).

test_edge_case_deep_nesting(Config) ->
    %% Test deep nesting edge case
    Scenario = yawl_scenario_generator:generate_edge_case_scenario(data_pipeline, #{}),

    %% Verify deep nesting capabilities
    Patterns = maps:get(pattern_combination, Scenario),
    NestedPatterns = [P || {P, Config} <- Patterns, maps:get(depth, Config, 0) > 3],

    %% At least one deeply nested pattern should exist
    ?assert(length(NestedPatterns) > 0).

%%====================================================================
%% Performance Tests
%%====================================================================

test_performance_high_load(Config) ->
    %% Test high load performance scenario
    Scenario = yawl_scenario_generator:generate_performance_scenario(notification_system, #{}),

    %% Verify performance scenario configuration
    ?assertEqual(performance, maps:get(type, Scenario)),
    ?assert(maps:is_key(load_profile, Scenario)),
    ?assert(maps:is_key(performance_metrics, Scenario)),

    %% Verify load profile
    LoadProfile = maps:get(load_profile, Scenario),
    ?assert(maps:get(peak_load, LoadProfile) > 100),
    ?assert(maps:get(ramp_up_time, LoadProfile) > 0).

test_performance_sustained_load(Config) ->
    %% Test sustained load performance
    Scenario = yawl_scenario_generator:generate_performance_scenario(data_pipeline, #{}),

    %% Verify sustained load configuration
    LoadProfile = maps:get(load_profile, Scenario),
    ?assert(maps:get(sustained_duration, LoadProfile) > 60000),

    %% Verify performance targets
    Metrics = maps:get(performance_metrics, Scenario),
    ?assert(maps:get(target_throughput, Metrics) > 0).

%%====================================================================
%% Error Scenario Tests
%%====================================================================

test_error_scenario_recovery(Config) ->
    %% Test error recovery scenario
    Scenario = yawl_scenario_generator:generate_error_scenario(order_processing, #{}),

    %% Verify error scenario structure
    ?assertEqual(error, maps:get(type, Scenario)),
    ?assert(maps:is_key(failure_injection, Scenario)),
    ?assert(maps:is_key(recovery_strategies, Scenario)),

    %% Verify recovery strategies
    RecoveryStrategies = maps:get(recovery_strategies, Scenario),
    ?assert(length(RecoveryStrategies) > 0).

test_error_scenario_cancellation(Config) ->
    %% Test cancellation error scenario
    Scenario = yawl_scenario_generator:generate_error_scenario(document_workflow, #{}),

    %% Check for cancellation patterns
    Patterns = [P || {P, _} <- maps:get(pattern_combination, Scenario)],
    ?assert(lists:member(cancelation_block, Patterns) orelse
            lists:member(cancelation_scope, Patterns)).

%%====================================================================
%% Validation Tests
%%====================================================================

test_pattern_validity(Config) ->
    %% Test pattern validity across all combinations
    AllPatterns = yawl_patterns:list_patterns(),

    %% Each pattern should be valid
    lists:foreach(fun(Pattern) ->
        PatternInfo = yawl_patterns:get_pattern_info(Pattern),
        ?assertNotEqual(unknown, maps:get(name, PatternInfo))
    end, AllPatterns).

test_resource_allocation(Config) ->
    %% Test resource allocation validation
    Scenario = yawl_scenario_generator:generate_business_scenario(order_processing, #{}),

    Resources = maps:get(resource_allocations, Scenario),

    %% Each task should have allocated resources
    ?assert(maps:size(Resources) > 0),
    lists:foreach(fun({Task, ResourceList}) ->
        ?assert(is_list(ResourceList)),
        ?assert(length(ResourceList) > 0)
    end, maps:to_list(Resources)).

test_business_rules(Config) ->
    %% Test business rules validation
    Scenario = yawl_scenario_generator:generate_business_scenario(approval_chain, #{}),

    Rules = maps:get(business_rules, Scenario),

    %% Verify business rule structure
    ?assert(length(Rules) > 0),
    lists:foreach(fun(Rule) ->
        ?assert(lists:member(rule_id, tuple_to_list(Rule))),
        ?assert(lists:member(condition, tuple_to_list(Rule))),
        ?assert(lists:member(action, tuple_to_list(Rule)))
    end, Rules).

%%====================================================================
%% Combination Matrix Tests
%%====================================================================

test_combination_matrix(Config) ->
    %% Test comprehensive combination matrix
    BusinessDomains = yawl_scenario_generator:list_available_domains(),
    Complexities = [low, medium, high],

    %% Generate test matrix
    TestMatrix = lists:foldl(fun(Domain, Acc) ->
        lists:foldl(fun(Complexity, Acc2) ->
            Scenario = yawl_scenario_generator:generate_scenario(Domain, Complexity, #{}),
            [Scenario | Acc2]
        end, Acc, Complexities)
    end, [], BusinessDomains),

    %% Verify matrix completeness
    ExpectedSize = length(BusinessDomains) * length(Complexities),
    ?assert(length(TestMatrix) >= ExpectedSize),

    %% All scenarios should be valid
    InvalidScenarios = lists:filter(fun(S) ->
        not yawl_scenario_generator:validate_scenario(S)
    end, TestMatrix),
    ?assertEqual(0, length(InvalidScenarios)).