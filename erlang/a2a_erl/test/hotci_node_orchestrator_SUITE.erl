%%% @doc HotCI Node Orchestrator Test Suite
%%%
%%% Comprehensive test suite for the HotCI node orchestrator,
/// validating multi-node container orchestration and cluster management.
-module(hotci_node_orchestrator_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("../include/hotci.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    test_cluster_creation/1,
    test_node_creation/1,
    test_node_lifecycle/1,
    test_cluster_destruction/1,
    test_upgrade_orchestration/1,
    test_cluster_status/1,
    test_node_registration/1,
    test_node_unregistration/1,
    test_cluster_scale/1,
    test_error_handling/1
]).

%%% ============================================================================
%%% CT Callbacks
%%% ============================================================================

all() ->
    [
        test_cluster_creation,
        test_node_creation,
        test_node_lifecycle,
        test_cluster_destruction,
        test_upgrade_orchestration,
        test_cluster_status,
        test_node_registration,
        test_node_unregistration,
        test_cluster_scale,
        test_error_handling
    ].

init_per_suite(Config) ->
    %% Start HotCI services
    {ok, _} = hotci_supervisor:start_link(),

    %% Wait for services to be ready
    timer:sleep(2000),

    %% Initialize test data
    TestClusterId = <<"test-cluster-001">>,
    TestNodes = [
        #{id => <<"node-1">>, ip => <<"127.0.0.1">>, port => 8081},
        #{id => <<"node-2">>, ip => <<"127.0.0.1">>, port => 8082}
    ],

    Config1 = [{test_cluster_id, TestClusterId}, {test_nodes, TestNodes} | Config],

    %% Start mock nodes for testing
    start_mock_nodes(TestNodes, Config1),

    Config1.

end_per_suite(_Config) ->
    %% Stop HotCI services
    hotci_supervisor:stop_child(hotci_node_orchestrator),

    %% Clean up mock nodes
    stop_mock_nodes(),

    ok.

init_per_testcase(TestCase, Config) ->
    %% Setup test-specific configuration
    case TestCase of
        test_cluster_creation ->
            %% Clean up any existing test clusters
            cleanup_test_clusters();
        _ ->
            ok
    end,

    Config.

end_per_testcase(_TestCase, _Config) ->
    %% Cleanup after each test case
    cleanup_test_clusters(),
    ok.

%%% ============================================================================
%%% Test Cases
%%% ============================================================================

