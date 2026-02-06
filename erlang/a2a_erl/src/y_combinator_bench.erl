%%%-------------------------------------------------------------------
%%% @doc
%%% Y Combinator Benchmark - Performance Benchmarking for YAWL Combinatoric Testing
%%%
%%% This module provides comprehensive performance benchmarking capabilities
%%% for the YAWL Combinatoric Testing system, measuring combination generation
%%% speed, memory usage, and scalability.
%%%
%%% Usage:
%%%   y_combinator_bench:run_all_benchmarks().
%%%   y_combinator_bench:benchmark_combinations([basic_sequential, parallel_split], 100).
%%%   y_combinator_bench:benchmark_scalability().
%%%   y_combinator_bench:benchmark_patterns().
%%%   y_combinator_bench:compare_results().
%%%   y_combinator_bench:benchmark_metrics().
%%% @end
%%%-------------------------------------------------------------------

-module(y_combinator_bench).
-author("A2A Team").
-export([
    %% Main benchmark functions
    run_all_benchmarks/0,
    run_all_benchmarks/1,
    benchmark_combinations/2,
    benchmark_scalability/0,
    benchmark_patterns/0,
    compare_results/0,
    benchmark_metrics/0,

    %% Detailed benchmark functions
    benchmark_pattern_pair/2,
    benchmark_pattern_triple/3,
    benchmark_memory_usage/1,
    benchmark_cpu_utilization/1,
    benchmark_concurrent_generation/2,

    %% Result storage and retrieval
    store_benchmark_results/2,
    load_benchmark_results/0,
    get_latest_results/0,
    export_results_to_json/0,
    export_results_to_csv/0,

    %% Analysis functions
    calculate_throughput/2,
    calculate_memory_efficiency/2,
    generate_comparison_table/0,
    generate_performance_report/0,
    plot_performance_trend/0
]).

%% Include files
-include_lib("kernel/include/logger.hrl").

%% Type definitions
-type benchmark_result() :: #{
    name := binary(),
    timestamp := integer(),
    duration_ms := number(),
    count := integer(),
    throughput := number(),
    memory_bytes := number(),
    cpu_percent := number(),
    details => map()
}.

-type pattern() :: atom().

%% Benchmark configuration
-define(WARMUP_ITERATIONS, 10).
-define(DEFAULT_SAMPLE_SIZE, 100).
-define(SCALABILITY_LEVELS, [1, 10, 100, 500, 1000]).
-define(BENCHMARK_FILE, "priv/benchmarks.json").
-define(CSV_FILE, "priv/benchmarks.csv").

%%====================================================================
%% Main Benchmark Functions
%%====================================================================

%% @doc Run all benchmarks with default configuration
run_all_benchmarks() ->
    run_all_benchmarks(#{
        sample_size => ?DEFAULT_SAMPLE_SIZE,
        include_patterns => true,
        include_scalability => true,
        include_metrics => true,
        store_results => true
    }).

%% @doc Run all benchmarks with custom configuration
run_all_benchmarks(Config) ->
    ?LOG_INFO("Starting comprehensive benchmark suite"),

    StartTime = erlang:monotonic_time(millisecond),
    Results = #{
        started_at => StartTime,
        config => Config
    },

    %% Warm up the system
    ?LOG_INFO("Warming up system..."),
    warmup_system(),
    ?LOG_INFO("System warmed up"),

    %% Run combination benchmarks
    ?LOG_INFO("Running combination benchmarks..."),
    ComboResults = benchmark_combinations(
        [basic_sequential, parallel_split, exclusive_choice],
        maps:get(sample_size, Config, ?DEFAULT_SAMPLE_SIZE)
    ),

    %% Run pattern benchmarks if configured
    PatternResults = case maps:get(include_patterns, Config, true) of
        true ->
            ?LOG_INFO("Running pattern benchmarks..."),
            benchmark_patterns();
        false ->
            undefined
    end,

    %% Run scalability benchmarks if configured
    ScalabilityResults = case maps:get(include_scalability, Config, true) of
        true ->
            ?LOG_INFO("Running scalability benchmarks..."),
            benchmark_scalability();
        false ->
            undefined
    end,

    %% Run metrics benchmarks if configured
    MetricsResults = case maps:get(include_metrics, Config, true) of
        true ->
            ?LOG_INFO("Running metrics benchmarks..."),
            benchmark_metrics();
        false ->
            undefined
    end,

    EndTime = erlang:monotonic_time(millisecond),
    TotalDuration = EndTime - StartTime,

    FinalResults = Results#{
        combination => ComboResults,
        patterns => PatternResults,
        scalability => ScalabilityResults,
        metrics => MetricsResults,
        total_duration_ms => TotalDuration,
        completed_at => EndTime
    },

    %% Store results if configured
    case maps:get(store_results, Config, true) of
        true ->
            ?LOG_INFO("Storing benchmark results..."),
            store_benchmark_results(comprehensive, FinalResults),
            export_results_to_json(),
            export_results_to_csv();
        false ->
            ok
    end,

    ?LOG_INFO("Benchmark suite completed in ~p ms", [TotalDuration]),
    {ok, FinalResults}.

