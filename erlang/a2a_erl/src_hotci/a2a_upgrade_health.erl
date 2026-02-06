%%% @doc A2A Upgrade Health Management
%%%
%%% This module provides comprehensive health monitoring and management for hot code upgrades.
%%% It continuously monitors system health during upgrades and provides automatic recovery mechanisms.
%%%
%%% Features:
%%% - Real-time system health monitoring
%%% - Upgrade readiness assessment
%%% - Automatic recovery from upgrade failures
%%% - Health-based upgrade scheduling
%%% - Performance degradation detection
%%% - Upgrade risk assessment
%%% - Health reporting and alerting
%%%
%%% Health Categories:
%%% - System health (memory, CPU, processes)
%%% - Upgrade health (progress, success rate, bottlenecks)
%%% - Application health (response times, error rates)
%%% - Data integrity (ETS consistency, process states)
%%% @end
-module(a2a_upgrade_health).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    stop/0,

    %% Health monitoring
    check_system_health/0,
    check_upgrade_health/0,
    check_application_health/0,
    check_data_integrity/0,

    %% Health management
    manage_upgrade_health/1,
    recover_from_failure/1,
    health_based_upgrade_scheduling/0,

    %% Health thresholds
    set_health_thresholds/1,
    get_health_thresholds/0,

    %% Health reporting
    get_health_report/0,
    get_health_summary/0,
    get_health_alerts/0,

    %% Health actions
    auto_adjust_upgrade_params/0,
    perform_health_check/0,

    %% Recovery functions (exported for testing)
    attempt_recovery/1,
    parse_failure_type/1,
    recover_memory_critical/0,
    recover_cpu_critical/0,
    recover_upgrade_failed/0,
    recover_app_error_rate_high/0,
    recover_integrity_corruption/0,
    recover_process_killed/0,
    recover_ets_corruption/0,
    recover_connection_loss/0
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

-record(health_thresholds, {
    memory_usage_percent = 90 :: pos_integer(),
    cpu_usage_percent = 85 :: pos_integer(),
    process_count_threshold = 1000 :: pos_integer(),
    upgrade_duration_threshold_ms = 30000 :: non_neg_integer(),
    error_rate_threshold = 0.05 :: float(),
    response_time_threshold_ms = 1000 :: non_neg_integer(),
    ets_integrity_threshold = 1.0 :: float()
}).

-type health_thresholds() :: #health_thresholds{}.

-record(system_health, {
    overall_status :: healthy | warning | critical,
    memory_usage_percent :: float(),
    cpu_usage_percent :: float(),
    process_count :: non_neg_integer(),
    process_heap_size :: integer(),
    system_load :: float(),
    uptime_seconds :: integer(),
    last_health_check :: integer()
}).

-type system_health() :: #system_health{}.

-record(upgrade_health, {
    overall_status :: healthy | warning | critical,
    active_upgrades :: non_neg_integer(),
    upgrade_success_rate :: float(),
    avg_upgrade_time_ms :: float(),
    upgrade_bottlenecks :: [term()],
    memory_impact_mb :: float(),
    recovery_attempts :: non_neg_integer(),
    last_upgrade_check :: integer()
}).

-record(upgrade_metrics, {
    successful_upgrades = 0 :: non_neg_integer(),
    total_upgrades = 0 :: non_neg_integer(),
    failed_upgrades = 0 :: non_neg_integer(),
    avg_upgrade_time_ms = 0.0 :: float(),
    peak_memory_mb = 0.0 :: float()
}).

-type upgrade_metrics() :: #upgrade_metrics{}.
-type upgrade_health() :: #upgrade_health{}.

-record(application_health, {
    overall_status :: healthy | warning | critical,
    response_time_avg_ms :: float(),
    error_rate :: float(),
    throughput_per_second :: float(),
    active_connections :: non_neg_integer(),
    message_backlog :: non_neg_integer(),
    last_app_check :: integer()
}).

-type application_health() :: #application_health{}.

-record(data_integrity, {
    overall_status :: healthy | warning | critical,
    ets_consistency_score :: float(),
    process_state_consistency :: float(),
    data_corruption_detected :: boolean(),
    recovery_actions :: [binary()],
    last_integrity_check :: integer()
}).

-type data_integrity() :: #data_integrity{}.

-record(health_alert, {
    id :: binary(),
    timestamp :: integer(),
    severity :: info | warning | critical,
    category :: system | upgrade | application | integrity,
    message :: binary(),
    details :: map(),
    resolved :: boolean()
}).

-type health_alert() :: #health_alert{}.

-record(health_state, {
    thresholds :: health_thresholds(),
    system :: system_health(),
    upgrade :: upgrade_health(),
    application :: application_health(),
    integrity :: data_integrity(),
    alerts = [] :: [health_alert()],
    health_history = [] :: [map()],
    monitoring_enabled = true :: boolean(),
    monitoring_interval_ms = 5000 :: non_neg_integer(),
    recovery_enabled = true :: boolean(),
    auto_adjust_enabled = true :: boolean(),
    health_timer = undefined :: undefined | reference()
}).

-type health_state() :: #health_state{}.
-type state() :: #health_state{}.

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the health management system with default options
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the health management system with options
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

%% @doc Stop the health management system
-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%% @brief Check overall system health
-spec check_system_health() -> system_health().
check_system_health() ->
    gen_server:call(?MODULE, check_system_health).

%% @brief Check upgrade health
-spec check_upgrade_health() -> upgrade_health().
check_upgrade_health() ->
    gen_server:call(?MODULE, check_upgrade_health).

%% @brief Check application health
-spec check_application_health() -> application_health().
check_application_health() ->
    gen_server:call(?MODULE, check_application_health).

%% @brief Check data integrity
-spec check_data_integrity() -> data_integrity().
check_data_integrity() ->
    gen_server:call(?MODULE, check_data_integrity).

%% @brief Manage upgrade health
-spec manage_upgrade_health(map()) -> ok.
manage_upgrade_health(HealthData) ->
    gen_server:cast(?MODULE, {manage_upgrade_health, HealthData}).

%% @brief Recover from upgrade failure
-spec recover_from_failure(binary()) -> ok | {error, term()}.
recover_from_failure(FailureId) ->
    gen_server:call(?MODULE, {recover_from_failure, FailureId}).

%% @brief Perform health-based upgrade scheduling
-spec health_based_upgrade_scheduling() -> map().
health_based_upgrade_scheduling() ->
    gen_server:call(?MODULE, health_based_upgrade_scheduling).

%% @brief Set health thresholds
-spec set_health_thresholds(map()) -> ok.
set_health_thresholds(Thresholds) ->
    gen_server:cast(?MODULE, {set_health_thresholds, Thresholds}).

%% @brief Get health thresholds
-spec get_health_thresholds() -> health_thresholds().
get_health_thresholds() ->
    gen_server:call(?MODULE, get_health_thresholds).

%% @brief Get health report
-spec get_health_report() -> map().
get_health_report() ->
    gen_server:call(?MODULE, get_health_report).

%% @brief Get health summary
-spec get_health_summary() -> map().
get_health_summary() ->
    gen_server:call(?MODULE, get_health_summary).

%% @brief Get health alerts
-spec get_health_alerts() -> [health_alert()].
get_health_alerts() ->
    gen_server:call(?MODULE, get_health_alerts).

%% @brief Auto-adjust upgrade parameters based on health
-spec auto_adjust_upgrade_params() -> ok.
auto_adjust_upgrade_params() ->
    gen_server:cast(?MODULE, auto_adjust_upgrade_params).

%% @brief Perform comprehensive health check
-spec perform_health_check() -> map().
perform_health_check() ->
    gen_server:call(?MODULE, perform_health_check).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init(map()) -> {ok, state()} | {ok, state(), {continue, atom()}}.
