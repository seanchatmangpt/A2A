%%% @doc HotCI Monitoring and Alerting System
%%%
%%% This module provides comprehensive monitoring and alerting for HotCI operations,
%%% including real-time health assessment, performance metrics, and critical
%%% notifications specifically designed for banking and telecom systems.
-module(a2a_monitoring).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    start_monitoring/2,
    stop_monitoring/1,
    get_health_metrics/0,
    get_performance_metrics/1,
    trigger_alert/3,
    configure_alert_rules/1,
    get_alert_history/1,
    analyze_system_performance/1,
    validate_service_health/1,
    monitor_critical_paths/1,
    generate_health_report/0
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
-define(METRICS_INTERVAL, 5000). % 5 seconds
-define(ALERT_LOG_FILE, "monitoring_alerts.log").
-define(HEALTH_THRESHOLD_CPU, 80.0). % 80%
-define(HEALTH_THRESHOLD_MEMORY, 85.0). % 85%
-define(HEALTH_THRESHOLD_DISK, 90.0). % 90%
-define(HEALTH_THRESHOLD_RESPONSE_TIME, 1000). % 1 second
-define(HEALTH_THRESHOLD_ERROR_RATE, 0.01). % 1%
-define(METRICS_RETENTION_HOURS, 24).

-record(metric_point, {
    timestamp :: integer(),
    service :: binary(),
    metric_type :: cpu | memory | disk | response_time | error_rate | throughput,
    value :: float() | integer(),
    unit :: binary(),
    tags :: [binary()],
    metadata :: map()
}).

-record.alert_rule, {
    id :: binary(),
    name :: binary(),
    condition :: binary(), % e.g., "cpu_usage > 80"
    severity :: low | medium | high | critical,
    threshold :: float() | integer(),
    duration :: integer(), % milliseconds
    notification_channels :: [binary()],
    escalation_rules :: [map()],
    enabled :: boolean()
}).

-record.alert, {
    id :: binary(),
    rule_id :: binary(),
    severity :: low | medium | high | critical,
    message :: binary(),
    timestamp :: integer(),
    service :: binary(),
    metric_value :: float(),
    triggered_by :: binary(),
    resolved :: boolean(),
    resolved_timestamp :: integer() | undefined,
    acknowledged :: boolean(),
    acknowledged_by :: binary() | undefined,
    acknowledged_timestamp :: integer() | undefined,
    notification_log :: [binary()]
}).

-record(monitoring_config, {
    metrics_collection_interval :: integer(),
    alert_rules :: [map()],
    notification_channels :: [binary()],
    critical_services :: [binary()],
    performance_thresholds :: map(),
    alert_retention_hours :: integer(),
    log_level :: debug | info | warn | error | critical
}).

-record(state, {
    config :: monitoring_config(),
    metrics :: ets:tid(), % metric_point
    alert_rules :: ets:tid(), % alert_rule
    alerts :: ets:tid(), % alert
    active_monitors :: [pid()],
    metrics_collection_ref :: reference(),
    performance_baseline :: map(),
    health_status :: healthy | degraded | critical,
    last_metrics_update :: integer(),
    alert_history :: [binary()],
    service_health :: map(),
    critical_paths :: [binary()],
    notification_targets :: [binary()]
}).

-type state() :: #state{}.
-type metric_point() :: #metric_point{}.
-type alert_rule() :: #alert_rule{}.
-type alert() :: #alert{}.

%% ============================================================================
%% API Functions
%% ============================================================================

%% @doc Start the monitoring system with default configuration
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the monitoring system with custom configuration
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Options) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Options, []).

%% @doc Start monitoring a specific service or component
-spec start_monitoring(binary(), map()) -> ok.
start_monitoring(ServiceId, Config) ->
    gen_server:cast(?SERVER, {start_monitoring, ServiceId, Config}).

%% @doc Stop monitoring a specific service or component
-spec stop_monitoring(binary()) -> ok.
stop_monitoring(ServiceId) ->
    gen_server:cast(?SERVER, {stop_monitoring, ServiceId}).

%% @doc Get current health metrics
-spec get_health_metrics() -> {ok, map()} | {error, term()}.
get_health_metrics() ->
    gen_server:call(?SERVER, get_health_metrics).

%% @doc Get performance metrics for a service
-spec get_performance_metrics(binary()) -> {ok, [metric_point()]} | {error, term()}.
get_performance_metrics(ServiceId) ->
    gen_server:call(?SERVER, {get_performance_metrics, ServiceId}).

%% @doc Trigger an alert manually
-spec trigger_alert(binary(), binary(), map()) -> ok.
trigger_alert(ServiceId, AlertType, AlertData) ->
    gen_server:cast(?SERVER, {trigger_alert, ServiceId, AlertType, AlertData}).

%% @doc Configure alert rules
-spec configure_alert_rules(map()) -> ok.
configure_alert_rules(AlertRules) ->
    gen_server:cast(?SERVER, {configure_alert_rules, AlertRules}).

%% @doc Get alert history
-spec get_alert_history(integer()) -> {ok, [alert()]} | {error, term()}.
get_alert_history(Hours) ->
    gen_server:call(?SERVER, {get_alert_history, Hours}).

%% @doc Analyze system performance
-spec analyze_system_performance(map()) -> {ok, map()} | {error, term()}.
analyze_system_performance(AnalysisOptions) ->
    gen_server:call(?SERVER, {analyze_system_performance, AnalysisOptions}).

%% @doc Validate service health
-spec validate_service_health(binary()) -> {ok, map()} | {error, term()}.
validate_service_health(ServiceId) ->
    gen_server:call(?SERVER, {validate_service_health, ServiceId}).

%% @doc Monitor critical system paths
-spec monitor_critical_paths(map()) -> ok.
monitor_critical_paths(PathConfig) ->
    gen_server:cast(?SERVER, {monitor_critical_paths, PathConfig}).

%% @doc Generate comprehensive health report
-spec generate_health_report() -> {ok, map()} | {error, term()}.
generate_health_report() ->
    gen_server:call(?SERVER, generate_health_report).

%% ============================================================================
%% gen_server Callbacks
%% ============================================================================

-spec init(map()) -> {ok, state()} | {stop, term()}.
init(Options) ->
    %% Initialize ETS tables
    Metrics = ets:new(metrics, [
        set,
        public,
        {keypos, 2},
        named_table,
        {heir, self(), undefined}
    ]),

    AlertRules = ets:new(alert_rules, [
        set,
        public,
        {keypos, 2},
        named_table,
        {heir, self(), undefined}
    ]),

    Alerts = ets:new(alerts, [
        set,
        public,
        {keypos, 2},
        named_table,
        {heir, self(), undefined}
    ]),

    %% Initialize state
    Config = initialize_config(Options),
    CriticalServices = maps:get(critical_services, Options, ["a2a_http_handler", "a2a_task_statem"]),
    NotificationTargets = maps.get(notification_targets, Options, ["admin", "monitoring_team"]),

    State = #state{
        config = Config,
        metrics = Metrics,
        alert_rules = AlertRules,
        alerts = Alerts,
        active_monitors = [],
        performance_baseline = establish_performance_baseline(),
        health_status = healthy,
        last_metrics_update = erlang:system_time(millisecond),
        alert_history = [],
        service_health = initialize_service_health(CriticalServices),
        critical_paths = [],
        notification_targets = NotificationTargets
    },

    %% Load default alert rules
    load_default_alert_rules(State),

    %% Start metrics collection
    MetricsCollectionRef = erlang:send_after(?METRICS_INTERVAL, self(), collect_metrics),

    {ok, State#state{
        metrics_collection_ref = MetricsCollectionRef
    }}.

