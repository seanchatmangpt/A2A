%%% @doc HotCI Upgrade Process Monitor
%%%
%%% This module provides comprehensive monitoring specifically for HotCI (Hot Code Upgrade)
%%% environments. It tracks upgrade processes, monitors system health during upgrades,
%%% and provides metrics collection and alerting for upgrade-related operations.
%%%
%%% Features:
%%% - Upgrade process lifecycle tracking
%%% - System health monitoring during upgrades
%%% - Performance metrics collection during upgrades
%%% - Alerting for upgrade failures and performance degradation
%%% - Upgrade rollback tracking
%%% - Real-time upgrade progress monitoring
%%%
%%% @end
-module(a2a_upgrade_monitor).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    stop/0,

    %% Upgrade lifecycle tracking
    start_upgrade/2,
    end_upgrade/2,
    upgrade_step_completed/3,
    upgrade_step_failed/3,
    upgrade_progress/1,

    %% Upgrade-specific metrics
    record_upgrade_metric/2,
    record_upgrade_metric/3,
    get_upgrade_metrics/0,
    get_upgrade_metrics/1,

    %% Health monitoring during upgrades
    check_upgrade_health/0,
    check_upgrade_readiness/0,
    get_upgrade_system_health/0,

    %% Alerting
    set_upgrade_alert_threshold/3,
    send_upgrade_alert/3,
    get_active_alerts/0,
    clear_alerts/0,

    %% Query functions
    is_upgrade_in_progress/0,
    get_current_upgrade/0,
    get_upgrade_history/0,
    get_upgrade_summary/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    handle_continue/2,
    terminate/2,
    code_change/3
]).

-include("a2a.hrl").

%%% ============================================================================
%%% Type Definitions
%%% ============================================================================

-define(UPGRADE_STATES, [not_started, in_progress, completed, failed, rolled_back]).
-define(ALERT_LEVELS, [info, warning, critical, emergency]).

-record(upgrade_step, {
    step_id :: binary(),
    name :: binary(),
    start_time :: integer(),
    end_time :: integer() | undefined,
    status :: atom(),  % pending, in_progress, completed, failed
    result :: term() | undefined,
    metrics :: map()
}).

-type upgrade_step() :: #upgrade_step{}.

-record(upgrade_metrics, {
    start_time :: integer(),
    end_time :: integer() | undefined,
    total_steps :: integer(),
    completed_steps :: integer(),
    failed_steps :: integer(),
    total_duration_ms :: integer(),
    critical_alerts :: integer(),
    non_critical_alerts :: integer(),
    system_impact_score :: float(),
    last_updated :: integer()
}).

-type upgrade_metrics() :: #upgrade_metrics{}.

-record(system_health_snapshot, {
    timestamp :: integer(),
    process_count :: integer(),
    memory_usage :: float(),
    cpu_usage :: float(),
    disk_usage :: float(),
    network_io :: map(),
    database_connections :: integer(),
    active_tasks :: integer(),
    upgrade_status :: atom(),
    health_score :: float()
}).

-type system_health_snapshot() :: #system_health_snapshot{}.

-record(alert_rule, {
    id :: binary(),
    metric_name :: binary(),
    condition :: binary(),
    threshold :: term(),
    level :: atom(),
    enabled :: boolean(),
    last_triggered :: integer() | undefined
}).

-type alert_rule() :: #alert_rule{}.

-record(active_alert, {
    id :: binary(),
    upgrade_id :: binary(),
    rule_id :: binary(),
    level :: atom(),
    message :: binary(),
    details :: map(),
    timestamp :: integer(),
    acknowledged :: boolean(),
    resolved :: boolean()
}).

-type active_alert() :: #active_alert{}.

-record(upgrade_record, {
    upgrade_id :: binary(),
    start_time :: integer(),
    end_time :: integer() | undefined,
    status :: atom(),
    version_from :: binary(),
    version_to :: binary(),
    steps :: [upgrade_step()],
    metrics :: upgrade_metrics(),
    health_snapshots :: [system_health_snapshot()],
    alerts :: [active_alert()],
    rollback_data :: map() | undefined
}).

-type upgrade_record() :: #upgrade_record{}.

-record(state, {
    current_upgrade :: upgrade_record() | undefined,
    upgrade_history :: [upgrade_record()],
    alert_rules :: [alert_rule()],
    active_alerts :: [active_alert()],
    monitoring_enabled :: boolean(),
    snapshot_interval_ms :: non_neg_integer(),
    health_score_threshold :: float(),
    alert_history :: [map()],
    metrics :: map()
}).

-type state() :: #state{}.

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the upgrade monitor with default options
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the upgrade monitor with options
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

%% @doc Stop the upgrade monitor
-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%%% ============================================================================
%%% Upgrade Lifecycle Tracking
%%% ============================================================================

%% @doc Start a new upgrade process
-spec start_upgrade(binary(), binary()) -> ok.
start_upgrade(UpgradeId, VersionTo) ->
    gen_server:cast(?MODULE, {start_upgrade, UpgradeId, VersionTo}).

%% @doc End an upgrade process
-spec end_upgrade(binary(), binary()) -> ok.
end_upgrade(UpgradeId, Result) ->
    gen_server:cast(?MODULE, {end_upgrade, UpgradeId, Result}).

%% @doc Record completed upgrade step
-spec upgrade_step_completed(binary(), binary(), map()) -> ok.
upgrade_step_completed(UpgradeId, StepId, Metrics) ->
    gen_server:cast(?MODULE, {upgrade_step_completed, UpgradeId, StepId, Metrics}).

%% @doc Record failed upgrade step
-spec upgrade_step_failed(binary(), binary(), term()) -> ok.
upgrade_step_failed(UpgradeId, StepId, Reason) ->
    gen_server:cast(?MODULE, {upgrade_step_failed, UpgradeId, StepId, Reason}).