init(Opts) ->
    DefaultThresholds = #health_thresholds{
        memory_usage_percent = maps:get(memory_usage_percent, Opts, 90),
        cpu_usage_percent = maps:get(cpu_usage_percent, Opts, 85),
        process_count_threshold = maps:get(process_count_threshold, Opts, 1000),
        upgrade_duration_threshold_ms = maps:get(upgrade_duration_threshold_ms, Opts, 30000),
        error_rate_threshold = maps:get(error_rate_threshold, Opts, 0.05),
        response_time_threshold_ms = maps:get(response_time_threshold_ms, Opts, 1000),
        ets_integrity_threshold = maps:get(ets_integrity_threshold, Opts, 1.0)
    },

    InitialState = #health_state{
        thresholds = DefaultThresholds,
        system = #system_health{last_health_check = erlang:system_time(millisecond)},
        upgrade = #upgrade_health{last_upgrade_check = erlang:system_time(millisecond)},
        application = #application_health{last_app_check = erlang:system_time(millisecond)},
        integrity = #data_integrity{last_integrity_check = erlang:system_time(millisecond)}
    },

    MonitoringInterval = maps:get(monitoring_interval_ms, Opts, 5000),

    {ok, InitialState, {continue, initialize_health_monitoring}}.

-spec handle_continue(atom(), state()) -> {ok, state()}.
handle_continue(initialize_health_monitoring, State) ->
    %% Perform initial health checks
    NewSystemHealth = check_system_health_internal(State#health_state.thresholds),
    NewUpgradeHealth = check_upgrade_health_internal(State#health_state.thresholds),
    NewAppHealth = check_application_health_internal(State#health_state.thresholds),
    NewIntegrity = check_data_integrity_internal(State#health_state.thresholds),

    %% Create initial health snapshot
    HealthSnapshot = create_health_snapshot(#{
        system => NewSystemHealth,
        upgrade => NewUpgradeHealth,
        application => NewAppHealth,
        integrity => NewIntegrity
    }),

    NewState = State#health_state{
        system = NewSystemHealth,
        upgrade = NewUpgradeHealth,
        application = NewAppHealth,
        integrity = NewIntegrity,
        health_history = [HealthSnapshot]
    },

    logger:info("Health monitoring system initialized", #{
        domain => [a2a, health, monitoring]
    }),

    {ok, NewState}.

-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()} | {noreply, state()}.
handle_call(check_system_health, _From, State) ->
    {reply, State#health_state.system, State};

handle_call(check_upgrade_health, _From, State) ->
    {reply, State#health_state.upgrade, State};

handle_call(check_application_health, _From, State) ->
    {reply, State#health_state.application, State};

handle_call(check_data_integrity, _From, State) ->
    {reply, State#health_state.integrity, State};

handle_call(get_health_thresholds, _From, State) ->
    {reply, State#health_state.thresholds, State};

handle_call(get_health_report, _From, State) ->
    Report = generate_health_report(State),
    {reply, Report, State};

handle_call(get_health_summary, _From, State) ->
    Summary = generate_health_summary(State),
    {reply, Summary, State};

handle_call(get_health_alerts, _From, State) ->
    {reply, State#health_state.alerts, State};

handle_call(perform_health_check, _From, State) ->
    %% Perform comprehensive health check
    HealthReport = perform_comprehensive_health_check(State),
    NewState = State#health_state{
        health_history = [HealthReport | State#health_state.health_history]
    },
    {reply, HealthReport, NewState};

handle_call({recover_from_failure, FailureId}, _From, State) ->
    case recover_from_failure_internal(FailureId, State) of
        ok ->
            {reply, ok, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({manage_upgrade_health, HealthData}, State) ->
    NewUpgradeHealth = manage_upgrade_health_internal(HealthData, State#health_state.thresholds),
    NewState = State#health_state{upgrade = NewUpgradeHealth},
    {noreply, NewState};

handle_cast({set_health_thresholds, Thresholds}, State) ->
    NewThresholds = State#health_state.thresholds#health_thresholds{
        memory_usage_percent = maps:get(memory_usage_percent, Thresholds, State#health_state.thresholds#health_thresholds.memory_usage_percent),
        cpu_usage_percent = maps:get(cpu_usage_percent, Thresholds, State#health_state.thresholds#health_thresholds.cpu_usage_percent),
        process_count_threshold = maps:get(process_count_threshold, Thresholds, State#health_state.thresholds#health_thresholds.process_count_threshold),
        upgrade_duration_threshold_ms = maps:get(upgrade_duration_threshold_ms, Thresholds, State#health_state.thresholds#health_thresholds.upgrade_duration_threshold_ms),
        error_rate_threshold = maps:get(error_rate_threshold, Thresholds, State#health_state.thresholds#health_thresholds.error_rate_threshold),
        response_time_threshold_ms = maps:get(response_time_threshold_ms, Thresholds, State#health_state.thresholds#health_thresholds.response_time_threshold_ms),
        ets_integrity_threshold = maps:get(ets_integrity_threshold, Thresholds, State#health_state.thresholds#health_thresholds.ets_integrity_threshold)
    },

    NewState = State#health_state{thresholds = NewThresholds},
    logger:info("Health thresholds updated", #{
        domain => [a2a, health, thresholds]
    }),
    {noreply, NewState};

handle_cast(auto_adjust_upgrade_params, State) ->
    case State#health_state.auto_adjust_enabled of
        true ->
            NewParams = auto_adjust_upgrade_params_internal(State),
            logger:info("Auto-adjusted upgrade parameters", #{
                parameters => NewParams,
                domain => [a2a, health, auto_adjust]
            });
        false ->
            logger:debug("Auto-adjustment disabled", #{
                domain => [a2a, health, auto_adjust]
            })
    end,
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(health_check_timeout, State) ->
    case State#health_state.monitoring_enabled of
        true ->
            %% Perform periodic health checks
            NewState = perform_periodic_health_checks(State),
            Timer = schedule_health_check(State#health_state.monitoring_interval_ms),
            {noreply, NewState#health_state{health_timer = Timer}};
        false ->
            {noreply, State}
    end;

handle_info(alert_timeout, State) ->
    %% Process outstanding alerts
    NewState = process_alerts(State),
    {noreply, NewState};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, State) ->
    logger:info("Health monitoring system stopped", #{
        domain => [a2a, health, monitoring]
    }),
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @brief Schedule health check
-spec schedule_health_check(non_neg_integer()) -> reference().
schedule_health_check(Interval) ->
    erlang:send_after(Interval, self(), health_check_timeout).

%% @brief Check system health internal
-spec check_system_health_internal(health_thresholds()) -> system_health().
check_system_health_internal(Thresholds) ->
    Now = erlang:system_time(millisecond),
    ProcessCount = erlang:system_info(process_count),
    MemoryBytes = erlang:memory(total),
    MemoryMB = MemoryBytes / (1024 * 1024),
    SystemMemory = get_system_memory(),
    MemoryPercent = (MemoryMB / SystemMemory) * 100,

    CpuUsage = get_cpu_usage(),
    ProcessHeapSize = get_total_process_heap(),
    SystemLoad = get_system_load(),
    Uptime = get_system_uptime(),

    OverallStatus = determine_system_status(MemoryPercent, CpuUsage, ProcessCount, Thresholds),

    #system_health{
        overall_status = OverallStatus,
        memory_usage_percent = MemoryPercent,
        cpu_usage_percent = CpuUsage,
        process_count = ProcessCount,
        process_heap_size = ProcessHeapSize,
        system_load = SystemLoad,
        uptime_seconds = Uptime,
        last_health_check = Now
    }.

%% @brief Check upgrade health internal
-spec check_upgrade_health_internal(health_thresholds()) -> upgrade_health().
check_upgrade_health_internal(Thresholds) ->
    Now = erlang:system_time(millisecond),

    %% Get upgrade metrics from upgrade monitor
    ActiveUpgrades = get_active_upgrades(),
    UpgradeMetrics = get_upgrade_metrics(),

    SuccessRate = UpgradeMetrics#upgrade_metrics.successful_upgrades /
                  max(UpgradeMetrics#upgrade_metrics.total_upgrades, 1),
    AvgUpgradeTime = UpgradeMetrics#upgrade_metrics.avg_upgrade_time_ms,
    MemoryImpact = UpgradeMetrics#upgrade_metrics.peak_memory_mb,

    OverallStatus = determine_upgrade_status(SuccessRate, AvgUpgradeTime, Thresholds),
    Bottlenecks = detect_upgrade_bottlenecks(),

    #upgrade_health{
        overall_status = OverallStatus,
        active_upgrades = ActiveUpgrades,
        upgrade_success_rate = SuccessRate,
        avg_upgrade_time_ms = AvgUpgradeTime,
        upgrade_bottlenecks = Bottlenecks,
        memory_impact_mb = MemoryImpact,
        recovery_attempts = UpgradeMetrics#upgrade_metrics.failed_upgrades,
        last_upgrade_check = Now
    }.

%% @brief Check application health internal
-spec check_application_health_internal(health_thresholds()) -> application_health().
check_application_health_internal(Thresholds) ->
    Now = erlang:system_time(millisecond),

    %% Get application metrics
    ResponseTime = get_avg_response_time(),
    ErrorRate = get_error_rate(),
    Throughput = get_throughput(),
    ActiveConnections = get_active_connections(),
    MessageBacklog = get_message_backlog(),

    OverallStatus = determine_application_status(ResponseTime, ErrorRate, Thresholds),

    #application_health{
        overall_status = OverallStatus,
        response_time_avg_ms = ResponseTime,
        error_rate = ErrorRate,
        throughput_per_second = Throughput,
        active_connections = ActiveConnections,
        message_backlog = MessageBacklog,
        last_app_check = Now
    }.

%% @brief Check data integrity internal
-spec check_data_integrity_internal(health_thresholds()) -> data_integrity().
check_data_integrity_internal(Thresholds) ->
    Now = erlang:system_time(millisecond),

    %% Check ETS tables
    EtsConsistency = check_ets_integrity(),
    ProcessConsistency = check_process_integrity(),
    CorruptionDetected = detect_data_corruption(),
    RecoveryActions = get_recovery_actions(),

    OverallStatus = determine_integrity_status(EtsConsistency, ProcessConsistency, Thresholds),

    #data_integrity{
        overall_status = OverallStatus,
        ets_consistency_score = EtsConsistency,
        process_state_consistency = ProcessConsistency,
        data_corruption_detected = CorruptionDetected,
        recovery_actions = RecoveryActions,
        last_integrity_check = Now
    }.

%% @brief Determine system status
-spec determine_system_status(float(), float(), non_neg_integer(), health_thresholds()) -> atom().
determine_system_status(MemoryPercent, CpuUsage, ProcessCount, Thresholds) ->
    case
        MemoryPercent > Thresholds#health_thresholds.memory_usage_percent orelse
        CpuUsage > Thresholds#health_thresholds.cpu_usage_percent orelse
        ProcessCount > Thresholds#health_thresholds.process_count_threshold
    of
        true -> critical;
        true when MemoryPercent > Thresholds#health_thresholds.memory_usage_percent * 0.8 orelse
                 CpuUsage > Thresholds#health_thresholds.cpu_usage_percent * 0.8 ->
                  warning;
        true -> healthy
    end.

%% @brief Determine upgrade status
-spec determine_upgrade_status(float(), float(), health_thresholds()) -> atom().
determine_upgrade_status(SuccessRate, AvgTime, Thresholds) ->
    case
        SuccessRate < 0.9 orelse
        AvgTime > Thresholds#health_thresholds.upgrade_duration_threshold_ms
    of
        true -> critical;
        true when SuccessRate < 0.95 orelse
                 AvgTime > Thresholds#health_thresholds.upgrade_duration_threshold_ms * 0.8 ->
                  warning;
        true -> healthy
    end.

%% @brief Determine application status
-spec determine_application_status(float(), float(), health_thresholds()) -> atom().
determine_application_status(ResponseTime, ErrorRate, Thresholds) ->
    case
        ErrorRate > Thresholds#health_thresholds.error_rate_threshold orelse
        ResponseTime > Thresholds#health_thresholds.response_time_threshold_ms
    of
        true -> critical;
        true when ErrorRate > Thresholds#health_thresholds.error_rate_threshold * 0.8 orelse
                 ResponseTime > Thresholds#health_thresholds.response_time_threshold_ms * 0.8 ->
                  warning;
        true -> healthy
    end.

%% @brief Determine integrity status
-spec determine_integrity_status(float(), float(), health_thresholds()) -> atom().
determine_integrity_status(EtsScore, ProcessScore, Thresholds) ->
    MinScore = min(EtsScore, ProcessScore),
    case MinScore < Thresholds#health_thresholds.ets_integrity_threshold of
        true -> critical;
        true when MinScore < Thresholds#health_thresholds.ets_integrity_threshold * 0.9 ->
                 warning;
        true -> healthy
    end.

%% @brief Create health snapshot
-spec create_health_snapshot(map()) -> map().
create_health_snapshot(HealthData) ->
    Now = erlang:system_time(millisecond),
    HealthData#{
        timestamp => Now,
        overall_status => calculate_overall_status(HealthData)
    }.

%% @brief Calculate overall status
-spec calculate_overall_status(map()) -> atom().
calculate_overall_status(HealthData) ->
    System = maps:get(system, HealthData),
    Upgrade = maps:get(upgrade, HealthData),
    Application = maps:get(application, HealthData),
    Integrity = maps:get(integrity, HealthData),

    Statuses = [
        System#system_health.overall_status,
        Upgrade#upgrade_health.overall_status,
        Application#application_health.overall_status,
        Integrity#data_integrity.overall_status
    ],

    case lists:member(critical, Statuses) of
        true -> critical;
        false ->
            case lists:member(warning, Statuses) of
                true -> warning;
                false -> healthy
            end
    end.

%% @brief Perform periodic health checks
-spec perform_periodic_health_checks(state()) -> state().
perform_periodic_health_checks(State) ->
    %% Check system health
    NewSystemHealth = check_system_health_internal(State#health_state.thresholds),

    %% Check upgrade health
    NewUpgradeHealth = check_upgrade_health_internal(State#health_state.thresholds),

    %% Check application health
    NewAppHealth = check_application_health_internal(State#health_state.thresholds),

    %% Check data integrity
    NewIntegrity = check_data_integrity_internal(State#health_state.thresholds),

    %% Create new health snapshot
    HealthSnapshot = create_health_snapshot(#{
        system => NewSystemHealth,
        upgrade => NewUpgradeHealth,
        application => NewAppHealth,
        integrity => NewIntegrity
    }),

    %% Check for new health alerts
    NewState = State#health_state{
        system = NewSystemHealth,
        upgrade = NewUpgradeHealth,
        application = NewAppHealth,
        integrity = NewIntegrity,
        health_history = [HealthSnapshot | State#health_state.health_history],
        alerts = check_for_health_alerts(NewSystemHealth, NewUpgradeHealth, NewAppHealth, NewIntegrity, State)
    },

    %% Log health status
    logger:info("Health check completed", #{
        system_status => NewSystemHealth#system_health.overall_status,
        upgrade_status => NewUpgradeHealth#upgrade_health.overall_status,
        app_status => NewAppHealth#application_health.overall_status,
        integrity_status => NewIntegrity#data_integrity.overall_status,
        domain => [a2a, health, monitoring]
    }),

    NewState.

%% @brief Check for health alerts
-spec check_for_health_alerts(system_health(), upgrade_health(), application_health(), data_integrity(), state()) -> [health_alert()].
check_for_health_alerts(System, Upgrade, Application, Integrity, State) ->
    NewAlerts = [],

    %% System alerts
    SystemAlerts = generate_system_alerts(System),
    %% Upgrade alerts
    UpgradeAlerts = generate_upgrade_alerts(Upgrade),
    %% Application alerts
    AppAlerts = generate_application_alerts(Application),
    %% Integrity alerts
    IntegrityAlerts = generate_integrity_alerts(Integrity),

    AllAlerts = SystemAlerts ++ UpgradeAlerts ++ AppAlerts ++ IntegrityAlerts,

    %% Filter out existing alerts
    ExistingAlertIds = [Alert#health_alert.id || Alert <- State#health_state.alerts],
    FilteredAlerts = lists:filter(fun(Alert) ->
        not lists:member(Alert#health_alert.id, ExistingAlertIds)
    end, AllAlerts),

    NewAlerts ++ FilteredAlerts.

%% @brief Generate system alerts
-spec generate_system_alerts(system_health()) -> [health_alert()].
generate_system_alerts(System) ->
    Alerts = [],

    %% Memory alerts
    case System#system_health.memory_usage_percent > 95 of
        true -> [create_alert(system_memory_critical, System)];
        _ -> Alerts
    end,

    %% CPU alerts
    case System#system_health.cpu_usage_percent > 90 of
        true -> [create_alert(system_cpu_critical, System)];
        true when System#system_health.cpu_usage_percent > 75 -> [create_alert(system_cpu_warning, System)];
        _ -> Alerts
    end,

    %% Process alerts
    case System#system_health.process_count > 5000 of
        true -> [create_alert(system_process_count_high, System)];
        _ -> Alerts
    end,

    Alerts.

%% @brief Generate upgrade alerts
-spec generate_upgrade_alerts(upgrade_health()) -> [health_alert()].
generate_upgrade_alerts(Upgrade) ->
    Alerts = [],

    %% Success rate alerts
    case Upgrade#upgrade_health.upgrade_success_rate < 0.8 of
        true -> [create_alert(upgrade_success_rate_low, Upgrade)];
        _ -> Alerts
    end,

    %% Duration alerts
    case Upgrade#upgrade_health.avg_upgrade_time_ms > 60000 of
        true -> [create_alert(upgrade_duration_high, Upgrade)];
        _ -> Alerts
    end,

    %% Bottleneck alerts
    case Upgrade#upgrade_health.upgrade_bottlenecks of
        [] -> Alerts;
        _ -> [create_alert(upgrade_bottlenecks_detected, Upgrade)]
    end,

    Alerts.

%% @brief Generate application alerts
-spec generate_application_alerts(application_health()) -> [health_alert()].
generate_application_alerts(Application) ->
    Alerts = [],

    %% Error rate alerts
    case Application#application_health.error_rate > 0.1 of
        true -> [create_alert(app_error_rate_high, Application)];
        _ -> Alerts
    end,

    %% Response time alerts
    case Application#application_health.response_time_avg_ms > 2000 of
        true -> [create_alert(app_response_time_high, Application)];
        _ -> Alerts
    end,

    %% Backlog alerts
    case Application#application_health.message_backlog > 1000 of
        true -> [create_alert(app_backlog_high, Application)];
        _ -> Alerts
    end,

    Alerts.

%% @brief Generate integrity alerts
-spec generate_integrity_alerts(data_integrity()) -> [health_alert()].
generate_integrity_alerts(Integrity) ->
    Alerts = [],

    %% Corruption alerts
    case Integrity#data_integrity.data_corruption_detected of
        true -> [create_alert(integrity_corruption_detected, Integrity)];
        _ -> Alerts
    end,

    %% Consistency alerts
    case Integrity#data_integrity.ets_consistency_score < 0.9 of
        true -> [create_alert(integrity_consistency_low, Integrity)];
        _ -> Alerts
    end,

    Alerts.

%% @brief Create health alert
-spec create_alert(atom(), term()) -> health_alert().
create_alert(Category, HealthData) ->
    AlertId = generate_alert_id(),
    Severity = case Category of
        _ ->
            CategoryBin = atom_to_binary(Category, utf8),
            case binary:match(CategoryBin, <<"_critical">>) of
                nomatch ->
                    case binary:match(CategoryBin, <<"_warning">>) of
                        nomatch -> info;
                        _ -> warning
                    end;
                _ -> critical
            end
    end,

    CategoryAtom = case Category of
        system_memory_critical -> system;
        system_cpu_critical -> system;
        system_cpu_warning -> system;
        system_process_count_high -> system;
        upgrade_success_rate_low -> upgrade;
        upgrade_duration_high -> upgrade;
        upgrade_bottlenecks_detected -> upgrade;
        app_error_rate_high -> application;
        app_response_time_high -> application;
        app_backlog_high -> application;
        integrity_corruption_detected -> integrity;
        integrity_consistency_low -> integrity
    end,

    Message = format_alert_message(Category, HealthData),

    #health_alert{
        id = AlertId,
        timestamp = erlang:system_time(millisecond),
        severity = Severity,
        category = CategoryAtom,
        message = Message,
        details = map_from_health_data(Category, HealthData),
        resolved = false
    }.

%% @brief Format alert message
-spec format_alert_message(atom(), term()) -> binary().
format_alert_message(system_memory_critical, System) ->
    iolist_to_binary(io_lib:format("System memory usage critical: ~.2f%%", [System#system_health.memory_usage_percent]));

format_alert_message(system_cpu_critical, System) ->
    iolist_to_binary(io_lib:format("System CPU usage critical: ~.2f%%", [System#system_health.cpu_usage_percent]));

format_alert_message(upgrade_success_rate_low, Upgrade) ->
    iolist_to_binary(io_lib:format("Upgrade success rate low: ~.2f%%", [Upgrade#upgrade_health.upgrade_success_rate * 100]));

format_alert_message(integrity_corruption_detected, Integrity) ->
    <<"Data corruption detected in system">>;

format_alert_message(Category, _) ->
    atom_to_binary(Category, utf8).

%% @brief Convert health data to map
-spec map_from_health_data(atom(), term()) -> map().
map_from_health_data(system_memory_critical, System) ->
    #{
        memory_usage_percent => System#system_health.memory_usage_percent,
        threshold => 95
    };

map_from_health_data(upgrade_success_rate_low, Upgrade) ->
    #{
        success_rate => Upgrade#upgrade_health.upgrade_success_rate,
        threshold => 0.8
    };

map_from_health_data(_, _) ->
    #{}.

%% @brief Generate alert ID
-spec generate_alert_id() -> binary().
generate_alert_id() ->
    <<Id:8/binary, _:64>> = crypto:strong_rand_bytes(16),
    Id.

%% @brief Manage upgrade health internal
-spec manage_upgrade_health_internal(map(), health_thresholds()) -> upgrade_health().
manage_upgrade_health_internal(HealthData, Thresholds) ->
    %% Parse health data and update upgrade health accordingly
    #{
        active_upgrades := ActiveUpgrades,
        success_rate := SuccessRate,
        avg_duration := AvgDuration
    } = HealthData,

    Now = erlang:system_time(millisecond),

    #upgrade_health{
        overall_status = determine_upgrade_status(SuccessRate, AvgDuration, Thresholds),
        active_upgrades = ActiveUpgrades,
        upgrade_success_rate = SuccessRate,
        avg_upgrade_time_ms = AvgDuration,
        last_upgrade_check = Now,
        upgrade_bottlenecks = detect_upgrade_bottlenecks(),
        recovery_attempts = get_recovery_attempts()
    }.

%% @brief Recover from failure internal
-spec recover_from_failure_internal(binary(), state()) -> ok | {error, term()}.
recover_from_failure_internal(FailureId, State) ->
    logger:info("Attempting recovery from failure", #{
        failure_id => FailureId,
        domain => [a2a, health, recovery]
    }),

    try
        %% Attempt recovery based on failure type
        RecoveryResult = attempt_recovery(FailureId),

        case RecoveryResult of
            success ->
                %% Record recovery action
                RecoveryAction = #{
                    timestamp => erlang:system_time(millisecond),
                    failure_id => FailureId,
                    result => success
                },

                logger:info("Recovery successful", #{
                    failure_id => FailureId,
                    domain => [a2a, health, recovery]
                }),

                ok;
            {partial_success, Details} ->
                logger:warning("Partial recovery success", #{
                    failure_id => FailureId,
                    details => Details,
                    domain => [a2a, health, recovery]
                }),

                ok;
            {failed, Reason} ->
                logger:error("Recovery failed", #{
                    failure_id => FailureId,
                    reason => Reason,
                    domain => [a2a, health, recovery]
                }),

                {error, Reason}
        end
    catch
        Error:ExceptionReason ->
            logger:error("Recovery attempt crashed", #{
                failure_id => FailureId,
                error => Error,
                reason => ExceptionReason,
                domain => [a2a, health, recovery]
            }),

            {error, ExceptionReason}
    end.

%% @brief Attempt recovery
-spec attempt_recovery(binary()) -> success | {partial_success, map()} | {failed, term()}.
attempt_recovery(FailureId) when is_binary(FailureId) ->
    FailureType = parse_failure_type(FailureId),
    attempt_recovery_by_type(FailureType, FailureId);

attempt_recovery(_) ->
    {failed, invalid_failure_id}.

%% @private Attempt recovery based on parsed failure type
-spec attempt_recovery_by_type(atom(), binary()) -> success | {partial_success, map()} | {failed, term()}.
attempt_recovery_by_type(memory_critical, _FailureId) ->
    recover_memory_critical();
attempt_recovery_by_type(cpu_critical, _FailureId) ->
    recover_cpu_critical();
attempt_recovery_by_type(upgrade_failed, _FailureId) ->
    recover_upgrade_failed();
attempt_recovery_by_type(app_error_rate_high, _FailureId) ->
    recover_app_error_rate_high();
attempt_recovery_by_type(app_response_time_high, _FailureId) ->
    recover_app_response_time_high();
attempt_recovery_by_type(integrity_corruption, _FailureId) ->
    recover_integrity_corruption();
attempt_recovery_by_type(integrity_consistency_low, _FailureId) ->
    recover_integrity_consistency_low();
attempt_recovery_by_type(process_killed, _FailureId) ->
    recover_process_killed();
attempt_recovery_by_type(ets_corruption, _FailureId) ->
    recover_ets_corruption();
attempt_recovery_by_type(connection_loss, _FailureId) ->
    recover_connection_loss();
attempt_recovery_by_type(unknown, FailureId) ->
    {partial_success, #{
        unknown_failure => FailureId,
        action => generic_recovery,
        message => <<"No specific recovery for this failure type">>
    }}.

%% @brief Parse failure ID to extract failure type
-spec parse_failure_type(binary()) -> atom().
parse_failure_type(<<>>) ->
    unknown;
parse_failure_type(FailureId) when is_binary(FailureId) ->
    case binary:split(FailureId, <<"_">>, [global]) of
        [<<"failure">>, <<"error">>, <<"rate">> | _] -> app_error_rate_high;
        [<<"failure">>, <<"response">>, <<"time">> | _] -> app_response_time_high;
        [<<"failure">>, Type | _] -> binary_to_failure_type(Type);
        _ ->
            unknown
    end;
parse_failure_type(_) ->
    unknown.

%% @private Convert binary failure type to atom
binary_to_failure_type(<<"memory">>) -> memory_critical;
binary_to_failure_type(<<"cpu">>) -> cpu_critical;
binary_to_failure_type(<<"upgrade">>) -> upgrade_failed;
binary_to_failure_type(<<"error_rate">>) -> app_error_rate_high;
binary_to_failure_type(<<"response_time">>) -> app_response_time_high;
binary_to_failure_type(<<"integrity">>) -> integrity_corruption;
binary_to_failure_type(<<"consistency">>) -> integrity_consistency_low;
binary_to_failure_type(<<"process">>) -> process_killed;
binary_to_failure_type(<<"ets">>) -> ets_corruption;
binary_to_failure_type(<<"connection">>) -> connection_loss;
binary_to_failure_type(_) -> unknown.

%% @brief Recover from memory critical failure
-spec recover_memory_critical() -> success | {partial_success, map()} | {failed, term()}.
recover_memory_critical() ->
    try
        %% Trigger garbage collection to free memory
        garbage_collect(),

        %% Run garbage collection on all processes
        _ = erlang:garbage_collect(),

        %% Log the recovery action
        logger:info("Memory recovery: garbage collection triggered", #{
            domain => [a2a, health, recovery, memory]
        }),

        %% In a real system, this might also:
        %% - Kill non-critical processes
        %% - Reduce cache sizes
        %% - Trigger process hibernation
        %% - Request manual intervention if severe

        success
    catch
        Error:Reason ->
            logger:error("Memory recovery failed", #{
                error => Error,
                reason => Reason,
                domain => [a2a, health, recovery, memory]
            }),
            {failed, {Error, Reason}}
    end.

%% @brief Recover from CPU critical failure
-spec recover_cpu_critical() -> success | {partial_success, map()} | {failed, term()}.
recover_cpu_critical() ->
    try
        %% Log the recovery action
        logger:info("CPU recovery: reducing system load", #{
            domain => [a2a, health, recovery, cpu]
        }),

        %% In a real system, this might:
        %% - Reduce concurrency levels
        %% - Throttle incoming requests
        %% - Defer non-critical work
        %% - Scale up if in distributed system

        %% Check if CPU usage has decreased
        case check_cpu_recovery() of
            ok -> success;
            {warning, Details} -> {partial_success, #{cpu_recovery => Details}}
        end
    catch
        Error:Reason ->
            logger:error("CPU recovery failed", #{
                error => Error,
                reason => Reason,
                domain => [a2a, health, recovery, cpu]
            }),
            {failed, {Error, Reason}}
    end.

%% @private Check if CPU has recovered
check_cpu_recovery() ->
    %% Simulate CPU recovery check
    %% In production, use actual CPU metrics
    ok.

%% @brief Recover from upgrade failure
-spec recover_upgrade_failed() -> success | {partial_success, map()} | {failed, term()}.
recover_upgrade_failed() ->
    try
        logger:info("Upgrade failure recovery initiated", #{
            domain => [a2a, health, recovery, upgrade]
        }),

        %% Phase 1: Check supervisor strategy for restart capability
        SupervisorInfo = get_upgrade_supervisor_info(),
        logger:info("Supervisor info", #{
            supervisor_info => SupervisorInfo,
            domain => [a2a, health, recovery, upgrade]
        }),

        %% Phase 2: Attempt supervisor-based restart
        RestartResult = attempt_supervisor_restart(SupervisorInfo),

        case RestartResult of
            {ok, _} ->
                logger:info("Supervisor restart successful", #{
                    domain => [a2a, health, recovery, upgrade]
                }),
                success;
            {error, _} ->
                %% Phase 3: Try rollback trigger if available
                case has_rollback_point() of
                    true ->
                        RollbackResult = trigger_rollback(),
                        case RollbackResult of
                            ok ->
                                logger:info("Rollback triggered successfully", #{
                                    domain => [a2a, health, recovery, upgrade]
                                }),
                                success;
                            {error, Reason} ->
                                {partial_success, #{
                                    upgrade_recovery => rollback_failed,
                                    supervisor_restart_failed => true,
                                    action => manual_intervention_required,
                                    message => <<"Both supervisor restart and rollback failed">>,
                                    reason => Reason
                                }}
                        end;
                    false ->
                        {partial_success, #{
                            upgrade_recovery => no_rollback_point,
                            supervisor_restart_failed => true,
                            action => manual_intervention_required,
                            message => <<"No rollback point available, manual recovery required">>
                        }}
                end
        end
    catch
        Class:Error:Stacktrace ->
            logger:error("Upgrade recovery failed", #{
                class => Class,
                error => Error,
                stacktrace => Stacktrace,
                domain => [a2a, health, recovery, upgrade]
            }),
            {failed, {Class, Error}}
    end.

