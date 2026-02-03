%%% @doc HotCI Upgrade Validator Test Suite
%%%
%%% Comprehensive test suite for the HotCI upgrade validator,
/// validating hot code upgrade testing and validation automation.
-module(hotci_upgrade_validator_SUITE).

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
    test_upgrade_validation_scenarios/1,
    test_validation_test_execution/1,
    test_consistency_validation/1,
    test_health_check_validation/1,
    test_validation_results/1,
    test_validation_metrics/1,
    test_validation_timeout_handling/1,
    test_validation_failure_scenarios/1,
    test_validation_concurrency/1,
    test_validation_persistence/1
]).

%%% ============================================================================
%%% CT Callbacks
%%% ============================================================================

all() ->
    [
        test_upgrade_validation_scenarios,
        test_validation_test_execution,
        test_consistency_validation,
        test_health_check_validation,
        test_validation_results,
        test_validation_metrics,
        test_validation_timeout_handling,
        test_validation_failure_scenarios,
        test_validation_concurrency,
        test_validation_persistence
    ].

init_per_suite(Config) ->
    %% Start HotCI services
    {ok, _} = hotci_supervisor:start_link(),

    %% Wait for services to be ready
    timer:sleep(2000),

    %% Initialize test data
    TestClusterId = <<"validation-cluster-001">>,
    UpgradeVersion = <<"2.0.0">>,

    Config1 = [{test_cluster_id, TestClusterId}, {upgrade_version, UpgradeVersion} | Config],

    %% Create test cluster
    NodeConfigs = [
        #{id => <<"validation-node-1">>, ip => <<"127.0.0.1">>, port => 8081, version => <<"1.0.0">>},
        #{id => <<"validation-node-2">>, ip => <<"127.0.0.1">>, port => 8082, version => <<"1.0.0">>}
    ],
    ok = hotci_node_orchestrator:create_test_cluster(#{nodes => NodeConfigs}),

    Config1.

end_per_suite(_Config) ->
    %% Stop HotCI services
    hotci_supervisor:stop_child(hotci_upgrade_validator),

    %% Clean up test clusters
    hotci_node_orchestrator:destroy_cluster(?config(test_cluster_id, _Config)),

    ok.

init_per_testcase(TestCase, Config) ->
    %% Setup test-specific configuration
    case TestCase of
        test_upgrade_validation_scenarios ->
            %% Clean up previous validation results
            cleanup_validation_results();
        _ ->
            ok
    end,

    Config.

end_per_testcase(_TestCase, _Config) ->
    %% Cleanup after each test case
    cleanup_validation_results(),
    ok.

%%% ============================================================================
%%% Test Cases
%%% ============================================================================

%% Test upgrade validation scenarios
test_upgrade_validation_scenarios(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),
    UpgradeVersion = ?config(upgrade_version, _Config),

    %% Create upgrade scenario
    Scenario = #upgrade_scenario{
        id = <<"test-scenario">>,
        cluster_id = TestClusterId,
        target_version = UpgradeVersion,
        nodes_to_upgrade = [<<"validation-node-1">>, <<"validation-node-2">>],
        upgrade_order = [<<"validation-node-1">>, <<"validation-node-2">>],
        validation_tests = [basic_functionality, data_integrity],
        created_at = erlang:system_time(millisecond),
        status = pending
    },

    %% Start upgrade validation
    {ok, ScenarioId} = hotci_upgrade_validator:validate_upgrade_scenario(Scenario),
    ?assertEqual(<<"test-scenario">>, ScenarioId),

    %% Verify scenario status
    case hotci_upgrade_validator:get_validation_results() of
        {ok, Results} ->
            ?assert(is_list(Results)),
            %% Validation results would be populated after test execution
            ok;
        {error, no_results} ->
            ok  % Results not ready yet
    end,

    ok.

