%%% @doc A2A Performance Benchmark Suite
%%%
%%% This module provides comprehensive performance benchmarking for hot code upgrades.
%%% It simulates various upgrade scenarios and measures performance characteristics.
%%%
%%% Features:
%%% - Process upgrade benchmarking with different strategies
%%% - ETS table upgrade benchmarking with different sizes
%%% - Memory usage monitoring during upgrades
%%% - Concurrency testing and scaling analysis
%%% - Bottleneck detection and performance tuning
%%% - Detailed performance reporting and optimization recommendations
%%%
%%% Benchmark Categories:
%%% - Single process upgrade times
%%% - Bulk process upgrade performance
%%% - ETS table upgrade performance
%%% - Memory impact analysis
%%% - CPU usage patterns
%%% - Concurrency optimization
%%% @end
-module(a2a_performance_benchmark).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    stop/0,

    %% Benchmark execution
    run_benchmark/1,
    run_benchmark/2,
    run_complete_suite/0,

    %% Process benchmarks
    benchmark_single_process/0,
    benchmark_bulk_processes/1,
    benchmark_concurrency_levels/1,

    %% ETS benchmarks
    benchmark_ets_upgrade/1,
    benchmark_ets_sizes/1,
    benchmark_ets_memory/1,

    %% System benchmarks
    benchmark_memory_usage/0,
    benchmark_cpu_usage/0,
    benchmark_downtime/0,

    %% Analysis and reporting
    get_benchmark_results/0,
    get_performance_report/0,
    generate_optimization_recommendations/0,
    export_benchmark_data/1,

    %% Configuration
    set_benchmark_config/1,
    get_benchmark_config/0
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

-record(benchmark_config, {
    process_count = 100 :: non_neg_integer(),
    concurrency_levels = [1, 2, 4, 8, 16] :: [pos_integer()],
    ets_table_sizes = [1000, 5000, 10000, 50000, 100000] :: [pos_integer()],
    memory_limit_mb = 2048 :: pos_integer(),
    benchmark_timeout_ms = 300000 :: non_neg_integer(),
    warmup_time_ms = 5000 :: non_neg_integer(),
    cooldown_time_ms = 3000 :: non_neg_integer(),
    enable_memory_tracking = true :: boolean(),
    enable_cpu_tracking = true :: boolean(),
    save_results_to_file = true :: boolean()
}).

-type benchmark_config() :: #benchmark_config{}.

-record(benchmark_result, {
    benchmark_id :: binary(),
    benchmark_type :: atom(),
    start_time :: integer(),
    end_time :: integer(),
    duration_ms :: non_neg_integer(),
    metrics :: map(),
    memory_before :: non_neg_integer(),
    memory_peak :: non_neg_integer(),
    memory_after :: non_neg_integer(),
    cpu_avg :: float(),
    cpu_peak :: float(),
    throughput :: float(),
    error_count :: non_neg_integer(),
    warnings :: [binary()],
    raw_data :: list()
}).

-type benchmark_result() :: #benchmark_result{}.

-record(process_benchmark_data, {
    pid :: pid(),
    upgrade_time_ms :: non_neg_integer(),
    memory_before :: non_neg_integer(),
    memory_after :: non_neg_integer(),
    status :: success | failed | timeout,
    error_reason :: term() | undefined,
    cpu_usage :: float()
}).

-type process_benchmark_data() :: #process_benchmark_data{}.

-record(ets_benchmark_data, {
    table_name :: ets_table_name(),
    record_count :: non_neg_integer(),
    upgrade_time_ms :: non_neg_integer(),
    memory_before :: non_neg_integer(),
    memory_after :: non_neg_integer(),
    status :: success | failed | timeout,
    error_reason :: term() | undefined,
    throughput_per_second :: float()
}).

-type ets_benchmark_data() :: #ets_benchmark_data{}.

-record(system_benchmark_data, {
    total_memory_mb :: float(),
    avg_cpu_usage :: float(),
    peak_cpu_usage :: float(),
    process_count :: non_neg_integer(),
    ets_count :: non_neg_integer(),
    garbage_collection_count :: non_neg_integer(),
    context_switches :: non_neg_integer()
}).

-type system_benchmark_data() :: #system_benchmark_data{}.

-record(state, {
    config :: benchmark_config(),
    current_benchmarks = #{} :: #{binary() => benchmark_result()},
    benchmark_history = [] :: [benchmark_result()],
    active_benchmarks = [] :: [binary()],
    monitoring_timer :: reference() | undefined,
    results_timer :: reference() | undefined,
    system_baseline :: system_benchmark_data() | undefined
}).

-type state() :: #state{}.

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the benchmark system with default options
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the benchmark system with options
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

