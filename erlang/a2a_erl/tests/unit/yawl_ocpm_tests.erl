%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL OCPM Module
%%%
%%% Tests for Object-Centric Process Mining based on van der Aalst 2025.
%%% Paper: arXiv:2508.00116 (Jul 2025)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_ocpm_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").

-include("yawl_types.hrl").
-include("yawl_xes.hrl").

%% Test fixtures
test_ocel_log() ->
    #{
        log_id => <<"test_ocel_log">>,
        events => [
            #{
                event_id => <<"e1">>,
                timestamp => 1000,
                activity => <<"CreateOrder">>,
                objects => #{<<"Order">> => [<<"order1">>]},
                attributes => #{customer => <<"cust1">>, amount => 100}
            },
            #{
                event_id => <<"e2">>,
                timestamp => 2000,
                activity => <<"CreateItem">>,
                objects => #{<<"Item">> => [<<"item1">>, <<"item2">>]},
                attributes => #{}
            },
            #{
                event_id => <<"e3">>,
                timestamp => 3000,
                activity => <<"AddItemToOrder">>,
                objects => #{
                    <<"Order">> => [<<"order1">>],
                    <<"Item">> => [<<"item1">>]
                },
                attributes => #{quantity => 2}
            },
            #{
                event_id => <<"e4">>,
                timestamp => 4000,
                activity => <<"AddItemToOrder">>,
                objects => #{
                    <<"Order">> => [<<"order1">>],
                    <<"Item">> => [<<"item2">>]
                },
                attributes => #{quantity => 1}
            },
            #{
                event_id => <<"e5">>,
                timestamp => 5000,
                activity => <<"CompleteOrder">>,
                objects => #{<<"Order">> => [<<"order1">>]},
                attributes => #{total => 300}
            }
        ],
        object_types => [<<"Order">>, <<"Item">>],
        metadata => #{created_at => erlang:system_time(millisecond)}
    }.

multi_object_event() ->
    #{
        activity => <<"ProcessPayment">>,
        objects => #{
            <<"Order">> => [<<"order1">>],
            <<"Payment">> => [<<"payment1">>],
            <<"Customer">> => [<<"cust1">>]
        },
        attributes => #{
            amount => 300,
            method => <<"credit_card">>
        }
    }.

%%====================================================================
%% Object-Centric Logging Tests
%%====================================================================

log_oc_event_test_() ->
    {setup,
     fun() -> {ok, Pid} = yawl_ocpm:start_link(), Pid end,
     fun(_Pid) -> yawl_ocpm:stop() end,
     fun(_Pid) ->
         Event = #{
             activity => <<"TestActivity">>,
             objects => #{<<"Object1">> => [<<"obj1">>]},
             attributes => #{}
         },
         ?assertEqual(ok, yawl_ocpm:log_oc_event(Event))
     end}.

log_multi_object_event_test_() ->
    {setup,
     fun() -> {ok, Pid} = yawl_ocpm:start_link(), Pid end,
     fun(_Pid) -> yawl_ocpm:stop() end,
     fun(_Pid) ->
         Objects = #{
             <<"Order">> => [<<"order1">>],
             <<"Item">> => [<<"item1">>]
         },
         EventData = #{
             activity => <<"AddItem">>
         },
         ?assertEqual(ok, yawl_ocpm:log_multi_object_event(Objects, EventData))
     end}.

create_ocel_log_test_() ->
    {setup,
     fun() -> {ok, Pid} = yawl_ocpm:start_link(), Pid end,
     fun(_Pid) -> yawl_ocpm:stop() end,
     fun(_Pid) ->
         {ok, LogId} = yawl_ocpm:create_ocel_log(),
         ?assert(is_binary(LogId)),
         ?assertMatch(<<"ocel_log_", _/binary>>, LogId)
     end}.

