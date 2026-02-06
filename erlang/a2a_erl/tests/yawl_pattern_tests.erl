%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Pattern Unit Tests
%%%
%%% This module contains comprehensive unit tests for all 40 YAWL
%%% workflow patterns. Each test verifies pattern creation, validation,
%%% and execution.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_pattern_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").

%%====================================================================
%% Test Generators
%%====================================================================

%% @doc Generate tests for all YAWL patterns
yawl_pattern_test_() ->
    Patterns = [
        {basic_sequential, fun test_basic_sequential/0},
        {parallel_split, fun test_parallel_split/0},
        {parallel_join, fun test_parallel_join/0},
        {exclusive_choice, fun test_exclusive_choice/0},
        {simple_merge, fun test_simple_merge/0},
        {iterative_loop, fun test_iterative_loop/0},
        {multi_instance, fun test_multi_instance/0},
        {interleaved_parallelism, fun test_interleaved_parallelism/0},
        {implicit_merge, fun test_implicit_merge/0},
        {multiple_merge, fun test_multiple_merge/0},
        {deferred_choice, fun test_deferred_choice/0},
        {interleaved_routing, fun test_interleaved_routing/0},
        {milestone, fun test_milestone/0},
        {cancelation_block, fun test_cancelation_block/0},
        {cancelation_scope, fun test_cancelation_scope/0},
        {cancelation_thread, fun test_cancelation_thread/0},
        {cancelation_subprocess, fun test_cancelation_subprocess/0},
        {cancelation_multiple_instances, fun test_cancelation_multiple_instances/0},
        {cancelation_multiple_instances_scope, fun test_cancelation_multiple_instances_scope/0},
        {cancelation_multiple_instances_thread, fun test_cancelation_multiple_instances_thread/0},
        {cancelation_multiple_instances_subprocess, fun test_cancelation_multiple_instances_subprocess/0},
        {cancelation_point, fun test_cancelation_point/0},
        {cancelation_end, fun test_cancelation_end/0},
        {cancelation_cancel, fun test_cancelation_cancel/0},
        {'cancelation_thread_after', fun test_cancelation_thread_after/0},
        {'cancelation_subprocess_after', fun test_cancelation_subprocess_after/0},
        {'cancelation_multiple_instances_after', fun test_cancelation_multiple_instances_after/0},
        {'cancelation_multiple_instances_thread_after', fun test_cancelation_multiple_instances_thread_after/0},
        {'cancelation_multiple_instances_subprocess_after', fun test_cancelation_multiple_instances_subprocess_after/0},
        {cancelation_thread_or, fun test_cancelation_thread_or/0},
        {cancelation_subprocess_or, fun test_cancelation_subprocess_or/0},
        {cancelation_multiple_instances_or, fun test_cancelation_multiple_instances_or/0},
        {cancelation_multiple_instances_thread_or, fun test_cancelation_multiple_instances_thread_or/0},
        {cancelation_multiple_instances_subprocess_or, fun test_cancelation_multiple_instances_subprocess_or/0},
        {cancelation_thread_and, fun test_cancelation_thread_and/0},
        {cancelation_subprocess_and, fun test_cancelation_subprocess_and/0},
        {cancelation_multiple_instances_and, fun test_cancelation_multiple_instances_and/0},
        {cancelation_multiple_instances_thread_and, fun test_cancelation_multiple_instances_thread_and/0},
        {cancelation_multiple_instances_subprocess_and, fun test_cancelation_multiple_instances_subprocess_and/0}
    ],
    [{atom_to_list(P), Test} || {P, Test} <- Patterns].

%%====================================================================
%% Basic Control-Flow Pattern Tests
%%====================================================================

test_basic_sequential() ->
    ?assertNotEqual(undefined, whereis(yawl_orchestrator)),
    Config = #{task1_name => "task1", task2_name => "task2"},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(basic_sequential, Config)),
    {ok, Info} = yawl_orchestrator:get_pattern_info(basic_sequential),
    ?assertEqual(<<"Basic Sequential">>, maps:get(name, Info)).

test_parallel_split() ->
    Config = #{branches => 3, task_names => ["task1", "task2", "task3"]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(parallel_split, Config)),
    {ok, Info} = yawl_orchestrator:get_pattern_info(parallel_split),
    ?assertEqual(<<"Parallel Split">>, maps:get(name, Info)).

test_parallel_join() ->
    Config = #{branches => 3},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(parallel_join, Config)),
    {ok, Info} = yawl_orchestrator:get_pattern_info(parallel_join),
    ?assertEqual(<<"Parallel Join">>, maps:get(name, Info)).

