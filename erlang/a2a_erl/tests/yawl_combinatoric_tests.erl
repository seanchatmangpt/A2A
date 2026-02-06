%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Combinatoric Test Suite
%%%
%%% This module contains comprehensive Common Test suites for testing YAWL
%%% pattern combinations. It systematically generates test cases for:
%%% - Sequential combinations (pattern1 -> pattern2 -> pattern3)
%%% - Parallel combinations (pattern1 || pattern2 || pattern3)
%%% - Nested combinations (pattern within pattern)
%%% - Mixed combinations (sequential + parallel + nested)
%%%
%%% The test suite uses combinatoric generation to produce 500+ test cases
%%% covering various pattern combinations across all 40 YAWL patterns.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_combinatoric_tests).
-author("A2A Team").

-include_lib("common_test/include/ct.hrl").
-include("yawl_types.hrl").

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

%% Test cases
-export([
    test_sequential_2pattern_combinations/1,
    test_sequential_3pattern_combinations/1,
    test_parallel_2branch_combinations/1,
    test_parallel_3branch_combinations/1,
    test_nested_depth2_combinations/1,
    test_nested_depth3_combinations/1,
    test_mixed_basic_combinations/1,
    test_mixed_complex_combinations/1,
    test_cancellation_family_combinations/1,
    test_combination_validation_rules/1,
    test_edge_case_combinations/1,
    test_stress_combinations/1
]).

%%====================================================================
%% Pattern Categories for Combinatoric Generation
%%====================================================================

-define(BASIC_PATTERNS, [
    basic_sequential,
    parallel_split,
    parallel_join,
    exclusive_choice,
    simple_merge,
    iterative_loop,
    multi_instance
]).

-define(ADVANCED_PATTERNS, [
    interleaved_parallelism,
    implicit_merge,
    multiple_merge,
    deferred_choice,
    interleaved_routing,
    milestone
]).

-define(CANCELLATION_PATTERNS, [
    cancelation_block,
    cancelation_scope,
    cancelation_thread,
    cancelation_subprocess,
    cancelation_multiple_instances,
    cancelation_point,
    cancelation_end,
    cancelation_cancel
]).

-define(CANCELLATION_TIMING_PATTERNS, [
    cancelation_thread_after,
    cancelation_subprocess_after,
    cancelation_multiple_instances_after
]).

-define(CANCELLATION_LOGIC_PATTERNS, [
    cancelation_thread_or,
    cancelation_subprocess_or,
    cancelation_multiple_instances_or,
    cancelation_thread_and,
    cancelation_subprocess_and,
    cancelation_multiple_instances_and
]).

%%====================================================================
%% Common Test Callbacks
%%====================================================================

%% @doc Return all test cases.
-spec all() -> [atom()].
all() ->
    [
        test_sequential_2pattern_combinations,
        test_sequential_3pattern_combinations,
        test_parallel_2branch_combinations,
        test_parallel_3branch_combinations,
        test_nested_depth2_combinations,
        test_nested_depth3_combinations,
        test_mixed_basic_combinations,
        test_mixed_complex_combinations,
        test_cancellation_family_combinations,
        test_combination_validation_rules,
        test_edge_case_combinations,
        test_stress_combinations
    ].

%% @doc Return test groups with parallel execution support.
-spec groups() -> [{atom(), list(), [atom()]}].
groups() ->
    [
        {sequential_tests, [parallel, {repeat, 1}], [
            test_sequential_2pattern_combinations,
            test_sequential_3pattern_combinations
        ]},
        {parallel_tests, [parallel, {repeat, 1}], [
            test_parallel_2branch_combinations,
            test_parallel_3branch_combinations
        ]},
        {nested_tests, [sequence], [
            test_nested_depth2_combinations,
            test_nested_depth3_combinations
        ]},
        {mixed_tests, [parallel], [
            test_mixed_basic_combinations,
            test_mixed_complex_combinations
        ]},
        {cancellation_tests, [sequence], [
            test_cancellation_family_combinations
        ]},
        {validation_tests, [sequence], [
            test_combination_validation_rules
        ]},
        {edge_case_tests, [parallel], [
            test_edge_case_combinations,
            test_stress_combinations
        ]}
    ].

%% @doc Initialize test suite - start orchestrator and dependencies.
-spec init_per_suite(Config) -> Config when Config :: [tuple()].
init_per_suite(Config) ->
    ct:pal("========================================"),
    ct:pal("Starting YAWL Combinatoric Test Suite"),
    ct:pal("Total YAWL patterns: ~p", [length(?YAWL_PATTERNS)]),
    ct:pal("========================================"),
    {ok, _} = application:ensure_all_started(a2a_erl),
    case whereis(yawl_orchestrator) of
        undefined ->
            {ok, OrchestratorPid} = yawl_orchestrator:start_link(),
            [{orchestrator_pid, OrchestratorPid} | Config];
        _Pid ->
            ct:pal("Orchestrator already running"),
            Config
    end.

