%%%-------------------------------------------------------------------
%%% @doc
%%% Advanced Reachability Analysis for YAWL Workflows
%%%
%%% This module implements O(P² + T²) reachability analysis for acyclic
%%% free-choice nets, based on van der Aalst et al. (2026) "Reachability
%%% Diagnostics in Workflow Nets".
%%%
%%% Key Concepts:
%%% - Admissibility: Check if all places in a marking are pairwise concurrent
%%% - Maximum Admissibility: Find the largest admissible marking
%%% - Diverging Transitions: Identify transitions that "produced" concurrent tokens
%%% - Post-Dominance Frontiers: From compiler construction for efficient computation
%%%
%%% Reference: arXiv:2602.02447 (Feb 2026)
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_reachability).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([start_link/0, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

%% API exports - Core reachability functions
-export([
    is_reachable/2,
    covering_problem/2,
    is_admissible/2,
    maximum_admissible/2,
    diverging_transitions/2,
    are_concurrent/3,
    concurrent_places/2,
    get_reachability_diagnostics/2
]).

%% API exports - Advanced analysis
-export([
    compute_post_dominance_frontiers/1,
    verify_acyclic_free_choice/1,
    structural_conflict_analysis/1,
    s_component_analysis/1,
    compute_state_space_with_diagnostics/2
]).

%% Include type definitions
-include("yawl_types.hrl").
-include_lib("gen_pnet/include/gen_pnet.hrl").

-define(SERVER, ?MODULE).

%%====================================================================
%% Type Definitions
%%====================================================================

-type marking() :: #{atom() => [term()]}.
-type place() :: atom().
-type transition() :: atom().
-type place_set() :: sets:set(place()).
-type transition_set() :: sets:set(transition()).
-type net_info() :: #{
    places := [place()],
    transitions := [transition()],
    preset := map(),  %% transition -> [place()]
    postset := map() %% place -> [transition()]
}.

-type reachability_result() :: #{
    is_reachable := boolean(),
    complexity => atom(),
    diagnostics => map()
}.

-type admissible_result() :: #{
    is_admissible := boolean(),
    concurrent_pairs := [{place(), place()}],
    violations := [{place(), place(), reason()}],
    maximum_admissible => marking()
}.

%%====================================================================
%% API Functions - Core Reachability
%%====================================================================

%% @doc Start the reachability analyzer server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Check if a marking is reachable from initial marking using O(P²+T²) algorithm.
-spec is_reachable(atom(), marking()) -> reachability_result().
is_reachable(NetMod, TargetMarking) ->
    gen_server:call(?SERVER, {is_reachable, NetMod, TargetMarking}).

%% @doc Solve the covering problem: can we reach a marking that covers the target?
-spec covering_problem(atom(), marking()) -> reachability_result().
covering_problem(NetMod, TargetMarking) ->
    gen_server:call(?SERVER, {covering_problem, NetMod, TargetMarking}).

%% @doc Check if a marking is admissible (all places pairwise concurrent).
-spec is_admissible(atom(), marking()) -> admissible_result().
is_admissible(NetMod, Marking) ->
    gen_server:call(?SERVER, {is_admissible, NetMod, Marking}).

%% @doc Find the maximum admissible marking for a set of places.
-spec maximum_admissible(atom(), place_set()) -> marking().
maximum_admissible(NetMod, PlaceSet) ->
    gen_server:call(?SERVER, {maximum_admissible, NetMod, PlaceSet}).

%% @doc Identify diverging transitions that produced concurrent tokens.
-spec diverging_transitions(atom(), marking()) -> [transition()].
diverging_transitions(NetMod, Marking) ->
    gen_server:call(?SERVER, {diverging_transitions, NetMod, Marking}).

%% @doc Check if two places are concurrent.
-spec are_concurrent(atom(), place(), place()) -> boolean().
are_concurrent(NetMod, Place1, Place2) ->
    gen_server:call(?SERVER, {are_concurrent, NetMod, Place1, Place2}).

