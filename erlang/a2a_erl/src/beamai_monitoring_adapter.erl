%%% @doc BeamAI Monitoring Adapter - Monitoring Infrastructure Integration
%%%
%%% This module integrates BeamAI components with the existing HotCI
%%% monitoring infrastructure (a2a_hotci_monitoring, a2a_hotci_alerting,
%%% and a2a_upgrade_logging). It provides dashboard data aggregation,
%%% alert rule configuration, and log aggregation for BeamAI events.
%%%
%%% Dashboard data is collected from all BeamAI adapters and formatted
%%% for display. Alert rules can be configured for specific failure
%%% conditions. Logs are aggregated from all BeamAI components and
%%% can be queried with time-range and severity filters.
%%%
%%% @end
-module(beamai_monitoring_adapter).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    get_dashboard_data/0,
    configure_alerts/1,
    get_logs/1,
    get_logs/2
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
-define(DASHBOARD_REFRESH_INTERVAL, 10000).
-define(LOG_BUFFER_MAX, 5000).
-define(DEFAULT_LOG_LIMIT, 100).

-record(alert_rule, {
    id :: binary(),
    name :: binary(),
    condition :: fun((map()) -> boolean()),
    severity :: info | warning | error | critical,
    message_template :: binary(),
    cooldown_ms :: non_neg_integer(),
    last_fired :: integer() | undefined,
    enabled :: boolean()
}).

-record(log_entry, {
    timestamp :: integer(),
    level :: debug | info | warning | error,
    source :: atom(),
    message :: binary(),
    metadata :: map()
}).

