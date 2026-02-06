%%%-------------------------------------------------------------------
%%% @doc
%%% Y Combinator Demo - YAWL Combinatoric Testing Demo Entry Point
%%%
%%% This module provides an interactive demo for the YAWL Combinatoric Testing
%%% system, designed for live demonstrations to stakeholders.
%%%
%%% Usage:
%%%   y_combinator_demo:start().         % Start demo server
%%%   y_combinator_demo:quick_demo().    % 30-second quick demo
%%%   y_combinator_demo:medium_demo().   % 2-minute medium demo
%%%   y_combinator_demo:full_demo().     % Full demo with all patterns
%%%   y_combinator_demo:interactive().   % Interactive mode
%%% @end
%%%-------------------------------------------------------------------

-module(y_combinator_demo).
-author("A2A Team").
-export([
    start/0,
    stop/0,
    quick_demo/0,
    medium_demo/0,
    full_demo/0,
    interactive/0,
    run_demo/1,
    run_scenario/1,
    list_scenarios/0,
    demo_status/0,
    show_patterns/0,
    %% Telemetry exports
    show_dashboard/0,
    export_logs/0,
    get_log_summary/0,
    reset_metrics/0
]).

%% ANSI Color codes
-define(RESET, "\e[0m").
-define(BOLD, "\e[1m").
-define(DIM, "\e[2m").
-define(RED, "\e[31m").
-define(GREEN, "\e[32m").
-define(YELLOW, "\e[33m").
-define(BLUE, "\e[34m").
-define(MAGENTA, "\e[35m").
-define(CYAN, "\e[36m").
-define(WHITE, "\e[37m").
-define(BRIGHT_RED, "\e[91m").
-define(BRIGHT_GREEN, "\e[92m").
-define(BRIGHT_YELLOW, "\e[93m").
-define(BRIGHT_BLUE, "\e[94m").
-define(BRIGHT_MAGENTA, "\e[95m").
-define(BRIGHT_CYAN, "\e[96m").

%% Progress bar characters
-define(PROGRESS_FULL, "=").
-define(PROGRESS_HEAD, ">").
-define(PROGRESS_EMPTY, " ").
-define(PROGRESS_WIDTH, 40).

-define(DEMO_SERVER, yawl_combinatoric_test).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the demo server and all dependencies
start() ->
    io:format("~n~s=== Y Combinator Demo: YAWL Combinatoric Testing ===~s~n~n", [?BRIGHT_CYAN, ?RESET]),
    color_print(info, "Starting demo server..."),

    case ensure_started() of
        {ok, _} ->
            color_print(success, "[OK] Demo server started successfully"),
            io:format("~n~sAvailable commands:~s~n", [?BOLD, ?RESET]),
            io:format("  ~squick_demo()~s    - Quick 30-second demo~n", [?BRIGHT_GREEN, ?RESET]),
            io:format("  ~smedium_demo()~s   - 2-minute medium demo~n", [?BRIGHT_YELLOW, ?RESET]),
            io:format("  ~sfull_demo()~s     - Full demo with all 43 patterns~n", [?BRIGHT_RED, ?RESET]),
            io:format("  ~sinteractive()~s   - Interactive demo mode~n", [?BRIGHT_BLUE, ?RESET]),
            io:format("  ~sshow_patterns()~s - List all available patterns~n", [?BRIGHT_MAGENTA, ?RESET]),
            io:format("  ~sstop()~s          - Stop demo server~n~n", [?BRIGHT_CYAN, ?RESET]),
            {ok, started};
        {error, Reason} ->
            color_print(error, "[ERROR] Failed to start: ~p", [Reason]),
            {error, Reason}
    end.

%% @doc Stop the demo server
stop() ->
    io:format("~n"),
    color_print(info, "Stopping demo server..."),
    case whereis(?DEMO_SERVER) of
        undefined ->
            color_print(info, "[INFO] Demo server not running"),
            ok;
        _Pid ->
            gen_server:stop(?DEMO_SERVER),
            color_print(success, "[OK] Demo server stopped"),
            ok
    end.

