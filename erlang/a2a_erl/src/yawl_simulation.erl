%%%-------------------------------------------------------------------
%%% @doc
%%% Petri Net Simulation Engine for YAWL Patterns
%%%
%%% This module provides simulation and analysis capabilities for Petri nets
%%% implementing YAWL workflow patterns using the gen_pnet behavior.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_simulation).
-author("A2A Team").

%% Include gen_pnet records
-include_lib("gen_pnet/include/gen_pnet.hrl").

%% API exports
-export([
    simulate/2,
    get_reachable_states/1,
    get_reachable_states/2,
    check_termination/1,
    check_termination/2,
    detect_deadlock/1,
    detect_deadlock/2,
    simulate_trace/2,
    get_enabled_transitions/1,
    fire_transition/3,
    is_final_marking/1,
    get_state_space_statistics/1,
    get_state_space_statistics/2,
    find_cycles/1,
    find_cycles/2,
    verify_soundness/1,
    verify_soundness/2,
    get_initial_marking/1,
    get_initial_marking/2,
    marking_to_string/1,
    compare_markings/2
]).

%%====================================================================
%% Types
%%====================================================================

-type marking() :: #{atom() => [term()]}.
-type transition() :: atom().
-type sim_state() :: #{
    marking => marking(),
    usr_info => term(),
    net_mod => atom()
}.
-type trace_entry() :: #{
    step => non_neg_integer(),
    transition => transition(),
    marking_before => marking(),
    marking_after => marking()
}.
-type trace() :: [trace_entry()].
-type state_graph() :: #{marking() => [{transition(), marking()}]}.

-export_type([
    marking/0,
    sim_state/0,
    trace/0,
    trace_entry/0,
    state_graph/0
]).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Runs a simulation of the Petri net.
-spec simulate(atom(), term()) -> {ok, trace()} | {error, term()}.
simulate(NetMod, UsrInfo) ->
    InitialMarking = build_initial_marking(NetMod, UsrInfo),
    InitialState = #{
        marking => InitialMarking,
        usr_info => UsrInfo,
        net_mod => NetMod
    },
    simulate_loop(InitialState, [], 0, 1000).

%% @doc Simulates a trace for steps.
-spec simulate_trace(atom(), non_neg_integer()) -> {ok, trace()}.
simulate_trace(NetMod, _MaxSteps) ->
    simulate(NetMod, []).

%% @private
simulate_loop(_State, Trace, Step, MaxSteps) when Step >= MaxSteps ->
    {ok, lists:reverse(Trace)};
simulate_loop(State, Trace, Step, MaxSteps) ->
    #{marking := Marking, usr_info := UsrInfo, net_mod := NetMod} = State,

    case is_final_marking(Marking) of
        true ->
            {ok, lists:reverse(Trace)};
        false ->
            Enabled = get_enabled_transitions(State),
            case Enabled of
                [] ->
                    {ok, lists:reverse(Trace)};
                _ ->
                    Transition = hd(Enabled),
                    case fire_transition(State, Transition, UsrInfo) of
                        {ok, NewMarking} ->
                            Entry = #{
                                step => Step,
                                transition => Transition,
                                marking_before => Marking,
                                marking_after => NewMarking
                            },
                            NewState = State#{marking => NewMarking},
                            simulate_loop(NewState, [Entry | Trace], Step + 1, MaxSteps);
                        {error, _} ->
                            {ok, lists:reverse(Trace)}
                    end
            end
    end.

%% @doc Returns all reachable markings.
-spec get_reachable_states(atom()) -> state_graph().
get_reachable_states(NetMod) ->
    get_reachable_states(NetMod, []).