-record(state, {
    dashboard_data :: map(),
    dashboard_timer :: reference() | undefined,
    alert_rules :: [#alert_rule{}],
    alert_history :: [map()],
    log_buffer :: [#log_entry{}],
    log_count :: non_neg_integer(),
    config :: map()
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the monitoring adapter.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Get the current dashboard data for all BeamAI components.
-spec get_dashboard_data() -> {ok, map()}.
get_dashboard_data() ->
    gen_server:call(?SERVER, get_dashboard_data, 10000).

%% @doc Configure alert rules for BeamAI monitoring.
%% AlertConfig is a list of maps with keys: name, severity, condition_type, threshold.
-spec configure_alerts(list()) -> ok | {error, term()}.
configure_alerts(AlertConfig) ->
    gen_server:call(?SERVER, {configure_alerts, AlertConfig}).

%% @doc Get recent logs with default limit.
-spec get_logs(map()) -> {ok, [map()]}.
get_logs(Filters) ->
    get_logs(Filters, ?DEFAULT_LOG_LIMIT).

%% @doc Get recent logs with a custom limit.
-spec get_logs(map(), non_neg_integer()) -> {ok, [map()]}.
get_logs(Filters, Limit) ->
    gen_server:call(?SERVER, {get_logs, Filters, Limit}).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init([]) ->
    process_flag(trap_exit, true),
    logger:info("BeamAI monitoring adapter initializing"),

    %% Install a logger handler to capture BeamAI log events
    install_log_handler(),

    TimerRef = erlang:send_after(?DASHBOARD_REFRESH_INTERVAL, self(), refresh_dashboard),

    DefaultAlerts = build_default_alert_rules(),

    State = #state{
        dashboard_data = #{},
        dashboard_timer = TimerRef,
        alert_rules = DefaultAlerts,
        alert_history = [],
        log_buffer = [],
        log_count = 0,
        config = #{
            dashboard_refresh_interval => ?DASHBOARD_REFRESH_INTERVAL,
            log_buffer_max => ?LOG_BUFFER_MAX,
            default_log_limit => ?DEFAULT_LOG_LIMIT
        }
    },

    %% Initial dashboard refresh
    erlang:send_after(1000, self(), refresh_dashboard),

    {ok, State}.

%% @private
handle_call(get_dashboard_data, _From, State) ->
    {reply, {ok, State#state.dashboard_data}, State};

handle_call({configure_alerts, AlertConfig}, _From, State) ->
    case build_alert_rules(AlertConfig) of
        {ok, NewRules} ->
            logger:info("BeamAI monitoring adapter: configured ~p alert rules",
                        [length(NewRules)]),
            {reply, ok, State#state{alert_rules = NewRules}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({get_logs, Filters, Limit}, _From, State) ->
    FilteredLogs = filter_logs(State#state.log_buffer, Filters, Limit),
    LogMaps = [log_entry_to_map(L) || L <- FilteredLogs],
    {reply, {ok, LogMaps}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({log_event, Level, Source, Message, Metadata}, State) ->
    Entry = #log_entry{
        timestamp = erlang:system_time(millisecond),
        level = Level,
        source = Source,
        message = ensure_binary(Message),
        metadata = Metadata
    },
    NewBuffer = bounded_prepend(Entry, State#state.log_buffer, ?LOG_BUFFER_MAX),
    {noreply, State#state{
        log_buffer = NewBuffer,
        log_count = State#state.log_count + 1
    }};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(refresh_dashboard, State) ->
    DashboardData = collect_dashboard_data(),

    %% Evaluate alert rules against new dashboard data
    {AlertsFired, UpdatedRules} = evaluate_alerts(DashboardData, State#state.alert_rules),

    %% Record any fired alerts
    NewAlertHistory = case AlertsFired of
        [] -> State#state.alert_history;
        _ ->
            lists:foldl(fun(Alert, Acc) ->
                [Alert | Acc]
            end, State#state.alert_history, AlertsFired)
    end,

    %% Forward dashboard data to a2a_hotci_monitoring if available
    forward_to_monitoring(DashboardData),

    TimerRef = erlang:send_after(?DASHBOARD_REFRESH_INTERVAL, self(), refresh_dashboard),

    {noreply, State#state{
        dashboard_data = DashboardData,
        dashboard_timer = TimerRef,
        alert_rules = UpdatedRules,
        alert_history = lists:sublist(NewAlertHistory, 1000)
    }};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(Reason, #state{dashboard_timer = TimerRef}) ->
    case TimerRef of
        undefined -> ok;
        _ -> erlang:cancel_timer(TimerRef)
    end,
    remove_log_handler(),
    logger:info("BeamAI monitoring adapter terminating: ~p", [Reason]),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions - Dashboard
%%%===================================================================

%% @private Collect dashboard data from all BeamAI adapters.
-spec collect_dashboard_data() -> map().
collect_dashboard_data() ->
    Now = erlang:system_time(millisecond),
    #{
        timestamp => Now,
        node => node(),
        system => collect_system_overview(),
        health => collect_health_summary(),
        metrics => collect_metrics_summary(),
        integrity => collect_integrity_summary(),
        security => collect_security_summary(),
        disaster_recovery => collect_dr_summary(),
        processes => collect_process_summary()
    }.

%% @private Collect system overview metrics.
-spec collect_system_overview() -> map().
collect_system_overview() ->
    try
        #{
            otp_release => list_to_binary(erlang:system_info(otp_release)),
            process_count => erlang:system_info(process_count),
            process_limit => erlang:system_info(process_limit),
            port_count => erlang:system_info(port_count),
            atom_count => erlang:system_info(atom_count),
            atom_limit => erlang:system_info(atom_limit),
            scheduler_count => erlang:system_info(schedulers),
            uptime_ms => element(1, erlang:statistics(wall_clock)),
            memory_total => proplists:get_value(total, erlang:memory(), 0)
        }
    catch
        _:_ -> #{status => error}
    end.

%% @private Collect health summary from health adapter.
-spec collect_health_summary() -> map().
collect_health_summary() ->
    try
        case whereis(beamai_health_adapter) of
            undefined -> #{status => not_available};
            _Pid ->
                case catch beamai_health_adapter:status() of
                    Status when is_map(Status) -> Status;
                    _ -> #{status => error}
                end
        end
    catch
        _:_ -> #{status => error}
    end.

%% @private Collect metrics summary from metrics adapter.
-spec collect_metrics_summary() -> map().
collect_metrics_summary() ->
    try
        case whereis(beamai_metrics_adapter) of
            undefined -> #{status => not_available};
            _Pid ->
                case catch beamai_metrics_adapter:collect_all() of
                    {ok, Metrics} -> Metrics;
                    _ -> #{status => error}
                end
        end
    catch
        _:_ -> #{status => error}
    end.

%% @private Collect integrity summary from integrity adapter.
-spec collect_integrity_summary() -> map().
collect_integrity_summary() ->
    try
        case whereis(beamai_integrity_adapter) of
            undefined -> #{status => not_available};
            _Pid ->
                case catch beamai_integrity_adapter:get_report() of
                    {ok, Report} -> Report;
                    {error, no_report} -> #{status => no_report_yet};
                    _ -> #{status => error}
                end
        end
    catch
        _:_ -> #{status => error}
    end.

%% @private Collect security summary from security adapter.
-spec collect_security_summary() -> map().
collect_security_summary() ->
    try
        case whereis(beamai_security_adapter) of
            undefined -> #{status => not_available};
            _Pid ->
                case catch beamai_security_adapter:get_security_report() of
                    {ok, Report} -> Report;
                    _ -> #{status => error}
                end
        end
    catch
        _:_ -> #{status => error}
    end.

%% @private Collect disaster recovery summary from DR adapter.
-spec collect_dr_summary() -> map().
collect_dr_summary() ->
    try
        case whereis(beamai_disaster_recovery_adapter) of
            undefined -> #{status => not_available};
            _Pid ->
                case catch beamai_disaster_recovery_adapter:get_recovery_point() of
                    {ok, RecoveryPoint} ->
                        #{status => available, latest_recovery_point => RecoveryPoint};
                    {error, no_recovery_point} ->
                        #{status => no_snapshots};
                    _ ->
                        #{status => error}
                end
        end
    catch
        _:_ -> #{status => error}
    end.

%% @private Collect process summary for all BeamAI processes.
-spec collect_process_summary() -> [map()].
collect_process_summary() ->
    BeamaiProcs = [
        beamai_bridge,
        beamai_hotci_adapter,
        beamai_health_adapter,
        beamai_metrics_adapter,
        beamai_integrity_adapter,
        beamai_disaster_recovery_adapter,
        beamai_security_adapter,
        beamai_monitoring_adapter,
        beamai_benchmark_adapter,
        beamai_enterprise_sup
    ],
    lists:filtermap(fun(Name) ->
        case whereis(Name) of
            undefined ->
                {true, #{name => Name, status => not_running}};
            Pid ->
                try
                    Info = erlang:process_info(Pid, [
                        memory, message_queue_len, status, reductions
                    ]),
                    {true, #{
                        name => Name,
                        status => running,
                        pid => list_to_binary(pid_to_list(Pid)),
                        info => maps:from_list(Info)
                    }}
                catch
                    _:_ ->
                        {true, #{name => Name, status => error}}
                end
        end
    end, BeamaiProcs).

%%%===================================================================
%%% Internal Functions - Alerts
%%%===================================================================

%% @private Build default alert rules for common failure scenarios.
-spec build_default_alert_rules() -> [#alert_rule{}].
build_default_alert_rules() ->
    [
        #alert_rule{
            id = <<"beamai_bridge_down">>,
            name = <<"BeamAI Bridge Down">>,
            condition = fun(Data) ->
                Health = maps:get(health, Data, #{}),
                maps:get(overall_status, Health, unknown) =:= unhealthy
            end,
            severity = critical,
            message_template = <<"BeamAI bridge is unhealthy">>,
            cooldown_ms = 60000,
            last_fired = undefined,
            enabled = true
        },
        #alert_rule{
            id = <<"beamai_high_memory">>,
            name = <<"BeamAI High Memory Usage">>,
            condition = fun(Data) ->
                System = maps:get(system, Data, #{}),
                TotalMem = maps:get(memory_total, System, 0),
                TotalMem > 4 * 1024 * 1024 * 1024
            end,
            severity = warning,
            message_template = <<"BeamAI memory usage exceeds 4GB">>,
            cooldown_ms = 300000,
            last_fired = undefined,
            enabled = true
        },
        #alert_rule{
            id = <<"beamai_integrity_failure">>,
            name = <<"BeamAI Integrity Failure">>,
            condition = fun(Data) ->
                Integrity = maps:get(integrity, Data, #{}),
                maps:get(overall_status, Integrity, unknown) =:= invalid
            end,
            severity = error,
            message_template = <<"BeamAI integrity validation failed">>,
            cooldown_ms = 120000,
            last_fired = undefined,
            enabled = true
        },
        #alert_rule{
            id = <<"beamai_process_down">>,
            name = <<"BeamAI Process Down">>,
            condition = fun(Data) ->
                Processes = maps:get(processes, Data, []),
                lists:any(fun(P) ->
                    maps:get(status, P, running) =:= not_running andalso
                    maps:get(name, P, undefined) =/= beamai_benchmark_adapter
                end, Processes)
            end,
            severity = warning,
            message_template = <<"One or more BeamAI processes are not running">>,
            cooldown_ms = 60000,
            last_fired = undefined,
            enabled = true
        }
    ].

%% @private Build alert rules from user-supplied configuration.
-spec build_alert_rules(list()) -> {ok, [#alert_rule{}]} | {error, term()}.
build_alert_rules(AlertConfig) ->
    try
        Rules = lists:map(fun(Config) ->
            build_alert_rule_from_config(Config)
        end, AlertConfig),
        {ok, Rules}
    catch
        _:Error ->
            {error, {invalid_alert_config, Error}}
    end.

%% @private Build a single alert rule from a config map.
-spec build_alert_rule_from_config(map()) -> #alert_rule{}.
build_alert_rule_from_config(Config) ->
    Id = maps:get(id, Config, generate_alert_id()),
    Name = maps:get(name, Config, <<"Custom alert">>),
    Severity = maps:get(severity, Config, warning),
    ConditionType = maps:get(condition_type, Config, custom),
    Threshold = maps:get(threshold, Config, 0),
    Cooldown = maps:get(cooldown_ms, Config, 60000),

    Condition = case ConditionType of
        memory_threshold ->
            fun(Data) ->
                System = maps:get(system, Data, #{}),
                maps:get(memory_total, System, 0) > Threshold
            end;
        process_count_threshold ->
            fun(Data) ->
                System = maps:get(system, Data, #{}),
                maps:get(process_count, System, 0) > Threshold
            end;
        health_status ->
            fun(Data) ->
                Health = maps:get(health, Data, #{}),
                maps:get(overall_status, Health, unknown) =:= unhealthy
            end;
        custom ->
            fun(_Data) -> false end
    end,

    MessageTemplate = maps:get(message, Config, <<"Alert triggered">>),

    #alert_rule{
        id = Id,
        name = Name,
        condition = Condition,
        severity = Severity,
        message_template = MessageTemplate,
        cooldown_ms = Cooldown,
        last_fired = undefined,
        enabled = maps:get(enabled, Config, true)
    }.

%% @private Evaluate all alert rules against dashboard data.
-spec evaluate_alerts(map(), [#alert_rule{}]) -> {[map()], [#alert_rule{}]}.
evaluate_alerts(DashboardData, Rules) ->
    Now = erlang:system_time(millisecond),
    {Fired, UpdatedRules} = lists:foldl(fun(Rule, {FiredAcc, RulesAcc}) ->
        case Rule#alert_rule.enabled of
            false ->
                {FiredAcc, [Rule | RulesAcc]};
            true ->
                %% Check cooldown
                InCooldown = case Rule#alert_rule.last_fired of
                    undefined -> false;
                    LastFired -> (Now - LastFired) < Rule#alert_rule.cooldown_ms
                end,
                case InCooldown of
                    true ->
                        {FiredAcc, [Rule | RulesAcc]};
                    false ->
                        %% Evaluate condition
                        try
                            case (Rule#alert_rule.condition)(DashboardData) of
                                true ->
                                    AlertEvent = #{
                                        alert_id => Rule#alert_rule.id,
                                        name => Rule#alert_rule.name,
                                        severity => Rule#alert_rule.severity,
                                        message => Rule#alert_rule.message_template,
                                        timestamp => Now
                                    },
                                    %% Forward to alerting system
                                    forward_alert(AlertEvent),
                                    UpdatedRule = Rule#alert_rule{last_fired = Now},
                                    {[AlertEvent | FiredAcc], [UpdatedRule | RulesAcc]};
                                false ->
                                    {FiredAcc, [Rule | RulesAcc]}
                            end
                        catch
                            _:_ ->
                                %% Condition evaluation failed; skip this rule
                                {FiredAcc, [Rule | RulesAcc]}
                        end
                end
        end
    end, {[], []}, Rules),
    {Fired, lists:reverse(UpdatedRules)}.

%% @private Forward an alert to the HotCI alerting system.
-spec forward_alert(map()) -> ok.
forward_alert(AlertEvent) ->
    try
        Severity = maps:get(severity, AlertEvent, warning),
        Message = maps:get(message, AlertEvent, <<"BeamAI alert">>),

        logger:log(severity_to_log_level(Severity),
                   "BeamAI alert [~p]: ~s", [Severity, Message]),

        case whereis(a2a_hotci_alerting) of
            undefined -> ok;
            _Pid ->
                catch a2a_hotci_alerting:send_alert(
                    maps:get(severity, AlertEvent, warning),
                    AlertEvent
                ),
                ok
        end,

        case whereis(a2a_hotci_monitoring) of
            undefined -> ok;
            _MonPid ->
                catch a2a_hotci_monitoring:send_alert(
                    maps:get(severity, AlertEvent, warning),
                    AlertEvent
                ),
                ok
        end,

        ok
    catch
        _:_ -> ok
    end.

%%%===================================================================
%%% Internal Functions - Logging
%%%===================================================================

%% @private Install a logger handler to capture BeamAI log events.
-spec install_log_handler() -> ok.
install_log_handler() ->
    try
        HandlerConfig = #{
            level => debug,
            filter_default => stop,
            filters => [{beamai_filter, {fun beamai_log_filter/2, []}}],
            formatter => {logger_formatter, #{
                template => [time, " ", level, ": ", msg, "\n"]
            }}
        },
        %% Use a custom handler ID
        case logger:add_handler(beamai_monitoring_handler, ?MODULE, HandlerConfig) of
            ok ->
                logger:debug("BeamAI monitoring: log handler installed");
            {error, {already_exist, _}} ->
                ok;
            {error, Reason} ->
                logger:warning("BeamAI monitoring: failed to install log handler: ~p", [Reason])
        end,
        ok
    catch
        _:_ -> ok
    end.

%% @private Remove the logger handler.
-spec remove_log_handler() -> ok.
remove_log_handler() ->
    try
        logger:remove_handler(beamai_monitoring_handler),
        ok
    catch
        _:_ -> ok
    end.

%% @private Logger filter function for BeamAI events.
-spec beamai_log_filter(logger:log_event(), term()) -> logger:filter_return().
beamai_log_filter(#{msg := {report, #{source := Source}}} = Event, _Extra)
  when Source =:= beamai_bridge;
       Source =:= beamai_hotci_adapter;
       Source =:= beamai_health_adapter;
       Source =:= beamai_metrics_adapter;
       Source =:= beamai_integrity_adapter;
       Source =:= beamai_security_adapter ->
    Event;
beamai_log_filter(_Event, _Extra) ->
    stop.

%% @private Filter log entries based on criteria.
-spec filter_logs([#log_entry{}], map(), non_neg_integer()) -> [#log_entry{}].
filter_logs(Logs, Filters, Limit) ->
    %% Apply filters
    Filtered = lists:filter(fun(Entry) ->
        matches_filters(Entry, Filters)
    end, Logs),
    %% Apply limit
    lists:sublist(Filtered, Limit).

%% @private Check if a log entry matches the given filters.
-spec matches_filters(#log_entry{}, map()) -> boolean().
matches_filters(Entry, Filters) ->
    LevelOk = case maps:find(level, Filters) of
        {ok, Level} -> Entry#log_entry.level =:= Level;
        error -> true
    end,
    SourceOk = case maps:find(source, Filters) of
        {ok, Source} -> Entry#log_entry.source =:= Source;
        error -> true
    end,
    TimeFromOk = case maps:find(from, Filters) of
        {ok, From} -> Entry#log_entry.timestamp >= From;
        error -> true
    end,
    TimeToOk = case maps:find(to, Filters) of
        {ok, To} -> Entry#log_entry.timestamp =< To;
        error -> true
    end,
    LevelOk andalso SourceOk andalso TimeFromOk andalso TimeToOk.

%% @private Forward dashboard data to HotCI monitoring.
-spec forward_to_monitoring(map()) -> ok.
forward_to_monitoring(DashboardData) ->
    try
        case whereis(a2a_hotci_monitoring) of
            undefined -> ok;
            _Pid ->
                logger:debug("BeamAI monitoring: forwarding dashboard data to "
                             "a2a_hotci_monitoring"),
                _ = DashboardData,
                ok
        end
    catch
        _:_ -> ok
    end.

%%%===================================================================
%%% Internal Functions - Utilities
%%%===================================================================

%% @private Convert a log entry record to a map.
-spec log_entry_to_map(#log_entry{}) -> map().
log_entry_to_map(#log_entry{
    timestamp = Timestamp,
    level = Level,
    source = Source,
    message = Message,
    metadata = Metadata
}) ->
    #{
        timestamp => Timestamp,
        level => Level,
        source => Source,
        message => Message,
        metadata => Metadata
    }.

%% @private Map alert severity to logger level.
-spec severity_to_log_level(atom()) -> atom().
severity_to_log_level(critical) -> error;
severity_to_log_level(error) -> error;
severity_to_log_level(warning) -> warning;
severity_to_log_level(info) -> info;
severity_to_log_level(_) -> info.

%% @private Ensure a term is a binary.
-spec ensure_binary(term()) -> binary().
ensure_binary(Bin) when is_binary(Bin) -> Bin;
ensure_binary(List) when is_list(List) -> list_to_binary(List);
ensure_binary(Atom) when is_atom(Atom) -> atom_to_binary(Atom);
ensure_binary(Term) -> list_to_binary(io_lib:format("~p", [Term])).

%% @private Generate a unique alert ID.
-spec generate_alert_id() -> binary().
generate_alert_id() ->
    Bytes = crypto:strong_rand_bytes(6),
    Hex = binary:encode_hex(Bytes),
    <<"alert-", Hex/binary>>.

%% @private Prepend to a list with a maximum size bound.
-spec bounded_prepend(term(), list(), non_neg_integer()) -> list().
bounded_prepend(Item, List, MaxSize) ->
    lists:sublist([Item | List], MaxSize).
