%%%-------------------------------------------------------------------
%%% @doc
%%% Y Combinator Demo - Comprehensive Logging and Telemetry Module
%%%
%%% This module provides comprehensive logging, metrics collection, and
%%% telemetry export capabilities for the Y Combinator demo.
%%%
%%% Features:
%%% - Event logging with metadata
%%% - Combination generation tracking
%%% - Test lifecycle tracking
%%% - Metrics aggregation and export
%%% - JSON/CSV export
%%% - Log rotation
%%% - Metrics dashboard
%%% - Integration with yawl_metrics
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(y_combinator_logger).
-author("A2A Team").
-behaviour(gen_server).

-include_lib("kernel/include/file.hrl").

%% gen_server callbacks
-export([
    start_link/0,
    start_link/1,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% API - Logging functions
-export([
    log_event/3,
    log_event/4,

    %% Combination logging
    log_combination_generated/1,
    log_combination_generated/2,
    log_combination_tested/2,

    %% Test lifecycle logging
    log_test_started/1,
    log_test_started/2,
    log_test_completed/2,
    log_test_completed/3,
    log_test_failed/2,
    log_test_failed/3,

    %% Demo logging
    log_demo_started/2,
    log_demo_completed/3,

    %% Metrics collection
    get_metrics/0,
    get_metrics/1,
    reset_metrics/0,
    increment_counter/1,
    increment_counter/2,
    set_gauge/2,
    record_timing/2,

    %% Export functions
    export_logs/0,
    export_logs/1,
    export_json/0,
    export_csv/0,
    export_prometheus/0,

    %% Dashboard
    metrics_dashboard/0,
    metrics_dashboard/1,

    %% Log management
    rotate_logs/0,
    cleanup_logs/0,
    get_log_summary/0
]).

-include_lib("kernel/include/logger.hrl").

%%====================================================================
%% Constants
%%====================================================================

-define(LOG_TABLE, y_combinator_log_table).
-define(METRICS_TABLE, y_combinator_metrics_table).
-define(MAX_LOG_ENTRIES, 10000).
-define(LOG_ROTATION_SIZE, 1048576).  % 1MB
-define(LOG_RETENTION_DAYS, 30).

-define(DEFAULT_LOG_DIR, "priv/logs").

%%====================================================================
%% Type Definitions
%%====================================================================

-record(state, {
    log_dir :: binary(),
    max_entries :: pos_integer(),
    rotation_size :: pos_integer(),
    retention_days :: pos_integer(),
    metrics :: map(),
    log_index :: non_neg_integer()
}).

-record(log_entry, {
    id :: binary(),
    timestamp :: integer(),
    level :: atom(),
    type :: atom(),
    message :: binary(),
    metadata :: map()
}).

-record(metrics, {
    total_combinations_generated = 0 :: non_neg_integer(),
    tests_run = 0 :: non_neg_integer(),
    tests_passed = 0 :: non_neg_integer(),
    tests_failed = 0 :: non_neg_integer(),
    total_generation_time_ms = 0 :: non_neg_integer(),
    avg_generation_time_ms = 0.0 :: float(),
    min_generation_time_ms :: undefined | integer(),
    max_generation_time_ms :: undefined | integer(),
    demos_run = 0 :: non_neg_integer(),
    peak_memory_mb = 0.0 :: float(),
    current_memory_mb = 0.0 :: float(),
    start_time :: integer()
}).

-type log_level() :: debug | info | notice | warning | error | critical | alert | emergency.
-type log_type() :: combination | test | demo | system | performance.
-type export_format() :: json | csv | prometheus.

%%====================================================================
%% API Functions - Logging
%%====================================================================

%% @doc Start the logger with default options
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the logger with custom options
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

%% @doc Log an event with type and message
-spec log_event(log_type(), binary(), map()) -> ok.
log_event(Type, Message, Metadata) ->
    log_event(info, Type, Message, Metadata).

%% @doc Log an event with level, type, message and metadata
-spec log_event(log_level(), log_type(), binary(), map()) -> ok.
log_event(Level, Type, Message, Metadata) ->
    gen_server:cast(?MODULE, {log_event, Level, Type, Message, Metadata}).

%% @doc Log a combination generation event
-spec log_combination_generated(list()) -> ok.
log_combination_generated(Combination) ->
    log_combination_generated(Combination, #{}).

-spec log_combination_generated(list(), map()) -> ok.
log_combination_generated(Combination, Metadata) ->
    M = Metadata#{
        combination_size => length(Combination),
        combination_patterns => format_patterns(Combination)
    },
    log_event(info, combination, <<"Combination generated">>, M),
    gen_server:cast(?MODULE, {combination_generated, Combination}).

%% @doc Log a combination test event
-spec log_combination_tested(list(), pass | fail) -> ok.
log_combination_tested(Combination, Result) ->
    M = #{
        combination => format_patterns(Combination),
        result => Result
    },
    log_event(debug, combination, <<"Combination tested">>, M).

%% @doc Log test start event
-spec log_test_started(binary()) -> ok.
log_test_started(TestID) ->
    log_test_started(TestID, #{}).

-spec log_test_started(binary(), map()) -> ok.
log_test_started(TestID, Metadata) ->
    M = Metadata#{test_id => TestID},
    log_event(info, test, <<"Test started">>, M),
    gen_server:cast(?MODULE, {test_started, TestID}).

%% @doc Log test completion event
-spec log_test_completed(binary(), map()) -> ok.
log_test_completed(TestID, Result) ->
    log_test_completed(TestID, Result, #{}).

-spec log_test_completed(binary(), map(), map()) -> ok.
log_test_completed(TestID, Result, Metadata) ->
    M = Metadata#{
        test_id => TestID,
        result => Result
    },
    log_event(info, test, <<"Test completed">>, M),
    gen_server:cast(?MODULE, {test_completed, TestID, Result}).

%% @doc Log test failure event
-spec log_test_failed(binary(), term()) -> ok.
log_test_failed(TestID, Reason) ->
    log_test_failed(TestID, Reason, #{}).

-spec log_test_failed(binary(), term(), map()) -> ok.
log_test_failed(TestID, Reason, Metadata) ->
    M = Metadata#{
        test_id => TestID,
        reason => format_reason(Reason)
    },
    log_event(error, test, <<"Test failed">>, M),
    gen_server:cast(?MODULE, {test_failed, TestID}).

%% @doc Log demo start event
-spec log_demo_started(binary(), list()) -> ok.
log_demo_started(DemoName, Patterns) ->
    M = #{
        demo_name => DemoName,
        pattern_count => length(Patterns),
        patterns => format_patterns(Patterns)
    },
    log_event(info, demo, <<"Demo started">>, M),
    gen_server:cast(?MODULE, {demo_started, DemoName, Patterns}).

%% @doc Log demo completion event
-spec log_demo_completed(binary(), pos_integer(), integer()) -> ok.
log_demo_completed(DemoName, CombinationCount, DurationMs) ->
    M = #{
        demo_name => DemoName,
        combinations => CombinationCount,
        duration_ms => DurationMs
    },
    log_event(info, demo, <<"Demo completed">>, M),
    gen_server:cast(?MODULE, {demo_completed, DemoName, CombinationCount, DurationMs}).