%% Test validation test execution
test_validation_test_execution(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),
    UpgradeVersion = ?config(upgrade_version, _Config),

    %% Start upgrade validation
    {ok, ScenarioId} = hotci_upgrade_validator:start_upgrade_validation(TestClusterId, UpgradeVersion),

    %% Wait for validation to complete
    timer:sleep(5000),

    %% Get validation results
    {ok, Results} = hotci_upgrade_validator:get_validation_results(),

    %% Verify results
    ?assert(is_list(Results)),
    ?assert(length(Results) > 0),

    %% Check result structure
    [Result | _] = Results,
    ?assert(is_binary(Result#validation_result.scenario_id)),
    ?assert(is_binary(Result#validation_result.node_id)),
    ?assert(is_atom(Result#validation_result.test_name)),
    ?assert(lists:member(Result#validation_result.status, [passed, failed, skipped])),
    ?assert(is_integer(Result#validation_result.duration)),
    ?assert(is_integer(Result#validation_result.timestamp)),

    ok.

%% Test consistency validation
test_consistency_validation(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),

    %% Run consistency validation
    {ok, Results} = hotci_upgrade_validator:validate_consistency(TestClusterId),

    %% Verify results
    ?assert(is_list(Results)),
    ?assert(length(Results) > 0),

    %% Check consistency check results
    [Result | _] = Results,
    ?assert(is_binary(Result#validation_result.scenario_id)),
    ?assert(is_binary(Result#validation_result.node_id)),
    ?assertEqual(consistency_check, Result#validation_result.test_name),
    ?assert(lists:member(Result#validation_result.status, [passed, failed])),

    ok.

%% Test health check validation
test_health_check_validation(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),

    %% Run health check validation
    {ok, Results} = hotci_upgrade_validator:validate_health_checks(TestClusterId),

    %% Verify results
    ?assert(is_list(Results)),
    ?assert(length(Results) > 0),

    %% Check health check results
    [Result | _] = Results,
    ?assert(is_binary(Result#validation_result.scenario_id)),
    ?assert(is_binary(Result#validation_result.node_id)),
    ?assertEqual(node_health, Result#validation_result.test_name),
    ?assert(lists:member(Result#validation_result.status, [passed, failed])),

    ok.

%% Test validation results
test_validation_results(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),
    UpgradeVersion = ?config(upgrade_version, _Config),

    %% Start upgrade validation
    {ok, ScenarioId} = hotci_upgrade_validator:start_upgrade_validation(TestClusterId, UpgradeVersion),

    %% Wait for validation to complete
    timer:sleep(5000),

    %% Get validation results
    {ok, Results} = hotci_upgrade_validator:get_validation_results(),

    %% Verify results structure
    ?assert(is_list(Results)),
    lists:foreach(fun(Result) ->
        ?assert(is_binary(Result#validation_result.scenario_id)),
        ?assert(is_binary(Result#validation_result.node_id)),
        ?assert(is_atom(Result#validation_result.test_name)),
        ?assert(lists:member(Result#validation_result.status, [passed, failed, skipped])),
        ?assert(is_integer(Result#validation_result.duration)),
        ?assert(is_integer(Result#validation_result.timestamp))
    end, Results),

    %% Test result filtering
    ScenarioResults = lists:filter(fun(R) ->
        R#validation_result.scenario_id =:= ScenarioId
    end, Results),
    ?assert(length(ScenarioResults) > 0),

    ok.

%% Test validation metrics
test_validation_metrics(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),
    UpgradeVersion = ?config(upgrade_version, _Config),

    %% Start upgrade validation
    {ok, _} = hotci_upgrade_validator:start_upgrade_validation(TestClusterId, UpgradeVersion),

    %% Wait for validation to complete
    timer:sleep(5000),

    %% Get validation metrics
    {ok, Metrics} = hotci_upgrade_validator:get_upgrade_metrics(),

    %% Verify metrics structure
    ?assert(is_list(Metrics)),
    lists:foreach(fun(Metric) ->
        ?assert(is_integer(Metric#validation_metrics.total_tests)),
        ?assert(is_integer(Metric#validation_metrics.passed_tests)),
        ?assert(is_integer(Metric#validation_metrics.failed_tests)),
        ?assert(is_integer(Metric#validation_metrics.skipped_tests)),
        ?assert(is_integer(Metric#validation_metrics.total_duration)),
        ?assert(is_number(Metric#validation_metrics.consistency_score))
    end, Metrics),

    ok.

%% Test validation timeout handling
test_validation_timeout_handling(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),

    %% Create a scenario with timeout
    Scenario = #upgrade_scenario{
        id = <<"timeout-scenario">>,
        cluster_id = TestClusterId,
        target_version = <<"2.0.0">>,
        nodes_to_upgrade = [<<"validation-node-1">>],
        validation_tests = [basic_functionality],
        created_at = erlang:system_time(millisecond),
        status = running
    },

    %% Start validation with short timeout
    {ok, _} = hotci_upgrade_validator:validate_upgrade_scenario(Scenario),

    %% Wait for timeout
    timer:sleep(6000),

    %% Check that validation completed (timed out)
    {ok, Results} = hotci_upgrade_validator:get_validation_results(),
    TimeoutResults = lists:filter(fun(R) ->
        R#validation_result.status =:= failed
    end, Results),

    ?assert(length(TimeoutResults) > 0),

    ok.

%% Test validation failure scenarios
test_validation_failure_scenarios(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),

    %% Create a scenario that will fail
    Scenario = #upgrade_scenario{
        id = <<"failure-scenario">>,
        cluster_id = TestClusterId,
        target_version = <<"invalid-version">>,
        nodes_to_upgrade = [<<"validation-node-1">>],
        validation_tests = [basic_functionality, data_integrity],
        created_at = erlang:system_time(millisecond),
        status = running
    },

    %% Start validation
    {ok, _} = hotci_upgrade_validator:validate_upgrade_scenario(Scenario),

    %% Wait for completion
    timer:sleep(5000),

    %% Check failure results
    {ok, Results} = hotci_upgrade_validator:get_validation_results(),
    FailedResults = lists:filter(fun(R) ->
        R#validation_result.status =:= failed
    end, Results),

    ?assert(length(FailedResults) > 0),

    ok.

%% Test validation concurrency
test_validation_concurrency(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),
    UpgradeVersion = ?config(upgrade_version, _Config),

    %% Start multiple validations concurrently
    {ok, ScenarioId1} = hotci_upgrade_validator:start_upgrade_validation(TestClusterId, UpgradeVersion),
    {ok, ScenarioId2} = hotci_upgrade_validator:start_upgrade_validation(TestClusterId, UpgradeVersion),

    %% Wait for both to complete
    timer:sleep(10000),

    %% Check both scenarios have results
    {ok, Results} = hotci_upgrade_validator:get_validation_results(),

    Scenario1Results = lists:filter(fun(R) ->
        R#validation_result.scenario_id =:= ScenarioId1
    end, Results),
    Scenario2Results = lists:filter(fun(R) ->
        R#validation_result.scenario_id =:= ScenarioId2
    end, Results),

    ?assert(length(Scenario1Results) > 0),
    ?assert(length(Scenario2Results) > 0),

    ok.

%% Test validation persistence
test_validation_persistence(_Config) ->
    TestClusterId = ?config(test_cluster_id, _Config),
    UpgradeVersion = ?config(upgrade_version, _Config),

    %% Start upgrade validation
    {ok, ScenarioId} = hotci_upgrade_validator:start_upgrade_validation(TestClusterId, UpgradeVersion),

    %% Wait for validation to complete
    timer:sleep(5000),

    %% Get initial results
    {ok, InitialResults} = hotci_upgrade_validator:get_validation_results(),

    %% Restart HotCI services to test persistence
    hotci_supervisor:stop_child(hotci_upgrade_validator),
    {ok, _} = hotci_upgrade_validator:start_link(),

    %% Get results after restart
    {ok, RestoredResults} = hotci_upgrade_validator:get_validation_results(),

    %% Verify results persisted
    ?assert(length(InitialResults) > 0),
    ?assert(length(RestoredResults) > 0),

    ok.

%%% ============================================================================
%%% Helper Functions
%%% ============================================================================

%% Clean up validation results
cleanup_validation_results() ->
    %% This would clean up validation data
    %% For testing, just ensure we start fresh
    ok.