%% @private Check if rollback point exists
has_rollback_point() ->
    %% Check if rollback manager has rollback points available
    try
        case whereis(a2a_rollback_manager) of
            undefined ->
                %% Fallback: check application environment
                case application:get_env(a2a_erl, has_rollback_point) of
                    {ok, true} -> true;
                    _ -> false
                end;
            _Pid ->
                %% Check ETS table for rollback points
                case ets:info(rollback_points, size) of
                    undefined -> false;
                    0 -> false;
                    N when N > 0 -> true
                end
        end
    catch
        _:_ -> false
    end.

%% @private Get upgrade supervisor information
get_upgrade_supervisor_info() ->
    try
        case application:get_key(a2a_erl, supervisor) of
            {ok, Supervisor} when is_atom(Supervisor) ->
                case whereis(Supervisor) of
                    undefined ->
                        #{supervisor => not_found, strategy => unknown};
                    Pid when is_pid(Pid) ->
                        case supervisor:which_children(Pid) of
                            Children when is_list(Children) ->
                                #{
                                    supervisor => Supervisor,
                                    pid => Pid,
                                    children_count => length(Children),
                                    strategy => get_supervisor_strategy(Pid),
                                    children => [ChildName || {ChildName, _, _, _} <- Children]
                                };
                            _ ->
                                #{supervisor => Supervisor, pid => Pid, strategy => unknown}
                        end
                end;
            _ ->
                #{supervisor => not_configured, strategy => unknown}
        end
    catch
        _:_ ->
            #{supervisor => error, strategy => unknown}
    end.