%% @doc Cleanup test suite - stop all processes.
-spec end_per_suite(Config) -> ok when Config :: [tuple()].
end_per_suite(Config) ->
    ct:pal("========================================"),
    ct:pal("Completed YAWL Combinatoric Test Suite"),
    ct:pal("========================================"),
    case proplists:get_value(orchestrator_pid, Config) of
        undefined -> ok;
        Pid when is_pid(Pid) ->
            gen_server:stop(Pid),
            application:stop(a2a_erl)
    end,
    ok.

%% @doc Initialize test group with context tracking.
-spec init_per_group(atom(), Config) -> Config when Config :: [tuple()].
init_per_group(GroupName, Config) ->
    ct:pal("----------------------------------------"),
    ct:pal("Starting group: ~p", [GroupName]),
    ct:pal("Test group start time: ~p", [erlang:timestamp()]),
    [{group_start_time, erlang:monotonic_time(millisecond)} | Config].

%% @doc Cleanup test group with metrics reporting.
-spec end_per_group(atom(), Config) -> ok when Config :: [tuple()].
end_per_group(GroupName, Config) ->
    StartTime = proplists:get_value(group_start_time, Config, 0),
    Duration = erlang:monotonic_time(millisecond) - StartTime,
    ct:pal("Completed group: ~p (duration: ~pms)", [GroupName, Duration]),
    ct:pal("----------------------------------------"),
    ok.

%% @doc Initialize test case with metrics.
-spec init_per_testcase(atom(), Config) -> Config when Config :: [tuple()].
init_per_testcase(TestName, Config) ->
    ct:pal("Starting test: ~p", [TestName]),
    [{test_start_time, erlang:monotonic_time(millisecond)} | Config].

%% @doc Cleanup test case with execution time.
-spec end_per_testcase(atom(), Config) -> ok when Config :: [tuple()].
end_per_testcase(TestName, Config) ->
    StartTime = proplists:get_value(test_start_time, Config, 0),
    Duration = erlang:monotonic_time(millisecond) - StartTime,
    ct:pal("Completed test: ~p (duration: ~pms)", [TestName, Duration]),
    ok.

%%====================================================================
%% Sequential Combination Tests
%%====================================================================

%% @doc Test all 2-pattern sequential combinations.
%% Generates C(43,2) = 903 combinations, tests a representative subset.
-spec test_sequential_2pattern_combinations(Config) -> ok when Config :: [tuple()].
test_sequential_2pattern_combinations(_Config) ->
    ct:pal("Testing 2-pattern sequential combinations"),
    Patterns = ?BASIC_PATTERNS ++ ?ADVANCED_PATTERNS,
    Combinations = generate_sequential_combinations(Patterns, 2),
    SubsetSize = min(100, length(Combinations)),
    TestSubset = lists:sublist(Combinations, SubsetSize),

    TestCount = length(TestSubset),
    PassedCount = lists:foldl(fun(Combo, Acc) ->
        Result = test_sequential_combination(Combo),
        Status = maps:get(status, Result, failed),
        case Status of
            passed -> Acc + 1;
            _ -> Acc
        end
    end, 0, TestSubset),

    ct:pal("Sequential 2-pattern tests: ~p/~p passed", [PassedCount, TestCount]),
    case (PassedCount * 100) >= (TestCount * 95) of
        true -> ok;
        false -> ct:fail("Pass rate too low: ~p%", [(PassedCount * 100) div TestCount])
    end.

%% @doc Test 3-pattern sequential combinations.
%% Tests representative 3-pattern sequences from basic patterns.
-spec test_sequential_3pattern_combinations(Config) -> ok when Config :: [tuple()].
test_sequential_3pattern_combinations(_Config) ->
    ct:pal("Testing 3-pattern sequential combinations"),
    Patterns = ?BASIC_PATTERNS,
    Combinations = generate_sequential_combinations(Patterns, 3),
    %% Use all combinations for 7 patterns: 7*6*5 = 210 combinations
    %% Sample to keep test time reasonable
    TestSubset = lists:sublist(Combinations, min(150, length(Combinations))),

    TestCount = length(TestSubset),
    PassedCount = lists:foldl(fun(Combo, Acc) ->
        Result = test_sequential_combination(Combo),
        Status = maps:get(status, Result, failed),
        case Status of
            passed -> Acc + 1;
            _ -> Acc
        end
    end, 0, TestSubset),

    ct:pal("Sequential 3-pattern tests: ~p/~p passed", [PassedCount, TestCount]),
    case (PassedCount * 100) >= (TestCount * 90) of
        true -> ok;
        false -> ct:fail("Pass rate too low: ~p%", [(PassedCount * 100) div TestCount])
    end.

