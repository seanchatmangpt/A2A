%%% @doc Real-time Performance Dashboard
%%% WebSocket-based dashboard for monitoring performance metrics

-module(dashboard).
-behaviour(cowboy_websocket).

%% API
-export([start_link/0, stop/0]).
-export([init/2, websocket_init/1, handle/2, terminate/2]).

-define(SERVER, ?MODULE).
-define(HEARTBEAT_INTERVAL, 30000). % 30 seconds
-define(UPDATE_INTERVAL, 5000). % 5 seconds

-record(state, {
    pid :: pid(),
    heartbeat_timer :: reference() | undefined,
    update_timer :: reference() | undefined,
    metrics :: map()
}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    cowboy:start_clear(?SERVER,
        [{port, 9090}],
        #{
            env => #{dispatch => dispatch()},
            websocket => ?MODULE
        }
    ).

stop() ->
    cowboy:stop(?SERVER).

%%====================================================================
%% Cowboy Websocket Callbacks
%%====================================================================

init(Req, State) ->
    {cowboy_websocket, Req, State}.

websocket_init(State) ->
    io:format("WebSocket client connected to dashboard~n"),

    %% Get initial metrics
    Metrics = performance_metrics:get_metrics(),
    Dashboard = generate_dashboard_data(Metrics),

    %% Send initial data
    ok = send_message(Dashboard),

    %% Start update timers
    HeartbeatTimer = erlang:send_after(?HEARTBEAT_INTERVAL, self(), heartbeat),
    UpdateTimer = erlang:send_after(?UPDATE_INTERVAL, self(), update_metrics),

    NewState = State#state{
        metrics = Metrics,
        heartbeat_timer = HeartbeatTimer,
        update_timer = UpdateTimer
    },

    {ok, NewState}.

handle({text, Msg}, State) ->
    %% Handle incoming messages
    try
        Data = jiffy:decode(Msg, [return_maps]),
        Response = handle_client_message(Data),
        send_message(Response)
    catch
        _:_ ->
            send_error_message("Invalid message format")
    end,
    {ok, State};

handle({binary, Bin}, State) ->
    %% Handle binary data
    send_error_message("Binary data not supported"),
    {ok, State};

handle(close, State) ->
    io:format("WebSocket client disconnected~n"),
    {stop, State};

handle(_Frame, State) ->
    {ok, State}.

terminate(_Reason, State) ->
    %% Clean up timers
    case State#state.heartbeat_timer of
        undefined -> ok;
        Timer -> erlang:cancel_timer(Timer)
    end,
    case State#state.update_timer of
        undefined -> ok;
        Timer -> erlang:cancel_timer(Timer)
    end,

    ok.

%%====================================================================
%% Internal Functions
%%====================================================================

handle_client_message(Message) ->
    case maps:get(<<"type">>, Message, undefined) of
        <<"get_metrics">> ->
            Metrics = performance_metrics:get_metrics(),
            generate_dashboard_data(Metrics);
        <<"get_dashboard">> ->
            Dashboard = performance_monitor:get_dashboard_data(),
            Dashboard;
        <<"get_alerts">> ->
            Alerts = performance_monitor:get_alerts(),
            #{
                <<"type">> => <<"alerts_response">>,
                <<"alerts">> => Alerts
            };
        <<"get_time_series">> ->
            Metric = maps:get(<<"metric">>, Message),
            From = maps:get(<<"from">>, Message),
            To = maps:get(<<"to">>, Message),
            TimeSeries = performance_monitor:get_time_series(Metric, From, To),
            #{
                <<"type">> => <<"time_series_response">>,
                <<"metric">> => Metric,
                <<"data">> => TimeSeries
            };
        <<"get_system_stats">> ->
            SystemStats = get_system_stats(),
            #{
                <<"type">> => <<"system_stats">>,
                <<"data">> => SystemStats
            };
        _ ->
            #{
                <<"type">> => <<"error">>,
                <<"message">> => <<"Unknown message type">>
            }
    end.

generate_dashboard_data(Metrics) ->
    #{
        <<"type">> => <<"dashboard_update">>,
        <<"timestamp">> => os:system_time(millisecond),
        <<"metrics">> => extract_key_metrics(Metrics),
        <<"system">> => get_system_stats(),
        <<"performance">> => get_performance_data(Metrics),
        <<"alerts">> => get_active_alerts()
    }.