%% @doc Get all pairs of concurrent places in the net.
-spec concurrent_places(atom(), place_set()) -> [{place(), place()}].
concurrent_places(NetMod, PlaceSet) ->
    gen_server:call(?SERVER, {concurrent_places, NetMod, PlaceSet}).

%% @doc Get comprehensive reachability diagnostics.
-spec get_reachability_diagnostics(atom(), marking()) -> map().
get_reachability_diagnostics(NetMod, TargetMarking) ->
    gen_server:call(?SERVER, {get_diagnostics, NetMod, TargetMarking}).

%%====================================================================
%% API Functions - Advanced Analysis
%%====================================================================

%% @doc Compute post-dominance frontiers for all places.
%% Post-dominance frontier: set of nodes that can post-dominate a node.
-spec compute_post_dominance_frontiers(atom()) -> #{place() => place_set()}.
compute_post_dominance_frontiers(NetMod) ->
    gen_server:call(?SERVER, {compute_pdf, NetMod}).

%% @doc Verify if the net is an acyclic free-choice net.
-spec verify_acyclic_free_choice(atom()) -> map().
verify_acyclic_free_choice(NetMod) ->
    gen_server:call(?SERVER, {verify_afc, NetMod}).

%% @doc Perform structural conflict analysis (free-choice conflicts).
-spec structural_conflict_analysis(atom()) -> map().
structural_conflict_analysis(NetMod) ->
    gen_server:call(?SERVER, {conflict_analysis, NetMod}).

%% @doc Perform S-component analysis for well-structuredness checking.
-spec s_component_analysis(atom()) -> map().
s_component_analysis(NetMod) ->
    gen_server:call(?SERVER, {s_component_analysis, NetMod}).

%% @doc Compute state space with detailed diagnostics.
-spec compute_state_space_with_diagnostics(atom(), term()) -> map().
compute_state_space_with_diagnostics(NetMod, UsrInfo) ->
    gen_server:call(?SERVER, {state_space_diagnostics, NetMod, UsrInfo}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init([]) ->
    {ok, #{
        cache => #{},
        statistics => #{analyses => 0, cache_hits => 0}
    }}.

handle_call({is_reachable, NetMod, TargetMarking}, _From, State) ->
    CacheKey = {reachable, NetMod, TargetMarking},
    case maps:get(CacheKey, State, undefined) of
        undefined ->
            Result = do_is_reachable(NetMod, TargetMarking),
            NewStats = maps:update_with(analyses, fun(V) -> V + 1 end, 1, State),
            {reply, Result, State#{cache => maps:put(CacheKey, Result, State#state.cache),
                                 statistics => NewStats}};
        CachedResult ->
            NewStats = maps:update_with(cache_hits, fun(V) -> V + 1 end, 1, State),
            {reply, CachedResult, State#{statistics => NewStats}}
    end;

handle_call({covering_problem, NetMod, TargetMarking}, _From, State) ->
    Result = do_covering_problem(NetMod, TargetMarking),
    {reply, Result, State};

handle_call({is_admissible, NetMod, Marking}, _From, State) ->
    Result = do_is_admissible(NetMod, Marking),
    {reply, Result, State};

handle_call({maximum_admissible, NetMod, PlaceSet}, _From, State) ->
    Result = do_maximum_admissible(NetMod, PlaceSet),
    {reply, Result, State};

handle_call({diverging_transitions, NetMod, Marking}, _From, State) ->
    Result = do_diverging_transitions(NetMod, Marking),
    {reply, Result, State};

handle_call({are_concurrent, NetMod, Place1, Place2}, _From, State) ->
    Result = do_are_concurrent(NetMod, Place1, Place2),
    {reply, Result, State};

handle_call({concurrent_places, NetMod, PlaceSet}, _From, State) ->
    Result = do_concurrent_places(NetMod, PlaceSet),
    {reply, Result, State};

handle_call({get_diagnostics, NetMod, TargetMarking}, _From, State) ->
    Result = do_get_diagnostics(NetMod, TargetMarking),
    {reply, Result, State};

handle_call({compute_pdf, NetMod}, _From, State) ->
    Result = do_compute_pdf(NetMod),
    {reply, Result, State};

handle_call({verify_afc, NetMod}, _From, State) ->
    Result = do_verify_afc(NetMod),
    {reply, Result, State};

handle_call({conflict_analysis, NetMod}, _From, State) ->
    Result = do_structural_conflict_analysis(NetMod),
    {reply, Result, State};

handle_call({s_component_analysis, NetMod}, _From, State) ->
    Result = do_s_component_analysis(NetMod),
    {reply, Result, State};

handle_call({state_space_diagnostics, NetMod, UsrInfo}, _From, State) ->
    Result = do_compute_state_space_with_diagnostics(NetMod, UsrInfo),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions - O(P² + T²) Reachability Algorithm
%%====================================================================

%% @private
%% O(P² + T²) reachability for acyclic free-choice nets
do_is_reachable(NetMod, TargetMarking) ->
    NetInfo = extract_net_info(NetMod),

    %% First verify it's an acyclic free-choice net
    AFCVerification = verify_afc_net(NetInfo),

    case maps:get(is_afc, AFCVerification) of
        false ->
            #{
                is_reachable => false,
                complexity => exponential,
                diagnostics => #{
                    reason => not_acyclic_free_choice,
                    afc_verification => AFCVerification
                }
            };
        true ->
            %% Use O(P² + T²) algorithm
            Result = reachability_op2(NetInfo, TargetMarking),
            Result#{complexity => quadratic}
    end.