-spec handle_call(term(), {pid(), reference()}, state()) ->
    {reply, term(), state()} | {stop, term(), state()}.
handle_call(get_health_metrics, _From, State) ->
    HealthMetrics = collect_health_metrics(State),
    {reply, {ok, HealthMetrics}, State};

handle_call({get_performance_metrics, ServiceId}, _From, State) ->
    ServiceMetrics = get_service_metrics(ServiceId, State),
    case ServiceMetrics of
        [] -> {reply, {error, no_metrics_found}, State};
        _ -> {reply, {ok, ServiceMetrics}, State}
    end;

handle_call({get_alert_history, Hours}, _From, State) ->
    AlertHistory = get_alerts_by_timeframe(Hours, State),
    {reply, {ok, AlertHistory}, State};

handle_call({analyze_system_performance, AnalysisOptions}, _From, State) ->
    AnalysisResults = analyze_system_performance_internal(AnalysisOptions, State),
    {reply, AnalysisResults, State};

handle_call({validate_service_health, ServiceId}, _From, State) ->
    ValidationResult = validate_service_health_internal(ServiceId, State),
    {reply, ValidationResult, State};

handle_call(generate_health_report, _From, State) ->
    HealthReport = generate_comprehensive_health_report(State),
    {reply, HealthReport, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({start_monitoring, ServiceId, Config}, State) ->
    %% Start monitoring for the service
    MonitorPid = spawn_monitor(fun() ->
        service_monitor_loop(ServiceId, Config, State)
    end),

    NewState = State#state{
        active_monitors = [MonitorPid | State#state.active_monitors],
        service_health = maps:put(ServiceId, initialize_service_state(), State#state.service_health)
    },

    log_event(monitoring_started, #{service => ServiceId, pid => MonitorPid}),
    {noreply, NewState};

handle_cast({stop_monitoring, ServiceId}, State) ->
    %% Stop monitoring for the service
    NewMonitors = lists:filter(fun({_, Pid}) ->
        case get_service_id_from_pid(Pid, State) of
            ServiceId -> false;
            _ -> true
        end
    end, State#state.active_monitors),

    NewState = State#state{
        active_monitors = NewMonitors,
        service_health = maps:remove(ServiceId, State#state.service_health)
    },

    log_event(monitoring_stopped, #{service => ServiceId}),
    {noreply, NewState};

handle_cast({trigger_alert, ServiceId, AlertType, AlertData}, State) ->
    AlertId = generate_alert_id(),
    Alert = #alert{
        id = AlertId,
        rule_id = "manual",
        severity = maps:get(severity, AlertData, medium),
        message = maps:get(message, AlertData, "Manual alert triggered"),
        timestamp = erlang:system_time(millisecond),
        service = ServiceId,
        metric_value = maps:get(metric_value, AlertData, 0.0),
        triggered_by = AlertType,
        resolved = false,
        notification_log = []
    },

    %% Store alert
    ets:insert(State#state.alerts, {AlertId, Alert}),

    %% Send notifications
    send_alert_notifications(Alert, State),

    %% Update state
    NewAlertHistory = [AlertId | State#state.alert_history],
    NewState = State#state{
        alert_history = NewAlertHistory
    },

    log_event(alert_triggered, Alert),
    {noreply, NewState};

handle_cast({configure_alert_rules, AlertRules}, State) ->
    %% Configure alert rules
    lists:foreach(fun(Rule) ->
        RuleId = generate_alert_rule_id(),
        AlertRule = #alert_rule{
            id = RuleId,
            name = maps:get(name, Rule),
            condition = maps:get(condition, Rule),
            severity = maps:get(severity, Rule),
            threshold = maps:get(threshold, Rule),
            duration = maps:get(duration, Rule, 0),
            notification_channels = maps:get(notification_channels, Rule, []),
            escalation_rules = maps:get(escalation_rules, Rule, []),
            enabled = maps:get(enabled, Rule, true)
        },
        ets:insert(State#state.alert_rules, {RuleId, AlertRule})
    end, AlertRules),

    log_event(alert_rules_configured, #{rules_count => length(AlertRules)}),
    {noreply, State};

handle_cast({monitor_critical_paths, PathConfig}, State) ->
    CriticalPaths = lists:map(fun(Path) ->
        spawn_link(fun() ->
            critical_path_monitor(Path, State)
        end)
    end, maps:get(paths, PathConfig, [])),

    NewState = State#state{
        critical_paths = CriticalPaths
    },

    log_event(critical_paths_started, #{paths => CriticalPaths}),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(collect_metrics, State) ->
    %% Collect metrics from all active monitors
    MetricsCollectionStartTime = erlang:system_time(millisecond),
    CollectedMetrics = collect_all_metrics(State),

    %% Store metrics
    lists:foreach(fun(Metric) ->
        ets:insert(State#state.metrics, {Metric#metric_point.timestamp, Metric})
    end, CollectedMetrics),

    %% Clean up old metrics
    cleanup_old_metrics(State),

    %% Check for alert conditions
    AlertsTriggered = check_alert_conditions(CollectedMetrics, State),

    %% Update state
    NewState = State#state{
        last_metrics_update = erlang:system_time(millisecond),
        health_status = determine_overall_health(State),
        service_health = update_service_health(CollectedMetrics, State)
    },

    %% Schedule next metrics collection
    erlang:send_after(?METRICS_INTERVAL, self(), collect_metrics),

    {noreply, NewState};

handle_info({'DOWN', Ref, process, _Pid, Reason}, State) ->
    %% Handle monitor process termination
    ActiveMonitors = lists:filter(fun({MonitorRef, _}) ->
        MonitorRef =/= Ref
    end, State#state.active_monitors),

    NewState = State#state{
        active_monitors = ActiveMonitors
    },

    log_event(monitor_down, #{reason => Reason}),
    {noreply, NewState};

handle_info(alert_timeout, State) ->
    %% Handle alert timeouts for duration-based alerts
    ActiveAlerts = lists:filter(fun({_AlertId, Alert}) ->
        not Alert#alert.resolved andalso is_alert_timed_out(Alert, State)
    end, ets:tab2list(State#state.alerts)),

    %% Escalate timed out alerts
    lists:foreach(fun({_, Alert}) ->
        escalate_alert(Alert, State)
    end, ActiveAlerts),

    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(Reason, State) ->
    logger:info("Monitoring system terminating: ~p", [Reason]),

    %% Cleanup ETS tables
    ets:delete(State#state.metrics),
    ets:delete(State#state.alert_rules),
    ets:delete(State#state.alerts),

    %% Stop all monitors
    lists:foreach(fun({_, Pid}) ->
        exit(Pid, normal)
    end, State#state.active_monitors),

    %% Final log
    log_termination(Reason),
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ============================================================================
%% Internal Functions
%% ============================================================================

%% Configuration Initialization
initialize_config(Options) ->
    DefaultConfig = #monitoring_config{
        metrics_collection_interval = ?METRICS_INTERVAL,
        alert_retention_hours = ?METRICS_RETENTION_HOURS,
        log_level => info,
        critical_services => ["a2a_http_handler", "a2a_task_statem"],
        performance_thresholds => #{
            cpu => 80.0,
            memory => 85.0,
            disk => 90.0,
            response_time => 1000,
            error_rate => 0.01
        }
    },

    MergedConfig = #monitoring_config{
        metrics_collection_interval = maps:get(metrics_collection_interval, Options, DefaultConfig#monitoring_config.metrics_collection_interval),
        alert_rules = maps:get(alert_rules, Options, []),
        notification_channels = maps.get(notification_channels, Options, []),
        critical_services = maps:get(critical_services, Options, DefaultConfig#monitoring_config.critical_services),
        performance_thresholds = maps:get(performance_thresholds, Options, DefaultConfig#monitoring_config.performance_thresholds),
        alert_retention_hours = maps:get(alert_retention_hours, Options, DefaultConfig#monitoring_config.alert_retention_hours),
        log_level = maps:get(log_level, Options, DefaultConfig#monitoring_config.log_level)
    },

    MergedConfig.

load_default_alert_rules(State) ->
    %% Load default alert rules
    DefaultRules = [
        #{
            name => "CPU Usage Alert",
            condition => "cpu_usage > 80",
            severity => high,
            threshold => 80.0,
            duration => 30000, % 30 seconds
            notification_channels => ["email", "slack"],
            escalation_rules => []
        },
        #{
            name => "Memory Usage Alert",
            condition => "memory_usage > 85",
            severity => high,
            threshold => 85.0,
            duration => 30000,
            notification_channels => ["email"],
            escalation_rules => []
        },
        #{
            name => "Response Time Alert",
            condition => "response_time > 1000",
            severity => medium,
            threshold => 1000,
            duration => 60000,
            notification_channels => ["slack"],
            escalation_rules => []
        },
        #{
            name => "Error Rate Alert",
            condition => "error_rate > 0.01",
            severity => critical,
            threshold => 0.01,
            duration => 15000,
            notification_channels => ["sms", "email", "slack"],
            escalation_rules => []
        }
    ],

    configure_alert_rules(DefaultRules).

%% Service Monitoring
service_monitor_loop(ServiceId, Config, State) ->
    receive
        stop -> ok;
        _ ->
            %% Collect service metrics
            ServiceMetrics = collect_service_metrics(ServiceId, Config),

            %% Send metrics to main monitoring process
            self() ! {metrics_collected, ServiceMetrics},

            service_monitor_loop(ServiceId, Config, State)
    after
        ?METRICS_INTERVAL ->
            %% Timeout - collect metrics
            ServiceMetrics = collect_service_metrics(ServiceId, Config),
            self() ! {metrics_collected, ServiceMetrics},
            service_monitor_loop(ServiceId, Config, State)
    end.

collect_service_metrics(ServiceId, Config) ->
    %% Collect metrics for specific service
    case ServiceId of
        "a2a_http_handler" ->
            collect_http_handler_metrics();
        "a2a_task_statem" ->
            collect_task_statem_metrics();
        "a2a_push_notifier" ->
            collect_push_notifier_metrics();
        _ ->
            collect_generic_service_metrics(ServiceId)
    end.

collect_http_handler_metrics() ->
    Metrics = #{
        timestamp => erlang:system_time(millisecond),
        active_connections => get_active_connections(),
        request_rate => get_request_rate(),
        response_time => get_average_response_time(),
        error_rate => get_error_rate()
    },

    [
        #metric_point{
            timestamp = Metrics#{
                timestamp := T
            } = Metrics#{
                timestamp := T
            },
            service = "a2a_http_handler",
            metric_type = cpu,
            value = get_cpu_usage(),
            unit = "percent",
            tags = [],
            metadata = Metrics
        },
        #metric_point{
            timestamp = Metrics#{
                timestamp := T
            } = Metrics#{
                timestamp := T
            },
            service = "a2a_http_handler",
            metric_type = response_time,
            value = Metrics#{
                response_time := RT
            } = Metrics#{
                response_time := RT
            },
            unit = "milliseconds",
            tags = [],
            metadata = Metrics
        }
    ].

collect_task_statem_metrics() ->
    Metrics = #{
        timestamp => erlang:system_time(millisecond),
        active_tasks => get_active_tasks(),
        completed_tasks => get_completed_tasks(),
        failed_tasks => get_failed_tasks()
    },

    [
        #metric_point{
            timestamp = Metrics#{
                timestamp := T
            } = Metrics#{
                timestamp := T
            },
            service = "a2a_task_statem",
            metric_type = throughput,
            value = Metrics#{
                completed_tasks := CT
            } = Metrics#{
                completed_tasks := CT
            },
            unit = "tasks_per_second",
            tags = [],
            metadata = Metrics
        }
    ].