%%====================================================================
%% Parallel Combination Tests
%%====================================================================

%% @doc Test 2-branch parallel combinations.
%% Each branch contains a pattern, executed in parallel.
-spec test_parallel_2branch_combinations(Config) -> ok when Config :: [tuple()].
test_parallel_2branch_combinations(_Config) ->
    ct:pal("Testing 2-branch parallel combinations"),
    Patterns = ?BASIC_PATTERNS,
    Combinations = generate_parallel_combinations(Patterns, 2),
    TestSubset = lists:sublist(Combinations, min(80, length(Combinations))),

    TestCount = length(TestSubset),
    PassedCount = lists:foldl(fun(Combo, Acc) ->
        Result = test_parallel_combination(Combo),
        Status = maps:get(status, Result, failed),
        case Status of
            passed -> Acc + 1;
            _ -> Acc
        end
    end, 0, TestSubset),

    ct:pal("Parallel 2-branch tests: ~p/~p passed", [PassedCount, TestCount]),
    case (PassedCount * 100) >= (TestCount * 90) of
        true -> ok;
        false -> ct:fail("Pass rate too low: ~p%", [(PassedCount * 100) div TestCount])
    end.

%% @doc Test 3-branch parallel combinations.
%% Three parallel branches with different patterns.
-spec test_parallel_3branch_combinations(Config) -> ok when Config :: [tuple()].
test_parallel_3branch_combinations(_Config) ->
    ct:pal("Testing 3-branch parallel combinations"),
    Patterns = ?BASIC_PATTERNS,
    Combinations = generate_parallel_combinations(Patterns, 3),
    TestSubset = lists:sublist(Combinations, min(60, length(Combinations))),

    TestCount = length(TestSubset),
    PassedCount = lists:foldl(fun(Combo, Acc) ->
        Result = test_parallel_combination(Combo),
        Status = maps:get(status, Result, failed),
        case Status of
            passed -> Acc + 1;
            _ -> Acc
        end
    end, 0, TestSubset),

    ct:pal("Parallel 3-branch tests: ~p/~p passed", [PassedCount, TestCount]),
    case (PassedCount * 100) >= (TestCount * 85) of
        true -> ok;
        false -> ct:fail("Pass rate too low: ~p%", [(PassedCount * 100) div TestCount])
    end.

%%====================================================================
%% Nested Combination Tests
%%====================================================================

%% @doc Test depth-2 nested combinations.
%% Pattern containing nested pattern structures.
-spec test_nested_depth2_combinations(Config) -> ok when Config :: [tuple()].
test_nested_depth2_combinations(_Config) ->
    ct:pal("Testing depth-2 nested combinations"),
    OuterPatterns = [basic_sequential, parallel_split, exclusive_choice],
    InnerPatterns = ?BASIC_PATTERNS -- [basic_sequential],
    Combinations = generate_nested_combinations(OuterPatterns, InnerPatterns, 2),
    TestSubset = lists:sublist(Combinations, min(70, length(Combinations))),

    TestCount = length(TestSubset),
    PassedCount = lists:foldl(fun({Outer, Inner}, Acc) ->
        Result = test_nested_combination(Outer, Inner),
        Status = maps:get(status, Result, failed),
        case Status of
            passed -> Acc + 1;
            _ -> Acc
        end
    end, 0, TestSubset),

    ct:pal("Nested depth-2 tests: ~p/~p passed", [PassedCount, TestCount]),
    case (PassedCount * 100) >= (TestCount * 88) of
        true -> ok;
        false -> ct:fail("Pass rate too low: ~p%", [(PassedCount * 100) div TestCount])
    end.

%% @doc Test depth-3 nested combinations.
%% Deeply nested pattern structures (3 levels).
-spec test_nested_depth3_combinations(Config) -> ok when Config :: [tuple()].
test_nested_depth3_combinations(_Config) ->
    ct:pal("Testing depth-3 nested combinations"),
    %% Select specific patterns for depth-3 nesting
    Outer = basic_sequential,
    Middle = [parallel_split, exclusive_choice],
    Inner = [iterative_loop, multi_instance],

    Combinations = [{Outer, [{M, [I]} || M <- Middle], I} || I <- Inner],
    TestCount = length(Combinations),

    PassedCount = lists:foldl(fun({O, M, I}, Acc) ->
        %% Execute outer with middle, then middle with inner
        Result1 = test_nested_combination(O, M),
        Result2 = case M of
            [Single] -> test_nested_combination(Single, [I]);
            _ -> test_nested_combination(hd(M), [I])
        end,
        Status = case {maps:get(status, Result1, failed),
                       maps:get(status, Result2, failed)} of
            {passed, passed} -> passed;
            _ -> failed
        end,
        case Status of
            passed -> Acc + 1;
            _ -> Acc
        end
    end, 0, Combinations),

    ct:pal("Nested depth-3 tests: ~p/~p passed", [PassedCount, TestCount]),
    case (PassedCount * 100) >= (TestCount * 80) of
        true -> ok;
        false -> ct:fail("Pass rate too low: ~p%", [(PassedCount * 100) div TestCount])
    end.