%% @doc Benchmark combination generation for specific patterns
-spec benchmark_combinations([pattern()], integer()) -> benchmark_result().
benchmark_combinations(Patterns, Count) when is_list(Patterns), is_integer(Count), Count > 0 ->
    ?LOG_INFO("Benchmarking combinations: patterns=~p, count=~p", [Patterns, Count]),

    %% Warmup
    lists:foreach(fun(_) ->
        yawl_combinatoric_test:generate_pattern_combinations(Patterns, min(Count, 10))
    end, lists:seq(1, ?WARMUP_ITERATIONS)),

    %% Force garbage collection before measurement
    erlang:garbage_collect(),
    timer:sleep(100),

    %% Measure memory before
    MemoryBefore = memory_usage(),

    %% Run benchmark
    StartTime = erlang:monotonic_time(millisecond),
    StartTimeCPU = erlang:statistics(runtime),

    Result = yawl_combinatoric_test:generate_pattern_combinations(Patterns, Count),

    EndTime = erlang:monotonic_time(millisecond),
    {_, CPUTime} = erlang:statistics(runtime),

    %% Measure memory after
    MemoryAfter = memory_usage(),

    %% Calculate metrics
    Duration = EndTime - StartTime,
    ActualCount = case Result of
        {ok, Combinations} when is_list(Combinations) -> length(Combinations);
        Combinations when is_list(Combinations) -> length(Combinations);
        _ -> 0
    end,

    Throughput = case Duration > 0 of
        true -> (ActualCount * 1000) / Duration;
        false -> 0
    end,

    MemoryUsed = MemoryAfter - MemoryBefore,
    CPUPercent = case Duration > 0 of
        true -> (CPUTime * 100) / Duration;
        false -> 0
    end,

    BenchmarkResult = #{
        name => list_to_binary(io_lib:format("combo_~p", [Patterns])),
        timestamp => StartTime,
        duration_ms => Duration,
        count => ActualCount,
        throughput => Throughput,
        memory_bytes => MemoryUsed,
        cpu_percent => CPUPercent,
        details => #{
            patterns => Patterns,
            requested_count => Count,
            actual_count => ActualCount
        }
    },

    ?LOG_INFO("Benchmark result: ~p combos in ~p ms (~.2f combos/sec)",
        [ActualCount, Duration, Throughput]),

    BenchmarkResult.

%% @doc Benchmark scalability across different combination counts
-spec benchmark_scalability() -> map().
benchmark_scalability() ->
    ?LOG_INFO("Running scalability benchmark..."),

    Patterns = [basic_sequential, parallel_split, exclusive_choice, iterative_loop],

    Results = lists:map(fun(Count) ->
        ?LOG_INFO("Testing with ~p combinations...", [Count]),
        Result = benchmark_combinations(Patterns, Count),
        {Count, Result}
    end, ?SCALABILITY_LEVELS),

    ScalabilityMap = maps:from_list(Results),

    %% Calculate scalability metrics
    ScalabilityMetrics = calculate_scalability_metrics(ScalabilityMap),

    ?LOG_INFO("Scalability benchmark completed"),

    ScalabilityMap#{
        metrics => ScalabilityMetrics,
        timestamp => erlang:system_time(millisecond)
    }.