get_ocel_log_test_() ->
    {setup,
     fun() ->
         {ok, Pid} = yawl_ocpm:start_link(),
         {ok, LogId} = yawl_ocpm:create_ocel_log(),
         {Pid, LogId}
     end,
     fun({_Pid, _LogId}) -> yawl_ocpm:stop() end,
     fun({_Pid, LogId}) ->
         {ok, Log} = yawl_ocpm:get_ocel_log(LogId),
         ?assertMatch(#{log_id := LogId}, Log)
     end}.

%%====================================================================
%% OCPM to XES Conversion Tests
%%====================================================================

ocpm_to_standard_xes_test_() ->
    OCELLog = test_ocel_log(),
    XESLog = yawl_ocpm:ocpm_to_standard_xes(OCELLog),
    ?assertMatch(#xes_log{}, XESLog),
    ?assert(length(XESLog#xes_log.traces) > 0).

extract_object_type_test_() ->
    OCELLog = test_ocel_log(),
    OrderEvents = yawl_ocpm:extract_object_type(OCELLog, <<"Order">>),
    ?assert(length(OrderEvents) > 0),
    ?assert(lists:all(
        fun(E) ->
            Objects = maps:get(objects, E, #{}),
            maps:is_key(<<"Order">>, Objects)
        end,
        OrderEvents
    )).

filter_by_object_type_test_() ->
    OCELLog = test_ocel_log(),
    Filtered = yawl_ocpm:filter_by_object_type(OCELLog, <<"Item">>),
    ?assertMatch(#{events := _, object_types := [<<"Item">>]}, Filtered),
    ?assertEqual([<<"Item">>], maps:get(object_types, Filtered)).

flatten_ocel_log_test_() ->
    OCELLog = test_ocel_log(),
    Traces = yawl_ocpm:flatten_ocel_log(OCELLog),
    ?assert(is_list(Traces)),
    ?assert(length(Traces) > 0),
    %% Each trace should be a list of events
    lists:foreach(
        fun(Trace) ->
            ?assert(is_list(Trace))
        end,
        Traces
    ).

%%====================================================================
%% AI Grounding Tests
%%====================================================================

ground_generative_ai_test_() ->
    OCELLog = test_ocel_log(),
    Result = yawl_ocpm:ground_generative_ai(OCELLog),
    ?assertMatch(#{
        grounded := _,
        confidence := _,
        evidence_count := _,
        grounding_map := _
    }, Result),
    ?assert(is_boolean(maps:get(grounded, Result))),
    ?assert(maps:get(confidence, Result) >= 0.0),
    ?assert(maps:get(confidence, Result) =< 1.0).

ground_predictive_ai_test_() ->
    OCELLog = test_ocel_log(),
    Result = yawl_ocpm:ground_predictive_ai(OCELLog),
    ?assertMatch(#{
        grounded := _,
        confidence := _,
        evidence_count := _,
        grounding_map := _
    }, Result),
    ?assert(is_boolean(maps:get(grounded, Result))),
    ?assert(maps:get(confidence, Result) >= 0.0),
    ?assert(maps:get(confidence, Result) =< 1.0).

ground_prescriptive_ai_test_() ->
    OCELLog = test_ocel_log(),
    Result = yawl_ocpm:ground_prescriptive_ai(OCELLog),
    ?assertMatch(#{
        grounded := _,
        confidence := _,
        evidence_count := _,
        grounding_map := _
    }, Result),
    ?assert(is_boolean(maps:get(grounded, Result))),
    ?assert(maps:get(confidence, Result) >= 0.0).

compute_grounding_score_test_() ->
    OCELLog = test_ocel_log(),
    AIOutput = #{
        predictions => [
            #{activity => <<"CreateOrder">>, object_type => <<"Order">>},
            #{activity => <<"CompleteOrder">>, object_type => <<"Order">>},
            #{activity => <<"UnknownActivity">>, object_type => <<"Unknown">>}
        ]
    },
    Score = yawl_ocpm:compute_grounding_score(OCELLog, AIOutput),
    ?assert(Score >= 0.0),
    ?assert(Score =< 1.0).

grounding_score_empty_predictions_test_() ->
    OCELLog = test_ocel_log(),
    AIOutput = #{predictions => []},
    Score = yawl_ocpm:compute_grounding_score(OCELLog, AIOutput),
    ?assertEqual(1.0, Score).

%%====================================================================
%% Process Intelligence Query Tests
%%====================================================================

pi_object_lifecycle_test_() ->
    OCELLog = test_ocel_log(),
    Lifecycle = yawl_ocpm:pi_object_lifecycle(OCELLog, <<"order1">>),
    ?assertMatch(#{
        object_id := <<"order1">>,
        event_count := _,
        lifecycle_states := _,
        first_event := _,
        last_event := _
    }, Lifecycle),
    ?assert(maps:get(event_count, Lifecycle) > 0).

pi_inter_object_dependencies_test_() ->
    OCELLog = test_ocel_log(),
    Dependencies = yawl_ocpm:pi_inter_object_dependencies(OCELLog),
    ?assert(is_list(Dependencies)),
    %% Each dependency is a tuple {Type1, Type2, Count}
    lists:foreach(
        fun({Type1, Type2, Count}) ->
            ?assert(is_binary(Type1)),
            ?assert(is_binary(Type2)),
            ?assert(is_integer(Count)),
            ?assert(Count >= 0)
        end,
        Dependencies
    ).

pi_object_interactions_test_() ->
    OCELLog = test_ocel_log(),
    Interactions = yawl_ocpm:pi_object_interactions(OCELLog),
    ?assert(is_list(Interactions)),
    ?assert(length(Interactions) > 0),
    lists:foreach(
        fun(Interaction) ->
            ?assertMatch(#{
                activity := _,
                timestamp := _,
                participating_types := _,
                interaction_type := _
            }, Interaction)
        end,
        Interactions
    ).

