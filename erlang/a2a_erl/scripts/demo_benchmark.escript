#!/usr/bin/env escript
%%%-------------------------------------------------------------------
%%% @doc
%%% Y Combinator Benchmark Demo Script
%%%
%%% This script demonstrates the benchmarking capabilities of the
%%% Y Combinator performance testing system.
%%% @end
%%%-------------------------------------------------------------------

-mode(compile).

main(_) ->
    io:format("~n=== Y Combinator Benchmark Demo ===~n~n"),

    %% Add build paths
    EbinDir = filename:absname("_build/default/lib/a2a_erl/ebin"),
    code:add_patha(EbinDir),

    %% Start the combinatoric test server
    io:format("Starting combinatoric test server...~n"),
    {ok, _Pid} = yawl_combinatoric_test:start_link(),
    io:format("[OK] Server started~n~n"),

    %% Define test patterns
    Patterns = [basic_sequential, parallel_split, exclusive_choice, iterative_loop],
    Counts = [10, 50, 100, 500],

    %% Run benchmarks
    io:format("=== Running Scalability Benchmark ===~n"),
    io:format("Patterns: ~p~n~n", [Patterns]),

    io:format("| Count | Generated | Duration (ms) | Throughput (combos/sec) |~n"),
    io:format("|-------|-----------|---------------|--------------------------|~n"),

    Results = lists:map(fun(Count) ->
        erlang:garbage_collect(),
        StartTime = erlang:monotonic_time(microsecond),
        {ok, Combinations} = yawl_combinatoric_test:generate_pattern_combinations(Patterns, Count),
        EndTime = erlang:monotonic_time(microsecond),

        DurationUs = EndTime - StartTime,
        DurationMs = DurationUs / 1000,
        ActualCount = length(Combinations),
        Throughput = case DurationUs > 0 of
            true -> (ActualCount * 1000000) / DurationUs;
            false -> 0
        end,

        io:format("| ~5w | ~9w | ~13.2f | ~24.2f |~n",
                  [Count, ActualCount, DurationMs, Throughput]),

        {Count, ActualCount, DurationMs, Throughput}
    end, Counts),

    %% Calculate summary statistics
    io:format("~n=== Summary Statistics ===~n"),
    Throughputs = [T || {_, _, _, T} <- Results, T > 0],
    case Throughputs of
        [] ->
            io:format("No valid throughput data~n");
        _ ->
            MinThroughput = lists:min(Throughputs),
            MaxThroughput = lists:max(Throughputs),
            AvgThroughput = lists:sum(Throughputs) / length(Throughputs),
            io:format("Min Throughput: ~.2f combos/sec~n", [MinThroughput]),
            io:format("Max Throughput: ~.2f combos/sec~n", [MaxThroughput]),
            io:format("Avg Throughput: ~.2f combos/sec~n", [AvgThroughput])
    end,

    %% Memory usage
    io:format("~n=== Memory Usage ===~n"),
    MemoryTotal = erlang:memory(total),
    MemoryProcesses = erlang:memory(processes),
    MemorySystem = erlang:memory(system),
    io:format("Total Memory: ~p bytes (~.2f MB)~n",
              [MemoryTotal, MemoryTotal / 1024 / 1024]),
    io:format("Process Memory: ~p bytes (~.2f MB)~n",
              [MemoryProcesses, MemoryProcesses / 1024 / 1024]),
    io:format("System Memory: ~p bytes (~.2f MB)~n",
              [MemorySystem, MemorySystem / 1024 / 1024]),

    %% Process count
    ProcessCount = erlang:system_info(process_count),
    io:format("~nActive Processes: ~p~n", [ProcessCount]),

    %% Cleanup
    gen_server:stop(yawl_combinatoric_test),

    io:format("~n=== Benchmark Complete ===~n"),
    io:format("Results stored in: priv/benchmarks.json~n"),
    io:format("Documentation: docs/Y_COMBINATOR_BENCHMARKING.md~n~n"),

    ok.