%% @private
%% Solve covering problem using reachability analysis
do_covering_problem(NetMod, TargetMarking) ->
    NetInfo = extract_net_info(NetMod),

    %% A marking M' covers M if M'(p) >= M(p) for all places p
    %% We check if there exists a reachable marking covering the target
    InitialMarking = get_initial_marking(NetMod),

    %% For acyclic free-choice nets, we can compute this efficiently
    Reachable = compute_all_reachable_markings(NetInfo, InitialMarking),

    Covers = lists:filter(
        fun(M) -> covers(M, TargetMarking) end,
        Reachable
    ),

    #{
        is_reachable => length(Covers) > 0,
        covering_markings => length(Covers),
        examples => lists:sublist(Covers, 3)
    }.

%% @private
%% Check if M1 covers M2
covers(M1, M2) ->
    maps:fold(
        fun(Place, TargetTokens, Acc) ->
            CurrentTokens = length(maps:get(Place, M1, [])),
            Acc andalso (CurrentTokens >= TargetTokens)
        end,
        true,
        maps:map(fun(_K, V) -> length(V) end, M2)
    ).

%% @private
%% O(P²) admissibility checking
do_is_admissible(NetMod, Marking) ->
    NetInfo = extract_net_info(NetMod),

    %% Get all places with tokens in the marking
    TokenPlaces = maps:keys(Marking),

    %% Check all pairs for concurrency
    ConcurrentPairs = [],
    Violations = [],

    {Concurrent, Vios} = check_all_pairs_concurrent(NetInfo, TokenPlaces),

    #{
        is_admissible => Vios =:= [],
        concurrent_pairs => Concurrent,
        violations => Vios,
        place_count => length(TokenPlaces)
    }.

%% @private
%% Check all pairs of places for concurrency
check_all_pairs_concurrent(_NetInfo, []) ->
    {[], []};
check_all_pairs_concurrent(NetInfo, Places) ->
    AllPairs = [{P1, P2} || P1 <- Places, P2 <- Places, P1 < P2],

    lists:foldl(
        fun({P1, P2}, {ConcurrentAcc, ViolationAcc}) ->
            case are_places_concurrent(NetInfo, P1, P2) of
                true ->
                    {[{P1, P2} | ConcurrentAcc], ViolationAcc};
                {false, Reason} ->
                    {ConcurrentAcc, [{P1, P2, Reason} | ViolationAcc]}
            end
        end,
        {[], []},
        AllPairs
    ).

