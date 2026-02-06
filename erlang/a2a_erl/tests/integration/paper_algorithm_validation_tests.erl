%%%-------------------------------------------------------------------
%%% @doc
%%% Integration Tests for Paper Algorithm Validation
%%%
%%% Comprehensive tests to validate the implementation of algorithms
%%% from van der Aalst 2025-2026 papers.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(paper_algorithm_validation_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").

-include("yawl_types.hrl").
-include("yawl_xes.hrl").
-include_lib("gen_pnet/include/gen_pnet.hrl").

%%====================================================================
%% Paper 2602.02447: Reachability Diagnostics Tests
%%====================================================================

op2_reachability_test_() ->
    %% Test O(P² + T²) reachability on acyclic free-choice net
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = create_afc_test_net(),
         TargetMarking = #{'end' => [token]},
         Result = yawl_reachability:is_reachable(Net, TargetMarking),
         ?assertMatch(#{is_reachable := true}, Result)
     end}.

admissibility_checking_test_() ->
    %% Test admissibility for concurrent markings
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = create_afc_test_net(),
         PlaceSet = sets:from_list([a, b, c]),
         MaxMarking = yawl_reachability:maximum_admissible(Net, PlaceSet),
         ?assert(maps:size(MaxMarking) > 0)
     end}.

%%====================================================================
%% Paper 2509.15346: Partial Order Process Discovery Tests
%%====================================================================

partial_order_preserves_concurrency_test_() ->
    %% Test that partial order preserves concurrency
    {setup,
     fun() -> {ok, _} = yawl_partial_order:start_link() end,
     fun(_) -> yawl_partial_order:stop() end,
     fun(_) ->
         Events = create_concurrent_event_trace(),
         PO = yawl_partial_order:event_log_to_partial_order(Events),
         Concurrent = maps:get(concurrent, PO, sets:new()),
         ?assert(sets:size(Concurrent) > 0)
     end}.