%% @doc Benchmark individual pattern types
-spec benchmark_patterns() -> map().
benchmark_patterns() ->
    ?LOG_INFO("Running pattern type benchmarks..."),

    %% Define pattern categories
    PatternCategories = #{
        basic => [basic_sequential, parallel_split, exclusive_choice, simple_merge],
        advanced => [implicit_merge, multiple_merge, deferred_choice, interleaved_routing],
        iteration => [iterative_loop, structured_loop, recursion, multi_instance],
        cancellation => [cancelation_block, cancelation_scope, cancelation_thread]
    },

    Results = maps:map(fun(Category, Patterns) ->
        ?LOG_INFO("Benchmarking ~s patterns...", [Category]),
        benchmark_combinations(Patterns, 50)
    end, PatternCategories),

    %% Benchmark individual pattern performance
    IndividualResults = lists:map(fun(Pattern) ->
        Result = benchmark_pattern_pair(Pattern, Pattern),
        {Pattern, Result}
    end, lists:flatten(maps:values(PatternCategories))),

    ?LOG_INFO("Pattern benchmarks completed"),

    #{
        categories => Results,
        individual => maps:from_list(IndividualResults),
        timestamp => erlang:system_time(millisecond)
    }.

%% @doc Compare results from different benchmark runs
-spec compare_results() -> map().
compare_results() ->
    ?LOG_INFO("Comparing benchmark results..."),

    case load_benchmark_results() of
        {ok, Results} when is_map(Results), map_size(Results) > 0 ->
            %% Get the two most recent results
            SortedResults = lists:sort(
                fun(A, B) ->
                    TsA = maps:get(timestamp, A, 0),
                    TsB = maps:get(timestamp, B, 0),
                    TsA >= TsB
                end,
                maps:values(Results)
            ),

            Comparison = case SortedResults of
                [Latest, Previous | _] ->
                    compare_benchmark_results(Previous, Latest);
                [Latest] ->
                    #{
                        status => single_result,
                        latest => Latest,
                        message => "Only one benchmark result available for comparison"
                    };
                [] ->
                    #{
                        status => no_results,
                        message => "No benchmark results available for comparison"
                    }
            end,

            ComparisonTable = generate_comparison_table(),

            ?LOG_INFO("Comparison completed"),

            #{
                comparison => Comparison,
                table => ComparisonTable,
                timestamp => erlang:system_time(millisecond)
            };
        {error, Reason} ->
            ?LOG_ERROR("Failed to load benchmark results: ~p", [Reason]),
            #{
                status => error,
                reason => Reason,
                timestamp => erlang:system_time(millisecond)
            }
    end.

%% @doc Get comprehensive benchmark metrics
-spec benchmark_metrics() -> map().
benchmark_metrics() ->
    ?LOG_INFO("Collecting benchmark metrics..."),

    %% System metrics
    SystemMetrics = #{
        process_count => erlang:system_info(process_count),
        atom_count => erlang:system_info(atom_count),
        port_count => erlang:system_info(port_count),
        ets_count => length(erlang:registered()) div 10,
        memory_total => erlang:memory(total),
        memory_processes => erlang:memory(processes),
        memory_system => erlang:memory(system),
        memory_atom => erlang:memory(atom),
        memory_binary => erlang:memory(binary),
        memory_ets => erlang:memory(ets)
    },

    %% Performance metrics
    PerfMetrics = calculate_performance_metrics(),

    %% Memory efficiency metrics
    MemoryEfficiency = calculate_memory_efficiency_metrics(),

    %% Throughput metrics
    ThroughputMetrics = calculate_throughput_metrics(),

    ?LOG_INFO("Metrics collection completed"),

    #{
        system => SystemMetrics,
        performance => PerfMetrics,
        memory_efficiency => MemoryEfficiency,
        throughput => ThroughputMetrics,
        timestamp => erlang:system_time(millisecond)
    }.

%%====================================================================
%% Detailed Benchmark Functions
%%====================================================================

%% @doc Benchmark a pair of patterns
-spec benchmark_pattern_pair(pattern(), pattern()) -> benchmark_result().
benchmark_pattern_pair(Pattern1, Pattern2) ->
    benchmark_combinations([Pattern1, Pattern2], 20).

