%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Graph Bridge
%%%
%%% Connects the existing YAWL workflow graph infrastructure (YAWL
%%% patterns, gen_pnet Petri nets, Colored Petri Nets) to BeamAI's
%%% graph engine. This bridge translates between YAWL's place/transition
%%% Petri net model and BeamAI's node/edge directed graph model.
%%%
%%% Responsibilities:
%%% - Wrap gen_pnet graphs as BeamAI graph nodes
%%% - Load YAWL workflow definitions as BeamAI graphs
%%% - Provide graph traversal respecting both YAWL and BeamAI semantics
%%% - Track node states during graph execution
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(beamai_graph_bridge).
-behaviour(gen_server).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% API
-export([
    start_link/0,
    start_link/1,
    from_yawl_definition/1,
    to_beamai_graph/1,
    execute_graph/2,
    get_node_state/2,
    list_graphs/0,
    get_graph/1,
    remove_graph/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%%%===================================================================
%%% Records
%%%===================================================================

%% A BeamAI graph node wrapping a YAWL place or transition.
-record(beamai_node, {
    id          :: binary(),
    type        :: place | transition | start_node | end_node | decision | fork | join,
    label       :: binary(),
    yawl_ref    :: atom() | undefined,   %% Reference to original YAWL place/transition
    state       :: idle | active | completed | disabled,
    properties  :: map(),
    position    :: {integer(), integer()} | undefined
}).

%% A BeamAI graph edge connecting two nodes.
-record(beamai_edge, {
    id          :: binary(),
    source      :: binary(),   %% Source node ID
    target      :: binary(),   %% Target node ID
    type        :: flow | cancel | signal | data,
    label       :: binary() | undefined,
    guard       :: map() | undefined,   %% Optional guard condition
    weight      :: pos_integer()
}).

%% A complete BeamAI graph wrapping a YAWL workflow definition.
-record(beamai_graph, {
    id          :: binary(),
    name        :: binary(),
    pattern_type :: atom(),
    nodes       :: #{binary() => #beamai_node{}},
    edges       :: [#beamai_edge{}],
    node_states :: #{binary() => atom()},
    entry_node  :: binary() | undefined,
    exit_nodes  :: [binary()],
    metadata    :: map(),
    created_at  :: integer()
}).

-record(state, {
    graphs      :: #{binary() => #beamai_graph{}},
    config      :: map(),
    metrics     :: map()
}).

-define(SERVER, ?MODULE).

-define(DEFAULT_CONFIG, #{
    max_graphs => 1000,
    enable_layout => false
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the graph bridge with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the graph bridge with custom configuration.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%% @doc Convert a YAWL workflow definition (pattern type + config) into
%% a BeamAI graph. The definition should be a map containing pattern_type
%% and optionally config, places, transitions, preset, and postset.
-spec from_yawl_definition(map()) -> {ok, binary()} | {error, term()}.
from_yawl_definition(Definition) ->
    gen_server:call(?SERVER, {from_yawl_definition, Definition}).

%% @doc Retrieve a stored graph in the BeamAI graph format (a map
%% representation suitable for serialization or external consumption).
-spec to_beamai_graph(binary()) -> {ok, map()} | {error, not_found}.
to_beamai_graph(GraphId) ->
    gen_server:call(?SERVER, {to_beamai_graph, GraphId}).

%% @doc Execute a graph by activating its entry node and propagating
%% tokens through the network. InputData supplies initial token values.
-spec execute_graph(binary(), map()) -> {ok, map()} | {error, term()}.
execute_graph(GraphId, InputData) ->
    gen_server:call(?SERVER, {execute_graph, GraphId, InputData}, infinity).

%% @doc Get the current state of a specific node in a graph.
-spec get_node_state(binary(), binary()) -> {ok, atom()} | {error, term()}.
get_node_state(GraphId, NodeId) ->
    gen_server:call(?SERVER, {get_node_state, GraphId, NodeId}).

%% @doc List all loaded graphs.
-spec list_graphs() -> [map()].
list_graphs() ->
    gen_server:call(?SERVER, list_graphs).

%% @doc Retrieve the full graph structure.
-spec get_graph(binary()) -> {ok, map()} | {error, not_found}.
get_graph(GraphId) ->
    gen_server:call(?SERVER, {get_graph, GraphId}).

%% @doc Remove a graph from the bridge.
-spec remove_graph(binary()) -> ok | {error, not_found}.
remove_graph(GraphId) ->
    gen_server:call(?SERVER, {remove_graph, GraphId}).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init(UserConfig) ->
    Config = maps:merge(?DEFAULT_CONFIG, UserConfig),
    State = #state{
        graphs = #{},
        config = Config,
        metrics = #{
            graphs_created => 0,
            graphs_executed => 0,
            nodes_activated => 0
        }
    },
    logger:info("BeamAI graph bridge initialized"),
    {ok, State}.

%% @private
handle_call({from_yawl_definition, Definition}, _From, State) ->
    case do_from_yawl_definition(Definition) of
        {ok, Graph} ->
            GraphId = Graph#beamai_graph.id,
            NewGraphs = maps:put(GraphId, Graph, State#state.graphs),
            Metrics = State#state.metrics,
            Count = maps:get(graphs_created, Metrics, 0),
            NewMetrics = Metrics#{graphs_created => Count + 1},
            {reply, {ok, GraphId},
             State#state{graphs = NewGraphs, metrics = NewMetrics}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({to_beamai_graph, GraphId}, _From, State) ->
    case maps:get(GraphId, State#state.graphs, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Graph ->
            {reply, {ok, graph_to_beamai_map(Graph)}, State}
    end;

handle_call({execute_graph, GraphId, InputData}, _From, State) ->
    case maps:get(GraphId, State#state.graphs, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Graph ->
            case do_execute_graph(Graph, InputData) of
                {ok, UpdatedGraph, Result} ->
                    NewGraphs = maps:put(GraphId, UpdatedGraph, State#state.graphs),
                    Metrics = State#state.metrics,
                    ExecCount = maps:get(graphs_executed, Metrics, 0),
                    NewMetrics = Metrics#{graphs_executed => ExecCount + 1},
                    {reply, {ok, Result},
                     State#state{graphs = NewGraphs, metrics = NewMetrics}};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;

handle_call({get_node_state, GraphId, NodeId}, _From, State) ->
    case maps:get(GraphId, State#state.graphs, undefined) of
        undefined ->
            {reply, {error, {graph_not_found, GraphId}}, State};
        Graph ->
            case maps:get(NodeId, Graph#beamai_graph.node_states, undefined) of
                undefined ->
                    case maps:is_key(NodeId, Graph#beamai_graph.nodes) of
                        true -> {reply, {ok, idle}, State};
                        false -> {reply, {error, {node_not_found, NodeId}}, State}
                    end;
                NodeState ->
                    {reply, {ok, NodeState}, State}
            end
    end;

handle_call(list_graphs, _From, #state{graphs = Graphs} = State) ->
    List = maps:fold(fun(_Id, G, Acc) ->
        [#{
            id => G#beamai_graph.id,
            name => G#beamai_graph.name,
            pattern_type => G#beamai_graph.pattern_type,
            node_count => map_size(G#beamai_graph.nodes),
            edge_count => length(G#beamai_graph.edges),
            created_at => G#beamai_graph.created_at
        } | Acc]
    end, [], Graphs),
    {reply, lists:reverse(List), State};

handle_call({get_graph, GraphId}, _From, State) ->
    case maps:get(GraphId, State#state.graphs, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Graph ->
            {reply, {ok, graph_to_full_map(Graph)}, State}
    end;

handle_call({remove_graph, GraphId}, _From, State) ->
    case maps:is_key(GraphId, State#state.graphs) of
        true ->
            NewGraphs = maps:remove(GraphId, State#state.graphs),
            {reply, ok, State#state{graphs = NewGraphs}};
        false ->
            {reply, {error, not_found}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @private Build a BeamAI graph from a YAWL workflow definition map.
-spec do_from_yawl_definition(map()) -> {ok, #beamai_graph{}} | {error, term()}.
do_from_yawl_definition(Definition) ->
    try
        PatternType = maps:get(pattern_type, Definition),
        Name = maps:get(name, Definition,
                        atom_to_binary(PatternType, utf8)),

        %% Extract places and transitions from the definition or
        %% fall back to retrieving them from yawl_patterns.
        {Places, Transitions, Preset, Postset} =
            extract_structure(PatternType, Definition),

        %% Build nodes from places
        PlaceNodes = lists:foldl(fun(Place, Acc) ->
            NodeId = place_to_node_id(Place),
            NodeType = classify_place(Place, Places),
            Node = #beamai_node{
                id = NodeId,
                type = NodeType,
                label = atom_to_binary(Place, utf8),
                yawl_ref = Place,
                state = idle,
                properties = #{origin => place},
                position = undefined
            },
            maps:put(NodeId, Node, Acc)
        end, #{}, Places),

        %% Build nodes from transitions
        TransNodes = lists:foldl(fun(Trsn, Acc) ->
            NodeId = transition_to_node_id(Trsn),
            NodeType = classify_transition(Trsn),
            Node = #beamai_node{
                id = NodeId,
                type = NodeType,
                label = atom_to_binary(Trsn, utf8),
                yawl_ref = Trsn,
                state = idle,
                properties = #{origin => transition},
                position = undefined
            },
            maps:put(NodeId, Node, Acc)
        end, #{}, Transitions),

        AllNodes = maps:merge(PlaceNodes, TransNodes),

        %% Build edges from preset and postset maps
        Edges = build_edges(Preset, Postset, AllNodes),

        %% Determine entry and exit nodes
        EntryNode = find_entry_node(AllNodes),
        ExitNodes = find_exit_nodes(AllNodes),

        Now = erlang:system_time(millisecond),
        GraphId = generate_graph_id(),

        Graph = #beamai_graph{
            id = GraphId,
            name = Name,
            pattern_type = PatternType,
            nodes = AllNodes,
            edges = Edges,
            node_states = #{},
            entry_node = EntryNode,
            exit_nodes = ExitNodes,
            metadata = maps:get(metadata, Definition, #{}),
            created_at = Now
        },
        {ok, Graph}
    catch
        _:Error ->
            {error, {definition_conversion_failed, Error}}
    end.

%% @private Extract the structural components from a definition.
-spec extract_structure(atom(), map()) ->
    {[atom()], [atom()], map(), map()}.
extract_structure(PatternType, Definition) ->
    Places = maps:get(places, Definition, default_places(PatternType)),
    Transitions = maps:get(transitions, Definition, default_transitions(PatternType)),
    Preset = maps:get(preset, Definition, #{}),
    Postset = maps:get(postset, Definition, #{}),
    {Places, Transitions, Preset, Postset}.

%% @private Provide default places for common YAWL patterns.
-spec default_places(atom()) -> [atom()].
default_places(basic_sequential) ->
    [start, task_a, task_b, 'end'];
default_places(parallel_split) ->
    [start, split, branch_a, branch_b, 'end'];
default_places(parallel_join) ->
    [start, branch_a, branch_b, join, 'end'];
default_places(exclusive_choice) ->
    [start, decision, path_a, path_b, 'end'];
default_places(simple_merge) ->
    [start, path_a, path_b, merge, 'end'];
default_places(_PatternType) ->
    [start, process, 'end'].

%% @private Provide default transitions for common YAWL patterns.
-spec default_transitions(atom()) -> [atom()].
default_transitions(basic_sequential) ->
    [t_start, t_a_to_b, t_end];
default_transitions(parallel_split) ->
    [t_start, t_split, t_a, t_b, t_end];
default_transitions(parallel_join) ->
    [t_start, t_a, t_b, t_join, t_end];
default_transitions(exclusive_choice) ->
    [t_start, t_choose_a, t_choose_b, t_end];
default_transitions(simple_merge) ->
    [t_start, t_a, t_b, t_merge, t_end];
default_transitions(_PatternType) ->
    [t_start, t_process, t_end].

%% @private Classify a place node based on its name and position.
-spec classify_place(atom(), [atom()]) -> atom().
classify_place(start, _Places) -> start_node;
classify_place('end', _Places) -> end_node;
classify_place(Place, _Places) ->
    PlaceStr = atom_to_list(Place),
    case PlaceStr of
        "join" ++ _ -> join;
        "split" ++ _ -> fork;
        "decision" ++ _ -> decision;
        "merge" ++ _ -> join;
        _ -> place
    end.

%% @private Classify a transition node based on its name.
-spec classify_transition(atom()) -> atom().
classify_transition(Trsn) ->
    TrsnStr = atom_to_list(Trsn),
    case TrsnStr of
        "t_split" ++ _ -> fork;
        "t_join" ++ _ -> join;
        "t_choose" ++ _ -> decision;
        "t_merge" ++ _ -> join;
        _ -> transition
    end.

%% @private Build edges from preset and postset relationships.
-spec build_edges(map(), map(), map()) -> [#beamai_edge{}].
build_edges(Preset, Postset, AllNodes) ->
    %% Edges from preset: transition -> places (incoming arcs to transition)
    PresetEdges = maps:fold(fun(Trsn, Places, Acc) ->
        TrsnId = transition_to_node_id(Trsn),
        lists:foldl(fun(Place, InnerAcc) ->
            PlaceId = place_to_node_id(Place),
            case maps:is_key(PlaceId, AllNodes) andalso maps:is_key(TrsnId, AllNodes) of
                true ->
                    Edge = #beamai_edge{
                        id = generate_edge_id(),
                        source = PlaceId,
                        target = TrsnId,
                        type = flow,
                        label = undefined,
                        guard = undefined,
                        weight = 1
                    },
                    [Edge | InnerAcc];
                false ->
                    InnerAcc
            end
        end, Acc, Places)
    end, [], Preset),

    %% Edges from postset: transition -> places (outgoing arcs from transition)
    PostsetEdges = maps:fold(fun(Trsn, Places, Acc) ->
        TrsnId = transition_to_node_id(Trsn),
        lists:foldl(fun(Place, InnerAcc) ->
            PlaceId = place_to_node_id(Place),
            case maps:is_key(PlaceId, AllNodes) andalso maps:is_key(TrsnId, AllNodes) of
                true ->
                    Edge = #beamai_edge{
                        id = generate_edge_id(),
                        source = TrsnId,
                        target = PlaceId,
                        type = flow,
                        label = undefined,
                        guard = undefined,
                        weight = 1
                    },
                    [Edge | InnerAcc];
                false ->
                    InnerAcc
            end
        end, Acc, Places)
    end, [], Postset),

    %% If no preset/postset was given, build sequential edges
    case PresetEdges =:= [] andalso PostsetEdges =:= [] of
        true -> build_sequential_edges(AllNodes);
        false -> PresetEdges ++ PostsetEdges
    end.

%% @private Build simple sequential edges when no structure is given.
-spec build_sequential_edges(map()) -> [#beamai_edge{}].
build_sequential_edges(AllNodes) ->
    NodeList = lists:sort(fun(#beamai_node{id = A}, #beamai_node{id = B}) ->
        A =< B
    end, maps:values(AllNodes)),
    build_chain_edges(NodeList, []).

build_chain_edges([_], Acc) -> lists:reverse(Acc);
build_chain_edges([A, B | Rest], Acc) ->
    Edge = #beamai_edge{
        id = generate_edge_id(),
        source = A#beamai_node.id,
        target = B#beamai_node.id,
        type = flow,
        label = undefined,
        guard = undefined,
        weight = 1
    },
    build_chain_edges([B | Rest], [Edge | Acc]);
build_chain_edges([], Acc) -> Acc.

%% @private Find the entry node of the graph.
-spec find_entry_node(map()) -> binary() | undefined.
find_entry_node(Nodes) ->
    Result = maps:fold(fun(_Id, #beamai_node{type = start_node, id = NodeId}, _Acc) ->
        NodeId;
    (_Id, _Node, Acc) ->
        Acc
    end, undefined, Nodes),
    Result.

%% @private Find exit nodes of the graph.
-spec find_exit_nodes(map()) -> [binary()].
find_exit_nodes(Nodes) ->
    maps:fold(fun(_Id, #beamai_node{type = end_node, id = NodeId}, Acc) ->
        [NodeId | Acc];
    (_Id, _Node, Acc) ->
        Acc
    end, [], Nodes).

%% @private Execute a graph by simulating token flow from entry to exit.
-spec do_execute_graph(#beamai_graph{}, map()) ->
    {ok, #beamai_graph{}, map()} | {error, term()}.
do_execute_graph(#beamai_graph{entry_node = undefined}, _InputData) ->
    {error, no_entry_node};
do_execute_graph(Graph, InputData) ->
    #beamai_graph{entry_node = EntryId, nodes = Nodes, edges = Edges,
                  exit_nodes = ExitNodeIds} = Graph,

    %% Initialize: activate the entry node
    InitStates = #{EntryId => active},

    %% Propagate activation through the graph using BFS
    {FinalStates, Trace} = propagate_tokens(
        [EntryId], InitStates, Edges, Nodes, ExitNodeIds, InputData, []
    ),

    UpdatedGraph = Graph#beamai_graph{node_states = FinalStates},
    Result = #{
        final_states => FinalStates,
        trace => lists:reverse(Trace),
        reached_exit => lists:any(
            fun(ExId) -> maps:get(ExId, FinalStates, idle) =:= completed end,
            ExitNodeIds
        ),
        input_data => InputData
    },
    {ok, UpdatedGraph, Result}.

%% @private Propagate tokens through graph edges using BFS traversal.
-spec propagate_tokens([binary()], map(), [#beamai_edge{}], map(),
                       [binary()], map(), [map()]) -> {map(), [map()]}.
propagate_tokens([], States, _Edges, _Nodes, _ExitNodes, _Data, Trace) ->
    {States, Trace};
propagate_tokens([NodeId | Queue], States, Edges, Nodes, ExitNodes, Data, Trace) ->
    %% Mark current node as completed
    NewStates = maps:put(NodeId, completed, States),

    TraceEntry = #{
        node_id => NodeId,
        action => completed,
        timestamp => erlang:system_time(millisecond)
    },

    %% Find outgoing edges from this node
    Outgoing = [E || #beamai_edge{source = Src} = E <- Edges, Src =:= NodeId],

    %% Activate target nodes
    {TargetStates, NewTargets} = lists:foldl(
        fun(#beamai_edge{target = TargetId}, {SAcc, TAcc}) ->
            case maps:get(TargetId, SAcc, idle) of
                idle ->
                    {maps:put(TargetId, active, SAcc), [TargetId | TAcc]};
                _ ->
                    {SAcc, TAcc}
            end
        end,
        {NewStates, []},
        Outgoing
    ),

    %% Filter out exit nodes from the queue (they complete but don't propagate)
    NextQueue = Queue ++ lists:filter(
        fun(TId) -> not lists:member(TId, ExitNodes) end,
        lists:reverse(NewTargets)
    ),

    %% Mark exit nodes as completed immediately
    FinalStates = lists:foldl(fun(TId, SAcc) ->
        case lists:member(TId, ExitNodes) of
            true -> maps:put(TId, completed, SAcc);
            false -> SAcc
        end
    end, TargetStates, NewTargets),

    propagate_tokens(NextQueue, FinalStates, Edges, Nodes, ExitNodes, Data,
                     [TraceEntry | Trace]).

%% @private Convert a graph record to the BeamAI external map format.
-spec graph_to_beamai_map(#beamai_graph{}) -> map().
graph_to_beamai_map(Graph) ->
    #{
        beamai_type => graph,
        id => Graph#beamai_graph.id,
        name => Graph#beamai_graph.name,
        nodes => [node_to_map(N) || N <- maps:values(Graph#beamai_graph.nodes)],
        edges => [edge_to_map(E) || E <- Graph#beamai_graph.edges],
        entry_node => Graph#beamai_graph.entry_node,
        exit_nodes => Graph#beamai_graph.exit_nodes,
        metadata => Graph#beamai_graph.metadata
    }.

%% @private Convert to full map including internal state.
-spec graph_to_full_map(#beamai_graph{}) -> map().
graph_to_full_map(Graph) ->
    Base = graph_to_beamai_map(Graph),
    Base#{
        pattern_type => Graph#beamai_graph.pattern_type,
        node_states => Graph#beamai_graph.node_states,
        created_at => Graph#beamai_graph.created_at
    }.

%% @private Convert a node record to a map.
-spec node_to_map(#beamai_node{}) -> map().
node_to_map(#beamai_node{} = N) ->
    #{
        id => N#beamai_node.id,
        type => N#beamai_node.type,
        label => N#beamai_node.label,
        state => N#beamai_node.state,
        properties => N#beamai_node.properties
    }.

%% @private Convert an edge record to a map.
-spec edge_to_map(#beamai_edge{}) -> map().
edge_to_map(#beamai_edge{} = E) ->
    #{
        id => E#beamai_edge.id,
        source => E#beamai_edge.source,
        target => E#beamai_edge.target,
        type => E#beamai_edge.type,
        label => E#beamai_edge.label,
        weight => E#beamai_edge.weight
    }.

%% @private Convert a place atom to a node identifier.
-spec place_to_node_id(atom()) -> binary().
place_to_node_id(Place) ->
    <<"p-", (atom_to_binary(Place, utf8))/binary>>.

%% @private Convert a transition atom to a node identifier.
-spec transition_to_node_id(atom()) -> binary().
transition_to_node_id(Trsn) ->
    <<"t-", (atom_to_binary(Trsn, utf8))/binary>>.

%% @private Generate a unique graph identifier.
-spec generate_graph_id() -> binary().
generate_graph_id() ->
    Bytes = crypto:strong_rand_bytes(8),
    Hex = binary:encode_hex(Bytes),
    <<"bgraph-", Hex/binary>>.

%% @private Generate a unique edge identifier.
-spec generate_edge_id() -> binary().
generate_edge_id() ->
    Bytes = crypto:strong_rand_bytes(6),
    Hex = binary:encode_hex(Bytes),
    <<"edge-", Hex/binary>>.