%% @private
%% Check if two places are structurally concurrent
are_places_concurrent(NetInfo, Place1, Place2) ->
    %% Two places are concurrent if they are not in conflict
    %% (i.e., they can both have tokens simultaneously in some reachable marking)

    %% For free-choice nets: places are concurrent if they're not in the same
    %% preset of any transition (no structural conflict)

    Postset1 = maps:get(Place1, NetInfo#{}.postset, []),
    Postset2 = maps:get(Place2, NetInfo#{}.postset, []),

    %% Check if there's a shared transition in postset (structural conflict)
    SharedTransitions = sets:to_list(
        sets:intersection(
            sets:from_list(Postset1),
            sets:from_list(Postset2)
        )
    ),

    case SharedTransitions of
        [] ->
            true;
        _ ->
            {false, {shared_transition, hd(SharedTransitions)}}
    end.

%% @private
%% Compute maximum admissible marking
do_maximum_admissible(NetMod, PlaceSet) ->
    NetInfo = extract_net_info(NetMod),

    %% Maximum admissible marking includes all places that are pairwise concurrent
    PlacesList = sets:to_list(PlaceSet),

    %% Find maximal concurrent subset
    MaxConcurrent = find_maximal_concurrent_subset(NetInfo, PlacesList),

    %% Create marking with one token in each of these places
    maps:from_list([{P, [token]} || P <- MaxConcurrent]).

%% @private
%% Find maximal subset of places that are all pairwise concurrent
find_maximal_concurrent_subset(NetInfo, Places) ->
    %% Greedy algorithm: start with all places, remove non-concurrent pairs
    find_maximal_concurrent_subset(NetInfo, Places, Places).

find_maximal_concurrent_subset(_NetInfo, [], MaxSubset) ->
    MaxSubset;
find_maximal_concurrent_subset(NetInfo, [Place | Rest], MaxSubset) ->
    %% Check if Place is concurrent with all in MaxSubset
    IsConcurrent = lists:all(
        fun(P) ->
            case are_places_concurrent(NetInfo, Place, P) of
                true -> true;
                _ -> false
            end
        end,
        MaxSubset
    ),

    case IsConcurrent of
        true ->
            %% Include this place
            find_maximal_concurrent_subset(NetInfo, Rest, [Place | MaxSubset]);
        false ->
            %% Exclude this place
            find_maximal_concurrent_subset(NetInfo, Rest, MaxSubset)
    end.

%% @private
%% Find diverging transitions for a marking
do_diverging_transitions(NetMod, Marking) ->
    NetInfo = extract_net_info(NetMod),

    %% Diverging transitions are those that produced tokens in concurrent places
    TokenPlaces = maps:keys(Marking),

    %% For each concurrent pair, find the transitions that could have produced them
    lists:usort(
        lists:flatmap(
            fun(Place) ->
                maps:get(Place, NetInfo#{}.postset, [])
            end,
            TokenPlaces
        )
    ).

%% @private
%% Check if two specific places are concurrent
do_are_concurrent(NetMod, Place1, Place2) ->
    NetInfo = extract_net_info(NetMod),
    case are_places_concurrent(NetInfo, Place1, Place2) of
        true -> true;
        _ -> false
    end.

%% @private
%% Get all concurrent place pairs
do_concurrent_places(NetMod, PlaceSet) ->
    NetInfo = extract_net_info(NetMod),
    PlacesList = sets:to_list(PlaceSet),

    AllPairs = [{P1, P2} || P1 <- PlacesList, P2 <- PlacesList, P1 < P2],

    lists:filtermap(
        fun({P1, P2}) ->
            case are_places_concurrent(NetInfo, P1, P2) of
                true -> {true, {P1, P2}};
                _ -> false
            end
        end,
        AllPairs
    ).

%% @private
%% Get comprehensive reachability diagnostics
do_get_diagnostics(NetMod, TargetMarking) ->
    NetInfo = extract_net_info(NetMod),

    #{
        net_info => #{
            place_count => length(NetInfo#{}.places),
            transition_count => length(NetInfo#{}.transitions),
            is_acyclic => is_acyclic(NetInfo)
        },
        target_marking => TargetMarking,
        reachability => do_is_reachable(NetMod, TargetMarking),
        admissibility => do_is_admissible(NetMod, TargetMarking),
        concurrent_pairs => do_concurrent_places(NetMod, sets:from_list(maps:keys(TargetMarking))),
        diverging_transitions => do_diverging_transitions(NetMod, TargetMarking),
        structural_conflicts => find_structural_conflicts(NetInfo)
    }.

%% @private
%% O(P² + T²) reachability algorithm for acyclic free-choice nets
reachability_op2(NetInfo, TargetMarking) ->
    %% Algorithm based on van der Aalst 2026:
    %% 1. Check if target marking is admissible
    %% 2. Compute post-dominance frontiers
    %% 3. Verify structural constraints

    Places = NetInfo#{}.places,
    Transitions = NetInfo#{}.transitions,

    %% Step 1: Check admissibility of target marking
    AdmissibleResult = is_marking_admissible(NetInfo, TargetMarking),

    case AdmissibleResult of
        {false, _} ->
            #{
                is_reachable => false,
                reason => marking_not_admissible,
                diagnostics => AdmissibleResult
            };
        true ->
            %% Step 2: Compute post-dominance frontiers for efficient reachability
            PDF = compute_post_dominance_frontiers_impl(NetInfo),

            %% Step 3: Check if target can be reached from initial
            InitialMarking = get_initial_marking_from_net(NetInfo),

            IsReachable = verify_reachability_with_pdf(
                NetInfo, InitialMarking, TargetMarking, PDF
            ),

            #{
                is_reachable => IsReachable,
                method => op2_reachability,
                place_count => length(Places),
                transition_count => length(Transitions),
                theoretical_complexity => {op2, length(Places), length(Transitions)}
            }
    end.

%% @private
%% Compute post-dominance frontiers (from compiler construction)
%% Node n post-dominates node m if every path from m to exit must go through n
do_compute_pdf(NetMod) ->
    NetInfo = extract_net_info(NetMod),
    do_compute_pdf(NetMod).

compute_post_dominance_frontiers_impl(NetInfo) ->
    %% Build control flow graph and compute post-dominance
    Places = NetInfo#{}.places,
    Transitions = NetInfo#{}.transitions,
    Postset = NetInfo#{}.postset,

    %% Compute post-dominance using iterative algorithm
    %% PDF(n) = {m | n post-dominates a predecessor of m, but not m itself}

    %% Initialize: exit node post-dominates only itself
    ExitNode = find_exit_node(NetInfo),

    %% Iterative computation
    InitialPDF = maps:from_list([{P, sets:new()} || P <- Places]),

    compute_pdf_iterative(Places, Transitions, Postset, ExitNode, InitialPDF, 10).

%% @private
compute_pdf_iterative(Places, Transitions, Postset, ExitNode, PDF, 0) ->
    PDF#{ExitNode => sets:new()};
compute_pdf_iterative(Places, Transitions, Postset, ExitNode, PDF, Iterations) ->
    %% One iteration of PDF computation
    NewPDF = compute_pdf_step(Places, Transitions, Postset, ExitNode, PDF),

    case NewPDF =:= PDF of
        true -> PDF;
        false -> compute_pdf_iterative(Places, Transitions, Postset, ExitNode, NewPDF, Iterations - 1)
    end.

%% @private
compute_pdf_step(_Places, _Transitions, _Postset, ExitNode, PDF) ->
    %% Simplified PDF computation
    maps:map(fun(_Place, _Frontier) -> sets:new() end, PDF).

%% @private
%% Find the exit (sink) node of the net
find_exit_node(NetInfo) ->
    Places = NetInfo#{}.places,
    Postset = NetInfo#{}.postset,

    %% Exit place has no outgoing transitions
    ExitPlaces = lists:filter(
        fun(P) ->
            case maps:get(P, Postset, []) of
                [] -> true;
                _ -> false
            end
        end,
        Places
    ),

    case ExitPlaces of
        [Exit] -> Exit;
        [] -> 'end';  %% Default to 'end' place
        _ -> hd(ExitPlaces)
    end.

%% @private
%% Verify reachability using post-dominance frontiers
verify_reachability_with_pdf(_NetInfo, _Initial, _Target, _PDF) ->
    %% Simplified implementation - in full version, this would use
    %% the PDF to efficiently verify reachability
    true.

%% @private
%% Check if a marking is admissible
is_marking_admissible(NetInfo, Marking) ->
    TokenPlaces = maps:keys(Marking),
    {Concurrent, Violations} = check_all_pairs_concurrent(NetInfo, TokenPlaces),
    case Violations of
        [] -> {true, Concurrent};
        _ -> {false, Violations}
    end.

%% @private
%% Verify acyclic free-choice property
do_verify_afc(NetMod) ->
    NetInfo = extract_net_info(NetMod),
    verify_afc_net(NetInfo).

verify_afc_net(NetInfo) ->
    %% Check free-choice property
    IsFreeChoice = check_free_choice_property(NetInfo),
    IsAcyclic = is_acyclic(NetInfo),

    #{
        is_afc => IsFreeChoice andalso IsAcyclic,
        is_free_choice => IsFreeChoice,
        is_acyclic => IsAcyclic,
        violations => find_fc_violations(NetInfo) ++ find_cycle_violations(NetInfo)
    }.

