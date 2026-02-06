%%%-------------------------------------------------------------------
%%% @doc
%%% Comprehensive Simulation Tests for Cancellation After Patterns (23-27)
%%%
%%% This module tests the five "cancellation after" patterns where cancellation
%%% occurs AFTER a target task/thread/subprocess completes. These patterns
%%% use quoted atoms because 'after' is a reserved keyword in Erlang.
%%%
%%% Patterns tested:
%%% 23. 'cancelation_thread_after' - cancel thread after completion
%%% 24. 'cancelation_subprocess_after' - cancel subprocess after completion
%%% 25. 'cancelation_multiple_instances_after' - cancel instances after
%%% 26. 'cancelation_multiple_instances_thread_after' - cancel instances thread after
%%% 27. 'cancelation_multiple_instances_subprocess_after' - cancel instances subprocess after
%%%
%%% Key Test Scenarios:
%%% - Pattern information verification
%%% - Workflow creation for each pattern
%%% - Cancellation scope verification
%%% - Cancellation trigger verification
%%% - Pattern structure verification
%%% - Quoted atom syntax handling
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_cancellation_after_sim_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").

%%====================================================================
%% Test Generator
%%====================================================================

cancellation_after_sim_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
      {"Pattern 23: Cancel Thread After - Info", fun test_cancelation_thread_after_info/0},
      {"Pattern 23: Cancel Thread After - Create", fun test_cancelation_thread_after_create/0},
      {"Pattern 24: Cancel Subprocess After - Info", fun test_cancelation_subprocess_after_info/0},
      {"Pattern 24: Cancel Subprocess After - Create", fun test_cancelation_subprocess_after_create/0},
      {"Pattern 25: Cancel Multiple Instances After - Info", fun test_cancelation_multiple_instances_after_info/0},
      {"Pattern 25: Cancel Multiple Instances After - Create", fun test_cancelation_multiple_instances_after_create/0},
      {"Pattern 26: Cancel Multiple Instances Thread After - Info", fun test_cancelation_multiple_instances_thread_after_info/0},
      {"Pattern 26: Cancel Multiple Instances Thread After - Create", fun test_cancelation_multiple_instances_thread_after_create/0},
      {"Pattern 27: Cancel Multiple Instances Subprocess After - Info", fun test_cancelation_multiple_instances_subprocess_after_info/0},
      {"Pattern 27: Cancel Multiple Instances Subprocess After - Create", fun test_cancelation_multiple_instances_subprocess_after_create/0},

      {"Cancellation Scope Verification: All Patterns", fun test_all_cancellation_scopes/0},
      {"Cancellation Trigger Verification: All Patterns", fun test_all_cancellation_triggers/0},
      {"Pattern Places Verification: All Patterns", fun test_all_pattern_places/0},

      {"Quoted Atom Syntax: Thread After", fun test_thread_after_quoted_atom/0},
      {"Quoted Atom Syntax: Subprocess After", fun test_subprocess_after_quoted_atom/0},
      {"Quoted Atom Syntax: Multiple Instances After", fun test_multiple_instances_after_quoted_atom/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    {ok, Pid} = yawl_orchestrator:start_link(),
    Pid.

cleanup(Pid) ->
    gen_server:stop(Pid),
    ok.

%%====================================================================
%% Pattern 23: 'cancelation_thread_after' Tests
%%====================================================================

test_cancelation_thread_after_info() ->
    %% Verify pattern exists and has correct metadata
    PatternType = 'cancelation_thread_after',
    Info = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Cancellation Thread After">>, maps:get(name, Info)),
    ?assertEqual(thread_after, maps:get(cancellation_scope, Info)),
    ?assertEqual('after', maps:get(cancellation_trigger, Info)),
    ?assertEqual(high, maps:get(complexity, Info)),
    %% Verify places and transitions exist
    ?assert(maps:is_key(places, Info)),
    ?assert(maps:is_key(transitions, Info)).

test_cancelation_thread_after_create() ->
    %% Verify workflow can be created with the pattern
    PatternType = 'cancelation_thread_after',
    Config = #{thread_id => "thread1"},
    ?assertMatch({ok, _}, yawl_patterns:create_workflow(PatternType, Config)).

%%====================================================================
%% Pattern 24: 'cancelation_subprocess_after' Tests
%%====================================================================

test_cancelation_subprocess_after_info() ->
    %% Verify pattern exists and has correct metadata
    PatternType = 'cancelation_subprocess_after',
    Info = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Cancellation Subprocess After">>, maps:get(name, Info)),
    ?assertEqual(subprocess_after, maps:get(cancellation_scope, Info)),
    ?assertEqual('after', maps:get(cancellation_trigger, Info)),
    ?assertEqual(high, maps:get(complexity, Info)),
    ?assert(maps:is_key(places, Info)),
    ?assert(maps:is_key(transitions, Info)).

test_cancelation_subprocess_after_create() ->
    %% Verify workflow can be created with the pattern
    PatternType = 'cancelation_subprocess_after',
    Config = #{subprocess_id => "subprocess1"},
    ?assertMatch({ok, _}, yawl_patterns:create_workflow(PatternType, Config)).

%%====================================================================
%% Pattern 25: 'cancelation_multiple_instances_after' Tests
%%====================================================================

test_cancelation_multiple_instances_after_info() ->
    %% Verify pattern exists and has correct metadata
    PatternType = 'cancelation_multiple_instances_after',
    Info = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Cancellation Multiple Instances After">>, maps:get(name, Info)),
    ?assertEqual(multiple_instances_after, maps:get(cancellation_scope, Info)),
    ?assertEqual('after', maps:get(cancellation_trigger, Info)),
    ?assertEqual(high, maps:get(complexity, Info)),
    ?assert(maps:is_key(places, Info)),
    ?assert(maps:is_key(transitions, Info)).

test_cancelation_multiple_instances_after_create() ->
    %% Verify workflow can be created with the pattern
    PatternType = 'cancelation_multiple_instances_after',
    Config = #{num_instances => 3},
    ?assertMatch({ok, _}, yawl_patterns:create_workflow(PatternType, Config)).

%%====================================================================
%% Pattern 26: 'cancelation_multiple_instances_thread_after' Tests
%%====================================================================

test_cancelation_multiple_instances_thread_after_info() ->
    %% Verify pattern exists and has correct metadata
    PatternType = 'cancelation_multiple_instances_thread_after',
    Info = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Cancellation Multiple Instances Thread After">>, maps:get(name, Info)),
    ?assertEqual(multiple_instances_thread_after, maps:get(cancellation_scope, Info)),
    ?assertEqual('after', maps:get(cancellation_trigger, Info)),
    ?assertEqual(high, maps:get(complexity, Info)),
    ?assert(maps:is_key(places, Info)),
    ?assert(maps:is_key(transitions, Info)).

test_cancelation_multiple_instances_thread_after_create() ->
    %% Verify workflow can be created with the pattern
    PatternType = 'cancelation_multiple_instances_thread_after',
    Config = #{thread_id => "thread1", num_instances => 3},
    ?assertMatch({ok, _}, yawl_patterns:create_workflow(PatternType, Config)).

%%====================================================================
%% Pattern 27: 'cancelation_multiple_instances_subprocess_after' Tests
%%====================================================================

test_cancelation_multiple_instances_subprocess_after_info() ->
    %% Verify pattern exists and has correct metadata
    PatternType = 'cancelation_multiple_instances_subprocess_after',
    Info = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Cancellation Multiple Instances Subprocess After">>, maps:get(name, Info)),
    ?assertEqual(multiple_instances_subprocess_after, maps:get(cancellation_scope, Info)),
    ?assertEqual('after', maps:get(cancellation_trigger, Info)),
    ?assertEqual(high, maps:get(complexity, Info)),
    ?assert(maps:is_key(places, Info)),
    ?assert(maps:is_key(transitions, Info)).

test_cancelation_multiple_instances_subprocess_after_create() ->
    %% Verify workflow can be created with the pattern
    PatternType = 'cancelation_multiple_instances_subprocess_after',
    Config = #{subprocess_id => "subprocess1", num_instances => 3},
    ?assertMatch({ok, _}, yawl_patterns:create_workflow(PatternType, Config)).

%%====================================================================
%% Cancellation Scope Verification Tests
%%====================================================================

%% @doc Verify all cancellation-after patterns have correct cancellation scopes
test_all_cancellation_scopes() ->
    %% Thread after scope
    Info1 = yawl_patterns:get_pattern_info('cancelation_thread_after'),
    ?assertEqual(thread_after, maps:get(cancellation_scope, Info1)),

    %% Subprocess after scope
    Info2 = yawl_patterns:get_pattern_info('cancelation_subprocess_after'),
    ?assertEqual(subprocess_after, maps:get(cancellation_scope, Info2)),

    %% Multiple instances after scope
    Info3 = yawl_patterns:get_pattern_info('cancelation_multiple_instances_after'),
    ?assertEqual(multiple_instances_after, maps:get(cancellation_scope, Info3)),

    %% Multiple instances thread after scope
    Info4 = yawl_patterns:get_pattern_info('cancelation_multiple_instances_thread_after'),
    ?assertEqual(multiple_instances_thread_after, maps:get(cancellation_scope, Info4)),

    %% Multiple instances subprocess after scope
    Info5 = yawl_patterns:get_pattern_info('cancelation_multiple_instances_subprocess_after'),
    ?assertEqual(multiple_instances_subprocess_after, maps:get(cancellation_scope, Info5)).

%% @doc Verify all cancellation-after patterns have correct cancellation triggers
test_all_cancellation_triggers() ->
    %% All "after" patterns should have 'after' as the trigger
    Patterns = [
        'cancelation_thread_after',
        'cancelation_subprocess_after',
        'cancelation_multiple_instances_after',
        'cancelation_multiple_instances_thread_after',
        'cancelation_multiple_instances_subprocess_after'
    ],

    lists:foreach(fun(Pattern) ->
        Info = yawl_patterns:get_pattern_info(Pattern),
        ?assertEqual('after', maps:get(cancellation_trigger, Info))
    end, Patterns).

%% @doc Verify all cancellation-after patterns have expected places
test_all_pattern_places() ->
    %% Thread after places
    Info1 = yawl_patterns:get_pattern_info('cancelation_thread_after'),
    ?assert(lists:member(thread, maps:get(places, Info1))),
    ?assert(lists:member(after_trigger, maps:get(places, Info1))),

    %% Subprocess after places
    Info2 = yawl_patterns:get_pattern_info('cancelation_subprocess_after'),
    ?assert(lists:member(subprocess, maps:get(places, Info2))),
    ?assert(lists:member(after_trigger, maps:get(places, Info2))),

    %% Multiple instances after places
    Info3 = yawl_patterns:get_pattern_info('cancelation_multiple_instances_after'),
    ?assert(lists:member(multiple_instances, maps:get(places, Info3))),
    ?assert(lists:member(after_trigger, maps:get(places, Info3))).

%%====================================================================
%% Quoted Atom Syntax Tests
%%====================================================================

%% @doc Verify quoted atom syntax works for thread after
test_thread_after_quoted_atom() ->
    %% The pattern name must use quoted atom since 'after' is reserved
    PatternType = 'cancelation_thread_after',
    ?assert(is_atom(PatternType)),
    ?assertEqual('cancelation_thread_after', PatternType),

    %% Verify it works with pattern functions
    {ok, _Workflow} = yawl_patterns:create_workflow(PatternType, #{}),
    Info = yawl_patterns:get_pattern_info(PatternType),
    ?assert(maps:is_key(name, Info)),
    ?assert(maps:is_key(cancellation_scope, Info)).

%% @doc Verify quoted atom syntax works for subprocess after
test_subprocess_after_quoted_atom() ->
    %% The pattern name must use quoted atom since 'after' is reserved
    PatternType = 'cancelation_subprocess_after',
    ?assert(is_atom(PatternType)),
    ?assertEqual('cancelation_subprocess_after', PatternType),

    %% Verify it works with pattern functions
    {ok, _Workflow} = yawl_patterns:create_workflow(PatternType, #{}),
    Info = yawl_patterns:get_pattern_info(PatternType),
    ?assert(maps:is_key(name, Info)),
    ?assert(maps:is_key(cancellation_scope, Info)).

%% @doc Verify quoted atom syntax works for multiple instances after
test_multiple_instances_after_quoted_atom() ->
    %% The pattern name must use quoted atom since 'after' is reserved
    PatternType = 'cancelation_multiple_instances_after',
    ?assert(is_atom(PatternType)),
    ?assertEqual('cancelation_multiple_instances_after', PatternType),

    %% Verify it works with pattern functions
    {ok, _Workflow} = yawl_patterns:create_workflow(PatternType, #{}),
    Info = yawl_patterns:get_pattern_info(PatternType),
    ?assert(maps:is_key(name, Info)),
    ?assert(maps:is_key(cancellation_scope, Info)).