extract_key_metrics(Metrics) ->
    #{
        <<"mcp_requests">> => maps:get(<<"mcp.requests">>, Metrics#{"counters"}, 0),
        <<"a2a_tasks">> => maps:get(<<"a2a.tasks_submitted">>, Metrics#{"counters"}, 0),
        <<"api_calls">> => maps:get(<<"api.call_rate">>, Metrics#{"counters"}, 0),
        <<"mcp_errors">> => maps:get(<<"mcp.errors">>, Metrics#{"counters"}, 0),
        <<"a2a_errors">> => maps:get(()<<"a2a.tasks_failed">>, Metrics#{"counters"}, 0),
        <<"api_errors">> => maps:get(<<"api.api_error_rate">>, Metrics#{"counters"}, 0),
        <<"avg_response_time">> => calculate_avg_response_time(Metrics),
        <<"memory_usage">> => get_memory_usage(Metrics),
        <<"cpu_usage">> => get_cpu_usage(Metrics)
    }.

get_system_stats() ->
    {TotalMemory, ProcessesMemory, SystemMemory} = erlang:memory(),
    ProcessCount = length(processes()),
    PortCount = erlang:system_info(port_count),
    AtomCount = erlang:system_info(atom_count),

    #{
        <<"memory">> => #{
            <<"total">> => TotalMemory,
            <<"processes">> => ProcessesMemory,
            <<"system">> => SystemMemory
        },
        <<"processes">> => #{
            <<"total">> => ProcessCount,
            <<"ports">> => PortCount,
            <<"atoms">> => AtomCount
        },
        <<"uptime">> => os:system_time(millisecond) - get(start_time, os:system_time(millisecond))
    }.

get_performance_data(Metrics) ->
    %% Calculate performance metrics
    ResponseTimes = extract_response_times(Metrics),
    ErrorRates = extract_error_rates(Metrics),

    #{
        <<"throughput">> => calculate_throughput(Metrics),
        <<"response_times">> => #{
            <<"avg">> => lists:sum(ResponseTimes) / max(length(ResponseTimes), 1),
            <<"p95">> => calculate_percentile(ResponseTimes, 95),
            <<"p99">> => calculate_percentile(ResponseTimes, 99)
        },
        <<"error_rates">> => #{
            <<"mcp">> => maps:get(<<"mcp.error_rate">>, ErrorRates, 0),
            <<"a2a">> => maps:get(<<"a2a.task_error_rate">>, ErrorRates, 0),
            <<"api">> => maps:get(<<"api.api_error_rate">>, ErrorRates, 0)
        }
    }.

get_active_alerts() ->
    %% Get currently active alerts
    Alerts = performance_monitor:get_alerts(),
    lists:filter(fun(Alert) ->
        maps:get(<<"enabled">>, Alert, true) andalso
        maps:get(<<"last_triggered">>, Alert, 0) > 0
    end, Alerts).

get_memory_usage(Metrics) ->
    case maps:get(<<"system.memory.processes">>, Metrics#{"gauges"}, 0) of
        0 -> erlang:memory(processes);
        Value -> Value
    end.

get_cpu_usage(Metrics) ->
    case maps:get(<<"system.cpu.usage">>, Metrics#{"gauges"}, 0) of
        0 -> 0.0;
        Value -> Value
    end.

calculate_avg_response_time(Metrics) ->
    ResponseTimes = extract_response_times(Metrics),
    case ResponseTimes of
        [] -> 0;
        _ -> lists:sum(ResponseTimes) / length(ResponseTimes)
    end.

extract_response_times(Metrics) ->
    %% Extract response times from metrics
    ResponseTimeMetrics = [
        <<"mcp.tool_call">>,
        <<"mcp.get_tool_cache">>,
        <<"a2a.task_start">>,
        <<"api.response_time">>
    ],

    lists:foldl(fun(Metric, Acc) ->
        case performance_metrics:get_metric(Metric, #{}) of
            {ok, #{value := Value}} -> [Value | Acc];
            _ -> Acc
        end
    end, [], ResponseTimeMetrics).

extract_error_rates(Metrics) ->
    %% Extract error rates from metrics
    ErrorRateMetrics = [
        <<"mcp.error_rate">>,
        <<"a2a.task_error_rate">>,
        <<"api.api_error_rate">>
    ],

    lists:foldl(fun(Metric, Acc) ->
        case performance_metrics:get_metric(Metric, #{}) of
            {ok, #{value := Value}} -> Acc#{Metric => Value};
            _ -> Acc
        end
    end, #{}, ErrorRateMetrics).

calculate_throughput(Metrics) ->
    %% Calculate requests per second
    case maps:get(<<"mcp.requests">>, Metrics#{"counters"}, 0) of
        0 -> 0.0;
        TotalRequests ->
            Uptime = os:system_time(millisecond) - get(start_time, os:system_time(millisecond)),
            TotalRequests / max(Uptime / 1000, 1)
    end.

calculate_percentile(List, Percentile) ->
    Sorted = lists:sort(List),
    Length = length(Sorted),
    Index = trunc((Percentile / 100) * Length),

    case Index > 0 andalso Index =< Length of
        true -> lists:nth(Index, Sorted);
        false -> 0
    end.

send_message(Message) ->
    %% Send message to WebSocket client
    Data = jiffy:encode(Message),
    cowboy:websocket_reply({text, Data}, #{}).

send_error_message(Message) ->
    Error = #{
        <<"type">> => <<"error">>,
        <<"message">> => Message,
        <<"timestamp">> => os:system_time(millisecond)
    },
    send_message(Error).

handle_message(heartbeat, State) ->
    %% Send heartbeat message
    Heartbeat = #{
        <<"type">> => <<"heartbeat">>,
        <<"timestamp">> => os:system_time(millisecond)
    },
    send_message(Heartbeat),

    %% Schedule next heartbeat
    NewTimer = erlang:send_after(?HEARTBEAT_INTERVAL, self(), heartbeat),

    {noreply, State#state{heartbeat_timer = NewTimer}};

handle_message(update_metrics, State) ->
    %% Update and send metrics
    Metrics = performance_metrics:get_metrics(),
    Dashboard = generate_dashboard_data(Metrics),

    send_message(Dashboard),

    %% Schedule next update
    NewTimer = erlang:send_after(?UPDATE_INTERVAL, self(), update_metrics),

    {noreply, State#state{metrics = Metrics, update_timer = NewTimer}}.

dispatch() ->
    cowboy_router:compile([
        {'_', [
            {"/ws", ?MODULE, []}
        ]}
    ]).