%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL Reachability Analysis
%%%
%%% Tests for O(P² + T²) reachability algorithm based on van der Aalst 2026.
%%% Paper: arXiv:2602.02447
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_reachability_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").

%% Include type definitions
-include("yawl_types.hrl").
-include_lib("gen_pnet/include/gen_pnet.hrl").

%% Test fixtures
simple_test_net() ->
    #{
        places => [p1, p2, p3, p4],
        transitions => [t1, t2, t3],
        preset => #{
            t1 => [p1],
            t2 => [p2],
            t3 => [p3]
        },
        postset => #{
            p1 => [t1],
            p2 => [t2],
            p3 => [t3],
            p4 => []
        }
    }.

concurrent_test_net() ->
    #{
        places => [start, a, b, join, finish],
        transitions => [split, ta, tb, merge],
        preset => #{
            split => [start],
            ta => [a],
            tb => [b],
            merge => [a, b]
        },
        postset => #{
            start => [split],
            a => [ta],
            b => [tb],
            ta => [merge],
            tb => [merge],
            merge => [finish],
            finish => []
        }
    }.

%%====================================================================
%% Admissibility Tests
%%====================================================================

is_admissible_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = concurrent_test_net(),
         Marking = #{a => [token], b => [token]},
         Result = yawl_reachability:is_admissible(Net, Marking),
         ?assertMatch(#{is_admissible := true}, Result),
         ?assert(length(maps:get(concurrent_pairs, Result, [])) > 0)
     end}.

not_admissible_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = simple_test_net(),
         Marking = #{p1 => [token], p2 => [token]},
         Result = yawl_reachability:is_admissible(Net, Marking),
         ?assertMatch(#{is_admissible := false}, Result)
     end}.

maximum_admissible_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = concurrent_test_net(),
         PlaceSet = sets:from_list([start, a, b, join, finish]),
         MaxMarking = yawl_reachability:maximum_admissible(Net, PlaceSet),
         ?assert(maps:is_key(start, MaxMarking)),
         ?assert(maps:is_key(a, MaxMarking)),
         ?assert(maps:is_key(b, MaxMarking))
     end}.

%%====================================================================
%% Concurrent Place Tests
%%====================================================================

are_concurrent_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = concurrent_test_net(),
         ?assert(yawl_reachability:are_concurrent(Net, a, b)),
         ?assertNot(yawl_reachability:are_concurrent(Net, a, start))
     end}.

concurrent_places_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = concurrent_test_net(),
         ConcurrentPairs = yawl_reachability:concurrent_places(Net, sets:from_list([a, b])),
         ?assert(lists:member({a, b}, ConcurrentPairs) orelse lists:member({b, a}, ConcurrentPairs))
     end}.

%%====================================================================
%% Diverging Transitions Tests
%%====================================================================

diverging_transitions_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = concurrent_test_net(),
         Marking = #{a => [token], b => [token]},
         Diverging = yawl_reachability:diverging_transitions(Net, Marking),
         ?assert(lists:member(split, Diverging))
     end}.

%%====================================================================
%% Reachability Tests
%%====================================================================

is_reachable_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = simple_test_net(),
         TargetMarking = #{p4 => [token]},
         Result = yawl_reachability:is_reachable(Net, TargetMarking),
         ?assertMatch(#{is_reachable := true}, Result)
     end}.

not_reachable_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = simple_test_net(),
         TargetMarking = #{p1 => [token], p4 => [token]},
         Result = yawl_reachability:is_reachable(Net, TargetMarking),
         ?assertMatch(#{is_reachable := false}, Result)
     end}.

%%====================================================================
%% Post-Dominance Frontier Tests
%%====================================================================

post_dominance_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = concurrent_test_net(),
         PDF = yawl_reachability:compute_post_dominance_frontiers(Net),
         ?assert(is_map(PDF)),
         ?assert(maps:is_key(finish, PDF))
     end}.

%%====================================================================
%% Acyclic Free-Choice Verification Tests
%%====================================================================

verify_afc_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = concurrent_test_net(),
         AFC = yawl_reachability:verify_acyclic_free_choice(Net),
         ?assertMatch(#{is_afc := true}, AFC)
     end}.

verify_not_free_choice_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = #{
             places => [p1, p2, p3],
             transitions => [t1, t2],
             preset => #{
                 t1 => [p1],
                 t2 => [p1, p2]
             },
             postset => #{
                 p1 => [t1],
                 p2 => [t2],
                 p3 => [t1, t2]
             }
         },
         AFC = yawl_reachability:verify_acyclic_free_choice(Net),
         ?assertMatch(#{is_free_choice := false}, AFC)
     end}.

%%====================================================================
%% Structural Conflict Analysis Tests
%%====================================================================

structural_conflict_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = concurrent_test_net(),
         Conflicts = yawl_reachability:structural_conflict_analysis(Net),
         ?assert(is_map(Conflicts)),
         ?assert(maps:is_key(conflict_count, Conflicts))
     end}.

%%====================================================================
%% Diagnostics Tests
%%====================================================================

get_diagnostics_test_() ->
    {setup,
     fun() -> {ok, _} = yawl_reachability:start_link() end,
     fun(_) -> yawl_reachability:stop() end,
     fun(_) ->
         Net = concurrent_test_net(),
         TargetMarking = #{a => [token]},
         Diagnostics = yawl_reachability:get_reachability_diagnostics(Net, TargetMarking),
         ?assertMatch(#{reachability := _, admissibility := _}, Diagnostics)
     end}.
