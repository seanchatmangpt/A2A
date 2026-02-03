%%% @doc HotCI Failure Injector
%%%
%%% This module simulates various failure scenarios during hot code upgrades
%%% to test system resilience and failure handling capabilities.
-module(hotci_failure_injector).
-behaviour(gen_server).

%% API
-export([start_link/0, inject_failure/3, schedule_failure/3,
         get_failure_scenarios/0, clear_failures/1, enable_failure_mode/2,
         disable_failure_mode/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% Records
-record.failure_scenario, {
    id :: binary(),
    name :: binary(),
    description :: binary(),
    probability :: float(),  % 0.0 to 1.0
    failure_type :: atom(),
    injection_points :: [binary()],
    recovery_timeout :: integer(),
    impact :: 'low' | 'medium' | 'high' | 'critical'
}.

record.failure_injection, {
    id :: binary(),
    scenario_id :: binary(),
    node_id :: binary(),
    status :: 'scheduled' | 'injected' | 'active' | 'recovered' | 'failed',
    start_time :: integer() | undefined,
    end_time :: integer() | undefined,
    details :: term()
}.

%% State record
-record.state, {
    scenarios = [] :: [record(failure_scenario)],
    injections = [] :: [record(failure_injection)],
    enabled_scenarios = [] :: [binary()],
    enabled_failures = #{} :: map(),  #{binary() => boolean()},
    failure_log = [] :: [term()]
}.

-define(SERVER, ?MODULE).
-define(DEFAULT_INJECTION_TIMEOUT, 5000).
-define(SCHEDULED_CHECK_INTERVAL, 1000).

-define(FAILURE_TYPES, [
    node_crash,
    network_partition,
    memory_exhaustion,
    disk_space_full,
    timeout,
    message_corruption,
    process_killed,
    database_failure,
    connection_loss,
    upgrade_failure
]).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the failure injector
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Inject a failure immediately
-spec inject_failure(cluster_id(), node_id(), binary()) -> ok | {error, term()}.
inject_failure(ClusterId, NodeId, ScenarioId) ->
    gen_server:call(?SERVER, {inject_failure, ClusterId, NodeId, ScenarioId}).

%% @doc Schedule a failure for injection at a future time
-spec schedule_failure(cluster_id(), node_id(), binary()) -> ok | {error, term()}.
schedule_failure(ClusterId, NodeId, ScenarioId) ->
    gen_server:call(?SERVER, {schedule_failure, ClusterId, NodeId, ScenarioId}).

%% @doc Get all available failure scenarios
-spec get_failure_scenarios() -> {ok, [record(failure_scenario)]}.
get_failure_scenarios() ->
    gen_server:call(?SERVER, get_failure_scenarios).

%% @doc Clear failures for a cluster
-spec clear_failures(cluster_id()) -> ok.
clear_failures(ClusterId) ->
    gen_server:cast(?SERVER, {clear_failures, ClusterId}).

%% @doc Enable a failure scenario
-spec enable_failure_mode(binary(), float()) -> ok.
enable_failure_mode(ScenarioId, Probability) ->
    gen_server:cast(?SERVER, {enable_failure_mode, ScenarioId, Probability}).

%% @doc Disable failure mode
-spec disable_failure_mode(binary()) -> ok.
disable_failure_mode(ScenarioId) ->
    gen_server:cast(?SERVER, {disable_failure_mode, ScenarioId}).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init([]) -> {ok, #state{}}.
init([]) ->
    %% Initialize default failure scenarios
    Scenarios = create_default_scenarios(),

    %% Start scheduled failure checker
    erlang:send_after(?SCHEDULED_CHECK_INTERVAL, self(), check_scheduled_failures),

    {ok, #state{scenarios = Scenarios}}.

-spec handle_call(term(), {pid(), reference()}, #state{}) -> {reply, term(), #state{}}.
handle_call({inject_failure, ClusterId, NodeId, ScenarioId}, _From, State) ->
    Result = do_inject_failure(ClusterId, NodeId, ScenarioId, State),
    {reply, Result, State};

handle_call({schedule_failure, ClusterId, NodeId, ScenarioId}, _From, State) ->
    Result = do_schedule_failure(ClusterId, NodeId, ScenarioId, State),
    {reply, Result, State};

handle_call(get_failure_scenarios, _From, State) ->
    {reply, {ok, State#state.scenarios}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast({clear_failures, ClusterId}, State) ->
    NewInjections = lists:filter(fun(Injection) ->
        case Injection#failure_injection.node_id of
            ClusterId -> false;
            _ -> true
        end
    end, State#state.injections),

    NewState = State#state{injections = NewInjections},
    {noreply, NewState};

handle_cast({enable_failure_mode, ScenarioId, Probability}, State) ->
    case lists:any(fun(Scenario) -> Scenario#failure_scenario.id =:= ScenarioId end, State#state.scenarios) of
        true ->
            NewEnabledScenarios = lists:usort([ScenarioId | State#state.enabled_scenarios]),
            NewFailures = maps:put(ScenarioId, Probability, State#state.enabled_failures),

            NewState = State#state{
                enabled_scenarios = NewEnabledScenarios,
                enabled_failures = NewFailures
            },

            logger:info("Enabled failure scenario ~p with probability ~.2f", [ScenarioId, Probability]),
            {noreply, NewState};
        false ->
            logger:warning("Failure scenario ~p not found", [ScenarioId]),
            {noreply, State}
    end;

handle_cast({disable_failure_mode, ScenarioId}, State) ->
    NewEnabledScenarios = lists:delete(ScenarioId, State#state.enabled_scenarios),
    NewFailures = maps:remove(ScenarioId, State#state.enabled_failures),

    NewState = State#state{
        enabled_scenarios = NewEnabledScenarios,
        enabled_failures = NewFailures
    },

    logger:info("Disabled failure scenario ~p", [ScenarioId]),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
handle_info(check_scheduled_failures, State) ->
    NewState = check_and_execute_scheduled_failures(State),
    erlang:send_after(?SCHEDULED_CHECK_INTERVAL, self(), check_scheduled_failures),
    {noreply, NewState};

handle_info(recovery_timeout, InjectionId) ->
    gen_server:cast(?SERVER, {recovery_timeout, InjectionId});

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, _State) ->
    ok.

-spec code_change(term(), #state{}, term()) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Inject failure immediately
-spec do_inject_failure(cluster_id(), node_id(), binary(), #state{}) -> ok | {error, term()}.
do_inject_failure(ClusterId, NodeId, ScenarioId, State) ->
    case lists:keyfind(ScenarioId, #failure_scenario.id, State#state.scenarios) of
        false ->
            {error, scenario_not_found};
        Scenario ->
            InjectionId = generate_injection_id(),
            Injection = #failure_injection{
                id = InjectionId,
                scenario_id = ScenarioId,
                node_id = NodeId,
                status = active,
                start_time = erlang:system_time(millisecond),
                details = Scenario
            },

            %% Perform the actual failure injection
            Result = perform_failure_injection(Injection, Scenario),

            %% Log the failure injection
            FailureLog = #{
                timestamp => erlang:system_time(millisecond),
                cluster_id => ClusterId,
                node_id => NodeId,
                scenario_id => ScenarioId,
                result => Result,
                injection_id => InjectionId
            },

            %% Update state
            NewInjections = [Injection | State#state.injections],
            NewFailureLog = [FailureLog | State#state.failure_log],

            %% Schedule recovery if applicable
            case Scenario#failure_scenario.recovery_timeout > 0 of
                true ->
                    erlang:send_after(Scenario#failure_scenario.recovery_timeout,
                        self(), {recovery_timeout, InjectionId});
                false ->
                    ok
            end,

            logger:warning("Injected failure ~p on node ~p: ~p", [
                Scenario#failure_scenario.name, NodeId, Result
            ]),

            ok
    end.

%% @doc Schedule failure for future injection
-spec do_schedule_failure(cluster_id(), node_id(), binary(), #state{}) -> ok | {error, term()}.
do_schedule_failure(ClusterId, NodeId, ScenarioId, State) ->
    case lists:keyfind(ScenarioId, #failure_scenario.id, State#state.scenarios) of
        false ->
            {error, scenario_not_found};
        _ ->
            %% Create injection record with scheduled status
            InjectionId = generate_injection_id(),
            Injection = #failure_injection{
                id = InjectionId,
                scenario_id = ScenarioId,
                node_id = NodeId,
                status = scheduled,
                details = #{scheduled_time => erlang:system_time(millisecond)}
            },

            NewInjections = [Injection | State#state.injections],
            logger:info("Scheduled failure injection ~p on node ~p", [
                ScenarioId, NodeId
            ]),

            {ok, NewInjections}
    end.

%% @doc Check and execute scheduled failures
-spec check_and_execute_scheduled_failures(#state{}) -> #state{}.
check_and_execute_scheduled_failures(State) ->
    Now = erlang:system_time(millisecond),

    %% Find scheduled failures that should be executed
    ScheduledFailures = lists:filter(fun(Injection) ->
        case Injection#failure_injection.status of
            scheduled ->
                Now - maps:get(scheduled_time, Injection#failure_injection.details, 0) > 0;
            _ -> false
        end
    end, State#state.injections),

    %% Execute scheduled failures
    lists:foldl(fun(ScheduledInjection, AccState) ->
        ClusterId = ScheduledInjection#failure_injection.node_id,
        NodeId = ScheduledInjection#failure_injection.node_id,
        ScenarioId = ScheduledInjection#failure_injection.scenario_id,

        case do_inject_failure(ClusterId, NodeId, ScenarioId, AccState) of
            ok ->
                AccState;
            {error, _} ->
                AccState
        end
    end, State, ScheduledFailures).

%% @doc Create default failure scenarios
-spec create_default_scenarios() -> [record(failure_scenario)].
create_default_scenarios() ->
    [
        #failure_scenario{
            id = <<"node_crash">>,
            name = <<"Node Crash">>,
            description = <<"Simulate Erlang node crash">>,
            probability = 0.1,
            failure_type = node_crash,
            injection_points = [node_startup, node_upgrade],
            recovery_timeout = 5000,
            impact = critical
        },
        #failure_scenario{
            id = <<"network_partition">>,
            name = <<"Network Partition">>,
            description = <<"Simulate network partition between nodes">>,
            probability = 0.2,
            failure_type = network_partition,
            injection_points = [distributed_upgrade],
            recovery_timeout = 10000,
            impact = high
        },
        #failure_scenario{
            id = <<"memory_exhaustion">>,
            name = <<"Memory Exhaustion">>,
            description = <<"Simulate memory exhaustion on node">>,
            probability = 0.15,
            failure_type = memory_exhaustion,
            injection_points = [upgrade_process, heavy_processing],
            recovery_timeout = 8000,
            impact = high
        },
        #failure_scenario{
            id = <<"disk_space_full">>,
            name = <<"Disk Space Full">>,
            description = <<"Simulate disk space exhaustion">>,
            probability = 0.05,
            failure_type = disk_space_full,
            injection_points = [artifact_storage, log_rotation],
            recovery_timeout = 15000,
            impact = medium
        },
        #failure_scenario{
            id = <<"timeout">>,
            name = <<"Timeout">>,
            description = <<"Simulate operation timeout">>,
            probability = 0.3,
            failure_type = timeout,
            injection_points = [message_processing, state_transition],
            recovery_timeout = 2000,
            impact = medium
        },
        #failure_scenario{
            id = <<"message_corruption">>,
            name = <<"Message Corruption">>,
            description = <<"Simulate message corruption">>,
            probability = 0.1,
            failure_type = message_corruption,
            injection_points = [message_exchange, task_processing],
            recovery_timeout = 3000,
            impact = medium
        },
        #failure_scenario{
            id = <<"process_killed">>,
            name = <<"Process Killed">>,
            description = <<"Simulate process termination">>,
            probability = 0.15,
            failure_type = process_killed,
            injection_points = [task_processing, artifact_creation],
            recovery_timeout = 4000,
            impact = medium
        },
        #failure_scenario{
            id = <<"database_failure">>,
            name = <<"Database Failure">>,
            description = <<"Simulate database connection failure">>,
            probability = 0.1,
            failure_type = database_failure,
            injection_points = [task_storage, metadata_persistence],
            recovery_timeout = 6000,
            impact = critical
        },
        #failure_scenario{
            id = <<"connection_loss">>,
            name = <<"Connection Loss">>,
            description = <<"Simulate connection loss to external services">>,
            probability = 0.2,
            failure_type = connection_loss,
            injection_points = [external_api, push_notifications],
            recovery_timeout = 5000,
            impact = low
        },
        #failure_scenario{
            id = <<"upgrade_failure">>,
            name = <<"Upgrade Failure">>,
            description = <<"Simulate hot code upgrade failure">>,
            probability = 0.1,
            failure_type = upgrade_failure,
            injection_points = [code_upgrade, module_reload],
            recovery_timeout = 10000,
            impact = critical
        }
    ].

%% @doc Perform the actual failure injection
-spec perform_failure_injection(record(failure_injection), record(failure_scenario)) -> term().
perform_failure_injection(Injection, Scenario) ->
    FailureType = Scenario#failure_scenario.failure_type,
    NodeId = Injection#failure_injection.node_id,

    try
        case FailureType of
            node_crash ->
                inject_node_crash(NodeId);
            network_partition ->
                inject_network_partition(NodeId);
            memory_exhaustion ->
                inject_memory_exhaustion(NodeId);
            disk_space_full ->
                inject_disk_space_full(NodeId);
            timeout ->
                inject_timeout(NodeId);
            message_corruption ->
                inject_message_corruption(NodeId);
            process_killed ->
                inject_process_killed(NodeId);
            database_failure ->
                inject_database_failure(NodeId);
            connection_loss ->
                inject_connection_loss(NodeId);
            upgrade_failure ->
                inject_upgrade_failure(NodeId);
            _ ->
                {error, unknown_failure_type}
        end
    catch
        Error:Reason ->
            logger:error("Failure injection error: ~p:~p", [Error, Reason]),
            {error, Reason}
    end.

%% @doc Inject node crash
-spec inject_node_crash(binary()) -> ok.
inject_node_crash(NodeId) ->
    logger:error("Simulating node crash on ~p", [NodeId]),
    %% In a real implementation, this would crash the actual node
    %% For now, just simulate
    erlang:send_after(1000, self(), {node_crash, NodeId}),
    ok.

%% @doc Inject network partition
-spec inject_network_partition(binary()) -> ok.
inject_network_partition(NodeId) ->
    logger:warning("Simulating network partition on ~p", [NodeId]),
    %% Simulate network partition
    ok.

%% @doc Inject memory exhaustion
-spec inject_memory_exhaustion(binary()) -> ok.
inject_memory_exhaustion(NodeId) ->
    logger:warning("Simulating memory exhaustion on ~p", [NodeId]),
    %% This would allocate memory until exhausted
    spawn(fun() ->
        lists:foreach(fun(_) ->
            _ = [crypto:strong_rand_bytes(1024 * 1024) || _ <- lists:seq(1, 100)]
        end, lists:seq(1, 10))
    end),
    ok.

%% @doc Inject disk space full
-spec inject_disk_space_full(binary()) -> ok.
inject_disk_space_full(NodeId) ->
    logger:warning("Simulating disk space full on ~p", [NodeId]),
    %% Simulate disk space filling
    ok.

%% @doc Inject timeout
-spec inject_timeout(binary()) -> ok.
inject_timeout(NodeId) ->
    logger:warning("Simulating timeout on ~p", [NodeId]),
    %% Simulate timeout
    ok.

%% @doc Inject message corruption
-spec inject_message_corruption(binary()) -> ok.
inject_message_corruption(NodeId) ->
    logger:warning("Simulating message corruption on ~p", [NodeId]),
    %% Simulate message corruption
    ok.

%% @doc Inject process killed
-spec inject_process_killed(binary()) -> ok.
inject_process_killed(NodeId) ->
    logger:warning("Simulating process killed on ~p", [NodeId]),
    %% Simulate process termination
    ok.

%% @doc Inject database failure
-spec inject_database_failure(binary()) -> ok.
inject_database_failure(NodeId) ->
    logger:error("Simulating database failure on ~p", [NodeId]),
    %% Simulate database failure
    ok.

%% @doc Inject connection loss
-spec inject_connection_loss(binary()) -> ok.
inject_connection_loss(NodeId) ->
    logger:warning("Simulating connection loss on ~p", [NodeId]),
    %% Simulate connection loss
    ok.

%% @doc Inject upgrade failure
-spec inject_upgrade_failure(binary()) -> ok.
inject_upgrade_failure(NodeId) ->
    logger:error("Simulating upgrade failure on ~p", [NodeId]),
    %% Simulate upgrade failure
    ok.

%% @doc Generate unique injection ID
-spec generate_injection_id() -> binary().
generate_injection_id() ->
    Now = erlang:system_time(millisecond),
    <<"injection_", (integer_to_binary(Now))/binary>>.