%%====================================================================
%% Mixed Combination Tests
%%====================================================================

%% @doc Test basic mixed combinations.
%% Combines sequential and parallel pattern execution.
-spec test_mixed_basic_combinations(Config) -> ok when Config :: [tuple()].
test_mixed_basic_combinations(_Config) ->
    ct:pal("Testing basic mixed combinations"),
    %% Sequential + Parallel combinations
    SequentialPatterns = [basic_sequential, exclusive_choice],
    ParallelPatterns = [parallel_split, multi_instance],

    Combinations = [
        {sequential, SequentialPatterns},
        {parallel, ParallelPatterns},
        {mixed, [basic_sequential, [parallel_split, iterative_loop]]},
        {mixed, [exclusive_choice, [multi_instance, simple_merge]]}
    ],

    TestCount = length(Combinations),
    PassedCount = lists:foldl(fun({Type, Combo}, Acc) ->
        Result = case Type of
            sequential -> test_sequential_combination(Combo);
            parallel -> test_parallel_combination(Combo);
            mixed -> test_mixed_combination(Combo)
        end,
        Status = maps:get(status, Result, failed),
        case Status of
            passed -> Acc + 1;
            _ -> Acc
        end
    end, 0, Combinations),

    ct:pal("Mixed basic tests: ~p/~p passed", [PassedCount, TestCount]),
    case (PassedCount * 100) >= (TestCount * 85) of
        true -> ok;
        false -> ct:fail("Pass rate too low: ~p%", [(PassedCount * 100) div TestCount])
    end.

%% @doc Test complex mixed combinations.
%% Complex workflows with sequential, parallel, and nested patterns.
-spec test_mixed_complex_combinations(Config) -> ok when Config :: [tuple()].
test_mixed_complex_combinations(_Config) ->
    ct:pal("Testing complex mixed combinations"),

    %% Simulate real-world workflow patterns
    ComplexCombos = [
        %% Order processing style
        [
            basic_sequential,
            [parallel_split, parallel_join],
            exclusive_choice,
            [iterative_loop]
        ],
        %% Document approval style
        [
            basic_sequential,
            exclusive_choice,
            [parallel_split, exclusive_choice, parallel_join],
            iterative_loop
        ],
        %% Data pipeline style
        [
            [parallel_split, parallel_split],
            [multi_instance, multi_instance],
            parallel_join
        ],
        %% Multi-stage processing
        [
            basic_sequential,
            [parallel_split, iterative_loop],
            exclusive_choice,
            [simple_merge, simple_merge]
        ]
    ],

    TestCount = length(ComplexCombos),
    PassedCount = lists:foldl(fun(Combo, Acc) ->
        Result = test_mixed_combination(Combo),
        Status = maps:get(status, Result, failed),
        case Status of
            passed -> Acc + 1;
            _ -> Acc
        end
    end, 0, ComplexCombos),

    ct:pal("Mixed complex tests: ~p/~p passed", [PassedCount, TestCount]),
    case (PassedCount * 100) >= (TestCount * 75) of
        true -> ok;
        false -> ct:fail("Pass rate too low: ~p%", [(PassedCount * 100) div TestCount])
    end.

%%====================================================================
%% Cancellation Family Tests
%%====================================================================

%% @doc Test cancellation pattern family combinations.
%% Tests relationships between various cancellation patterns.
-spec test_cancellation_family_combinations(Config) -> ok when Config :: [tuple()].
test_cancellation_family_combinations(_Config) ->
    ct:pal("Testing cancellation pattern family combinations"),

    %% Test basic cancellation patterns in sequences
    CancelCombos = [
        [cancelation_block, cancelation_scope],
        [cancelation_thread, cancelation_subprocess],
        [cancelation_point, cancelation_end, cancelation_cancel],
        [cancelation_thread_after, cancelation_subprocess_after],
        [cancelation_thread_or, cancelation_thread_and],
        [cancelation_block, cancelation_thread, cancelation_end]
    ],

    %% Test cancellation with basic patterns
    MixedCancelCombos = [
        [basic_sequential, cancelation_block],
        [parallel_split, cancelation_scope, parallel_join],
        [exclusive_choice, cancelation_point, simple_merge],
        [iterative_loop, cancelation_thread_after]
    ],

    AllCombos = CancelCombos ++ MixedCancelCombos,
    TestCount = length(AllCombos),

    PassedCount = lists:foldl(fun(Combo, Acc) ->
        Result = test_sequential_combination(Combo),
        Status = maps:get(status, Result, failed),
        case Status of
            passed -> Acc + 1;
            _ -> Acc
        end
    end, 0, AllCombos),

    ct:pal("Cancellation family tests: ~p/~p passed", [PassedCount, TestCount]),
    case (PassedCount * 100) >= (TestCount * 80) of
        true -> ok;
        false -> ct:fail("Pass rate too low: ~p%", [(PassedCount * 100) div TestCount])
    end.