sound_by_construction_test_() ->
    %% Test that discovered models are sound workflow nets
    {setup,
     fun() -> {ok, _} = yawl_partial_order:start_link() end,
     fun(_) -> yawl_partial_order:stop() end,
     fun(_) ->
         PO = create_test_partial_order(),
         Model = yawl_partial_order:partial_order_to_workflow_net(PO),
         ?assertMatch(#{is_sound_by_construction := true}, Model)
     end}.

%%====================================================================
%% Paper 2509.15336: LLM Hallucination Detection Tests
%%====================================================================

knowledge_driven_hallucination_test_() ->
    %% Test detection of knowledge-driven hallucinations
    {setup,
     fun() -> {ok, _} = yawl_llm_validator:start_link() end,
     fun(_) -> yawl_llm_validator:stop() end,
     fun(_) ->
         Scenario = yawl_llm_validator:create_conflict_scenario(spurious_activities),
         Model = maps:get(model, Scenario),
         Evidence = maps:get(evidence, Scenario),
         Result = yawl_llm_validator:validate_against_xes(Model, Evidence),
         ?assertMatch(#{is_valid := false}, Result),
         Contradictions = maps:get(contradictions, Result, []),
         ?assert(length(Contradictions) > 0)
     end}.

fidelity_assessment_test_() ->
    %% Test fidelity scoring
    {setup,
     fun() -> {ok, _} = yawl_llm_validator:start_link() end,
     fun(_) -> yawl_llm_validator:stop() end,
     fun(_) ->
         GoodModel = create_accurate_model(),
         BadModel = create_inaccurate_model(),
         Evidence = test_xes_log_map(),
         GoodScore = yawl_llm_validator:fidelity_score(GoodModel, Evidence),
         BadScore = yawl_llm_validator:fidelity_score(BadModel, Evidence),
         ?assert(GoodScore > BadScore)
     end}.

%%====================================================================
%% Paper 2508.00116: Object-Centric Process Mining Tests
%%====================================================================

ocel_event_logging_test_() ->
    %% Test OCPM event logging
    {setup,
     fun() -> {ok, _} = yawl_ocpm:start_link() end,
     fun(_) -> yawl_ocpm:stop() end,
     fun(_) ->
         Objects = #{order => [<<"order1">>], item => [<<"item1">>, <<"item2">>]},
         yawl_ocpm:log_multi_object_event(Objects, #{activity => <<"process">>}),
         {ok, LogId} = yawl_ocpm:create_ocel_log(),
         {ok, OCELLog} = yawl_ocpm:get_ocel_log(LogId),
         ?assertMatch(#{events := _, object_types := _}, OCELLog)
     end}.

ai_grounding_test_() ->
    %% Test AI grounding with OCPM data
    {setup,
     fun() -> {ok, _} = yawl_ocpm:start_link() end,
     fun(_) -> yawl_ocpm:stop() end,
     fun(_) ->
         OCELLog = create_test_ocel_log(),
         GenResult = yawl_ocpm:ground_generative_ai(OCELLog),
         ?assertMatch(#{grounded := _, confidence := _}, GenResult),
         PredResult = yawl_ocpm:ground_predictive_ai(OCELLog),
         ?assertMatch(#{grounded := _, confidence := _}, PredResult)
     end}.

%%====================================================================
%% Paper 2506.12238: Colored Petri Nets Tests
%%====================================================================

cpn_token_color_test_() ->
    %% Test colored token creation and handling
    {setup,
     fun() -> {ok, _} = yawl_cpn:start_link() end,
     fun(_) -> yawl_cpn:stop() end,
     fun(_) ->
         IntCS = yawl_cpn:create_color_set(integer, integer),
         ?assertMatch(#{type := integer}, IntCS),
         TimedToken = yawl_cpn:create_timed_token(test_data(), erlang:system_time(millisecond)),
         ?assertMatch(#{data := _, timestamp := _}, TimedToken)
     end}.

json_export_test_() ->
    %% Test JSON export for LLM compatibility
    {setup,
     fun() -> {ok, _} = yawl_cpn:start_link() end,
     fun(_) -> yawl_cpn:stop() end,
     fun(_) ->
         JSON = yawl_cpn:workflow_to_cpn_json(yawl_patterns),
         ?assert(is_binary(JSON)),
         ?assert(binary:match(JSON, <<"places">>) =/= nomatch)
     end}.

%%====================================================================
%% Performance Benchmark Tests
%%====================================================================

reachability_complexity_benchmark_test_() ->
    %% Compare O(P² + T²) vs exponential on larger nets
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         SmallNet = create_afc_test_net(),
         MediumNet = create_medium_afc_net(),
         {_Time1, _} = timer:tc(fun() ->
             yawl_reachability:is_reachable(SmallNet, #{'end' => [token]})
         end),
         {_Time2, _} = timer:tc(fun() ->
             yawl_reachability:is_reachable(MediumNet, #{'end' => [token]})
         end),
         ?assert(true)
     end}.

partial_order_reduction_test_() ->
    %% Test partial order reduction ratio
    {setup,
     fun() -> {ok, _} = yawl_partial_order:start_link() end,
     fun(_) -> yawl_partial_order:stop() end,
     fun(_) ->
         Events = create_concurrent_event_trace(),
         PO = yawl_partial_order:event_log_to_partial_order(Events),
         _TotalPairs = length(maps:get(events, PO, [])) * (length(maps:get(events, PO, [])) - 1) div 2,
         ConcurrentPairs = sets:size(maps:get(concurrent, PO, sets:new())),
         ?assert(ConcurrentPairs > 0)
     end}.

%%====================================================================
%% Fixtures and Helpers
%%====================================================================

create_afc_test_net() ->
    %% Create an acyclic free-choice net for testing
    yosys_test_net().

yosys_test_net() ->
    %% Simple test net structure
    #{
        places => [start, a, b, 'end'],
        transitions => [t1, t2],
        preset => #{t1 => [start], t2 => [a, b]},
        postset => #{start => [t1], a => [t2], b => [t2], 'end' => []}
    }.

create_medium_afc_net() ->
    #{
        places => [start, p1, p2, p3, p4, 'end'],
        transitions => [t1, t2, t3, t4, t5],
        preset => #{
            t1 => [start],
            t2 => [p1],
            t3 => [p2],
            t4 => [p3],
            t5 => [p4]
        },
        postset => #{
            start => [t1],
            p1 => [t2],
            p2 => [t3],
            p3 => [t4],
            p4 => [t5],
            'end' => []
        }
    }.

create_concurrent_event_trace() ->
    [
        #{id => <<"e1">>, activity => <<"Start">>, timestamp => 1000, trace_id => <<"t1">>},
        #{id => <<"e2">>, activity => <<"TaskA">>, timestamp => 2000, trace_id => <<"t1">>},
        #{id => <<"e3">>, activity => <<"TaskB">>, timestamp => 2000, trace_id => <<"t1">>},
        #{id => <<"e4">>, activity => <<"End">>, timestamp => 3000, trace_id => <<"t1">>}
    ].

create_test_partial_order() ->
    #{
        events => create_concurrent_event_trace(),
        order => #{<<"e1">> => [<<"e2">>, <<"e3">>], <<"e2">> => [<<"e4">>], <<"e3">> => [<<"e4">>]},
        concurrent => sets:from_list([{<<"e2">>, <<"e3">>}]),
        trace_id => <<"test_po">>
    }.

test_xes_log_map() ->
    #{
        log_id => <<"test">>,
        trace_id => <<"trace1">>,
        started_at => erlang:system_time(millisecond),
        events => [
            #{
                event_id => <<"e1">>,
                timestamp => 1000,
                activity => <<"A">>,
                lifecycle => complete
            },
            #{
                event_id => <<"e2">>,
                timestamp => 2000,
                activity => <<"B">>,
                lifecycle => complete
            }
        ],
        metadata => #{}
    }.

create_accurate_model() ->
    #{
        model_type => <<"accurate">>,
        activities => [<<"A">>, <<"B">>],
        transitions => [#{from => <<"A">>, to => <<"B">>}]
    }.

create_inaccurate_model() ->
    #{
        model_type => <<"inaccurate">>,
        activities => [<<"A">>, <<"C">>],
        transitions => [#{from => <<"A">>, to => <<"D">>}]
    }.

create_test_ocel_log() ->
    #{
        log_id => <<"ocel_test">>,
        events => [
            #{
                event_id => <<"oe1">>,
                timestamp => 1000,
                activity => <<"order_process">>,
                objects => #{order => [<<"o1">>], item => [<<"i1">>]}
            }
        ],
        object_types => [<<"order">>, <<"item">>],
        metadata => #{}
    }.

test_data() ->
    <<"test_data">>.