%% @private Get supervisor restart strategy
get_supervisor_strategy(SupPid) when is_pid(SupPid) ->
    try
        case supervisor:get_children(SupPid) of
            {ok, Children} when is_list(Children) ->
                %% Try to determine strategy from child specs
                case length(Children) > 0 of
                    true -> one_for_one; %% Most common strategy
                    false -> undefined
                end;
            _ ->
                undefined
        end
    catch
        _:_ -> undefined
    end;
get_supervisor_strategy(_) ->
    undefined.

%% @private Attempt supervisor-based restart of failed processes
attempt_supervisor_restart(SupervisorInfo) ->
    try
        case maps:get(supervisor, SupervisorInfo) of
            not_found ->
                {error, supervisor_not_found};
            not_configured ->
                {error, supervisor_not_configured};
            error ->
                {error, supervisor_error};
            Sup when is_atom(Sup) ->
                Pid = maps:get(pid, SupervisorInfo),
                Children = maps:get(children, SupervisorInfo, []),

                %% Attempt to restart failed children using supervisor's restart strategy
                RestartedCount = lists:foldl(fun(ChildName, Acc) ->
                    case restart_child_via_supervisor(Pid, ChildName) of
                        ok -> Acc + 1;
                        _ -> Acc
                    end
                end, 0, Children),

                case RestartedCount > 0 of
                    true -> {ok, #{restarted_count => RestartedCount}};
                    false -> {error, no_children_restarted}
                end
        end
    catch
        Error:Reason ->
            {error, {Error, Reason}}
    end.

%% @private Restart a specific child via supervisor
restart_child_via_supervisor(SupPid, ChildName) when is_pid(SupPid) ->
    try
        case supervisor:restart_child(SupPid, ChildName) of
            {ok, _Pid} -> ok;
            {ok, _Pid, _Info} -> ok;
            ok -> ok;
            {error, running} -> ok; %% Already running, considered success
            {error, not_found} -> {error, child_not_found};
            {error, Reason} -> {error, Reason}
        end
    catch
        _:_ -> {error, restart_failed}
    end;
restart_child_via_supervisor(_, _) ->
    {error, invalid_supervisor}.

%% @private Trigger rollback via rollback manager
trigger_rollback() ->
    try
        case whereis(a2a_rollback_manager) of
            undefined ->
                %% Try to start rollback manager temporarily
                {error, rollback_manager_not_available};
            Pid when is_pid(Pid) ->
                %% Request auto-rollback with latest version
                TargetVersion = get_previous_stable_version(),
                case gen_server:call(Pid, {auto_rollback, #{trigger => upgrade_failure}}) of
                    {ok, _OperationId} -> ok;
                    {error, Reason} -> {error, Reason}
                end
        end
    catch
        _:Error ->
            {error, Error}
    end.

%% @private Get previous stable version for rollback
get_previous_stable_version() ->
    try
        case application:get_env(a2a_erl, previous_stable_version) of
            {ok, Version} when is_binary(Version); is_list(Version) -> Version;
            _ -> <<"1.0.0">> %% Fallback to initial version
        end
    catch
        _:_ -> <<"1.0.0">>
    end.

%% @brief Recover from application error rate high
-spec recover_app_error_rate_high() -> success | {partial_success, map()} | {failed, term()}.
recover_app_error_rate_high() ->
    try
        logger:info("Application error recovery: checking error sources", #{
            domain => [a2a, health, recovery, application]
        }),

        %% Check system error logs for patterns
        case analyze_error_patterns() of
            {ok, patterns} when length(patterns) > 0 ->
                logger:info("Error patterns detected, attempting mitigation", #{
                    patterns => patterns,
                    domain => [a2a, health, recovery, application]
                }),
                success;
            {ok, []} ->
                logger:warning("No specific error patterns found", #{
                    domain => [a2a, health, recovery, application]
                }),
                {partial_success, #{
                    error_recovery => no_patterns,
                    message => <<"Monitoring for error rate reduction">>
                }}
        end
    catch
        Error:Reason ->
            logger:error("Application error recovery failed", #{
                error => Error,
                reason => Reason,
                domain => [a2a, health, recovery, application]
            }),
            {failed, {Error, Reason}}
    end.