%% @doc Benchmark a triple of patterns
-spec benchmark_pattern_triple(pattern(), pattern(), pattern()) -> benchmark_result().
benchmark_pattern_triple(Pattern1, Pattern2, Pattern3) ->
    benchmark_combinations([Pattern1, Pattern2, Pattern3], 20).

%% @doc Benchmark memory usage for combination generation
-spec benchmark_memory_usage(integer()) -> map().
benchmark_memory_usage(Count) ->
    Patterns = [basic_sequential, parallel_split, exclusive_choice],

    %% Force GC before measurement
    erlang:garbage_collect(),
    MemoryBefore = erlang:memory(total),

    %% Generate combinations
    yawl_combinatoric_test:generate_pattern_combinations(Patterns, Count),

    %% Force GC and measure
    erlang:garbage_collect(),
    MemoryAfter = erlang:memory(total),

    MemoryUsed = MemoryAfter - MemoryBefore,
    PerCombination = case Count > 0 of
        true -> MemoryUsed / Count;
        false -> 0
    end,

    #{
        total_bytes => MemoryUsed,
        per_combination_bytes => PerCombination,
        total_kb => MemoryUsed / 1024,
        per_combination_kb => PerCombination / 1024,
        count => Count
    }.

%% @doc Benchmark CPU utilization for combination generation
-spec benchmark_cpu_utilization(integer()) -> map().
benchmark_cpu_utilization(Count) ->
    Patterns = [basic_sequential, parallel_split],

    %% Get initial CPU stats
    {WallClockBefore, CpuTimeBefore} = get_cpu_stats(),

    %% Generate combinations
    yawl_combinatoric_test:generate_pattern_combinations(Patterns, Count),

    %% Get final CPU stats
    {WallClockAfter, CpuTimeAfter} = get_cpu_stats(),

    WallClockDelta = WallClockAfter - WallClockBefore,
    CpuTimeDelta = CpuTimeAfter - CpuTimeBefore,

    CPUPercent = case WallClockDelta > 0 of
        true -> (CpuTimeDelta * 100) / WallClockDelta;
        false -> 0
    end,

    #{
        cpu_percent => CPUPercent,
        wall_time_ms => WallClockDelta,
        cpu_time_ms => CpuTimeDelta,
        count => Count
    }.

%% @doc Benchmark concurrent combination generation
-spec benchmark_concurrent_generation(integer(), integer()) -> map().
benchmark_concurrent_generation(Count, Workers) ->
    Patterns = [basic_sequential, parallel_split, exclusive_choice],

    StartTime = erlang:monotonic_time(millisecond),

    %% Spawn workers
    Pids = lists:map(fun(_) ->
        spawn_link(fun() ->
            yawl_combinatoric_test:generate_pattern_combinations(Patterns, Count div Workers)
        end)
    end, lists:seq(1, Workers)),

    %% Wait for completion
    Results = [wait_for_completion(Pid) || Pid <- Pids],

    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    TotalCombinations = lists:sum([case R of
        {ok, Combs} when is_list(Combs) -> length(Combs);
        Combs when is_list(Combs) -> length(Combs);
        _ -> 0
    end || R <- Results]),

    Throughput = case Duration > 0 of
        true -> (TotalCombinations * 1000) / Duration;
        false -> 0
    end,

    #{
        workers => Workers,
        total_combinations => TotalCombinations,
        duration_ms => Duration,
        throughput => Throughput,
        results => Results
    }.

%%====================================================================
%% Result Storage and Retrieval
%%====================================================================