%% @doc Get upgrade progress
-spec upgrade_progress(binary()) -> map().
upgrade_progress(UpgradeId) ->
    gen_server:call(?MODULE, {upgrade_progress, UpgradeId}).

%%% ============================================================================
%%% Upgrade-Specific Metrics
%%% ============================================================================

%% @doc Record upgrade metric with default value
-spec record_upgrade_metric(binary(), integer()) -> ok.
record_upgrade_metric(UpgradeId, Value) ->
    record_upgrade_metric(UpgradeId, Value, #{}).

%% @doc Record upgrade metric with additional data
-spec record_upgrade_metric(binary(), integer(), map()) -> ok.
record_upgrade_metric(UpgradeId, Value, Metadata) ->
    gen_server:cast(?MODULE, {record_upgrade_metric, UpgradeId, Value, Metadata}).

%% @doc Get all upgrade metrics
-spec get_upgrade_metrics() -> map().
get_upgrade_metrics() ->
    gen_server:call(?MODULE, get_upgrade_metrics).

%% @doc Get metrics for specific upgrade
-spec get_upgrade_metrics(binary()) -> map().
get_upgrade_metrics(UpgradeId) ->
    gen_server:call(?MODULE, {get_upgrade_metrics, UpgradeId}).

%%% ============================================================================
%%% Health Monitoring During Upgrades
%%% ============================================================================

%% @doc Check overall system health during upgrade
-spec check_upgrade_health() -> map().
check_upgrade_health() ->
    gen_server:call(?MODULE, check_upgrade_health).

%% @doc Check if system is ready for upgrade
-spec check_upgrade_readiness() -> {boolean(), binary(), map()}.
check_upgrade_readiness() ->
    gen_server:call(?MODULE, check_upgrade_readiness).

%% @doc Get upgrade system health report
-spec get_upgrade_system_health() -> map().
get_upgrade_system_health() ->
    gen_server:call(?MODULE, get_upgrade_system_health).

%%% ============================================================================
%%% Alerting
%%% ============================================================================

%% @doc Set alert threshold for a metric
-spec set_upgrade_alert_threshold(binary(), binary(), term()) -> ok.
set_upgrade_alert_threshold(MetricName, Condition, Threshold) ->
    gen_server:cast(?MODULE, {set_alert_threshold, MetricName, Condition, Threshold}).

%% @doc Send upgrade alert
-spec send_upgrade_alert(binary(), binary(), map()) -> ok.
send_upgrade_alert(UpgradeId, Message, Details) ->
    gen_server:cast(?MODULE, {send_upgrade_alert, UpgradeId, Message, Details}).

%% @doc Get active alerts
-spec get_active_alerts() -> [map()].
get_active_alerts() ->
    gen_server:call(?MODULE, get_active_alerts).

%% @doc Clear all alerts
-spec clear_alerts() -> ok.
clear_alerts() ->
    gen_server:cast(?MODULE, clear_alerts).

%%% ============================================================================
%%% Query Functions
%%% ============================================================================

%% @doc Check if upgrade is in progress
-spec is_upgrade_in_progress() -> boolean().
is_upgrade_in_progress() ->
    gen_server:call(?MODULE, is_upgrade_in_progress).

%% @doc Get current upgrade details
-spec get_current_upgrade() -> map() | undefined.
get_current_upgrade() ->
    gen_server:call(?MODULE, get_current_upgrade).

%% @doc Get upgrade history
-spec get_upgrade_history() -> [map()].
get_upgrade_history() ->
    gen_server:call(?MODULE, get_upgrade_history).

%% @doc Get upgrade summary
-spec get_upgrade_summary() -> map().
get_upgrade_summary() ->
    gen_server:call(?MODULE, get_upgrade_summary).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init(map()) -> {ok, state()} | {ok, state(), {continue, atom()}}.
init(Opts) ->
    SnapshotInterval = maps:get(snapshot_interval_ms, Opts, 30000),
    HealthThreshold = maps:get(health_score_threshold, Opts, 0.8),
    MonitoringEnabled = maps:get(monitoring_enabled, Opts, true),

    %% Initialize default alert rules
    DefaultAlertRules = [
        #alert_rule{
            id = <<"high_cpu_usage">>,
            metric_name = <<"system.cpu_usage">>,
            condition = "greater_than",
            threshold = 90.0,
            level = critical,
            enabled = true,
            last_triggered = undefined
        },
        #alert_rule{
            id = <<"high_memory_usage">>,
            metric_name = <<"system.memory_usage">>,
            condition = "greater_than",
            threshold = 85.0,
            level = critical,
            enabled = true,
            last_triggered = undefined
        },
        #alert_rule{
            id = <<"upgrade_step_failure">>,
            metric_name = <<"upgrade.step_failed">>,
            condition = "equals",
            threshold = true,
            level = warning,
            enabled = true,
            last_triggered = undefined
        },
        #alert_rule{
            id = <<"upgrade_timeout">>,
            metric_name = <<"upgrade.duration">>,
            condition = "greater_than",
            threshold = 300000,  % 5 minutes
            level = critical,
            enabled = true,
            last_triggered = undefined
        }
    ],

    State = #state{
        current_upgrade = undefined,
        upgrade_history = [],
        alert_rules = DefaultAlertRules,
        active_alerts = [],
        monitoring_enabled = MonitoringEnabled,
        snapshot_interval_ms = SnapshotInterval,
        health_score_threshold = HealthThreshold,
        alert_history = [],
        metrics = #{}
    },

    if MonitoringEnabled ->
        %% Schedule health snapshots
        Timer = erlang:send_after(SnapshotInterval, self(), collect_health_snapshot),
        {ok, State#state{snapshot_timer = Timer}, {continue, collect_initial_snapshot}};
       true ->
        {ok, State}
    end.

-spec handle_continue(atom(), state()) -> {ok, state()}.
handle_continue(collect_initial_snapshot, State) ->
    %% Collect initial health snapshot
    NewState = collect_health_snapshot(State),
    {ok, NewState}.

-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()} | {noreply, state()}.
handle_call({upgrade_progress, UpgradeId}, _From, State) ->
    case get_upgrade_record(UpgradeId, State) of
        undefined ->
            {reply, {error, upgrade_not_found}, State};
        UpgradeRecord ->
            Progress = calculate_upgrade_progress(UpgradeRecord),
            {reply, {ok, Progress}, State}
    end;

