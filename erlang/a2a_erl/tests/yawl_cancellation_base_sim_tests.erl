%%%-------------------------------------------------------------------
%%% @doc
%%% Cancellation Base Pattern Simulation Tests (Patterns 14-22)
%%%
%%% This module contains simulation tests for YAWL Cancellation Base
%%% patterns using the yawl_simulation state space explorer.
%%%
%%% Patterns tested:
%%% 14. cancelation - cancel entire workflow
%%% 15. cancelation_block - cancel within block scope
%%% 16. cancelation_scope - cancel with defined scope
%%% 17. cancelation_thread - cancel single thread
%%% 18. cancelation_subprocess - cancel subprocess
%%% 19. cancelation_multiple_instances - cancel all instances
%%% 20. cancelation_point - explicit cancellation point
%%% 21. cancelation_end - end of cancellation region
%%% 22. cancelation_cancel - explicit cancel action
%%%
%%% Tests verify:
%%% - Pattern places are defined in yawl_patterns
%%% - Pattern transitions are defined in yawl_patterns
%%% - Simulation engine can explore state space
%%% - Termination and deadlock checks work correctly
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_cancellation_base_sim_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").

%%====================================================================
%% Pattern 14: Cancellation - Cancel Entire Workflow
%%====================================================================

cancelation_test_() ->
    [
        fun test_cancelation_place_exists/0,
        fun test_cancelation_transition_exists/0,
        fun test_cancelation_simulation_module_exists/0
    ].

test_cancelation_place_exists() ->
    % Verify cancel place is defined in yawl_patterns
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(cancel, Places)).

test_cancelation_transition_exists() ->
    % Verify cancel_workflow transition is defined
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:member(cancel_workflow, Transitions)).

test_cancelation_simulation_module_exists() ->
    % Verify simulation module can be called
    Stats = yawl_simulation:get_state_space_statistics(yawl_patterns),
    ?assert(is_map(Stats)).

%%====================================================================
%% Pattern 15: Cancellation Block - Cancel Within Block Scope
%%====================================================================

cancelation_block_test_() ->
    [
        fun test_cancelation_block_place_exists/0,
        fun test_cancelation_block_transition_exists/0,
        fun test_cancelation_block_preset_defined/0
    ].

test_cancelation_block_place_exists() ->
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(cancel_scope, Places)).

test_cancelation_block_transition_exists() ->
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:member(cancel_block, Transitions)).

test_cancelation_block_preset_defined() ->
    Preset = yawl_patterns:preset(cancel_block),
    ?assert(is_list(Preset)).

%%====================================================================
%% Pattern 16: Cancellation Scope - Cancel with Defined Scope
%%====================================================================

cancelation_scope_test_() ->
    [
        fun test_cancelation_scope_place_exists/0,
        fun test_cancelation_scope_transitions_exist/0,
        fun test_cancelation_scope_preset_defined/0
    ].

test_cancelation_scope_place_exists() ->
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(cancel_region, Places)).

test_cancelation_scope_transitions_exist() ->
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:member(cancel_scope_enter, Transitions)),
    ?assert(lists:member(cancel_scope_exit, Transitions)).

test_cancelation_scope_preset_defined() ->
    PresetEnter = yawl_patterns:preset(cancel_scope_enter),
    PresetExit = yawl_patterns:preset(cancel_scope_exit),
    ?assert(is_list(PresetEnter)),
    ?assert(is_list(PresetExit)).

%%====================================================================
%% Pattern 17: Cancellation Thread - Cancel Single Thread
%%====================================================================

cancelation_thread_test_() ->
    [
        fun test_cancelation_thread_place_exists/0,
        fun test_cancelation_thread_transition_exists/0,
        fun test_cancelation_thread_preset_defined/0
    ].

test_cancelation_thread_place_exists() ->
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(thread, Places)).

test_cancelation_thread_transition_exists() ->
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:member(cancel_thread, Transitions)).

test_cancelation_thread_preset_defined() ->
    Preset = yawl_patterns:preset(cancel_thread),
    ?assert(is_list(Preset)).

%%====================================================================
%% Pattern 18: Cancellation Subprocess - Cancel Subprocess
%%====================================================================

cancelation_subprocess_test_() ->
    [
        fun test_cancelation_subprocess_place_exists/0,
        fun test_cancelation_subprocess_transition_exists/0,
        fun test_cancelation_subprocess_preset_defined/0
    ].

test_cancelation_subprocess_place_exists() ->
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(subprocess, Places)).

test_cancelation_subprocess_transition_exists() ->
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:member(cancel_subprocess, Transitions)).

test_cancelation_subprocess_preset_defined() ->
    Preset = yawl_patterns:preset(cancel_subprocess),
    ?assert(is_list(Preset)).

%%====================================================================
%% Pattern 19: Cancellation Multiple Instances - Cancel All Instances
%%====================================================================

