%%%-------------------------------------------------------------------
%%% @doc
%%% Comprehensive Unit Tests for YAWL Patterns
%%%
%%% This module provides comprehensive test coverage for YAWL workflow patterns,
%%% covering all major functions, edge cases, error paths, gen_pnet behavior
%%% callbacks, pattern validation, generation, and all 43 pattern types.
%%%
%%% Target Coverage: 95%+
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_patterns_comprehensive_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include_lib("gen_pnet/include/gen_pnet.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Generator
%%====================================================================

patterns_comprehensive_test_() ->
    [
     {"Group 1: gen_pnet Callbacks - Places", fun test_group_places/0},
     {"Group 2: gen_pnet Callbacks - Transitions", fun test_group_transitions/0},
     {"Group 3: gen_pnet Callbacks - Init Marking", fun test_group_init_marking/0},
     {"Group 4: gen_pnet Callbacks - Preset", fun test_group_preset/0},
     {"Group 5: gen_pnet Callbacks - Is Enabled", fun test_group_is_enabled/0},
     {"Group 6: gen_pnet Callbacks - Fire", fun test_group_fire/0},
     {"Group 7: gen_pnet Callbacks - Trigger", fun test_group_trigger/0},
     {"Group 8: API - Create Workflow", fun test_group_create_workflow/0},
     {"Group 9: API - Validate Pattern", fun test_group_validate_pattern/0},
     {"Group 10: API - Get Pattern Info", fun test_group_pattern_info/0},
     {"Group 11: API - List Patterns", fun test_group_list_patterns/0},
     {"Group 12: Pattern Generation", fun test_group_generation/0},
     {"Group 13: Pattern Config Validation", fun test_group_config_validation/0},
     {"Group 14: All Pattern Types", fun test_group_all_patterns/0}
    ].

%%====================================================================
%% Group 1: gen_pnet Callbacks - Places
%%====================================================================

test_group_places() ->
    test_place_lst_basic(),
    test_place_lst_atoms(),
    test_place_lst_no_duplicates(),
    test_place_lst_complete(),
    ok.

test_place_lst_basic() ->
    Places = yawl_patterns:place_lst(),
    ?assert(is_list(Places)),
    ?assert(length(Places) > 0).

test_place_lst_atoms() ->
    Places = yawl_patterns:place_lst(),
    ?assert(lists:all(fun is_atom/1, Places)).

test_place_lst_no_duplicates() ->
    Places = yawl_patterns:place_lst(),
    ?assertEqual(length(Places), length(lists:usort(Places))).

test_place_lst_complete() ->
    ExpectedPlaces = [start, 'end', join, split, condition, action,
                     decision, merge, cancel, error, data],
    Places = yawl_patterns:place_lst(),
    lists:foreach(fun(P) ->
        ?assert(lists:member(P, Places))
    end, ExpectedPlaces).

%%====================================================================
%% Group 2: gen_pnet Callbacks - Transitions
%%====================================================================

test_group_transitions() ->
    test_trsn_lst_basic(),
    test_trsn_lst_atoms(),
    test_trsn_lst_no_duplicates(),
    test_trsn_lst_complete(),
    ok.

test_trsn_lst_basic() ->
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(is_list(Transitions)),
    ?assert(length(Transitions) > 0).

test_trsn_lst_atoms() ->
    Transitions = yawl_patterns:trsn_lst(),
    ?assert(lists:all(fun is_atom/1, Transitions)).

test_trsn_lst_no_duplicates() ->
    Transitions = yawl_patterns:trsn_lst(),
    ?assertEqual(length(Transitions), length(lists:usort(Transitions))).

test_trsn_lst_complete() ->
    Expected = [start_workflow, end_workflow, parallel_split,
                parallel_join, exclusive_choice, simple_merge,
                multi_split, multi_join, iterative_loop,
                cancel_workflow, handle_error, process_data,
                evaluate_condition],
    Transitions = yawl_patterns:trsn_lst(),
    lists:foreach(fun(T) ->
        ?assert(lists:member(T, Transitions))
    end, Expected).

%%====================================================================
%% Group 3: gen_pnet Callbacks - Init Marking
%%====================================================================

test_group_init_marking() ->
    test_init_start_has_token(),
    test_init_end_empty(),
    test_init_other_places_empty(),
    test_init_with_usrinfo(),
    ok.

test_init_start_has_token() ->
    Marking = yawl_patterns:init_marking(start, #{}),
    ?assertEqual([workflow_token], Marking).

test_init_end_empty() ->
    Marking = yawl_patterns:init_marking('end', #{}),
    ?assertEqual([], Marking).

test_init_other_places_empty() ->
    OtherPlaces = [join, split, condition, action, decision, merge, cancel, error, data],
    lists:foreach(fun(P) ->
        Marking = yawl_patterns:init_marking(P, #{}),
        ?assertEqual([], Marking)
    end, OtherPlaces).

test_init_with_usrinfo() ->
    Marking = yawl_patterns:init_marking(start, #{custom => info}),
    ?assertEqual([workflow_token], Marking).

%%====================================================================
%% Group 4: gen_pnet Callbacks - Preset
%%====================================================================

test_group_preset() ->
    test_preset_start_workflow(),
    test_preset_end_workflow(),
    test_preset_parallel_split(),
    test_preset_parallel_join(),
    test_preset_exclusive_choice(),
    test_preset_simple_merge(),
    test_preset_multi_split(),
    test_preset_multi_join(),
    test_preset_iterative_loop(),
    test_preset_cancel_workflow(),
    test_preset_handle_error(),
    test_preset_process_data(),
    test_preset_evaluate_condition(),
    ok.

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

test_preset_exclusive_choice() ->
    Preset = yawl_patterns:preset(exclusive_choice),
    ?assertEqual([join], Preset).

test_preset_simple_merge() ->
    Preset = yawl_patterns:preset(simple_merge),
    ?assertEqual([split], Preset).

test_preset_multi_split() ->
    Preset = yawl_patterns:preset(multi_split),
    ?assertEqual([join], Preset).

test_preset_multi_join() ->
    Preset = yawl_patterns:preset(multi_join),
    ?assertEqual([split], Preset).

test_preset_iterative_loop() ->
    Preset = yawl_patterns:preset(iterative_loop),
    ?assertEqual([condition], Preset).

test_preset_cancel_workflow() ->
    Preset = yawl_patterns:preset(cancel_workflow),
    ?assertEqual([cancel], Preset).

test_preset_handle_error() ->
    Preset = yawl_patterns:preset(handle_error),
    ?assertEqual([error], Preset).

test_preset_process_data() ->
    Preset = yawl_patterns:preset(process_data),
    ?assertEqual([data], Preset).

test_preset_evaluate_condition() ->
    Preset = yawl_patterns:preset(evaluate_condition),
    ?assertEqual([condition], Preset).

%%====================================================================
%% Group 5: gen_pnet Callbacks - Is Enabled
%%====================================================================

test_group_is_enabled() ->
    test_enabled_start_with_token(),
    test_enabled_start_without_token(),
    test_enabled_end_with_one(),
    test_enabled_end_without_token(),
    test_enabled_parallel_join_two(),
    test_enabled_parallel_join_one(),
    test_enabled_simple_merge_any(),
    test_enabled_iterative_true(),
    test_enabled_iterative_false(),
    ok.

test_enabled_start_with_token() ->
    Mode = #{start => [workflow_token]},
    ?assert(yawl_patterns:is_enabled(start_workflow, Mode, #{})).

test_enabled_start_without_token() ->
    Mode = #{start => []},
    ?assertNot(yawl_patterns:is_enabled(start_workflow, Mode, #{})).

test_enabled_end_with_one() ->
    Mode = #{action => [execute_token]},
    ?assert(yawl_patterns:is_enabled(end_workflow, Mode, #{})).

test_enabled_end_without_token() ->
    Mode = #{action => []},
    ?assertNot(yawl_patterns:is_enabled(end_workflow, Mode, #{})).

test_enabled_parallel_join_two() ->
    Mode = #{split => [t1, t2]},
    ?assert(yawl_patterns:is_enabled(parallel_join, Mode, #{})).

test_enabled_parallel_join_one() ->
    Mode = #{split => [t1]},
    ?assertNot(yawl_patterns:is_enabled(parallel_join, Mode, #{})).

test_enabled_simple_merge_any() ->
    Mode = #{split => [t1]},
    ?assert(yawl_patterns:is_enabled(simple_merge, Mode, #{})),
    Mode2 = #{split => [t1, t2, t3]},
    ?assert(yawl_patterns:is_enabled(simple_merge, Mode2, #{})).

test_enabled_iterative_true() ->
    Mode = #{condition => [true]},
    ?assert(yawl_patterns:is_enabled(iterative_loop, Mode, #{})).

test_enabled_iterative_false() ->
    Mode = #{condition => [false]},
    ?assertNot(yawl_patterns:is_enabled(iterative_loop, Mode, #{})).

%%====================================================================
%% Group 6: gen_pnet Callbacks - Fire
%%====================================================================

test_group_fire() ->
    test_fire_start_workflow(),
    test_fire_end_workflow(),
    test_fire_parallel_split(),
    test_fire_parallel_join(),
    test_fire_exclusive_choice(),
    test_fire_simple_merge(),
    test_fire_multi_split(),
    test_fire_multi_join(),
    test_fire_iterative_loop(),
    test_fire_cancel_workflow(),
    test_fire_handle_error(),
    test_fire_process_data(),
    test_fire_evaluate_condition(),
    ok.

test_fire_start_workflow() ->
    {produce, Result} = yawl_patterns:fire(start_workflow, #{}, #{}),
    ?assertEqual([token], maps:get(join, Result)),
    ?assertEqual([execute_token], maps:get(action, Result)).

test_fire_end_workflow() ->
    {produce, Result} = yawl_patterns:fire(end_workflow, #{}, #{}),
    ?assertEqual([completion_token], maps:get('end', Result)).

test_fire_parallel_split() ->
    {produce, Result} = yawl_patterns:fire(parallel_split, #{}, #{}),
    ?assertEqual([token, token], maps:get(split, Result)).

test_fire_parallel_join() ->
    {produce, Result} = yawl_patterns:fire(parallel_join, #{}, #{}),
    ?assertEqual([joined_token], maps:get(merge, Result)).

test_fire_exclusive_choice() ->
    {produce, Result} = yawl_patterns:fire(exclusive_choice, #{}, #{}),
    ?assertEqual([selected_token], maps:get(split, Result)).

test_fire_simple_merge() ->
    {produce, Result} = yawl_patterns:fire(simple_merge, #{}, #{}),
    ?assertEqual([merged_token], maps:get(merge, Result)).

test_fire_multi_split() ->
    {produce, Result} = yawl_patterns:fire(multi_split, #{}, #{}),
    ?assertEqual([token, token, token], maps:get(split, Result)).

test_fire_multi_join() ->
    {produce, Result} = yawl_patterns:fire(multi_join, #{}, #{}),
    ?assertEqual([sync_token], maps:get(merge, Result)).

test_fire_iterative_loop() ->
    {produce, Result} = yawl_patterns:fire(iterative_loop, #{}, #{}),
    ?assertEqual([false], maps:get(condition, Result)),
    ?assertEqual([loop_token], maps:get(action, Result)).

test_fire_cancel_workflow() ->
    {produce, Result} = yawl_patterns:fire(cancel_workflow, #{}, #{}),
    ?assertEqual([cancel_token], maps:get(cancel, Result)),
    ?assertEqual([cancelled_token], maps:get('end', Result)).

test_fire_handle_error() ->
    {produce, Result} = yawl_patterns:fire(handle_error, #{}, #{}),
    ?assertEqual([resolved_token], maps:get(error, Result)),
    ?assertEqual([recovery_token], maps:get(action, Result)).

test_fire_process_data() ->
    {produce, Result} = yawl_patterns:fire(process_data, #{}, #{}),
    ?assertEqual([processed_token], maps:get(action, Result)).

test_fire_evaluate_condition() ->
    {produce, Result} = yawl_patterns:fire(evaluate_condition, #{}, #{}),
    ?assertEqual([true], maps:get(decision, Result)).

%%====================================================================
%% Group 7: gen_pnet Callbacks - Trigger
%%====================================================================

test_group_trigger() ->
    test_trigger_start_pass(),
    test_trigger_start_other_token(),
    test_trigger_cancel_drop(),
    test_trigger_cancel_other(),
    test_trigger_error_drop(),
    test_trigger_error_other(),
    test_trigger_other_pass(),
    ok.

test_trigger_start_pass() ->
    ?assertEqual(pass, yawl_patterns:trigger(start, workflow_token, #{})).

test_trigger_start_other_token() ->
    ?assertEqual(pass, yawl_patterns:trigger(start, other_token, #{})).

test_trigger_cancel_drop() ->
    ?assertEqual(drop, yawl_patterns:trigger(cancel, cancel_token, #{})).

test_trigger_cancel_other() ->
    ?assertEqual(pass, yawl_patterns:trigger(cancel, other_token, #{})).

test_trigger_error_drop() ->
    ?assertEqual(drop, yawl_patterns:trigger(error, resolved_token, #{})).

test_trigger_error_other() ->
    ?assertEqual(pass, yawl_patterns:trigger(error, other_token, #{})).

test_trigger_other_pass() ->
    OtherPlaces = [join, split, condition, action, 'end', decision, merge, data],
    lists:foreach(fun(Place) ->
        ?assertEqual(pass, yawl_patterns:trigger(Place, any_token, #{}))
    end, OtherPlaces).

%%====================================================================
%% Group 8: API - Create Workflow
%%====================================================================

test_group_create_workflow() ->
    test_create_valid_basic(),
    test_create_valid_parallel(),
    test_create_valid_multi_instance(),
    test_create_invalid_config(),
    test_create_unknown_pattern(),
    test_create_with_options(),
    ok.

test_create_valid_basic() ->
    Config = #{pattern_config => #{}},
    Result = yawl_patterns:create_workflow(basic_sequential, Config),
    ?assertMatch({ok, _}, Result).

test_create_valid_parallel() ->
    Config = #{pattern_config => #{branches => 3}},
    Result = yawl_patterns:create_workflow(parallel_split, Config),
    ?assertMatch({ok, _}, Result).

test_create_valid_multi_instance() ->
    Config = #{num_instances => 3, data => [1, 2, 3]},
    Result = yawl_patterns:create_workflow(multi_instance, Config),
    ?assertMatch({ok, _}, Result).

test_create_invalid_config() ->
    Config = #{pattern_config => #{branches => 1}},
    Result = yawl_patterns:create_workflow(parallel_split, Config),
    ?assertEqual({error, invalid_pattern_config}, Result).

test_create_unknown_pattern() ->
    Config = #{},
    Result = yawl_patterns:create_workflow(unknown_pattern_xyz, Config),
    ?assertEqual({error, invalid_pattern_config}, Result).

test_create_with_options() ->
    Config = #{pattern_config => #{}, task_names => ["t1", "t2"]},
    Result = yawl_patterns:create_workflow(basic_sequential, Config),
    ?assertMatch({ok, _}, Result).

%%====================================================================
%% Group 9: API - Validate Pattern
%%====================================================================

test_group_validate_pattern() ->
    test_validate_known_pattern(),
    test_validate_unknown_pattern(),
    test_validate_basic_config(),
    test_validate_parallel_config(),
    test_validate_iterative_config(),
    test_validate_multi_config(),
    ok.

test_validate_known_pattern() ->
    Result = yawl_patterns:validate_pattern(basic_sequential, #{}),
    ?assert(Result).

test_validate_unknown_pattern() ->
    Result = yawl_patterns:validate_pattern(unknown_pattern_xyz, #{}),
    ?assertNot(Result).

test_validate_basic_config() ->
    ?assert(yawl_patterns:validate_pattern(basic_sequential, #{})),
    ?assert(yawl_patterns:validate_pattern(basic_sequential, #{any => thing})).

test_validate_parallel_config() ->
    ?assert(yawl_patterns:validate_pattern(parallel_split, #{branches => 2})),
    ?assert(yawl_patterns:validate_pattern(parallel_split, #{branches => 5})),
    ?assertNot(yawl_patterns:validate_pattern(parallel_split, #{branches => 1})).

test_validate_iterative_config() ->
    ConditionFun = fun(_) -> true end,
    ?assert(yawl_patterns:validate_pattern(iterative_loop, #{condition => ConditionFun})),
    ?assertNot(yawl_patterns:validate_pattern(iterative_loop, #{})).

test_validate_multi_config() ->
    ?assert(yawl_patterns:validate_pattern(multi_instance, #{num_instances => 3, data => [1,2,3]})),
    ?assertNot(yawl_patterns:validate_pattern(multi_instance, #{num_instances => 0})),
    ?assertNot(yawl_patterns:validate_pattern(multi_instance, #{num_instances => 3})).

%%====================================================================
%% Group 10: API - Get Pattern Info
%%====================================================================

test_group_pattern_info() ->
    test_info_basic_sequential(),
    test_info_parallel_split(),
    test_info_parallel_join(),
    test_info_exclusive_choice(),
    test_info_simple_merge(),
    test_info_iterative_loop(),
    test_info_multi_instance(),
    test_info_cancelation(),
    test_info_interleaved_parallelism(),
    test_info_unknown(),
    test_info_structure(),
    ok.

test_info_basic_sequential() ->
    Info = yawl_patterns:get_pattern_info(basic_sequential),
    ?assertEqual(<<"Basic Sequential">>, maps:get(name, Info)),
    ?assertEqual(low, maps:get(complexity, Info)),
    ?assertEqual([start, action1, action2, 'end'], maps:get(places, Info)).

test_info_parallel_split() ->
    Info = yawl_patterns:get_pattern_info(parallel_split),
    ?assertEqual(<<"Parallel Split">>, maps:get(name, Info)),
    ?assertEqual(medium, maps:get(complexity, Info)).

test_info_parallel_join() ->
    Info = yawl_patterns:get_pattern_info(parallel_join),
    ?assertEqual(<<"Parallel Join">>, maps:get(name, Info)),
    ?assertEqual(medium, maps:get(complexity, Info)).

test_info_exclusive_choice() ->
    Info = yawl_patterns:get_pattern_info(exclusive_choice),
    ?assertEqual(<<"Exclusive Choice">>, maps:get(name, Info)),
    ?assertEqual(medium, maps:get(complexity, Info)).

test_info_simple_merge() ->
    Info = yawl_patterns:get_pattern_info(simple_merge),
    ?assertEqual(<<"Simple Merge">>, maps:get(name, Info)).

test_info_iterative_loop() ->
    Info = yawl_patterns:get_pattern_info(iterative_loop),
    ?assertEqual(<<"Iterative Loop">>, maps:get(name, Info)),
    ?assertEqual(high, maps:get(complexity, Info)).

test_info_multi_instance() ->
    Info = yawl_patterns:get_pattern_info(multi_instance),
    ?assertEqual(<<"Multi-Instance">>, maps:get(name, Info)),
    ?assertEqual(high, maps:get(complexity, Info)).

test_info_cancelation() ->
    Info = yawl_patterns:get_pattern_info(cancelation),
    ?assertEqual(<<"Cancellation">>, maps:get(name, Info)).

test_info_interleaved_parallelism() ->
    Info = yawl_patterns:get_pattern_info(interleaved_parallelism),
    ?assertEqual(<<"Interleaved Parallelism">>, maps:get(name, Info)).

test_info_unknown() ->
    Info = yawl_patterns:get_pattern_info(unknown_pattern_xyz),
    ?assertEqual(<<"unknown">>, maps:get(name, Info)),
    ?assertEqual([], maps:get(places, Info)).

test_info_structure() ->
    Info = yawl_patterns:get_pattern_info(basic_sequential),
    ?assert(is_map(Info)),
    ?assert(maps:is_key(name, Info)),
    ?assert(maps:is_key(description, Info)),
    ?assert(maps:is_key(places, Info)),
    ?assert(maps:is_key(transitions, Info)),
    ?assert(maps:is_key(complexity, Info)).

%%====================================================================
%% Group 11: API - List Patterns
%%====================================================================

test_group_list_patterns() ->
    test_list_count(),
    test_list_has_all_basic(),
    test_list_has_all_cancellation(),
    test_list_all_patterns(),
    ok.

test_list_count() ->
    Patterns = yawl_patterns:list_patterns(),
    ?assert(length(Patterns) >= 40).

test_list_has_all_basic() ->
    Patterns = yawl_patterns:list_patterns(),
    BasicPatterns = [basic_sequential, parallel_split, parallel_join,
                    exclusive_choice, simple_merge, iterative_loop,
                    multi_instance],
    lists:foreach(fun(P) ->
        ?assert(lists:member(P, Patterns))
    end, BasicPatterns).

test_list_has_all_cancellation() ->
    Patterns = yawl_patterns:list_patterns(),
    CancelPatterns = [cancelation, cancelation_block, cancelation_scope,
                      cancelation_thread, cancelation_subprocess,
                      cancelation_multiple_instances],
    lists:foreach(fun(P) ->
        ?assert(lists:member(P, Patterns))
    end, CancelPatterns).

test_list_all_patterns() ->
    Patterns = yawl_patterns:list_patterns(),
    AllYAWLPatterns = ?YAWL_PATTERNS,
    ?assertEqual(length(AllYAWLPatterns), length(Patterns)).

%%====================================================================
%% Group 12: Pattern Generation
%%====================================================================

test_group_generation() ->
    test_generate_basic(),
    test_generate_parallel_split(),
    test_generate_parallel_join(),
    test_generate_exclusive_choice(),
    test_generate_simple_merge(),
    test_generate_iterative(),
    test_generate_multi_instance(),
    test_generate_unknown_fallback(),
    test_generate_structure(),
    ok.

test_generate_basic() ->
    Def = yawl_patterns:generate_pattern_definition(basic_sequential, #{}),
    ?assertEqual(basic_sequential, maps:get(pattern_type, Def)),
    ?assertEqual(low, maps:get(complexity, Def)),
    ?assertEqual([start, action1, action2, 'end'], maps:get(places, Def)).

test_generate_parallel_split() ->
    Def = yawl_patterns:generate_pattern_definition(parallel_split, #{}),
    ?assertEqual(parallel_split, maps:get(pattern_type, Def)),
    ?assert(lists:member(split, maps:get(places, Def))).

test_generate_parallel_join() ->
    Def = yawl_patterns:generate_pattern_definition(parallel_join, #{}),
    ?assertEqual(parallel_join, maps:get(pattern_type, Def)),
    ?assert(lists:member(join, maps:get(places, Def))).

test_generate_exclusive_choice() ->
    Def = yawl_patterns:generate_pattern_definition(exclusive_choice, #{}),
    ?assertEqual(exclusive_choice, maps:get(pattern_type, Def)),
    ?assert(lists:member(choice, maps:get(places, Def))).

test_generate_simple_merge() ->
    Def = yawl_patterns:generate_pattern_definition(simple_merge, #{}),
    ?assertEqual(simple_merge, maps:get(pattern_type, Def)),
    ?assert(lists:member(merge, maps:get(places, Def))).

test_generate_iterative() ->
    Def = yawl_patterns:generate_pattern_definition(iterative_loop, #{}),
    ?assertEqual(iterative_loop, maps:get(pattern_type, Def)),
    ?assertEqual(high, maps:get(complexity, Def)),
    ?assert(lists:member(loop, maps:get(places, Def))).

test_generate_multi_instance() ->
    Def = yawl_patterns:generate_pattern_definition(multi_instance, #{num_instances => 3}),
    ?assertEqual(multi_instance, maps:get(pattern_type, Def)),
    ?assertEqual(high, maps:get(complexity, Def)),
    ?assertEqual(7, length(maps:get(places, Def))).

test_generate_unknown_fallback() ->
    Def = yawl_patterns:generate_pattern_definition(unknown_pattern, #{}),
    ?assertEqual(basic_sequential, maps:get(pattern_type, Def)).

test_generate_structure() ->
    Def = yawl_patterns:generate_pattern_definition(basic_sequential, #{}),
    ?assert(maps:is_key(places, Def)),
    ?assert(maps:is_key(transitions, Def)),
    ?assert(maps:is_key(marking, Def)),
    ?assert(maps:is_key(preset, Def)),
    ?assert(is_list(maps:get(places, Def))),
    ?assert(is_list(maps:get(transitions, Def))),
    ?assert(is_map(maps:get(marking, Def))),
    ?assert(is_map(maps:get(preset, Def))).

%%====================================================================
%% Group 13: Pattern Config Validation
%%====================================================================

test_group_config_validation() ->
    test_validate_config_basic(),
    test_validate_config_parallel(),
    test_validate_config_parallel_join(),
    test_validate_config_exclusive(),
    test_validate_config_iterative(),
    test_validate_config_multi(),
    test_validate_config_default(),
    ok.

test_validate_config_basic() ->
    ?assert(yawl_patterns:validate_pattern_config(basic_sequential, #{})),
    ?assert(yawl_patterns:validate_pattern_config(basic_sequential, #{any => thing})).

test_validate_config_parallel() ->
    ?assert(yawl_patterns:validate_pattern_config(parallel_split, #{branches => 2})),
    ?assert(yawl_patterns:validate_pattern_config(parallel_split, #{branches => 10})),
    ?assertNot(yawl_patterns:validate_pattern_config(parallel_split, #{branches => 1})),
    ?assertNot(yawl_patterns:validate_pattern_config(parallel_split, #{})).

test_validate_config_parallel_join() ->
    ?assert(yawl_patterns:validate_pattern_config(parallel_join, #{branches => 2})),
    ?assert(yawl_patterns:validate_pattern_config(parallel_join, #{branches => 5})),
    ?assertNot(yawl_patterns:validate_pattern_config(parallel_join, #{branches => 1})).

test_validate_config_exclusive() ->
    ?assert(yawl_patterns:validate_pattern_config(exclusive_choice, #{conditions => [a, b]})),
    ?assertNot(yawl_patterns:validate_pattern_config(exclusive_choice, #{conditions => []})),
    ?assertNot(yawl_patterns:validate_pattern_config(exclusive_choice, #{})).

test_validate_config_iterative() ->
    ConditionFun = fun(_) -> true end,
    ?assert(yawl_patterns:validate_pattern_config(iterative_loop, #{condition => ConditionFun})),
    ?assertNot(yawl_patterns:validate_pattern_config(iterative_loop, #{})).

test_validate_config_multi() ->
    ?assert(yawl_patterns:validate_pattern_config(multi_instance, #{num_instances => 1, data => [1]})),
    ?assert(yawl_patterns:validate_pattern_config(multi_instance, #{num_instances => 10, data => lists:seq(1,10)})),
    ?assertNot(yawl_patterns:validate_pattern_config(multi_instance, #{num_instances => 0})),
    ?assertNot(yawl_patterns:validate_pattern_config(multi_instance, #{data => [1]})).

test_validate_config_default() ->
    ?assert(yawl_patterns:validate_pattern_config(unknown_pattern, #{})),
    ?assert(yawl_patterns:validate_pattern_config(unknown_pattern, #{any => thing})).

%%====================================================================
%% Group 14: All Pattern Types
%%====================================================================

test_group_all_patterns() ->
    AllPatterns = yawl_patterns:list_patterns(),
    lists:foreach(fun(Pattern) ->
        test_pattern_type(Pattern)
    end, AllPatterns),
    ok.

test_pattern_type(Pattern) ->
    %% Each pattern should have valid info
    Info = yawl_patterns:get_pattern_info(Pattern),
    ?assert(is_map(Info)),
    ?assert(is_binary(maps:get(name, Info))),
    ?assert(lists:member(maps:get(complexity, Info), [low, medium, high])),
    ?assert(is_list(maps:get(places, Info))),
    ?assert(is_list(maps:get(transitions, Info))).

%%====================================================================
%% Multi-Instance Pattern Specific Tests
%%====================================================================

multi_instance_preset_test_() ->
    [
     {"Generate preset for 1 instance", fun test_multi_instance_preset_1/0},
     {"Generate preset for 3 instances", fun test_multi_instance_preset_3/0},
     {"Generate preset for 10 instances", fun test_multi_instance_preset_10/0}
    ].

test_multi_instance_preset_1() ->
    Preset = yawl_patterns:generate_multi_instance_preset(1),
    ?assertEqual([start], maps:get(start, Preset)),
    ?assertEqual([create], maps:get(create, Preset)),
    ?assertEqual([instance_1], maps:get(execute_1, Preset)).

test_multi_instance_preset_3() ->
    Preset = yawl_patterns:generate_multi_instance_preset(3),
    ?assertEqual([instance_1, instance_2, instance_3], maps:get(collect, Preset)).

test_multi_instance_preset_10() ->
    Preset = yawl_patterns:generate_multi_instance_preset(10),
    ?assertEqual(10, length(maps:get(collect, Preset))),
    lists:foreach(fun(I) ->
        ExecuteKey = list_to_atom("execute_" ++ integer_to_list(I)),
        ?assertEqual([list_to_atom("instance_" ++ integer_to_list(I))], maps:get(ExecuteKey, Preset))
    end, lists:seq(1, 10)).

%%====================================================================
%% Property-Based Tests (Manual Implementation)
%%====================================================================

property_test_() ->
    [
     {"Pattern list contains all YAWL patterns", fun test_prop_pattern_list_complete/0},
     {"Pattern info always valid structure", fun test_prop_pattern_info_valid/0},
     {"Validation idempotent", fun test_prop_validation_idempotent/0}
    ].

test_prop_pattern_list_complete() ->
    Patterns = yawl_patterns:list_patterns(),
    YAWLPatterns = ?YAWL_PATTERNS,
    lists:foreach(fun(P) ->
        ?assert(lists:member(P, Patterns))
    end, YAWLPatterns),
    lists:foreach(fun(P) ->
        ?assert(lists:member(P, YAWLPatterns) orelse lists:member(P, [basic_sequential]))
    end, Patterns).

test_prop_pattern_info_valid() ->
    Patterns = yawl_patterns:list_patterns(),
    lists:foreach(fun(P) ->
        Info = yawl_patterns:get_pattern_info(P),
        ?assert(is_map(Info)),
        ?assert(is_binary(maps:get(name, Info))),
        ?assert(is_list(maps:get(places, Info))),
        ?assert(is_list(maps:get(transitions, Info)))
    end, Patterns).

test_prop_validation_idempotent() ->
    TestCases = [
        {basic_sequential, #{}},
        {parallel_split, #{branches => 3}},
        {multi_instance, #{num_instances => 5, data => lists:seq(1,5)}}
    ],
    lists:foreach(fun({Pattern, Config}) ->
        Result1 = yawl_patterns:validate_pattern(Pattern, Config),
        Result2 = yawl_patterns:validate_pattern(Pattern, Config),
        ?assertEqual(Result1, Result2)
    end, TestCases).
