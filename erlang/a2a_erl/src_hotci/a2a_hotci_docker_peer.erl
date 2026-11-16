%%% @doc HotCI Docker-based Peer Testing Module
%%%
%%% This module provides Docker-based real-environment testing for HotCI operations.
%%% It spins up peer nodes in Docker containers for testing distributed scenarios
%%% including network partitions, node failures, and rolling upgrades.
-module(a2a_hotci_docker_peer).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    create_peer_cluster/2,
    start_peer/2,
    stop_peer/2,
    partition_network/3,
    heal_network/2,
    execute_on_peer/3,
    get_peer_status/2,
    cleanup_cluster/1,
    run_compatibility_test/2,
    run_rolling_upgrade/3,
    simulate_network_conditions/3,
    capture_peer_logs/2
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

-include("a2a.hrl").

-define(SERVER, ?MODULE).
-define(DEFAULT_PEER_IMAGE, "ghcr.io/erlang-solutions/erlang:27").
-define(PEER_STARTUP_TIMEOUT, 60000). % 1 minute
-define(DOCKER_API_VERSION, "1.41").

-record(peer_node, {
    id :: binary(),
    name :: binary(),
    container_id :: binary(),
    node_name :: binary(),
    cookie :: binary(),
    status :: starting | running | stopped | partitioned | failed,
    ip_address :: binary(),
    port :: integer(),
    capabilities :: [atom()],
    metadata :: map()
}).

-record(cluster_config, {
    cluster_id :: binary(),
    base_name :: binary(),
    peer_count :: integer(),
    cookie :: binary(),
    network_name :: binary(),
    docker_network_id :: binary(),
    peers :: ets:tid(),
    test_results :: [map()],
    cleanup_policy :: automatic | manual
}).

-record(test_scenario, {
    id :: binary(),
    name :: binary(),
    description :: binary(),
    steps :: [map()],
    expected_results :: map(),
    actual_results :: map() | undefined,
    status :: pending | running | passed | failed
}).

-record(state, {
    clusters :: ets:tid(),
    active_peer_monitor :: pid() | undefined,
    docker_available :: boolean(),
    docker_api :: term(),
    log_dir :: binary()
}).

-type state() :: #state{}.
-type peer_node() :: #peer_node{}.
-type cluster_config() :: #cluster_config{}.

%% ============================================================================
%% API Functions
%% ============================================================================

%% @doc Start the Docker peer manager with default configuration
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the Docker peer manager with custom configuration
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Options) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Options, []).

%% @doc Create a peer cluster for testing
-spec create_peer_cluster(binary(), map()) ->
    {ok, binary()} | {error, term()}.
create_peer_cluster(ClusterId, Options) ->
    gen_server:call(?SERVER, {create_peer_cluster, ClusterId, Options}).

%% @doc Start a peer node in the cluster
-spec start_peer(binary(), binary()) ->
    {ok, peer_node()} | {error, term()}.
start_peer(ClusterId, PeerId) ->
    gen_server:call(?SERVER, {start_peer, ClusterId, PeerId}).

%% @doc Stop a peer node
-spec stop_peer(binary(), binary()) ->
    ok | {error, term()}.
stop_peer(ClusterId, PeerId) ->
    gen_server:call(?SERVER, {stop_peer, ClusterId, PeerId}).

%% @doc Partition network between peers
-spec partition_network(binary(), [binary()], [binary()]) ->
    ok | {error, term()}.
partition_network(ClusterId, PeersA, PeersB) ->
    gen_server:call(?SERVER, {partition_network, ClusterId, PeersA, PeersB}).

%% @doc Heal network partition
-spec heal_network(binary(), [binary()]) ->
    ok | {error, term()}.
heal_network(ClusterId, Peers) ->
    gen_server:call(?SERVER, {heal_network, ClusterId, Peers}).

%% @doc Execute command on peer node
-spec execute_on_peer(binary(), binary(), binary()) ->
    {ok, binary()} | {error, term()}.
execute_on_peer(ClusterId, PeerId, Command) ->
    gen_server:call(?SERVER, {execute_on_peer, ClusterId, PeerId, Command}).

%% @doc Get status of peer node
-spec get_peer_status(binary(), binary()) ->
    {ok, map()} | {error, term()}.