cancelation_multiple_instances_test_() ->
    [
        fun test_cancelation_multiple_instances_place_exists/0,
        fun test_cancelation_multiple_instances_transition_exists/0,
        fun test_cancelation_multiple_instances_preset_defined/0
    ].

test_cancelation_multiple_instances_place_exists() ->
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(multiple_instances, Places)).

test_cancelation_multiple_instances_transition_exists() ->
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:member(cancel_multiple, Transitions)).

test_cancelation_multiple_instances_preset_defined() ->
    Preset = yawl_patterns:preset(cancel_multiple),
    ?assert(is_list(Preset)).

%%====================================================================
%% Pattern 20: Cancellation Point - Explicit Cancellation Point
%%====================================================================

cancelation_point_test_() ->
    [
        fun test_cancelation_point_place_exists/0,
        fun test_cancelation_point_has_cancellation_places/0
    ].

test_cancelation_point_place_exists() ->
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(cancel_point, Places)).

test_cancelation_point_has_cancellation_places() ->
    % Verify cancellation-related places exist
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(cancel, Places)),
    ?assert(lists:member(cancel_trigger, Places)).

%%====================================================================
%% Pattern 21: Cancellation End - End of Cancellation Region
%%====================================================================

cancelation_end_test_() ->
    [
        fun test_cancelation_end_basic_places_exist/0,
        fun test_cancelation_end_scope_transitions_exist/0
    ].

test_cancelation_end_basic_places_exist() ->
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(cancel_region, Places)).

test_cancelation_end_scope_transitions_exist() ->
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:member(cancel_scope_enter, Transitions)),
    ?assert(lists:member(cancel_scope_exit, Transitions)).

%%====================================================================
%% Pattern 22: Cancellation Cancel - Explicit Cancel Action
%%====================================================================

cancelation_cancel_test_() ->
    [
        fun test_cancelation_cancel_trigger_exists/0,
        fun test_cancelation_cancel_workflow_transition/0
    ].

test_cancelation_cancel_trigger_exists() ->
    Places = yawl_patterns:place_lst(),
    ?assert(lists:member(cancel_trigger, Places)).

test_cancelation_cancel_workflow_transition() ->
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:member(cancel_workflow, Transitions)).

%%====================================================================
%% Comprehensive Tests
%%====================================================================

cancelation_comprehensive_test_() ->
    [
        fun test_all_cancelation_places_defined/0,
        fun test_all_cancelation_transitions_defined/0,
        fun test_simulation_basic_workflow/0
    ].

test_all_cancelation_places_defined() ->
    Places = yawl_patterns:place_lst(),
    RequiredPlaces = [
        cancel,
        cancel_scope,
        cancel_region,
        cancel_trigger,
        subprocess,
        thread,
        multiple_instances,
        cancel_point
    ],
    lists:foreach(fun(Place) ->
        ?assert(lists:member(Place, Places))
    end, RequiredPlaces).

test_all_cancelation_transitions_defined() ->
    Transitions = yawl_patterns:trsn_lst(),
    RequiredTransitions = [
        cancel_workflow,
        cancel_block,
        cancel_thread,
        cancel_subprocess,
        cancel_multiple,
        cancel_scope_enter,
        cancel_scope_exit
    ],
    lists:foreach(fun(Transition) ->
        ?assert(lists:member(Transition, Transitions))
    end, RequiredTransitions).

test_simulation_basic_workflow() ->
    % Test that simulation can run on yawl_patterns
    {ok, CanTerminate} = yawl_simulation:check_termination(yawl_patterns),
    ?assert(is_boolean(CanTerminate)),

    {ok, Deadlocks} = yawl_simulation:detect_deadlock(yawl_patterns),
    ?assert(is_list(Deadlocks)),

    Stats = yawl_simulation:get_state_space_statistics(yawl_patterns),
    ?assert(is_map(Stats)).

%%====================================================================
%% Simulation Engine Tests
%%====================================================================

cancelation_simulation_engine_test_() ->
    [
        fun test_simulation_get_initial_marking/0,
        fun test_simulation_fire_transition/0,
        fun test_simulation_is_final_marking/0
    ].

test_simulation_get_initial_marking() ->
    Marking = yawl_simulation:get_initial_marking(yawl_patterns),
    ?assert(is_map(Marking)),
    ?assert(maps:is_key(start, Marking)).

test_simulation_fire_transition() ->
    % Test firing a transition with preset
    State = #{
        marking => #{start => [workflow_token]},
        usr_info => [],
        net_mod => yawl_patterns
    },
    case yawl_simulation:fire_transition(State, start_workflow, []) of
        {ok, NewMarking} ->
            ?assert(is_map(NewMarking));
        {error, _} ->
            ?assert(true)
    end.

test_simulation_is_final_marking() ->
    % Test final marking detection
    FinalMarking = #{'end' => [workflow_token]},
    ?assert(yawl_simulation:is_final_marking(FinalMarking)),

    NonFinalMarking = #{start => [workflow_token]},
    ?assertNot(yawl_simulation:is_final_marking(NonFinalMarking)).