%% @doc Quick demo - 2 patterns, 4 combinations (30 seconds)
quick_demo() ->
    io:format("~n~s=== Quick Demo (30 seconds) ===~s~n~n", [?BRIGHT_GREEN, ?RESET]),
    Patterns = [basic_sequential, parallel_split],
    run_combinations(Patterns, 2, "Quick Demo").

%% @doc Medium demo - 5 patterns, 10 combinations (2 minutes)
medium_demo() ->
    io:format("~n~s=== Medium Demo (2 minutes) ===~s~n~n", [?BRIGHT_YELLOW, ?RESET]),
    Patterns = [basic_sequential, parallel_split, exclusive_choice,
                iterative_loop, multi_instance],
    run_combinations(Patterns, 5, "Medium Demo").

%% @doc Full demo - All 43 patterns, 500+ combinations (10 minutes)
full_demo() ->
    io:format("~n~s=== Full Demo (All Patterns) ===~s~n~n", [?BRIGHT_RED, ?RESET]),
    Patterns = get_all_patterns(),
    run_combinations(Patterns, 20, "Full Demo").

%% @doc Interactive demo mode
interactive() ->
    io:format("~n~s=== Interactive Demo Mode ===~s~n~n", [?BRIGHT_BLUE, ?RESET]),
    color_print(info, "Select a demo scenario:"),
    io:format("  ~s1~s. Quick (30s)  - 2 patterns, basic test~n", [?BRIGHT_GREEN, ?RESET]),
    io:format("  ~s2~s. Medium (2m)  - 5 patterns, mixed test~n", [?BRIGHT_YELLOW, ?RESET]),
    io:format("  ~s3~s. Full (10m)   - All 43 patterns, comprehensive~n", [?BRIGHT_RED, ?RESET]),
    io:format("  ~s4~s. Custom       - Choose your own patterns~n", [?BRIGHT_CYAN, ?RESET]),
    io:format("  ~s5~s. Status       - Show current demo status~n", [?BRIGHT_MAGENTA, ?RESET]),
    io:format("  ~s6~s. Patterns     - List all available patterns~n", [?WHITE, ?RESET]),
    io:format("  ~s0~s. Exit~n~n", [?BRIGHT_RED, ?RESET]),
    io:format("Choice: "),

    case io:get_line("") of
        "1\n" -> quick_demo(), continue_interactive();
        "2\n" -> medium_demo(), continue_interactive();
        "3\n" -> full_demo(), continue_interactive();
        "4\n" -> custom_demo(), continue_interactive();
        "5\n" -> demo_status(), continue_interactive();
        "6\n" -> show_patterns(), continue_interactive();
        "0\n" -> color_print(info, "~nExiting interactive mode."), ok;
        _ -> color_print(warning, "Invalid choice."), interactive()
    end.

%% @doc Run a specific demo scenario
run_demo(Scenario) when is_atom(Scenario) ->
    case Scenario of
        quick -> quick_demo();
        medium -> medium_demo();
        full -> full_demo();
        _ -> color_print(error, "Unknown scenario: ~p", [Scenario])
    end;
run_demo(ScenarioConfig) when is_map(ScenarioConfig) ->
    Patterns = maps:get(patterns, ScenarioConfig, [basic_sequential]),
    Count = maps:get(count, ScenarioConfig, 5),
    Name = maps:get(name, ScenarioConfig, "Custom Demo"),
    run_combinations(Patterns, Count, Name).