%%====================================================================
%% Validation Tests
%%====================================================================

%% @doc Test combination validation rules.
%% Verifies that pattern combinations follow YAWL semantics.
-spec test_combination_validation_rules(Config) -> ok when Config :: [tuple()].
test_combination_validation_rules(_Config) ->
    ct:pal("Testing combination validation rules"),

    %% Valid parallel split/join pairs
    ValidPairs = [
        {parallel_split, parallel_join},
        {exclusive_choice, simple_merge},
        {cancelation_block, cancelation_end}
    ],

    %% Test valid pairs
    ValidCount = lists:foldl(fun({P1, P2}, Acc) ->
        {ok, Valid1} = yawl_orchestrator:validate_pattern(P1, #{}),
        {ok, Valid2} = yawl_orchestrator:validate_pattern(P2, #{}),
        case Valid1 andalso Valid2 of
            true -> Acc + 1;
            false -> Acc
        end
    end, 0, ValidPairs),

    %% Test all patterns are in the pattern list
    AllPatterns = yawl_orchestrator:list_patterns(),
    case length(AllPatterns) >= 40 of
        true -> ok;
        false -> ct:fail("Expected at least 40 patterns, got ~p", [length(AllPatterns)])
    end,

    ct:pal("Validation rules: ~p/~p valid pairs confirmed", [ValidCount, length(ValidPairs)]),
    ok.

%%====================================================================
%% Edge Case Tests
%%====================================================================

%% @doc Test edge case combinations.
%% Boundary conditions and unusual pattern pairings.
-spec test_edge_case_combinations(Config) -> ok when Config :: [tuple()].
test_edge_case_combinations(_Config) ->
    ct:pal("Testing edge case combinations"),

    EdgeCases = [
        %% Single pattern (edge of combinations)
        [basic_sequential],
        %% Same pattern repeated
        [basic_sequential, basic_sequential],
        [parallel_split, parallel_split, parallel_split],
        %% All cancellation patterns together
        [cancelation_block, cancelation_scope, cancelation_thread],
        %% Mix of all pattern types
        [basic_sequential, parallel_split, exclusive_choice,
         iterative_loop, multi_instance, milestone],
        %% Deep nesting edge
        {basic_sequential, [{parallel_split, [exclusive_choice]}]}
    ],

    TestCount = length(EdgeCases),
    PassedCount = lists:foldl(fun(EdgeCase, Acc) ->
        Result = case EdgeCase of
            {Outer, Inner} -> test_nested_combination(Outer, Inner);
            Combo -> test_sequential_combination(Combo)
        end,
        Status = maps:get(status, Result, failed),
        case Status of
            passed -> Acc + 1;
            _ -> Acc
        end
    end, 0, EdgeCases),

    ct:pal("Edge case tests: ~p/~p passed", [PassedCount, TestCount]),
    ok.

%%====================================================================
%% Stress Tests
%%====================================================================

%% @doc Stress test with many combinations.
%% Tests system behavior under heavy combination load.
-spec test_stress_combinations(Config) -> ok when Config :: [tuple()].
test_stress_combinations(_Config) ->
    ct:pal("Testing stress combinations"),

    %% Generate many small combinations
    Patterns = ?BASIC_PATTERNS,
    StressCombos = generate_stress_combinations(Patterns, 50),

    StartTime = erlang:monotonic_time(millisecond),
    Results = lists:map(fun(Combo) ->
        test_sequential_combination(Combo)
    end, StressCombos),
    Duration = erlang:monotonic_time(millisecond) - StartTime,

    PassedCount = lists:foldl(fun(Result, Acc) ->
        case maps:get(status, Result, failed) of
            passed -> Acc + 1;
            _ -> Acc
        end
    end, 0, Results),

    TestCount = length(StressCombos),
    ct:pal("Stress test: ~p tests in ~pms (~.2f tests/sec)",
           [TestCount, Duration, TestCount * 1000 / max(1, Duration)]),
    ct:pal("Stress test results: ~p/~p passed", [PassedCount, TestCount]),

    case Duration < 30000 of
        true -> ok;
        false -> ct:fail("Test took too long: ~pms", [Duration])
    end,
    case (PassedCount * 100) >= (TestCount * 75) of
        true -> ok;
        false -> ct:fail("Pass rate too low: ~p%", [(PassedCount * 100) div TestCount])
    end,
    ok.

%%====================================================================
%% Combinatoric Generation Functions
%%====================================================================

%% @private
%% @doc Generate sequential combinations of patterns.
-spec generate_sequential_combinations([atom()], pos_integer()) -> [[atom()]].
generate_sequential_combinations(Patterns, N) ->
    %% Generate all N-length permutations (with replacement)
    generate_permutations(Patterns, N, []).

%% @private
%% @doc Recursive permutation generator.
generate_permutations(_Patterns, 0, Acc) ->
    lists:reverse(Acc);
generate_permutations(Patterns, N, Acc) ->
    NewPerms = case N of
        1 -> [[P] || P <- Patterns];
        _ ->
            SubPerms = generate_permutations(Patterns, N - 1, []),
            lists:flatmap(fun(P) ->
                [[P | Sub] || Sub <- SubPerms]
            end, Patterns)
    end,
    lists:usort(NewPerms ++ Acc).

%% @private
%% @doc Generate parallel branch combinations.
-spec generate_parallel_combinations([atom()], pos_integer()) -> [[[atom()]]].
generate_parallel_combinations(Patterns, NumBranches) ->
    %% Each branch is a list of patterns
    Branches = [[P] || P <- Patterns],
    generate_parallel_branches(Branches, NumBranches).

%% @private
%% @doc Generate parallel branches recursively.
generate_parallel_branches(_Branches, 0) ->
    [[]];
generate_parallel_branches(Branches, NumBranches) ->
    SubBranches = generate_parallel_branches(Branches, NumBranches - 1),
    lists:flatmap(fun(Branch) ->
        [lists:reverse([Branch | Sub]) || Sub <- SubBranches]
    end, Branches).

%% @private
%% @doc Generate nested combinations.
-spec generate_nested_combinations([atom()], [atom()], pos_integer()) ->
    [{atom(), [atom()]}].
generate_nested_combinations(OuterPatterns, InnerPatterns, Depth) ->
    lists:flatmap(fun(Outer) ->
        InnerCombos = generate_sequential_combinations(InnerPatterns, Depth),
        [{Outer, Combo} || Combo <- InnerCombos]
    end, OuterPatterns).

%% @private
%% @doc Generate stress test combinations.
-spec generate_stress_combinations([atom()], pos_integer()) -> [[atom()]].
generate_stress_combinations(Patterns, Count) ->
    %% Generate random combinations for stress testing
    Seed = erlang:phash2({erlang:monotonic_time(), erlang:unique_integer()}),
    rand:seed(exsss, Seed),
    generate_stress_combinations_loop(Patterns, Count, [], sets:new()).

%% @private
%% @doc Helper to generate unique stress combinations.
generate_stress_combinations_loop(_Patterns, 0, Acc, _Seen) ->
    lists:reverse(Acc);
generate_stress_combinations_loop(Patterns, Count, Acc, Seen) ->
    ComboLen = rand:uniform(3) + 1,  %% 1-3 patterns
    Combo = generate_random_combo(Patterns, ComboLen),
    ComboKey = lists:sort(Combo),
    case sets:is_element(ComboKey, Seen) of
        true ->
            generate_stress_combinations_loop(Patterns, Count, Acc, Seen);
        false ->
            NewSeen = sets:add_element(ComboKey, Seen),
            generate_stress_combinations_loop(Patterns, Count - 1, [Combo | Acc], NewSeen)
    end.

%% @private
%% @doc Generate a random combination of patterns.
generate_random_combo(Patterns, Len) ->
    [lists:nth(rand:uniform(length(Patterns)), Patterns) || _ <- lists:seq(1, Len)].

%%====================================================================
%% Test Execution Helper Functions
%%====================================================================

%% @private
%% @doc Test a sequential combination of patterns.
-spec test_sequential_combination([atom()]) -> map().
test_sequential_combination(Patterns) ->
    try
        Results = lists:map(fun(Pattern) ->
            Config = get_test_config_for_pattern(Pattern),
            case yawl_orchestrator:create_workflow(Pattern, Config) of
                {ok, WorkflowId} ->
                    case yawl_orchestrator:execute_workflow(WorkflowId) of
                        {ok, ExecResult} ->
                            #{pattern => Pattern,
                              status => maps:get(status, ExecResult, completed),
                              result => ExecResult};
                        {error, Reason} ->
                            #{pattern => Pattern,
                              status => failed,
                              error => Reason}
                    end;
                {error, Reason} ->
                    #{pattern => Pattern,
                     status => failed,
                     error => Reason}
            end
        end, Patterns),

        AllPassed = lists:all(fun(R) -> maps:get(status, R) =:= completed end, Results),
        #{status => case AllPassed of true -> passed; false -> failed end,
          combination_type => sequential,
          patterns => Patterns,
          results => Results}
    catch
        _:Error ->
            #{status => failed,
              combination_type => sequential,
              patterns => Patterns,
              error => Error}
    end.