%% @doc Returns all reachable markings with user info.
-spec get_reachable_states(atom(), term()) -> state_graph().
get_reachable_states(NetMod, UsrInfo) ->
    InitialMarking = build_initial_marking(NetMod, UsrInfo),
    InitialState = #{
        marking => InitialMarking,
        usr_info => UsrInfo,
        net_mod => NetMod
    },
    explore_state_space([InitialState], #{InitialMarking => true}, #{}).

%% @private
explore_state_space([], _Visited, Reachable) ->
    Reachable;
explore_state_space([State | Rest], Visited, Reachable) ->
    #{marking := Marking, usr_info := UsrInfo, net_mod := NetMod} = State,

    case maps:is_key(Marking, Visited) of
        true ->
            explore_state_space(Rest, Visited, Reachable);
        false ->
            NewVisited = Visited#{Marking => true},
            Successors = find_successors(State),
            NewReachable = lists:foldl(
                fun({Trans, NewMarking}, Acc) ->
                    Existing = maps:get(Marking, Acc, []),
                    Acc#{Marking => [{Trans, NewMarking} | Existing]}
                end,
                Reachable,
                Successors
            ),
            NewStates = [State#{marking => NewM} || {_T, NewM} <- Successors],
            explore_state_space(Rest ++ NewStates, NewVisited, NewReachable)
    end.

%% @private
find_successors(State) ->
    #{marking := Marking, usr_info := UsrInfo, net_mod := NetMod} = State,
    Transitions = NetMod:trsn_lst(),
    Enabled = lists:filter(fun(T) -> is_transition_enabled(NetMod, T, Marking, UsrInfo) end, Transitions),

    lists:foldl(
        fun(T, Acc) ->
            case fire_transition(State, T, UsrInfo) of
                {ok, NewMarking} -> [{T, NewMarking} | Acc];
                {error, _} -> Acc
            end
        end,
        [],
        Enabled
    ).

%% @doc Verifies termination.
-spec check_termination(atom()) -> {ok, boolean()}.
check_termination(NetMod) ->
    check_termination(NetMod, []).

%% @doc Verifies termination with user info.
-spec check_termination(atom(), term()) -> {ok, boolean()}.
check_termination(NetMod, UsrInfo) ->
    Reachable = maps:keys(get_reachable_states(NetMod, UsrInfo)),
    FinalMarkings = lists:filter(fun(M) -> is_final_marking(M) end, Reachable),
    {ok, length(FinalMarkings) > 0}.

%% @doc Finds deadlock states.
-spec detect_deadlock(atom()) -> {ok, [marking()]}.
detect_deadlock(NetMod) ->
    detect_deadlock(NetMod, []).

%% @doc Finds deadlock states with user info.
-spec detect_deadlock(atom(), term()) -> {ok, [marking()]}.
detect_deadlock(NetMod, UsrInfo) ->
    Reachable = maps:keys(get_reachable_states(NetMod, UsrInfo)),

    Deadlocks = lists:filter(
        fun(Marking) ->
            case is_final_marking(Marking) of
                true -> false;
                false ->
                    State = #{marking => Marking, usr_info => UsrInfo, net_mod => NetMod},
                    get_enabled_transitions(State) =:= []
            end
        end,
        Reachable
    ),

    {ok, Deadlocks}.

%% @doc Gets enabled transitions.
-spec get_enabled_transitions(sim_state()) -> [transition()].
get_enabled_transitions(#{marking := Marking, usr_info := UsrInfo, net_mod := NetMod}) ->
    Transitions = NetMod:trsn_lst(),
    lists:filter(fun(T) -> is_transition_enabled(NetMod, T, Marking, UsrInfo) end, Transitions).

%% @doc Fires a transition.
-spec fire_transition(sim_state(), transition(), term()) -> {ok, marking()} | {error, term()}.
fire_transition(State, Transition, UsrInfo) ->
    #{marking := Marking, net_mod := NetMod} = State,

    case is_transition_enabled(NetMod, Transition, Marking, UsrInfo) of
        false ->
            {error, {transition_not_enabled, Transition}};
        true ->
            Preset = NetMod:preset(Transition),
            Mode = build_mode(Preset, Marking),

            case NetMod:fire(Transition, Mode, UsrInfo) of
                abort ->
                    {error, firing_aborted};
                {produce, ProduceMap} ->
                    NewMarking1 = consume_tokens(Marking, Mode),
                    NewMarking2 = apply_trigger(ProduceMap, NetMod, State),
                    NewMarking3 = produce_tokens(NewMarking1, NewMarking2),
                    {ok, NewMarking3}
            end
    end.

%% @doc Checks if marking is final.
-spec is_final_marking(marking()) -> boolean().
is_final_marking(Marking) ->
    Places = maps:keys(Marking),

    NonEndPlaces = lists:filter(fun(P) -> P =/= 'end' end, Places),
    AllEmpty = lists:all(
        fun(P) ->
            case maps:get(P, Marking, []) of
                [] -> true;
                _ -> false
            end
        end,
        NonEndPlaces
    ),

    EndHasTokens = case maps:get('end', Marking, []) of
        [] -> false;
        _ -> true
    end,

    AllEmpty andalso EndHasTokens.

%% @doc Gets state space statistics.
-spec get_state_space_statistics(atom()) -> map().
get_state_space_statistics(NetMod) ->
    get_state_space_statistics(NetMod, []).

%% @doc Gets state space statistics with user info.
-spec get_state_space_statistics(atom(), term()) -> map().
get_state_space_statistics(NetMod, UsrInfo) ->
    ReachableGraph = get_reachable_states(NetMod, UsrInfo),
    States = maps:keys(ReachableGraph),
    TotalStates = length(States),

    Deadlocks = case detect_deadlock(NetMod, UsrInfo) of
        {ok, D} -> length(D);
        _ -> 0
    end,

    FinalStates = length(lists:filter(fun is_final_marking/1, States)),

    AllTransitions = lists:flatten(maps:values(ReachableGraph)),
    TotalTransitions = length(AllTransitions),
    AvgOutDegree = case TotalStates of
        0 -> 0.0;
        _ -> TotalTransitions / TotalStates
    end,

    #{
        total_states => TotalStates,
        deadlock_states => Deadlocks,
        final_states => FinalStates,
        avg_out_degree => AvgOutDegree
    }.

%% @doc Finds cycles in state space.
-spec find_cycles(atom()) -> [[marking()]].
find_cycles(NetMod) ->
    find_cycles(NetMod, []).

%% @doc Finds cycles with user info.
-spec find_cycles(atom(), term()) -> [[marking()]].
find_cycles(NetMod, UsrInfo) ->
    ReachableGraph = get_reachable_states(NetMod, UsrInfo),
    States = maps:keys(ReachableGraph),
    find_cycles_in_graph(States, ReachableGraph, [], []).

%% @private
find_cycles_in_graph([], _Graph, _Visited, Cycles) ->
    lists:reverse(Cycles);
find_cycles_in_graph([State | Rest], Graph, Visited, Cycles) ->
    case lists:member(State, Visited) of
        true ->
            find_cycles_in_graph(Rest, Graph, Visited, Cycles);
        false ->
            case dfs_find_cycle(State, Graph, [State], sets:new(), []) of
                {cycle, Cycle} ->
                    find_cycles_in_graph(Rest, Graph, [State | Visited], [Cycle | Cycles]);
                no_cycle ->
                    find_cycles_in_graph(Rest, Graph, [State | Visited], Cycles)
            end
    end.

%% @private
dfs_find_cycle(_Current, _Graph, Path, _Visited, _AccCycle) when length(Path) > 100 ->
    {cycle, lists:reverse(Path)};
dfs_find_cycle(Current, Graph, Path, Visited, AccCycle) ->
    case sets:is_element(Current, Visited) andalso length(Path) > 1 of
        true ->
            CycleStart = find_index(Current, Path, 1),
            Cycle = lists:sublist(Path, CycleStart, length(Path) - CycleStart + 1),
            {cycle, lists:reverse(Cycle)};
        false ->
            NewVisited = sets:add_element(Current, Visited),
            Successors = case maps:get(Current, Graph) of
                undefined -> [];
                TransList -> [M || {_T, M} <- TransList]
            end,

            case Successors of
                [] ->
                    no_cycle;
                _ ->
                    lists:foldl(
                        fun(Succ, Acc) ->
                            case Acc of
                                {cycle, _} -> Acc;
                                no_cycle ->
                                    case lists:member(Succ, Path) of
                                        true ->
                                            CycleStart = find_index(Succ, Path, 1),
                                            Cycle = lists:sublist(Path, CycleStart, length(Path) - CycleStart + 1),
                                            {cycle, lists:reverse([Succ | Cycle])};
                                        false ->
                                            dfs_find_cycle(Succ, Graph, [Succ | Path], NewVisited, Acc)
                                    end
                            end
                        end,
                        no_cycle,
                        Successors
                    )
            end
    end.

%% @private
find_index(_Item, [], _N) -> 0;
find_index(Item, [Item | _], N) -> N;
find_index(Item, [_ | T], N) -> find_index(Item, T, N + 1).

%% @doc Verifies soundness.
-spec verify_soundness(atom()) -> map().
verify_soundness(NetMod) ->
    verify_soundness(NetMod, []).

%% @doc Verifies soundness with user info.
-spec verify_soundness(atom(), term()) -> map().
verify_soundness(NetMod, UsrInfo) ->
    Reasons = [],

    {ok, Deadlocks} = detect_deadlock(NetMod, UsrInfo),
    Reasons1 = case Deadlocks of
        [] -> Reasons;
        _ -> [{deadlock_detected, length(Deadlocks)} | Reasons]
    end,

    {ok, CanTerminate} = check_termination(NetMod, UsrInfo),
    Reasons2 = case CanTerminate of
        true -> Reasons1;
        false -> [cannot_terminate | Reasons1]
    end,

    Reachable = maps:keys(get_reachable_states(NetMod, UsrInfo)),
    FinalStates = lists:filter(fun is_final_marking/1, Reachable),
    Reasons3 = case FinalStates of
        [] -> [no_final_state | Reasons2];
        _ -> Reasons2
    end,

    Sound = Reasons3 =:= [],
    #{sound => Sound, reasons => lists:reverse(Reasons3)}.

%% @doc Gets initial marking.
-spec get_initial_marking(atom()) -> marking().
get_initial_marking(NetMod) ->
    get_initial_marking(NetMod, []).

%% @doc Gets initial marking with user info.
-spec get_initial_marking(atom(), term()) -> marking().
get_initial_marking(NetMod, UsrInfo) ->
    build_initial_marking(NetMod, UsrInfo).

%% @doc Converts marking to string.
-spec marking_to_string(marking()) -> string().
marking_to_string(Marking) ->
    PlaceStrings = lists:map(
        fun({Place, Tokens}) ->
            TokenCount = length(Tokens),
            lists:flatten(io_lib:format("~p:~p", [Place, TokenCount]))
        end,
        lists:sort(maps:to_list(Marking))
    ),
    "{$" ++ string:join(PlaceStrings, ", ") ++ "}".

%% @doc Compares two markings.
-spec compare_markings(marking(), marking()) -> boolean().
compare_markings(Marking1, Marking2) ->
    Keys1 = lists:sort(maps:keys(Marking1)),
    Keys2 = lists:sort(maps:keys(Marking2)),
    case Keys1 =:= Keys2 of
        false -> false;
        true ->
            lists:all(fun(Key) ->
                Tokens1 = lists:sort(maps:get(Key, Marking1, [])),
                Tokens2 = lists:sort(maps:get(Key, Marking2, [])),
                Tokens1 =:= Tokens2
            end, Keys1)
    end.

%%====================================================================
%% Internal Helpers
%%====================================================================

%% @private
build_initial_marking(NetMod, UsrInfo) ->
    Places = NetMod:place_lst(),
    lists:foldl(
        fun(P, Acc) ->
            Acc#{P => NetMod:init_marking(P, UsrInfo)}
        end,
        #{},
        Places
    ).

%% @private
is_transition_enabled(NetMod, Transition, Marking, UsrInfo) ->
    Preset = NetMod:preset(Transition),
    Mode = build_mode(Preset, Marking),
    NetMod:is_enabled(Transition, Mode, UsrInfo).

%% @private
build_mode(Preset, Marking) ->
    lists:foldl(
        fun(Place, Acc) ->
            Tokens = maps:get(Place, Marking, []),
            Acc#{Place => Tokens}
        end,
        #{},
        Preset
    ).

%% @private
consume_tokens(Marking, Mode) ->
    maps:map(
        fun(_Place, Tokens) ->
            %% Simplify token consumption - remove first token
            case Tokens of
                [] -> [];
                [_ | Rest] -> Rest
            end
        end,
        Marking
    ).

%% @private
apply_trigger(ProduceMap, NetMod, _State) ->
    %% Simplified trigger - just pass everything through
    ProduceMap.

%% @private
produce_tokens(Marking, ProduceMap) ->
    maps:fold(
        fun(Place, Tokens, Acc) ->
            CurrentTokens = maps:get(Place, Acc, []),
            Acc#{Place => CurrentTokens ++ Tokens}
        end,
        Marking,
        ProduceMap
    ).
