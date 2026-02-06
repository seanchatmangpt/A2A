%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Error Scenario Test Suite
%%%
%%% Comprehensive test suite for error handling and edge cases in the
%%% YAWL Combinatoric Testing Framework. These tests ensure the system
%%% gracefully handles invalid inputs, timeouts, memory pressure, and
%%% missing dependencies.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_error_scenario_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% Test Suite Setup and Teardown
%%====================================================================

%% @doc Setup function - runs before each test
setup() ->
    {ok, Pid} = yawl_combinatoric_test:start_link(),
    Pid.

%% @doc Teardown function - runs after each test
cleanup(_Pid) ->
    gen_server:stop(yawl_combinatoric_test),
    ok.

%%====================================================================
%% Test Generators
%%====================================================================

%% @doc Generate all tests with setup/teardown
error_scenario_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun test_invalid_pattern_name/1,
         fun test_empty_pattern_list/1,
         fun test_negative_count/1,
         fun test_zero_count/1,
         fun test_large_combination_count/1,
         fun test_timeout_scenario/1,
         fun test_memory_overflow_scenario/1,
         fun test_invalid_scenario_type/1,
         fun test_invalid_complexity/1,
         fun test_invalid_config_type/1,
         fun test_malformed_config/1,
         fun test_undefined_pattern/1,
         fun test_duplicate_patterns/1,
         fun test_non_list_patterns/1,
         fun test_validate_patterns_function/1,
         fun test_error_log_function/1,
         fun test_error_scenario_tests_function/1
     ]
    }.

%%====================================================================
%% Invalid Pattern Name Tests
%%====================================================================

test_invalid_pattern_name(_Pid) ->
    fun() ->
        ?assertMatch(
            {error, _},
            yawl_combinatoric_test:generate_pattern_combinations([invalid_pattern_xyz], 5)
        ),
        ?assertEqual(
            {error, {invalid_patterns, [invalid_pattern_xyz]}},
            yawl_combinatoric_test:validate_patterns([invalid_pattern_xyz])
        )
    end.

%%====================================================================
%% Empty Pattern List Tests
%%====================================================================

test_empty_pattern_list(_Pid) ->
    fun() ->
        ?assertEqual(
            {error, empty_pattern_list},
            yawl_combinatoric_test:validate_patterns([])
        )
    end.

%%====================================================================
%% Negative Count Tests
%%====================================================================

test_negative_count(_Pid) ->
    fun() ->
        ?assertMatch(
            {error, negative_count},
            yawl_combinatoric_test:generate_pattern_combinations([basic_sequential], -5)
        )
    end.

%%====================================================================
%% Zero Count Tests
%%====================================================================

test_zero_count(_Pid) ->
    fun() ->
        ?assertMatch(
            {error, zero_count},
            yawl_combinatoric_test:generate_pattern_combinations([basic_sequential], 0)
        )
    end.

%%====================================================================
%% Large Combination Count Tests (Graceful Degradation)
%%====================================================================

test_large_combination_count(_Pid) ->
    fun() ->
        %% Test that large counts (>10000) are handled gracefully
        MaxSafe = 10000,
        {ok, Result} = yawl_combinatoric_test:generate_pattern_combinations(
            [basic_sequential, parallel_split], 50000
        ),
        ?assert(length(Result) =< MaxSafe)
    end.

%%====================================================================
%% Timeout Scenario Tests
%%====================================================================

test_timeout_scenario(_Pid) ->
    fun() ->
        %% Create a test that will timeout
        TestID = <<"timeout_test_1">>,
        Options = #{timeout => 100, count => 1000000},  %% Very short timeout

        Result = try
            yawl_combinatoric_test:execute_combinatoric_test(
                TestID,
                [basic_sequential],
                #{},
                Options
            )
        catch
            _:Error -> Error
        end,

        %% The test should either timeout or complete gracefully
        ?assert(is_map(Result) orelse is_tuple(Result))
    end.

%%====================================================================
%% Memory Overflow Scenario Tests
%%====================================================================

test_memory_overflow_scenario(_Pid) ->
    fun() ->
        %% Check that the system can handle memory pressure
        InitialMem = erlang:memory(total),

        %% Create a test that would consume memory
        {ok, Result} = yawl_combinatoric_test:generate_pattern_combinations(
            [basic_sequential, parallel_split, exclusive_choice], 1000
        ),

        FinalMem = erlang:memory(total),

        %% Memory should not grow unbounded
        ?assert(is_list(Result)),
        ?assert(FinalMem - InitialMem < 100000000)  %% Less than 100MB growth
    end.

%%====================================================================
%% Invalid Scenario Type Tests
%%====================================================================