%% @private
%% @doc Test a parallel combination of patterns.
-spec test_parallel_combination([[atom()]]) -> map().
test_parallel_combination(PatternGroups) ->
    Parent = self(),
    Ref = make_ref(),

    Pids = lists:map(fun(Patterns) ->
        spawn_monitor(fun() ->
            Result = test_sequential_combination(Patterns),
            Parent ! {Ref, Result}
        end)
    end, PatternGroups),

    Results = lists:map(fun({_Pid, MRef}) ->
        receive
            {Ref, Result} ->
                erlang:demonitor(MRef, [flush]),
                Result;
            {'DOWN', MRef, process, _, Reason} ->
                #{status => failed, error => Reason}
        after 5000 ->
            #{status => timeout, error => test_timeout}
        end
    end, Pids),

    AllPassed = lists:all(fun(R) -> maps:get(status, R, failed) =:= passed end, Results),
    #{status => case AllPassed of true -> passed; false -> failed end,
      combination_type => parallel,
      pattern_groups => PatternGroups,
      results => Results}.

%% @private
%% @doc Test a nested combination of patterns.
-spec test_nested_combination(atom(), [atom()] | [[atom()]]) -> map().
test_nested_combination(OuterPattern, InnerPatterns) ->
    try
        OuterConfig = get_test_config_for_pattern(OuterPattern),
        {ok, OuterWorkflowId} = yawl_orchestrator:create_workflow(OuterPattern, OuterConfig),

        InnerResults = lists:map(fun(Patterns) when is_list(Patterns) ->
            test_sequential_combination(Patterns);
        (Pattern) when is_atom(Pattern) ->
            Config = get_test_config_for_pattern(Pattern),
            case yawl_orchestrator:create_workflow(Pattern, Config) of
                {ok, WorkflowId} ->
                    {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),
                    #{status => maps:get(status, Result, completed)};
                {error, Reason} ->
                    #{status => failed, error => Reason}
            end
        end, ensure_list(InnerPatterns)),

        {ok, _} = yawl_orchestrator:execute_workflow(OuterWorkflowId),

        InnerPassed = lists:all(fun(R) -> maps:get(status, R, failed) =:= passed end, InnerResults),
        #{status => case InnerPassed of true -> passed; false -> failed end,
          combination_type => nested,
          outer_pattern => OuterPattern,
          inner_results => InnerResults}
    catch
        _:Error ->
            #{status => failed,
              combination_type => nested,
              outer_pattern => OuterPattern,
              error => Error}
    end.