handle_call(get_upgrade_metrics, _From, State) ->
    AllMetrics = collect_all_upgrade_metrics(State),
    {reply, AllMetrics, State};

handle_call({get_upgrade_metrics, UpgradeId}, _From, State) ->
    case get_upgrade_record(UpgradeId, State) of
        undefined ->
            {reply, {error, upgrade_not_found}, State};
        UpgradeRecord ->
            Metrics = format_upgrade_metrics(UpgradeRecord),
            {reply, {ok, Metrics}, State}
    end;

handle_call(check_upgrade_health, _From, State) ->
    HealthReport = generate_health_report(State),
    {reply, HealthReport, State};

handle_call(check_upgrade_readiness, _From, State) ->
    Readiness = perform_readiness_check(State),
    {reply, Readiness, State};

handle_call(get_upgrade_system_health, _From, State) ->
    HealthReport = generate_system_health_report(State),
    {reply, HealthReport, State};

handle_call(get_active_alerts, _From, State) ->
    AlertList = format_active_alerts(State#state.active_alerts),
    {reply, AlertList, State};

handle_call(is_upgrade_in_progress, _From, State) ->
    InProgress = case State#state.current_upgrade of
        undefined -> false;
        _UpgradeRecord -> is_upgrade_active(State#state.current_upgrade)
    end,
    {reply, InProgress, State};

handle_call(get_current_upgrade, _From, State) ->
    Current = case State#state.current_upgrade of
        undefined -> undefined;
        UpgradeRecord -> format_upgrade_record(UpgradeRecord)
    end,
    {reply, Current, State};

handle_call(get_upgrade_history, _From, State) ->
    History = lists:map(fun format_upgrade_record/1, State#state.upgrade_history),
    {reply, History, State};

handle_call(get_upgrade_summary, _From, State) ->
    Summary = generate_upgrade_summary(State),
    {reply, Summary, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({start_upgrade, UpgradeId, VersionTo}, State) ->
    %% Validate upgrade can start
    case can_start_upgrade(State) of
        true ->
            VersionFrom = get_current_version(),
            UpgradeRecord = #upgrade_record{
                upgrade_id = UpgradeId,
                start_time = erlang:system_time(millisecond),
                status = in_progress,
                version_from = VersionFrom,
                version_to = VersionTo,
                steps = [],
                metrics = #upgrade_metrics{
                    start_time = erlang:system_time(millisecond),
                    last_updated = erlang:system_time(millisecond)
                },
                health_snapshots = [],
                alerts = [],
                rollback_data = undefined
            },

            logger:info("Upgrade started", #{
                upgrade_id => UpgradeId,
                version_from => VersionFrom,
                version_to => VersionTo,
                domain => [a2a, upgrade, monitor]
            }),

            %% Check initial readiness
            {Ready, Reason, ReadinessData} = perform_readiness_check(State),
            if not Ready ->
                    Alert = #active_alert{
                        id = generate_id(),
                        upgrade_id = UpgradeId,
                        rule_id = <<"upgrade_not_ready">>,
                        level = critical,
                        message = <<"Upgrade not ready: ", Reason/binary>>,
                        details = ReadinessData,
                        timestamp = erlang:system_time(millisecond),
                        acknowledged = false,
                        resolved = false
                    },
                    NewState = add_alert(State, Alert),
                    send_alert_notification(Alert),
                    gen_server:cast(?MODULE, {end_upgrade, UpgradeId, not_ready});
               true ->
                    NewState = State#state{
                        current_upgrade = UpgradeRecord,
                        alert_history = []
                    }
            end;

        false ->
            logger:warning("Cannot start upgrade - another upgrade in progress", #{
                domain => [a2a, upgrade, monitor]
            }),
            NewState = State
    end,

    {noreply, NewState};

handle_cast({end_upgrade, UpgradeId, Result}, State) ->
    case get_upgrade_record(UpgradeId, State) of
        undefined ->
            {noreply, State};
        CurrentUpgrade ->
            EndTime = erlang:system_time(millisecond),

            FinalStatus = case Result of
                completed -> completed;
                _ -> failed
            end,

            %% Update metrics
            UpdatedMetrics = CurrentUpgrade#upgrade_record.metrics,
            FinalMetrics = UpdatedMetrics#upgrade_metrics{
                end_time = EndTime,
                total_duration_ms = EndTime - CurrentUpgrade#upgrade_record.start_time,
                last_updated = EndTime
            },

            %% Add to history
            FinalUpgrade = CurrentUpgrade#upgrade_record{
                end_time = EndTime,
                status = FinalStatus,
                metrics = FinalMetrics
            },

            logger:info("Upgrade completed", #{
                upgrade_id => UpgradeId,
                status => FinalStatus,
                duration_ms => FinalMetrics#upgrade_metrics.total_duration_ms,
                domain => [a2a, upgrade, monitor]
            }),

            %% Check for critical alerts
            CriticalAlerts = lists:filter(
                fun(Alert) -> Alert#active_alert.level == critical end,
                CurrentUpgrade#upgrade_record.alerts
            ),

            NewState = State#state{
                current_upgrade = undefined,
                upgrade_history = [FinalUpgrade | State#state.upgrade_history]
            },

            %% If failed, consider rollback
            case FinalStatus of
                failed ->
                    handle_upgrade_failure(FinalUpgrade, NewState);
                _ ->
                    NewState
            end
    end,
    {noreply, NewState};

