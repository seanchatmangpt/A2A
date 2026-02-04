%%% @doc Performance Metrics Collection
%%% Collects and manages performance metrics for Craftplan MCP + A2A

-module(performance_metrics).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([increment_counter/2, record_timing/3, record_gauge/3, record_histogram/3]).
-export([get_metrics/0, get_metric/2, reset_metrics/1]).
-export([start_metrics_collection/0, stop_metrics_collection/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(METRICS_INTERVAL, 1000). % 1 second collection interval
-define(HISTOGRAM_BUCKETS, [10, 50, 100, 200, 500, 1000, 2000, 5000]).

%% Metric types
-define(COUNTER, counter).
-define(GAUGE, gauge).
-define(HISTOGRAM, histogram).

-record(metric, {
    type :: counter | gauge | histogram,
    value :: number(),
    timestamp :: integer()
}).

-record(state, {
    metrics :: map(),  #{metric_name() => map()},
    histograms :: map(), #{metric_name() => [integer()]},
    counters :: map(), #{metric_name() => integer()},
    gauges :: map(), #{metric_name() => number()},
    collection_enabled :: boolean(),
    stats_timer :: reference() | undefined
}).

-type metric_name() :: binary().
-type metric_value() :: integer() | float().

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

%% @doc Increment a counter metric
-spec increment_counter(metric_name(), integer()) -> ok.
increment_counter(Name, Delta) ->
    gen_server:cast(?SERVER, {increment_counter, Name, Delta}).

%% @doc Record a timing metric (histogram)
-spec record_timing(metric_name(), integer(), map()) -> ok.
record_timing(Name, Duration, Tags) ->
    gen_server:cast(?SERVER, {record_timing, Name, Duration, Tags}).

%% @doc Record a gauge metric
-spec record_gauge(metric_name(), number(), map()) -> ok.
record_gauge(Name, Value, Tags) ->
    gen_server:cast(?SERVER, {record_gauge, Name, Value, Tags}).

%% @doc Record a histogram metric
-spec record_histogram(metric_name(), integer(), map()) -> ok.
record_histogram(Name, Value, Tags) ->
    gen_server:cast(?SERVER, {record_histogram, Name, Value, Tags}).

%% @doc Get all metrics
-spec get_metrics() -> map().
get_metrics() ->
    gen_server:call(?SERVER, get_metrics).

%% @doc Get a specific metric
-spec get_metric(metric_name(), map()) -> {ok, map()} | {error, not_found}.
get_metric(Name, Tags) ->
    gen_server:call(?SERVER, {get_metric, Name, Tags}).

%% @doc Reset specific metrics
-spec reset_metrics([metric_name()]) -> ok.
reset_metrics(Names) ->
    gen_server:call(?SERVER, {reset_metrics, Names}).

%% @doc Start automatic metrics collection
-spec start_metrics_collection() -> ok.
start_metrics_collection() ->
    gen_server:call(?SERVER, start_metrics_collection).

%% @doc Stop automatic metrics collection
-spec stop_metrics_collection() -> ok.
stop_metrics_collection() ->
    gen_server:call(?SERVER, stop_metrics_collection).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    State = #state{
        metrics = #{},
        histograms = #{},
        counters = #{},
        gauges = #{},
        collection_enabled = true,
        stats_timer = undefined
    },

    %% Start metrics collection timer
    {ok, State1} = handle_call(start_metrics_collection, undefined, State),

    %% Register system metrics collection
    start_system_metrics(),

    io:format("Performance Metrics Server started~n"),
    {ok, State1}.

handle_call(get_metrics, _From, State) ->
    Metrics = collect_metrics(State),
    {reply, Metrics, State};

handle_call({get_metric, Name, Tags}, _From, State) ->
    Key = metric_key(Name, Tags),
    case maps:get(Key, State#state.metrics, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Metric ->
            {reply, {ok, Metric}, State}
    end;

handle_call({reset_metrics, Names}, _From, State) ->
    NewCounters = reset_metrics_map(State#state.counters, Names),
    NewGauges = reset_metrics_map(State#state.gauges, Names),
    NewHistograms = reset_metrics_map(State#state.histograms, Names),

    NewState = State#state{
        counters = NewCounters,
        gauges = NewGauges,
        histograms = NewHistograms
    },

    {reply, ok, NewState};

handle_call(start_metrics_collection, _From, State) ->
    %% Start periodic metrics collection
    Timer = erlang:send_after(?METRICS_INTERVAL, self(), collect_stats),

    %% Collect initial stats
    collect_system_stats(),

    NewState = State#state{
        stats_timer = Timer,
        collection_enabled = true
    },

    {reply, ok, NewState};

handle_call(stop_metrics_collection, _From, State) ->
    case State#state.stats_timer of
        undefined ->
            {reply, ok, State};
        Timer ->
            erlang:cancel_timer(Timer),
            NewState = State#state{
                stats_timer = undefined,
                collection_enabled = false
            },
            {reply, ok, NewState}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast({increment_counter, Name, Delta}, State) ->
    Key = metric_key(Name, #{}),
    CurrentValue = maps:get(Key, State#state.counters, 0),
    NewCounters = maps:put(Key, CurrentValue + Delta, State#state.counters),

    %% Update metrics map
    NewMetrics = update_metric_map(State#state.metrics, Name, #{
        type => ?COUNTER,
        value => CurrentValue + Delta,
        timestamp => os:system_time(millisecond)
    }, #{}),

    NewState = State#state{
        counters = NewCounters,
        metrics = NewMetrics
    },

    %% Log high counter values
    case CurrentValue + Delta > 10000 of
        true ->
            error_logger:warning_msg("High counter value for ~s: ~p", [Name, CurrentValue + Delta]);
        false ->
            ok
    end,

    {noreply, NewState};

handle_cast({record_timing, Name, Duration, Tags}, State) ->
    Key = metric_key(Name, Tags),

    %% Update histogram
    Histogram = case maps:get(Key, State#state.histograms, []) of
        [] -> ?HISTOGRAM_BUCKETS;
        H -> H
    end,
    NewHistogram = update_histogram(Histogram, Duration),

    %% Update metrics map
    NewMetrics = update_metric_map(State#state.metrics, Name, #{
        type => ?HISTOGRAM,
        value => Duration,
        timestamp => os:system_time(millisecond),
        min => min_value(Histogram),
        max => max_value(Histogram),
        mean => calculate_mean(Histogram),
        p95 => calculate_percentile(Histogram, 95)
    }, Tags),

    NewState = State#state{
        histograms = maps:put(Key, NewHistogram, State#state.histograms),
        metrics = NewMetrics
    },

    {noreply, NewState};

handle_cast({record_gauge, Name, Value, Tags}, State) ->
    Key = metric_key(Name, Tags),

    %% Update gauges
    NewGauges = maps:put(Key, Value, State#state.gauges),

    %% Update metrics map
    NewMetrics = update_metric_map(State#state.metrics, Name, #{
        type => ?GAUGE,
        value => Value,
        timestamp => os:system_time(millisecond)
    }, Tags),

    %% Log extreme gauge values
    case abs(Value) > 1000 of
        true ->
            error_logger:warning_msg("Extreme gauge value for ~s: ~p", [Name, Value]);
        false ->
            ok
    end,

    NewState = State#state{
        gauges = NewGauges,
        metrics = NewMetrics
    },

    {noreply, NewState};

handle_cast({record_histogram, Name, Value, Tags}, State) ->
    Key = metric_key(Name, Tags),
    Histogram = case maps:get(Key, State#state.histograms, []) of
        [] -> ?HISTOGRAM_BUCKETS;
        H -> H
    end,
    NewHistogram = update_histogram(Histogram, Value),

    NewMetrics = update_metric_map(State#state.metrics, Name, #{
        type => ?HISTOGRAM,
        value => Value,
        timestamp => os:system_time(millisecond),
        count => length(NewHistogram),
        sum => lists:sum(NewHistogram)
    }, Tags),

    NewState = State#state{
        histograms = maps:put(Key, NewHistogram, State#state.histograms),
        metrics = NewMetrics
    },

    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(collect_stats, State) ->
    collect_system_stats(),

    %% Schedule next collection
    case State#state.collection_enabled of
        true ->
            Timer = erlang:send_after(?METRICS_INTERVAL, self(), collect_stats),
            {noreply, State#state{stats_timer = Timer}};
        false ->
            {noreply, State#state{stats_timer = undefined}}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    stop_system_metrics(),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

metric_key(Name, Tags) when is_binary(Name) ->
    case map_size(Tags) of
        0 -> Name;
        _ ->
            TagStr = lists:map(fun({K, V}) -> [K, $=, V] end, maps:to_list(Tags)),
            iolist_to_binary([Name, $[, TagStr])
    end.

metric_key(Name, Tags) when is_list(Name) ->
    metric_key(iolist_to_binary(Name), Tags).

update_metric_map(Metrics, Name, Metric, Tags) ->
    Key = metric_key(Name, Tags),
    maps:put(Key, Metric, Metrics).

reset_metrics_map(Map, Names) ->
    lists:foldl(fun(Name, Acc) ->
        maps:remove(metric_key(Name, #{}), Acc)
    end, Map, Names).

update_histogram(Histogram, Value) ->
    case update_histogram_bucket(Histogram, Value, []) of
        {Updated, _} -> Updated;
        Updated -> Updated
    end.

update_histogram_bucket([], Value, Acc) ->
    {[Value | Acc], 1};

update_histogram_bucket([Bucket | Rest], Value, Acc) when Value =< Bucket ->
    {[Bucket | Rest], 1};

update_histogram_bucket([Bucket | Rest], Value, Acc) ->
    update_histogram_bucket(Rest, Value, [Bucket | Acc]).

min_value([]) -> 0;
min_value([H | _]) -> H.

max_value([]) -> 0;
max_value(List) -> lists:max(List).

calculate_mean([]) -> 0;
calculate_mean(List) -> lists:sum(List) / length(List).

calculate_percentile(List, Percentile) ->
    Sorted = lists:sort(List),
    Length = length(Sorted),
    Index = trunc((Percentile / 100) * Length),
    case Index > 0 andalso Index =< Length of
        true -> lists:nth(Index, Sorted);
        false -> 0
    end.

collect_metrics(State) ->
    #{
        <<"counters">> => State#state.counters,
        <<"gauges">> => State#state.gauges,
        <<"histograms">> => State#state.histograms,
        <<"metrics">> => State#state.metrics,
        <<"collection_enabled">> => State#state.collection_enabled,
        <<"timestamp">> => os:system_time(millisecond)
    }.

%% System metrics collection
start_system_metrics() ->
    %% Start process metrics collection
    erlang:send_after(5000, self(), collect_process_metrics),
    ok.

stop_system_metrics() ->
    ok.

collect_system_stats() ->
    %% Collect system-wide metrics
    Memory = memory_usage(),
    Cpu = cpu_usage(),

    %% Record system metrics
    record_gauge(<<"system.memory.total">>, Memory#memory.total, #{}),
    record_gauge(<<"system.memory.processes">>, Memory#memory.processes, #{}),
    record_gauge(<<"system.memory.system">>, Memory#memory.system, #{}),
    record_gauge(<<"system.cpu.usage">>, Cpu, #{}),

    %% Collect process metrics
    collect_process_metrics().

memory_usage() ->
    {Total, Processes, System, _, _, _} = erlang:memory(),
    #memory{
        total = Total,
        processes = Processes,
        system = System
    }.

cpu_usage() ->
    %% Simple CPU usage calculation
    PrevCpu = get(prev_cpu_usage, 0),
    PrevTime = get(prev_cpu_time, os:system_time(millisecond)),

    CurrentCpu = process_info(self(), total_heap_size),
    CurrentTime = os:system_time(millisecond),

    case PrevCpu =/= 0 andalso PrevTime =/= 0 of
        true ->
            CpuDiff = CurrentCpu - PrevCpu,
            TimeDiff = CurrentTime - PrevTime,
            CpuUsage = (CpuDiff / TimeDiff) * 100,
            put(prev_cpu_usage, CurrentCpu),
            put(prev_cpu_time, CurrentTime),
            min(max(CpuUsage, 0), 100);
        false ->
            put(prev_cpu_usage, CurrentCpu),
            put(prev_cpu_time, CurrentTime),
            0
    end.

collect_process_metrics() ->
    %% Collect per-process metrics
    Processes = processes(),

    ActiveProcesses = length(lists:filter(fun(Pid) ->
        is_process_alive(Pid) andalso is_atom(element(1, process_info(Pid, current_function)))
    end, Processes)),

    record_gauge(<<"processes.count">>, length(Processes), #{}),
    record_gauge(<<"processes.active">>, ActiveProcesses, #{}),

    %% Schedule next collection
    erlang:send_after(10000, self(), collect_process_metrics).

-record(memory, {
    total :: integer(),
    processes :: integer(),
    system :: integer()
}).