test_invalid_scenario_type(_Pid) ->
    fun() ->
        ?assertMatch(
            {error, _},
            yawl_combinatoric_test:create_test_scenario(invalid_scenario_type, #{}, medium)
        )
    end.

%%====================================================================
%% Invalid Complexity Tests
%%====================================================================

test_invalid_complexity(_Pid) ->
    fun() ->
        ?assertEqual(
            {error, {invalid_complexity, invalid_complexity}},
            yawl_scenario_generator:validate_complexity(invalid_complexity)
        ),
        ?assertEqual(
            {error, {invalid_complexity, 123}},
            yawl_scenario_generator:validate_complexity(123)
        )
    end.

%%====================================================================
%% Invalid Config Type Tests
%%====================================================================

test_invalid_config_type(_Pid) ->
    fun() ->
        ?assertEqual(
            {error, {invalid_config_type, "not_a_map"}},
            yawl_scenario_generator:validate_config("not_a_map")
        ),
        ?assertEqual(
            {error, {invalid_config_type, 123}},
            yawl_scenario_generator:validate_config(123)
        )
    end.

%%====================================================================
%% Malformed Config Tests
%%====================================================================

test_malformed_config(_Pid) ->
    fun() ->
        Result = try
            yawl_combinatoric_test:create_test_scenario(business, "invalid_config", medium)
        catch
            _:Error -> {error, Error}
        end,
        ?assertMatch({error, _}, Result)
    end.

%%====================================================================
%% Undefined Pattern Tests
%%====================================================================

test_undefined_pattern(_Pid) ->
    fun() ->
        ?assertMatch(
            {error, {invalid_patterns, [_]}},
            yawl_combinatoric_test:validate_patterns([undefined_pattern_atom])
        )
    end.

%%====================================================================
%% Duplicate Patterns Tests
%%====================================================================

test_duplicate_patterns(_Pid) ->
    fun() ->
        %% Duplicate patterns should be allowed with warning
        ?assertEqual(
            {warning, duplicate_patterns_found},
            yawl_combinatoric_test:validate_patterns([basic_sequential, basic_sequential])
        )
    end.

%%====================================================================
%% Non-List Patterns Tests
%%====================================================================

test_non_list_patterns(_Pid) ->
    fun() ->
        ?assertEqual(
            {error, {invalid_patterns_type, "Patterns must be a list"}},
            yawl_combinatoric_test:validate_patterns(not_a_list)
        )
    end.

%%====================================================================
%% Validate Patterns Function Tests
%%====================================================================

test_validate_patterns_function(_Pid) ->
    fun() ->
        %% Test valid patterns
        ?assertEqual(
            {ok, [basic_sequential, parallel_split]},
            yawl_combinatoric_test:validate_patterns([basic_sequential, parallel_split])
        ),

        %% Test invalid patterns
        ?assertMatch(
            {error, {invalid_patterns, _}},
            yawl_combinatoric_test:validate_patterns([invalid_pattern])
        )
    end.

%%====================================================================
%% Error Log Function Tests
%%====================================================================

test_error_log_function(_Pid) ->
    fun() ->
        LogPath = yawl_combinatoric_test:get_error_log_path(),

        %% Test logging without details
        ok = yawl_combinatoric_test:log_error("test_context", test_error),

        %% Test logging with details
        ok = yawl_combinatoric_test:log_error(
            "test_context_detailed",
            test_error_detailed,
            #{key => value}
        ),

        %% Verify log file exists
        ?assert(filelib:is_file(LogPath))
    end.

%%====================================================================
%% Error Scenario Tests Function Tests
%%====================================================================

test_error_scenario_tests_function(_Pid) ->
    fun() ->
        %% Run all error scenario tests
        {ok, Results} = yawl_combinatoric_test:error_scenario_tests(),

        %% Verify we get results for all expected test scenarios
        ?assert(is_list(Results)),
        ?assert(length(Results) >= 10),

        %% Check that each result has a test_name
        lists:foreach(fun(Result) ->
            ?assert(maps:is_key(test_name, Result))
        end, Results)
    end.

%%====================================================================
%% Integration Tests with Scenario Generator
%%====================================================================

%% @doc Test error scenario generation through scenario generator
error_scenario_generation_test_() ->
    {setup,
     fun() ->
         application:ensure_all_started(a2a_erl),
         ok
     end,
     fun(_) ->
         application:stop(a2a_erl)
     end,
     fun(_) -> [
         ?_test(begin
             %% Test error scenario generation
             Result = yawl_scenario_generator:generate_error_scenario(
                 order_processing,
                 medium
             ),
             ?assert(is_map(Result)),
             ?assertEqual(error, maps:get(type, Result)),
             ?assert(maps:is_key(failure_injections, Result))
         end)
     ]
    end}.

%%====================================================================
%% Validation Helper Tests
%%====================================================================

validation_helpers_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun test_business_domain_validation/1,
         fun test_complexity_validation/1,
         fun test_dependency_checking/1
     ]
    }.

test_business_domain_validation(_Pid) ->
    fun() ->
        %% Valid domains
        ?assertEqual(ok, yawl_scenario_generator:validate_business_domain(order_processing)),
        ?assertEqual(ok, yawl_scenario_generator:validate_business_domain(document_workflow)),

        %% Invalid domain
        ?assertMatch(
            {error, {unknown_domain, _}},
            yawl_scenario_generator:validate_business_domain(invalid_domain)
        ),

        %% Invalid type
        ?assertMatch(
            {error, {invalid_domain_type, _}},
            yawl_scenario_generator:validate_business_domain("not_an_atom")
        )
    end.

test_complexity_validation(_Pid) ->
    fun() ->
        %% Valid complexities
        ?assertEqual(ok, yawl_scenario_generator:validate_complexity(low)),
        ?assertEqual(ok, yawl_scenario_generator:validate_complexity(medium)),
        ?assertEqual(ok, yawl_scenario_generator:validate_complexity(high)),

        %% Invalid complexities
        ?assertMatch(
            {error, {invalid_complexity_value, _}},
            yawl_scenario_generator:validate_complexity(invalid)
        ),
        ?assertMatch(
            {error, {invalid_complexity_value, _}},
            yawl_scenario_generator:validate_complexity(123)
        )
    end.

test_dependency_checking(_Pid) ->
    fun() ->
        MissingDeps = yawl_scenario_generator:check_dependencies(),
        ?assert(is_list(MissingDeps))
    end.