%% @doc Get current demo status
demo_status() ->
    io:format("~n~s=== Demo Status ===~s~n~n", [?BRIGHT_CYAN, ?RESET]),
    case whereis(?DEMO_SERVER) of
        undefined ->
            color_print(warning, "Demo Server: [STOPPED]"),
            color_print(info, "Run start() to begin.");
        Pid ->
            color_print(success, "Demo Server: [RUNNING]"),
            io:format("~sPID:~s ~p~n", [?DIM, ?RESET, [Pid]]),
            case gen_server:call(?DEMO_SERVER, get_status, 2000) of
                {ok, Status} ->
                    Active = maps:get(active_tests, Status, 0),
                    Completed = maps:get(completed, Status, 0),
                    Failed = maps:get(failed, Status, 0),
                    io:format("~sActive Tests:~s ~p~n", [?BOLD, ?RESET, Active]),
                    io:format("~sCompleted:~s ~p~n", [?GREEN, ?RESET, Completed]),
                    io:format("~sFailed:~s ~p~n", [?RED, ?RESET, Failed]);
                _ ->
                    color_print(warning, "Status: Query timeout (server busy)")
            end
    end,
    io:format("~n").

%% @doc Show all available YAWL patterns
show_patterns() ->
    io:format("~n~s=== Available YAWL Patterns (43 total) ===~s~n~n", [?BRIGHT_CYAN, ?RESET]),
    Patterns = get_all_patterns(),

    io:format("~sBasic Control Flow (5):~s~n", [?BOLD, ?RESET]),
    Basic = [basic_sequential, parallel_split, parallel_join,
             exclusive_choice, simple_merge],
    lists:foreach(fun(P) -> io:format("  ~s-~s ~p~n", [?GREEN, ?RESET, [P]]) end, Basic),

    io:format("~n~sAdvanced Control Flow (8):~s~n", [?BOLD, ?RESET]),
    Advanced = [implicit_merge, multiple_merge, deferred_choice,
                interleaved_routing, milestone, discriminator,
                n_out_of_m, arbitrary_cycle],
    lists:foreach(fun(P) -> io:format("  ~s-~s ~p~n", [?YELLOW, ?RESET, [P]]) end, Advanced),

    io:format("~n~sIteration Patterns (6):~s~n", [?BOLD, ?RESET]),
    Iteration = [iterative_loop, structured_loop, recursion,
                  multi_instance, sequential_multi_instance,
                  parallel_multi_instance],
    lists:foreach(fun(P) -> io:format("  ~s-~s ~p~n", [?BRIGHT_BLUE, ?RESET, [P]]) end, Iteration),

    io:format("~n~sCancellation Patterns (17):~s~n", [?BOLD, ?RESET]),
    Cancellation = [cancelation_block, cancelation_scope,
                    cancelation_thread, cancelation_subprocess,
                    cancelation_multiple_instances, cancelation_point,
                    cancelation_end, cancelation_cancel,
                    cancelation_thread_after, cancelation_subprocess_after,
                    cancelation_multiple_instances_after,
                    cancelation_thread_or, cancelation_subprocess_or,
                    cancelation_multiple_instances_or,
                    cancelation_thread_and, cancelation_subprocess_and,
                    cancelation_multiple_instances_and],
    lists:foreach(fun(P) -> io:format("  ~s-~s ~p~n", [?RED, ?RESET, [P]]) end, Cancellation),

    io:format("~n~sOther Patterns (7):~s~n", [?BOLD, ?RESET]),
    Others = Patterns -- Basic -- Advanced -- Iteration -- Cancellation,
    lists:foreach(fun(P) -> io:format("  ~s-~s ~p~n", [?CYAN, ?RESET, [P]]) end, Others),

    io:format("~n~sTotal:~s ~p patterns~n~n", [?BOLD, ?RESET, length(Patterns)]),
    ok.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private Ensure demo server and dependencies are started
ensure_started() ->
    %% Start YAWL orchestrator if needed
    case whereis(yawl_orchestrator) of
        undefined ->
            application:ensure_all_started(a2a_erl);
        _ ->
            ok
    end,

    %% Start combinatoric test server
    case whereis(?DEMO_SERVER) of
        undefined ->
            yawl_combinatoric_test:start_link();
        _ ->
            {ok, already_started}
    end.