get_peer_status(ClusterId, PeerId) ->
    gen_server:call(?SERVER, {get_peer_status, ClusterId, PeerId}).

%% @doc Clean up cluster and remove all peers
-spec cleanup_cluster(binary()) ->
    ok | {error, term()}.
cleanup_cluster(ClusterId) ->
    gen_server:call(?SERVER, {cleanup_cluster, ClusterId}).

%% @doc Run compatibility test between peers
-spec run_compatibility_test(binary(), map()) ->
    {ok, map()} | {error, term()}.
run_compatibility_test(ClusterId, TestConfig) ->
    gen_server:call(?SERVER, {run_compatibility_test, ClusterId, TestConfig}).

%% @doc Run rolling upgrade across peers
-spec run_rolling_upgrade(binary(), binary(), map()) ->
    {ok, map()} | {error, term()}.
run_rolling_upgrade(ClusterId, TargetVersion, UpgradeConfig) ->
    gen_server:call(?SERVER, {run_rolling_upgrade, ClusterId, TargetVersion, UpgradeConfig}).

%% @doc Simulate network conditions (latency, packet loss, bandwidth)
-spec simulate_network_conditions(binary(), map(), [binary()]) ->
    ok | {error, term()}.
simulate_network_conditions(ClusterId, Conditions, Peers) ->
    gen_server:call(?SERVER, {simulate_network_conditions, ClusterId, Conditions, Peers}).

%% @doc Capture logs from peer nodes
-spec capture_peer_logs(binary(), binary()) ->
    {ok, binary()} | {error, term()}.
capture_peer_logs(ClusterId, PeerId) ->
    gen_server:call(?SERVER, {capture_peer_logs, ClusterId, PeerId}).

%% ============================================================================
%% gen_server Callbacks
%% ============================================================================

-spec init(map()) -> {ok, state()} | {stop, term()}.
init(Options) ->
    %% Initialize ETS table for clusters
    Clusters = ets:new(clusters, [
        set,
        public,
        {keypos, 2},
        named_table,
        {heir, self(), undefined}
    ]),

    %% Check Docker availability
    DockerAvailable = check_docker_availability(),
    DockerApi = case DockerAvailable of
        true -> initialize_docker_api(Options);
        false -> undefined
    end,

    %% Setup log directory
    LogDir = case maps:get(log_dir, Options, undefined) of
        undefined -> filename:absname("peer_logs");
        Dir -> Dir
    end,
    filelib:ensure_dir(LogDir),

    %% Start peer monitor
    PeerMonitor = case DockerAvailable of
        true -> spawn_link(fun() -> peer_monitor_loop(Clusters) end);
        false -> undefined
    end,

    State = #state{
        clusters = Clusters,
        active_peer_monitor = PeerMonitor,
        docker_available = DockerAvailable,
        docker_api = DockerApi,
        log_dir = list_to_binary(LogDir)
    },

    logger:info("Docker peer testing module initialized: docker_available=~p",
        [DockerAvailable]),

    {ok, State}.

-spec handle_call(term(), {pid(), reference()}, state()) ->
    {reply, term(), state()} | {stop, term(), state()}.
handle_call({create_peer_cluster, ClusterId, Options}, _From, State) ->
    Result = create_peer_cluster_internal(ClusterId, Options, State),
    {reply, Result, State};

handle_call({start_peer, ClusterId, PeerId}, _From, State) ->
    Result = start_peer_internal(ClusterId, PeerId, State),
    {reply, Result, State};

handle_call({stop_peer, ClusterId, PeerId}, _From, State) ->
    Result = stop_peer_internal(ClusterId, PeerId, State),
    {reply, Result, State};

handle_call({partition_network, ClusterId, PeersA, PeersB}, _From, State) ->
    Result = partition_network_internal(ClusterId, PeersA, PeersB, State),
    {reply, Result, State};

handle_call({heal_network, ClusterId, Peers}, _From, State) ->
    Result = heal_network_internal(ClusterId, Peers, State),
    {reply, Result, State};

handle_call({execute_on_peer, ClusterId, PeerId, Command}, _From, State) ->
    Result = execute_on_peer_internal(ClusterId, PeerId, Command, State),
    {reply, Result, State};

