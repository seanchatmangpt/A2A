%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL CPN PM4Py Bridge
%%%
%%% Chicago TDD: Tests written first, will fail initially.
%%% Tests for PM4Py Python bridge integration.
%%%
%%% Reference: arXiv:2506.12238 - Berti, van der Aalst (Mar 2025)
%%% "CPN-Py: Colored Petri Nets with Python/PM4Py Integration"
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_cpn_pm4py_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").

-include("yawl_types.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

%% Sample CPN JSON for testing
test_cpn_json() ->
    #{
        <<"version">> => <<"1.0">>,
        <<"format">> => <<"cpn-json">>,
        <<"places">> => [
            #{<<"id">> => <<"p1">>, <<"name">> => <<"Start">>, <<"initialTokens">> => 1, <<"type">> => <<"place">>},
            #{<<"id">> => <<"p2">>, <<"name">> => <<"Process">>, <<"initialTokens">> => 0, <<"type">> => <<"place">>},
            #{<<"id">> => <<"p3">>, <<"name">> => <<"End">>, <<"initialTokens">> => 0, <<"type">> => <<"place">>}
        ],
        <<"transitions">> => [
            #{<<"id">> => <<"t1">>, <<"name">> => <<"StartProcess">>, <<"guard">> => null, <<"type">> => <<"transition">>},
            #{<<"id">> => <<"t2">>, <<"name">> => <<"CompleteProcess">>, <<"guard">> => null, <<"type">> => <<"transition">>}
        ],
        <<"arcs">> => [
            #{<<"source">> => <<"p1">>, <<"target">> => <<"t1">>, <<"type">> => <<"place_to_transition">>},
            #{<<"source">> => <<"t1">>, <<"target">> => <<"p2">>, <<"type">> => <<"transition_to_place">>},
            #{<<"source">> => <<"p2">>, <<"target">> => <<"t2">>, <<"type">> => <<"place_to_transition">>},
            #{<<"source">> => <<"t2">>, <<"target">> => <<"p3">>, <<"type">> => <<"transition_to_place">>}
        ],
        <<"colorSets">> => #{
            <<"any">> => #{<<"type">> => <<"any">>},
            <<"boolean">> => #{<<"type">> => <<"boolean">>},
            <<"integer">> => #{<<"type">> => <<"integer">>},
            <<"string">> => #{<<"type">> => <<"string">>}
        }
    }.

%% Sample XES log map
test_xes_log_map() ->
    #{
        log_id => <<"test_log">>,
        trace_id => <<"trace1">>,
        started_at => erlang:system_time(millisecond),
        events => [
            #{
                event_id => <<"e1">>,
                timestamp => 1000,
                activity => <<"StartProcess">>,
                lifecycle => complete
            },
            #{
                event_id => <<"e2">>,
                timestamp => 2000,
                activity => <<"CompleteProcess">>,
                lifecycle => complete
            }
        ],
        metadata => #{}
    }.

%% State with no Python bridge
test_state_no_bridge() ->
    #{
        color_sets => #{
            boolean => #{name => boolean, type => boolean, constraints => []},
            integer => #{name => integer, type => integer, constraints => []},
            string => #{name => string, type => string, constraints => []},
            any => #{name => any, type => any, constraints => []}
        },
        cache => #{},
        python_bridge => undefined
    }.

test_model() ->
    #{model_id => <<"test_model">>, type => petri_net}.

%%====================================================================
%% do_call_pm4py Tests - CHICAGO TDD: TESTS FIRST
%%====================================================================