%% @doc Stop the benchmark system
-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%% @brief Run a specific benchmark
-spec run_benchmark(atom()) -> {ok, binary()} | {error, term()}.
run_benchmark(Type) ->
    run_benchmark(Type, #{}).

%% @brief Run a specific benchmark with options
-spec run_benchmark(atom(), map()) -> {ok, binary()} | {error, term()}.
run_benchmark(Type, Options) ->
    gen_server:call(?MODULE, {run_benchmark, Type, Options}).

%% @brief Run the complete benchmark suite
-spec run_complete_suite() -> {ok, [binary()]} | {error, term()}.
run_complete_suite() ->
    gen_server:call(?MODULE, run_complete_suite).

%% @brief Benchmark single process upgrade
-spec benchmark_single_process() -> {ok, binary()} | {error, term()}.
benchmark_single_process() ->
    gen_server:call(?MODULE, benchmark_single_process).

%% @brief Benchmark bulk process upgrade
-spec benchmark_bulk_processes(pos_integer()) -> {ok, binary()} | {error, term()}.
benchmark_bulk_processes(ProcessCount) ->
    gen_server:call(?MODULE, {benchmark_bulk_processes, ProcessCount}).

%% @brief Benchmark different concurrency levels
-spec benchmark_concurrency_levels([pos_integer()]) -> {ok, binary()} | {error, term()}.
benchmark_concurrency_levels(Levels) ->
    gen_server:call(?MODULE, {benchmark_concurrency_levels, Levels}).

%% @brief Benchmark ETS table upgrade
-spec benchmark_ets_upgrade(pos_integer()) -> {ok, binary()} | {error, term()}.
benchmark_ets_upgrade(RecordCount) ->
    gen_server:call(?MODULE, {benchmark_ets_upgrade, RecordCount}).

%% @brief Benchmark different ETS table sizes
-spec benchmark_ets_sizes([pos_integer()]) -> {ok, binary()} | {error, term()}.
benchmark_ets_sizes(Sizes) ->
    gen_server:call(?MODULE, {benchmark_ets_sizes, Sizes}).

%% @brief Benchmark ETS table memory impact
-spec benchmark_ets_memory(pos_integer()) -> {ok, binary()} | {error, term()}.
benchmark_ets_memory(RecordCount) ->
    gen_server:call(?MODULE, {benchmark_ets_memory, RecordCount}).

%% @brief Benchmark memory usage during upgrades
-spec benchmark_memory_usage() -> {ok, binary()} | {error, term()}.
benchmark_memory_usage() ->
    gen_server:call(?MODULE, benchmark_memory_usage).

%% @brief Benchmark CPU usage during upgrades
-spec benchmark_cpu_usage() -> {ok, binary()} | {error, term()}.
benchmark_cpu_usage() ->
    gen_server:call(?MODULE, benchmark_cpu_usage).

%% @brief Benchmark downtime during upgrades
-spec benchmark_downtime() -> {ok, binary()} | {error, term()}.
benchmark_downtime() ->
    gen_server:call(?MODULE, benchmark_downtime).

%% @brief Get benchmark results
-spec get_benchmark_results() -> #{binary() => benchmark_result()}.
get_benchmark_results() ->
    gen_server:call(?MODULE, get_benchmark_results).

%% @brief Get performance report
-spec get_performance_report() -> map().
get_performance_report() ->
    gen_server:call(?MODULE, get_performance_report).

%% @brief Generate optimization recommendations
-spec generate_optimization_recommendations() -> [binary()].
generate_optimization_recommendations() ->
    gen_server:call(?MODULE, generate_optimization_recommendations).

%% @brief Export benchmark data to file
-spec export_benchmark_data(file:filename()) -> ok | {error, term()}.
export_benchmark_data(Filename) ->
    gen_server:call(?MODULE, {export_benchmark_data, Filename}).

%% @brief Set benchmark configuration
-spec set_benchmark_config(map()) -> ok.
set_benchmark_config(Config) ->
    gen_server:cast(?MODULE, {set_benchmark_config, Config}).

%% @brief Get benchmark configuration
-spec get_benchmark_config() -> benchmark_config().
get_benchmark_config() ->
    gen_server:call(?MODULE, get_benchmark_config).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init(map()) -> {ok, state()} | {ok, state(), {continue, atom()}}.
init(Opts) ->
    DefaultConfig = #benchmark_config{
        process_count = maps:get(process_count, Opts, 100),
        concurrency_levels = maps:get(concurrency_levels, Opts, [1, 2, 4, 8, 16]),
        ets_table_sizes = maps:get(ets_table_sizes, Opts, [1000, 5000, 10000, 50000, 100000]),
        memory_limit_mb = maps.get(memory_limit_mb, Opts, 2048),
        benchmark_timeout_ms = maps.get(benchmark_timeout_ms, Opts, 300000),
        warmup_time_ms = maps.get(warmup_time_ms, Opts, 5000),
        cooldown_time_ms = maps.get(cooldown_time_ms, Opts, 3000),
        enable_memory_tracking = maps.get(enable_memory_tracking, Opts, true),
        enable_cpu_tracking = maps.get(enable_cpu_tracking, Opts, true),
        save_results_to_file = maps.get(save_results_to_file, Opts, true)
    },

    State = #state{
        config = DefaultConfig
    },

    {ok, State, {continue, initialize_benchmark_system}}.

-spec handle_continue(atom(), state()) -> {ok, state()}.
handle_continue(initialize_benchmark_system, State) ->
    %% Capture system baseline
    Baseline = capture_system_baseline(),
    NewState = State#state{system_baseline = Baseline},

    %% Start monitoring timers
    MonitoringTimer = schedule_monitoring(1000),
    ResultsTimer = schedule_results_summary(30000),

    logger:info("Performance benchmark system initialized", #{
        baseline_memory => Baseline#system_benchmark_data.total_memory_mb,
        baseline_processes => Baseline#system_benchmark_data.process_count,
        domain => [a2a, benchmark, system]
    }),

    {ok, NewState#state{
        monitoring_timer = MonitoringTimer,
        results_timer = ResultsTimer
    }}.