%% @doc Store benchmark results to file
-spec store_benchmark_results(atom(), map()) -> ok | {error, term()}.
store_benchmark_results(Type, Results) ->
    FilePath = filename:join([code:priv_dir(a2a_erl), "benchmarks.json"]),

    %% Load existing results
    ExistingResults = case file:read_file(FilePath) of
        {ok, Binary} ->
            case json:decode(Binary) of
                {ok, Data} when is_map(Data) -> Data;
                _ -> #{}
            end;
        {error, enoent} ->
            #{};
        _ ->
            #{}
    end,

    %% Create new entry
    Timestamp = erlang:system_time(millisecond),
    Key = list_to_binary(io_lib:format("~s_~p", [Type, Timestamp])),

    UpdatedResults = ExistingResults#{Key => Results#{
        stored_at => Timestamp,
        type => Type
    }},

    %% Write back to file
    case filelib:ensure_dir(FilePath) of
        ok ->
            case json:encode(UpdatedResults) of
                {ok, JSONBinary} ->
                    file:write_file(FilePath, JSONBinary);
                {error, Reason} ->
                    {error, {encode_error, Reason}}
            end;
        {error, Reason} ->
            {error, {dir_error, Reason}}
    end.

%% @doc Load benchmark results from file
-spec load_benchmark_results() -> {ok, map()} | {error, term()}.
load_benchmark_results() ->
    FilePath = filename:join([code:priv_dir(a2a_erl), "benchmarks.json"]),

    case file:read_file(FilePath) of
        {ok, Binary} ->
            case json:decode(Binary) of
                {ok, Data} when is_map(Data) ->
                    {ok, Data};
                {error, Reason} ->
                    {error, {decode_error, Reason}}
            end;
        {error, Reason} ->
            {error, {file_error, Reason}}
    end.

%% @doc Get the most recent benchmark results
-spec get_latest_results() -> {ok, map()} | {error, term()}.
get_latest_results() ->
    case load_benchmark_results() of
        {ok, Results} when is_map(Results) ->
            %% Find the most recent entry
            SortedKeys = lists:sort(fun(A, B) -> A > B end, maps:keys(Results)),
            case SortedKeys of
                [LatestKey | _] ->
                    {ok, maps:get(LatestKey, Results)};
                [] ->
                    {error, no_results}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Export results to JSON format
-spec export_results_to_json() -> ok | {error, term()}.
export_results_to_json() ->
    case load_benchmark_results() of
        {ok, Results} ->
            FilePath = filename:join([code:priv_dir(a2a_erl), "benchmarks_export.json"]),
            case json:encode(Results) of
                {ok, JSON} ->
                    file:write_file(FilePath, JSON);
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Export results to CSV format
-spec export_results_to_csv() -> ok | {error, term()}.
export_results_to_csv() ->
    case load_benchmark_results() of
        {ok, Results} ->
            CSVContent = generate_csv_content(Results),
            FilePath = filename:join([code:priv_dir(a2a_erl), "benchmarks.csv"]),
            file:write_file(FilePath, CSVContent);
        {error, Reason} ->
            {error, Reason}
    end.

%%====================================================================
%% Analysis Functions
%%====================================================================

%% @doc Calculate throughput (combinations per second)
-spec calculate_throughput(integer(), number()) -> float().
calculate_throughput(Count, DurationMs) when DurationMs > 0 ->
    (Count * 1000) / DurationMs;
calculate_throughput(_, _) ->
    0.0.

%% @doc Calculate memory efficiency
-spec calculate_memory_efficiency(integer(), number()) -> float().
calculate_memory_efficiency(Count, MemoryBytes) when Count > 0 ->
    MemoryBytes / Count;
calculate_memory_efficiency(_, _) ->
    0.0.

%% @doc Generate comparison table of benchmark results
-spec generate_comparison_table() -> binary().
generate_comparison_table() ->
    case load_benchmark_results() of
        {ok, Results} when is_map(Results) ->
            %% Generate table header
            Header = "| Benchmark | Count | Duration (ms) | Throughput (combos/sec) | Memory (bytes) | CPU (%) |\n"
                      "|-----------|-------|--------------|-------------------------|----------------|----------|\n",

            %% Generate table rows
            Rows = lists:map(fun({_Key, Result}) ->
                Name = maps:get(name, Result, <<"unknown">>),
                Count = maps:get(count, Result, 0),
                Duration = maps:get(duration_ms, Result, 0),
                Throughput = maps:get(throughput, Result, 0),
                Memory = maps:get(memory_bytes, Result, 0),
                CPU = maps:get(cpu_percent, Result, 0),

                io_lib:format("| ~s | ~p | ~.2f | ~.2f | ~p | ~.2f |~n",
                    [Name, Count, Duration, Throughput, Memory, CPU])
            end, maps:to_list(Results)),

            list_to_binary(Header ++ Rows);
        {error, _} ->
            <<"| Error loading benchmark results |">>
    end.