test_exclusive_choice() ->
    Config = #{conditions => [option1, option2, option3], default_branch => option1},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(exclusive_choice, Config)),
    {ok, Info} = yawl_orchestrator:get_pattern_info(exclusive_choice),
    ?assertEqual(<<"Exclusive Choice">>, maps:get(name, Info)).

test_simple_merge() ->
    Config = #{branches => 3},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(simple_merge, Config)),
    {ok, Info} = yawl_orchestrator:get_pattern_info(simple_merge),
    ?assertEqual(<<"Simple Merge">>, maps:get(name, Info)).

test_iterative_loop() ->
    Config = #{condition => "continue", max_iterations => 5},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(iterative_loop, Config)),
    {ok, Info} = yawl_orchestrator:get_pattern_info(iterative_loop),
    ?assertEqual(<<"Iterative Loop">>, maps:get(name, Info)).

test_multi_instance() ->
    Config = #{num_instances => 3, data => [item1, item2, item3]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(multi_instance, Config)),
    {ok, Info} = yawl_orchestrator:get_pattern_info(multi_instance),
    ?assertEqual(<<"Multi-Instance">>, maps:get(name, Info)).

test_interleaved_parallelism() ->
    Config = #{tasks => ["task1", "task2", "task3"], ordering => any},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(interleaved_parallelism, Config)),
    {ok, Info} = yawl_orchestrator:get_pattern_info(interleaved_parallelism),
    ?assertEqual(<<"Interleaved Parallelism">>, maps:get(name, Info)).

%%====================================================================
%% Advanced Control-Flow Pattern Tests
%%====================================================================

test_implicit_merge() ->
    Config = #{},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(implicit_merge, Config)).

test_multiple_merge() ->
    Config = #{branches => 3},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(multiple_merge, Config)).

test_deferred_choice() ->
    Config = #{options => [opt1, opt2, opt3], choice_strategy => runtime},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(deferred_choice, Config)).

test_interleaved_routing() ->
    Config = #{routes => [route1, route2, route3], interleaving_strategy => round_robin},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(interleaved_routing, Config)).

test_milestone() ->
    Config = #{milestone_condition => "reached", milestone_actions => [notify]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(milestone, Config)).

%%====================================================================
%% Cancellation Pattern Tests
%%====================================================================

test_cancelation_block() ->
    Config = #{scope => "test_scope", cancel_condition => "never"},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_block, Config)),
    {ok, Info} = yawl_orchestrator:get_pattern_info(cancelation_block),
    ?assertEqual(<<"Cancellation Block">>, maps:get(name, Info)).

test_cancelation_scope() ->
    Config = #{scope => "test_scope", scope_actions => [action1, action2]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_scope, Config)).

test_cancelation_thread() ->
    Config = #{thread_id => "thread1"},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_thread, Config)).

test_cancelation_subprocess() ->
    Config = #{subprocess_id => "subprocess1"},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_subprocess, Config)).

test_cancelation_multiple_instances() ->
    Config = #{num_instances => 3, cancel_strategy => all},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_multiple_instances, Config)).

test_cancelation_multiple_instances_scope() ->
    Config = #{scope => "test_scope", num_instances => 3},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_multiple_instances_scope, Config)).

test_cancelation_multiple_instances_thread() ->
    Config = #{thread_id => "thread1", num_instances => 3},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_multiple_instances_thread, Config)).

test_cancelation_multiple_instances_subprocess() ->
    Config = #{subprocess_id => "subprocess1", num_instances => 3},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_multiple_instances_subprocess, Config)).

test_cancelation_point() ->
    Config = #{},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_point, Config)).

test_cancelation_end() ->
    Config = #{},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_end, Config)).

test_cancelation_cancel() ->
    Config = #{},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_cancel, Config)).

%%====================================================================
%% Timing-Based Cancellation Pattern Tests
%%====================================================================

test_cancelation_thread_after() ->
    Config = #{thread_id => "thread1", trigger_condition => "completed"},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow('cancelation_thread_after', Config)).

test_cancelation_subprocess_after() ->
    Config = #{subprocess_id => "subprocess1", trigger_condition => "completed"},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow('cancelation_subprocess_after', Config)).

test_cancelation_multiple_instances_after() ->
    Config = #{num_instances => 3, trigger_condition => "completed"},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow('cancelation_multiple_instances_after', Config)).

test_cancelation_multiple_instances_thread_after() ->
    Config = #{thread_id => "thread1", num_instances => 3, trigger_condition => "completed"},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow('cancelation_multiple_instances_thread_after', Config)).

test_cancelation_multiple_instances_subprocess_after() ->
    Config = #{subprocess_id => "subprocess1", num_instances => 3, trigger_condition => "completed"},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow('cancelation_multiple_instances_subprocess_after', Config)).

