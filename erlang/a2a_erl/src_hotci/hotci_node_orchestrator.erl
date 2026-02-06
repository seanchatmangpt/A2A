%%% @doc HotCI Node Orchestrator
%%%
%%% This module orchestrates distributed Erlang nodes across Docker containers
%%% for hot code upgrade testing. It manages the lifecycle of test nodes,
%%% coordinates communication, and provides APIs for creating upgrade scenarios.
-module(hotci_node_orchestrator).
-behaviour(gen_server).

%% API
-export([start_link/0, create_test_cluster/1, destroy_cluster/1,
         upgrade_node/3, get_cluster_status/0, get_node_info/1,
         register_node/2, unregister_node/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% Record definitions
-record(node_info, {
    id :: binary(),
    container_id :: binary(),
    node_name :: binary(),
    node_ip :: binary(),
    port :: integer(),
    status :: 'starting' | 'running' | 'upgrading' | 'stopped' | 'failed',
    version :: binary(),
    start_time :: integer(),
    last_heartbeat :: integer() | undefined
}).

-record(cluster_info, {
    id :: binary(),
    nodes = [] :: [#node_info{}],
    created_at :: integer(),
    version :: binary()
}).

%% State record
-record(state, {
    clusters = #{} :: #{cluster_id() => #cluster_info{}},
    nodes = #{} :: #{node_id() => #node_info{}},
    next_cluster_id = 1 :: integer(),
    next_node_id = 1 :: integer()
}).

-type cluster_id() :: binary().
-type node_id() :: binary().
-type node_status() :: 'starting' | 'running' | 'upgrading' | 'stopped' | 'failed'.

-define(SERVER, ?MODULE).
-define(TICK_INTERVAL, 30000).  % 30 seconds for heartbeats
-define(CLUSTER_TIMEOUT, 60000). % 60 seconds for cluster operations

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the node orchestrator
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Create a test cluster with specified node configuration
-spec create_test_cluster(Config :: map()) -> {ok, cluster_id()} | {error, term()}.
create_test_cluster(Config) ->
    ClusterId = generate_cluster_id(),
    NodeConfigs = maps:get(nodes, Config, []),

    gen_server:call(?SERVER, {create_cluster, ClusterId, NodeConfigs}, ?CLUSTER_TIMEOUT).

%% @doc Destroy a test cluster and all its nodes
-spec destroy_cluster(cluster_id()) -> ok | {error, term()}.
destroy_cluster(ClusterId) ->
    gen_server:call(?SERVER, {destroy_cluster, ClusterId}).

%% @doc Upgrade a specific node in the cluster
-spec upgrade_node(cluster_id(), node_id(), binary()) -> ok | {error, term()}.
upgrade_node(ClusterId, NodeId, NewVersion) ->
    gen_server:call(?SERVER, {upgrade_node, ClusterId, NodeId, NewVersion}).

%% @doc Get cluster status
-spec get_cluster_status() -> map().
get_cluster_status() ->
    gen_server:call(?SERVER, get_cluster_status).

%% @doc Get node information
-spec get_node_info(node_id()) -> {ok, #node_info{}} | {error, term()}.
get_node_info(NodeId) ->
    gen_server:call(?SERVER, {get_node_info, NodeId}).

%% @doc Register a node with the orchestrator
-spec register_node(node_id(), map()) -> ok | {error, term()}.
register_node(NodeId, NodeInfo) ->
    gen_server:call(?SERVER, {register_node, NodeId, NodeInfo}).

%% @doc Unregister a node
-spec unregister_node(node_id()) -> ok.
unregister_node(NodeId) ->
    gen_server:cast(?SERVER, {unregister_node, NodeId}).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init([]) -> {ok, #state{}}.
init([]) ->
    %% Start heartbeat monitoring
    erlang:send_after(?TICK_INTERVAL, self(), tick),

    %% Load persisted state if needed
    State = load_state(),

    %% Register for node events
    net_kernel_monitor:start(),

    {ok, State}.

-spec handle_call(term(), {pid(), reference()}, #state{}) -> {reply, term(), #state{}}.
handle_call({create_cluster, ClusterId, NodeConfigs}, _From, State) ->
    Result = do_create_cluster(ClusterId, NodeConfigs, State),
    {reply, Result, State};

handle_call({destroy_cluster, ClusterId}, _From, State) ->
    Result = do_destroy_cluster(ClusterId, State),
    {reply, Result, State};

handle_call({upgrade_node, ClusterId, NodeId, NewVersion}, _From, State) ->
    Result = do_upgrade_node(ClusterId, NodeId, NewVersion, State),
    {reply, Result, State};

handle_call(get_cluster_status, _From, State) ->
    Status = build_cluster_status(State),
    {reply, {ok, Status}, State};

handle_call({get_node_info, NodeId}, _From, State) ->
    case maps:get(NodeId, State#state.nodes, undefined) of
        undefined ->
            {reply, {error, node_not_found}, State};
        NodeInfo ->
            {reply, {ok, NodeInfo}, State}
    end;

handle_call({register_node, NodeId, NodeInfo}, _From, State) ->
    NewState = State#state{
        nodes = maps:put(NodeId, NodeInfo, State#state.nodes)
    },
    save_state(NewState),
    {reply, ok, NewState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast({unregister_node, NodeId}, State) ->
    NewState = State#state{
        nodes = maps:remove(NodeId, State#state.nodes)
    },
    save_state(NewState),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
handle_info(tick, State) ->
    %% Process heartbeats and timeouts
    NewState = process_heartbeats(State),

    %% Schedule next tick
    erlang:send_after(?TICK_INTERVAL, self(), tick),

    {noreply, NewState};

handle_info({node_event, NodeName, Event}, State) ->
    %% Handle node events from the network
    NewState = handle_node_event(NodeName, Event, State),
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, _State) ->
    %% Save state before shutdown
    save_state(_State),
    ok.

-spec code_change(term(), #state{}, term()) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Create a cluster with the specified nodes
-spec do_create_cluster(cluster_id(), [map()], #state{}) -> {ok, cluster_id()} | {error, term()}.
do_create_cluster(ClusterId, NodeConfigs, State) ->
    case maps:is_key(ClusterId, State#state.clusters) of
        true ->
            {error, cluster_exists};
        false ->
            %% Create nodes
            Nodes = lists:map(fun(NodeConfig) ->
                create_node(ClusterId, NodeConfig, State)
            end, NodeConfigs),

            %% Create cluster info
            ClusterInfo = #cluster_info{
                id = ClusterId,
                nodes = Nodes,
                created_at = erlang:system_time(millisecond),
                version = <<"1.0.0">>
            },

            %% Update state
            NewState = State#state{
                clusters = maps:put(ClusterId, ClusterInfo, State#state.clusters),
                next_cluster_id = State#state.next_cluster_id + 1
            },

            save_state(NewState),
            {ok, ClusterId}
    end.

%% @doc Destroy a cluster and its nodes
-spec do_destroy_cluster(cluster_id(), #state{}) -> ok | {error, term()}.
do_destroy_cluster(ClusterId, State) ->
    case maps:get(ClusterId, State#state.clusters, undefined) of
        undefined ->
            {error, cluster_not_found};
        ClusterInfo ->
            %% Stop all nodes in the cluster
            lists:foreach(fun(NodeInfo) ->
                stop_node(NodeInfo)
            end, ClusterInfo#cluster_info.nodes),

            %% Remove from state
            NewState = State#state{
                clusters = maps:remove(ClusterId, State#state.clusters),
                nodes = maps_remove_keys(
                    lists:map(fun(#node_info{id = Id}) -> Id end, ClusterInfo#cluster_info.nodes),
                    State#state.nodes
                )
            },

            save_state(NewState),
            ok
    end.

%% @doc Upgrade a node
-spec do_upgrade_node(cluster_id(), node_id(), binary(), #state{}) -> ok | {error, term()}.
do_upgrade_node(ClusterId, NodeId, NewVersion, State) ->
    case maps:get(ClusterId, State#state.clusters, undefined) of
        undefined ->
            {error, cluster_not_found};
        ClusterInfo ->
            case lists:keyfind(NodeId, #node_info.id, ClusterInfo#cluster_info.nodes) of
                false ->
                    {error, node_not_found};
                NodeInfo ->
                    %% Start upgrade process
                    NewNodeInfo = NodeInfo#node_info{
                        status = upgrading,
                        version = NewVersion
                    },

                    %% Update node status
                    NewNodes = lists:keyreplace(NodeId, #node_info.id,
                        ClusterInfo#cluster_info.nodes, NewNodeInfo),

                    NewClusterInfo = ClusterInfo#cluster_info{nodes = NewNodes},

                    %% Perform actual upgrade
                    case perform_node_upgrade(NodeInfo, NewVersion) of
                        ok ->
                            %% Update to running status
                            FinalNodeInfo = NewNodeInfo#node_info{status = running},
                            FinalNodes = lists:keyreplace(NodeId, #node_info.id, NewNodes, FinalNodeInfo),
                            FinalClusterInfo = NewClusterInfo#cluster_info{nodes = FinalNodes},

                            %% Update state
                            NewState = State#state{
                                clusters = maps:put(ClusterId, FinalClusterInfo, State#state.clusters),
                                nodes = maps:put(NodeId, FinalNodeInfo, State#state.nodes)
                            },

                            save_state(NewState),
                            ok;
                        {error, Reason} ->
                            %% Mark as failed
                            FailedNodeInfo = NewNodeInfo#node_info{status = failed},
                            FailedNodes = lists:keyreplace(NodeId, #node_info.id, NewNodes, FailedNodeInfo),
                            FailedClusterInfo = NewClusterInfo#cluster_info{nodes = FailedNodes},

                            NewState = State#state{
                                clusters = maps:put(ClusterId, FailedClusterInfo, State#state.clusters),
                                nodes = maps:put(NodeId, FailedNodeInfo, State#state.nodes)
                            },

                            save_state(NewState),
                            {error, Reason}
                    end
            end
    end.

%% @doc Create a single test node
-spec create_node(cluster_id(), map(), #state{}) -> #node_info{}.
create_node(ClusterId, NodeConfig, State) ->
    NodeId = generate_node_id(),

    NodeInfo = #node_info{
        id = NodeId,
        container_id = generate_container_id(),
        node_name = generate_node_name(ClusterId, NodeId),
        node_ip = maps:get(ip, NodeConfig, <<"127.0.0.1">>),
        port = maps:get(port, NodeConfig, 8080),
        status = starting,
        version = maps:get(version, NodeConfig, <<"1.0.0">>),
        start_time = erlang:system_time(millisecond),
        last_heartbeat = erlang:system_time(millisecond)
    },

    %% Start the node (this would interact with Docker)
    start_node(NodeInfo),

    NodeInfo.

%% @doc Process node heartbeats and timeouts
-spec process_heartbeats(#state{}) -> #state{}.
process_heartbeats(State) ->
    Now = erlang:system_time(millisecond),

    %% Update last heartbeat for nodes that have sent it
    UpdatedNodes = maps:map(fun(_NodeId, NodeInfo) ->
        case NodeInfo#node_info.last_heartbeat of
            undefined -> NodeInfo;
            LastHB ->
                case Now - LastHB > ?CLUSTER_TIMEOUT of
                    true ->
                        %% Node timeout - mark as failed
                        logger:warning("Node ~p heartbeat timeout", [NodeInfo#node_info.id]),
                        NodeInfo#node_info{status = failed, last_heartbeat = undefined};
                    false ->
                        NodeInfo
                end
        end
    end, State#state.nodes),

    State#state{nodes = UpdatedNodes}.

%% @doc Handle node events
-spec handle_node_event(binary(), term(), #state{}) -> #state{}.
handle_node_event(NodeName, Event, State) ->
    %% Find the node by node name
    case find_node_by_name(NodeName, State) of
        {ok, NodeId, NodeInfo} ->
            %% Update node based on event
            NewNodeInfo = handle_node_event_type(Event, NodeInfo),

            %% Update state
            State#state{
                nodes = maps:put(NodeId, NewNodeInfo, State#state.nodes)
            };
        error ->
            %% Unknown node, create entry
            NewNodeId = generate_node_id(),
            NewNodeInfo = #node_info{
                id = NewNodeId,
                container_id = generate_container_id(),
                node_name = NodeName,
                node_ip = <<"unknown">>,
                port = 0,
                status = running,
                version = <<"unknown">>,
                start_time = erlang:system_time(millisecond),
                last_heartbeat = erlang:system_time(millisecond)
            },

            State#state{
                nodes = maps:put(NewNodeId, NewNodeInfo, State#state.nodes)
            }
    end.

%% @doc Handle specific node event types
-spec handle_node_event_type(term(), #node_info{}) -> #node_info{}.
handle_node_event_type({heartbeat, Metadata}, NodeInfo) ->
    NodeInfo#node_info{
        last_heartbeat = erlang:system_time(millisecond),
        status = running
    };

handle_node_event_type({status_changed, NewStatus}, NodeInfo) ->
    NodeInfo#node_info{status = NewStatus};

handle_node_event_type({upgrade_started, Version}, NodeInfo) ->
    NodeInfo#node_info{status = upgrading, version = Version};

handle_node_event_type({upgrade_completed, Version}, NodeInfo) ->
    NodeInfo#node_info{status = running, version = Version};

handle_node_event_type({upgrade_failed, Reason}, NodeInfo) ->
    logger:warning("Node ~p upgrade failed: ~p", [NodeInfo#node_info.id, Reason]),
    NodeInfo#node_info{status = failed};

handle_node_event_type(Event, NodeInfo) ->
    logger:debug("Unhandled node event: ~p", [Event]),
    NodeInfo.

%% @doc Build cluster status for API response
-spec build_cluster_status(#state{}) -> map().
build_cluster_status(State) ->
    Clusters = maps:map(fun(_ClusterId, ClusterInfo) ->
        #{
            id => ClusterInfo#cluster_info.id,
            created_at => ClusterInfo#cluster_info.created_at,
            version => ClusterInfo#cluster_info.version,
            nodes => build_nodes_status(ClusterInfo#cluster_info.nodes)
        }
    end, State#state.clusters),

    #{
        clusters => Clusters,
        total_clusters => maps:size(State#state.clusters),
        total_nodes => maps:size(State#state.nodes)
    }.

%% @doc Build nodes status list
-spec build_nodes_status([#node_info{}]) -> [map()].
build_nodes_status(Nodes) ->
    lists:map(fun(NodeInfo) ->
        #{
            id => NodeInfo#node_info.id,
            container_id => NodeInfo#node_info.container_id,
            node_name => NodeInfo#node_info.node_name,
            node_ip => NodeInfo#node_info.node_ip,
            port => NodeInfo#node_info.port,
            status => NodeInfo#node_info.status,
            version => NodeInfo#node_info.version,
            start_time => NodeInfo#node_info.start_time,
            last_heartbeat => NodeInfo#node_info.last_heartbeat
        }
    end, Nodes).

%% @doc Find node by node name
-spec find_node_by_name(binary(), #state{}) -> {ok, node_id(), #node_info{}} | error.
find_node_by_name(NodeName, State) ->
    case lists:filtermap(fun(NodeInfo) ->
        case NodeInfo#node_info.node_name of
            NodeName -> {true, {NodeInfo#node_info.id, NodeInfo}};
            _ -> false
        end
    end, maps:values(State#state.nodes)) of
        [{NodeId, NodeInfo}] -> {ok, NodeId, NodeInfo};
        [] -> error
    end.

%% @doc Start a test node (would interact with Docker)
-spec start_node(#node_info{}) -> ok | {error, term()}.
start_node(NodeInfo) ->
    %% This would actually start a Docker container
    %% For now, just simulate
    logger:info("Starting node ~p at ~p:~p", [
        NodeInfo#node_info.node_name,
        NodeInfo#node_info.node_ip,
        NodeInfo#node_info.port
    ]),
    ok.

%% @doc Stop a test node
-spec stop_node(#node_info{}) -> ok.
stop_node(NodeInfo) ->
    logger:info("Stopping node ~p", [NodeInfo#node_info.node_name]),
    ok.

%% @doc Perform node upgrade (would interact with Docker)
-spec perform_node_upgrade(#node_info{}, binary()) -> ok | {error, term()}.
perform_node_upgrade(NodeInfo, NewVersion) ->
    logger:info("Upgrading node ~p to version ~p", [
        NodeInfo#node_info.node_name,
        NewVersion
    ]),

    %% Simulate upgrade process
    timer:sleep(2000),

    %% Simulate occasional failure for testing
    case crypto:strong_rand_bytes(1) of
        <<0>> -> ok;
        _ -> {error, upgrade_failed}
    end.

%% @doc Generate unique cluster ID
-spec generate_cluster_id() -> binary().
generate_cluster_id() ->
    Now = erlang:system_time(millisecond),
    <<"cluster_", (integer_to_binary(Now))/binary>>.

%% @doc Generate unique node ID
-spec generate_node_id() -> binary().
generate_node_id() ->
    Now = erlang:system_time(millisecond),
    <<"node_", (integer_to_binary(Now))/binary>>.

%% @doc Generate unique container ID
-spec generate_container_id() -> binary().
generate_container_id() ->
    Now = erlang:system_time(millisecond),
    <<"container_", (integer_to_binary(Now))/binary>>.

%% @doc Generate node name for cluster
-spec generate_node_name(cluster_id(), node_id()) -> binary().
generate_node_name(ClusterId, NodeId) ->
    <<ClusterId/binary, "@", NodeId/binary>>.

%% @doc Save state to persistent storage
-spec save_state(#state{}) -> ok.
save_state(_State) ->
    %% In production, this would save to Mnesia, file, or database
    ok.

%% @doc Load state from persistent storage
-spec load_state() -> #state{}.
load_state() ->
    %% In production, this would load from Mnesia, file, or database
    #state{}.

%% @doc Helper to remove multiple keys from map
-spec maps_remove_keys([term()], map()) -> map().
maps_remove_keys(Keys, Map) ->
    lists:foldl(fun(Key, Acc) -> maps:remove(Key, Acc) end, Map, Keys).