%% @doc Generate comprehensive performance report
-spec generate_performance_report() -> binary().
generate_performance_report() ->
    case get_latest_results() of
        {ok, Results} ->
            Report = io_lib:format(
                "=== Y Combinator Benchmark Performance Report ===~n"
                "Generated: ~s~n~n"
                "=== Summary ===~n"
                "Total Duration: ~p ms~n"
                "Combinations Generated: ~p~n"
                "Average Throughput: ~.2f combos/sec~n"
                "Memory Used: ~p bytes~n"
                "CPU Utilization: ~.2f%~n~n"
                "=== Detailed Results ===~n"
                "~p~n",
                [
                    format_timestamp(maps:get(timestamp, Results, 0)),
                    maps:get(duration_ms, Results, 0),
                    maps:get(count, Results, 0),
                    maps:get(throughput, Results, 0),
                    maps:get(memory_bytes, Results, 0),
                    maps:get(cpu_percent, Results, 0),
                    Results
                ]
            ),
            list_to_binary(Report);
        {error, Reason} ->
            list_to_binary(io_lib:format("Error generating report: ~p~n", [Reason]))
    end.

%% @doc Plot performance trend (basic ASCII representation)
-spec plot_performance_trend() -> binary().
plot_performance_trend() ->
    case load_benchmark_results() of
        {ok, Results} when is_map(Results) ->
            %% Sort by timestamp
            SortedResults = lists:sort(fun(A, B) ->
                maps:get(timestamp, A, 0) =< maps:get(timestamp, B, 0)
            end, maps:values(Results)),

            %% Generate throughput trend
            Throughputs = [maps:get(throughput, R, 0) || R <- SortedResults],
            MaxThroughput = case Throughputs of
                [] -> 1;
                _ -> lists:max(Throughputs)
            end,

            Trend = lists:map(fun(Throughput) ->
                Bars = round((Throughput / MaxThroughput) * 40),
                io_lib:format("~.2f combos/sec |~s|~n", [Throughput, lists:duplicate(Bars, $=)])
            end, Throughputs),

            list_to_binary(
                "=== Throughput Trend ===\n"
                "40 bars = maximum throughput\n\n"
                ++ Trend
            );
        _ ->
            <<"No data available for trend plot">>
    end.

%%====================================================================
%% Internal Helper Functions
%%====================================================================

%% @private Warm up the system before benchmarking
warmup_system() ->
    Patterns = [basic_sequential, parallel_split],
    lists:foreach(fun(_) ->
        yawl_combinatoric_test:generate_pattern_combinations(Patterns, 5)
    end, lists:seq(1, ?WARMUP_ITERATIONS)).

%% @private Get current memory usage
memory_usage() ->
    erlang:memory(total).

%% @private Get CPU statistics
get_cpu_stats() ->
    WallClock = erlang:monotonic_time(millisecond),
    {CpuTime, _} = erlang:statistics(runtime),
    {WallClock, CpuTime}.

%% @private Wait for process completion
wait_for_completion(Pid) ->
    MonitorRef = erlang:monitor(process, Pid),
    receive
        {'DOWN', MonitorRef, process, Pid, _Reason} ->
            timeout
    after 30000 ->
        erlang:demonitor(MonitorRef, [flush]),
        timeout
    end.

%% @private Calculate scalability metrics
calculate_scalability_metrics(Results) ->
    %% Extract counts and durations
    DataPoints = lists:map(fun({Count, Result}) ->
        Duration = maps:get(duration_ms, Result, 1),
        Throughput = maps:get(throughput, Result, 0),
        {Count, Duration, Throughput}
    end, maps:to_list(Results)),

    %% Calculate scaling factor (how duration scales with count)
    ScalingFactors = case DataPoints of
        [{C1, D1, _}, {C2, D2, _} | _] when C2 > C1, D1 > 0 ->
            (D2 / C2) / (D1 / C1);
        _ ->
            1.0
    end,

    #{
        scaling_factor => ScalingFactors,
        linear_scaling => abs(ScalingFactors - 1.0) < 0.2,
        data_points => DataPoints
    }.