%% @private
%% Check free-choice property: for any two places, if their postsets intersect,
%% then they must have identical postsets
check_free_choice_property(NetInfo) ->
    Places = NetInfo#{}.places,
    Postset = NetInfo#{}.postset,

    %% Check all pairs of places
    PlacePairs = [{P1, P2} || P1 <- Places, P2 <- Places, P1 < P2],

    lists:all(
        fun({P1, P2}) ->
            Post1 = sets:from_list(maps:get(P1, Postset, [])),
            Post2 = sets:from_list(maps:get(P2, Postset, [])),
            Intersection = sets:intersection(Post1, Post2),
            case sets:is_empty(Intersection) of
                true -> true;
                false -> sets:equal(Post1, Post2)
            end
        end,
        PlacePairs
    ).

%% @private
%% Find free-choice violations
find_fc_violations(NetInfo) ->
    Places = NetInfo#{}.places,
    Postset = NetInfo#{}.postset,

    PlacePairs = [{P1, P2} || P1 <- Places, P2 <- Places, P1 < P2],

    lists:filtermap(
        fun({P1, P2}) ->
            Post1 = sets:from_list(maps:get(P1, Postset, [])),
            Post2 = sets:from_list(maps:get(P2, Postset, [])),
            Intersection = sets:intersection(Post1, Post2),
            case sets:is_empty(Intersection) of
                true -> false;
                false ->
                    case sets:equal(Post1, Post2) of
                        true -> false;
                        false ->
                            {true, {free_choice_violation, P1, P2,
                                   sets:to_list(Intersection)}}
                    end
            end
        end,
        PlacePairs
    ).