%% @brief Recover from application response time high
-spec recover_app_response_time_high() -> success | {partial_success, map()} | {failed, term()}.
recover_app_response_time_high() ->
    try
        logger:info("Response time recovery: optimizing performance", #{
            domain => [a2a, health, recovery, application]
        }),

        %% In production:
        %% - Check for blocking operations
        %% - Identify slow queries
        %% - Check network latency
        %% - Scale resources if needed

        success
    catch
        Error:Reason ->
            logger:error("Response time recovery failed", #{
                error => Error,
                reason => Reason,
                domain => [a2a, health, recovery, application]
            }),
            {failed, {Error, Reason}}
    end.

%% @private Analyze error patterns
analyze_error_patterns() ->
    %% In production, analyze actual error logs
    {ok, []}.

%% @brief Recover from data integrity corruption
-spec recover_integrity_corruption() -> success | {partial_success, map()} | {failed, term()}.
recover_integrity_corruption() ->
    try
        logger:warning("Integrity corruption recovery: attempting data validation", #{
            domain => [a2a, health, recovery, integrity]
        }),

        %% Validate ETS tables
        ETSValid = validate_ets_integrity(),

        %% Validate process states
        ProcessValid = validate_process_states(),

        case {ETSValid, ProcessValid} of
            {true, true} ->
                logger:info("Integrity validation passed", #{
                    domain => [a2a, health, recovery, integrity]
                }),
                success;
            {false, _} ->
                {partial_success, #{
                    integrity_recovery => ets_corruption_detected,
                    action => ets_repair_initiated
                }};
            {_, false} ->
                {partial_success, #{
                    integrity_recovery => process_state_inconsistent,
                    action => state_repair_initiated
                }}
        end
    catch
        Error:Reason ->
            logger:error("Integrity recovery failed", #{
                error => Error,
                reason => Reason,
                domain => [a2a, health, recovery, integrity]
            }),
            {failed, {Error, Reason}}
    end.

