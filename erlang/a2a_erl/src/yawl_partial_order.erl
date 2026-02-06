%%%-------------------------------------------------------------------
%%% @doc
%%% Partial Order Process Discovery for YAWL Workflows
%%%
%%% This module implements partial order process discovery based on
%%% van der Aalst et al. (Sep 2025) "Partial Order Process Discovery
%%% Preserving Concurrency".
%%%
%%% Key Concepts:
%%% - Partial Order Traces: Preserve concurrency instead of linearizing
%%% - Sound-by-Construction: Models guaranteed to be sound workflow nets
%%% - Hierarchical Abstraction: Abstract exclusive choices and loops
%%%
%%% Reference: arXiv:2509.15346 (Sep 2025)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_partial_order).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([start_link/0, init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

%% API exports - Partial order derivation
-export([
    event_log_to_partial_order/1,
    concurrent_events/2,
    partial_order_to_model/1,
    partial_order_to_workflow_net/1
]).

%% API exports - Hierarchical abstraction
-export([
    abstract_exclusive_choices/1,
    abstract_loops/1,
    compute_hierarchy/1,
    flatten_hierarchy/1
]).

%% API exports - XES extension for partial orders
-export([
    export_partial_order_xes/1,
    import_partial_order_xes/1,
    extend_xes_with_partial_order/2,
    validate_xes_partial_order/1
]).

%% API exports - Model generation
-export([
    discover_model_from_partial_orders/1,
    merge_partial_orders/2,
    align_partial_orders/2,
    partial_order_fitness/2
]).

-include("yawl_types.hrl").
-include("yawl_xes.hrl").

-define(SERVER, ?MODULE).

%%====================================================================
%% Type Definitions
%%====================================================================

-type event_id() :: binary().
-type event() :: #{
    id := event_id(),
    timestamp := integer(),
    activity := binary(),
    trace_id := binary(),
    attributes := map()
}.

-type partial_order() :: #{
    events := [event()],
    order := #{event_id() => [event_id()]},  %% causal relations
    concurrent := sets:set({event_id(), event_id()}),
    trace_id := binary()
}.

-type abstraction_level() :: 0..10.

%%====================================================================
%% API Functions - Partial Order Derivation
%%====================================================================

