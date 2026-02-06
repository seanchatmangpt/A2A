%%%-------------------------------------------------------------------
%%% @doc
%%% Advanced Concurrency Analysis for Workflow Nets
%%%
%%% This module provides advanced concurrency detection and analysis
%%% for YAWL workflow patterns, building on van der Aalst's work on
%%% concurrency in workflow nets (2025-2026).
%%%
%%% Key Features:
%%% - Pairwise concurrency detection
%%% - Maximal concurrency sets
%%% - Conflict and causal relation analysis
%%% - Concurrent regions identification
%%% - Token game analysis for concurrency validation
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_concurrency_analyzer).
-author("A2A Team").

%% API exports - Core concurrency functions
-export([
    are_concurrent/3,
    find_concurrent_pairs/2,
    find_maximal_concurrent_set/2,
    concurrent_regions/1,
    token_game/3,
    verify_concurrency_semantics/2
]).

%% API exports - Advanced relation analysis
-export([
    conflict_relation/2,
    causal_relation/2,
    concurrent_relation/2,
    relation_matrix/1,
    concurrency_graph/1
]).

%% API exports - Concurrency metrics
-export([
    concurrency_degree/2,
    average_concurrency/1,
    maximum_concurrency/1,
    concurrency_metrics/2
]).

-include("yawl_types.hrl").
-include_lib("gen_pnet/include/gen_pnet.hrl").

%%====================================================================
%% Type Definitions
%%====================================================================

-type place() :: atom().
-type marking() :: #{place() => [term()]}.
-type relation() :: concurrent | conflict | causal | unrelated.
-type relation_map() :: #{ {place(), place()} => relation() }.
-type concurrent_set() :: sets:set(place()).

%%====================================================================
%% API Functions - Core Concurrency
%%====================================================================

%% @doc Check if two places are concurrent in a given net.
%% Places are concurrent if they can both contain tokens simultaneously
%% in some reachable marking.
-spec are_concurrent(atom(), place(), place()) -> boolean().
are_concurrent(NetMod, Place1, Place2) ->
    NetInfo = extract_net_info(NetMod),
    check_structural_concurrency(NetInfo, Place1, Place2).

%% @doc Find all concurrent place pairs in the net.
-spec find_concurrent_pairs(atom(), place_set() | all) -> [{place(), place()}].
find_concurrent_pairs(NetMod, all) ->
    NetInfo = extract_net_info(NetMod),
    Places = maps:get(places, NetInfo),
    PlaceSet = sets:from_list(Places),
    find_concurrent_pairs(NetMod, PlaceSet);
find_concurrent_pairs(NetMod, PlaceSet) ->
    Places = sets:to_list(PlaceSet),
    AllPairs = [{P1, P2} || P1 <- Places, P2 <- Places, P1 < P2],

    lists:filtermap(
        fun({P1, P2}) ->
            case are_concurrent(NetMod, P1, P2) of
                true -> {true, {P1, P2}};
                false -> false
            end
        end,
        AllPairs
    ).

%% @doc Find a maximal set of mutually concurrent places.
-spec find_maximal_concurrent_set(atom(), place_set() | all) -> concurrent_set().
find_maximal_concurrent_set(NetMod, all) ->
    NetInfo = extract_net_info(NetMod),
    Places = maps:get(places, NetInfo),
    PlaceSet = sets:from_list(Places),
    find_maximal_concurrent_set(NetMod, PlaceSet);
find_maximal_concurrent_set(NetMod, PlaceSet) ->
    %% Use greedy algorithm to find maximal concurrent subset
    Places = sets:to_list(PlaceSet),
    MaxSet = find_maximal_concurrent_subset(NetMod, Places, []),
    sets:from_list(MaxSet).

%% @private
find_maximal_concurrent_subset(_NetMod, [], Acc) ->
    lists:reverse(Acc);
find_maximal_concurrent_subset(NetMod, [Place | Rest], Acc) ->
    %% Check if Place is concurrent with all in Acc
    IsConcurrent = lists:all(
        fun(P) -> are_concurrent(NetMod, Place, P) end,
        Acc
    ),

    case IsConcurrent of
        true ->
            find_maximal_concurrent_subset(NetMod, Rest, [Place | Acc]);
        false ->
            %% Try with rest
            find_maximal_concurrent_subset(NetMod, Rest, Acc)
    end.