%% Test basic cluster creation
test_cluster_creation(_Config) ->
    ClusterId = generate_test_cluster_id(),
    NodeConfigs = [
        #{ip => <<"127.0.0.1">>, port => 8081, version => <<"1.0.0">>},
        #{ip => <<"127.0.0.1">>, port => 8082, version => <<"1.0.0">>}
    ],

    %% Create cluster
    {ok, CreatedClusterId} = hotci_node_orchestrator:create_test_cluster(#{nodes => NodeConfigs}),
    ?assertEqual(ClusterId, CreatedClusterId),

    %% Verify cluster was created
    {ok, Status} = hotci_node_orchestrator:get_cluster_status(),
    ?assertEqual(1, maps:get(total_clusters, Status)),
    ?assertEqual(2, maps:get(total_nodes, Status)),

    %% Verify nodes were created
    Node1Info = hotci_node_orchestrator:get_node_info(<<"node-1">>),
    ?assertEqual(<<"node-1">>, element(2, Node1Info)#node_info.id),

    ok.

%% Test node creation within cluster
test_node_creation(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),
    NodeConfig = #{ip => <<"127.0.0.1">>, port => 8083, version => <<"1.0.0">>},

    %% Add node to cluster
    ok = hotci_node_orchestrator:register_node(<<"new-node">>, NodeConfig),

    %% Verify node was added
    NodeInfo = hotci_node_orchestrator:get_node_info(<<"new-node">>),
    ?assertEqual(<<"new-node">>, NodeInfo#node_info.id),
    ?assertEqual(<<"127.0.0.1">>, NodeInfo#node_info.node_ip),
    ?assertEqual(8083, NodeInfo#node_info.port),

    ok.

%% Test node lifecycle management
test_node_lifecycle(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),

    %% Create a test node
    NodeId = <<"lifecycle-node">>,
    NodeConfig = #{ip => <<"127.0.0.1">>, port => 8084, version => <<"1.0.0">>},
    ok = hotci_node_orchestrator:register_node(NodeId, NodeConfig),

    %% Verify node is running
    {ok, NodeInfo} = hotci_node_orchestrator:get_node_info(NodeId),
    ?assertEqual(running, NodeInfo#node_info.status),

    %% Stop the node
    ok = hotci_node_orchestrator:unregister_node(NodeId),

    %% Verify node is stopped
    {error, node_not_found} = hotci_node_orchestrator:get_node_info(NodeId),

    ok.

%% Test cluster destruction
test_cluster_destruction(_Config) ->
    %% Create test cluster first
    ClusterId = generate_test_cluster_id(),
    NodeConfigs = [
        #{ip => <<"127.0.0.1">>, port => 8085, version => <<"1.0.0">>},
        #{ip => <<"127.0.0.1">>, port => 8086, version => <<"1.0.0">>}
    ],
    ok = hotci_node_orchestrator:create_test_cluster(#{nodes => NodeConfigs}),

    %% Verify cluster exists
    {ok, Status} = hotci_node_orchestrator:get_cluster_status(),
    ?assertEqual(1, maps:get(total_clusters, Status)),

    %% Destroy cluster
    ok = hotci_node_orchestrator:destroy_cluster(ClusterId),

    %% Verify cluster is destroyed
    {ok, StatusAfter} = hotci_node_orchestrator:get_cluster_status(),
    ?assertEqual(0, maps:get(total_clusters, StatusAfter)),

    ok.

%% Test upgrade orchestration
test_upgrade_orchestration(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),
    NodeId = <<"upgrade-node">>,
    TargetVersion = <<"2.0.0">>,

    %% Create test node
    NodeConfig = #{ip => <<"127.0.0.1">>, port => 8087, version => <<"1.0.0">>},
    ok = hotci_node_orchestrator:register_node(NodeId, NodeConfig),

    %% Perform upgrade
    {ok, _} = hotci_node_orchestrator:upgrade_node(TestClusterId, NodeId, TargetVersion),

    %% Verify upgrade
    {ok, NodeInfo} = hotci_node_orchestrator:get_node_info(NodeId),
    ?assertEqual(<<"2.0.0">>, NodeInfo#node_info.version),
    ?assertEqual(running, NodeInfo#node_info.status),

    ok.

%% Test cluster status reporting
test_cluster_status(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),

    %% Get cluster status
    {ok, Status} = hotci_node_orchestrator:get_cluster_status(),

    %% Verify status structure
    ?assert(is_map(Status)),
    ?assert(is_integer(maps:get(total_clusters, Status))),
    ?assert(is_integer(maps:get(total_nodes, Status))),

    %% Verify clusters
    Clusters = maps:get(clusters, Status),
    ?assert(is_map(Clusters)),

    %% Verify test cluster exists
    ?assert(maps:is_key(TestClusterId, Clusters)),

    ClusterInfo = maps:get(TestClusterId, Clusters),
    ?assertEqual(TestClusterId, ClusterInfo#cluster_info.id),
    ?assert(is_list(ClusterInfo#cluster_info.nodes)),

    ok.

%% Test node registration
test_node_registration(_Config) ->
    NodeId = <<"registration-node">>,
    NodeConfig = #{ip => <<"127.0.0.1">>, port => 8088, version => <<"1.0.0">>},

    %% Register node
    ok = hotci_node_orchestrator:register_node(NodeId, NodeConfig),

    %% Verify registration
    {ok, NodeInfo} = hotci_node_orchestrator:get_node_info(NodeId),
    ?assertEqual(NodeId, NodeInfo#node_info.id),
    ?assertEqual(running, NodeInfo#node_info.status),

    %% Check heartbeat
    ?assert(is_integer(NodeInfo#node_info.last_heartbeat)),

    ok.

%% Test node unregistration
test_node_unregistration(_Config) ->
    NodeId = <<"unregistration-node">>,
    NodeConfig = #{ip => <<"127.0.0.1">>, port => 8089, version => <<"1.0.0">>},

    %% Register node first
    ok = hotci_node_orchestrator:register_node(NodeId, NodeConfig),

    %% Verify it exists
    {ok, _} = hotci_node_orchestrator:get_node_info(NodeId),

    %% Unregister node
    ok = hotci_node_orchestrator:unregister_node(NodeId),

    %% Verify it's gone
    {error, node_not_found} = hotci_node_orchestrator:get_node_info(NodeId),

    ok.

%% Test cluster scaling
test_cluster_scale(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),

    %% Add multiple nodes
    NewNodes = [
        #{id => <<"scale-node-1">>, ip => <<"127.0.0.1">>, port => 8090},
        #{id => <<"scale-node-2">>, ip => <<"127.0.0.1">>, port => 8091},
        #{id => <<"scale-node-3">>, ip => <<"127.0.0.1">>, port => 8092}
    ],

    lists:foreach(fun(Node) ->
        NodeConfig = Node#{version => <<"1.0.0">>},
        ok = hotci_node_orchestrator:register_node(Node#id, NodeConfig)
    end, NewNodes),

    %% Verify scale
    {ok, Status} = hotci_node_orchestrator:get_cluster_status(),
    ExpectedNodeCount = length(?config(test_nodes, _Config)) + length(NewNodes),
    ?assertEqual(ExpectedNodeCount, maps:get(total_nodes, Status)),

    ok.

%% Test error handling
test_error_handling(_Config) ->
    %% Test non-existent cluster
    {error, cluster_not_found} = hotci_node_orchestrator:destroy_cluster(<<"non-existent">>),

    %% Test non-existent node
    {error, node_not_found} = hotci_node_orchestrator:get_node_info(<<"non-existent">>),

    %% Test invalid cluster config
    {error, cluster_exists} = hotci_node_orchestrator:create_test_cluster(#{nodes => []}),

    %% Test invalid upgrade
    {error, node_not_found} = hotci_node_orchestrator:upgrade_node(
        ?config(test_cluster_id, _Config), <<"non-existent">>, <<"2.0.0">>
    ),

    ok.

%%% ============================================================================
%%% Helper Functions
%%% ============================================================================

%% Generate test cluster ID
generate_test_cluster_id() ->
    Now = erlang:system_time(millisecond),
    <<"test-cluster-", (integer_to_binary(Now))/binary>>.

%% Start mock nodes for testing
start_mock_nodes(NodeConfigs, Config) ->
    lists:foreach(fun(NodeConfig) ->
        NodeId = maps:get(id, NodeConfig),
        start_mock_node(NodeId, NodeConfig)
    end, NodeConfigs).

%% Start a single mock node
start_mock_node(NodeId, NodeConfig) ->
    %% This would start actual mock containers
    %% For testing, just register the node
    hotci_node_orchestrator:register_node(NodeId, NodeConfig).

%% Stop mock nodes
stop_mock_nodes() ->
    %% This would stop actual mock containers
    %% For testing, just unregister known nodes
    ok.

%% Clean up test clusters
cleanup_test_clusters() ->
    %% Get all clusters
    case hotci_node_orchestrator:get_cluster_status() of
        {ok, Status} ->
            Clusters = maps:get(clusters, Status),
            lists:foreach(fun({ClusterId, _}) ->
                hotci_node_orchestrator:destroy_cluster(ClusterId)
            end, maps:to_list(Clusters));
        {error, _} ->
            ok
    end.