%%% @doc HotCI Upgrade Validator
%%%
%%% This module validates hot code upgrades across distributed Erlang nodes.
%%% It performs comprehensive testing to ensure upgrade compatibility,
%%% consistency, and system integrity during and after upgrades.
-module(hotci_upgrade_validator).
-behaviour(gen_server).

%% API
-export([start_link/0, start_upgrade_validation/2, validate_upgrade_scenario/1,
         validate_consistency/1, validate_health_checks/1,
         get_validation_results/0, get_upgrade_metrics/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% Records
-record(upgrade_scenario, {
    id :: binary(),
    cluster_id :: binary(),
    target_version :: binary(),
    nodes_to_upgrade :: [binary()],
    upgrade_order :: [binary()],
    validation_tests = [] :: [atom()],
    created_at :: integer(),
    status :: 'pending' | 'running' | 'completed' | 'failed'
}).

-record(validation_result, {
    scenario_id :: binary(),
    node_id :: binary(),
    test_name :: atom(),
    status :: 'passed' | 'failed' | 'skipped',
    details :: term(),
    duration :: integer(),
    timestamp :: integer()
}).

-record.validation_metrics, {
    total_tests :: integer(),
    passed_tests :: integer(),
    failed_tests :: integer(),
    skipped_tests :: integer(),
    total_duration :: integer(),
    upgrade_time :: integer(),
    rollback_time :: integer(),
    consistency_score :: float()
}.

%% State record
-record(state, {
    scenarios = #{} :: map(),             #{binary() => upgrade_scenario()},
    results = [] :: [validation_result()],
    metrics = [] :: [validation_metrics()],
    next_scenario_id = 1 :: integer()
}).

-define(SERVER, ?MODULE).
-define(TEST_TIMEOUT, 30000).  % 30 seconds per test
-define(MAX_CONCURRENT_TESTS, 5).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the upgrade validator
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Start upgrade validation for a cluster
-spec start_upgrade_validation(cluster_id(), binary()) -> {ok, binary()} | {error, term()}.
start_upgrade_validation(ClusterId, TargetVersion) ->
    gen_server:call(?SERVER, {start_upgrade_validation, ClusterId, TargetVersion}).

%% @doc Validate a specific upgrade scenario
-spec validate_upgrade_scenario(#upgrade_scenario{}) -> {ok, binary()} | {error, term()}.
validate_upgrade_scenario(Scenario) ->
    gen_server:call(?SERVER, {validate_upgrade_scenario, Scenario}).

%% @doc Validate consistency across all nodes in a cluster
-spec validate_consistency(cluster_id()) -> {ok, [validation_result()]} | {error, term()}.
validate_consistency(ClusterId) ->
    gen_server:call(?SERVER, {validate_consistency, ClusterId}).

%% @doc Perform health check validation on all nodes
-spec validate_health_checks(cluster_id()) -> {ok, [validation_result()]} | {error, term()}.
validate_health_checks(ClusterId) ->
    gen_server:call(?SERVER, {validate_health_checks, ClusterId}).

%% @doc Get all validation results
-spec get_validation_results() -> {ok, [validation_result()]}.
get_validation_results() ->
    gen_server:call(?SERVER, get_validation_results).

%% @doc Get upgrade validation metrics
-spec get_upgrade_metrics() -> {ok, [validation_metrics()]}.
get_upgrade_metrics() ->
    gen_server:call(?SERVER, get_upgrade_metrics).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init([]) -> {ok, #state{}}.
init([]) ->
    %% Load persisted state
    State = load_validation_state(),

    %% Start test execution supervisor
    {ok, _} = hotci_test_supervisor:start_link(),

    {ok, State}.

-spec handle_call(term(), {pid(), reference()}, #state{}) -> {reply, term(), #state{}}.
handle_call({start_upgrade_validation, ClusterId, TargetVersion}, _From, State) ->
    Scenario = create_upgrade_scenario(ClusterId, TargetVersion, State),
    NewState = execute_upgrade_validation(Scenario, State),
    {reply, {ok, Scenario#upgrade_scenario.id}, NewState};

handle_call({validate_upgrade_scenario, Scenario}, _From, State) ->
    NewState = execute_upgrade_validation(Scenario, State),
    {reply, {ok, Scenario#upgrade_scenario.id}, NewState};

handle_call({validate_consistency, ClusterId}, _From, State) ->
    Results = run_consistency_validation(ClusterId, State),
    {reply, {ok, Results}, State};

handle_call({validate_health_checks, ClusterId}, _From, State) ->
    Results = run_health_check_validation(ClusterId, State),
    {reply, {ok, Results}, State};

handle_call(get_validation_results, _From, State) ->
    {reply, {ok, State#state.results}, State};

handle_call(get_upgrade_metrics, _From, State) ->
    {reply, {ok, State#state.metrics}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast({validation_completed, ScenarioId, Results}, State) ->
    %% Update scenario with completion status
    UpdatedScenario = case lists:any(fun(Result) -> Result#validation_result.status =:= failed end, Results) of
        true ->
            logger:warning("Upgrade validation ~p failed", [ScenarioId]),
            State#state.scenarios#{ScenarioId => (State#state.scenarios#{ScenarioId})#upgrade_scenario{status = failed}};
        false ->
            logger:info("Upgrade validation ~p completed successfully", [ScenarioId]),
            State#state.scenarios#{ScenarioId => (State#state.scenarios#{ScenarioId})#upgrade_scenario{status = completed}}
    end,

    %% Add results to results list
    NewResults = lists:append(Results, State#state.results),

    %% Calculate metrics
    Metrics = calculate_validation_metrics(Results, ScenarioId),

    NewState = State#state{
        scenarios = UpdatedScenario,
        results = NewResults,
        metrics = Metrics ++ State#state.metrics
    },

    save_validation_state(NewState),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, _State) ->
    %% Save state before shutdown
    save_validation_state(_State),
    ok.

-spec code_change(term(), #state{}, term()) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Create an upgrade scenario
-spec create_upgrade_scenario(cluster_id(), binary(), #state{}) -> #upgrade_scenario{}.
create_upgrade_scenario(ClusterId, TargetVersion, State) ->
    ScenarioId = generate_scenario_id(State),

    %% Get all nodes in the cluster
    Nodes = get_nodes_in_cluster(ClusterId),

    %% Create scenario
    Scenario = #upgrade_scenario{
        id = ScenarioId,
        cluster_id = ClusterId,
        target_version = TargetVersion,
        nodes_to_upgrade = Nodes,
        upgrade_order = determine_upgrade_order(Nodes),
        validation_tests = get_default_validation_tests(),
        created_at = erlang:system_time(millisecond),
        status = running
    },

    Scenario.

%% @doc Execute upgrade validation
-spec execute_upgrade_validation(#upgrade_scenario{}, #state{}) -> #state{}.
execute_upgrade_validation(Scenario, State) ->
    ScenarioId = Scenario#upgrade_scenario.id,

    %% Update scenario status
    UpdatedScenario = Scenario#upgrade_scenario{status = running},
    UpdatedState = State#state{
        scenarios = maps:put(ScenarioId, UpdatedScenario, State#state.scenarios),
        next_scenario_id = State#state.next_scenario_id + 1
    },

    %% Schedule validation tests
    ValidationTests = get_validation_tasks(Scenario),
    start_validation_tests(ValidationTests, ScenarioId),

    UpdatedState.

%% @doc Run consistency validation
-spec run_consistency_validation(cluster_id(), #state{}) -> [validation_result()].
run_consistency_validation(ClusterId, _State) ->
    %% Get all nodes in cluster
    Nodes = get_nodes_in_cluster(ClusterId),

    %% Run consistency tests
    Tests = [
        test_consistency_data,
        test_consistency_processes,
        test_consistency_tables,
        test_consistency_messages
    ],

    lists:foldl(fun(Test, Acc) ->
        Start = erlang:system_time(millisecond),
        Result = run_consistency_test(Test, Nodes),
        Duration = erlang:system_time(millisecond) - Start,

        ValidationResult = #validation_result{
            scenario_id = <<"consistency_check">>,
            node_id = ClusterId,
            test_name = Test,
            status = case Result of
                {ok, _} -> passed;
                {error, _} -> failed
            end,
            details = Result,
            duration = Duration,
            timestamp = erlang:system_time(millisecond)
        },

        [ValidationResult | Acc]
    end, [], Tests).

%% @doc Run health check validation
-spec run_health_check_validation(cluster_id(), #state{}) -> [validation_result()].
run_health_check_validation(ClusterId, _State) ->
    %% Get all nodes in cluster
    Nodes = get_nodes_in_cluster(ClusterId),

    lists:foldl(fun(NodeId, Acc) ->
        Start = erlang:system_time(millisecond),
        Result = run_node_health_check(NodeId),
        Duration = erlang:system_time(millisecond) - Start,

        ValidationResult = #validation_result{
            scenario_id = <<"health_check">>,
            node_id = NodeId,
            test_name = node_health,
            status = case Result of
                {ok, _} -> passed;
                {error, _} -> failed
            end,
            details = Result,
            duration = Duration,
            timestamp = erlang:system_time(millisecond)
        },

        [ValidationResult | Acc]
    end, [], Nodes).

%% @doc Run consistency tests
-spec run_consistency_test(atom(), [binary()]) -> {ok, term()} | {error, term()}.
run_consistency_test(test_consistency_data, Nodes) ->
    %% Test that all nodes have the same data
    SampleData = get_sample_data_from_nodes(Nodes),
    case check_data_consistency(SampleData) of
        true -> {ok, data_consistent};
        false -> {error, data_inconsistent}
    end;

run_consistency_test(test_consistency_processes, Nodes) ->
    %% Test that all nodes have consistent process counts
    ProcessCounts = get_process_counts_from_nodes(Nodes),
    case check_process_consistency(ProcessCounts) of
        true -> {ok, process_consistent};
        false -> {error, process_inconsistent}
    end;

run_consistency_test(test_consistency_tables, Nodes) ->
    %% Test that all nodes have consistent ETS tables
    TableCounts = get_table_counts_from_nodes(Nodes),
    case check_table_consistency(TableCounts) of
        true -> {ok, table_consistent};
        false -> {error, table_inconsistent}
    end;

run_consistency_test(test_consistency_messages, Nodes) ->
    %% Test that all nodes have consistent message queues
    QueueLengths = get_message_queue_lengths(Nodes),
    case check_queue_consistency(QueueLengths) of
        true -> {ok, message_consistent};
        false -> {error, message_inconsistent}
    end.

%% @doc Run node health check
-spec run_node_health_check(binary()) -> {ok, map()} | {error, term()}.
run_node_health_check(NodeId) ->
    %% Check node connectivity
    case check_node_connectivity(NodeId) of
        ok ->
            %% Check system metrics
            Metrics = get_system_metrics(NodeId),
            %% Check application health
            Health = get_application_health(NodeId),
            {ok, #{metrics => Metrics, health => Health}};
        {error, Reason} ->
            {error, Reason}
    end.

%% @ Get validation tasks for a scenario
-spec get_validation_tasks(#upgrade_scenario{}) -> [map()].
get_validation_tasks(Scenario) ->
    Nodes = Scenario#upgrade_scenario.nodes_to_upgrade,
    Tests = Scenario#upgrade_scenario.validation_tests,

    lists:flatten(lists:map(fun(NodeId) ->
        lists:map(fun(Test) ->
            #{
                node_id => NodeId,
                test_name => Test,
                scenario_id => Scenario#upgrade_scenario.id,
                timeout => ?TEST_TIMEOUT
            }
        end, Tests)
    end, Nodes)).

%% @doc Start validation tests
-spec start_validation_tests([map()], binary()) -> ok.
start_validation_tests(ValidationTasks, ScenarioId) ->
    %% Limit concurrent tests
    TasksToStart = lists:sublist(ValidationTasks, ?MAX_CONCURRENT_TESTS),

    lists:foreach(fun(Task) ->
        hotci_test_supervisor:start_test(Task#{scenario_id => ScenarioId})
    end, TasksToStart).

%% @doc Calculate validation metrics
-spec calculate_validation_metrics([validation_result()], binary()) -> [validation_metrics()].
calculate_validation_metrics(Results, ScenarioId) ->
    Total = length(Results),
    Passed = lists:filter(fun(R) -> R#validation_result.status =:= passed end, Results),
    Failed = lists:filter(fun(R) -> R#validation_result.status =:= failed end, Results),
    Skipped = lists:filter(fun(R) -> R#validation_result.status =:= skipped end, Results),

    TotalDuration = lists:foldl(fun(R, Acc) -> Acc + R#validation_result.duration end, Results, 0),
    PassedCount = length(Passed),
    FailedCount = length(Failed),
    SkippedCount = length(Skipped),

    ConsistencyScore = if
        Total > 0 -> (PassedCount / Total) * 100.0;
        true -> 0.0
    end,

    [#validation_metrics{
        total_tests = Total,
        passed_tests = PassedCount,
        failed_tests = FailedCount,
        skipped_tests = SkippedCount,
        total_duration = TotalDuration,
        upgrade_time = 0,  % Would be tracked during actual upgrade
        rollback_time = 0,  % Would be tracked during rollback
        consistency_score = ConsistencyScore
    }].

%% @doc Get default validation tests
-spec get_default_validation_tests() -> [atom()].
get_default_validation_tests() ->
    [
        basic_functionality,
        data_integrity,
        process_consistency,
        message_handling,
        performance_impact,
        memory_usage,
        cpu_usage,
        network_connectivity,
        state_machine_transitions,
        subscription_functionality,
        artifact_management
    ].

%% @doc Determine upgrade order for nodes
-spec determine_upgrade_order([binary()]) -> [binary()].
determine_upgrade_order(Nodes) ->
    %% Simple round-robin order - could be more sophisticated
    Nodes.

%% @doc Get nodes in a cluster
-spec get_nodes_in_cluster(cluster_id()) -> [binary()].
get_nodes_in_cluster(ClusterId) ->
    %% This would query the node orchestrator
    case hotci_node_orchestrator:get_cluster_status() of
        {ok, Status} ->
            maps:get(ClusterId, Status#{});  % Simplified
        {error, _} ->
            []
    end.

%% @doc Generate scenario ID
-spec generate_scenario_id(#state{}) -> binary().
generate_scenario_id(State) ->
    Id = integer_to_binary(State#state.next_scenario_id),
    <<"scenario_", Id/binary>>.

%% @doc Save validation state
-spec save_validation_state(#state{}) -> ok.
save_validation_state(_State) ->
    %% Would save to persistent storage
    ok.

%% @doc Load validation state
-spec load_validation_state() -> #state{}.
load_validation_state() ->
    %% Would load from persistent storage
    #state{}.

%% @doc Simulated functions for testing
-spec get_sample_data_from_nodes([binary()]) -> [term()].
get_sample_data_from_nodes(_Nodes) ->
    [data1, data2, data3].  % Simplified

-spec check_data_consistency([term()]) -> boolean().
check_data_consistency(_Data) ->
    true.  % Simplified

-spec get_process_counts_from_nodes([binary()]) -> [integer()].
get_process_counts_from_nodes(_Nodes) ->
    [100, 100, 100].  % Simplified

-spec check_process_consistency([integer()]) -> boolean().
check_process_consistency(_Counts) ->
    true.  % Simplified

-spec get_table_counts_from_nodes([binary()]) -> [integer()].
get_table_counts_from_nodes(_Nodes) ->
    [50, 50, 50].  % Simplified

-spec check_table_consistency([integer()]) -> boolean().
check_table_consistency(_Counts) ->
    true.  % Simplified

-spec get_message_queue_lengths([binary()]) -> [integer()].
get_message_queue_lengths(_Nodes) ->
    [5, 5, 5].  % Simplified

-spec check_queue_consistency([integer()]) -> boolean().
check_queue_consistency(_Lengths) ->
    true.  % Simplified

-spec check_node_connectivity(binary()) -> ok | {error, term()}.
check_node_connectivity(_NodeId) ->
    ok.  % Simplified

-spec get_system_metrics(binary()) -> map().
get_system_metrics(_NodeId) ->
    #{cpu => 50.0, memory => 1024.0}.  % Simplified

-spec get_application_health(binary()) -> map().
get_application_health(_NodeId) ->
    #{status => healthy, tasks => 10}.  % Simplified