%% @private Run pattern combinations with progress display
run_combinations(Patterns, Count, DemoName) ->
    ensure_started(),

    %% Log demo start
    y_combinator_logger:log_demo_started(DemoName, Patterns),

    io:format("~sDemo:~s ~s~n", [?BOLD, ?RESET, [DemoName]]),
    io:format("~sPatterns:~s ~p~n", [?DIM, ?RESET, [Patterns]]),
    io:format("~sTarget combinations:~s ~p~n~n", [?DIM, ?RESET, [Count]]),

    color_print(info, "Generating combinations..."),
    io:format("~n"),

    StartTime = erlang:monotonic_time(millisecond),

    Result = case catch yawl_combinatoric_test:generate_pattern_combinations(Patterns, Count) of
        {'EXIT', Reason} ->
            io:format("~n"),
            color_print(error, "Generation failed: ~p", [Reason]),
            y_combinator_logger:log_event(error, demo, <<"Demo failed">>, #{reason => Reason}),
            {error, Reason};
        {ok, Combinations} ->
            Duration = erlang:monotonic_time(millisecond) - StartTime,
            io:format("~n"),
            y_combinator_logger:log_demo_completed(DemoName, length(Combinations), Duration),
            display_results(Combinations, Duration, DemoName);
        Combinations when is_list(Combinations) ->
            Duration = erlang:monotonic_time(millisecond) - StartTime,
            io:format("~n"),
            y_combinator_logger:log_demo_completed(DemoName, length(Combinations), Duration),
            display_results(Combinations, Duration, DemoName)
    end,

    Result.

%% @private Display test results with formatting
display_results(Combinations, Duration, DemoName) ->
    Count = length(Combinations),
    Pass = length([C || C <- Combinations, is_map(C) andalso maps:get(status, C, pass) =:= pass]),
    Fail = Count - Pass,
    PassRate = if Count > 0 -> (Pass * 100) div Count; true -> 0 end,

    io:format("~n~s=== Results: ~s ===~s~n~n", [?BRIGHT_CYAN, [DemoName], ?RESET]),

    %% Summary statistics with visual indicators
    display_summary(Count, Pass, Fail, PassRate, Duration),

    %% Display combinations table
    if
        Count > 0 andalso Count =< 50 ->
            io:format("~n~sGenerated Combinations:~s~n", [?BOLD, ?RESET]),
            display_combinations_table(Combinations);
        Count > 50 ->
            io:format("~n~sFirst 20 combinations:~s~n", [?DIM, ?RESET]),
            {First, _} = lists:split(20, Combinations),
            display_combinations_table(First),
            color_print(info, "... and ~p more combinations", [Count - 20]);
        true ->
            color_print(warning, "No combinations generated")
    end,

    %% Final status with visual indicator
    if
        Fail =:= 0 andalso Count > 0 ->
            color_print(success, "~n[SUCCESS] All ~p combinations generated!", [Count]);
        Fail > 0 ->
            color_print(error, "~n[WARNING] ~p of ~p combinations failed", [Fail, Count]);
        true ->
            color_print(warning, "~nNo combinations generated")
    end,

    io:format("~nDemo completed.~n~n"),
    {ok, #{count => Count, pass => Pass, fail => Fail, duration => Duration}}.

%% @private Continue interactive mode after action
continue_interactive() ->
    io:format("~nPress Enter to continue or 'q' to quit: "),
    case io:get_line("") of
        "q\n" -> color_print(info, "~nExiting interactive mode."), ok;
        "\n" -> interactive();
        _ -> interactive()
    end.

%% @private Custom pattern demo
custom_demo() ->
    io:format("~nEnter patterns (comma-separated): "),
    Input = io:get_line(""),
    PatternsStr = string:trim(Input, trailing, "\n"),
    PatternAtoms = [list_to_existing_atom(string:trim(P)) ||
                    P <- string:split(PatternsStr, ",", all)],
    io:format("~nEnter number of combinations: "),
    CountInput = io:get_line(""),
    Count = case string:to_integer(string:trim(CountInput, trailing, "\n")) of
        {N, _} when N > 0 -> N;
        _ -> 5
    end,
    run_combinations(PatternAtoms, Count, "Custom Demo").

%% @doc Run a predefined business scenario
run_scenario(ScenarioName) when is_atom(ScenarioName) ->
    case y_demo_scenarios:validate_scenario(ScenarioName) of
        {ok, valid} ->
            color_print(info, "Running scenario: ~p", [ScenarioName]),
            y_demo_scenarios:run_scenario(ScenarioName);
        {error, Reason} ->
            color_print(error, "Cannot run scenario: ~p", [Reason]),
            io:format("~nAvailable scenarios:~n"),
            list_scenarios(),
            {error, Reason}
    end.

%% @doc List all available business scenarios
list_scenarios() ->
    io:format("~n~s=== YAWL Demo Scenarios ===~s~n~n", [?BRIGHT_CYAN, ?RESET]),
    y_demo_scenarios:list_scenarios(),
    io:format("~nUsage:~n  ~sy_combinator_demo:run_scenario(order_processing).~s~n",
              [?BRIGHT_GREEN, ?RESET]),
    io:format("  ~sy_combinator_demo:run_scenario(document_approval).~s~n",
              [?BRIGHT_YELLOW, ?RESET]),
    io:format("  ~sy_combinator_demo:run_scenario(data_pipeline).~s~n",
              [?BRIGHT_BLUE, ?RESET]),
    io:format("  ~sy_combinator_demo:run_scenario(financial_audit).~s~n~n",
              [?BRIGHT_MAGENTA, ?RESET]),
    ok.

%% @private Get all available YAWL patterns
get_all_patterns() ->
    [
        basic_sequential,
        parallel_split,
        parallel_join,
        exclusive_choice,
        simple_merge,
        iterative_loop,
        multi_instance,
        interleaved_parallelism,
        implicit_merge,
        multiple_merge,
        deferred_choice,
        interleaved_routing,
        milestone,
        cancelation_block,
        cancelation_scope,
        cancelation_thread,
        cancelation_subprocess,
        cancelation_multiple_instances,
        cancelation_point,
        cancelation_end,
        cancelation_cancel,
        cancelation_thread_after,
        cancelation_subprocess_after,
        cancelation_multiple_instances_after,
        cancelation_thread_or,
        cancelation_subprocess_or,
        cancelation_multiple_instances_or,
        cancelation_thread_and,
        cancelation_subprocess_and,
        cancelation_multiple_instances_and,
        discriminator,
        n_out_of_m,
        arbitrary_cycle,
        structured_loop,
        recursion,
        sequential_multi_instance,
        parallel_multi_instance,
        critical_section,
        multiple_instances_with_prior_knowledge,
        static_partial_join,
        dynamic_partial_join,
        blocking_pattern,
        forced_execution,
        strict_sequence
    ].

%%====================================================================
%% Telemetry and Logging Functions
%%====================================================================

%% @doc Show the metrics dashboard
show_dashboard() ->
    y_combinator_logger:metrics_dashboard().

%% @doc Export logs to JSON file
export_logs() ->
    case y_combinator_logger:export_logs(json) of
        {ok, Filename} ->
            io:format("~nLogs exported to: ~s~n", [Filename]),
            ok;
        {error, Reason} ->
            io:format("~nFailed to export logs: ~p~n", [Reason]),
            {error, Reason}
    end.

%% @doc Get log summary statistics
get_log_summary() ->
    case y_combinator_logger:get_log_summary() of
        {ok, Summary} ->
            io:format("~n~s=== Log Summary ===~s~n", [?BRIGHT_CYAN, ?RESET]),
            io:format("Total Entries: ~p~n", [maps_get(total_entries, Summary, 0)]),
            io:format("~nBy Level:~n", []),
            display_by_level(maps_get(by_level, Summary, #{})),
            io:format("~nBy Type:~n", []),
            display_by_type(maps_get(by_type, Summary, #{})),
            io:format("~n"),
            ok;
        {error, Reason} ->
            io:format("Failed to get log summary: ~p~n", [Reason]),
            {error, Reason}
    end.

%% @doc Reset all metrics
reset_metrics() ->
    y_combinator_logger:reset_metrics(),
    color_print(info, "Metrics reset successfully."),
    ok.

%% @private Display by level statistics
display_by_level(Levels) when is_map(Levels) ->
    maps:foreach(fun(Level, Count) ->
        io:format("  ~p: ~p~n", [Level, Count])
    end, Levels);
display_by_level(_) ->
    ok.

%% @private Display by type statistics
display_by_type(Types) when is_map(Types) ->
    maps:foreach(fun(Type, Count) ->
        io:format("  ~p: ~p~n", [Type, Count])
    end, Types);
display_by_type(_) ->
    ok.

%% @private Safe maps get
maps_get(Key, Map, Default) ->
    case maps:get(Key, Map, Default) of
        undefined -> Default;
        Value -> Value
    end.

%% @private Color print helper for different message types
color_print(success, Format) ->
    io:format("~s" ++ Format ++ "~s~n", [?BRIGHT_GREEN, ?RESET]);
color_print(success, Format, Args) ->
    io:format("~s" ++ Format ++ "~s~n", [?BRIGHT_GREEN, Args, ?RESET]);

color_print(error, Format) ->
    io:format("~s" ++ Format ++ "~s~n", [?BRIGHT_RED, ?RESET]);
color_print(error, Format, Args) ->
    io:format("~s" ++ Format ++ "~s~n", [?BRIGHT_RED, Args, ?RESET]);

color_print(warning, Format) ->
    io:format("~s" ++ Format ++ "~s~n", [?BRIGHT_YELLOW, ?RESET]);
color_print(warning, Format, Args) ->
    io:format("~s" ++ Format ++ "~s~n", [?BRIGHT_YELLOW, Args, ?RESET]);

color_print(info, Format) ->
    io:format("~s" ++ Format ++ "~s~n", [?BRIGHT_CYAN, ?RESET]);
color_print(info, Format, Args) ->
    io:format("~s" ++ Format ++ "~s~n", [?BRIGHT_CYAN, Args, ?RESET]).

%% @private Display summary statistics with visual indicators
display_summary(Count, Pass, Fail, PassRate, Duration) ->
    %% Calculate average time per combination
    AvgTime = if Count > 0 -> Duration / Count; true -> 0 end,

    %% Display statistics in a box
    io:format("┌─ ~sStatistics~s ─────────────────────────────────┐~n", [?BOLD, ?RESET]),
    io:format("│ ~sTotal Combinations:~s   ~4w~n", [?CYAN, ?RESET, [Count]]),
    io:format("│ ~sPassed:~s               ~4w ~s(~w%)~s~n", [?GREEN, ?RESET, [Pass], [?DIM, [PassRate], ?RESET]]),
    io:format("│ ~sFailed:~s               ~4w~n", [?RED, ?RESET, [Fail]]),
    io:format("│                                              │~n"),
    io:format("│ ~sTotal Duration:~s        ~w ms~n", [?BLUE, ?RESET, [Duration]]),
    io:format("│ ~sAvg per Combination:~s   ~.2f ms~n", [?BLUE, ?RESET, [AvgTime]]),
    io:format("└──────────────────────────────────────────────────┘~n~n"),

    %% Display pass rate progress bar
    display_pass_rate_bar(PassRate).

%% @private Display combinations in table format
display_combinations_table(Combinations) ->
    display_table_header(),
    display_table_rows(Combinations, 1),
    display_table_footer(length(Combinations)).

%% @private Display table header
display_table_header() ->
    io:format("┌──────┬──────────────────────────────────────────────────┬────────┬─────────┐~n"),
    io:format("│ ~s#~s   │ Pattern Combinations                            │ Status │ Time    │~n",
              [?BOLD, ?RESET]),
    io:format("├──────┼──────────────────────────────────────────────────┼────────┼─────────┤~n").

%% @private Display table rows
display_table_rows([], _) -> ok;
display_table_rows([Combo | Rest], Index) ->
    {Patterns, Status, Timing} = case Combo of
        {P1, P2} ->
            {io_lib:format("~p + ~p", [P1, P2]), pass, 0};
        {P1, P2, P3} ->
            {io_lib:format("~p + ~p + ~p", [P1, P2, P3]), pass, 0};
        _ when is_map(Combo) ->
            ComboStatus = maps:get(status, Combo, pass),
            Pattern = maps:get(pattern, Combo, unknown),
            Time = maps:get(time, Combo, 0),
            {io_lib:format("~p", [Pattern]), ComboStatus, Time};
        _ ->
            {io_lib:format("~p", [Combo]), pass, 0}
    end,

    %% Format row
    PatternsStr = lists:flatten(Patterns),
    PatternsTruncated = case length(PatternsStr) > 50 of
        true -> string:slice(PatternsStr, 0, 47) ++ "...";
        false -> PatternsStr
    end,

    StatusStr = case Status of
        pass -> io_lib:format("~sPASS~s", [?GREEN, ?RESET]);
        fail -> io_lib:format("~sFAIL~s", [?RED, ?RESET]);
        _ -> io_lib:format("~s~w~s", [?YELLOW, [Status], ?RESET])
    end,

    TimingStr = if
        Timing > 0 -> io_lib:format("~w ms", [Timing]);
        true -> "-"
    end,

    io:format("│ ~4w │ ~s │ ~s │ ~7s │~n",
              [Index, [PatternsTruncated], StatusStr, [TimingStr]]),

    display_table_rows(Rest, Index + 1).

%% @private Display table footer with timing info
display_table_footer(TotalCount) ->
    io:format("└──────┴──────────────────────────────────────────────────┴────────┴─────────┘~n"),
    color_print(info, "Showing ~p combinations", [TotalCount]),
    io:format("~n").

%% @private Display a visual pass rate progress bar
display_pass_rate_bar(PassRate) ->
    BarWidth = 40,
    Filled = (PassRate * BarWidth) div 100,
    Empty = BarWidth - Filled,

    %% Choose color based on pass rate
    Color = if
        PassRate >= 90 -> ?GREEN;
        PassRate >= 70 -> ?YELLOW;
        PassRate >= 50 -> ?BRIGHT_YELLOW;
        true -> ?RED
    end,

    %% Build progress bar
    FilledBar = lists:duplicate(Filled, ?PROGRESS_FULL),
    EmptyBar = lists:duplicate(Empty, ?PROGRESS_EMPTY),
    BarStr = FilledBar ++ case Empty > 0 of
        true -> [?PROGRESS_HEAD | EmptyBar];
        false -> []
    end,

    io:format("  Pass Rate: ~s[~s~s~s~s] ~w%~s~n~n",
              [Color, BarStr, Color, ?RESET, [PassRate]]).

%% @private Legacy combinations display (for backward compatibility)
display_combinations_legacy(Combinations) ->
    lists:foreach(fun(Combo) ->
        case Combo of
            {P1, P2} ->
                io:format("  ~s[COMBO]~s ~p + ~p~n", [?CYAN, ?RESET, P1, P2]);
            {P1, P2, P3} ->
                io:format("  ~s[COMBO]~s ~p + ~p + ~p~n", [?CYAN, ?RESET, P1, P2, P3]);
            _ when is_map(Combo) ->
                case maps:get(status, Combo, pass) of
                    fail ->
                        io:format("  ~s[FAIL]~s ~p~n", [?RED, ?RESET, maps:get(pattern, Combo, unknown)]);
                    _ ->
                        ok
                end;
            _ ->
                io:format("  ~s[COMBO]~s ~p~n", [?CYAN, ?RESET, Combo])
        end
    end, Combinations).

%%====================================================================
%% Visual Utility Functions
%%====================================================================

%% @doc Display a progress bar for long-running operations
%% @param Current - Current progress value
%% @param Total - Total value (100%)
-spec progress_bar(non_neg_integer(), pos_integer()) -> ok.
progress_bar(Current, Total) when Total > 0 ->
    progress_bar(Current, Total, "");
progress_bar(_, _) ->
    ok.

%% @doc Display a progress bar with a custom label
%% @param Current - Current progress value
%% @param Total - Total value (100%)
%% @param Label - Optional label to display
-spec progress_bar(non_neg_integer(), pos_integer(), string()) -> ok.
progress_bar(Current, Total, Label) when Total > 0 ->
    Percentage = (Current * 100) div Total,
    Filled = (Percentage * ?PROGRESS_WIDTH) div 100,
    Empty = ?PROGRESS_WIDTH - Filled,

    %% Choose color based on percentage
    Color = if
        Percentage >= 100 -> ?GREEN;
        Percentage >= 50 -> ?YELLOW;
        true -> ?RED
    end,

    %% Build bar
    FilledBar = lists:duplicate(Filled, ?PROGRESS_FULL),
    EmptyBar = lists:duplicate(Empty, ?PROGRESS_EMPTY),

    LabelStr = case Label of
        "" -> "";
        _ -> io_lib:format(" ~s", [Label])
    end,

    %% Print progress bar with carriage return for animation
    io:format("\r~sProgress:~s [~s~s~s~s~s] ~w%~s",
              [?BOLD, ?RESET, Color, FilledBar,
               case Empty > 0 of
                   true -> [?PROGRESS_HEAD | EmptyBar];
                   false -> []
               end, ?RESET, [Percentage], LabelStr]),

    %% Newline when complete
    case Percentage >= 100 of
        true -> io:format("~n");
        false -> ok
    end.

%% @doc Format a list of items into a table structure
-spec format_table(list()) -> string().
format_table(Items) when is_list(Items) ->
    format_table(Items, []).

%% @doc Format items with custom column definitions
%% @param Items - List of rows (each row is a list of values)
%% @param Columns - List of {Name, Width} tuples for column definitions
-spec format_table(list(), list()) -> string().
format_table(Items, Columns) when is_list(Items), is_list(Columns) ->
    case {Items, Columns} of
        {[], []} ->
            "[Empty Table]";
        {_, []} when length(Items) > 0 ->
            %% Auto-detect columns from first item
            FirstRow = hd(Items),
            ColCount = if
                is_tuple(FirstRow) -> tuple_size(FirstRow);
                is_list(FirstRow) -> length(FirstRow);
                true -> 1
            end,
            AutoColumns = [{io_lib:format("Col~w", [N]), 15} || N <- lists:seq(1, ColCount)],
            format_table(Items, AutoColumns);
        _ ->
            build_table(Items, Columns)
    end.

%% @private Build formatted table string
build_table(Items, Columns) ->
    %% Calculate total width
    TotalWidth = lists:sum([W || {_, W} <- Columns]) + (3 * length(Columns)) + 1,

    %% Build separator line
    Separator = lists:duplicate(TotalWidth, $-),

    %% Build header row
    HeaderRow = build_table_row(Columns, fun({Name, _}) ->
        string:pad(Name, 20)
    end),

    %% Build data rows
    DataRows = [build_table_row(Items, fun(Item) -> "" end) || _ <- Items],

    lists:flatten([
        "┌", Separator, "┐\n",
        "│ ", HeaderRow, " │\n",
        "├", Separator, "┤\n",
        DataRows,
        "└", Separator, "┘\n"
    ]).

%% @private Build a table row from values
build_table_row(Values, Formatter) ->
    Formatted = [Formatter(V) || V <- Values],
    string:join(Formatted, " │ ").

%% @doc Stream results as they complete (for async operations)
%% @param Callback - Function to call with each result
%% @param Acc - Accumulator for results
-spec stream_results(fun(), list()) -> list().
stream_results(Callback, InitialList) ->
    stream_results(Callback, InitialList, []).

%% @doc Stream results with accumulator
stream_results(_Callback, [], Acc) ->
    lists:reverse(Acc);
stream_results(Callback, [Item | Rest], Acc) ->
    Result = Callback(Item),
    stream_results(Callback, Rest, [Result | Acc]).
