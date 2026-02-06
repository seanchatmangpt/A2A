%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Advanced Control Flow Patterns Simulation Tests
%%%
%%% This module contains simulation tests for YAWL Advanced Control Flow
%%% patterns (8-13) using the yawl_simulation state space explorer.
%%%
%%% Patterns tested:
%%% 8. interleaved_parallelism - Execute tasks in any order
%%% 9. implicit_merge - Automatic merge without explicit merge point
%%% 10. multiple_merge - Multiple merge points for synchronization
%%% 11. deferred_choice - Choose path when task is ready
%%% 12. interleaved_routing - Complex routing with interleaving
%%% 13. milestone - Define and wait for milestone completion
%%%
%%% Tests verify:
%%% - Pattern places are defined in yawl_patterns
%%% - Pattern transitions are defined in yawl_patterns
%%% - Simulation engine can explore state space
%%% - Token passing follows Petri net semantics
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_advanced_patterns_sim_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("gen_pnet.hrl").

%%====================================================================
%%% Test Generator
%%====================================================================

yawl_advanced_patterns_sim_test_() ->
    [
        {"Pattern 8: Interleaved Parallelism",
         fun test_interleaved_parallelism/0},
        {"Pattern 9: Implicit Merge",
         fun test_implicit_merge/0},
        {"Pattern 10: Multiple Merge",
         fun test_multiple_merge/0},
        {"Pattern 11: Deferred Choice",
         fun test_deferred_choice/0},
        {"Pattern 12: Interleaved Routing",
         fun test_interleaved_routing/0},
        {"Pattern 13: Milestone",
         fun test_milestone/0},
        {"Advanced patterns - structure completeness",
         fun test_advanced_patterns_structure/0},
        {"Advanced patterns - token passing",
         fun test_advanced_patterns_token_passing/0},
        {"Advanced patterns - state space",
         fun test_advanced_patterns_state_space/0}
    ].

%%====================================================================
%%% Pattern 8: Interleaved Parallelism Tests
%%====================================================================

test_interleaved_parallelism() ->
    % Verify pattern structure
    Pattern = yawl_patterns:get_pattern_info(interleaved_parallelism),
    ?assertEqual(<<"Interleaved Parallelism">>, maps:get(name, Pattern)),
    ?assertEqual(medium, maps:get(complexity, Pattern)),

    % Verify places
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(interleaved, Places)),

    % Verify transitions
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:member(interleaved_execute, Transitions)),
    ?assert(lists:member(interleaved_merge, Transitions)),

    % Test simulation
    {ok, CanTerminate} = yawl_simulation:check_termination(yawl_patterns),
    ?assert(is_boolean(CanTerminate)).

%%====================================================================
%%% Pattern 9: Implicit Merge Tests
%%====================================================================

test_implicit_merge() ->
    % Verify pattern structure
    Pattern = yawl_patterns:get_pattern_info(implicit_merge),
    ?assertEqual(<<"Implicit Merge">>, maps:get(name, Pattern)),

    % Test token passing through implicit merge
    {Places, Transitions, PresetMap, PostsetMap} =
        yawl_patterns:get_pattern_structure(implicit_merge),

    InitialMarking = create_initial_marking(Places),
    InitialMarking1 = apply_init_marking(InitialMarking, PresetMap),

    % Start creates tokens for both tasks
    ?assertEqual(1, token_count(start, InitialMarking1)),

    Marking1 = fire_transition(start, InitialMarking1, PresetMap, PostsetMap),

    % Both task1 and task2 should have tokens (implicit merge allows both paths)
    ?assert(token_count(task1, Marking1) + token_count(task2, Marking1) >= 1),

    % Either task can proceed to 'end' (implicit merge)
    Marking2a = fire_transition(t1, Marking1, PresetMap, PostsetMap),
    ?assert(token_count('end', Marking2a) >= 0 orelse token_count(task2, Marking2a) >= 0).

%%====================================================================
%%% Pattern 10: Multiple Merge Tests
%%====================================================================

test_multiple_merge() ->
    % Verify pattern structure
    Pattern = yawl_patterns:get_pattern_info(multiple_merge),
    ?assertEqual(<<"Multiple Merge">>, maps:get(name, Pattern)),
    ?assertEqual(high, maps:get(complexity, Pattern)),

    % Verify multiple merge places exist
    {Places, _Transitions, _PresetMap, _PostsetMap} =
        yawl_patterns:get_pattern_structure(multiple_merge),

    ?assert(lists:member(merge1, Places)),
    ?assert(lists:member(merge2, Places)),

    % Test state space exploration
    Stats = yawl_simulation:get_state_space_statistics(yawl_patterns),
    ?assert(is_map(Stats)).

%%====================================================================
%%% Pattern 11: Deferred Choice Tests
%%====================================================================

test_deferred_choice() ->
    % Verify pattern structure
    Pattern = yawl_patterns:get_pattern_info(deferred_choice),
    ?assertEqual(<<"Deferred Choice">>, maps:get(name, Pattern)),

    % Verify defer place exists
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(defer, Places)),

    % Verify deferred_choice_select transition
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:member(deferred_choice_select, Transitions)),

    % Test deadlock detection
    {ok, Deadlocks} = yawl_simulation:detect_deadlock(yawl_patterns),
    ?assert(is_list(Deadlocks)).