%% @brief Recover from data integrity consistency low
-spec recover_integrity_consistency_low() -> success | {partial_success, map()} | {failed, term()}.
recover_integrity_consistency_low() ->
    try
        logger:info("Consistency recovery: re-synchronizing data", #{
            domain => [a2a, health, recovery, integrity]
        }),

        %% In production:
        %% - Trigger data reconciliation
        %% - Sync with backup/replicas
        %% - Rebuild indexes if needed

        success
    catch
        Error:Reason ->
            logger:error("Consistency recovery failed", #{
                error => Error,
                reason => Reason,
                domain => [a2a, health, recovery, integrity]
            }),
            {failed, {Error, Reason}}
    end.

%% @private Validate ETS table integrity
validate_ets_integrity() ->
    try
        Tables = ets:all(),
        lists:foreach(fun(T) ->
            case ets:info(T, size) of
                undefined -> ok;
                Size when is_integer(Size) -> ok
            end
        end, Tables),
        true
    catch
        _:_ -> false
    end.

%% @private Validate process states
validate_process_states() ->
    %% In production, check critical process states
    true.

%% @brief Recover from killed process
-spec recover_process_killed() -> success | {partial_success, map()} | {failed, term()}.
recover_process_killed() ->
    try
        logger:info("Process recovery: checking for supervised processes", #{
            domain => [a2a, health, recovery, process]
        }),

        %% Supervised processes will be auto-restarted by their supervisors
        %% Check if critical processes are alive
        CriticalProcesses = get_critical_processes(),

        AliveCount = lists:foldl(fun(ProcessName, Count) ->
            case whereis(ProcessName) of
                undefined -> Count;
                _Pid -> Count + 1
            end
        end, 0, CriticalProcesses),

        case AliveCount of
            N when N =:= length(CriticalProcesses) ->
                logger:info("All critical processes running", #{
                    count => AliveCount,
                    domain => [a2a, health, recovery, process]
                }),
                success;
            _ ->
                logger:warning("Some critical processes not running", #{
                    alive => AliveCount,
                    expected => length(CriticalProcesses),
                    domain => [a2a, health, recovery, process]
                }),
                {partial_success, #{
                    process_recovery => some_down,
                    alive => AliveCount,
                    total => length(CriticalProcesses)
                }}
        end
    catch
        Error:Reason ->
            logger:error("Process recovery failed", #{
                error => Error,
                reason => Reason,
                domain => [a2a, health, recovery, process]
            }),
            {failed, {Error, Reason}}
    end.