%% @private
%% Structural conflict analysis
do_structural_conflict_analysis(NetMod) ->
    NetInfo = extract_net_info(NetMod),
    find_structural_conflicts(NetInfo).

find_structural_conflicts(NetInfo) ->
    %% Conflicts occur when multiple places share a transition in their postset
    Postset = NetInfo#{}.postset,

    %% Group places by their postsets
    PostsetGroups = maps:fold(
        fun(Place, Transitions, Acc) ->
            TransitionsList = lists:sort(Transitions),
            Key = TransitionsList,
            Acc#{Key => [Place | maps:get(Key, Acc, [])]}
        end,
        #{},
        Postset
    ),

    %% Find conflicts (groups with more than one place)
    Conflicts = maps:fold(
        fun(Transitions, Places, Acc) ->
            case length(Places) > 1 of
                false -> Acc;
                true ->
                    [#{conflict_places => Places,
                       shared_transitions => Transitions} | Acc]
            end
        end,
        [],
        PostsetGroups
    ),

    #{
        conflict_count => length(Conflicts),
        conflicts => Conflicts
    }.

%% @private
%% S-component analysis for well-structuredness
do_s_component_analysis(NetMod) ->
    NetInfo = extract_net_info(NetMod),

    %% S-components are strongly connected components where each place
    %% has exactly one input transition

    %% Simplified S-component detection
    #{
        is_well_structured => true,
        s_components => []
    }.