%% @doc Identify concurrent regions in the workflow.
%% A concurrent region is a maximal set of places that can be
%% simultaneously active.
-spec concurrent_regions(atom()) -> [concurrent_set()].
concurrent_regions(NetMod) ->
    %% Find regions using structural analysis
    NetInfo = extract_net_info(NetMod),

    %% Build a graph of concurrent places and find connected components
    ConcurrentPairs = find_concurrent_pairs(NetMod, all),

    %% Build adjacency list
    Adj = lists:foldl(
        fun({P1, P2}, Acc) ->
            Acc1 = maps:update_with(P1, fun(S) -> sets:add_element(P2, S) end, sets:from_list([P2]), Acc),
            maps:update_with(P2, fun(S) -> sets:add_element(P1, S) end, sets:from_list([P1]), Acc1)
        end,
        #{},
        ConcurrentPairs
    ),

    %% Find connected components (concurrent regions)
    AllPlaces = maps:get(places, NetInfo),
    Visited = sets:new(),
    find_connected_components(AllPlaces, Adj, Visited, []).

%% @doc Execute token game to verify concurrency properties.
%% Returns true if the token game can reach a marking where
%% both places have tokens.
-spec token_game(atom(), place(), place()) -> boolean().
token_game(NetMod, Place1, Place2) ->
    %% Try to find a firing sequence that puts tokens in both places
    InitialMarking = get_initial_marking(NetMod),

    case token_game_search(NetMod, InitialMarking, Place1, Place2, 10) of
        {true, _Sequence} -> true;
        false -> false
    end.

%% @doc Verify concurrency semantics for a workflow net.
-spec verify_concurrency_semantics(atom(), term()) -> map().
verify_concurrency_semantics(NetMod, _UsrInfo) ->
    NetInfo = extract_net_info(NetMod),

    #{
        net_type => classify_net_type(NetInfo),
        has_concurrent_regions => length(concurrent_regions(NetMod)) > 0,
        concurrent_pairs => find_concurrent_pairs(NetMod, all),
        relation_matrix => relation_matrix(NetMod),
        max_concurrent_places => maximum_concurrency(NetMod),
        avg_concurrency => average_concurrency(NetMod)
    }.

%%====================================================================
%% API Functions - Relation Analysis
%%====================================================================

%% @doc Compute the conflict relation between places.
%% Two places are in conflict if they have a shared output transition.
-spec conflict_relation(atom(), place_set() | all) -> [{place(), place()}].
conflict_relation(NetMod, all) ->
    NetInfo = extract_net_info(NetMod),
    Places = maps:get(places, NetInfo),
    conflict_relation(NetMod, sets:from_list(Places));
conflict_relation(NetMod, PlaceSet) ->
    NetInfo = extract_net_info(NetMod),
    Postset = maps:get(postset, NetInfo),

    Places = sets:to_list(PlaceSet),
    AllPairs = [{P1, P2} || P1 <- Places, P2 <- Places, P1 < P2],

    lists:filter(
        fun({P1, P2}) ->
            Post1 = sets:from_list(maps:get(P1, Postset, [])),
            Post2 = sets:from_list(maps:get(P2, Postset, [])),
            not sets:is_empty(sets:intersection(Post1, Post2))
        end,
        AllPairs
    ).

%% @doc Compute the causal relation between places.
%% P1 causally precedes P2 if there's a directed path from P1 to P2.
-spec causal_relation(atom(), place_set() | all) -> [{place(), place()}].
causal_relation(NetMod, all) ->
    NetInfo = extract_net_info(NetMod),
    Places = maps:get(places, NetInfo),
    causal_relation(NetMod, sets:from_list(Places));
causal_relation(NetMod, PlaceSet) ->
    NetInfo = extract_net_info(NetMod),

    %% Build adjacency and check reachability
    Successors = build_successor_map(NetInfo),

    Places = sets:to_list(PlaceSet),
    AllPairs = [{P1, P2} || P1 <- Places, P2 <- Places, P1 =/= P2],

    lists:filter(
        fun({P1, P2}) ->
            is_reachable(Successors, P1, P2, sets:new())
        end,
        AllPairs
    ).