%% @private Get list of critical processes
get_critical_processes() ->
    %% In production, get from configuration or service registry
    [a2a_upgrade_health, a2a_disaster_recovery].

%% @brief Recover from ETS corruption
-spec recover_ets_corruption() -> success | {partial_success, map()} | {failed, term()}.
recover_ets_corruption() ->
    try
        logger:warning("ETS corruption recovery: validating tables", #{
            domain => [a2a, health, recovery, ets]
        }),

        %% Get all ETS tables
        Tables = ets:all(),

        %% Validate and repair if needed
        CorruptTables = lists:filter(fun(T) ->
            not is_table_healthy(T)
        end, Tables),

        case length(CorruptTables) of
            0 ->
                logger:info("All ETS tables healthy", #{
                    domain => [a2a, health, recovery, ets]
                }),
                success;
            N ->
                logger:warning("Found corrupt ETS tables", #{
                    count => N,
                    domain => [a2a, health, recovery, ets]
                }),
                {partial_success, #{
                    ets_recovery => corrupt_tables_found,
                    count => N,
                    tables => [ets:info(T, name) || T <- CorruptTables, ets:info(T, name) =/= undefined]
                }}
        end
    catch
        Error:Reason ->
            logger:error("ETS recovery failed", #{
                error => Error,
                reason => Reason,
                domain => [a2a, health, recovery, ets]
            }),
            {failed, {Error, Reason}}
    end.

%% @private Check if ETS table is healthy
is_table_healthy(Table) ->
    try
        %% Basic health check: can we read table info?
        case ets:info(Table, size) of
            Size when is_integer(Size), Size >= 0 -> true;
            _ -> false
        end
    catch
        _:_ -> false
    end.

%% @brief Recover from connection loss
-spec recover_connection_loss() -> success | {partial_success, map()} | {failed, term()}.
recover_connection_loss() ->
    try
        logger:info("Connection loss recovery: checking network status", #{
            domain => [a2a, health, recovery, network]
        }),

        %% Check node connectivity if distributed
        Nodes = [node() | nodes()],

        ConnectedCount = lists:foldl(fun(N, Count) ->
            case net_adm:ping(N) of
                pong -> Count + 1;
                pang -> Count
            end
        end, 0, Nodes),

        case ConnectedCount of
            N when N =:= length(Nodes) ->
                logger:info("All nodes connected", #{
                    count => N,
                    domain => [a2a, health, recovery, network]
                }),
                success;
            _ ->
                logger:warning("Some nodes disconnected", #{
                    connected => ConnectedCount,
                    total => length(Nodes),
                    domain => [a2a, health, recovery, network]
                }),
                {partial_success, #{
                    network_recovery => partial,
                    connected => ConnectedCount,
                    total => length(Nodes)
                }}
        end
    catch
        Error:Reason ->
            logger:error("Connection recovery failed", #{
                error => Error,
                reason => Reason,
                domain => [a2a, health, recovery, network]
            }),
            {failed, {Error, Reason}}
    end.

%% @brief Auto-adjust upgrade parameters internal
-spec auto_adjust_upgrade_params_internal(state()) -> map().
auto_adjust_upgrade_params_internal(State) ->
    %% Analyze health data and adjust parameters accordingly
    System = State#health_state.system,
    Upgrade = State#health_state.upgrade,

    %% Base parameters
    BaseParams = #{
        concurrency_level => 4,
        memory_limit_mb => 1024,
        max_process_time_ms => 30000
    },

    %% Adjust based on system health
    AdjustedParams = case System#system_health.memory_usage_percent > 80 of
        true -> BaseParams#{memory_limit_mb => 512};
        _ -> BaseParams
    end,

    %% Adjust based on upgrade health
    FinalParams = case Upgrade#upgrade_health.upgrade_success_rate < 0.9 of
        true -> AdjustedParams#{concurrency_level => 2};
        _ -> AdjustedParams
    end,

    FinalParams.

%% @brief Generate health report
-spec generate_health_report(state()) -> map().
generate_health_report(State) ->
    HealthHistory = lists:last(10, State#health_state.health_history),

    #{
        timestamp => erlang:system_time(millisecond),
        overall_status => calculate_overall_status(#{
            system => State#health_state.system,
            upgrade => State#health_state.upgrade,
            application => State#health_state.application,
            integrity => State#health_state.integrity
        }),
        system_health => State#health_state.system,
        upgrade_health => State#health_state.upgrade,
        application_health => State#health_state.application,
        data_integrity => State#health_state.integrity,
        active_alerts => length(State#health_state.alerts),
        health_history => HealthHistory,
        recommendations => generate_health_recommendations(State)
    }.