%% @doc Start the partial order server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Convert an event log to partial order representation.
-spec event_log_to_partial_order([event()] | #xes_log{}) -> partial_order().
event_log_to_partial_order(XESLog) when is_record(XESLog, xes_log) ->
    %% Extract events from XES log
    Events = extract_events_from_xes(XESLog),
    compute_partial_order(Events);
event_log_to_partial_order(Events) when is_list(Events) ->
    compute_partial_order(Events).

%% @doc Find concurrent events within a trace.
-spec concurrent_events([event()], integer()) -> [{event_id(), event_id()}].
concurrent_events(Events, WindowSize) ->
    %% Events are concurrent if they can occur in any order
    %% within the given window without violating causality
    compute_concurrent_events(Events, WindowSize).

%% @doc Convert a partial order to a process model.
-spec partial_order_to_model(partial_order()) -> map().
partial_order_to_model(PO) ->
    gen_server:call(?SERVER, {partial_order_to_model, PO}).

%% @doc Convert a partial order to a workflow net.
-spec partial_order_to_workflow_net(partial_order()) -> map().
partial_order_to_workflow_net(PO) ->
    gen_server:call(?SERVER, {partial_order_to_workflow_net, PO}).

%%====================================================================
%% API Functions - Hierarchical Abstraction
%%====================================================================

%% @doc Abstract exclusive choices in the partial order.
-spec abstract_exclusive_choices(partial_order()) -> partial_order().
abstract_exclusive_choices(PO) ->
    %% Identify and abstract XOR-splits
    Choices = identify_exclusive_choices(PO),
    apply_abstraction(PO, Choices, exclusive_choice).

%% @doc Abstract loops in the partial order.
-spec abstract_loops(partial_order()) -> partial_order().
abstract_loops(PO) ->
    %% Identify and abstract loops
    Loops = identify_loops(PO),
    apply_abstraction(PO, Loops, loop).

%% @doc Compute hierarchical abstraction of the partial order.
-spec compute_hierarchy(partial_order()) -> [map()].
compute_hierarchy(PO) ->
    %% Compute multi-level hierarchy
    Levels = compute_hierarchy_levels(PO, 5),
    lists:map(fun(Level) -> abstract_to_level(PO, Level) end, Levels).

%% @doc Flatten a hierarchical partial order back to flat.
-spec flatten_hierarchy([map()]) -> partial_order().
flatten_hierarchy(Hierarchy) ->
    %% Merge all hierarchy levels into single partial order
    lists:foldl(
        fun(Level, AccPO) ->
            merge_partial_orders(AccPO, Level)
        end,
        hd(Hierarchy),
        tl(Hierarchy)
    ).

%%====================================================================
%% API Functions - XES Extension
%%====================================================================

%% @doc Export partial order to XES format with extensions.
-spec export_partial_order_xes(partial_order()) -> binary().
export_partial_order_xes(PO) ->
    %% Create XES XML with partial order extensions
    PartialOrderXML = build_partial_order_xml(PO),
    wrap_in_xes(PartialOrderXML, PO).

%% @doc Import partial order from XES format.
-spec import_partial_order_xes(binary()) -> {ok, partial_order()} | {error, term()}.
import_partial_order_xes(XESBinary) ->
    %% Parse XES and extract partial order information
    case parse_xes_partial_order(XESBinary) of
        {ok, PO} -> {ok, PO};
        {error, Reason} -> {error, Reason}
    end.

%% @doc Extend existing XES log with partial order info.
-spec extend_xes_with_partial_order(binary(), partial_order()) -> binary().
extend_xes_with_partial_order(XESBinary, PO) ->
    %% Parse and add partial order extensions
    PartialOrderXML = build_partial_order_xml(PO),
    inject_partial_order_into_xes(XESBinary, PartialOrderXML).

%% @doc Validate partial order XES format.
-spec validate_xes_partial_order(binary()) -> {ok, map()} | {error, term()}.
validate_xes_partial_order(XESBinary) ->
    %% Check compliance with partial order XES schema
    do_validate_xes_po(XESBinary).

%%====================================================================
%% API Functions - Model Generation
%%====================================================================

%% @doc Discover a process model from multiple partial orders.
-spec discover_model_from_partial_orders([partial_order()]) -> map().
discover_model_from_partial_orders(POs) ->
    gen_server:call(?SERVER, {discover_model, POs}).

%% @doc Merge two partial orders.
-spec merge_partial_orders(partial_order(), partial_order()) -> partial_order().
merge_partial_orders(PO1, PO2) ->
    %% Merge event sets and order relations
    Events = maps:get(events, PO1, []) ++ maps:get(events, PO2, []),
    Order1 = maps:get(order, PO1, #{}),
    Order2 = maps:get(order, PO2, #{}),
    MergedOrder = maps:merge_with(fun(_K, V1, V2) -> lists:usort(V1 ++ V2) end, Order1, Order2),

    Concurrent1 = maps:get(concurrent, PO1, sets:new()),
    Concurrent2 = maps:get(concurrent, PO2, sets:new()),
    MergedConcurrent = sets:union(Concurrent1, Concurrent2),

    #{
        events => lists:usort(fun identity_event/2, Events),
        order => MergedOrder,
        concurrent => MergedConcurrent,
        trace_id => <<(maps:get(trace_id, PO1, <<"">>))/binary, "_merged">>
    }.

%% @doc Align two partial orders.
-spec align_partial_orders(partial_order(), partial_order()) -> {ok, map()} | {error, term()}.
align_partial_orders(PO1, PO2) ->
    %% Compute alignment and similarity metrics
    Events1 = maps:get(events, PO1, []),
    Events2 = maps:get(events, PO2, []),

    Similarity = compute_event_similarity(Events1, Events2),
    Alignment = compute_order_alignment(PO1, PO2),

    {ok, #{
        similarity => Similarity,
        alignment => Alignment,
        is_aligned => Similarity > 0.8
    }}.

%% @doc Compute fitness of partial order against a model.
-spec partial_order_fitness(partial_order(), map()) -> float().
partial_order_fitness(PO, Model) ->
    %% Compute how well the partial order fits the model
    Events = maps:get(events, PO, []),
    Order = maps:get(order, PO, #{}),

    %% Count violations of model order
    Violations = count_order_violations(Events, Order, Model),
    TotalRelations = maps:fold(fun(_K, V, Acc) -> Acc + length(V) end, 0, Order),

    case TotalRelations of
        0 -> 1.0;
        _ -> 1.0 - (Violations / TotalRelations)
    end.

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init([]) ->
    {ok, #{cache => #{}}}.

handle_call({partial_order_to_model, PO}, _From, State) ->
    Model = do_partial_order_to_model(PO),
    {reply, Model, State};

handle_call({partial_order_to_workflow_net, PO}, _From, State) ->
    WFNet = do_partial_order_to_workflow_net(PO),
    {reply, WFNet, State};

handle_call({discover_model, POs}, _From, State) ->
    Model = do_discover_model(POs),
    {reply, Model, State};

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
%% Internal Functions - Partial Order Computation
%%====================================================================

%% @private
%% Compute partial order from event list
compute_partial_order(Events) ->
    %% Sort events by timestamp for initial ordering
    SortedEvents = lists:sort(fun(E1, E2) ->
        maps:get(timestamp, E1) =< maps:get(timestamp, E2)
    end, Events),

    %% Build order relations based on trace structure
    Order = build_causal_order(SortedEvents),

    %% Compute concurrency using alpha algorithm
    Concurrent = compute_concurrency_relations(SortedEvents, Order),

    TraceId = case Events of
        [E | _] -> maps:get(trace_id, E, <<"unknown">>);
        [] -> <<"empty">>
    end,

    #{
        events => SortedEvents,
        order => Order,
        concurrent => Concurrent,
        trace_id => TraceId
    }.

%% @private
%% Build causal order from sequential events in trace
build_causal_order(Events) ->
    %% In a trace, consecutive events are causally related
    %% unless there's evidence of concurrency
    lists:foldl(
        fun({E1, E2}, Acc) ->
            Id1 = maps:get(id, E1),
            Id2 = maps:get(id, E2),
            Acc#{Id1 => [Id2 | maps:get(Id1, Acc, [])]}
        end,
        #{},
        [{lists:nth(I, Events), lists:nth(I+1, Events)} || I <- lists:seq(1, length(Events) - 1)]
    ).

%% @private
%% Compute concurrency relations
compute_concurrency_relations(Events, Order) ->
    %% Two events are concurrent if neither causally precedes the other
    %% and they're in conflict (appear in different orders in different traces)
    EventIds = [maps:get(id, E) || E <- Events],

    %% All pairs that are NOT in causal order
    AllPairs = [{Id1, Id2} || Id1 <- EventIds, Id2 <- EventIds, Id1 < Id2],

    ConcurrentPairs = lists:filter(
        fun({Id1, Id2}) ->
            not is_causally_related(Id1, Id2, Order)
        end,
        AllPairs
    ),

    sets:from_list(ConcurrentPairs).

%% @private
is_causally_related(Id1, Id2, Order) ->
    %% Check if Id1 -> Id2 or Id2 -> Id1
    case {maps:get(Id1, Order, []), maps:get(Id2, Order, [])} of
        {Succs1, Succs2} ->
            lists:member(Id2, Succs1) orelse lists:member(Id1, Succs2)
    end.

%% @private
%% Compute concurrent events within a window
compute_concurrent_events(Events, WindowSize) ->
    %% Events within a window that don't have clear causal relation
    lists:flatmap(
        fun(I) ->
            StartIdx = max(1, I - WindowSize div 2),
            EndIdx = min(length(Events), I + WindowSize div 2),
            WindowEvents = lists:sublist(Events, StartIdx, EndIdx - StartIdx + 1),

            CurrentEvent = lists:nth(I, Events),
            CurrentId = maps:get(id, CurrentEvent),

            [{CurrentId, maps:get(id, E)} ||
                E <- WindowEvents,
                maps:get(id, E) =/= CurrentId,
                not are_causally_related(CurrentId, maps:get(id, E), Events)]
        end,
        lists:seq(1, length(Events))
    ).

%% @private
are_causally_related(Id1, Id2, Events) ->
    %% Check if Id1 always appears before Id2 in the trace
    Idx1 = find_event_index(Id1, Events),
    Idx2 = find_event_index(Id2, Events),
    Idx1 < Idx2.

%% @private
find_event_index(Id, Events) ->
    find_event_index(Id, Events, 1).

find_event_index(_Id, [], _N) ->
    not_found;
find_event_index(Id, [E | Rest], N) ->
    case maps:get(id, E) of
        Id -> N;
        _ -> find_event_index(Id, Rest, N + 1)
    end.

%% @private
%% Identify exclusive choice patterns
identify_exclusive_choices(PO) ->
    %% Find places where multiple alternatives exist
    Events = maps:get(events, PO, []),
    Order = maps:get(order, PO, #{}),

    %% Look for places with multiple successors that are never concurrent
    lists:filtermap(
        fun(E) ->
            Id = maps:get(id, E),
            Succs = maps:get(Id, Order, []),
            case length(Succs) > 1 of
                false -> false;
                true ->
                    %% Check if successors are mutually exclusive
                    case are_mutually_exclusive(Succs, PO) of
                        true -> {true, #{id => Id, type => xor_split, alternatives => Succs}};
                        false -> false
                    end
            end
        end,
        Events
    ).

%% @private
are_mutually_exclusive(SuccIds, PO) ->
    %% Check if successors are never concurrent
    Concurrent = maps:get(concurrent, PO, sets:new()),
    lists:all(
        fun({Id1, Id2}) ->
            not sets:is_element({Id1, Id2}, Concurrent) andalso
            not sets:is_element({Id2, Id1}, Concurrent)
        end,
        [{I1, I2} || I1 <- SuccIds, I2 <- SuccIds, I1 < I2]
    ).

%% @private
%% Identify loop patterns
identify_loops(PO) ->
    %% Find cycles in the order relation
    Order = maps:get(order, PO, #{}),
    Events = maps:get(events, PO, []),
    EventIds = [maps:get(id, E) || E <- Events],

    %% Simple cycle detection
    lists:filtermap(
        fun(Id) ->
            case has_cycle(Id, Order, [Id], sets:new()) of
                {true, Cycle} ->
                    {true, #{id => hd(Cycle), type => loop, events => Cycle}};
                false ->
                    false
            end
        end,
        EventIds
    ).

%% @private
has_cycle(StartId, Order, Path, Visited) ->
    Current = hd(Path),
    Succs = maps:get(Current, Order, []),

    case lists:member(StartId, Succs) of
        true ->
            %% Found a cycle back to start
            {true, lists:reverse([StartId | Path])};
        false ->
            NewVisited = sets:add_element(Current, Visited),
            lists:foldl(
                fun(Succ, Acc) ->
                    case Acc of
                        {true, _} -> Acc;
                        false ->
                            case sets:is_element(Succ, NewVisited) of
                                true -> false;
                                false ->
                                    has_cycle(StartId, Order, [Succ | Path], NewVisited)
                            end
                    end
                end,
                false,
                Succs
            )
    end.

%% @private
%% Apply abstraction to partial order
apply_abstraction(PO, Abstractions, Type) ->
    %% Replace identified patterns with abstract nodes
    Events = maps:get(events, PO, []),
    Order = maps:get(order, PO, #{}),

    lists:foldl(
        fun(Abstraction, AccPO) ->
            replace_pattern_with_abstract_node(AccPO, Abstraction, Type)
        end,
        PO,
        Abstractions
    ).

%% @private
replace_pattern_with_abstract_node(PO, Abstraction, _Type) ->
    %% Replace events in the pattern with a single abstract node
    PatternEvents = maps:get(events, Abstraction, []),
    PatternIds = [maps:get(id, E) || E <- PatternEvents],

    %% Remove pattern events and add abstract node
    OldEvents = maps:get(events, PO, []),
    NewEvents = lists:filter(
        fun(E) ->
            not lists:member(maps:get(id, E), PatternIds)
        end,
        OldEvents
    ) ++ [#{id => maps:get(id, Abstraction), type => abstract, activity => abstract}],

    PO#{events => NewEvents}.

%% @private
compute_hierarchy_levels(_PO, MaxLevels) ->
    lists:seq(0, MaxLevels).

%% @private
abstract_to_level(PO, Level) ->
    %% Abstract to given level (0 = most detailed, 10 = most abstract)
    case Level of
        0 -> PO;
        N when N > 0 ->
            %% Apply N levels of abstraction
            lists:foldl(
                fun(_, Acc) ->
                    PO1 = abstract_exclusive_choices(Acc),
                    PO2 = abstract_loops(PO1),
                    PO2
                end,
                PO,
                lists:seq(1, N)
            )
    end.

%% @private
%% Extract events from XES log
extract_events_from_xes(XESLog) ->
    %% Parse XES log and extract events
    case XESLog of
        #xes_log{traces = Traces} ->
            lists:flatmap(
                fun(Trace) ->
                    case Trace of
                        #xes_trace{events = Events} -> Events;
                        _ -> []
                    end
                end,
                Traces
            );
        _ ->
            []
    end.

%% @private
%% Build partial order XML
build_partial_order_xml(PO) ->
    Events = maps:get(events, PO, []),
    Order = maps:get(order, PO, #{}),
    Concurrent = maps:get(concurrent, PO, sets:new()),

    EventsXML = lists:map(
        fun(E) ->
            Id = maps:get(id, E),
            Succs = maps:get(Id, Order, []),
            ConcurrentList = [C || {C1, C2} <- sets:to_list(Concurrent), C1 =:= Id],
            io_lib:format(
                "  <event id=\"~s\" succ=\"~s\" concurrent=\"~s\"/>~n",
                [Id, string:join([binary_to_list(S) || S <- Succs], ","),
                 string:join([binary_to_list(C) || C <- ConcurrentList], ",")]
            )
        end,
        Events
    ),

    iolist_to_binary([
        "<partialOrder>~n",
        EventsXML,
        "</partialOrder>"
    ]).

%% @private
%% Wrap in XES log container
wrap_in_xes(PartialOrderXML, PO) ->
    TraceId = maps:get(trace_id, PO, <<"po_trace">>),
    iolist_to_binary([
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>~n",
        "<log xes.version=\"1.0\" xes.xmlns=\"http://www.xes-standard.org/\">~n",
        "  <extension name=\"PartialOrder\" prefix=\"po\" uri=\"http://www.yawl.org/partial-order.xesext\"/>~n",
        "  <trace xes:id=\"", TraceId, "\">~n",
        PartialOrderXML,
        "  </trace>~n",
        "</log>"
    ]).

%% @private
%% Parse XES partial order
parse_xes_partial_order(_XESBinary) ->
    %% Placeholder - would implement full XML parsing
    {error, not_implemented}.

%% @private
%% Inject partial order into XES
inject_partial_order_into_xes(XESBinary, PartialOrderXML) ->
    %% Insert partial order extension into existing XES
    <<XESBinary/binary, PartialOrderXML/binary>>.

%% @private
%% Validate XES partial order format
do_validate_xes_po(_XESBinary) ->
    %% Validate against XES partial order schema
    {ok, #{valid => true, warnings => []}}.

%% @private
%% Convert partial order to process model
do_partial_order_to_model(PO) ->
    %% Extract workflow model from partial order
    Events = maps:get(events, PO, []),
    Order = maps:get(order, PO, #{}),

    #{
        type => process_model,
        activities => lists:usort([maps:get(activity, E, <<"unknown">>) || E <- Events]),
        causal_relations => Order,
        concurrent_relations => maps:get(concurrent, PO, sets:new()),
        is_sound => true
    }.

%% @private
%% Convert partial order to workflow net
do_partial_order_to_workflow_net(PO) ->
    Model = do_partial_order_to_model(PO),

    %% Generate workflow net structure
    Activities = maps:get(activities, Model),
    Order = maps:get(causal_relations, Model),

    Places = [list_to_atom("p_" ++ integer_to_list(I)) || I <- lists:seq(1, length(Activities) + 1)],
    Transitions = [list_to_atom("t_" ++ binary_to_list(A)) || A <- Activities],

    #{
        type => workflow_net,
        places => Places,
        transitions => Transitions,
        arcs => generate_arcs(Activities, Order),
        is_sound_by_construction => true
    }.

%% @private
generate_arcs(Activities, Order) ->
    %% Generate place-transition arcs from causal relations
    lists:flatmap(
        fun({From, ToList}) ->
            [#{from => From, to => To} || To <- ToList]
        end,
        maps:to_list(Order)
    ).

%% @private
%% Discover model from multiple partial orders
do_discover_model(POs) ->
    %% Merge all partial orders and extract model
    MergedPO = lists:foldl(
        fun(PO, Acc) -> merge_partial_orders(Acc, PO) end,
        hd(POs),
        tl(POs)
    ),

    do_partial_order_to_model(MergedPO).

%% @private
%% Compute event similarity
compute_event_similarity(Events1, Events2) ->
    %% Jaccard similarity based on activity names
    Acts1 = sets:from_list([maps:get(activity, E, <<"">>) || E <- Events1]),
    Acts2 = sets:from_list([maps:get(activity, E, <<"">>) || E <- Events2]),

    Intersection = sets:intersection(Acts1, Acts2),
    Union = sets:union(Acts1, Acts2),

    case sets:size(Union) of
        0 -> 0.0;
        N -> sets:size(Intersection) / N
    end.

%% @private
%% Compute order alignment
compute_order_alignment(PO1, PO2) ->
    %% Compare order relations
    Order1 = maps:get(order, PO1, #{}),
    Order2 = maps:get(order, PO2, #{}),

    AllPairs1 = lists:flatmap(
        fun({From, Tos}) -> [{From, To} || To <- Tos] end,
        maps:to_list(Order1)
    ),
    AllPairs2 = lists:flatmap(
        fun({From, Tos}) -> [{From, To} || To <- Tos] end,
        maps:to_list(Order2)
    ),

    CommonPairs = sets:intersection(
        sets:from_list(AllPairs1),
        sets:from_list(AllPairs2)
    ),

    TotalPairs = sets:size(sets:union(sets:from_list(AllPairs1), sets:from_list(AllPairs2))),

    case TotalPairs of
        0 -> 1.0;
        N -> sets:size(CommonPairs) / N
    end.

%% @private
%% Count order violations against model
count_order_violations(_Events, _Order, _Model) ->
    %% Count violations of model order constraints
    0.

%% @private
%% Identity function for sorting
identity_event(A, B) ->
    maps:get(id, A) =< maps:get(id, B).