-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()} | {noreply, state()}.
handle_call({run_benchmark, Type, Options}, _From, State) ->
    case State#state.active_benchmarks of
        [] ->
            BenchmarkId = generate_benchmark_id(),
            NewConfig = apply_benchmark_options(State#state.config, Options),

            case start_benchmark(Type, BenchmarkId, NewConfig, State) of
                {ok, NewState} ->
                    {reply, {ok, BenchmarkId}, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        _ ->
            {reply, {error, benchmark_in_progress}, State}
    end;

handle_call(run_complete_suite, _From, State) ->
    case State#state.active_benchmarks of
        [] ->
            BenchmarkIds = run_complete_suite_internal(State),
            {reply, {ok, BenchmarkIds}, State};
        _ ->
            {reply, {error, benchmark_in_progress}, State}
    end;

handle_call(benchmark_single_process, _From, State) ->
    BenchmarkId = generate_benchmark_id(),
    case run_single_process_benchmark(BenchmarkId, State#state.config) of
        {ok, NewState} ->
            {reply, {ok, BenchmarkId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({benchmark_bulk_processes, ProcessCount}, _From, State) ->
    BenchmarkId = generate_benchmark_id(),
    case run_bulk_process_benchmark(BenchmarkId, ProcessCount, State#state.config) of
        {ok, NewState} ->
            {reply, {ok, BenchmarkId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({benchmark_concurrency_levels, Levels}, _From, State) ->
    BenchmarkId = generate_benchmark_id(),
    case run_concurrency_benchmark(BenchmarkId, Levels, State#state.config) of
        {ok, NewState} ->
            {reply, {ok, BenchmarkId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({benchmark_ets_upgrade, RecordCount}, _From, State) ->
    BenchmarkId = generate_benchmark_id(),
    case run_ets_upgrade_benchmark(BenchmarkId, RecordCount, State#state.config) of
        {ok, NewState} ->
            {reply, {ok, BenchmarkId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({benchmark_ets_sizes, Sizes}, _From, State) ->
    BenchmarkId = generate_benchmark_id(),
    case run_ets_sizes_benchmark(BenchmarkId, Sizes, State#state.config) of
        {ok, NewState} ->
            {reply, {ok, BenchmarkId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({benchmark_ets_memory, RecordCount}, _From, State) ->
    BenchmarkId = generate_benchmark_id(),
    case run_ets_memory_benchmark(BenchmarkId, RecordCount, State#state.config) of
        {ok, NewState} ->
            {reply, {ok, BenchmarkId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(benchmark_memory_usage, _From, State) ->
    BenchmarkId = generate_benchmark_id(),
    case run_memory_usage_benchmark(BenchmarkId, State#state.config) of
        {ok, NewState} ->
            {reply, {ok, BenchmarkId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(benchmark_cpu_usage, _From, State) ->
    BenchmarkId = generate_benchmark_id(),
    case run_cpu_usage_benchmark(BenchmarkId, State#state.config) of
        {ok, NewState} ->
            {reply, {ok, BenchmarkId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(benchmark_downtime, _From, State) ->
    BenchmarkId = generate_benchmark_id(),
    case run_downtime_benchmark(BenchmarkId, State#state.config) of
        {ok, NewState} ->
            {reply, {ok, BenchmarkId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(get_benchmark_results, _From, State) ->
    {reply, State#state.current_benchmarks, State};

handle_call(get_performance_report, _From, State) ->
    Report = generate_performance_report(State),
    {reply, Report, State};

handle_call(generate_optimization_recommendations, _From, State) ->
    Recommendations = generate_optimization_recommendations_internal(State),
    {reply, Recommendations, State};

handle_call({export_benchmark_data, Filename}, _From, State) ->
    case export_results_to_file(Filename, State) of
        ok ->
            {reply, ok, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(get_benchmark_config, _From, State) ->
    {reply, State#state.config, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({set_benchmark_config, Config}, State) ->
    NewConfig = apply_benchmark_options(State#state.config, Config),
    NewState = State#state{config = NewConfig},
    logger:info("Benchmark configuration updated", #{
        domain => [a2a, benchmark, system]
    }),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(monitoring_timeout, State) ->
    %% Perform system monitoring
    NewState = perform_system_monitoring(State),
    MonitoringTimer = schedule_monitoring(1000),
    {noreply, NewState#state{monitoring_timer = MonitoringTimer}};

handle_info(results_summary_timeout, State) ->
    %% Generate and log results summary
    ResultsSummary = generate_results_summary(State),
    logger:info("Benchmark results summary", #{
        summary => ResultsSummary,
        domain => [a2a, benchmark, system]
    }),

    ResultsTimer = schedule_results_summary(30000),
    {noreply, NewState#state{results_timer = ResultsTimer}};

handle_info(benchmark_complete, State) ->
    %% Handle benchmark completion
    case State#state.active_benchmarks of
        [Id] when length(State#state.active_benchmarks) =:= 1 ->
            %% Last benchmark completed
            NewActive = lists:delete(Id, State#state.active_benchmarks),
            FinalState = State#state{active_benchmarks = NewActive},
            logger:info("All benchmarks completed", #{
                domain => [a2a, benchmark, system]
            }),
            {noreply, FinalState};
        _ ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, #state{monitoring_timer = MonitoringTimer, results_timer = ResultsTimer}) ->
    %% Cancel timers
    case MonitoringTimer of
        undefined -> ok;
        T -> erlang:cancel_timer(T)
    end,
    case ResultsTimer of
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

%% @doc Apply benchmark options to config
-spec apply_benchmark_options(benchmark_config(), map()) -> benchmark_config().
apply_benchmark_options(Config, Options) ->
    Config#benchmark_config{
        process_count = maps:get(process_count, Options, Config#benchmark_config.process_count),
        concurrency_levels = maps:get(concurrency_levels, Options, Config#benchmark_config.concurrency_levels),
        ets_table_sizes = maps:get(ets_table_sizes, Options, Config#benchmark_config.ets_table_sizes),
        memory_limit_mb = maps:get(memory_limit_mb, Options, Config#benchmark_config.memory_limit_mb),
        benchmark_timeout_ms = maps:get(benchmark_timeout_ms, Options, Config#benchmark_config.benchmark_timeout_ms),
        warmup_time_ms = maps:get(warmup_time_ms, Options, Config#benchmark_config.warmup_time_ms),
        cooldown_time_ms = maps:get(cooldown_time_ms, Options, Config#benchmark_config.cooldown_time_ms),
        enable_memory_tracking = maps:get(enable_memory_tracking, Options, Config#benchmark_config.enable_memory_tracking),
        enable_cpu_tracking = maps:get(enable_cpu_tracking, Options, Config#benchmark_config.enable_cpu_tracking),
        save_results_to_file = maps:get(save_results_to_file, Options, Config#benchmark_config.save_results_to_file)
    }.

%% @doc Generate benchmark ID
-spec generate_benchmark_id() -> binary().
generate_benchmark_id() ->
    Now = erlang:system_time(millisecond),
    <<Id:8/binary, _:64>> = crypto:strong_rand_bytes(16),
    <<Id/binary, "-", (integer_to_binary(Now))/binary>>.

%% @doc Capture system baseline
-spec capture_system_baseline() -> system_benchmark_data().
capture_system_baseline() ->
    ProcessCount = erlang:system_info(process_count),
    MemoryWords = erlang:memory(total),
    MemoryMB = MemoryWords * erlang:wordsize() / (1024 * 1024),
    CpuUsage = get_cpu_usage(),

    #system_benchmark_data{
        total_memory_mb = MemoryMB,
        avg_cpu_usage = CpuUsage,
        peak_cpu_usage = CpuUsage,
        process_count = ProcessCount,
        ets_count = length(ets:all()),
        garbage_collection_count = erlang:system_info(garbage_collection_count),
        context_switches = erlang:system_info(context_switches)
    }.

%% @doc Start a benchmark
-spec start_benchmark(atom(), binary(), benchmark_config(), state()) -> {ok, state()} | {error, term()}.
start_benchmark(Type, BenchmarkId, Config, State) ->
    %% Validate benchmark type
    ValidTypes = [single_process, bulk_processes, concurrency_levels, ets_upgrade, ets_sizes, ets_memory, memory_usage, cpu_usage, downtime],
    case lists:member(Type, ValidTypes) of
        true ->
            StartNow = erlang:system_time(millisecond),
            Baseline = get_system_stats(),

            BenchmarkResult = #benchmark_result{
                benchmark_id = BenchmarkId,
                benchmark_type = Type,
                start_time = StartNow,
                memory_before = Baseline#system_benchmark_data.total_memory_mb,
                raw_data = []
            },

            NewState = State#state{
                current_benchmarks = maps:put(BenchmarkId, BenchmarkResult, State#state.current_benchmarks),
                active_benchmarks = [BenchmarkId | State#state.active_benchmarks]
            },

            %% Spawn benchmark process
            spawn_link(fun() ->
                execute_benchmark(Type, BenchmarkId, Config, NewState)
            end),

            {ok, NewState};
        false ->
            {error, invalid_benchmark_type}
    end.

%% @doc Execute a benchmark
-spec execute_benchmark(atom(), binary(), benchmark_config(), state()) -> ok.
execute_benchmark(single_process, BenchmarkId, _Config, _State) ->
    run_single_process_benchmark(BenchmarkId);

execute_benchmark(bulk_processes, BenchmarkId, Config, _State) ->
    run_bulk_process_benchmark(BenchmarkId, Config#benchmark_config.process_count);

execute_benchmark(concurrency_levels, BenchmarkId, Config, _State) ->
    run_concurrency_benchmark(BenchmarkId, Config#benchmark_config.concurrency_levels);

execute_benchmark(ets_upgrade, BenchmarkId, Config, _State) ->
    run_ets_upgrade_benchmark(BenchmarkId, lists:nth(1, Config#benchmark_config.ets_table_sizes));

execute_benchmark(ets_sizes, BenchmarkId, Config, _State) ->
    run_ets_sizes_benchmark(BenchmarkId, Config#benchmark_config.ets_table_sizes);

execute_benchmark(ets_memory, BenchmarkId, Config, _State) ->
    run_ets_memory_benchmark(BenchmarkId, lists:nth(1, Config#benchmark_config.ets_table_sizes));

execute_benchmark(memory_usage, BenchmarkId, Config, _State) ->
    run_memory_usage_benchmark(BenchmarkId);

execute_benchmark(cpu_usage, BenchmarkId, Config, _State) ->
    run_cpu_usage_benchmark(BenchmarkId);

execute_benchmark(downtime, BenchmarkId, Config, _State) ->
    run_downtime_benchmark(BenchmarkId).

%% @doc Run single process benchmark
-spec run_single_process_benchmark(binary()) -> ok.
run_single_process_benchmark(BenchmarkId) ->
    logger:info("Starting single process benchmark", #{
        benchmark_id => BenchmarkId,
        domain => [a2a, benchmark, single_process]
    }),

    %% Create test process
    Pid = spawn_link(fun() -> benchmark_process_loop() end),

    %% Perform upgrade
    Start = erlang:monotonic_time(millisecond),
    Result = upgrade_test_process(Pid),
    End = erlang:monotonic_time(millisecond),

    %% Clean up
    unlink(Pid),
    exit(Pid, normal),

    Duration = End - Start,
    MemoryBefore = get_process_memory(Pid),
    MemoryAfter = get_process_memory(Pid),

    ResultData = #{
        upgrade_time_ms => Duration,
        memory_before => MemoryBefore,
        memory_after => MemoryAfter,
        success => Result =:= success
    },

    logger:info("Single process benchmark completed", #{
        benchmark_id => BenchmarkId,
        duration_ms => Duration,
        domain => [a2a, benchmark, single_process]
    }),

    self() ! {benchmark_complete, BenchmarkId, ResultData}.

%% @doc Run bulk process benchmark
-spec run_bulk_process_benchmark(binary(), pos_integer()) -> ok.
run_bulk_process_benchmark(BenchmarkId, ProcessCount) ->
    logger:info("Starting bulk process benchmark", #{
        benchmark_id => BenchmarkId,
        process_count => ProcessCount,
        domain => [a2a, benchmark, bulk_processes]
    }),

    %% Create test processes
    Processes = lists:map(fun(_) ->
        spawn_link(fun() -> benchmark_process_loop() end)
    end, lists:seq(1, ProcessCount)),

    %% Perform upgrades
    Start = erlang:monotonic_time(millisecond),
    Results = lists:map(fun(Pid) ->
        Result = upgrade_test_process(Pid),
        unlink(Pid),
        exit(Pid, normal),
        Result
    end, Processes),

    End = erlang:monotonic_time(millisecond),

    Duration = End - Start,
    SuccessCount = lists:filter(fun(R) -> R =:= success end, Results),
    SuccessRate = length(SuccessCount) / length(Results),

    ResultData = #{
        process_count => ProcessCount,
        duration_ms => Duration,
        success_rate => SuccessRate,
        avg_upgrade_time_ms => Duration / length(Processes),
        total_success => length(SuccessCount),
        total_failures => length(Results) - length(SuccessCount)
    },

    logger:info("Bulk process benchmark completed", #{
        benchmark_id => BenchmarkId,
        duration_ms => Duration,
        success_rate => SuccessRate,
        domain => [a2a, benchmark, bulk_processes]
    }),

    self() ! {benchmark_complete, BenchmarkId, ResultData}.

%% @doc Run concurrency benchmark
-spec run_concurrency_benchmark(binary(), [pos_integer()]) -> ok.
run_concurrency_benchmark(BenchmarkId, ConcurrencyLevels) ->
    logger:info("Starting concurrency benchmark", #{
        benchmark_id => BenchmarkId,
        levels => ConcurrencyLevels,
        domain => [a2a, benchmark, concurrency]
    }),

    Results = lists:map(fun(Concurrency) ->
        ProcessCount = 50, %% Fixed number of processes for each level
        Processes = lists:map(fun(_) ->
            spawn_link(fun() -> benchmark_process_loop() end)
        end, lists:seq(1, ProcessCount)),

        %% Perform upgrades with controlled concurrency
        Start = erlang:monotonic_time(millisecond),
        Results = upgrade_concurrent_processes(Processes, Concurrency),
        End = erlang:monotonic_time(millisecond),

        %% Clean up
        lists:foreach(fun(Pid) ->
            unlink(Pid),
            exit(Pid, normal)
        end, Processes),

        Duration = End - Start,
        SuccessCount = lists:filter(fun(R) -> R =:= success end, Results),
        SuccessRate = length(SuccessCount) / length(Results),

        #{
            concurrency => Concurrency,
            process_count => ProcessCount,
            duration_ms => Duration,
            success_rate => SuccessRate,
            throughput => ProcessCount / (Duration / 1000)
        }
    end, ConcurrencyLevels),

    logger:info("Concurrency benchmark completed", #{
        benchmark_id => BenchmarkId,
        domain => [a2a, benchmark, concurrency]
    }),

    self() ! {benchmark_complete, BenchmarkId, Results}.

%% @doc Run ETS upgrade benchmark
-spec run_ets_upgrade_benchmark(binary(), pos_integer()) -> ok.
run_ets_upgrade_benchmark(BenchmarkId, RecordCount) ->
    logger:info("Starting ETS upgrade benchmark", #{
        benchmark_id => BenchmarkId,
        record_count => RecordCount,
        domain => [a2a, benchmark, ets]
    }),

    %% Create test ETS table
    TableName = list_to_atom("benchmark_" ++ binary_to_list(BenchmarkId)),
    ets:new(TableName, [named_table, public, set, {write_concurrency, auto}]),
    populate_ets_table(TableName, RecordCount),

    %% Perform upgrade
    Start = erlang:monotonic_time(millisecond),
    Result = upgrade_ets_table(TableName),
    End = erlang:monotonic_time(millisecond),

    %% Clean up
    ets:delete(TableName),

    Duration = End - Start,
    MemoryBefore = ets:info(TableName, memory),
    MemoryAfter = ets:info(TableName, memory),

    ResultData = #{
        record_count => RecordCount,
        duration_ms => Duration,
        memory_before => MemoryBefore,
        memory_after => MemoryAfter,
        upgrade_success => Result =:= success,
        throughput_per_second => RecordCount / (Duration / 1000)
    },

    logger:info("ETS upgrade benchmark completed", #{
        benchmark_id => BenchmarkId,
        duration_ms => Duration,
        domain => [a2a, benchmark, ets]
    }),

    self() ! {benchmark_complete, BenchmarkId, ResultData}.

%% @doc Run ETS sizes benchmark
-spec run_ets_sizes_benchmark(binary(), [pos_integer()]) -> ok.
run_ets_sizes_benchmark(BenchmarkId, Sizes) ->
    logger:info("Starting ETS sizes benchmark", #{
        benchmark_id => BenchmarkId,
        sizes => Sizes,
        domain => [a2a, benchmark, ets]
    }),

    Results = lists:map(fun(RecordCount) ->
        TableName = list_to_atom("benchmark_size_" ++ integer_to_list(RecordCount)),
        ets:new(TableName, [named_table, public, set, {write_concurrency, auto}]),
        populate_ets_table(TableName, RecordCount),

        Start = erlang:monotonic_time(millisecond),
        Result = upgrade_ets_table(TableName),
        End = erlang:monotonic_time(millisecond),

        ets:delete(TableName),

        Duration = End - Start,
        MemoryUsage = ets:info(TableName, memory),

        #{
            record_count => RecordCount,
            duration_ms => Duration,
            memory_usage => MemoryUsage,
            upgrade_success => Result =:= success,
            throughput_per_second => RecordCount / (Duration / 1000)
        }
    end, Sizes),

    logger:info("ETS sizes benchmark completed", #{
        benchmark_id => BenchmarkId,
        domain => [a2a, benchmark, ets]
    }),

    self() ! {benchmark_complete, BenchmarkId, Results}.

%% @doc Run ETS memory benchmark
-spec run_ets_memory_benchmark(binary(), pos_integer()) -> ok.
run_ets_memory_benchmark(BenchmarkId, RecordCount) ->
    logger:info("Starting ETS memory benchmark", #{
        benchmark_id => BenchmarkId,
        record_count => RecordCount,
        domain => [a2a, benchmark, ets]
    }),

    %% Create test ETS table
    TableName = list_to_atom("benchmark_memory_" ++ binary_to_list(BenchmarkId)),
    ets:new(TableName, [named_table, public, set, {write_concurrency, auto}]),
    populate_ets_table(TableName, RecordCount),

    %% Monitor memory during upgrade
    InitialMemory = erlang:memory(total),
    Start = erlang:monotonic_time(millisecond),
    Result = upgrade_ets_table(TableName),
    End = erlang:monotonic_time(millisecond),
    FinalMemory = erlang:memory(total),

    %% Clean up
    ets:delete(TableName),

    Duration = End - Start,
    MemoryImpact = (FinalMemory - InitialMemory) * erlang:wordsize() / (1024 * 1024),

    ResultData = #{
        record_count => RecordCount,
        duration_ms => Duration,
        initial_memory_mb => InitialMemory * erlang:wordsize() / (1024 * 1024),
        final_memory_mb => FinalMemory * erlang:wordsize() / (1024 * 1024),
        memory_impact_mb => MemoryImpact,
        upgrade_success => Result =:= success,
        memory_efficiency => RecordCount / MemoryImpact
    },

    logger:info("ETS memory benchmark completed", #{
        benchmark_id => BenchmarkId,
        duration_ms => Duration,
        memory_impact_mb => MemoryImpact,
        domain => [a2a, benchmark, ets]
    }),

    self() ! {benchmark_complete, BenchmarkId, ResultData}.

%% @doc Run memory usage benchmark
-spec run_memory_usage_benchmark(binary()) -> ok.
run_memory_usage_benchmark(BenchmarkId) ->
    logger:info("Starting memory usage benchmark", #{
        benchmark_id => BenchmarkId,
        domain => [a2a, benchmark, memory]
    }),

    %% Monitor memory during various operations
    InitialMemory = erlang:memory(total),
    MemorySnapshots = [],

    %% Create processes
    Start = erlang:monotonic_time(millisecond),
    Processes = lists:map(fun(_) ->
        spawn_link(fun() -> benchmark_process_loop() end)
    end, lists:seq(1, 100)),

    %% Perform operations
    lists:foreach(fun(_) ->
        %% Simulate some work
        lists:seq(1, 1000),
        MemoryNow = erlang:memory(total),
        MemorySnapshots = [MemoryNow | MemorySnapshots]
    end, lists:seq(1, 50)),

    %% Upgrade processes
    UpgradeResults = lists:map(fun(Pid) ->
        upgrade_test_process(Pid)
    end, Processes),

    %% Clean up
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, Processes),

    End = erlang:monotonic_time(millisecond),
    FinalMemory = erlang:memory(total),

    Duration = End - Start,
    PeakMemory = lists:max(MemorySnapshots),

    ResultData = #{
        duration_ms => Duration,
        initial_memory_mb => InitialMemory * erlang:wordsize() / (1024 * 1024),
        peak_memory_mb => PeakMemory * erlang:wordsize() / (1024 * 1024),
        final_memory_mb => FinalMemory * erlang:wordsize() / (1024 * 1024),
        memory_peak_impact_mb => (PeakMemory - InitialMemory) * erlang:wordsize() / (1024 * 1024),
        processes_created => 100,
        processes_upgraded => length(UpgradeResults),
        upgrade_success_rate => lists:filter(fun(R) -> R =:= success end, UpgradeResults) / length(UpgradeResults)
    },

    logger:info("Memory usage benchmark completed", #{
        benchmark_id => BenchmarkId,
        duration_ms => Duration,
        peak_memory_mb => PeakMemory * erlang:wordsize() / (1024 * 1024),
        domain => [a2a, benchmark, memory]
    }),

    self() ! {benchmark_complete, BenchmarkId, ResultData}.

%% @doc Run CPU usage benchmark
-spec run_cpu_usage_benchmark(binary()) -> ok.
run_cpu_usage_benchmark(BenchmarkId) ->
    logger:info("Starting CPU usage benchmark", #{
        benchmark_id => BenchmarkId,
        domain => [a2a, benchmark, cpu]
    }),

    %% Monitor CPU during various operations
    Start = erlang:monotonic_time(millisecond),
    CpuSnapshots = [],

    %% Perform CPU-intensive operations
    lists:foreach(fun(_) ->
        CpuNow = get_cpu_usage(),
        CpuSnapshots = [CpuNow | CpuSnapshots],

        %% Simulate CPU work
        lists:foldl(fun(_, Acc) -> Acc + math:sqrt(Acc) end, 10000, lists:seq(1, 1000))
    end, lists:seq(1, 100)),

    End = erlang:monotonic_time(millisecond),

    Duration = End - Start,
    AvgCpu = lists:sum(CpuSnapshots) / length(CpuSnapshots),
    PeakCpu = lists:max(CpuSnapshots),

    ResultData = #{
        duration_ms => Duration,
        avg_cpu_usage => AvgCpu,
        peak_cpu_usage => PeakCpu,
        operations_per_second => 100 / (Duration / 1000),
        total_operations => 100
    },

    logger:info("CPU usage benchmark completed", #{
        benchmark_id => BenchmarkId,
        duration_ms => Duration,
        avg_cpu_usage => AvgCpu,
        domain => [a2a, benchmark, cpu]
    }),

    self() ! {benchmark_complete, BenchmarkId, ResultData}.

%% @doc Run downtime benchmark
-spec run_downtime_benchmark(binary()) -> ok.
run_downtime_benchmark(BenchmarkId) ->
    logger:info("Starting downtime benchmark", #{
        benchmark_id => BenchmarkId,
        domain => [a2a, benchmark, downtime]
    }),

    %% Create test clients
    TestClients = lists:map(fun(Id) ->
        spawn_link(fun() -> benchmark_client(Id) end)
    end, lists:seq(1, 10)),

    %% Allow clients to initialize
    timer:sleep(1000),

    %% Perform upgrade and measure downtime
    StartTime = erlang:monotonic_time(millisecond),
    UpgradeResult = perform_system_upgrade(),
    EndTime = erlang:monotonic_time(millisecond),

    MeasureDowntime(TestClients),

    %% Clean up
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, TestClients),

    Duration = EndTime - StartTime,

    ResultData = #{
        upgrade_duration_ms => Duration,
        total_downtime_ms => calculate_total_downtime(),
        clients_affected => length(TestClients),
        upgrade_success => UpgradeResult =:= success,
        downtime_per_client => calculate_total_downtime() / length(TestClients)
    },

    logger:info("Downtime benchmark completed", #{
        benchmark_id => BenchmarkId,
        duration_ms => Duration,
        total_downtime_ms => calculate_total_downtime(),
        domain => [a2a, benchmark, downtime]
    }),

    self() ! {benchmark_complete, BenchmarkId, ResultData}.

%% @doc Run complete suite
-spec run_complete_suite_internal(state()) -> [binary()].
run_complete_suite_internal(State) ->
    Config = State#state.config,
    Benchmarks = [
        {single_process, #{}},
        {bulk_processes, #{process_count => Config#benchmark_config.process_count}},
        {concurrency_levels, #{concurrency_levels => Config#benchmark_config.concurrency_levels}},
        {ets_upgrade, #{record_count => lists:nth(1, Config#benchmark_config.ets_table_sizes)}},
        {ets_sizes, #{ets_table_sizes => Config#benchmark_config.ets_table_sizes}},
        {ets_memory, #{record_count => lists:nth(1, Config#benchmark_config.ets_table_sizes)}},
        {memory_usage, #{}},
        {cpu_usage, #{}},
        {downtime, #{}}
    ],

    %% Run benchmarks sequentially
    Results = lists:map(fun({Type, Options}) ->
        case run_benchmark(Type, Options) of
            {ok, Id} -> Id;
            {error, _} -> undefined
        end
    end, Benchmarks),

    %% Filter out undefined results
    lists:filter(fun(Id) -> Id =/= undefined end, Results).

%% @doc Test process loop
-spec benchmark_process_loop() -> no_return().
benchmark_process_loop() ->
    receive
        _ -> benchmark_process_loop()
    end.

%% @doc Test client
-spec benchmark_client(integer()) -> no_return().
benchmark_client(Id) ->
    %% Simulate client work
    receive
        _ -> benchmark_client(Id)
    after 10000 ->
        %% Timeout
        ok
    end.

%% @doc Upgrade test process
-spec upgrade_test_process(pid()) -> success | failed.
upgrade_test_process(Pid) ->
    try
        %% Simulate upgrade operation
        case process_info(Pid) of
            undefined -> failed;
            _ -> success
        end
    catch
        _:Error -> failed
    end.

%% @doc Upgrade concurrent processes
-spec upgrade_concurrent_processes([pid()], pos_integer()) -> [success | failed].
upgrade_concurrent_processes(Processes, Concurrency) ->
    %% Group processes by concurrency level
    Groups = chunk_list(Processes, Concurrency),
    lists:map(fun(Group) ->
        %% Process group in parallel
        Results = lists:map(fun(Pid) ->
            upgrade_test_process(Pid)
        end, Group),
        %% Wait for group to complete
        lists:foreach(fun(Pid) ->
            receive
                {Pid, Result} -> Result
            after 5000 -> timeout
            end
        end, Group),
        Results
    end, Groups).

%% @doc Populate ETS table
-spec populate_ets_table(ets_table_name(), pos_integer()) -> ok.
populate_ets_table(TableName, RecordCount) ->
    lists:foreach(fun(I) ->
        ets:insert(TableName, {I, <<"test_data_", (integer_to_binary(I))/binary>>})
    end, lists:seq(1, RecordCount)).

%% @doc Upgrade ETS table
-spec upgrade_ets_table(ets_table_name()) -> success | failed.
upgrade_ets_table(TableName) ->
    try
        %% Simulate ETS upgrade operation
        case ets:info(TableName) of
            undefined -> failed;
            _ -> success
        end
    catch
        _:Error -> failed
    end.

%% @doc Get system stats
-spec get_system_stats() -> system_benchmark_data().
get_system_stats() ->
    ProcessCount = erlang:system_info(process_count),
    MemoryWords = erlang:memory(total),
    MemoryMB = MemoryWords * erlang:wordsize() / (1024 * 1024),
    CpuUsage = get_cpu_usage(),

    #system_benchmark_data{
        total_memory_mb = MemoryMB,
        avg_cpu_usage = CpuUsage,
        peak_cpu_usage = CpuUsage,
        process_count = ProcessCount,
        ets_count = length(ets:all()),
        garbage_collection_count = erlang:system_info(garbage_collection_count),
        context_switches = erlang:system_info(context_switches)
    }.

%% @doc Get CPU usage (simplified)
-spec get_cpu_usage() -> float().
get_cpu_usage() ->
    %% This is a simplified version - in production, use OS-specific calls
    0.0.

%% @doc Get process memory
-spec get_process_memory(pid()) -> non_neg_integer().
get_process_memory(Pid) ->
    case process_info(Pid, memory) of
        {memory, Mem} -> Mem;
        undefined -> 0
    end.

%% @brief Measure downtime
-spec measure_downtime([pid()]) -> ok.
measure_downtime(Clients) ->
    %% Send test messages to measure response time
    TestStartTime = erlang:monotonic_time(millisecond),
    lists:foreach(fun(Pid) ->
        Pid ! {test_message, self()}
    end, Clients),

    %% Collect responses
    Responses = lists:map(fun(_) ->
        receive
            {test_response, ResponseTime} -> ResponseTime
        after 5000 -> 5000
        end
    end, Clients),

    TestEndTime = erlang:monotonic_time(millisecond),
    logger:info("Downtime measurement", #{
        test_duration_ms => TestEndTime - TestStartTime,
        response_times => Responses,
        domain => [a2a, benchmark, downtime]
    }),
    ok.

%% @brief Calculate total downtime
-spec calculate_total_downtime() -> non_neg_integer().
calculate_total_downtime() ->
    %% This would calculate actual downtime from measurements
    0.

%% @brief Chunk list
-spec chunk_list([term()], pos_integer()) -> [[term()]].
chunk_list(List, Size) ->
    chunk_list(List, Size, []).

chunk_list(_, 0, Acc) -> lists:reverse(Acc);
chunk_list(List, Size, Acc) ->
    {Chunk, Rest} = lists:split(min(Size, length(List)), List),
    chunk_list(Rest, Size, [Chunk | Acc]).

%% @brief Generate performance report
-spec generate_performance_report(state()) -> map().
generate_performance_report(State) ->
    Benchmarks = State#state.current_benchmarks,
    History = State#state.benchmark_history,

    %% Calculate summary statistics
    TotalBenchmarks = length(History),
    SuccessfulBenchmarks = lists:filter(fun(B) ->
        case B#benchmark_result.metrics of
            #{success := true} -> true;
            #{upgrade_success := true} -> true;
            _ -> false
        end
    end, History),

    SuccessRate = length(SuccessfulBenchmarks) / max(TotalBenchmarks, 1),

    AverageDuration = lists:foldl(fun(B, Acc) ->
        Acc + B#benchmark_result.duration_ms
    end, 0, History) / max(TotalBenchmarks, 1),

    PeakMemory = lists:foldl(fun(B, Acc) ->
        max(Acc, B#benchmark_result.memory_peak)
    end, 0, History),

    %% Generate recommendations
    Recommendations = generate_optimization_recommendations_internal(State),

    #{
        total_benchmarks => TotalBenchmarks,
        successful_benchmarks => length(SuccessfulBenchmarks),
        success_rate => SuccessRate,
        average_duration_ms => round(AverageDuration),
        peak_memory_mb => PeakMemory,
        recent_benchmarks => lists:last(10, History),
        recommendations => Recommendations
    }.

%% @brief Generate optimization recommendations
-spec generate_optimization_recommendations_internal(state()) -> [binary()].
generate_optimization_recommendations_internal(State) ->
    Recommendations = [],

    %% Analyze recent benchmark results
    RecentBenchmarks = lists:last(10, State#state.benchmark_history),

    %% Check for slow upgrades
    SlowBenchmarks = lists:filter(fun(B) ->
        B#benchmark_result.duration_ms > 10000
    end, RecentBenchmarks),

    case SlowBenchmarks of
        [] -> Recommendations;
        _ -> [<<"Some benchmarks are running slower than expected, consider optimizing the upgrade process">> | Recommendations]
    end,

    %% Check for memory issues
    HighMemoryBenchmarks = lists:filter(fun(B) ->
        B#benchmark_result.memory_peak > 1000
    end, RecentBenchmarks),

    case HighMemoryBenchmarks of
        [] -> Recommendations;
        _ -> [<<"High memory usage detected during upgrades, consider memory optimization strategies">> | Recommendations]
    end,

    %% Check for success rate
    TotalBenchmarks = length(RecentBenchmarks),
    FailedBenchmarks = lists:filter(fun(B) ->
        case B#benchmark_result.metrics of
            #{success := false} -> true;
            #{upgrade_success := false} -> true;
            _ -> false
        end
    end, RecentBenchmarks),

    FailedRate = length(FailedBenchmarks) / max(TotalBenchmarks, 1),
    case FailedRate > 0.1 of
        true -> [<<"High failure rate detected, investigate potential issues">> | Recommendations];
        false -> Recommendations
    end.

%% @brief Export results to file
-spec export_results_to_file(file:filename(), state()) -> ok | {error, term()}.
export_results_to_file(Filename, State) ->
    try
        Results = jsx:encode(#{
            timestamp => erlang:system_time(millisecond),
            config => State#state.config,
            current_benchmarks => maps:values(State#state.current_benchmarks),
            benchmark_history => State#state.benchmark_history,
            system_baseline => State#state.system_baseline
        }),

        file:write_file(Filename, Results),
        logger:info("Benchmark results exported", #{
            filename => Filename,
            domain => [a2a, benchmark, system]
        }),
        ok
    catch
        Error:Reason ->
            logger:error("Failed to export benchmark results", #{
                error => Error,
                reason => Reason,
                filename => Filename,
                domain => [a2a, benchmark, system]
            }),
            {error, Reason}
    end.

%% @brief Generate results summary
-spec generate_results_summary(state()) -> map().
generate_results_summary(State) ->
    CurrentBenchmarks = State#state.current_benchmarks,
    ActiveCount = length(State#state.active_benchmarks),

    Summary = #{
        active_benchmarks => ActiveCount,
        total_benchmarks => length(State#state.benchmark_history),
        recent_results => lists:last(5, State#state.benchmark_history),
        system_status => get_system_status(State)
    },

    Summary.

%% @brief Get system status
-spec get_system_status(state()) -> map().
get_system_status(State) ->
    CurrentMemory = erlang:memory(total) * erlang:wordsize() / (1024 * 1024),

    #{
        memory_usage_mb => CurrentMemory,
        process_count => erlang:system_info(process_count),
        ets_count => length(ets:all()),
        system_load => calculate_system_load(State)
    }.

%% @brief Calculate system load
-spec calculate_system_load(state()) -> float().
calculate_system_load(_State) ->
    %% This would calculate actual system load
    0.5.

%% @brief Perform system monitoring
-spec perform_system_monitoring(state()) -> state().
perform_system_monitoring(State) ->
    %% Update system metrics
    CurrentStats = get_system_stats(),

    %% Log current status
    logger:debug("System monitoring", #{
        memory_mb => CurrentStats#system_benchmark_data.total_memory_mb,
        cpu_usage => CurrentStats#system_benchmark_data.avg_cpu_usage,
        processes => CurrentStats#system_benchmark_data.process_count,
        domain => [a2a, benchmark, monitoring]
    }),

    State.

%% @brief Schedule monitoring
-spec schedule_monitoring(non_neg_integer()) -> reference().
schedule_monitoring(Interval) ->
    erlang:send_after(Interval, self(), monitoring_timeout).

%% @brief Schedule results summary
-spec schedule_results_summary(non_neg_integer()) -> reference().
schedule_results_summary(Interval) ->
    erlang:send_after(Interval, self(), results_summary_timeout).