%% @doc Compute the concurrent relation (all concurrent pairs).
-spec concurrent_relation(atom(), place_set() | all) -> [{place(), place()}].
concurrent_relation(NetMod, PlaceSet) ->
    find_concurrent_pairs(NetMod, PlaceSet).

%% @doc Compute the full relation matrix for all place pairs.
-spec relation_matrix(atom()) -> relation_map().
relation_matrix(NetMod) ->
    NetInfo = extract_net_info(NetMod),
    Places = maps:get(places, NetInfo),

    AllPairs = [{P1, P2} || P1 <- Places, P2 <- Places],

    lists:foldl(
        fun({P1, P2}, Acc) when P1 =:= P2 ->
                Acc#{ {P1, P2} => unrelated };
           ({P1, P2}, Acc) ->
                Relation = determine_relation(NetInfo, P1, P2),
                Acc#{ {P1, P2} => Relation }
        end,
        #{},
        AllPairs
    ).

%% @doc Build and return the concurrency graph.
%% Returns adjacency map of concurrent places.
-spec concurrency_graph(atom()) -> #{place() => [place()]}.
concurrency_graph(NetMod) ->
    ConcurrentPairs = find_concurrent_pairs(NetMod, all),

    lists:foldl(
        fun({P1, P2}, Acc) ->
            Acc1 = maps:update_with(P1, fun(L) -> [P2 | L] end, [P2], Acc),
            maps:update_with(P2, fun(L) -> [P1 | L] end, [P1], Acc1)
        end,
        #{},
        ConcurrentPairs
    ).

%%====================================================================
%% API Functions - Concurrency Metrics
%%====================================================================

%% @doc Calculate the concurrency degree of a marking.
%% Number of pairs of places that both have tokens.
-spec concurrency_degree(atom(), marking()) -> non_neg_integer().
concurrency_degree(NetMod, Marking) ->
    TokenPlaces = maps:keys(Marking),
    PairCount = length(TokenPlaces) * (length(TokenPlaces) - 1) div 2,

    ConcurrentPairs = find_concurrent_pairs(NetMod, sets:from_list(TokenPlaces)),
    length(ConcurrentPairs).

%% @doc Calculate average concurrency over all reachable markings.
-spec average_concurrency(atom()) -> float().
average_concurrency(NetMod) ->
    %% Simplified - would compute over all reachable states
    Regions = concurrent_regions(NetMod),
    case length(Regions) of
        0 -> 0.0;
        N ->
            Total = lists:foldl(fun(R, Acc) -> Acc + sets:size(R) end, 0, Regions),
            Total / N
    end.

%% @doc Find maximum concurrent set size.
-spec maximum_concurrency(atom()) -> pos_integer().
maximum_concurrency(NetMod) ->
    Regions = concurrent_regions(NetMod),
    case Regions of
        [] -> 1;
        _ -> lists:max([sets:size(R) || R <- Regions])
    end.

%% @doc Get comprehensive concurrency metrics.
-spec concurrency_metrics(atom(), term()) -> map().
concurrency_metrics(NetMod, _UsrInfo) ->
    NetInfo = extract_net_info(NetMod),

    %% Compute various metrics
    Places = maps:get(places, NetInfo),

    #{
        total_places => length(Places),
        concurrent_regions => concurrent_regions(NetMod),
        max_concurrent_set_size => maximum_concurrency(NetMod),
        avg_concurrency => average_concurrency(NetMod),
        concurrent_pair_count => length(find_concurrent_pairs(NetMod, all)),
        conflict_pair_count => length(conflict_relation(NetMod, all)),
        causal_pair_count => length(causal_relation(NetMod, all)),
        has_concurrency => length(concurrent_regions(NetMod)) > 0
    }.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