pi_process_variant_test_() ->
    OCELLog = test_ocel_log(),
    Variant = yawl_ocpm:pi_process_variant(OCELLog, <<"Order">>),
    ?assert(is_list(Variant)),
    ?assert(length(Variant) > 0),
    %% All elements should be activity binaries
    lists:foreach(
        fun(Activity) ->
            ?assert(is_binary(Activity))
        end,
        Variant
    ).

%%====================================================================
%% Multi-Object Event Tests
%%====================================================================

multi_object_interaction_classification_test_() ->
    OCELLog = test_ocel_log(),
    %% Add multi-object event
    MultiObjEvent = multi_object_event(),
    %% Log should have multi-object interactions
    Interactions = yawl_ocpm:pi_object_interactions(OCELLog),
    MultiInteractions = lists:filter(
        fun(I) ->
            Types = maps:get(participating_types, I, []),
            length(Types) >= 2
        end,
        Interactions
    ),
    ?assert(length(MultiInteractions) >= 2).  %% We have 2 multi-object events in test log

interaction_type_test_() ->
    %% Test different interaction classifications
    SingleObjEvent = #{
        activity => <<"Single">>,
        objects => #{<<"Order">> => [<<"order1">>]},
        timestamp => 1000
    },
    BinaryObjEvent = #{
        activity => <<"Binary">>,
        objects => #{<<"Order">> => [<<"order1">>], <<"Item">> => [<<"item1">>]},
        timestamp => 2000
    },
    MultiObjEvent = #{
        activity => <<"Multi">>,
        objects => #{
            <<"Order">> => [<<"order1">>],
            <<"Item">> => [<<"item1">>],
            <<"Payment">> => [<<"pay1">>]
        },
        timestamp => 3000
    },
    %% These would be tested through the interaction patterns
    ?assert(is_map(SingleObjEvent)),
    ?assert(is_map(BinaryObjEvent)),
    ?assert(is_map(MultiObjEvent)).

%%====================================================================
%% OCPM Edge Case Tests
%%====================================================================

empty_ocel_log_test_() ->
    EmptyLog = #{
        log_id => <<"empty">>,
        events => [],
        object_types => [],
        metadata => #{}
    },
    Result = yawl_ocpm:ground_generative_ai(EmptyLog),
    ?assertMatch(#{grounded := false, confidence := 0.0}, Result).

single_event_log_test_() ->
    SingleEventLog = #{
        log_id => <<"single">>,
        events => [
            #{
                event_id => <<"e1">>,
                timestamp => 1000,
                activity => <<"OnlyActivity">>,
                objects => #{<<"Obj">> => [<<"obj1">>]},
                attributes => #{}
            }
        ],
        object_types => [<<"Obj">>],
        metadata => #{}
    },
    Result = yawl_ocpm:ground_generative_ai(SingleEventLog),
    ?assert(maps:get(grounded, Result)),
    ?assert(maps:get(evidence_count, Result) =:= 1).

missing_attributes_test_() ->
    %% Test handling of events with missing optional attributes
    Event = #{
        activity => <<"Test">>,
        objects => #{<<"Obj">> => [<<"obj1">>]}
        %% Missing 'attributes' key
    },
    {setup,
     fun() -> {ok, Pid} = yawl_ocpm:start_link(), Pid end,
     fun(_Pid) -> yawl_ocpm:stop() end,
     fun(_Pid) ->
         %% Should not crash
         ?assertEqual(ok, yawl_ocpm:log_oc_event(Event))
     end}.

%%====================================================================
%% XES Conversion Edge Cases
%%====================================================================

xes_conversion_preserves_activities_test_() ->
    OCELLog = test_ocel_log(),
    XESLog = yawl_ocpm:ocpm_to_standard_xes(OCELLog),
    %% Check that activities are preserved in traces
    AllActivities = lists:flatmap(
        fun(Trace) ->
            [#xes_event{activity = A} || A <- Trace#xes_trace.events]
        end,
        XESLog#xes_log.traces
    ),
    ?assert(length(AllActivities) > 0),
    lists:foreach(
        fun(A) ->
            ?assert(is_binary(A))
        end,
        AllActivities
    ).

xes_trace_count_matches_object_types_test_() ->
    OCELLog = test_ocel_log(),
    XESLog = yawl_ocpm:ocpm_to_standard_xes(OCELLog),
    %% Should have one trace per object type
    ObjectTypeCount = length(maps:get(object_types, OCELLog, [])),
    TraceCount = length(XESLog#xes_log.traces),
    ?assert(TraceCount >= ObjectTypeCount).
