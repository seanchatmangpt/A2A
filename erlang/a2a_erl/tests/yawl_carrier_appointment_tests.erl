%%%-------------------------------------------------------------------
%%% @doc
%%% Carrier Appointment Workflow Tests
%%%
%%% EUnit tests for the carrier appointment workflow example.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_carrier_appointment_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%%% Test Generator
%%====================================================================

yawl_carrier_appointment_test_() ->
    [
        {"Workflow specification is valid",
         fun test_workflow_spec_valid/0},
        {"TL path simulation",
         fun test_tl_path_simulation/0},
        {"LTL path simulation",
         fun test_ltl_path_simulation/0},
        {"No carrier cancellation",
         fun test_no_carrier_cancellation/0},
        {"Parallel carrier selection",
         fun test_parallel_carrier_selection/0},
        {"Carrier timeout handling",
         fun test_carrier_timeout/0},
        {"Retry after failure",
         fun test_retry_after_failure/0},
        {"Pattern structure completeness",
         fun test_pattern_structure_completeness/0}
    ].

%%====================================================================
%%% Test Cases
%%====================================================================

test_workflow_spec_valid() ->
    Spec = carrier_appointment_workflow:get_workflow_spec(),
    ?assert(maps:is_key(workflow_id, Spec)),
    ?assert(maps:is_key(workflow_name, Spec)),
    ?assert(maps:is_key(places, Spec)),
    ?assert(maps:is_key(transitions, Spec)),
    ?assert(maps:is_key(initial_marking, Spec)),
    ?assert(length(maps:get(places, Spec)) > 0),
    ?assert(length(maps:get(transitions, Spec)) > 0).

test_tl_path_simulation() ->
    Result = carrier_appointment_workflow:simulate_tl_path(),
    ?assertMatch({ok, _Marking}, Result),
    {ok, Marking} = Result,
    % Verify simulation ran and produced a marking
    ?assert(is_map(Marking)).

test_ltl_path_simulation() ->
    Result = carrier_appointment_workflow:simulate_ltl_path(),
    ?assertMatch({ok, _Marking}, Result),
    {ok, Marking} = Result,
    ?assert(is_map(Marking)).

test_no_carrier_cancellation() ->
    Result = carrier_appointment_workflow:simulate_no_carrier_available(),
    ?assertMatch({ok, _Marking}, Result),
    {ok, Marking} = Result,
    ?assert(is_map(Marking)).

test_parallel_carrier_selection() ->
    Result = carrier_appointment_workflow:simulate_parallel_carrier_selection(),
    ?assertMatch({ok, _Marking}, Result),
    {ok, Marking} = Result,
    ?assert(is_map(Marking)).

test_carrier_timeout() ->
    Result = carrier_appointment_workflow:simulate_carrier_timeout(),
    ?assertMatch({ok, _}, Result).

test_retry_after_failure() ->
    Result = carrier_appointment_workflow:simulate_retry_after_failure(),
    ?assertMatch({ok, _}, Result).

test_pattern_structure_completeness() ->
    Places = carrier_appointment_workflow:place_lst(),
    Transitions = carrier_appointment_workflow:trsn_lst(),

    % Verify all places and transitions are non-empty
    ?assert(length(Places) > 0),
    ?assert(length(Transitions) > 0),
    ?assert(lists:all(fun(T) -> length(carrier_appointment_workflow:preset(T)) > 0 end, Transitions)),
    ?assert(lists:all(fun(T) -> length(carrier_appointment_workflow:postset(T)) > 0 end, Transitions)).