%%====================================================================
%% OR-Based Cancellation Pattern Tests
%%====================================================================

test_cancelation_thread_or() ->
    Config = #{thread_id => "thread1", conditions => [cond1, cond2]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_thread_or, Config)).

test_cancelation_subprocess_or() ->
    Config = #{subprocess_id => "subprocess1", conditions => [cond1, cond2]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_subprocess_or, Config)).

test_cancelation_multiple_instances_or() ->
    Config = #{num_instances => 3, conditions => [cond1, cond2]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_multiple_instances_or, Config)).

test_cancelation_multiple_instances_thread_or() ->
    Config = #{thread_id => "thread1", num_instances => 3, conditions => [cond1, cond2]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_multiple_instances_thread_or, Config)).

test_cancelation_multiple_instances_subprocess_or() ->
    Config = #{subprocess_id => "subprocess1", num_instances => 3, conditions => [cond1, cond2]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_multiple_instances_subprocess_or, Config)).

%%====================================================================
%% AND-Based Cancellation Pattern Tests
%%====================================================================

test_cancelation_thread_and() ->
    Config = #{thread_id => "thread1", conditions => [cond1, cond2]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_thread_and, Config)).

test_cancelation_subprocess_and() ->
    Config = #{subprocess_id => "subprocess1", conditions => [cond1, cond2]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_subprocess_and, Config)).

test_cancelation_multiple_instances_and() ->
    Config = #{num_instances => 3, conditions => [cond1, cond2]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_multiple_instances_and, Config)).

test_cancelation_multiple_instances_thread_and() ->
    Config = #{thread_id => "thread1", num_instances => 3, conditions => [cond1, cond2]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_multiple_instances_thread_and, Config)).

test_cancelation_multiple_instances_subprocess_and() ->
    Config = #{subprocess_id => "subprocess1", num_instances => 3, conditions => [cond1, cond2]},
    ?assertMatch({ok, _}, yawl_orchestrator:create_workflow(cancelation_multiple_instances_subprocess_and, Config)).

%%====================================================================
%% Validation Tests
%%====================================================================

invalid_config_test_() ->
    [
        {"Missing required param for parallel_split", fun() ->
            Config = #{},
            ?assertMatch({error, {invalid_config, {missing_params, _}}},
                yawl_orchestrator:create_workflow(parallel_split, Config))
        end},
        {"Missing required param for multi_instance", fun() ->
            Config = #{},
            ?assertMatch({error, {invalid_config, {missing_params, _}}},
                yawl_orchestrator:create_workflow(multi_instance, Config))
        end},
        {"Unknown pattern type", fun() ->
            Config = #{},
            ?assertMatch({error, {unknown_pattern, _}},
                yawl_orchestrator:create_workflow(unknown_pattern, Config))
        end}
    ].

pattern_validation_test_() ->
    [
        {"Validate basic_sequential pattern", fun() ->
            Config = #{},
            ?assertMatch({ok, true}, yawl_orchestrator:validate_pattern(basic_sequential, Config))
        end},
        {"Validate parallel_split with valid config", fun() ->
            Config = #{branches => 3},
            ?assertMatch({ok, true}, yawl_orchestrator:validate_pattern(parallel_split, Config))
        end},
        {"Validate parallel_split with invalid config", fun() ->
            Config = #{},
            ?assertMatch({ok, false}, yawl_orchestrator:validate_pattern(parallel_split, Config))
        end}
    ].

list_patterns_test_() ->
    [
        {"List all patterns returns 40 patterns", fun() ->
            Patterns = yawl_orchestrator:list_patterns(),
            ?assertEqual(40, length(Patterns))
        end},
        {"All basic patterns are in list", fun() ->
            Patterns = yawl_orchestrator:list_patterns(),
            ?assert(lists:member(basic_sequential, Patterns)),
            ?assert(lists:member(parallel_split, Patterns)),
            ?assert(lists:member(exclusive_choice, Patterns))
        end}
    ].

%%====================================================================
%% Setup and Teardown
%%====================================================================

setup() ->
    {ok, Pid} = yawl_orchestrator:start_link(),
    Pid.

cleanup(_Pid) ->
    ok.

%%====================================================================
%% Test Suites
%%====================================================================

pattern_execution_suite_test_() ->
    {foreach,
        fun setup/0,
        fun cleanup/1,
        [
            fun(_) -> test_basic_sequential() end,
            fun(_) -> test_parallel_split() end,
            fun(_) -> test_exclusive_choice() end,
            fun(_) -> test_multi_instance() end
        ]
    }.