%% Test: do_call_pm4py with undefined python_bridge should return placeholder
do_call_pm4py_no_bridge_test() ->
    State = test_state_no_bridge(),
    Result = yawl_cpn:do_call_pm4py_test(discover, [test_xes_log_map()], State),
    ?assertMatch({ok, #{function := discover}}, Result),
    ?assert(maps:is_key(args, element(2, Result))),
    ?assert(maps:is_key(result, element(2, Result))).

%% Test: do_call_pm4py with stochastic_replay function
do_call_pm4py_stochastic_replay_test() ->
    State = test_state_no_bridge(),
    Result = yawl_cpn:do_call_pm4py_test(stochastic_replay,
                                          [test_xes_log_map(), test_model()], State),
    ?assertMatch({ok, #{function := stochastic_replay}}, Result).

%% Test: do_call_pm4py with process_discovery function
do_call_pm4py_process_discovery_test() ->
    State = test_state_no_bridge(),
    Result = yawl_cpn:do_call_pm4py_test(discover, [test_xes_log_map()], State),
    ?assertMatch({ok, #{function := discover}}, Result).

%% Test: do_call_pm4py with align_traces function
do_call_pm4py_align_traces_test() ->
    State = test_state_no_bridge(),
    Result = yawl_cpn:do_call_pm4py_test(align,
                                          [test_xes_log_map(), test_model()], State),
    ?assertMatch({ok, #{function := align}}, Result).

%% Test: do_call_pm4py error handling
do_call_pm4py_error_handling_test_() ->
    {setup,
     fun() -> ok end,
     fun(_) -> ok end,
     fun(_) -> [
         ?_test(begin
             State = test_state_no_bridge(),
             %% Test with invalid function
             Result = yawl_cpn:do_call_pm4py_test(invalid_function, [], State),
             ?assertMatch({ok, _}, Result)  %% Should still return ok with placeholder
         end)
     ] end}.

%%====================================================================
%% CPN to PM4Py Conversion Tests
%%====================================================================

%% Test: to_pm4py_petri_net should return PM4Py format
to_pm4py_petri_net_test_() ->
    {setup,
     fun() -> ok end,
     fun(_) -> ok end,
     fun(_) -> [
         ?_test(begin
             CPNJSON = test_cpn_json(),
             Result = yawl_cpn:to_pm4py_petri_net_test(CPNJSON),
             ?assertMatch({ok, #{net := _, places := _, transitions := _}}, Result)
         end)
     ] end}.

%% Test: to_pm4py_petri_net with minimal CPN
to_pm4py_petri_net_minimal_test_() ->
    {setup,
     fun() -> ok end,
     fun(_) -> ok end,
     fun(_) -> [
         ?_test(begin
             MinimalCPN = #{
                 <<"places">> => [#{<<"id">> => <<"p1">>, <<"name">> => <<"Place1">>}],
                 <<"transitions">> => [#{<<"id">> => <<"t1">>, <<"name">> => <<"Trans1">>}],
                 <<"arcs">> => []
             },
             Result = yawl_cpn:to_pm4py_petri_net_test(MinimalCPN),
             ?assertMatch({ok, _}, Result)
         end)
     ] end}.

%% Test: to_pm4py_petri_net conversion structure
to_pm4py_petri_net_structure_test_() ->
    {setup,
     fun() -> ok end,
     fun(_) -> ok end,
     fun(_) -> [
         ?_test(begin
             CPNJSON = test_cpn_json(),
             {ok, Result} = yawl_cpn:to_pm4py_petri_net_test(CPNJSON),
             %% Verify structure
             ?assert(maps:is_key(net, Result)),
             ?assert(maps:is_key(places, Result)),
             ?assert(maps:is_key(transitions, Result)),
             ?assert(maps:is_key(arcs, Result)),
             %% Verify counts
             Net = maps:get(net, Result),
             ?assertEqual(3, maps:get(place_count, Net)),
             ?assertEqual(2, maps:get(transition_count, Net)),
             ?assertEqual(4, maps:get(arc_count, Net))
         end)
     ] end}.

%%====================================================================
%% Integration Tests
%%====================================================================

%% Test: Full pipeline from CPN JSON to PM4Py
cpn_to_pm4py_pipeline_test_() ->
    {setup,
     fun() -> ok end,
     fun(_) -> ok end,
     fun(_) -> [
         ?_test(begin
             %% 1. Export workflow to CPN JSON
             %% 2. Convert to PM4Py format
             %% 3. Verify structure
             CPNJSON = test_cpn_json(),
             {ok, PM4PyResult} = yawl_cpn:to_pm4py_petri_net_test(CPNJSON),
             ?assert(maps:is_key(net, PM4PyResult)),
             ?assert(maps:is_key(places, PM4PyResult)),
             ?assert(maps:is_key(transitions, PM4PyResult)),
             ?assert(maps:is_key(arcs, PM4PyResult))
         end)
     ] end}.

%% Test: Verify local conversion method when bridge unavailable
cpn_local_conversion_test_() ->
    {setup,
     fun() -> ok end,
     fun(_) -> ok end,
     fun(_) -> [
         ?_test(begin
             CPNJSON = test_cpn_json(),
             {ok, Result} = yawl_cpn:to_pm4py_petri_net_test(CPNJSON),
             %% Should use local conversion when bridge unavailable
             ?assertEqual(local, maps:get(conversion_method, Result))
         end)
     ] end}.

%% Test: Verify timestamp is included in result
cpn_timestamp_test_() ->
    {setup,
     fun() -> ok end,
     fun(_) -> ok end,
     fun(_) -> [
         ?_test(begin
             CPNJSON = test_cpn_json(),
             {ok, Result} = yawl_cpn:to_pm4py_petri_net_test(CPNJSON),
             ?assert(maps:is_key(timestamp, Result)),
             Timestamp = maps:get(timestamp, Result),
             ?assert(is_integer(Timestamp)),
             ?assert(Timestamp > 0)
         end)
     ] end}.