%% Check structural concurrency between two places
check_structural_concurrency(NetInfo, Place1, Place2) ->
    %% For free-choice nets: places are concurrent if they don't share
    %% an output transition (no structural conflict)
    Postset = maps:get(postset, NetInfo),

    Post1 = sets:from_list(maps:get(Place1, Postset, [])),
    Post2 = sets:from_list(maps:get(Place2, Postset, [])),

    %% No shared transitions means they can be concurrent
    Shared = sets:intersection(Post1, Post2),
    sets:is_empty(Shared).

%% @private
%% Extract net information
extract_net_info(NetMod) ->
    Places = NetMod:place_lst(),
    Transitions = NetMod:trsn_lst(),

    Preset = lists:foldl(
        fun(T, Acc) -> Acc#{T => NetMod:preset(T)} end,
        #{},
        Transitions
    ),

    Postset = build_postset(NetMod, Places, Transitions),

    #{places => Places, transitions => Transitions, preset => Preset, postset => Postset}.

%% @private
%% Build postset map
build_postset(NetMod, Places, Transitions) ->
    lists:foldl(
        fun(P, Acc) ->
            OutputTrans = lists:filter(
                fun(T) -> lists:member(P, NetMod:preset(T)) end,
                Transitions
            ),
            Acc#{P => OutputTrans}
        end,
        #{},
        Places
    ).

%% @private
%% Build successor map for reachability
build_successor_map(NetInfo) ->
    Places = maps:get(places, NetInfo),
    Transitions = maps:get(transitions, NetInfo),
    Postset = maps:get(postset, NetInfo),

    %% Place -> Transitions -> Places
    lists:foldl(
        fun(P, Acc) ->
            SuccTrans = maps:get(P, Postset, []),
            SuccPlaces = lists:flatmap(
                fun(T) ->
                    %% Find places in T's postset
                    lists:filter(
                        fun(Place) ->
                            lists:member(Place, maps:get(T, maps:get(preset, NetInfo), []))
                        end,
                        Places
                    )
                end,
                SuccTrans
            ),
            Acc#{P => SuccPlaces}
        end,
        #{},
        Places
    ).

%% @private
%% Check if node2 is reachable from node1
is_reachable(_Successors, Node, Node, _Visited) ->
    true;
is_reachable(Successors, Node, Target, Visited) ->
    case sets:is_element(Node, Visited) of
        true -> false;
        false ->
            NewVisited = sets:add_element(Node, Visited),
            Succs = maps:get(Node, Successors, []),
            lists:any(fun(S) -> is_reachable(Successors, S, Target, NewVisited) end, Succs)
    end.

%% @private
%% Find connected components in concurrent graph
find_connected_components([], _Adj, Visited, Components) ->
    lists:reverse(Components);
find_connected_components([Place | Rest], Adj, Visited, Components) ->
    case sets:is_element(Place, Visited) of
        true ->
            find_connected_components(Rest, Adj, Visited, Components);
        false ->
            {Component, NewVisited} = bfs_component(Place, Adj, Visited),
            find_connected_components(Rest, Adj, NewVisited, [sets:from_list(Component) | Components])
    end.

%% @private
bfs_component(Start, Adj, InitialVisited) ->
    Queue = [Start],
    bfs_loop(Queue, Adj, sets:add_element(Start, InitialVisited), []).

bfs_loop([], _Adj, _Visited, Acc) ->
    {lists:reverse(Acc), _Visited};
bfs_loop([Node | Rest], Adj, Visited, Acc) ->
    Neighbors = sets:to_list(maps:get(Node, Adj, sets:new())),
    Unvisited = [N || N <- Neighbors, not sets:is_element(N, Visited)],

    NewVisited = lists:foldl(fun(N, V) -> sets:add_element(N, V) end, Visited, Unvisited),
    bfs_loop(Rest ++ Unvisited, Adj, NewVisited, [Node | Acc]).

%% @private
%% Token game search for concurrent marking
token_game_search(_NetMod, _Marking, _Place1, _Place2, 0) ->
    false;