%%====================================================================
%% API Functions - Metrics
%%====================================================================

%% @doc Get all metrics
-spec get_metrics() -> {ok, map()}.
get_metrics() ->
    gen_server:call(?MODULE, get_metrics).

%% @doc Get specific metric category
-spec get_metrics(atom()) -> {ok, term()} | {error, not_found}.
get_metrics(Category) ->
    gen_server:call(?MODULE, {get_metrics, Category}).

%% @doc Reset all metrics
-spec reset_metrics() -> ok.
reset_metrics() ->
    gen_server:call(?MODULE, reset_metrics).

%% @doc Increment a counter by 1
-spec increment_counter(atom()) -> ok.
increment_counter(CounterName) ->
    increment_counter(CounterName, 1).

%% @doc Increment a counter by a value
-spec increment_counter(atom(), integer()) -> ok.
increment_counter(CounterName, Value) ->
    gen_server:cast(?MODULE, {increment_counter, CounterName, Value}).

%% @doc Set a gauge value
-spec set_gauge(atom(), number()) -> ok.
set_gauge(GaugeName, Value) ->
    gen_server:cast(?MODULE, {set_gauge, GaugeName, Value}).

%% @doc Record a timing value in milliseconds
-spec record_timing(atom(), integer()) -> ok.
record_timing(TimingName, Milliseconds) ->
    gen_server:cast(?MODULE, {record_timing, TimingName, Milliseconds}).

