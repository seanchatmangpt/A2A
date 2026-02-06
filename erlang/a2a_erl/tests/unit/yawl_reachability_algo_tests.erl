%%%-------------------------------------------------------------------
%%% @doc
%%% Chicago-Style TDD Tests for YAWL Reachability Algorithms
%%%
%%% RED PHASE: Tests written first.
%%% GREEN PHASE: Functions implemented to make tests pass.
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_reachability_algo_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").

%%====================================================================
%% CYCLE DETECTION TESTS
%%====================================================================

acyclic_net_no_cycles_test_() ->
    NetInfo = #{
        places => [p1, p2, p3],
        transitions => [t1, t2],
        preset => #{t1 => [p1], t2 => [p2]},
        postset => #{p1 => [t1], p2 => [t2], p3 => []}
    },
    [?_assertEqual([], yawl_reachability:detect_cycles_in_net(NetInfo))].

self_loop_cycle_detected_test_() ->
    NetInfo = #{
        places => [p1],
        transitions => [t1],
        preset => #{t1 => [p1]},
        postset => #{p1 => [t1]}
    },
    [?_test(begin
        Cycles = yawl_reachability:detect_cycles_in_net(NetInfo),
        ?assert(length(Cycles) > 0),
        ?assert(lists:any(fun(C) -> lists:member(p1, C) end, Cycles))
    end)].

two_node_cycle_detected_test_() ->
    NetInfo = #{
        places => [p1, p2],
        transitions => [t1, t2],
        preset => #{t1 => [p1], t2 => [p2]},
        postset => #{p1 => [t2], p2 => [t1]}
    },
    [?_test(begin
        Cycles = yawl_reachability:detect_cycles_in_net(NetInfo),
        ?assert(length(Cycles) > 0)
    end)].

cycle_structure_test_() ->
    NetInfo = #{
        places => [p1, p2],
        transitions => [t1, t2],
        preset => #{t1 => [p1], t2 => [p2]},
        postset => #{p1 => [t2], p2 => [t1]}
    },
    [?_test(begin
        Cycles = yawl_reachability:detect_cycles_in_net(NetInfo),
        ?assert(is_list(Cycles)),
        ?assert(lists:all(fun is_list/1, Cycles))
    end)].

%%====================================================================
%% STATE SPACE EXPLORATION TESTS
%%====================================================================

state_space_includes_initial_marking_test_() ->
    NetInfo = #{
        places => [p1],
        transitions => [],
        preset => #{},
        postset => #{p1 => []}
    },
    InitialMarking = #{p1 => [token]},
    [?_assert(lists:member(InitialMarking,
        yawl_reachability:compute_all_reachable_markings(NetInfo, InitialMarking)))].

state_space_empty_net_test_() ->
    NetInfo = #{
        places => [],
        transitions => [],
        preset => #{},
        postset => #{}
    },
    InitialMarking = #{},
    [?_assertEqual([InitialMarking],
        yawl_reachability:compute_all_reachable_markings(NetInfo, InitialMarking))].

state_space_finds_reachable_states_test_() ->
    NetInfo = #{
        places => [p1, p2, p3],
        transitions => [t1, t2],
        preset => #{t1 => [p1], t2 => [p2]},
        postset => #{p1 => [t1], p2 => [t2], p3 => []}
    },
    InitialMarking = #{p1 => [token], p2 => [], p3 => []},
    [?_test(begin
        Reachable = yawl_reachability:compute_all_reachable_markings(NetInfo, InitialMarking),
        ?assert(length(Reachable) > 1)
    end)].

state_space_returns_unique_markings_test_() ->
    NetInfo = #{
        places => [p1, p2],
        transitions => [t1],
        preset => #{t1 => [p1]},
        postset => #{p1 => [t1], p2 => []}
    },
    InitialMarking = #{p1 => [token], p2 => []},
    [?_test(begin
        Reachable = yawl_reachability:compute_all_reachable_markings(NetInfo, InitialMarking),
        Unique = lists:usort(fun(A, B) -> A =< B end, Reachable),
        ?assertEqual(length(Reachable), length(Unique))
    end)].