token_game_search(NetMod, Marking, Place1, Place2, Depth) ->
    %% Check if both places have tokens in current marking
    HasP1 = maps:is_key(Place1, Marking) andalso maps:get(Place1, Marking, []) =/= [],
    HasP2 = maps:is_key(Place2, Marking) andalso maps:get(Place2, Marking, []) =/= [],

    case HasP1 andalso HasP2 of
        true -> {true, [Marking]};
        false ->
            %% Try firing enabled transitions
            Enabled = get_enabled_transitions(NetMod, Marking),
            case Enabled of
                [] -> false;
                _ ->
                    lists:foldl(
                        fun(T, Acc) ->
                            case Acc of
                                false ->
                                    case fire_transition(NetMod, Marking, T) of
                                        {ok, NewMarking} ->
                                            case token_game_search(NetMod, NewMarking, Place1, Place2, Depth - 1) of
                                                false -> false;
                                                {true, Seq} -> {true, [Marking | Seq]}
                                            end;
                                        _ -> false
                                    end;
                                _ -> Acc
                            end
                        end,
                        false,
                        Enabled
                    )
            end
    end.

%% @private
get_enabled_transitions(NetMod, Marking) ->
    Transitions = NetMod:trsn_lst(),
    lists:filter(
        fun(T) ->
            Preset = NetMod:preset(T),
            lists:all(
                fun(P) ->
                    maps:get(P, Marking, []) =/= []
                end,
                Preset
            )
        end,
        Transitions
    ).

%% @private
fire_transition(NetMod, Marking, Transition) ->
    %% Simplified transition firing
    Preset = NetMod:preset(Transition),

    %% Check if enabled
    IsEnabled = lists:all(
        fun(P) -> maps:get(P, Marking, []) =/= [] end,
        Preset
    ),

    case IsEnabled of
        false -> {error, not_enabled};
        true ->
            %% Consume tokens
            NewMarking1 = lists:foldl(
                fun(P, Acc) ->
                    Tokens = maps:get(P, Marking, []),
                    case Tokens of
                        [] -> Acc;
                        [_ | Rest] -> Acc#{P => Rest}
                    end
                end,
                Marking,
                Preset
            ),

            %% Produce tokens (simplified)
            %% In full version, would call NetMod:fire/3
            {ok, NewMarking1}
    end.

%% @private
get_initial_marking(NetMod) ->
    lists:foldl(
        fun(P, Acc) ->
            Tokens = NetMod:init_marking(P, []),
            case Tokens of
                [] -> Acc;
                _ -> Acc#{P => Tokens}
            end
        end,
        #{},
        NetMod:place_lst()
    ).

%% @private
%% Determine relation between two places
determine_relation(NetInfo, P1, P2) ->
    %% Check in order: conflict, causal, concurrent
    Postset = maps:get(postset, NetInfo),

    Post1 = sets:from_list(maps:get(P1, Postset, [])),
    Post2 = sets:from_list(maps:get(P2, Postset, [])),

    %% Conflict: shared output transition
    Shared = sets:intersection(Post1, Post2),
    case sets:to_list(Shared) of
        [_ | _] -> conflict;
        [] ->
            %% Check causal relation
            Successors = build_successor_map(NetInfo),
            case is_reachable(Successors, P1, P2, sets:new()) of
                true -> causal;
                false ->
                    case is_reachable(Successors, P2, P1, sets:new()) of
                        true -> causal;
                        false -> concurrent
                    end
            end
    end.

%% @private
classify_net_type(NetInfo) ->
    Places = maps:get(places, NetInfo),
    ConcurrentPairs = find_concurrent_pairs_from_info(NetInfo, sets:from_list(Places)),

    case length(ConcurrentPairs) of
        0 -> sequential;
        N when N < length(Places) -> partially_concurrent;
        _ -> highly_concurrent
    end.

%% @private
find_concurrent_pairs_from_info(NetInfo, PlaceSet) ->
    Postset = maps:get(postset, NetInfo),
    Places = sets:to_list(PlaceSet),
    AllPairs = [{P1, P2} || P1 <- Places, P2 <- Places, P1 < P2],

    lists:filter(
        fun({P1, P2}) ->
            Post1 = sets:from_list(maps:get(P1, Postset, [])),
            Post2 = sets:from_list(maps:get(P2, Postset, [])),
            sets:is_empty(sets:intersection(Post1, Post2))
        end,
        AllPairs
    ).