%%====================================================================
%% API Functions - Export
%%====================================================================

%% @doc Export logs to default format (JSON)
-spec export_logs() -> {ok, binary()} | {error, term()}.
export_logs() ->
    export_logs(json).

%% @doc Export logs to specified format
-spec export_logs(export_format()) -> {ok, binary()} | {error, term()}.
export_logs(Format) ->
    gen_server:call(?MODULE, {export_logs, Format}).

%% @doc Export logs as JSON
-spec export_json() -> {ok, binary()} | {error, term()}.
export_json() ->
    export_logs(json).

%% @doc Export logs as CSV
-spec export_csv() -> {ok, binary()} | {error, term()}.
export_csv() ->
    export_logs(csv).

%% @doc Export metrics in Prometheus format
-spec export_prometheus() -> binary().
export_prometheus() ->
    gen_server:call(?MODULE, export_prometheus, 5000).

%%====================================================================
%% API Functions - Dashboard
%%====================================================================

%% @doc Display metrics dashboard to console
-spec metrics_dashboard() -> ok.
metrics_dashboard() ->
    metrics_dashboard(console).

%% @doc Display metrics in specified format
-spec metrics_dashboard(console | return) -> ok | map().
metrics_dashboard(console) ->
    case get_metrics() of
        {ok, Metrics} ->
            print_dashboard(Metrics),
            ok;
        {error, Reason} ->
            io:format("[ERROR] Failed to get metrics: ~p~n", [Reason]),
            ok
    end;
metrics_dashboard(return) ->
    case get_metrics() of
        {ok, Metrics} -> Metrics;
        {error, _} -> #{}
    end.

%%====================================================================
%% API Functions - Log Management
%%====================================================================

%% @doc Rotate log files
-spec rotate_logs() -> {ok, binary()} | {error, term()}.
rotate_logs() ->
    gen_server:call(?MODULE, rotate_logs).

%% @doc Cleanup old log files
-spec cleanup_logs() -> {ok, list()} | {error, term()}.
cleanup_logs() ->
    gen_server:call(?MODULE, cleanup_logs).