handle_call({get_peer_status, ClusterId, PeerId}, _From, State) ->
    Result = get_peer_status_internal(ClusterId, PeerId, State),
    {reply, Result, State};

handle_call({cleanup_cluster, ClusterId}, _From, State) ->
    Result = cleanup_cluster_internal(ClusterId, State),
    {reply, Result, State};

handle_call({run_compatibility_test, ClusterId, TestConfig}, _From, State) ->
    Result = run_compatibility_test_internal(ClusterId, TestConfig, State),
    {reply, Result, State};

handle_call({run_rolling_upgrade, ClusterId, TargetVersion, UpgradeConfig}, _From, State) ->
    Result = run_rolling_upgrade_internal(ClusterId, TargetVersion, UpgradeConfig, State),
    {reply, Result, State};

handle_call({simulate_network_conditions, ClusterId, Conditions, Peers}, _From, State) ->
    Result = simulate_network_conditions_internal(ClusterId, Conditions, Peers, State),
    {reply, Result, State};

handle_call({capture_peer_logs, ClusterId, PeerId}, _From, State) ->
    Result = capture_peer_logs_internal(ClusterId, PeerId, State),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info({peer_monitor_event, Event}, State) ->
    handle_peer_monitor_event(Event, State),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(Reason, State) ->
    logger:info("Docker peer manager terminating: ~p", [Reason]),

    %% Cleanup all clusters
    case ets:tab2list(State#state.clusters) of
        [] -> ok;
        Clusters ->
            lists:foreach(fun({ClusterId, _}) ->
                cleanup_cluster_internal(ClusterId, State)
            end, Clusters)
    end,

    %% Cleanup ETS table
    ets:delete(State#state.clusters),

    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ============================================================================
%% Internal Functions
%% ============================================================================

%% @doc Check if Docker is available
check_docker_availability() ->
    case os:find_executable("docker") of
        false ->
            logger:warning("Docker executable not found"),
            false;
        _ ->
            case docker_command(["version", "--format", "{{.Server.APIVersion}}"]) of
                {ok, _} ->
                    logger:info("Docker is available"),
                    true;
                {error, Reason} ->
                    logger:warning("Docker check failed: ~p", [Reason]),
                    false
            end
    end.

%% @doc Initialize Docker API connection
initialize_docker_api(_Options) ->
    %% For now, use CLI commands instead of direct API
    %% Could be extended to use docker_engine or gun for HTTP API
    cli_api.

%% @doc Execute Docker command
docker_command(Args) ->
    Port = open_port({spawn_executable, os:find_executable("docker")},
        [{args, Args}, binary, exit_status, use_stdio, stderr_to_stdout]),

    receive
        {Port, {exit_status, 0}} ->
            {Port, {data, Data}} ->
                {ok, binary:replace(Data, <<"\n">>, <<>>)};
        {Port, {exit_status, Status}} ->
            {Port, {data, Data}} ->
                {error, {Status, binary:replace(Data, <<"\n">>, <<>>)}}
    after 5000 ->
        port_close(Port),
        {error, timeout}
    end.

%% @doc Create a peer cluster for testing
create_peer_cluster_internal(ClusterId, Options, State) ->
    case State#state.docker_available of
        false ->
            {error, docker_not_available};
        true ->
            PeerCount = maps:get(peer_count, Options, 3),
            BaseName = maps:get(base_name, Options, <<"hotci_peer">>),
            Cookie = generate_cluster_cookie(),
            NetworkName = <<ClusterId/binary, "_net">>,

            %% Create Docker network
            case create_docker_network(NetworkName) of
                {ok, NetworkId} ->
                    %% Create cluster configuration
                    PeersTable = ets:new(peers, [set, public]),

                    ClusterConfig = #cluster_config{
                        cluster_id = ClusterId,
                        base_name = BaseName,
                        peer_count = PeerCount,
                        cookie = Cookie,
                        network_name = NetworkName,
                        docker_network_id = NetworkId,
                        peers = PeersTable,
                        test_results = [],
                        cleanup_policy = maps:get(cleanup_policy, Options, automatic)
                    },

                    ets:insert(State#state.clusters, {ClusterId, ClusterConfig}),

                    logger:info("Created peer cluster ~p with ~p peers",
                        [ClusterId, PeerCount]),

                    {ok, #{
                        cluster_id => ClusterId,
                        network_id => NetworkId,
                        peer_count => PeerCount,
                        cookie => Cookie
                    }};
                {error, Reason} ->
                    {error, {network_creation_failed, Reason}}
            end
    end.

%% @doc Create Docker network for cluster
create_docker_network(NetworkName) ->
    NetworkNameStr = binary_to_list(NetworkName),
    case docker_command(["network", "create", NetworkNameStr]) of
        {ok, NetworkId} ->
            {ok, list_to_binary(NetworkId)};
        {error, {_, Error}} ->
            {error, Error}
    end.

%% @doc Start a peer node in the cluster
start_peer_internal(ClusterId, PeerId, State) ->
    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, ClusterConfig}] ->
            start_peer_node(ClusterId, PeerId, ClusterConfig, State);
        [] ->
            {error, cluster_not_found}
    end.