handle_cast({upgrade_step_completed, UpgradeId, StepId, Metrics}, State) ->
    case get_upgrade_record(UpgradeId, State) of
        undefined ->
            {noreply, State};
        CurrentUpgrade ->
            Step = #upgrade_step{
                step_id = StepId,
                name = <<"Step ", StepId/binary>>,
                start_time = erlang:system_time(millisecond),
                end_time = erlang:system_time(millisecond),
                status = completed,
                metrics = Metrics
            },

            UpdatedSteps = [Step | CurrentUpgrade#upgrade_record.steps],
            UpdatedMetrics = CurrentUpgrade#upgrade_record.metrics,

            NewMetrics = UpdatedMetrics#upgrade_metrics{
                completed_steps = UpdatedMetrics#upgrade_metrics.completed_steps + 1,
                last_updated = erlang:system_time(millisecond)
            },

            FinalUpgrade = CurrentUpgrade#upgrade_record{
                steps = UpdatedSteps,
                metrics = NewMetrics
            },

            logger:info("Upgrade step completed", #[
                {upgrade_id, UpgradeId},
                {step_id, StepId},
                {metrics, Metrics},
                {domain, [a2a, upgrade, monitor]}
            ]),

            {noreply, State#state{current_upgrade = FinalUpgrade}}
    end;

handle_cast({upgrade_step_failed, UpgradeId, StepId, Reason}, State) ->
    case get_upgrade_record(UpgradeId, State) of
        undefined ->
            {noreply, State};
        CurrentUpgrade ->
            Step = #upgrade_step{
                step_id = StepId,
                name = <<"Step ", StepId/binary>>,
                start_time = erlang:system_time(millisecond),
                end_time = erlang:system_time(millisecond),
                status = failed,
                result = Reason
            },

            UpdatedSteps = [Step | CurrentUpgrade#upgrade_record.steps],
            UpdatedMetrics = CurrentUpgrade#upgrade_record.metrics,

            NewMetrics = UpdatedMetrics#upgrade_metrics{
                failed_steps = UpdatedMetrics#upgrade_metrics.failed_steps + 1,
                last_updated = erlang:system_time(millisecond)
            },

            %% Create alert for step failure
            Alert = #active_alert{
                id = generate_id(),
                upgrade_id = UpgradeId,
                rule_id = <<"upgrade_step_failure">>,
                level = warning,
                message = io_lib:format("Upgrade step failed: ~p", [StepId]),
                details = #{step_id => StepId, reason => Reason},
                timestamp = erlang:system_time(millisecond),
                acknowledged = false,
                resolved = false
            },

            FinalUpgrade = CurrentUpgrade#upgrade_record{
                steps = UpdatedSteps,
                metrics = NewMetrics,
                alerts = [Alert | CurrentUpgrade#upgrade_record.alerts]
            },

            logger:warning("Upgrade step failed", #[
                {upgrade_id, UpgradeId},
                {step_id, StepId},
                {reason, Reason},
                {domain, [a2a, upgrade, monitor]}
            ]),

            {noreply, State#state{current_upgrade = FinalUpgrade}}
    end;

handle_cast({record_upgrade_metric, UpgradeId, Value, Metadata}, State) ->
    case get_upgrade_record(UpgradeId, State) of
        undefined ->
            {noreply, State};
        CurrentUpgrade ->
            UpdatedMetrics = CurrentUpgrade#upgrade_record.metrics,
            NewMetrics = UpdatedMetrics#upgrade_metrics{
                last_updated = erlang:system_time(millisecond)
            },

            MetricKey = <<"upgrade.metrics.", UpgradeId/binary>>,
            UpdatedMetricsData = maps:get(MetricKey, State#state.metrics, #{}),
            NewMetricsData = maps:put(<<"value">>, Value, Metadata),

            FinalUpgrade = CurrentUpgrade#upgrade_record{
                metrics = NewMetrics
            },

            {noreply, State#state{
                current_upgrade = FinalUpgrade,
                metrics = maps:put(MetricKey, NewMetricsData, State#state.metrics)
            }}
    end;

handle_cast({set_alert_threshold, MetricName, Condition, Threshold}, State) ->
    AlertRule = #alert_rule{
        id = generate_id(),
        metric_name = MetricName,
        condition = Condition,
        threshold = Threshold,
        level = info,  % Default level, can be updated
        enabled = true,
        last_triggered = undefined
    },

    NewState = State#state{
        alert_rules = [AlertRule | State#state.alert_rules]
    },

    logger:info("Alert threshold set", #[
        {metric_name, MetricName},
        {condition, Condition},
        {threshold, Threshold},
        {domain, [a2a, upgrade, monitor]}
    ]),

    {noreply, NewState};

handle_cast({send_upgrade_alert, UpgradeId, Message, Details}, State) ->
    Alert = #active_alert{
        id = generate_id(),
        upgrade_id = UpgradeId,
        rule_id = <<"manual_alert">>,
        level = maps:get(level, Details, warning),
        message = Message,
        details = Details,
        timestamp = erlang:system_time(millisecond),
        acknowledged = false,
        resolved = false
    },

    NewState = add_alert(State, Alert),
    send_alert_notification(Alert),

    {noreply, NewState};