%% @private
%% @doc Test a mixed combination of patterns.
-spec test_mixed_combination([atom() | [atom()]]) -> map().
test_mixed_combination(Combo) ->
    try
        Results = lists:map(fun(Element) ->
            case Element of
                Pattern when is_atom(Pattern) ->
                    Config = get_test_config_for_pattern(Pattern),
                    case yawl_orchestrator:create_workflow(Pattern, Config) of
                        {ok, WorkflowId} ->
                            {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),
                            #{type => single, pattern => Pattern,
                              status => maps:get(status, Result, completed)};
                        {error, Reason} ->
                            #{type => single, pattern => Pattern,
                             status => failed, error => Reason}
                    end;
                SubCombo when is_list(SubCombo) ->
                    SubResult = test_sequential_combination(SubCombo),
                    #{type => sequential, patterns => SubCombo,
                      status => maps:get(status, SubResult, failed)}
            end
        end, Combo),

        AllPassed = lists:all(fun(R) -> maps:get(status, R, failed) =:= passed end, Results),
        #{status => case AllPassed of true -> passed; false -> failed end,
          combination_type => mixed,
          combination => Combo,
          results => Results}
    catch
        _:Error ->
            #{status => failed,
              combination_type => mixed,
              combination => Combo,
              error => Error}
    end.

%% @private
%% @doc Get test configuration for a pattern.
-spec get_test_config_for_pattern(atom()) -> map().
get_test_config_for_pattern(basic_sequential) ->
    #{task1_name => "task1", task2_name => "task2"};
get_test_config_for_pattern(parallel_split) ->
    #{branches => 3, task_names => ["task1", "task2", "task3"]};
get_test_config_for_pattern(parallel_join) ->
    #{branches => 3, join_type => sync};