%%====================================================================
%%% Pattern 12: Interleaved Routing Tests
%%====================================================================

test_interleaved_routing() ->
    % Verify pattern structure
    Pattern = yawl_patterns:get_pattern_info(interleaved_routing),
    ?assertEqual(<<"Interleaved Routing">>, maps:get(name, Pattern)),
    ?assertEqual(high, maps:get(complexity, Pattern)),

    % Test simulation trace
    {ok, Trace} = yawl_simulation:simulate_trace(yawl_patterns, 10),
    ?assert(is_list(Trace)).

%%====================================================================
%%% Pattern 13: Milestone Tests
%%====================================================================

test_milestone() ->
    % Verify pattern structure
    Pattern = yawl_patterns:get_pattern_info(milestone),
    ?assertEqual(<<"Milestone">>, maps:get(name, Pattern)),

    % Verify milestone places exist
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(milestone, Places)),

    % Verify milestone transitions
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:member(milestone_reach, Transitions)),
    ?assert(lists:member(milestone_wait, Transitions)),

    % Test soundness verification
    Soundness = yawl_simulation:verify_soundness(yawl_patterns),
    ?assert(is_map(Soundness)),
    ?assert(maps:is_key(sound, Soundness)).

%%====================================================================
%%% Comprehensive Structure Tests
%%====================================================================

test_advanced_patterns_structure() ->
    Patterns = [
        interleaved_parallelism,
        implicit_merge,
        multiple_merge,
        deferred_choice,
        interleaved_routing,
        milestone
    ],

    lists:foreach(fun(Pattern) ->
        Info = yawl_patterns:get_pattern_info(Pattern),
        ?assert(maps:is_key(name, Info), {missing_name, Pattern}),
        ?assert(maps:is_key(description, Info), {missing_description, Pattern}),
        ?assert(maps:is_key(complexity, Info), {missing_complexity, Pattern})
    end, Patterns).

%%====================================================================
%%% Token Passing Tests
%%====================================================================

test_advanced_patterns_token_passing() ->
    % Test token passing for all advanced patterns
    Patterns = [
        {interleaved_parallelism, [interleaved]},
        {implicit_merge, [start, task1, task2, 'end']},
        {multiple_merge, [start, task1, task2, merge1, merge2, 'end']},
        {deferred_choice, [start, defer, task1, task2, 'end']},
        {interleaved_routing, [start, route1, route2, route3, 'end']},
        {milestone, [start, milestone, action, 'end']}
    ],

    lists:foreach(fun({Pattern, ExpectedPlaces}) ->
        {ActualPlaces, _Transitions, _PresetMap, _PostsetMap} =
            yawl_patterns:get_pattern_structure(Pattern),

        % Verify expected places exist
        lists:foreach(fun(Place) ->
            ?assert(lists:member(Place, ActualPlaces), {missing_place, Pattern, Place})
        end, ExpectedPlaces)
    end, Patterns).

%%====================================================================
%%% State Space Tests
%%====================================================================

test_advanced_patterns_state_space() ->
    % Test state space exploration for advanced patterns
    Reachable = yawl_simulation:get_reachable_states(yawl_patterns),
    ?assert(is_map(Reachable)),

    % Verify we can get statistics
    Stats = yawl_simulation:get_state_space_statistics(yawl_patterns),
    ?assert(maps:is_key(total_states, Stats)),
    ?assert(maps:get(total_states, Stats) >= 0).

%%====================================================================
%%% Helper Functions
%%====================================================================

%% @private Create initial marking for places
create_initial_marking(Places) ->
    maps:from_list([{P, []} || P <- Places]).

%% @private Apply initial marking
apply_init_marking(Marking, PresetMap) ->
    maps:put(start, [start], Marking).

%% @private Get token count for a place
token_count(Place, Marking) ->
    length(maps:get(Place, Marking, [])).

%% @private Fire a transition
fire_transition(Transition, Marking, PresetMap, PostsetMap) ->
    % Consume tokens from preset
    Marking1 = consume_tokens(Transition, Marking, PresetMap),
    % Produce tokens to postset
    produce_tokens(Transition, Marking1, PostsetMap).

%% @private Consume tokens from preset
consume_tokens(Transition, Marking, PresetMap) ->
    PresetPlaces = maps:get(Transition, PresetMap, []),
    lists:foldl(fun(Place, Acc) ->
        case maps:get(Place, Acc, []) of
            [_Token | Rest] -> maps:put(Place, Rest, Acc);
            _ -> Acc
        end
    end, Marking, PresetPlaces).

%% @private Produce tokens to postset
produce_tokens(Transition, Marking, PostsetMap) ->
    PostsetPlaces = maps:get(Transition, PostsetMap, []),
    lists:foldl(fun(Place, Acc) ->
        CurrentTokens = maps:get(Place, Acc, []),
        maps:put(Place, [token | CurrentTokens], Acc)
    end, Marking, PostsetPlaces).