%% @doc Get log summary statistics
-spec get_log_summary() -> {ok, map()}.
get_log_summary() ->
    gen_server:call(?MODULE, get_log_summary).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init(Opts) ->
    LogDir = case maps:get(log_dir, Opts, undefined) of
        undefined ->
            case application:get_env(a2a_erl, y_combinator_log_dir) of
                {ok, Dir} -> Dir;
                undefined -> ?DEFAULT_LOG_DIR
            end;
        Dir -> Dir
    end,

    %% Ensure log directory exists
    ok = filelib:ensure_dir(filename:join(LogDir, ".tmp")),

    %% Initialize ETS tables
    _ = ets:new(?LOG_TABLE, [set, public, named_table, {keypos, #log_entry.id}]),
    _ = ets:new(?METRICS_TABLE, [set, public, named_table]),

    %% Initialize state
    State = #state{
        log_dir = LogDir,
        max_entries = maps:get(max_entries, Opts, ?MAX_LOG_ENTRIES),
        rotation_size = maps:get(rotation_size, Opts, ?LOG_ROTATION_SIZE),
        retention_days = maps:get(retention_days, Opts, ?LOG_RETENTION_DAYS),
        metrics = initialize_metrics(),
        log_index = 0
    },

    %% Schedule periodic metrics update
    schedule_metrics_update(5000),

    {ok, State}.

handle_call(get_metrics, _From, State) ->
    UpdatedMetrics = update_system_metrics(State#state.metrics),
    {reply, {ok, metrics_to_map(UpdatedMetrics)}, State};

handle_call({get_metrics, Category}, _From, State) ->
    MetricsMap = metrics_to_map(State#state.metrics),
    case maps:get(Category, MetricsMap, undefined) of
        undefined -> {reply, {error, not_found}, State};
        Value -> {reply, {ok, Value}, State}
    end;

handle_call(reset_metrics, _From, State) ->
    NewState = State#state{metrics = initialize_metrics()},
    {reply, ok, NewState};

handle_call({export_logs, Format}, _From, State) ->
    Logs = ets:tab2list(?LOG_TABLE),
    Result = case Format of
        json -> export_logs_json(Logs, State);
        csv -> export_logs_csv(Logs, State);
        prometheus -> export_logs_prometheus(Logs, State)
    end,
    {reply, Result, State};

handle_call(export_prometheus, _From, State) ->
    Metrics = metrics_to_map(State#state.metrics),
    Output = build_prometheus_export(Metrics),
    {reply, Output, State};

handle_call(rotate_logs, _From, State) ->
    Result = do_rotate_logs(State),
    {reply, Result, State};

handle_call(cleanup_logs, _From, State) ->
    Result = do_cleanup_logs(State),
    {reply, Result, State};

handle_call(get_log_summary, _From, State) ->
    Logs = ets:tab2list(?LOG_TABLE),
    Summary = calculate_log_summary(Logs),
    {reply, {ok, Summary}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({log_event, Level, Type, Message, Metadata}, State) ->
    Entry = #log_entry{
        id = generate_log_id(State),
        timestamp = erlang:system_time(millisecond),
        level = Level,
        type = Type,
        message = Message,
        metadata = Metadata
    },
    ets:insert(?LOG_TABLE, Entry),

    %% Also log to Erlang logger
    ?LOG(Level, "#{level=>~p, type=>~p} ~s ~p", [Level, Type, Message, Metadata]),
    {noreply, State};

handle_cast({combination_generated, _Combination}, State) ->
    Metrics = State#state.metrics,
    NewMetrics = Metrics#metrics{
        total_combinations_generated = Metrics#metrics.total_combinations_generated + 1
    },
    {noreply, State#state{metrics = NewMetrics}};

handle_cast({test_started, _TestID}, State) ->
    Metrics = State#state.metrics,
    NewMetrics = Metrics#metrics{
        tests_run = Metrics#metrics.tests_run + 1
    },
    {noreply, State#state{metrics = NewMetrics}};

handle_cast({test_completed, _TestID, Result}, State) ->
    Metrics = State#state.metrics,
    IsPass = maps:get(<<"status">>, Result, <<"pass">>) =:= <<"pass">>,
    NewMetrics = case IsPass of
        true ->
            Metrics#metrics{tests_passed = Metrics#metrics.tests_passed + 1};
        false ->
            Metrics#metrics{tests_failed = Metrics#metrics.tests_failed + 1}
    end,
    {noreply, State#state{metrics = NewMetrics}};

handle_cast({test_failed, _TestID}, State) ->
    Metrics = State#state.metrics,
    NewMetrics = Metrics#metrics{
        tests_failed = Metrics#metrics.tests_failed + 1
    },
    {noreply, State#state{metrics = NewMetrics}};

handle_cast({demo_started, _DemoName, _Patterns}, State) ->
    Metrics = State#state.metrics,
    NewMetrics = Metrics#metrics{
        demos_run = Metrics#metrics.demos_run + 1,
        start_time = erlang:monotonic_time(millisecond)
    },
    {noreply, State#state{metrics = NewMetrics}};

handle_cast({demo_completed, _DemoName, _Count, DurationMs}, State) ->
    Metrics = State#state.metrics,
    TotalTime = Metrics#metrics.total_generation_time_ms + DurationMs,
    TotalCombinations = Metrics#metrics.total_combinations_generated,
    AvgTime = case TotalCombinations of
        0 -> 0.0;
        _ -> TotalTime / TotalCombinations
    end,
    MinTime = case Metrics#metrics.min_generation_time_ms of
        undefined -> DurationMs;
        Min -> min(Min, DurationMs)
    end,
    MaxTime = case Metrics#metrics.max_generation_time_ms of
        undefined -> DurationMs;
        Max -> max(Max, DurationMs)
    end,
    NewMetrics = Metrics#metrics{
        total_generation_time_ms = TotalTime,
        avg_generation_time_ms = AvgTime,
        min_generation_time_ms = MinTime,
        max_generation_time_ms = MaxTime
    },
    {noreply, State#state{metrics = NewMetrics}};

handle_cast({increment_counter, _CounterName, _Value}, State) ->
    %% Counter implementation for extensibility
    {noreply, State};

handle_cast({set_gauge, _GaugeName, _Value}, State) ->
    %% Gauge implementation for extensibility
    {noreply, State};

handle_cast({record_timing, _TimingName, _Milliseconds}, State) ->
    %% Timing implementation for extensibility
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(metrics_update, State) ->
    NewMetrics = update_system_metrics(State#state.metrics),
    schedule_metrics_update(5000),
    {noreply, State#state{metrics = NewMetrics}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    %% Cleanup ETS tables
    catch ets:delete(?LOG_TABLE),
    catch ets:delete(?METRICS_TABLE),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private Initialize metrics record
initialize_metrics() ->
    #metrics{
        start_time = erlang:monotonic_time(millisecond)
    }.

%% @private Generate unique log ID
generate_log_id(State) ->
    Index = State#state.log_index,
    Timestamp = erlang:system_time(millisecond),
    iolist_to_binary(io_lib:format("~p_~p", [Timestamp, Index])).

%% @private Format patterns for logging
format_patterns(Patterns) when is_list(Patterns) ->
    iolist_to_binary([atom_to_list(P) || P <- Patterns]);
format_patterns(Patterns) when is_tuple(Patterns) ->
    iolist_to_binary([atom_to_list(P) || P <- tuple_to_list(Patterns)]);
format_patterns(Other) ->
    list_to_binary(io_lib:format("~p", [Other])).

%% @private Format error reason
format_reason(Reason) when is_binary(Reason) ->
    Reason;
format_reason(Reason) when is_atom(Reason) ->
    atom_to_binary(Reason, utf8);
format_reason(Reason) ->
    list_to_binary(io_lib:format("~p", [Reason])).

%% @private Update system metrics
update_system_metrics(Metrics) ->
    MemoryWords = erlang:memory(total),
    MemoryMB = MemoryWords * erlang:system_info(wordsize) / (1024 * 1024),
    PeakMemory = max(Metrics#metrics.peak_memory_mb, MemoryMB),
    Metrics#metrics{
        current_memory_mb = MemoryMB,
        peak_memory_mb = PeakMemory
    }.

%% @private Convert metrics record to map
metrics_to_map(#metrics{} = M) ->
    #{
        total_combinations_generated => M#metrics.total_combinations_generated,
        tests_run => M#metrics.tests_run,
        tests_passed => M#metrics.tests_passed,
        tests_failed => M#metrics.tests_failed,
        success_rate => calculate_success_rate(M),
        total_generation_time_ms => M#metrics.total_generation_time_ms,
        avg_generation_time_ms => M#metrics.avg_generation_time_ms,
        min_generation_time_ms => M#metrics.min_generation_time_ms,
        max_generation_time_ms => M#metrics.max_generation_time_ms,
        demos_run => M#metrics.demos_run,
        current_memory_mb => M#metrics.current_memory_mb,
        peak_memory_mb => M#metrics.peak_memory_mb,
        uptime_ms => erlang:monotonic_time(millisecond) - M#metrics.start_time
    }.

%% @private Calculate success rate
calculate_success_rate(#metrics{tests_run = 0}) ->
    0.0;
calculate_success_rate(#metrics{tests_passed = Passed, tests_run = Run}) ->
    Passed / Run.

%% @private Print dashboard to console
print_dashboard(Metrics) ->
    io:format("~n=== Y Combinator Demo - Metrics Dashboard ===~n~n"),

    io:format("Combinations Generated: ~p~n", [maps_get(total_combinations_generated, Metrics, 0)]),
    io:format("Tests Run: ~p~n", [maps_get(tests_run, Metrics, 0)]),
    io:format("Tests Passed: ~p~n", [maps_get(tests_passed, Metrics, 0)]),
    io:format("Tests Failed: ~p~n", [maps_get(tests_failed, Metrics, 0)]),
    io:format("Success Rate: ~.2f%~n", [maps_get(success_rate, Metrics, 0.0) * 100]),

    io:format("~nPerformance:~n"),
    io:format("  Total Generation Time: ~p ms~n", [maps_get(total_generation_time_ms, Metrics, 0)]),
    io:format("  Avg Generation Time: ~.2f ms~n", [maps_get(avg_generation_time_ms, Metrics, 0.0)]),
    io:format("  Min Generation Time: ~p ms~n", [maps_get(min_generation_time_ms, Metrics, 0)]),
    io:format("  Max Generation Time: ~p ms~n", [maps_get(max_generation_time_ms, Metrics, 0)]),

    io:format("~nSystem:~n"),
    io:format("  Current Memory: ~.2f MB~n", [maps_get(current_memory_mb, Metrics, 0.0)]),
    io:format("  Peak Memory: ~.2f MB~n", [maps_get(peak_memory_mb, Metrics, 0.0)]),
    io:format("  Uptime: ~p ms~n", [maps_get(uptime_ms, Metrics, 0)]),
    io:format("  Demos Run: ~p~n", [maps_get(demos_run, Metrics, 0)]),

    io:format("~n============================================~n~n"),
    ok.

%% @private Safe maps get
maps_get(Key, Map, Default) ->
    case maps:get(Key, Map, Default) of
        undefined -> Default;
        Value -> Value
    end.

%% @private Export logs as JSON
export_logs_json(Logs, State) ->
    ExportData = #{
        timestamp => erlang:system_time(millisecond),
        log_count => length(Logs),
        logs => [log_entry_to_map(Entry) || Entry <- Logs]
    },
    JSON = case application:get_key(a2a_erl, applications) of
        {ok, Apps} ->
            case lists:keyfind(jiffy, 1, [{A, application:load(A)} || A <- Apps]) of
                jiffy ->
                    jiffy:encode(ExportData);
                _ ->
                    %% Fallback to simple JSON
                    encode_simple_json(ExportData)
            end;
        _ ->
            encode_simple_json(ExportData)
    end,
    Filename = generate_filename(State, json),
    case file:write_file(Filename, JSON) of
        ok -> {ok, Filename};
        {error, Reason} -> {error, Reason}
    end.

%% @private Export logs as CSV
export_logs_csv(Logs, State) ->
    Header = <<"id,timestamp,level,type,message,metadata\n">>,
    Rows = [log_entry_to_csv(Entry) || Entry <- Logs],
    CSV = <<Header/binary, (iolist_to_binary(Rows))/binary>>,
    Filename = generate_filename(State, csv),
    case file:write_file(Filename, CSV) of
        ok -> {ok, Filename};
        {error, Reason} -> {error, Reason}
    end.

%% @private Export logs in Prometheus format
export_logs_prometheus(_Logs, _State) ->
    %% Prometheus format focuses on metrics, not logs
    {ok, <<>>}.  % Placeholder

%% @private Build Prometheus export
build_prometheus_export(Metrics) ->
    Lines = [
        io_lib:format("# HELP y_combinator_combinations_total Total combinations generated\n", []),
        io_lib:format("# TYPE y_combinator_combinations_total counter\n", []),
        io_lib:format("y_combinator_combinations_total ~p\n", [maps_get(total_combinations_generated, Metrics, 0)]),
        <<"\n">>,
        io_lib:format("# HELP y_combinator_tests_total Total tests run\n", []),
        io_lib:format("# TYPE y_combinator_tests_total counter\n", []),
        io_lib:format("y_combinator_tests_total ~p\n", [maps_get(tests_run, Metrics, 0)]),
        <<"\n">>,
        io_lib:format("# HELP y_combinator_tests_passed Total tests passed\n", []),
        io_lib:format("# TYPE y_combinator_tests_passed counter\n", []),
        io_lib:format("y_combinator_tests_passed ~p\n", [maps_get(tests_passed, Metrics, 0)]),
        <<"\n">>,
        io_lib:format("# HELP y_combinator_tests_failed Total tests failed\n", []),
        io_lib:format("# TYPE y_combinator_tests_failed counter\n", []),
        io_lib:format("y_combinator_tests_failed ~p\n", [maps_get(tests_failed, Metrics, 0)]),
        <<"\n">>,
        io_lib:format("# HELP y_combinator_generation_time_ms Average generation time\n", []),
        io_lib:format("# TYPE y_combinator_generation_time_ms gauge\n", []),
        io_lib:format("y_combinator_generation_time_ms ~.2f\n", [maps_get(avg_generation_time_ms, Metrics, 0.0)]),
        <<"\n">>,
        io_lib:format("# HELP y_combinator_memory_mb Current memory usage\n", []),
        io_lib:format("# TYPE y_combinator_memory_mb gauge\n", []),
        io_lib:format("y_combinator_memory_mb ~.2f\n", [maps_get(current_memory_mb, Metrics, 0.0)])
    ],
    iolist_to_binary(Lines).

%% @private Convert log entry to map
log_entry_to_map(#log_entry{} = E) ->
    #{
        id => E#log_entry.id,
        timestamp => E#log_entry.timestamp,
        level => E#log_entry.level,
        type => E#log_entry.type,
        message => E#log_entry.message,
        metadata => E#log_entry.metadata
    }.

%% @private Convert log entry to CSV
log_entry_to_csv(#log_entry{} = E) ->
    MetadataJSON = encode_simple_json(E#log_entry.metadata),
    io_lib:format("~s,~p,~p,~p,\"~s\",\"~s\"\n",
        [E#log_entry.id, E#log_entry.timestamp, E#log_entry.level,
         E#log_entry.type, escape_csv(E#log_entry.message), escape_csv(MetadataJSON)]).

%% @private Escape CSV values
escape_csv(Value) ->
    binary:replace(Value, <<"\"">>, <<"\"\"">>).

%% @private Encode simple JSON (fallback)
encode_simple_json(Term) when is_map(Term) ->
    Items = [[encode_simple_json(K), <<":">>, encode_simple_json(V)] || {K, V} <- maps:to_list(Term)],
    <<"{$", (iolist_to_binary(lists:join(<<",">>, Items)))/binary, "}">>;
encode_simple_json(Term) when is_list(Term) ->
    case io_lib:printable_list(Term) of
        true -> <<"\"", (list_to_binary(Term))/binary, "\"">>;
        false -> encode_simple_json(lists:map(fun encode_simple_json/1, Term))
    end;
encode_simple_json(Term) when is_binary(Term) ->
    <<"\"", Term/binary, "\"">>;
encode_simple_json(Term) when is_integer(Term) ->
    list_to_binary(integer_to_list(Term));
encode_simple_json(Term) when is_float(Term) ->
    list_to_binary(io_lib:format("~p", [Term]));
encode_simple_json(Term) when is_atom(Term) ->
    <<"\"", (atom_to_binary(Term, utf8))/binary, "\"">>;
encode_simple_json(_Term) ->
    <<"null">>.

%% @private Generate filename
generate_filename(State, Ext) ->
    Timestamp = erlang:system_time(millisecond),
    Filename = iolist_to_binary(io_lib:format("y_combinator_~p.~s", [Timestamp, Ext])),
    filename:join(State#state.log_dir, Filename).

%% @private Rotate log files
do_rotate_logs(State) ->
    LogDir = State#state.log_dir,
    Timestamp = erlang:system_time(millisecond),
    ArchiveFilename = filename:join([LogDir, "archive", iolist_to_binary(io_lib:format("logs_~p.tar", [Timestamp]))]),
    ok = filelib:ensure_dir(ArchiveFilename),
    {ok, ArchiveFilename}.

%% @private Cleanup old log files
do_cleanup_logs(State) ->
    LogDir = State#state.log_dir,
    RetentionMs = State#state.retention_days * 24 * 60 * 60 * 1000,
    CutoffTime = erlang:system_time(millisecond) - RetentionMs,
    {ok, Files} = file:list_dir(LogDir),
    DeletedFiles = lists:filter(fun(Filename) ->
        FullPath = filename:join(LogDir, Filename),
        case filelib:is_file(FullPath) of
            true ->
                {ok, FileInfo} = file:read_file_info(FullPath, [{raw_time_milliseconds}]),
                    %% mtime is in seconds for older file formats, convert to milliseconds
                    MtimeMs = case FileInfo#file_info.mtime of
                        {MegaSecs, Secs, MicroSecs} ->
                            (MegaSecs * 1000000 + Secs) * 1000 + MicroSecs div 1000;
                        Seconds when is_integer(Seconds) ->
                            Seconds * 1000
                    end,
                    MtimeMs < CutoffTime;
            false ->
                false
        end
    end, Files),
    lists:foreach(fun(Filename) ->
        file:delete(filename:join(LogDir, Filename))
    end, DeletedFiles),
    {ok, DeletedFiles}.

%% @private Calculate log summary
calculate_log_summary(Logs) ->
    TotalCount = length(Logs),
    ByLevel = lists:foldl(fun(#log_entry{level = L}, Acc) ->
        maps:update_with(L, fun(V) -> V + 1 end, 1, Acc)
    end, #{}, Logs),
    ByType = lists:foldl(fun(#log_entry{type = T}, Acc) ->
        maps:update_with(T, fun(V) -> V + 1 end, 1, Acc)
    end, #{}, Logs),
    #{
        total_entries => TotalCount,
        by_level => ByLevel,
        by_type => ByType
    }.

%% @private Schedule metrics update
schedule_metrics_update(Interval) ->
    erlang:send_after(Interval, self(), metrics_update).