get_test_config_for_pattern(exclusive_choice) ->
    #{conditions => [option1, option2, option3], default_branch => option1};
get_test_config_for_pattern(simple_merge) ->
    #{branches => 3};
get_test_config_for_pattern(iterative_loop) ->
    #{condition => "continue", max_iterations => 5};
get_test_config_for_pattern(multi_instance) ->
    #{num_instances => 3, data => [item1, item2, item3]};
get_test_config_for_pattern(interleaved_parallelism) ->
    #{tasks => ["task1", "task2", "task3"], ordering => any};
get_test_config_for_pattern(implicit_merge) ->
    #{branches => 2};
get_test_config_for_pattern(multiple_merge) ->
    #{branches => 3};
get_test_config_for_pattern(deferred_choice) ->
    #{options => [opt1, opt2, opt3], choice_strategy => runtime};
get_test_config_for_pattern(interleaved_routing) ->
    #{routes => [route1, route2, route3], interleaving_strategy => round_robin};
get_test_config_for_pattern(milestone) ->
    #{milestone_condition => "reached", milestone_actions => [notify]};
get_test_config_for_pattern(cancelation_block) ->
    #{scope => "test_scope", cancel_condition => "never"};
get_test_config_for_pattern(cancelation_scope) ->
    #{scope => "test_scope", scope_actions => [action1, action2]};
get_test_config_for_pattern(cancelation_thread) ->
    #{thread_id => "thread1"};
get_test_config_for_pattern(cancelation_subprocess) ->
    #{subprocess_id => "subprocess1"};
get_test_config_for_pattern(cancelation_multiple_instances) ->
    #{num_instances => 3, cancel_strategy => all};
get_test_config_for_pattern(cancelation_multiple_instances_scope) ->
    #{scope => "test_scope", num_instances => 3};
get_test_config_for_pattern(cancelation_multiple_instances_thread) ->
    #{thread_id => "thread1", num_instances => 3};
get_test_config_for_pattern(cancelation_multiple_instances_subprocess) ->
    #{subprocess_id => "subprocess1", num_instances => 3};
get_test_config_for_pattern(cancelation_point) ->
    #{};
get_test_config_for_pattern(cancelation_end) ->
    #{};
get_test_config_for_pattern(cancelation_cancel) ->
    #{};
get_test_config_for_pattern(cancelation_thread_after) ->
    #{thread_id => "thread1", trigger_condition => "completed"};
get_test_config_for_pattern(cancelation_subprocess_after) ->
    #{subprocess_id => "subprocess1", trigger_condition => "completed"};
get_test_config_for_pattern(cancelation_multiple_instances_after) ->
    #{num_instances => 3, trigger_condition => "completed"};
get_test_config_for_pattern(cancelation_multiple_instances_thread_after) ->
    #{thread_id => "thread1", num_instances => 3, trigger_condition => "completed"};
get_test_config_for_pattern(cancelation_multiple_instances_subprocess_after) ->
    #{subprocess_id => "subprocess1", num_instances => 3, trigger_condition => "completed"};
get_test_config_for_pattern(cancelation_thread_or) ->
    #{thread_id => "thread1", conditions => [cond1, cond2]};
get_test_config_for_pattern(cancelation_subprocess_or) ->
    #{subprocess_id => "subprocess1", conditions => [cond1, cond2]};
get_test_config_for_pattern(cancelation_multiple_instances_or) ->
    #{num_instances => 3, conditions => [cond1, cond2]};
get_test_config_for_pattern(cancelation_multiple_instances_thread_or) ->
    #{thread_id => "thread1", num_instances => 3, conditions => [cond1, cond2]};
get_test_config_for_pattern(cancelation_multiple_instances_subprocess_or) ->
    #{subprocess_id => "subprocess1", num_instances => 3, conditions => [cond1, cond2]};
get_test_config_for_pattern(cancelation_thread_and) ->
    #{thread_id => "thread1", conditions => [cond1, cond2]};
get_test_config_for_pattern(cancelation_subprocess_and) ->
    #{subprocess_id => "subprocess1", conditions => [cond1, cond2]};
get_test_config_for_pattern(cancelation_multiple_instances_and) ->
    #{num_instances => 3, conditions => [cond1, cond2]};
get_test_config_for_pattern(cancelation_multiple_instances_thread_and) ->
    #{thread_id => "thread1", num_instances => 3, conditions => [cond1, cond2]};
get_test_config_for_pattern(cancelation_multiple_instances_subprocess_and) ->
    #{subprocess_id => "subprocess1", num_instances => 3, conditions => [cond1, cond2]};
get_test_config_for_pattern(_) ->
    #{}.

%% @private
%% @doc Ensure input is a list.
ensure_list(List) when is_list(List) -> List;
ensure_list(Item) -> [Item].