collect_push_notifier_metrics() ->
    Metrics = #{
        timestamp => erlang:system_time(millisecond),
        pending_notifications => get_pending_notifications(),
        delivered_notifications => get_delivered_notifications(),
        failed_notifications => get_failed_notifications()
    },

    [
        #metric_point{
            timestamp = Metrics#{
                timestamp := T
            } = Metrics#{
                timestamp := T
            },
            service = "a2a_push_notifier",
            metric_type = error_rate,
            value = calculate_error_rate(Metrics),
            unit = "percent",
            tags = [],
            metadata = Metrics
        }
    ].

collect_generic_service_metrics(ServiceId) ->
    %% Generic metrics collection for any service
    Metrics = #{
        timestamp => erlang:system_time(millisecond),
        service_id => ServiceId
    },

    [
        #metric_point{
            timestamp = Metrics#{
                timestamp := T
            } = Metrics#{
                timestamp := T
            },
            service = ServiceId,
            metric_type = cpu,
            value = get_cpu_usage(),
            unit = "percent",
            tags = [],
            metadata = Metrics
        }
    ].

%% Metrics Collection and Processing
collect_all_metrics(State) ->
    %% Collect metrics from all active monitors
    lists:flatmap(fun({_, MonitorPid}) ->
        MonitorPid ! {request_metrics, self()},
        receive
            {metrics_response, Metrics} -> Metrics;
            timeout -> []
        after 1000 -> []
        end
    end, State#state.active_monitors).

get_service_metrics(ServiceId, State) ->
    %% Get metrics for specific service
    StartTime = erlang:system_time(millisecond) - 3600000, % Last hour
    FilterFun = fun({_Timestamp, Metric}) ->
        Metric#metric_point.service =:= ServiceId andalso
        Metric#metric_point.timestamp >= StartTime
    end,

    lists:filter(FilterFun, ets:tab2list(State#state.metrics)).

cleanup_old_metrics(State) ->
    %% Clean up metrics older than retention period
    RetentionMillis = State#state.config#monitoring_config.alert_retention_hours * 3600000,
    CutoffTime = erlang:system_time(millisecond) - RetentionMillis,

    lists:foreach(fun({Timestamp, _Metric}) ->
        if
            Timestamp < CutoffTime ->
                ets:delete(State#state.metrics, Timestamp);
            true ->
                ok
        end
    end, ets:tab2list(State#state.metrics)).

%% Health Assessment
collect_health_metrics(State) ->
    OverallHealth = determine_overall_health(State),

    ServiceHealth = lists:map(fun(ServiceId) ->
        get_individual_service_health(ServiceId, State)
    end, State#state.config#monitoring_config.critical_services),

    SystemMetrics = collect_system_metrics(),

    #{
        overall_status => OverallHealth,
        service_health => ServiceHealth,
        system_metrics => SystemMetrics,
        timestamp => erlang:system_time(millisecond),
        active_monitors => length(State#state.active_monitors),
        active_alerts => count_active_alerts(State)
    }.

determine_overall_health(State) ->
    ActiveAlerts = lists:filter(fun({__, Alert}) ->
        not Alert#alert.resolved
    end, ets:tab2list(State#state.alerts)),

    CriticalAlerts = lists:filter(fun({__, Alert}) ->
        Alert#alert.severity =:= critical
    end, ActiveAlerts),

    HighAlerts = lists:filter(fun({__, Alert}) ->
        Alert#alert.severity =:= high
    end, ActiveAlerts),

    case CriticalAlerts of
        [] ->
            case HighAlerts of
                [] -> healthy;
                _ -> degraded
            end;
        _ -> critical
    end.

initialize_service_health(CriticalServices) ->
    lists:foldl(fun(Service, Acc) ->
        maps:put(Service, initialize_service_state(), Acc)
    end, #{}, CriticalServices).

initialize_service_state() ->
    #{
        status => healthy,
        last_check => erlang:system_time(millisecond),
        metrics => [],
        alerts => []
    }.

update_service_health(CollectedMetrics, State) ->
    lists:foldl(fun(Metric, Acc) ->
        ServiceId = Metric#metric_point.service,
        CurrentState = maps:get(ServiceId, Acc, initialize_service_state()),
        UpdatedState = update_service_state_with_metric(CurrentState, Metric),
        maps:put(ServiceId, UpdatedState, Acc)
    end, State#state.service_health, CollectedMetrics).

update_service_state_with_metric(ServiceState, Metric) ->
    MetricsList = maps:get(metrics, ServiceState, []) ++ [Metric],
    ServiceStatus = determine_service_status(Metric, ServiceState),

    ServiceState#{
        status => ServiceStatus,
        last_check => Metric#metric_point.timestamp,
        metrics => MetricsList
    }.

determine_service_status(Metric, ServiceState) ->
    MetricType = Metric#metric_point.metric_type,
    Value = Metric#metric_point.value,

    case MetricType of
        cpu ->
            case Value > ?HEALTH_THRESHOLD_CPU of
                true -> degraded;
                false -> healthy
            end;
        memory ->
            case Value > ?HEALTH_THRESHOLD_MEMORY of
                true -> degraded;
                false -> healthy
            end;
        error_rate ->
            case Value > ?HEALTH_THRESHOLD_ERROR_RATE of
                true -> critical;
                false -> healthy
            end;
        response_time ->
            case Value > ?HEALTH_THRESHOLD_RESPONSE_TIME of
                true -> degraded;
                false -> healthy
            end;
        _ -> maps:get(status, ServiceState, healthy)
    end.

get_individual_service_health(ServiceId, State) ->
    case maps:get(ServiceId, State#state.service_health, initialize_service_state()) of
        HealthState when is_map(HealthState) ->
            #{
                service_id => ServiceId,
                status => maps:get(status, HealthState, healthy),
                last_check => maps:get(last_check, HealthState, 0),
                recent_metrics => get_recent_metrics(ServiceId, State),
                active_alerts => get_service_alerts(ServiceId, State)
            };
        _ ->
            #{
                service_id => ServiceId,
                status => unknown,
                last_check => 0,
                recent_metrics => [],
                active_alerts => []
            }
    end.

get_recent_metrics(ServiceId, State) ->
    StartTime = erlang:system_time(millisecond) - 300000, % 5 minutes
    lists:filter(fun({_Timestamp, Metric}) ->
        Metric#metric_point.service =:= ServiceId andalso
        Metric#metric_point.timestamp >= StartTime
    end, ets:tab2list(State#state.metrics)).

get_service_alerts(ServiceId, State) ->
    lists:filter(fun({_AlertId, Alert}) ->
        Alert#alert.service =:= ServiceId andalso
        not Alert#alert.resolved
    end, ets:tab2list(State#state.alerts)).

collect_system_metrics() ->
    #{
        cpu_usage => get_cpu_usage(),
        memory_usage => get_memory_usage(),
        disk_usage => get_disk_usage(),
        system_load => get_system_load(),
        timestamp => erlang:system_time(millisecond)
    }.

get_cpu_usage() ->
    %% Get CPU usage percentage
    %% Placeholder implementation
    45.2.

get_memory_usage() ->
    %% Get memory usage percentage
    %% Placeholder implementation
    67.8.

get_disk_usage() ->
    %% Get disk usage percentage
    %% Placeholder implementation
    23.4.

get_system_load() ->
    %% Get system load average
    %% Placeholder implementation
    1.2.

get_active_connections() ->
    %% Get number of active connections
    %% Placeholder implementation
    1250.

get_request_rate() ->
    %% Get requests per second
    %% Placeholder implementation
    50.0.

get_average_response_time() ->
    %% Get average response time in milliseconds
    %% Placeholder implementation
    150.

get_error_rate() ->
    %% Get error rate as decimal
    %% Placeholder implementation
    0.002.

get_active_tasks() ->
    %% Get number of active tasks
    %% Placeholder implementation
    25.

get_completed_tasks() ->
    %% Get number of completed tasks
    %% Placeholder implementation
    1000.

get_failed_tasks() ->
    %% Get number of failed tasks
    %% Placeholder implementation
    5.

get_pending_notifications() ->
    %% Get number of pending notifications
    %% Placeholder implementation
    150.

get_delivered_notifications() ->
    %% Get number of delivered notifications
    %% Placeholder implementation
    2000.

get_failed_notifications() ->
    %% Get number of failed notifications
    %% Placeholder implementation
    10.

calculate_error_rate(Metrics) ->
    case Metrics#{
        delivered_notifications := DN,
        failed_notifications := FN
    } of
        Metrics when DN > 0, FN > 0 ->
            (FN / (DN + FN)) * 100;
        _ ->
            0.0
    end.

%% Alert Management
check_alert_conditions(CollectedMetrics, State) ->
    %% Check all active alert rules against collected metrics
    lists:foldl fun({RuleId, AlertRule}, Alerts) ->
        case AlertRule#alert_rule.enabled of
            true ->
                check_alert_condition(AlertRule, CollectedMetrics, State);
            false ->
                Alerts
        end
    end, [], ets:tab2list(State#state.alert_rules)).

check_alert_condition(AlertRule, Metrics, State) ->
    %% Check if alert condition is met
    RelevantMetrics = lists:filter(fun(Metric) ->
        Metric#metric_point.service =:= AlertRule#alert_rule.service
    end, Metrics),

    case RelevantMetrics of
        [] -> [];
        _ ->
            lists:foldl(fun(Metric, Alerts) ->
                case evaluate_alert_condition(AlertRule, Metric, State) of
                    true ->
                        AlertId = generate_alert_id(),
                        Alert = #alert{
                            id = AlertId,
                            rule_id = AlertRule#alert_rule.id,
                            severity = AlertRule#alert_rule.severity,
                            message = generate_alert_message(AlertRule, Metric),
                            timestamp = erlang:system_time(millisecond),
                            service = Metric#metric_point.service,
                            metric_value = Metric#metric_point.value,
                            triggered_by = "condition_met",
                            resolved = false,
                            notification_log = []
                        },
                        ets:insert(State#state.alerts, {AlertId, Alert}),
                        send_alert_notifications(Alert, State),
                        [Alert | Alerts];
                    false ->
                        Alerts
                end
            end, [], RelevantMetrics)
    end.

evaluate_alert_condition(AlertRule, Metric, State) ->
    %% Evaluate if alert condition is met
    MetricType = Metric#metric_point.metric_type,
    MetricValue = Metric#metric_point.value,
    Threshold = AlertRule#alert_rule.threshold,
    Condition = AlertRule#alert_rule.condition,

    %% Simple condition evaluation (in real implementation, use proper parser)
    case Condition of
        "cpu_usage > 80" ->
            MetricType =:= cpu andalso MetricValue > Threshold;
        "memory_usage > 85" ->
            MetricType =:= memory andalso MetricValue > Threshold;
        "response_time > 1000" ->
            MetricType =:= response_time andalso MetricValue > Threshold;
        "error_rate > 0.01" ->
            MetricType =:= error_rate andalso MetricValue > Threshold;
        _ ->
            false
    end.

generate_alert_message(AlertRule, Metric) ->
    lists:flatten(io_lib:format(
        "Alert triggered for ~s: ~s value (~p) exceeds threshold (~p)",
        [Metric#metric_point.service, atom_to_list(Metric#metric_point.metric_type), Metric#metric_point.value, AlertRule#alert_rule.threshold]
    )).

send_alert_notifications(Alert, State) ->
    %% Send alert notifications to configured channels
    NotificationChannels = case ets:lookup(State#state.alert_rules, Alert#alert.rule_id) of
        [{_, AlertRule}] ->
            AlertRule#alert_rule.notification_channels;
        _ ->
            []
    end,

    NotificationLog = lists:foldl(fun(Channel, Log) ->
        Notification = #{
            alert_id => Alert#alert.id,
            channel => Channel,
            message => Alert#alert.message,
            severity => Alert#alert.severity,
            timestamp => erlang:system_time(millisecond),
            delivered => send_channel_notification(Channel, Alert, State)
        },
        [Channel | Log]
    end, [], NotificationChannels),

    %% Update alert with notification log
    UpdatedAlert = Alert#alert{
        notification_log = NotificationLog
    },
    ets:insert(State#state.alerts, {Alert#alert.id, UpdatedAlert}).

send_channel_notification(Channel, Alert, State) ->
    %% Send notification via specific channel
    case Channel of
        "email" ->
            send_email_notification(Alert, State);
        "slack" ->
            send_slack_notification(Alert, State);
        "sms" ->
            send_sms_notification(Alert, State);
        _ ->
            false
    end.

send_email_notification(Alert, State) ->
    %% Send email notification
    %% Placeholder implementation
    logger:info("Sending email notification for alert: ~p", [Alert#alert.id]),
    true.

send_slack_notification(Alert, State) ->
    %% Send Slack notification
    %% Placeholder implementation
    logger:info("Sending Slack notification for alert: ~p", [Alert#alert.id]),
    true.

send_sms_notification(Alert, State) ->
    %% Send SMS notification
    %% Placeholder implementation
    logger:info("Sending SMS notification for alert: ~p", [Alert#alert.id]),
    true.

escalate_alert(Alert, State) ->
    %% Escalate alert based on escalation rules
    EscalationMessage = lists:flatten(io_lib:format(
        "ALERT ESCALATED: ~s - ~s",
        [Alert#alert.service, Alert#alert.message]
    )),

    EscalatedAlert = Alert#alert{
        message = EscalationMessage,
        severity = critical
    },

    %% Send escalation notifications
    send_alert_notifications(EscalatedAlert, State),

    log_event(alert_escalated, EscalatedAlert).

is_alert_timed_out(Alert, State) ->
    %% Check if alert has timed out based on duration
    case ets:lookup(State#state.alert_rules, Alert#alert.rule_id) of
        [{_, AlertRule}] ->
            Duration = AlertRule#alert_rule.duration,
            if
                Duration =:= 0 -> false; % No duration limit
                true ->
                    TimeSinceAlert = erlang:system_time(millisecond) - Alert#alert.timestamp,
                    TimeSinceAlert > Duration
            end;
        _ -> false
    end.

count_active_alerts(State) ->
    length([Alert || {_Id, Alert} <- ets:tab2list(State#state.alerts), not Alert#alert.resolved]).

get_alerts_by_timeframe(Hours, State) ->
    CutoffTime = erlang:system_time(millisecond) - (Hours * 3600000),
    lists:filter(fun({_Id, Alert}) ->
        Alert#alert.timestamp >= CutoffTime
    end, ets:tab2list(State#state.alerts)).

%% Performance Analysis
analyze_system_performance_internal(AnalysisOptions, State) ->
    TimeRange = maps:get(time_range, AnalysisOptions, 3600000), % 1 hour
    StartTime = erlang:system_time(millisecond) - TimeRange

    Metrics = lists:filter(fun({_Timestamp, Metric}) ->
        Metric#metric_point.timestamp >= StartTime
    end, ets:tab2list(State#state.metrics)),

    AnalysisResults = #{
        time_range => TimeRange,
        services_analyzed => get_analyzed_services(AnalysisOptions, State),
        performance_summary => calculate_performance_summary(Metrics),
        bottleneck_analysis => identify_bottlenecks(Metrics, State),
        trend_analysis => calculate_trends(Metrics),
        recommendations => generate_recommendations(Metrics, AnalysisOptions)
    },

    AnalysisResults.

get_analyzed_services(AnalysisOptions, State) ->
    case maps:get(services, AnalysisOptions, undefined) of
        undefined -> State#state.config#monitoring_config.critical_services;
        Services -> Services
    end.

calculate_performance_summary(Metrics) ->
    #{
        total_metrics => length(Metrics),
        unique_services => unique_services(Metrics),
        avg_cpu => average_metric(Metrics, cpu),
        avg_memory => average_metric(Metrics, memory),
        avg_response_time => average_metric(Metrics, response_time),
        error_rate_trend => calculate_error_rate_trend(Metrics)
    }.

unique_services(Metrics) ->
    lists:usort([M#metric_point.service || M <- Metrics]).

average_metric(Metrics, MetricType) ->
    RelevantMetrics = [M#metric_point.value || M <- Metrics, M#metric_point.metric_type =:= MetricType],
    case RelevantMetrics of
        [] -> 0;
        _ -> lists:sum(RelevantMetrics) / length(RelevantMetrics)
    end.

calculate_error_rate_trend(Metrics) ->
    %% Calculate error rate trend over time
    ErrorMetrics = [M#metric_point.value || M <- Metrics, M#metric_point.metric_type =:= error_rate],
    case ErrorMetrics of
        [] -> "unknown";
        _ ->
            calculate_trend_direction(ErrorMetrics)
    end.

calculate_trend_direction(Values) ->
    %% Simple trend calculation (could be improved with proper statistical analysis)
    Length = length(Values),
    if
        Length < 2 -> "stable";
        true ->
            FirstHalf = lists:sublist(Values, trunc(Length / 2)),
            SecondHalf = lists:nthtail(trunc(Length / 2), Values),
            FirstAvg = lists:sum(FirstHalf) / length(FirstHalf),
            SecondAvg = lists:sum(SecondHalf) / length(SecondHalf),
            if
                SecondAvg > FirstAvg * 1.1 -> "increasing";
                SecondAvg < FirstAvg * 0.9 -> "decreasing";
                true -> "stable"
            end
    end.

identify_bottlenecks(Metrics, State) ->
    %% Identify system bottlenecks
    Bottlenecks = lists:foldl(fun(Metric, Acc) ->
        case Metric#metric_point.metric_type of
            cpu when Metric#metric_point.value > ?HEALTH_THRESHOLD_CPU ->
                [#{service => Metric#metric_point.service, type => cpu_bottleneck} | Acc];
            memory when Metric#metric_point.value > ?HEALTH_THRESHOLD_MEMORY ->
                [#{service => Metric#metric_point.service, type => memory_bottleneck} | Acc];
            response_time when Metric#metric_point.value > ?HEALTH_THRESHOLD_RESPONSE_TIME ->
                [#{service => Metric#metric_point.service, type => response_bottleneck} | Acc];
            _ -> Acc
        end
    end, [], Metrics),

    Bottlenecks.

generate_recommendations(Metrics, AnalysisOptions) ->
    %% Generate improvement recommendations
    Recommendations = []

    %% CPU-based recommendations
    HighCpu = [M#metric_point.value || M <- Metrics, M#metric_point.metric_type =:= cpu, M#metric_point.value > 80],
    case HighCpu of
        [_|_] ->
            Recommendations ++ [#{type => cpu_optimization, priority => high}];
        _ ->
            Recommendations
    end,

    %% Memory-based recommendations
    HighMemory = [M#metric_point.value || M <- Metrics, M#metric_point.metric_type =:= memory, M#metric_point.value > 85],
    case HighMemory of
        [_|_] ->
            Recommendations ++ [#{type => memory_optimization, priority => high}];
        _ ->
            Recommendations
    end,

    Recommendations.

%% Critical Path Monitoring
critical_path_monitor(PathConfig, State) ->
    receive
        stop -> ok;
        _ ->
            PathMetrics = monitor_critical_path(PathConfig, State),
            self() ! {path_metrics, PathMetrics},
            critical_path_monitor(PathConfig, State)
    after
        10000 -> % 10 seconds
            critical_path_monitor(PathConfig, State)
    end.

monitor_critical_path(PathConfig, State) ->
    %% Monitor specific critical path
    PathId = maps:get(path_id, PathConfig),
    PathSteps = maps:get(steps, PathConfig),

    StepResults = lists:map(fun(Step) ->
        monitor_path_step(Step, State)
    end, PathSteps),

    #{
        path_id => PathId,
        timestamp => erlang:system_time(millisecond),
        step_results => StepResults,
        overall_status => determine_path_status(StepResults)
    }.

monitor_path_step(Step, State) ->
    %% Monitor individual step in critical path
    StepId = maps:get(step_id, Step),
    StepType = maps:get(step_type, Step),

    case StepType of
        "service_call" ->
            monitor_service_step(Step, State);
        "database_query" ->
            monitor_database_step(Step, State);
        "external_api" ->
            monitor_external_step(Step, State);
        _ ->
            monitor_generic_step(Step, State)
    end.

monitor_service_step(Step, State) ->
    StepId = maps:get(step_id, Step),
    ServiceId = maps.get(service_id, Step),
    StartTime = erlang:system_time(millisecond),

    %% Simulate service call
    Response = simulate_service_call(ServiceId),

    EndTime = erlang:system_time(millisecond),
    Duration = EndTime - StartTime,

    #{
        step_id => StepId,
        step_type => "service_call",
        service_id => ServiceId,
        status => case Response#{
            success := true
        } of
            Response -> success;
            _ -> failed
        end,
        duration => Duration,
        timestamp => EndTime,
        response => Response
    }.

monitor_database_step(Step, State) ->
    StepId = maps:get(step_id, Step),
    Query = maps:get(query, Step),
    StartTime = erlang:system_time(millisecond),

    %% Simulate database query
    Result = simulate_database_query(Query),

    EndTime = erlang:system_time(millisecond),
    Duration = EndTime - StartTime,

    #{
        step_id => StepId,
        step_type => "database_query",
        query => Query,
        status => case Result#{
            success := true
        } of
            Result -> success;
            _ -> failed
        end,
        duration => Duration,
        timestamp => EndTime,
        result => Result
    }.

monitor_external_step(Step, State) ->
    StepId = maps:get(step_id, Step),
    ApiEndpoint = maps:get(api_endpoint, Step),
    StartTime = erlang:system_time(millisecond),

    %% Simulate external API call
    ApiResult = simulate_external_api_call(ApiEndpoint),

    EndTime = erlang:system_time(millisecond),
    Duration = EndTime - StartTime,

    #{
        step_id => StepId,
        step_type => "external_api",
        api_endpoint => ApiEndpoint,
        status => case ApiResult#{
            success := true
        } of
            ApiResult -> success;
            _ -> failed
        end,
        duration => Duration,
        timestamp => EndTime,
        response => ApiResult
    }.

monitor_generic_step(Step, State) ->
    StepId = maps:get(step_id, Step),
    StepType = maps:get(step_type, Step),
    StartTime = erlang:system_time(millisecond),

    %% Simulate generic step
    StepResult = simulate_generic_step(StepType, State),

    EndTime = erlang:system_time(millisecond),
    Duration = EndTime - StartTime,

    #{
        step_id => StepId,
        step_type => StepType,
        status => success, % Placeholder
        duration => Duration,
        timestamp => EndTime,
        result => StepResult
    }.

simulate_service_call(ServiceId) ->
    %% Simulate service call
    case ServiceId of
        "a2a_http_handler" ->
            #{success => true, response_time => 50};
        _ ->
            #{success => true, response_time => 100}
    end.

simulate_database_query(Query) ->
    %% Simulate database query
    #{success => true, execution_time => 20, rows_affected => 1}.

simulate_external_api_call(ApiEndpoint) ->
    %% Simulate external API call
    #{success => true, response_time => 200, status_code => 200}.

simulate_generic_step(StepType, State) ->
    %% Simulate generic step
    #{success => true, duration => 50}.

determine_path_status(StepResults) ->
    case lists:all(fun(Step) -> maps:get(status, Step) =:= success end, StepResults) of
        true -> healthy;
        false -> degraded
    end.

%% Reporting
generate_comprehensive_health_report(State) ->
    HealthMetrics = collect_health_metrics(State),
    PerformanceMetrics = get_performance_metrics_for_report(State),
    AlertSummary = get_alert_summary(State),
    Recommendations = generate_health_recommendations(State),

    #{
        timestamp => erlang:system_time(millisecond),
        executive_summary => generate_executive_summary(HealthMetrics, AlertSummary),
        system_health => HealthMetrics,
        performance_analysis => PerformanceMetrics,
        alert_summary => AlertSummary,
        recommendations => Recommendations,
        service_health_details => generate_service_health_details(State),
        system_metrics => collect_system_metrics(),
        monitoring_status => get_monitoring_status(State)
    }.

get_performance_metrics_for_report(State) ->
    TimeRange = 3600000, % 1 hour
    StartTime = erlang:system_time(millisecond) - TimeRange

    Metrics = lists:filter(fun({_Timestamp, Metric}) ->
        Metric#metric_point.timestamp >= StartTime
    end, ets:tab2list(State#state.metrics)),

    #{
        time_range => TimeRange,
        total_metrics => length(Metrics),
        services => analyze_service_performance(Metrics, State),
        trends => calculate_performance_trends(Metrics),
        anomalies => identify_performance_anomalies(Metrics)
    }.

analyze_service_performance(Metrics, State) ->
    Services = lists:usort([M#metric_point.service || M <- Metrics]),
    lists:map(fun(Service) ->
        ServiceMetrics = [M#metric_point.value || M <- Metrics, M#metric_point.service =:= Service],
        #{
            service_id => Service,
            average_response => lists:sum(ServiceMetrics) / length(ServiceMetrics),
            max_response => lists:max(ServiceMetrics),
            min_response => lists:min(ServiceMetrics),
            error_rate => calculate_service_error_rate(ServiceMetrics),
            availability => calculate_service_availability(ServiceMetrics)
        }
    end, Services).

calculate_service_error_rate(Metrics) ->
    ErrorMetrics = [M || M <- Metrics, M#metric_point.metric_type =:= error_rate],
    case ErrorMetrics of
        [] -> 0.0;
        _ -> lists:sum([M#metric_point.value || M <- ErrorMetrics]) / length(ErrorMetrics)
    end.

calculate_service_availability(Metrics) ->
    SuccessfulMetrics = [M || M <- Metrics, M#metric_point.metric_type =/= error_rate orelse M#metric_point.value =:= 0],
    case Metrics of
        [] -> 0.0;
        _ -> length(SuccessfulMetrics) / length(Metrics)
    end.

calculate_performance_trends(Metrics) ->
    %% Calculate performance trends for different metric types
    MetricTypes = lists:usort([M#metric_point.metric_type || M <- Metrics]),
    lists:map(fun(Type) ->
        TypeMetrics = [M#metric_point.value || M <- Metrics, M#metric_point.metric_type =:= Type],
        #{
            metric_type => Type,
            average => lists:sum(TypeMetrics) / length(TypeMetrics),
            trend => calculate_metric_trend(TypeMetrics)
        }
    end, MetricTypes).

calculate_metric_trend(Metrics) ->
    %% Calculate trend direction for metric values
    case Metrics of
        [_] -> "stable";
        _ ->
            First = lists:nth(1, Metrics),
            Last = lists:last(Metrics),
            Diff = Last - First,
            if
                Diff > First * 0.1 -> "increasing";
                Diff < First * -0.1 -> "decreasing";
                true -> "stable"
            end
    end.

identify_performance_anomalies(Metrics) ->
    %% Identify performance anomalies using statistical methods
    AnomalyThreshold = 2.0, % 2 standard deviations
    Anomalies = []

    lists:foldl fun(Metric, Acc) ->
        case is_metric_anomalous(Metric, Metrics) of
            true -> [Metric | Acc];
            false -> Acc
        end
    end, [], Metrics).

is_metric_anomalous(Metric, AllMetrics) ->
    MetricType = Metric#metric_point.metric_type,
    MetricValue = Metric#metric_point.value,

    TypeMetrics = [M#metric_point.value || M <- AllMetrics, M#metric_point.metric_type =:= MetricType],
    case TypeMetrics of
        [] -> false;
        _ ->
            Mean = lists:sum(TypeMetrics) / length(TypeMetrics),
            Variance = calculate_variance(TypeMetrics, Mean),
            StdDev = math:sqrt(Variance),
            Deviation = abs(MetricValue - Mean),
            Deviation > AnomalyThreshold * StdDev
    end.

calculate_variance(Values, Mean) ->
    lists:sum([(V - Mean) * (V - Mean) || V <- Values]) / length(Values).

get_alert_summary(State) ->
    ActiveAlerts = [Alert || {_Id, Alert} <- ets:tab2list(State#state.alerts), not Alert#alert.resolved],
    ResolvedAlerts = [Alert || {_Id, Alert} <- ets:tab2list(State#state.alerts), Alert#alert.resolved],

    #{
        active_count => length(ActiveAlerts),
        resolved_count => length(ResolvedAlerts),
        critical_count => length([A || A <- ActiveAlerts, A#alert.severity =:= critical]),
        high_count => length([A || A <- ActiveAlerts, A#alert.severity =:= high]),
        distribution => alert_distribution(ActiveAlerts),
        recent_alerts => lists:sublist(lists:reverse(ets:tab2list(State#state.alerts)), 10)
    }.

alert_distribution(Alerts) ->
    #{
        critical => length([A || A <- Alerts, A#alert.severity =:= critical]),
        high => length([A || A <- Alerts, A#alert.severity =:= high]),
        medium => length([A || A <- Alerts, A#alert.severity =:= medium]),
        low => length([A || A <- Alerts, A#alert.severity =:= low])
    }.

generate_health_recommendations(State) ->
    %% Generate health recommendations based on current state
    Recommendations = []

    CPURecommendations = case get_cpu_usage() > 80 of
        true -> [#{type => cpu_optimization, priority => high, description => "High CPU usage detected. Consider optimizing service code or scaling horizontally."}];
        false -> []
    end,

    MemoryRecommendations = case get_memory_usage() > 85 of
        true -> [#{type => memory_optimization, priority => high, description => "High memory usage detected. Check for memory leaks and optimize data structures."}];
        false -> []
    end,

    AlertRecommendations = case count_active_alerts(State) > 5 of
        true -> [#{type => alert_management, priority => medium, description => "High number of active alerts. Consider reviewing alert thresholds and configuration."}];
        false -> []
    end,

    ServiceRecommendations = generate_service_specific_recommendations(State),

    CPURecommendations ++ MemoryRecommendations ++ AlertRecommendations ++ ServiceRecommendations.

generate_service_specific_recommendations(State) ->
    %% Generate recommendations specific to service health
    lists:foldl(fun(ServiceId, Acc) ->
        case get_individual_service_health(ServiceId, State) of
            ServiceHealth when is_map(ServiceHealth) ->
                case ServiceHealth#{
                    status := degraded
                } of
                    ServiceHealth ->
                        [#{type => service_optimization, service_id => ServiceId, priority => medium, description => "Service " ++ binary_to_list(ServiceId) ++ " is degraded. Check logs and performance metrics."} | Acc];
                    _ -> Acc
                end;
            _ -> Acc
        end
    end, [], State#state.config#monitoring_config.critical_services).

generate_service_health_details(State) ->
    lists:map(fun(ServiceId) ->
        get_individual_service_health(ServiceId, State)
    end, State#state.config#monitoring_config.critical_services).

get_monitoring_status(State) ->
    #{
        overall_status => State#state.health_status,
        active_monitors => length(State#state.active_monitors),
        total_metrics => ets:info(State#state.metrics, size),
        total_alerts => ets:info(State#state.alerts, size),
        last_metrics_update => State#state.last_metrics_update,
        config => State#state.config
    }.

generate_executive_summary(HealthMetrics, AlertSummary) ->
    #{
        overall_health => HealthMetrics#{
            overall_status := OverallStatus
        } = HealthMetrics,
        status_summary => case OverallStatus of
            healthy -> "All systems are operating normally";
            degraded -> "Some systems are experiencing performance issues";
            critical -> "Critical system issues detected - immediate attention required"
        end,
        alert_summary => AlertSummary#{
            active_count := ActiveCount,
            critical_count := CriticalCount
        },
        timestamp => erlang:system_time(millisecond)
    }.

%% Utility Functions
generate_alert_id() ->
    Bytes = crypto:strong_rand_bytes(16),
    binary:encode_hex(Bytes).

generate_alert_rule_id() ->
    Bytes = crypto:strong_rand_bytes(12),
    binary:encode_hex(Bytes).

get_service_id_from_pid(Pid, State) ->
    %% Get service ID from monitor process PID
    case lists:filter(fun({_, P}) -> P =:= Pid end, State#state.active_monitors) of
        [{_, Pid, ServiceId} | _] -> ServiceId;
        _ -> undefined
    end.

log_event(EventType, Data) ->
    LogEntry = #{
        event => EventType,
        data => Data,
        timestamp => erlang:system_time(millisecond)
    },

    case filelib:ensure_dir(?ALERT_LOG_FILE) of
        ok ->
            file:write_file(?ALERT_LOG_FILE, jsx:encode(LogEntry) ++ <<"\n">>, [append]);
        {error, Reason} ->
            logger:error("Failed to write monitoring log: ~p", [Reason])
    end.

log_termination(Reason) ->
    log_event(system_termination, #{reason => Reason}).

establish_performance_baseline() ->
    %% Establish performance baseline
    #{
        cpu => 45.0,
        memory => 60.0,
        disk => 20.0,
        response_time => 150.0,
        error_rate => 0.001
    }.

get_service_metrics_by_service(ServiceId, State, StartTime) ->
    lists:filter(fun({_Timestamp, Metric}) ->
        Metric#metric_point.service =:= ServiceId andalso
        Metric#metric_point.timestamp >= StartTime
    end, ets:tab2list(State#state.metrics)).

calculate_average_response_time(ServiceId, State) ->
    StartTime = erlang:system_time(millisecond) - 3600000, % 1 hour
    ServiceMetrics = get_service_metrics_by_service(ServiceId, State, StartTime),
    ResponseMetrics = [M#metric_point.value || M <- ServiceMetrics, M#metric_point.metric_type =:= response_time],

    case ResponseMetrics of
        [] -> 0;
        _ -> lists:sum(ResponseMetrics) / length(ResponseMetrics)
    end.

validate_service_health_internal(ServiceId, State) ->
    ServiceHealth = get_individual_service_health(ServiceId, State),
    ServiceMetrics = get_service_metrics(ServiceId, State),

    ValidationResults = #{
        service_id => ServiceId,
        health_status => maps:get(status, ServiceHealth),
        metrics_collected => length(ServiceMetrics),
        performance_metrics => extract_performance_metrics(ServiceMetrics),
        recommendations => generate_service_recommendations(ServiceId, State)
    },

    ValidationResults.

extract_performance_metrics(ServiceMetrics) ->
    lists:foldl(fun(Metric, Acc) ->
        MetricType = Metric#metric_point.metric_type,
        Value = Metric#metric_point.value,
        case MetricType of
            cpu ->
                Acc#{cpu => Value};
            memory ->
                Acc#{memory => Value};
            response_time ->
                Acc#{response_time => Value};
            error_rate ->
                Acc#{error_rate => Value};
            _ -> Acc
        end
    end, #{}, ServiceMetrics).

generate_service_recommendations(ServiceId, State) ->
    %% Generate specific recommendations for a service
    Recommendations = []

    ServiceMetrics = get_service_metrics(ServiceId, State),
    CpuMetrics = [M#metric_point.value || M <- ServiceMetrics, M#metric_point.metric_type =:= cpu],
    MemoryMetrics = [M#metric_point.value || M <- ServiceMetrics, M#metric_point.metric_type =:= memory],

    case CpuMetrics of
        [_|_] when lists:max(CpuMetrics) > 80 ->
            Recommendations ++ [#{type => cpu_scaling, service_id => ServiceId, priority => high}];
        _ -> Recommendations
    end,

    case MemoryMetrics of
        [_|_] when lists:max(MemoryMetrics) > 85 ->
            Recommendations ++ [#{type => memory_optimization, service_id => ServiceId, priority => high}];
        _ -> Recommendations
    end.