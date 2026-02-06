%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL Partial Order Process Discovery
%%%
%%% Tests for partial order process discovery based on van der Aalst 2025.
%%% Paper: arXiv:2509.15346
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_partial_order_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").

-include("yawl_types.hrl").

%% Test event log fixture
test_event_log() ->
    [
        #{
            id => <<"e1">>,
            timestamp => 1000,
            activity => <<"A">>,
            trace_id => <<"trace1">>
        },
        #{
            id => <<"e2">>,
            timestamp => 2000,
            activity => <<"B">>,
            trace_id => <<"trace1">>
        },
        #{
            id => <<"e3">>,
            timestamp => 3000,
            activity => <<"C">>,
            trace_id => <<"trace1">>
        }
    ].

%%====================================================================
%% Partial Order Derivation Tests
%%====================================================================

event_log_to_partial_order_test_() ->
    Events = test_event_log(),
    PO = yawl_partial_order:event_log_to_partial_order(Events),
    ?assertMatch(#{events := _, order := _, concurrent := _}, PO),
    ?assert(length(maps:get(events, PO, [])) =:= 3).

concurrent_events_test_() ->
    Events = test_event_log(),
    Concurrent = yawl_partial_order:concurrent_events(Events, 2),
    ?assert(is_list(Concurrent)).

partial_order_to_model_test_() ->
    PO = #{
        events => test_event_log(),
        order => #{<<"e1">> => [<<"e2">>], <<"e2">> => [<<"e3">>]},
        concurrent => sets:new(),
        trace_id => <<"test">>
    },
    Model = yawl_partial_order:partial_order_to_model(PO),
    ?assertMatch(#{type := process_model, activities := _}, Model).

%%====================================================================
%% Hierarchical Abstraction Tests
%%====================================================================

abstract_exclusive_choices_test_() ->
    PO = #{
        events => test_event_log(),
        order => #{<<"e1">> => [<<"e2">>, <<"e3">>], <<"e2">> => [<<"e4">>], <<"e3">> => [<<"e4">>]},
        concurrent => sets:from_list([{<<"e2">>, <<"e3">>}]),
        trace_id => <<"test">>
    },
    Abstracted = yawl_partial_order:abstract_exclusive_choices(PO),
    ?assert(is_map(Abstracted)).

abstract_loops_test_() ->
    PO = #{
        events => [
            #{id => <<"e1">>, activity => <<"Start">>, timestamp => 1000},
            #{id => <<"e2">>, activity => <<"Process">>, timestamp => 2000},
            #{id => <<"e3">>, activity => <<"Start">>, timestamp => 3000}  %% Loop
        ],
        order => #{<<"e1">> => [<<"e2">>], <<"e2">> => [<<"e3">>], <<"e3">> => [<<"e1">>]},
        concurrent => sets:new(),
        trace_id => <<"loop_test">>
    },
    Abstracted = yawl_partial_order:abstract_loops(PO),
    ?assert(is_map(Abstracted)).

%%====================================================================
%% XES Extension Tests
%%====================================================================

export_partial_order_xes_test_() ->
    PO = #{
        events => test_event_log(),
        order => #{<<"e1">> => [<<"e2">>], <<"e2">> => [<<"e3">>]},
        concurrent => sets:new(),
        trace_id => <<"test">>
    },
    XES = yawl_partial_order:export_partial_order_xes(PO),
    ?assert(is_binary(XES)),
    ?assert(binary:match(XES, <<"partialOrder">>) =/= nomatch).

validate_xes_partial_order_test_() ->
    ValidXES = <<"<?xml version=\"1.0\"?>",
                 "<log>",
                 "  <partialOrder>",
                 "    <event id=\"e1\" succ=\"e2\"/>",
                 "  </partialOrder>",
                 "</log>">>,
    ?assertMatch({ok, _}, yawl_partial_order:validate_xes_partial_order(ValidXES)).

%%====================================================================
%% Model Generation Tests
%%====================================================================%

discover_model_test_() ->
    POs = [
        #{
            events => [#{id => <<"e1">>, activity => <<"A">>}, #{id => <<"e2">>, activity => <<"B">>}],
            order => #{<<"e1">> => [<<"e2">>]},
            concurrent => sets:new(),
            trace_id => <<"t1">>
        }
    ],
    Model = yawl_partial_order:discover_model_from_partial_orders(POs),
    ?assertMatch(#{type := process_model}, Model).

merge_partial_orders_test_() ->
    PO1 = #{
        events => [#{id => <<"e1">>, activity => <<"A">>}],
        order => #{},
        concurrent => sets:new(),
        trace_id => <<"p1">>
    },
    PO2 = #{
        events => [#{id => <<"e2">>, activity => <<"B">>}],
        order => #{},
        concurrent => sets:new(),
        trace_id => <<"p2">>
    },
    Merged = yawl_partial_order:merge_partial_orders(PO1, PO2),
    ?assert(length(maps:get(events, Merged, [])) =:= 2).

partial_order_fitness_test_() ->
    PO = #{
        events => [#{id => <<"e1">>, activity => <<"A">>}, #{id => <<"e2">>, activity => <<"B">>}],
        order => #{<<"e1">> => [<<"e2">>]},
        concurrent => sets:new(),
        trace_id => <<"test">>
    },
    Model = #{activities => [<<"A">>, <<"B">>], causal_relations => #{<<"A">> => [<<"B">>]}},
    Fitness = yawl_partial_order:partial_order_fitness(PO, Model),
    ?assert(Fitness >= 0.0),
    ?assert(Fitness =< 1.01).