handle_cast(clear_alerts, State) ->
    logger:info("All alerts cleared", #{domain => [a2a, upgrade, monitor]}),
    {noreply, State#state{active_alerts = []}}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(collect_health_snapshot, State) ->
    NewState = collect_health_snapshot(State),

    %% Reschedule if monitoring is enabled
    if State#state.monitoring_enabled ->
            Timer = erlang:send_after(
                State#state.snapshot_interval_ms,
                self(),
                collect_health_snapshot
            ),
            {noreply, NewState#state{snapshot_timer = Timer}};
       true ->
            {noreply, NewState}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, State) ->
    %% Cancel timer if exists
    case State#state.snapshot_timer of
        undefined -> ok;
        T -> erlang:cancel_timer(T)
    end,
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Get upgrade record by ID
-spec get_upgrade_record(binary(), state()) -> upgrade_record() | undefined.
get_upgrade_record(UpgradeId, State) ->
    case State#state.current_upgrade of
        undefined -> undefined;
        CurrentUpgrade when CurrentUpgrade#upgrade_record.upgrade_id == UpgradeId ->
            CurrentUpgrade;
        _ ->
            %% Check history
            lists:find(fun(U) -> U#upgrade_record.upgrade_id == UpgradeId end,
                      State#state.upgrade_history)
    end.

%% @doc Calculate upgrade progress
-spec calculate_upgrade_progress(upgrade_record()) -> map().
calculate_upgrade_progress(UpgradeRecord) ->
    Steps = UpgradeRecord#upgrade_record.steps,
    TotalSteps = length(Steps),

    CompletedSteps = lists:filter(fun(S) -> S#upgrade_step.status == completed end, Steps),
    FailedSteps = lists:filter(fun(S) -> S#upgrade_step.status == failed end, Steps),

    ProgressPercentage = case TotalSteps of
        0 -> 0;
        _ -> (length(CompletedSteps) / TotalSteps) * 100
    end,

    #{
        upgrade_id => UpgradeRecord#upgrade_record.upgrade_id,
        status => UpgradeRecord#upgrade_record.status,
        progress => ProgressPercentage,
        total_steps => TotalSteps,
        completed_steps => length(CompletedSteps),
        failed_steps => length(FailedSteps),
        start_time => UpgradeRecord#upgrade_record.start_time,
        last_updated => UpgradeRecord#upgrade_record.metrics#upgrade_metrics.last_updated
    }.

%% @doc Collect health snapshot
-spec collect_health_snapshot(state()) -> state().
collect_health_snapshot(State) ->
    Snapshot = #system_health_snapshot{
        timestamp = erlang:system_time(millisecond),
        process_count = erlang:system_info(process_count),
        memory_usage = calculate_memory_usage(),
        cpu_usage = estimate_cpu_usage(),
        disk_usage = calculate_disk_usage(),
        network_io = get_network_io_stats(),
        database_connections = get_database_connection_count(),
        active_tasks = get_active_task_count(),
        upgrade_status => get_current_upgrade_status(State),
        health_score = calculate_health_score(State)
    },

    %% Add to current upgrade or history
    case State#state.current_upgrade of
        undefined ->
            %% Store in general metrics
            SnapshotKey = io_lib:format("health_snapshot_~p", [Snapshot#system_health_snapshot.timestamp]),
            NewMetrics = maps:put(list_to_binary(SnapshotKey), Snapshot, State#state.metrics);
        CurrentUpgrade ->
            UpdatedHealthSnapshots = [Snapshot | CurrentUpgrade#upgrade_record.health_snapshots],
            UpdatedUpgrade = CurrentUpgrade#upgrade_record{
                health_snapshots = UpdatedHealthSnapshots
            },
            NewMetrics = State#state.metrics
    end,

    State#state{
        metrics = NewMetrics
    }.

%% @doc Calculate memory usage percentage
-spec calculate_memory_usage() -> float().
calculate_memory_usage() ->
    TotalMemory = case os:type() of
        {unix, _} ->
            case os:cmd("free -m | awk 'NR==2{print $3}'") of
                [] -> 0;
                Output ->
                    try list_to_integer(string:trim(Output))
                    catch _:_ -> 0
                    end
            end;
        _ -> 0
    end,

    UsedMemory = erlang:memory(total) div (1024 * 1024),

    case TotalMemory of
        0 -> 0.0;
        _ -> (UsedMemory / TotalMemory) * 100
    end.

%% @doc Estimate CPU usage (simplified)
-spec estimate_cpu_usage() -> float().
estimate_cpu_usage() ->
    %% This is a simplified implementation
    %% In production, you'd use OS-specific tools
    case os:type() of
        {unix, _} ->
            case os:cmd("top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\\([0-9.]*\\)%* id.*/\\1/' | awk '{print 100 - $1}'") of
                [] -> 0.0;
                Output ->
                    try list_to_float(string:trim(Output))
                    catch _:_ -> 0.0
                    end
            end;
        _ -> 0.0
    end.

%% @doc Calculate disk usage
-spec calculate_disk_usage() -> float().
calculate_disk_usage() ->
    case os:type() of
        {unix, _} ->
            case os:cmd("df -h / | awk 'NR==2{print $5}'") of
                [] -> 0.0;
                Output ->
                    case string:tokens(string:trim(Output), "%") of
                        [Value] -> list_to_float(Value);
                        _ -> 0.0
                    end
            end;
        _ -> 0.0
    end.

%% @doc Get network I/O statistics
-spec get_network_io_stats() -> map().
get_network_io_stats() ->
    %% This would typically use OS-specific tools
    #{bytes_sent => 0, bytes_received => 0, packets_sent => 0, packets_received => 0}.

%% @doc Get database connection count
-spec get_database_connection_count() -> integer().
get_database_connection_count() ->
    %% Placeholder - would check actual database connections
    0.

%% @doc Get active task count
-spec get_active_task_count() -> integer().
get_active_task_count() ->
    try
        a2a_metrics:get_active_tasks()
    catch
        _:_ -> 0
    end.

%% @doc Get current upgrade status
-spec get_current_upgrade_status(state()) -> atom().
get_current_upgrade_status(State) ->
    case State#state.current_upgrade of
        undefined -> not_started;
        _ -> in_progress
    end.

%% @doc Calculate health score
-spec calculate_health_score(state()) -> float().
calculate_health_score(State) ->
    %% Based on system metrics and alert status
    Metrics = State#state.metrics,
    Alerts = State#state.active_alerts,

    BaseScore = 1.0,

    %% Deduct points for critical alerts
    CriticalAlertCount = lists:filter(fun(A) -> A#active_alert.level == critical end, Alerts),
    AlertDeduction = length(CriticalAlertCount) * 0.2,

    %% Deduct points for high resource usage
    HealthSnapshots = maps:values(filter_recent_health_snapshots(Metrics, 300000)),  % 5 minutes

    ResourceDeduction = case HealthSnapshots of
        [Latest|_] ->
            CPUUsage = Latest#system_health_snapshot.cpu_usage,
            MemoryUsage = Latest#system_health_snapshot.memory_usage,
            min(CPUUsage, MemoryUsage) / 100;
        _ -> 0.0
    end,

    max(0.0, BaseScore - AlertDeduction - ResourceDeduction).

%% @doc Filter recent health snapshots
-spec filter_recent_health_snapshots(map(), integer()) -> map().
filter_recent_health_snapshots(Metrics, MaxAge) ->
    Now = erlang:system_time(millisecond),
    lists:foldl(fun({Key, Value}, Acc) ->
        case Value of
            #system_health_snapshot{timestamp = Timestamp} when Now - Timestamp =< MaxAge ->
                Acc#{Key => Value};
            _ -> Acc
        end
    end, #{}, Metrics).

%% @doc Generate health report
-spec generate_health_report(state()) -> map().
generate_health_report(State) ->
    CurrentHealth = calculate_health_score(State),
    SystemInfo = get_system_info(),

    #{
        health_score => CurrentHealth,
        overall_status => health_status(CurrentHealth),
        system_info => SystemInfo,
        active_alerts => length(State#state.active_alerts),
        critical_alerts => length(lists:filter(
            fun(A) -> A#active_alert.level == critical end,
            State#state.active_alerts
        )),
        last_updated => erlang:system_time(millisecond)
    }.

%% @doc Generate system health report
-spec generate_system_health_report(state()) -> map().
generate_system_health_report(State) ->
    RecentSnapshots = filter_recent_health_snapshots(State#state.metrics, 300000),  % 5 minutes

    AvgCPU = calculate_metric_average(RecentSnapshots, fun(S) -> S#system_health_snapshot.cpu_usage end),
    AvgMemory = calculate_metric_average(RecentSnapshots, fun(S) -> S#system_health_snapshot.memory_usage end),
    AvgNetwork = calculate_metric_average(RecentSnapshots, fun(S) -> S#system_health_snapshot.network_io end),

    #{
        current_metrics => get_latest_system_metrics(State),
        averages => #{
            cpu_usage => AvgCPU,
            memory_usage => AvgMemory,
            network_io => AvgNetwork
        },
        trends => analyze_trends(RecentSnapshots),
        recommendations => generate_health_recommendations(RecentSnapshots),
        timestamp => erlang:system_time(millisecond)
    }.

%% @brief Get latest system metrics
-spec get_latest_system_metrics(state()) -> map().
get_latest_system_metrics(State) ->
    RecentSnapshots = filter_recent_health_snapshots(State#state.metrics, 60000),  % 1 minute
    case RecentSnapshots of
        [Latest|_] -> convert_snapshot_to_metrics(Latest);
        _ -> #{}
    end.

%% @brief Convert health snapshot to metrics map
-spec convert_snapshot_to_metrics(system_health_snapshot()) -> map().
convert_snapshot_to_metrics(Snapshot) ->
    #{
        process_count => Snapshot#system_health_snapshot.process_count,
        memory_usage => Snapshot#system_health_snapshot.memory_usage,
        cpu_usage => Snapshot#system_health_snapshot.cpu_usage,
        disk_usage => Snapshot#system_health_snapshot.disk_usage,
        network_io => Snapshot#system_health_snapshot.network_io,
        database_connections => Snapshot#system_health_snapshot.database_connections,
        active_tasks => Snapshot#system_health_snapshot.active_tasks,
        timestamp => Snapshot#system_health_snapshot.timestamp
    }.

%% @brief Get system information
-spec get_system_info() -> map().
get_system_info() ->
    #{
        node => list_to_binary(atom_to_list(node())),
        otp_release => list_to_binary(erlang:system_info(otp_release)),
        erts_version => list_to_binary(erlang:system_info(version)),
        scheduler_threads => erlang:system_info(schedulers),
        smp_support => erlang:system_info(smp_support),
        kernel_poll => erlang:system_info(kernel_poll)
    }.

%% @brief Calculate average of metric from snapshots
-spec calculate_metric_average(map(), function()) -> number().
calculate_metric_average(Snapshots, MetricFun) ->
    Values = lists:map(fun(Snapshot) -> MetricFun(Snapshot) end, maps:values(Snapshots)),
    case Values of
        [] -> 0;
        _ -> lists:sum(Values) / length(Values)
    end.

%% @brief Analyze trends in health metrics
-spec analyze_trends(map()) -> map().
analyze_trends(Snapshots) ->
    %% Simple trend analysis - in production, this would be more sophisticated
    Values = maps:values(Snapshots),

    if length(Values) < 2 ->
            #{trend => undefined, confidence => 0.0};
       true ->
            %% Simple linear trend calculation
            {Trend, Confidence} = calculate_linear_trend(Values),
            #{trend => Trend, confidence => Confidence}
    end.

%% @brief Calculate linear trend
-spec calculate_linear_trend([system_health_snapshot()]) -> {atom(), float()}.
calculate_linear_trend(Values) ->
    %% Simplified implementation
    #{trend => stable, confidence => 0.75}.

%% @brief Generate health recommendations
-spec generate_health_recommendations(map()) -> [binary()].
generate_health_recommendations(Snapshots) ->
    Recommendations = [],

    %% Add recommendations based on metrics
    case calculate_metric_average(Snapshots, fun(S) -> S#system_health_snapshot.cpu_usage end) of
        Avg when Avg > 80.0 ->
            [<<"Consider scaling up resources due to high CPU usage">>];
        _ ->
            Recommendations
    end.

%% @brief Check if upgrade can start
-spec can_start_upgrade(state()) -> boolean().
can_start_upgrade(State) ->
    State#state.current_upgrade == undefined andalso
    not lists:any(fun(U) -> U#upgrade_record.status == in_progress end, State#state.upgrade_history).

%% @brief Check if upgrade is active
-spec is_upgrade_active(upgrade_record()) -> boolean().
is_upgrade_active(UpgradeRecord) ->
    UpgradeRecord#upgrade_record.status == in_progress.

%% @brief Perform readiness check
-spec perform_readiness_check(state()) -> {boolean(), binary(), map()}.
perform_readiness_check(State) ->
    %% Check system resources
    HealthScore = calculate_health_score(State),

    if HealthScore < State#state.health_score_threshold ->
            {false, <<"System health score below threshold">>, #{health_score => HealthScore}};
       true ->
            %% Check if any upgrade is in progress
            if State#state.current_upgrade /= undefined ->
                    {false, <<"Another upgrade is already in progress">>, #{}};
               true ->
                    {true, <<"System is ready for upgrade">>, #{health_score => HealthScore}}
            end
    end.

%% @brief Handle upgrade failure
-spec handle_upgrade_failure(upgrade_record(), state()) -> state().
handle_upgrade_failure(FailedUpgrade, State) ->
    logger:warning("Upgrade failed, considering rollback", #{
        upgrade_id => FailedUpgrade#upgrade_record.upgrade_id,
        domain => [a2a, upgrade, monitor]
    }),

    %% Prepare rollback data
    RollbackData = #{
        failed_upgrade => FailedUpgrade#upgrade_record.upgrade_id,
        rollback_triggered => false,
        rollback_failed => false,
        rollback_attempts => 0
    },

    %% Add rollback alerts
    CriticalAlert = #active_alert{
        id = generate_id(),
        upgrade_id => FailedUpgrade#upgrade_record.upgrade_id,
        rule_id = <<"upgrade_failure">>,
        level => critical,
        message => <<"Upgrade failed, rollback may be required">>,
        details => FailedUpgrade,
        timestamp => erlang:system_time(millisecond),
        acknowledged => false,
        resolved => false
    },

    add_alert(State, CriticalAlert).

%% @brief Add alert to state
-spec add_alert(state(), active_alert()) -> state().
add_alert(State, Alert) ->
    UpdatedAlerts = [Alert | State#state.active_alerts],

    %% Add to alert history
    AlertHistoryEntry = #{
        id => Alert#active_alert.id,
        upgrade_id => Alert#active_alert.upgrade_id,
        level => Alert#active_alert.level,
        message => Alert#active_alert.message,
        timestamp => Alert#active_alert.timestamp,
        acknowledged => Alert#active_alert.acknowledged
    },

    NewState = State#state{
        active_alerts = UpdatedAlerts,
        alert_history = [AlertHistoryEntry | State#state.alert_history]
    },

    send_alert_notification(Alert),
    NewState.

%% @brief Send alert notification
-spec send_alert_notification(active_alert()) -> ok.
send_alert_notification(Alert) ->
    logger:warning("Upgrade alert", #[
        {id, Alert#active_alert.id},
        {level, Alert#active_alert.level},
        {message, Alert#active_alert.message},
        {timestamp, Alert#active_alert.timestamp},
        {domain, [a2a, upgrade, monitor]}
    ]),

    %% In production, this would send notifications via:
    %% - Email
    %% - Slack/Teams
    %% - PagerDuty
    %% - Custom webhook
    ok.

%% @brief Format active alerts
-spec format_active_alerts([active_alert()]) -> [map()].
format_active_alerts(Alerts) ->
    lists:map(fun format_alert/1, Alerts).

%% @brief Format a single alert
-spec format_alert(active_alert()) -> map().
format_alert(Alert) ->
    #{
        id => Alert#active_alert.id,
        upgrade_id => Alert#active_alert.upgrade_id,
        level => Alert#active_alert.level,
        message => Alert#active_alert.message,
        details => Alert#active_alert.details,
        timestamp => Alert#active_alert.timestamp,
        acknowledged => Alert#active_alert.acknowledged,
        resolved => Alert#active_alert.resolved
    }.

%% @brief Format upgrade record for external API
-spec format_upgrade_record(upgrade_record()) -> map().
format_upgrade_record(UpgradeRecord) ->
    #{
        upgrade_id => UpgradeRecord#upgrade_record.upgrade_id,
        start_time => UpgradeRecord#upgrade_record.start_time,
        end_time => UpgradeRecord#upgrade_record.end_time,
        status => UpgradeRecord#upgrade_record.status,
        version_from => UpgradeRecord#upgrade_record.version_from,
        version_to => UpgradeRecord#upgrade_record.version_to,
        steps => lists:map(fun format_upgrade_step/1, UpgradeRecord#upgrade_record.steps),
        metrics => format_upgrade_metrics(UpgradeRecord),
        health_snapshots => lists:map(fun format_health_snapshot/1,
                                     UpgradeRecord#upgrade_record.health_snapshots),
        alerts => lists:map(fun format_alert/1, UpgradeRecord#upgrade_record.alerts),
        rollback_data => UpgradeRecord#upgrade_record.rollback_data
    }.

%% @brief Format upgrade step
-spec format_upgrade_step(upgrade_step()) -> map().
format_upgrade_step(Step) ->
    #{
        step_id => Step#upgrade_step.step_id,
        name => Step#upgrade_step.name,
        start_time => Step#upgrade_step.start_time,
        end_time => Step#upgrade_step.end_time,
        status => Step#upgrade_step.status,
        result => Step#upgrade_step.result,
        metrics => Step#upgrade_step.metrics
    }.

%% @brief format health snapshot
-spec format_health_snapshot(system_health_snapshot()) -> map().
format_health_snapshot(Snapshot) ->
    #{
        timestamp => Snapshot#system_health_snapshot.timestamp,
        process_count => Snapshot#system_health_snapshot.process_count,
        memory_usage => Snapshot#system_health_snapshot.memory_usage,
        cpu_usage => Snapshot#system_health_snapshot.cpu_usage,
        disk_usage => Snapshot#system_health_snapshot.disk_usage,
        network_io => Snapshot#system_health_snapshot.network_io,
        database_connections => Snapshot#system_health_snapshot.database_connections,
        active_tasks => Snapshot#system_health_snapshot.active_tasks,
        upgrade_status => Snapshot#system_health_snapshot.upgrade_status,
        health_score => Snapshot#system_health_snapshot.health_score
    }.

%% @brief format upgrade metrics
-spec format_upgrade_metrics(upgrade_record()) -> map().
format_upgrade_metrics(UpgradeRecord) ->
    Metrics = UpgradeRecord#upgrade_record.metrics,
    #{
        start_time => Metrics#upgrade_metrics.start_time,
        end_time => Metrics#upgrade_metrics.end_time,
        total_steps => Metrics#upgrade_metrics.total_steps,
        completed_steps => Metrics#upgrade_metrics.completed_steps,
        failed_steps => Metrics#upgrade_metrics.failed_steps,
        total_duration_ms => Metrics#upgrade_metrics.total_duration_ms,
        critical_alerts => Metrics#upgrade_metrics.critical_alerts,
        non_critical_alerts => Metrics#upgrade_metrics.non_critical_alerts,
        system_impact_score => Metrics#upgrade_metrics.system_impact_score,
        last_updated => Metrics#upgrade_metrics.last_updated
    }.

%% @brief Collect all upgrade metrics
-spec collect_all_upgrade_metrics(state()) -> map().
collect_all_upgrade_metrics(State) ->
    CurrentMetrics = case State#state.current_upgrade of
        undefined -> #{};
        UpgradeRecord -> format_upgrade_metrics(UpgradeRecord)
    end,

    HistoryMetrics = lists:map(fun format_upgrade_metrics/1, State#state.upgrade_history),

    #{
        current => CurrentMetrics,
        history => HistoryMetrics,
        system_metrics => State#state.metrics
    }.

%% @brief Generate upgrade summary
-spec generate_upgrade_summary(state()) -> map().
generate_upgrade_summary(State) ->
    TotalUpgrades = length(State#state.upgrade_history),
    ActiveUpgrade = case State#state.current_upgrade of
        undefined -> undefined;
        UpgradeRecord -> UpgradeRecord#upgrade_record.upgrade_id
    end,

    CompletedUpgrades = lists:filter(fun(U) -> U#upgrade_record.status == completed end,
                                     State#state.upgrade_history),
    FailedUpgrades = lists:filter(fun(U) -> U#upgrade_record.status == failed end,
                                  State#state.upgrade_history),

    LatestUpgrade = case CompletedUpgrades of
        [Latest|_] -> Latest;
        _ -> undefined
    end,

    #{
        total_upgrades => TotalUpgrades,
        completed_upgrades => length(CompletedUpgrades),
        failed_upgrades => length(FailedUpgrades),
        active_upgrade => ActiveUpgrade,
        success_rate => case TotalUpgrades of
            0 -> 0.0;
            _ -> length(CompletedUpgrades) / TotalUpgrades
        end,
        latest_upgrade => case LatestUpgrade of
            undefined -> undefined;
            U -> format_upgrade_metrics(U)
        end,
        current_health => calculate_health_score(State),
        active_alerts => length(State#state.active_alerts)
    }.

%% @brief Get current version
-spec get_current_version() -> binary().
get_current_version() ->
    %% In production, this would read from application version or git tags
    <<"0.4.0">>.

%% @brief Determine health status from score
-spec health_status(float()) -> atom().
health_status(Score) when Score >= 0.9 -> excellent;
health_status(Score) when Score >= 0.7 -> good;
health_status(Score) when Score >= 0.5 -> fair;
health_status(Score) when Score >= 0.3 -> poor;
health_status(_) -> critical.

%% @brief Generate UUID
-spec generate_id() -> binary().
generate_id() ->
    Bytes = crypto:strong_rand_bytes(16),
    Hex = binary:encode_hex(Bytes),
    <<A:8/binary, B:4/binary, C:4/binary, D:4/binary, E:12/binary>> = Hex,
    <<A/binary, "-", B/binary, "-", C/binary, "-", D/binary, "-", E/binary>>.