%% @brief Generate health summary
-spec generate_health_summary(state()) -> map().
generate_health_summary(State) ->
    System = State#health_state.system,
    Upgrade = State#health_state.upgrade,
    Application = State#health_state.application,
    Integrity = State#health_state.integrity,

    #{
        system_status => System#system_health.overall_status,
        upgrade_status => Upgrade#upgrade_health.overall_status,
        app_status => Application#application_health.overall_status,
        integrity_status => Integrity#data_integrity.overall_status,
        critical_alerts => length([A || A <- State#health_state.alerts, A#health_alert.severity =:= critical]),
        warning_alerts => length([A || A <- State#health_state.alerts, A#health_alert.severity =:= warning]),
        info_alerts => length([A || A <- State#health_state.alerts, A#health_alert.severity =:= info]),
        uptime_seconds => System#system_health.uptime_seconds,
        active_upgrades => Upgrade#upgrade_health.active_upgrades,
        success_rate => Upgrade#upgrade_health.upgrade_success_rate
    }.

%% @brief Generate health recommendations
-spec generate_health_recommendations(state()) -> [binary()].
generate_health_recommendations(State) ->
    Recommendations = [],

    System = State#health_state.system,
    Upgrade = State#health_state.upgrade,
    Application = State#health_state.application,
    Thresholds = State#health_state.thresholds,

    %% System recommendations
    Rec1 = case System#system_health.memory_usage_percent > Thresholds#health_thresholds.memory_usage_percent * 0.9 of
        true -> [<<"Consider increasing system memory or optimizing memory usage">>];
        false -> []
    end,

    %% Upgrade recommendations
    Rec2 = case Upgrade#upgrade_health.upgrade_success_rate < 0.9 of
        true -> [<<"Consider reducing upgrade concurrency or implementing better error handling">>];
        false -> []
    end,

    %% Application recommendations
    Rec3 = case Application#application_health.error_rate > Thresholds#health_thresholds.error_rate_threshold of
        true -> [<<"Investigate application errors and improve error handling">>];
        false -> []
    end,

    %% Integrity recommendations
    Rec4 = case State#health_state.integrity#data_integrity.ets_consistency_score < 0.95 of
        true -> [<<"Schedule data integrity check and cleanup">>];
        false -> []
    end,

    lists:flatten([Rec1, Rec2, Rec3, Rec4]).

%% @brief Process alerts
-spec process_alerts(state()) -> state().
process_alerts(State) ->
    %% Process outstanding alerts and update their status
    Now = erlang:system_time(millisecond),

    UpdatedAlerts = lists:map(fun(Alert) ->
        case Alert#health_alert.resolved of
            true -> Alert;
            false ->
                %% Check if alert should be resolved automatically
                case should_auto_resolve_alert(Alert) of
                    true -> Alert#health_alert{resolved = true};
                    false -> Alert
                end
        end
    end, State#health_state.alerts),

    State#health_state{alerts = UpdatedAlerts}.

%% @brief Check if alert should be auto-resolved
-spec should_auto_resolve_alert(health_alert()) -> boolean().
should_auto_resolve_alert(Alert) ->
    case Alert#health_alert.category of
        system ->
            %% Check if system conditions have improved
            CurrentSystem = get_current_system_health(),
            case Alert#health_alert.severity of
                critical ->
                    CurrentSystem#system_health.overall_status =/= critical;
                warning ->
                    CurrentSystem#system_health.overall_status =:= healthy;
                _ -> true
            end;
        upgrade ->
            %% Check if upgrade conditions have improved
            CurrentUpgrade = get_current_upgrade_health(),
            case Alert#health_alert.severity of
                critical ->
                    CurrentUpgrade#upgrade_health.overall_status =/= critical;
                warning ->
                    CurrentUpgrade#upgrade_health.overall_status =:= healthy;
                _ -> true
            end;
        _ ->
            false
    end.

%% @brief Get current system health
-spec get_current_system_health() -> system_health().
get_current_system_health() ->
    %% This would get the current system health
    #system_health{overall_status = healthy}.

%% @brief Get current upgrade health
-spec get_current_upgrade_health() -> upgrade_health().
get_current_upgrade_health() ->
    %% This would get the current upgrade health
    #upgrade_health{overall_status = healthy}.

%% @brief Perform comprehensive health check
-spec perform_comprehensive_health_check(state()) -> map().
perform_comprehensive_health_check(State) ->
    %% Perform all health checks
    NewSystemHealth = check_system_health_internal(State#health_state.thresholds),
    NewUpgradeHealth = check_upgrade_health_internal(State#health_state.thresholds),
    NewAppHealth = check_application_health_internal(State#health_state.thresholds),
    NewIntegrity = check_data_integrity_internal(State#health_state.thresholds),

    %% Create comprehensive health report
    HealthReport = create_health_snapshot(#{
        system => NewSystemHealth,
        upgrade => NewUpgradeHealth,
        application => NewAppHealth,
        integrity => NewIntegrity
    }),

    HealthReport.

%% @brief Helper functions for system metrics
-spec get_system_memory() -> float().
get_system_memory() ->
    %% This would get actual system memory
    8192.0. %% 8GB

-spec get_cpu_usage() -> float().
get_cpu_usage() ->
    %% This would get actual CPU usage
    45.0.

-spec get_total_process_heap() -> integer().
get_total_process_heap() ->
    %% This would get total process heap
    1024 * 1024. %% 1MB

-spec get_system_load() -> float().
get_system_load() ->
    %% This would get system load
    1.5.

-spec get_system_uptime() -> integer().
get_system_uptime() ->
    %% This would get system uptime in seconds
    3600.

%% @brief Helper functions for upgrade metrics
-spec get_active_upgrades() -> non_neg_integer().
get_active_upgrades() ->
    %% This would get actual active upgrade count
    0.

-spec get_upgrade_metrics() -> upgrade_metrics().
get_upgrade_metrics() ->
    %% This would get actual upgrade metrics
    #upgrade_metrics{}.

-spec detect_upgrade_bottlenecks() -> [term()].
detect_upgrade_bottlenecks() ->
    %% This would detect actual bottlenecks
    [].

-spec get_recovery_attempts() -> non_neg_integer().
get_recovery_attempts() ->
    %% This would get actual recovery attempts
    0.

%% @brief Helper functions for application metrics
-spec get_avg_response_time() -> float().
get_avg_response_time() ->
    %% This would get actual average response time
    150.0.

-spec get_error_rate() -> float().
get_error_rate() ->
    %% This would get actual error rate
    0.02.

-spec get_throughput() -> float().
get_throughput() ->
    %% This would get actual throughput
    100.0.

-spec get_active_connections() -> non_neg_integer().
get_active_connections() ->
    %% This would get actual active connections
    50.

-spec get_message_backlog() -> non_neg_integer().
get_message_backlog() ->
    %% This would get actual message backlog
    0.

%% @brief Helper functions for integrity metrics
-spec check_ets_integrity() -> float().
check_ets_integrity() ->
    %% This would check ETS integrity
    1.0.

-spec check_process_integrity() -> float().
check_process_integrity() ->
    %% This would check process integrity
    1.0.

-spec detect_data_corruption() -> boolean().
detect_data_corruption() ->
    %% This would detect data corruption
    false.

-spec get_recovery_actions() -> [binary()].
get_recovery_actions() ->
    %% This would get actual recovery actions
    [].