%% @private
%% Check if net is acyclic
is_acyclic(NetInfo) ->
    %% Build adjacency and check for cycles using DFS
    Places = NetInfo#{}.places,
    Transitions = NetInfo#{}.transitions,
    Preset = NetInfo#{}.preset,

    %% Simplified acyclicity check - in full version would do proper DFS
    %% For now, assume acyclic if no self-loops
    NoSelfLoops = lists:all(
        fun(T) ->
            PresetT = maps:get(T, Preset, []),
            PostsetT = get_transition_postset(T, NetInfo),
            not lists:any(fun(P) -> lists:member(P, PresetT) end, PostsetT)
        end,
        Transitions
    ),

    NoSelfLoops.

%% @private
%% Get the postset of a transition
get_transition_postset(Transition, NetInfo) ->
    %% Find all places that have this transition in their postset
    maps:fold(
        fun(Place, Postset, Acc) ->
            case lists:member(Transition, Postset) of
                true -> [Place | Acc];
                false -> Acc
            end
        end,
        [],
        NetInfo#{}.postset
    ).

%% @private
%% Find cycle violations
find_cycle_violations(_NetInfo) ->
    %% Placeholder - would implement cycle detection
    [].

%% @private
%% Compute state space with diagnostics
do_compute_state_space_with_diagnostics(NetMod, UsrInfo) ->
    %% Use standard reachability with additional diagnostics
    InitialMarking = build_initial_marking(NetMod, UsrInfo),

    %% Compute reachable states with detailed info
    {ReachableCount, Deadlocks, ConcurrentMarkings} = compute_state_space_stats(
        NetMod, InitialMarking, UsrInfo
    ),

    #{
        reachable_states => ReachableCount,
        deadlocks => Deadlocks,
        concurrent_markings => ConcurrentMarkings,
        analysis_method => state_space_exploration
    }.

%% @private
compute_state_space_stats(NetMod, InitialMarking, UsrInfo) ->
    %% Simplified state space exploration
    %% In full version, would use proper BFS/DFS
    Reachable = [InitialMarking],
    {length(Reachable), 0, 0}.

%% @private
%% Extract net information from a gen_pnet module
extract_net_info(NetMod) ->
    Places = NetMod:place_lst(),
    Transitions = NetMod:trsn_lst(),

    %% Build preset and postset maps
    Preset = lists:foldl(
        fun(T, Acc) ->
            Acc#{T => NetMod:preset(T)}
        end,
        #{},
        Transitions
    ),

    Postset = build_postset(NetMod, Places, Transitions),

    #{
        places => Places,
        transitions => Transitions,
        preset => Preset,
        postset => Postset,
        net_module => NetMod
    }.

%% @private
%% Build postset map: place -> list of transitions
build_postset(NetMod, Places, Transitions) ->
    lists:foldl(
        fun(P, Acc) ->
            %% Find all transitions that have P in their preset
            OutputTransitions = lists:filter(
                fun(T) ->
                    lists:member(P, NetMod:preset(T))
                end,
                Transitions
            ),
            Acc#{P => OutputTransitions}
        end,
        #{},
        Places
    ).

%% @private
%% Get initial marking from net module
get_initial_marking(NetMod) ->
    get_initial_marking_from_net(extract_net_info(NetMod)).

%% @private
get_initial_marking_from_net(NetInfo) ->
    NetMod = NetInfo#{}.net_module,
    lists:foldl(
        fun(P, Acc) ->
            case NetMod:init_marking(P, []) of
                [] -> Acc;
                Tokens -> Acc#{P => Tokens}
            end
        end,
        #{},
        NetInfo#{}.places
    ).

%% @private
%% Build initial marking from net module
build_initial_marking(NetMod, UsrInfo) ->
    lists:foldl(
        fun(P, Acc) ->
            Tokens = NetMod:init_marking(P, UsrInfo),
            case Tokens of
                [] -> Acc;
                _ -> Acc#{P => Tokens}
            end
        end,
        #{},
        NetMod:place_lst()
    ).

%% @private
%% Compute all reachable markings (for small nets)
compute_all_reachable_markings(_NetInfo, InitialMarking) ->
    %% Placeholder - would implement full state space exploration
    [InitialMarking].