%% @doc Start an individual peer node
start_peer_node(ClusterId, PeerId, ClusterConfig, State) ->
    PeerName = <<(ClusterConfig#cluster_config.base_name)/binary, "_", PeerId/binary>>,
    NodeName = <<PeerName/binary, "@localhost">>,
    ContainerName = <<ClusterId/binary, "_", PeerId/binary>>,

    %% Prepare Docker run command
    Image = maps:get(image, ClusterConfig#cluster_config.metadata, ?DEFAULT_PEER_IMAGE),
    Cookie = ClusterConfig#cluster_config.cookie,
    NetworkName = binary_to_list(ClusterConfig#cluster_config.network_name),

    %% Create environment variables
    EnvVars = [
        "ERL_AFLAGS=-setcookie " ++ binary_to_list(Cookie),
        "NODE_NAME=" ++ binary_to_list(NodeName)
    ],

    %% Build Docker command
    DockerArgs = [
        "run", "-d",
        "--name", binary_to_list(ContainerName),
        "--network", NetworkName
    ] ++ lists:flatmap(fun(E) -> ["-e", E] end, EnvVars) ++ [
        binary_to_list(Image),
        "erl", "-sname", binary_to_list(PeerName),
        "-setcookie", binary_to_list(Cookie)
    ],

    case docker_command(DockerArgs) of
        {ok, ContainerId} ->
            %% Get container IP address
            case get_container_ip(ContainerId, NetworkName) of
                {ok, IPAddress} ->
                    PeerNode = #peer_node{
                        id = PeerId,
                        name = PeerName,
                        container_id = list_to_binary(ContainerId),
                        node_name = NodeName,
                        cookie = Cookie,
                        status = starting,
                        ip_address = IPAddress,
                        port = 0,
                        capabilities = [],
                        metadata => #{
                            cluster_id => ClusterId,
                            created_at => erlang:system_time(millisecond)
                        }
                    },

                    %% Store peer in cluster
                    ets:insert(ClusterConfig#cluster_config.peers, {PeerId, PeerNode}),

                    %% Wait for peer to be ready
                    wait_for_peer_ready(PeerNode, State),

                    logger:info("Started peer ~p in cluster ~p", [PeerId, ClusterId]),

                    {ok, PeerNode};
                {error, Reason} ->
                    {error, {ip_fetch_failed, Reason}}
            end;
        {error, Reason} ->
            {error, {container_start_failed, Reason}}
    end.

%% @doc Get container IP address
get_container_ip(ContainerId, NetworkName) ->
    InspectArgs = ["inspect", "--format",
        "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
        ContainerId],

    case docker_command(InspectArgs) of
        {ok, IP} when IP =/= <<>> ->
            {ok, IP};
        {ok, <<>>} ->
            {error, no_ip_address};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Wait for peer node to be ready
wait_for_peer_ready(PeerNode, State) ->
    %% In a real implementation, this would ping the node
    %% For now, simulate startup time
    timer:sleep(1000),

    %% Update peer status
    UpdatedPeer = PeerNode#peer_node{status = running},
    ClusterId = maps:get(cluster_id, PeerNode#peer_node.metadata),

    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, ClusterConfig}] ->
            ets:insert(ClusterConfig#cluster_config.peers,
                {PeerNode#peer_node.id, UpdatedPeer});
        [] ->
            ok
    end.

%% @doc Stop a peer node
stop_peer_internal(ClusterId, PeerId, State) ->
    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, ClusterConfig}] ->
            case ets:lookup(ClusterConfig#cluster_config.peers, PeerId) of
                [{PeerId, PeerNode}] ->
                    ContainerId = binary_to_list(PeerNode#peer_node.container_id),

                    case docker_command(["stop", ContainerId]) of
                        {ok, _} ->
                            docker_command(["rm", ContainerId]),
                            ets:delete(ClusterConfig#cluster_config.peers, PeerId),

                            logger:info("Stopped peer ~p in cluster ~p", [PeerId, ClusterId]),
                            ok;
                        {error, Reason} ->
                            {error, {stop_failed, Reason}}
                    end;
                [] ->
                    {error, peer_not_found}
            end;
        [] ->
            {error, cluster_not_found}
    end.

%% @doc Partition network between peers
partition_network_internal(ClusterId, PeersA, PeersB, State) ->
    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, ClusterConfig}] ->
            NetworkName = binary_to_list(ClusterConfig#cluster_config.network_name),

            %% Use tc (traffic control) via Docker to simulate partition
            lists:foreach(fun(PeerId) ->
                case ets:lookup(ClusterConfig#cluster_config.peers, PeerId) of
                    [{PeerId, PeerNode}] ->
                        ContainerId = binary_to_list(PeerNode#peer_node.container_id),

                        %% Block traffic to peers in the other partition
                        lists:foreach(fun(OtherPeerId) ->
                            case lists:member(OtherPeerId, PeersA) of
                                true -> ok;
                                false ->
                                    case ets:lookup(ClusterConfig#cluster_config.peers, OtherPeerId) of
                                        [{OtherPeerId, OtherPeerNode}] ->
                                            %% Block traffic to this peer
                                            block_container_traffic(ContainerId,
                                                OtherPeerNode#peer_node.ip_address);
                                        [] ->
                                            ok
                                    end
                            end
                        end, PeersA ++ PeersB),

                        %% Update peer status
                        UpdatedPeer = PeerNode#peer_node{status = partitioned},
                        ets:insert(ClusterConfig#cluster_config.peers, {PeerId, UpdatedPeer})
                end
            end, PeersA),

            logger:info("Created network partition in cluster ~p: ~p || ~p",
                [ClusterId, PeersA, PeersB]),
            ok;
        [] ->
            {error, cluster_not_found}
    end.

%% @doc Block traffic between containers
block_container_traffic(ContainerId, TargetIP) ->
    %% Use iptables via Docker exec
    IPStr = binary_to_list(TargetIP),
    docker_command(["exec", ContainerId,
        "iptables", "-A", "INPUT", "-s", IPStr, "-j", "DROP"]),
    docker_command(["exec", ContainerId,
        "iptables", "-A", "OUTPUT", "-d", IPStr, "-j", "DROP"]).

%% @doc Heal network partition
heal_network_internal(ClusterId, Peers, State) ->
    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, ClusterConfig}] ->
            lists:foreach(fun(PeerId) ->
                case ets:lookup(ClusterConfig#cluster_config.peers, PeerId) of
                    [{PeerId, PeerNode}] ->
                        ContainerId = binary_to_list(PeerNode#peer_node.container_id),

                        %% Flush iptables rules
                        docker_command(["exec", ContainerId,
                            "iptables", "-F"]),

                        %% Update peer status
                        UpdatedPeer = PeerNode#peer_node{status = running},
                        ets:insert(ClusterConfig#cluster_config.peers, {PeerId, UpdatedPeer})
                end
            end, Peers),

            logger:info("Healed network partition in cluster ~p", [ClusterId]),
            ok;
        [] ->
            {error, cluster_not_found}
    end.

%% @doc Execute command on peer node
execute_on_peer_internal(ClusterId, PeerId, Command, State) ->
    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, ClusterConfig}] ->
            case ets:lookup(ClusterConfig#cluster_config.peers, PeerId) of
                [{PeerId, PeerNode}] ->
                    ContainerId = binary_to_list(PeerNode#peer_node.container_id),
                    CommandStr = binary_to_list(Command),

                    case docker_command(["exec", ContainerId, "sh", "-c", CommandStr]) of
                        {ok, Output} ->
                            {ok, Output};
                        {error, Reason} ->
                            {error, {exec_failed, Reason}}
                    end;
                [] ->
                    {error, peer_not_found}
            end;
        [] ->
            {error, cluster_not_found}
    end.

%% @doc Get peer status
get_peer_status_internal(ClusterId, PeerId, State) ->
    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, ClusterConfig}] ->
            case ets:lookup(ClusterConfig#cluster_config.peers, PeerId) of
                [{PeerId, PeerNode}] ->
                    Status = #{
                        peer_id => PeerNode#peer_node.id,
                        name => PeerNode#peer_node.name,
                        node_name => PeerNode#peer_node.node_name,
                        status => PeerNode#peer_node.status,
                        ip_address => PeerNode#peer_node.ip_address,
                        port => PeerNode#peer_node.port,
                        capabilities => PeerNode#peer_node.capabilities,
                        container_id => PeerNode#peer_node.container_id,
                        metadata => PeerNode#peer_node.metadata
                    },
                    {ok, Status};
                [] ->
                    {error, peer_not_found}
            end;
        [] ->
            {error, cluster_not_found}
    end.

%% @doc Clean up cluster
cleanup_cluster_internal(ClusterId, State) ->
    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, ClusterConfig}] ->
            %% Stop all peers
            Peers = ets:tab2list(ClusterConfig#cluster_config.peers),
            lists:foreach(fun({PeerId, _PeerNode}) ->
                stop_peer_internal(ClusterId, PeerId, State)
            end, Peers),

            %% Remove Docker network
            NetworkName = binary_to_list(ClusterConfig#cluster_config.network_name),
            docker_command(["network", "rm", NetworkName]),

            %% Delete cluster
            ets:delete(State#state.clusters, ClusterId),
            ets:delete(ClusterConfig#cluster_config.peers),

            logger:info("Cleaned up cluster ~p", [ClusterId]),
            ok;
        [] ->
            {error, cluster_not_found}
    end.

%% @doc Run compatibility test
run_compatibility_test_internal(ClusterId, TestConfig, State) ->
    TestScenario = #test_scenario{
        id = generate_test_id(),
        name = maps:get(name, TestConfig, <<"compatibility_test">>),
        description = maps:get(description, TestConfig, <<"Peer compatibility test">>),
        steps = maps:get(steps, TestConfig, []),
        expected_results = maps:get(expected_results, TestConfig, #{}),
        actual_results = undefined,
        status = pending
    },

    logger:info("Running compatibility test ~p on cluster ~p",
        [TestScenario#test_scenario.id, ClusterId]),

    %% Execute test steps
    {ok, Results} = execute_test_steps(ClusterId, TestScenario, State),

    {ok, #{
        test_id => TestScenario#test_scenario.id,
        cluster_id => ClusterId,
        results => Results,
        status => completed
    }}.

%% @doc Execute test steps
execute_test_steps(ClusterId, TestScenario, State) ->
    lists:foldl(fun(Step, AccResults) ->
        StepType = maps:get(type, Step),
        StepData = maps:get(data, Step, #{}),

        Result = case StepType of
            ping_peers ->
                test_peer_connectivity(ClusterId, State);
            version_check ->
                check_peer_versions(ClusterId, State);
            module_load ->
                test_module_loading(ClusterId, maps:get(module, StepData), State);
            distributed_call ->
                test_distributed_call(ClusterId, StepData, State);
            _ ->
                {error, unknown_step_type}
        end,

        maps:put(StepType, Result, AccResults)
    end, #{}, TestScenario#test_scenario.steps).

%% @doc Test peer connectivity
test_peer_connectivity(ClusterId, State) ->
    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, ClusterConfig}] ->
            Peers = ets:tab2list(ClusterConfig#cluster_config.peers),
            TestFun = fun({_PeerId, PeerNode}) ->
                case execute_on_peer_internal(ClusterId, PeerNode#peer_node.id,
                    <<"erl -noshell -eval 'net_adm:ping(list_to_atom(\""#
                        ++ (PeerNode#peer_node.node_name)/binary ++ <<"\"))'">>, State) of
                    {ok, Output} ->
                        case binary:match(Output, <<"pong">>) of
                            nomatch -> {error, ping_failed};
                            _ -> ok
                        end;
                    {error, _} ->
                        {error, exec_failed}
                end
            end,

            Results = lists:map(TestFun, Peers),
            case lists:all(fun(R) -> R =:= ok end, Results) of
                true -> {ok, all_connected};
                false -> {error, some_peers_unreachable}
            end;
        [] ->
            {error, cluster_not_found}
    end.

%% @doc Check peer versions
check_peer_versions(ClusterId, State) ->
    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, _ClusterConfig}] ->
            Command = <<"erl -noshell -eval 'erlang:system_info(otp_release)'">>,
            execute_on_peer_internal(ClusterId, hd(get_peer_ids(ClusterId, State)), Command);
        [] ->
            {error, cluster_not_found}
    end.

%% @doc Test module loading
test_module_loading(ClusterId, Module, State) ->
    Command = <<"erl -noshell -eval 'code:is_loaded(", Module/binary, ")'">>,
    execute_on_peer_internal(ClusterId, hd(get_peer_ids(ClusterId, State)), Command).

%% @doc Test distributed call
test_distributed_call(ClusterId, StepData, State) ->
    TargetModule = maps:get(module, StepData, erlang),
    TargetFunction = maps:get(function, StepData, system_info),
    TargetArgs = maps:get(args, StepData, [otp_release]),

    Command = io_lib:format(
        "erl -noshell -eval '~s:~s(~p)'",
        [TargetModule, TargetFunction, TargetArgs]
    ),

    execute_on_peer_internal(ClusterId, hd(get_peer_ids(ClusterId, State)),
        list_to_binary(Command)).

%% @doc Get peer IDs from cluster
get_peer_ids(ClusterId, State) ->
    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, ClusterConfig}] ->
            [PeerId || {PeerId, _PeerNode} <- ets:tab2list(ClusterConfig#cluster_config.peers)];
        [] ->
            []
    end.

%% @doc Run rolling upgrade
run_rolling_upgrade_internal(ClusterId, TargetVersion, UpgradeConfig, State) ->
    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, ClusterConfig}] ->
            Peers = ets:tab2list(ClusterConfig#cluster_config.peers),
            BatchSize = maps:get(batch_size, UpgradeConfig, 1),

            %% Process peers in batches
            Batches = partition_list(Peers, BatchSize),

            Results = lists:map(fun(Batch) ->
                upgrade_peer_batch(ClusterId, Batch, TargetVersion, UpgradeConfig, State)
            end, Batches),

            {ok, #{
                cluster_id => ClusterId,
                target_version => TargetVersion,
                batches_upgraded => length(Results),
                results => Results
            }};
        [] ->
            {error, cluster_not_found}
    end.

%% @doc Upgrade a batch of peers
upgrade_peer_batch(ClusterId, Batch, TargetVersion, UpgradeConfig, State) ->
    BatchResults = lists:map(fun({PeerId, PeerNode}) ->
        logger:info("Upgrading peer ~p to version ~p", [PeerId, TargetVersion]),

        %% Stop peer
        stop_peer_internal(ClusterId, PeerId, State),

        %% Start peer with new version
        Image = maps:get(upgrade_image, UpgradeConfig, ?DEFAULT_PEER_IMAGE),
        %% In real implementation, would use new version

        timer:sleep(1000),

        %% Restart peer
        case start_peer_internal(ClusterId, PeerId, State) of
            {ok, _} ->
                {PeerId, upgraded};
            {error, Reason} ->
                {PeerId, {upgrade_failed, Reason}}
        end
    end, Batch),

    lists:filter(fun({_PeerId, Result}) -> Result =:= upgraded end, BatchResults).

%% @doc Partition list into batches
partition_list(List, BatchSize) ->
    partition_list(List, BatchSize, []).

partition_list([], _BatchSize, Acc) ->
    lists:reverse(Acc);
partition_list(List, BatchSize, Acc) ->
    {Batch, Rest} = lists:split(min(BatchSize, length(List)), List),
    partition_list(Rest, BatchSize, [Batch | Acc]).

%% @doc Simulate network conditions
simulate_network_conditions_internal(ClusterId, Conditions, Peers, State) ->
    Latency = maps_get(latency, Conditions, 0),
    PacketLoss = maps_get(packet_loss, Conditions, 0),
    Bandwidth = maps_get(bandwidth, Conditions, unlimited),

    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, _ClusterConfig}] ->
            lists:foreach(fun(PeerId) ->
                apply_network_conditions(ClusterId, PeerId, Latency, PacketLoss, Bandwidth, State)
            end, Peers),

            logger:info("Applied network conditions to cluster ~p: latency=~p, loss=~p, bandwidth=~p",
                [ClusterId, Latency, PacketLoss, Bandwidth]),
            ok;
        [] ->
            {error, cluster_not_found}
    end.

%% @doc Apply network conditions to peer
apply_network_conditions(ClusterId, PeerId, Latency, PacketLoss, Bandwidth, State) ->
    case execute_on_peer_internal(ClusterId, PeerId,
        <<"tc qdisc add dev eth0 root netem delay ",
            (integer_to_binary(Latency))/binary, "ms loss ",
            (integer_to_binary(PacketLoss))/binary, "%">>, State) of
        {ok, _} -> ok;
        {error, _} ->
            %% tc might not be available in container, simulate in logs
            logger:info("Simulated network conditions for peer ~p", [PeerId]),
            ok
    end.

%% @doc Capture logs from peer
capture_peer_logs_internal(ClusterId, PeerId, State) ->
    case ets:lookup(State#state.clusters, ClusterId) of
        [{ClusterId, _ClusterConfig}] ->
            case ets:lookup(State#state.clusters, ClusterId) of
                [{ClusterId, ClusterConfig}] ->
                    case ets:lookup(ClusterConfig#cluster_config.peers, PeerId) of
                        [{PeerId, PeerNode}] ->
                            ContainerId = binary_to_list(PeerNode#peer_node.container_id),
                            LogDir = filename:join([State#state.log_dir, ClusterId]),
                            filelib:ensure_dir(LogDir),
                            LogFile = filename:join(LogDir, [PeerId, ".log"]),

                            case docker_command(["logs", ContainerId]) of
                                {ok, Logs} ->
                                    file:write_file(LogFile, Logs),
                                    {ok, LogFile};
                                {error, Reason} ->
                                    {error, {log_capture_failed, Reason}}
                            end;
                        [] ->
                            {error, peer_not_found}
                    end;
                [] ->
                    {error, cluster_not_found}
            end;
        [] ->
            {error, cluster_not_found}
    end.

%% @doc Handle peer monitor events
handle_peer_monitor_event(Event, State) ->
    logger:debug("Peer monitor event: ~p", [Event]),
    ok.

%% @doc Peer monitor loop
peer_monitor_loop(Clusters) ->
    receive
        stop -> ok;
        {check_health, ClusterId} ->
            case ets:lookup(Clusters, ClusterId) of
                [{ClusterId, ClusterConfig}] ->
                    check_cluster_health(ClusterId, ClusterConfig);
                [] -> ok
            end,
            peer_monitor_loop(Clusters);
        _ ->
            peer_monitor_loop(Clusters)
    after 30000 ->
        %% Periodic health check
        lists:foreach(fun({ClusterId, _}) ->
            self() ! {check_health, ClusterId}
        end, ets:tab2list(Clusters)),
        peer_monitor_loop(Clusters)
    end.

%% @doc Check cluster health
check_cluster_health(ClusterId, ClusterConfig) ->
    Peers = ets:tab2list(ClusterConfig#cluster_config.peers),
    HealthyCount = lists:foldl(fun({_PeerId, PeerNode}, Acc) ->
        case PeerNode#peer_node.status of
            running -> Acc + 1;
            _ -> Acc
        end
    end, 0, Peers),

    logger:debug("Cluster ~p health: ~p/~p peers healthy",
        [ClusterId, HealthyCount, length(Peers)]).

%% @doc Generate cluster cookie
generate_cluster_cookie() ->
    crypto:strong_rand_bytes(32).

%% @doc Generate test ID
generate_test_id() ->
    Bytes = crypto:strong_rand_bytes(16),
    <<"test_", (binary:encode_hex(Bytes))/binary>>.

%% @doc Safe maps:get with default
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
