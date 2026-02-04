%%% @doc Performance Monitoring System
%%% Real-time performance monitoring with dashboards and alerts

-module(performance_monitor).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([register_alert/3, unregister_alert/2, check_alerts/0]).
-export([get_dashboard_data/0, get_time_series/3, get_alerts/0]).
-export([start_health_check/0, set_health_threshold/4]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(ALERT_CHECK_INTERVAL, 10000). % 10 seconds
-define(DASHBOARD_DATA_POINTS, 60). % Keep 60 data points (1 hour at 1m intervals)
-define(HEALTH_CHECK_INTERVAL, 30000). % 30 seconds

%% Alert types
-define(THRESHOLD_ALERT, threshold).
-define(TREND_ALERT, trend).
-define(ANOMALY_ALERT, anomaly).

-record(alert, {
    id :: binary(),
    name :: binary(),
    metric :: binary(),
    type :: threshold | trend | anomaly,
    condition :: map(),
    enabled :: boolean(),
    last_triggered :: integer() | undefined,
    trigger_count :: integer()
}).

-record(threshold_alert, {
    operator :: '==' | '!=' | '>' | '>=' | '<' | '<=',
    value :: number(),
    duration :: integer() % milliseconds
}).

-record(trend_alert, {
    change_percentage :: float(),
    duration :: integer() % milliseconds
}).

-record(anomaly_alert, {
    z_score_threshold :: float(),
    window_size :: integer()
}).

-record(state, {
    alerts :: map(), #{binary() => #alert{}},
    alert_timers :: map(), #{binary() => reference()},
    dashboard_data :: map(), #{binary() => list()},
    health_thresholds :: map(),
    health_checks :: map(),
    collection_enabled :: boolean()
}).

-type alert_id() :: binary().
-type metric_name() :: binary().

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

%% @doc Register a new alert
-spec register_alert(binary(), binary(), map()) -> {ok, alert_id()} | {error, term()}.
register_alert(Name, Metric, Config) ->
    gen_server:call(?SERVER, {register_alert, Name, Metric, Config}).

%% @doc Unregister an alert
-spec unregister_alert(binary(), binary()) -> ok.
unregister_alert(Name, Metric) ->
    gen_server:call(?SERVER, {unregister_alert, Name, Metric}).

%% @doc Check all alerts manually
-spec check_alerts() -> ok.
check_alerts() ->
    gen_server:cast(?SERVER, check_alerts).

%% @doc Get dashboard data
-spec get_dashboard_data() -> map().
get_dashboard_data() ->
    gen_server:call(?SERVER, get_dashboard_data).

%% @doc Get time series data for a metric
-spec get_time_series(metric_name(), integer(), integer()) -> list().
get_time_series(Metric, From, To) ->
    gen_server:call(?SERVER, {get_time_series, Metric, From, To}).

%% @doc Get all alerts
-spec get_alerts() -> list(map()).
get_alerts() ->
    gen_server:call(?SERVER, get_alerts).

%% @doc Start health check system
-spec start_health_check() -> ok.
start_health_check() ->
    gen_server:call(?SERVER, start_health_check).

%% @doc Set health threshold
-spec set_health_threshold(binary(), binary(), number(), integer()) -> ok.
set_health_threshold(Category, Metric, Threshold, Duration) ->
    gen_server:call(?SERVER, {set_health_threshold, Category, Metric, Threshold, Duration}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    State = #state{
        alerts = #{},
        alert_timers = #{},
        dashboard_data = #{},
        health_thresholds = #{
            <<"mcp">> => #{
                <<"request_rate">> => #{threshold => 5000, duration => 60000},
                <<"error_rate">> => #{threshold => 0.05, duration => 300000},
                <<"avg_response_time">> => #{threshold => 200, duration => 300000}
            },
            <<"a2a">> => #{
                <<"task_rate">> => #{threshold => 1000, duration => 60000},
                <<"task_error_rate">> => #{threshold => 0.02, duration => 300000},
                <<"avg_task_time">> => #{threshold => 1000, duration => 300000}
            },
            <<"api">> => #{
                <<"call_rate">> => #{threshold => 10000, duration => 60000},
                <<"api_error_rate">> => #{threshold => 0.01, duration => 300000},
                <<"avg_api_time">> => #{threshold => 500, duration => 300000}
            }
        },
        health_checks = #{},
        collection_enabled = true
    },

    %% Start alert checking
    {ok, State1} = handle_call(start_alert_checking, undefined, State),
    {ok, State2} = handle_call(start_health_check, undefined, State1),

    %% Initialize dashboard data
    initialize_dashboard_data(),

    io:format("Performance Monitor started~n"),
    {ok, State2}.