%% @private Calculate performance metrics
calculate_performance_metrics() ->
    %% Measure actual combination generation time
    Patterns = [basic_sequential, parallel_split, exclusive_choice],
    Count = 100,

    StartTime = erlang:monotonic_time(microsecond),
    {ok, Combinations} = yawl_combinatoric_test:generate_pattern_combinations(Patterns, Count),
    EndTime = erlang:monotonic_time(microsecond),

    DurationUs = EndTime - StartTime,
    DurationMs = DurationUs / 1000,
    ActualCount = length(Combinations),

    #{
        avg_duration_us => DurationUs / ActualCount,
        avg_duration_ms => DurationMs / ActualCount,
        total_duration_ms => DurationMs,
        combinations => ActualCount,
        operations_per_second => (ActualCount * 1000000) / DurationUs
    }.

%% @private Calculate memory efficiency metrics
calculate_memory_efficiency_metrics() ->
    %% Test memory efficiency at different scales
    Scales = [10, 50, 100, 500],
    MemoryData = lists:map(fun(Count) ->
        benchmark_memory_usage(Count)
    end, Scales),

    %% Calculate average memory per combination
    AvgMemory = lists:avg([maps:get(per_combination_bytes, M, 0) || M <- MemoryData]),

    #{
        avg_bytes_per_combination => AvgMemory,
        avg_kb_per_combination => AvgMemory / 1024,
        memory_data => MemoryData
    }.

%% @private Calculate throughput metrics
calculate_throughput_metrics() ->
    %% Measure throughput at different scales
    Scales = [10, 50, 100, 500],
    ThroughputData = lists:map(fun(Count) ->
        Result = benchmark_combinations([basic_sequential, parallel_split], Count),
        maps:get(throughput, Result, 0)
    end, Scales),

    #{
        min_throughput => lists:min(ThroughputData),
        max_throughput => lists:max(ThroughputData),
        avg_throughput => lists:sum(ThroughputData) / length(ThroughputData),
        throughput_data => ThroughputData
    }.

%% @private Compare two benchmark results
compare_benchmark_results(Previous, Latest) ->
    PrevDuration = maps:get(duration_ms, Previous, 1),
    LatestDuration = maps:get(duration_ms, Latest, 1),
    PrevThroughput = maps:get(throughput, Previous, 0),
    LatestThroughput = maps:get(throughput, Latest, 0),

    DurationChange = ((LatestDuration - PrevDuration) / PrevDuration) * 100,
    ThroughputChange = ((LatestThroughput - PrevThroughput) / PrevThroughput) * 100,

    #{
        duration_change_percent => DurationChange,
        throughput_change_percent => ThroughputChange,
        improvement => DurationChange < 0,
        previous => Previous,
        latest => Latest
    }.

%% @private Generate CSV content from results
generate_csv_content(Results) ->
    %% CSV header
    Header = "Benchmark,Count,Duration_ms,Throughput,Memory_Bytes,CPU_Percent,Timestamp\n",

    %% CSV rows
    Rows = lists:map(fun({_Key, Result}) ->
        Name = maps:get(name, Result, "unknown"),
        Count = maps:get(count, Result, 0),
        Duration = maps:get(duration_ms, Result, 0),
        Throughput = maps:get(throughput, Result, 0),
        Memory = maps:get(memory_bytes, Result, 0),
        CPU = maps:get(cpu_percent, Result, 0),
        Timestamp = maps:get(timestamp, Result, 0),

        io_lib:format("~s,~p,~.2f,~.2f,~p,~.2f,~p~n",
            [Name, Count, Duration, Throughput, Memory, CPU, Timestamp])
    end, maps:to_list(Results)),

    list_to_binary(Header ++ Rows).

%% @private Format timestamp for display
format_timestamp(Timestamp) when is_integer(Timestamp) ->
    {{Y, M, D}, {H, Min, S}} = calendar:system_time_to_universal_time(Timestamp, milliseconds),
    io_lib:format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B UTC", [Y, M, D, H, Min, S]).