handle_call({register_alert, Name, Metric, Config}, _From, State) ->
    AlertId = generate_alert_id(Name, Metric),
    Alert = parse_alert_config(AlertId, Name, Metric, Config),

    case Alert of
        {ok, ParsedAlert} ->
            %% Schedule alert checking
            {ok, NewState} = schedule_alert_check(ParsedAlert, State),

            %% Add to alerts map
            NewAlerts = maps:put(AlertId, ParsedAlert, State#state.alerts),

            io:format("Registered alert: ~s for metric ~s~n", [Name, Metric]),
            {reply, {ok, AlertId}, State#state{alerts = NewAlerts}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({unregister_alert, Name, Metric}, _From, State) ->
    AlertId = generate_alert_id(Name, Metric),

    case maps:get(AlertId, State#state.alerts, undefined) of
        undefined ->
            {reply, ok, State};
        Alert ->
            %% Cancel alert timer
            case maps:get(AlertId, State#state.alert_timers, undefined) of
                undefined -> ok;
                Timer -> erlang:cancel_timer(Timer)
            end,

            %% Remove from maps
            NewAlerts = maps:remove(AlertId, State#state.alerts),
            NewTimers = maps:remove(AlertId, State#state.alert_timers),

            io:format("Unregistered alert: ~s~n", [Name]),
            {reply, ok, State#state{alerts = NewAlerts, alert_timers = NewTimers}}
    end;

handle_call(get_dashboard_data, _From, State) ->
    DashboardData = collect_dashboard_data(State),
    {reply, DashboardData, State};

handle_call({get_time_series, Metric, From, To}, _From, State) ->
    TimeSeries = get_time_series_data(Metric, From, To, State#state.dashboard_data),
    {reply, TimeSeries, State};

handle_call(get_alerts, _From, State) ->
    AlertList = maps:values(State#state.alerts),
    FormattedAlerts = [format_alert(Alert) || Alert <- AlertList],
    {reply, FormattedAlerts, State};

handle_call(start_alert_checking, _From, State) ->
    %% Start periodic alert checking
    Timer = erlang:send_after(?ALERT_CHECK_INTERVAL, self(), check_alerts),

    NewState = State#state{
        alert_timers = maps:put(alert_check_timer, Timer, State#state.alert_timers)
    },

    {reply, ok, NewState};

handle_call(start_health_check, _From, State) ->
    %% Start periodic health checks
    Timer = erlang:send_after(?HEALTH_CHECK_INTERVAL, self(), run_health_check),

    NewState = State#state{
        health_checks = maps:put(health_check_timer, Timer, State#state.health_checks)
    },

    {reply, ok, NewState};

handle_call({set_health_threshold, Category, Metric, Threshold, Duration}, _From, State) ->
    NewThresholds = case maps:get(Category, State#state.health_thresholds, undefined) of
        undefined -> #{};
        CatThresholds ->
            maps:put(Metric, #{threshold => Threshold, duration => Duration}, CatThresholds)
    end,

    ThresholdMap = maps:put(Category, NewThresholds, State#state.health_thresholds),

    io:format("Set health threshold: ~s.~s = ~p for ~pms~n", [Category, Metric, Threshold, Duration]),
    {reply, ok, State#state{health_thresholds = ThresholdMap}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(check_alerts, State) ->
    %% Check all alerts
    check_all_alerts(State),

    %% Schedule next check
    Timer = erlang:send_after(?ALERT_CHECK_INTERVAL, self(), check_alerts),
    NewTimers = maps:put(alert_check_timer, Timer, State#state.alert_timers),

    {noreply, State#state{alert_timers = NewTimers}};

handle_cast(update_dashboard, State) ->
    %% Update dashboard data
    UpdatedData = update_dashboard_metrics(State#state.dashboard_data),
    {noreply, State#state{dashboard_data = UpdatedData}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(run_health_check, State) ->
    run_health_checks(State),

    %% Schedule next check
    Timer = erlang:send_after(?HEALTH_CHECK_INTERVAL, self(), run_health_check),
    NewChecks = maps:put(health_check_timer, Timer, State#state.health_checks),

    {noreply, State#state{health_checks = NewChecks}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

generate_alert_id(Name, Metric) ->
    Timestamp = os:system_time(millisecond),
    iolist_to_binary(io_lib:format("alert_~s_~s_~p", [Name, Metric, Timestamp])).

parse_alert_config(AlertId, Name, Metric, Config) ->
    Type = maps:get(type, Config, ?THRESHOLD_ALERT),

    case Type of
        ?THRESHOLD_ALERT ->
            Operator = maps:get(operator, Config, '>'),
            Value = maps:get(value, Config, 0),
            Duration = maps:get(duration, Config, 60000),
            Threshold = #threshold_alert{
                operator = Operator,
                value = Value,
                duration = Duration
            },
            {ok, #alert{
                id = AlertId,
                name = Name,
                metric = Metric,
                type = Type,
                condition = Threshold,
                enabled = maps:get(enabled, Config, true),
                last_triggered = undefined,
                trigger_count = 0
            }};
        ?TREND_ALERT ->
            ChangePercentage = maps:get(change_percentage, Config, 0.5),
            Duration = maps:get(duration, Config, 300000),
            Trend = #trend_alert{
                change_percentage = ChangePercentage,
                duration = Duration
            },
            {ok, #alert{
                id = AlertId,
                name = Name,
                metric = Metric,
                type = Type,
                condition = Trend,
                enabled = maps:get(enabled, Config, true),
                last_triggered = undefined,
                trigger_count = 0
            }};
        ?ANOMALY_ALERT ->
            ZScoreThreshold = maps:get(z_score_threshold, Config, 3.0),
            WindowSize = maps:get(window_size, Config, 10),
            Anomaly = #anomaly_alert{
                z_score_threshold = ZScoreThreshold,
                window_size = WindowSize
            },
            {ok, #alert{
                id = AlertId,
                name = Name,
                metric = Metric,
                type = Type,
                condition = Anomaly,
                enabled = maps:get(enabled, Config, true),
                last_triggered = undefined,
                trigger_count = 0
            }};
        _ ->
            {error, unknown_alert_type}
    end.

schedule_alert_check(Alert, State) ->
    %% Check alert immediately
    check_alert(Alert, State),

    %% Schedule periodic checking
    %% This is simplified - in production, would use dynamic timers based on alert duration
    ok.

check_all_alerts(State) ->
    Now = os:system_time(millisecond),
    lists:foreach(fun(Alert) ->
        case Alert#alert.enabled of
            true ->
                check_alert(Alert, State);
            false ->
                ok
        end
    end, maps:values(State#state.alerts)).

check_alert(Alert, State) ->
    AlertId = Alert#alert.id,
    Metric = Alert#alert.metric,
    MetricType = Alert#alert.type,

    case MetricType of
        ?THRESHOLD_ALERT ->
            check_threshold_alert(Alert, State);
        ?TREND_ALERT ->
            check_trend_alert(Alert, State);
        ?ANOMALY_ALERT ->
            check_anomaly_alert(Alert, State)
    end.

check_threshold_alert(Alert, _State) ->
    #alert{
        id = AlertId,
        name = Name,
        metric = Metric,
        condition = Threshold
    } = Alert,

    %% Get current metric value
    case performance_metrics:get_metric(Metric, #{}) of
        {ok, #{value := Value}} ->
            #threshold_alert{operator = Op, value = ThresholdValue} = Threshold,

            ConditionMet = case Op of
                '>' -> Value > ThresholdValue;
                '>=' -> Value >= ThresholdValue;
                '<' -> Value < ThresholdValue;
                '<=' -> Value =< ThresholdValue;
                '==' -> Value == ThresholdValue;
                '!=' -> Value /= ThresholdValue
            end,

            if
                ConditionMet ->
                    trigger_alert(Alert, <<"Threshold exceeded: current value ~p exceeds threshold ~p", [Value, ThresholdValue]>>);
                true ->
                    ok
            end;
        {error, not_found} ->
            ok
    end.

check_trend_alert(Alert, State) ->
    #alert{
        id = AlertId,
        metric = Metric,
        condition = Trend
    } = Alert,

    #trend_alert{
        change_percentage = ChangePct,
        duration = Duration
    } = Trend,

    %% Get time series data
    Now = os:system_time(millisecond),
    Then = Now - Duration,
    TimeSeries = get_time_series_data(Metric, Then, Now, State#state.dashboard_data),

    case length(TimeSeries) >= 2 of
        true ->
            FirstValue = proplists:get_value(then, TimeSeries),
            LastValue = proplists:get_value(now, TimeSeries),

            Change = (LastValue - FirstValue) / FirstValue,

            if
                abs(Change) > ChangePct ->
                    trigger_alert(Alert, <<"Significant trend detected: ~p% change over ~pms", [Change * 100, Duration]>>);
                true ->
                    ok
            end;
        false ->
            ok
    end.

check_anomaly_alert(Alert, State) ->
    #alert{
        id = AlertId,
        metric = Metric,
        condition = Anomaly
    } = Alert,

    #anomaly_alert{
        z_score_threshold = ZThreshold,
        window_size = WindowSize
    } = Anomaly,

    %% Get recent values
    Now = os:system_time(millisecond),
    Then = Now - (WindowSize * 1000), % Assuming 1s intervals
    TimeSeries = get_time_series_data(Metric, Then, Now, State#state.dashboard_data),

    case length(TimeSeries) >= WindowSize of
        true ->
            Values = [V || {_, V} <- TimeSeries],
            Mean = lists:sum(Values) / length(Values),
            StdDev = math:sqrt(lists:sum([math:pow(V - Mean, 2) || V <- Values]) / length(Values)),

            case StdDev > 0 of
                true ->
                    LastValue = lists:last(Values),
                    ZScore = abs(LastValue - Mean) / StdDev,

                    if
                        ZScore > ZThreshold ->
                            trigger_alert(Alert, <<"Anomaly detected: Z-score ~p exceeds threshold ~p", [ZScore, ZThreshold]>>);
                        true ->
                            ok
                    end;
                false ->
                    ok
            end;
        false ->
            ok
    end.

trigger_alert(Alert, Message) ->
    #alert{
        id = AlertId,
        name = Name,
        metric = Metric,
        last_triggered = LastTriggered,
        trigger_count = TriggerCount
    } = Alert,

    Now = os:system_time(millisecond),

    %% Check if alert is already triggered (prevent spam)
    case LastTriggered of
        undefined ->
            %% New alert
            send_alert_notification(Name, Metric, Message);
        LastTriggered when Now - LastTriggered > 60000 -> % 1 minute cooldown
            send_alert_notification(Name, Metric, Message);
        _ ->
            ok
    end,

    %% Update alert state
    put(alert_state, AlertId, Alert#alert{
        last_triggered = Now,
        trigger_count = TriggerCount + 1
    }),

    error_logger:warning_msg("ALERT: ~s - ~s~n", [Name, Message]).

send_alert_notification(Name, Metric, Message) ->
    %% Send alert to monitoring system
    Alert = #{
        <<"name">> => Name,
        <<"metric">> => Metric,
        <<"message">> => Message,
        <<"timestamp">> => os:system_time(millisecond),
        <<"severity">> => <<"warning">>
    },

    %% Could integrate with external monitoring system here
    io:format("ALERT NOTIFICATION: ~p~n", [Alert]).

initialize_dashboard_data() ->
    %% Initialize dashboard data structures
    DashboardMetrics = [
        <<"mcp.request_rate">>,
        <<"mcp.error_rate">>,
        <<"mcp.avg_response_time">>,
        <<"a2a.task_rate">>,
        <<"a2a.task_error_rate">>,
        <<"a2a.avg_task_time">>,
        <<"api.call_rate">>,
        <<"api.api_error_rate">>,
        <<"api.avg_api_time">>
    ],

    lists:foreach(fun(Metric) ->
        performance_metrics:start_metrics_collection()
    end, DashboardMetrics).

collect_dashboard_data(State) ->
    Dashboard = #{},
    Now = os:system_time(millisecond),

    %% Get key metrics for dashboard
    Dashboard = get_dashboard_metric(Dashboard, <<"mcp.request_rate">>, State),
    Dashboard = get_dashboard_metric(Dashboard, <<"mcp.error_rate">>, State),
    Dashboard = get_dashboard_metric(Dashboard, <<"mcp.avg_response_time">>, State),
    Dashboard = get_dashboard_metric(Dashboard, <<"a2a.task_rate">>, State),
    Dashboard = get_dashboard_metric(Dashboard, <<"a2a.task_error_rate">>, State),
    Dashboard = get_dashboard_metric(Dashboard, <<"a2a.avg_task_time">>, State),

    Dashboard#{
        <<"timestamp">> => Now,
        <<"uptime">> => os:system_time(millisecond) - get(start_time, os:system_time(millisecond))
    }.

get_dashboard_metric(Dashboard, Metric, State) ->
    case performance_metrics:get_metric(Metric, #{}) of
        {ok, Value} ->
            Dashboard#{Metric => Value};
        {error, not_found} ->
            Dashboard#{Metric => 0}
    end.

get_time_series_data(Metric, From, To, DashboardData) ->
    %% Simplified implementation - in production would use proper time series storage
    Data = maps:get(Metric, DashboardData, []),
    Filtered = lists:filter(fun({Timestamp, _}) -> Timestamp >= From andalso Timestamp =< To end, Data),
    Filtered.

update_dashboard_metrics(DashboardData) ->
    %% Update dashboard metrics with current values
    Now = os:system_time(millisecond),

    %% Get and store current metrics
    Metrics = [
        {<<"mcp.request_rate">>, <<"counter">>},
        {<<"mcp.error_rate">>, <<"gauge">>},
        {<<"mcp.avg_response_time">>, <<"histogram">>},
        {<<"a2a.task_rate">>, <<"counter">>},
        {<<"a2a.task_error_rate">>, <<"gauge">>},
        {<<"a2a.avg_task_time">>, <<"histogram">>}
    ],

    lists:foldl(fun({Metric, Type}, Acc) ->
        case performance_metrics:get_metric(Metric, #{}) of
            {ok, #{value := Value}} ->
                Data = maps:get(Metric, Acc, []),
                NewData = keep_recent_data([{Now, Value} | Data], ?DASHBOARD_DATA_POINTS),
                maps:put(Metric, NewData, Acc);
            {error, not_found} ->
                Acc
        end
    end, DashboardData, Metrics).

keep_recent_data(Data, MaxPoints) ->
    lists:nthtail(length(Data) - MaxPoints, Data).

format_alert(Alert) ->
    #alert{
        id = AlertId,
        name = Name,
        metric = Metric,
        type = Type,
        enabled = Enabled,
        last_triggered = LastTriggered,
        trigger_count = TriggerCount
    } = Alert,

    #{
        <<"id">> => AlertId,
        <<"name">> => Name,
        <<"metric">> => Metric,
        <<"type">> => atom_to_binary(Type),
        <<"enabled">> => Enabled,
        <<"last_triggered">> => LastTriggered,
        <<"trigger_count">> => TriggerCount
    }.

run_health_checks(State) ->
    Now = os:system_time(millisecond),

    CheckThresholds = fun(Category, Metrics) ->
        case maps:get(Category, State#state.health_thresholds, undefined) of
            undefined -> ok;
            Thresholds ->
                check_category_thresholds(Category, Thresholds, Now)
        end
    end,

    maps:foreach(CheckThresholds, State#state.health_thresholds).

check_category_thresholds(Category, Thresholds, Now) ->
    CheckMetric = fun(Metric, Config) ->
        Threshold = maps:get(threshold, Config),
        Duration = maps:get(duration, Config),

        MetricKey = iolist_to_binary([Category, $., Metric]),

        case performance_metrics:get_metric(MetricKey, #{}) of
            {ok, #{value := Value}} ->
                case Category of
                    <<"mcp">> when Metric == <<"error_rate">> ->
                        if
                            Value > Threshold ->
                                trigger_health_alert(Category, Metric, Value, Threshold);
                            true ->
                                ok
                        end;
                    <<"a2a">> when Metric == <<"task_error_rate">> ->
                        if
                            Value > Threshold ->
                                trigger_health_alert(Category, Metric, Value, Threshold);
                            true ->
                                ok
                        end;
                    <<"api">> when Metric == <<"api_error_rate">> ->
                        if
                            Value > Threshold ->
                                trigger_health_alert(Category, Metric, Value, Threshold);
                            true ->
                                ok
                        end;
                    _ ->
                        if
                            Value > Threshold ->
                                trigger_health_alert(Category, Metric, Value, Threshold);
                            true ->
                                ok
                        end
                end;
            {error, not_found} ->
                ok
        end
    end,

    maps:foreach(CheckMetric, Thresholds).

trigger_health_alert(Category, Metric, Value, Threshold) ->
    AlertName = iolist_to_binary([Category, "_", Metric, "_alert"]),
    Message = iolist_to_binary([
        "Health threshold exceeded: ",
        Category, ".", Metric, " = ", Value,
        " exceeds threshold ", Threshold
    ]),

    trigger_alert(#alert{
        id = generate_alert_id(AlertName, Metric),
        name = AlertName,
        metric = Metric,
        type = ?THRESHOLD_ALERT,
        condition = #threshold_alert{operator = '>', value = Threshold},
        enabled = true,
        last_triggered = undefined,
        trigger_count = 0
    }, Message).