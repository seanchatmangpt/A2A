%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Demo Scenarios - Predefined Business Workflow Scenarios
%%%
%%% This module provides ready-to-run demo scenarios for the Y Combinator
%%% demo, showcasing real-world workflow patterns with visual progress
%%% indicators and color-coded status output.
%%%
%%% Scenarios:
%%%   - order_processing: E-commerce order flow demo
%%%   - document_approval: Multi-level approval demo
%%%   - data_pipeline: ETL processing demo
%%%   - financial_audit: Compliance checking demo
%%%
%%% Usage:
%%%   y_demo_scenarios:run_scenario(order_processing).
%%%   y_demo_scenarios:run_scenario(document_approval).
%%%   y_demo_scenarios:run_scenario(data_pipeline).
%%%   y_demo_scenarios:run_scenario(financial_audit).
%%%   y_demo_scenarios:list_scenarios().
%%% @end
%%%-------------------------------------------------------------------

-module(y_demo_scenarios).
-author("A2A Team").
-export([
    run_scenario/1,
    list_scenarios/0,
    get_scenario_info/1,
    validate_scenario/1
]).

%% ANSI Color codes for terminal output
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

%% Status symbols
-define(CHECK, "[\033[32m✓\033[0m]").
-define(CROSS, "[\033[31m✗\033[0m]").
-define(CLOCK, "[\033[33m⏱\033[0m]").
-define(RUNNING, "[\033[34m▶\033[0m]").
-define(WAIT, "[\033[35m⋯\033[0m]").
-define(INFO, "[\033[36mℹ\033[0m]").

%% Progress bar settings
-define(PROGRESS_FULL, "=").
-define(PROGRESS_HEAD, ">").
-define(PROGRESS_EMPTY, " ").
-define(PROGRESS_WIDTH, 40).

%%====================================================================
%% Type Definitions
%%====================================================================

-type scenario_name() :: order_processing | document_approval | data_pipeline | financial_audit.
-type scenario_status() :: pending | running | completed | failed.
-type step_status() :: pending | running | passed | failed.

%%====================================================================
%% Scenario Records
%%====================================================================

-record(scenario, {
    name :: scenario_name(),
    title :: binary(),
    description :: binary(),
    patterns :: list(atom()),
    steps :: list(#{}),
    expected_duration :: integer(),
    complexity :: low | medium | high
}).

-record(step, {
    id :: integer(),
    name :: binary(),
    pattern :: atom(),
    status :: step_status(),
    duration :: integer()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Run a specific demo scenario
run_scenario(ScenarioName) when is_atom(ScenarioName) ->
    case get_scenario_definition(ScenarioName) of
        {ok, Scenario} ->
            execute_scenario(Scenario);
        {error, not_found} ->
            print_error("Scenario not found: ~p", [ScenarioName]),
            io:format("~nAvailable scenarios:~n"),
            list_scenarios(),
            {error, not_found}
    end.

%% @doc List all available demo scenarios
list_scenarios() ->
    Scenarios = [
        {order_processing, "E-commerce Order Flow", "30s", "Basic sequential + parallel split"},
        {document_approval, "Multi-level Approval", "45s", "Exclusive choice + multi-instance"},
        {data_pipeline, "ETL Processing", "60s", "Parallel split + join + iteration"},
        {financial_audit, "Compliance Checking", "90s", "Advanced patterns + cancellation"}
    ],
    lists:foreach(fun({Name, Title, Duration, Desc}) ->
        io:format("  ~-20s ~-25s ~5s ~s~n",
                  [Name, Title, Duration, Desc])
    end, Scenarios),
    ok.

%% @doc Get detailed information about a scenario
get_scenario_info(ScenarioName) ->
    case get_scenario_definition(ScenarioName) of
        {ok, Scenario} ->
            #scenario{
                title = Title,
                description = Description,
                patterns = Patterns,
                expected_duration = Duration,
                complexity = Complexity
            } = Scenario,
            #{
                title => Title,
                description => Description,
                patterns => Patterns,
                expected_duration => Duration,
                complexity => Complexity
            };
        {error, not_found} ->
            #{error => scenario_not_found}
    end.

%% @doc Validate that a scenario can be run
validate_scenario(ScenarioName) ->
    case get_scenario_definition(ScenarioName) of
        {ok, _Scenario} ->
            %% Check if required modules are available
            RequiredModules = [yawl_combinatoric_test, yawl_patterns],
            case lists:all(fun(M) -> code:is_loaded(M) =/= false orelse
                                     whereis(M) =/= undefined orelse
                                     module_loaded(M) end
                            , RequiredModules) of
                true -> {ok, valid};
                false -> {error, missing_dependencies}
            end;
        {error, not_found} ->
            {error, invalid_scenario}
    end.

%%====================================================================
%% Scenario Definitions
%%====================================================================

%% @private Get scenario definition by name
get_scenario_definition(order_processing) ->
    {ok, #scenario{
        name = order_processing,
        title = <<"E-commerce Order Processing">>,
        description = <<"Complete order flow from creation to delivery, including inventory check, "
                        "payment processing, and shipment scheduling.">>,
        patterns = [basic_sequential, parallel_split, exclusive_choice],
        steps = [
            #step{id = 1, name = <<"Receive Order">>, pattern = basic_sequential,
                  status = pending, duration = 500},
            #step{id = 2, name = <<"Validate Inventory">>, pattern = basic_sequential,
                  status = pending, duration = 800},
            #step{id = 3, name = <<"Process Payment">>, pattern = parallel_split,
                  status = pending, duration = 1200},
            #step{id = 4, name = <<"Allocate Stock">>, pattern = parallel_split,
                  status = pending, duration = 1000},
            #step{id = 5, name = <<"Choose Shipping">>, pattern = exclusive_choice,
                  status = pending, duration = 600},
            #step{id = 6, name = <<"Generate Invoice">>, pattern = basic_sequential,
                  status = pending, duration = 400},
            #step{id = 7, name = <<"Schedule Pickup">>, pattern = basic_sequential,
                  status = pending, duration = 700}
        ],
        expected_duration = 30000,
        complexity = low
    }};
get_scenario_definition(document_approval) ->
    {ok, #scenario{
        name = document_approval,
        title = <<"Multi-level Document Approval">>,
        description = <<"Document routing through multiple approval levels with parallel "
                        "reviewers and conditional escalation.">>,
        patterns = [exclusive_choice, multi_instance, parallel_split, simple_merge],
        steps = [
            #step{id = 1, name = <<"Submit Document">>, pattern = basic_sequential,
                  status = pending, duration = 400},
            #step{id = 2, name = <<"Initial Review">>, pattern = basic_sequential,
                  status = pending, duration = 800},
            #step{id = 3, name = <<"Route to Approvers">>, pattern = exclusive_choice,
                  status = pending, duration = 500},
            #step{id = 4, name = <<"Parallel Review">>, pattern = multi_instance,
                  status = pending, duration = 2000},
            #step{id = 5, name = <<"Collect Approvals">>, pattern = parallel_join,
                  status = pending, duration = 600},
            #step{id = 6, name = <<"Check Quorum">>, pattern = simple_merge,
                  status = pending, duration = 400},
            #step{id = 7, name = <<"Escalate if Needed">>, pattern = exclusive_choice,
                  status = pending, duration = 700},
            #step{id = 8, name = <<"Final Approval">>, pattern = basic_sequential,
                  status = pending, duration = 500},
            #step{id = 9, name = <<"Archive Document">>, pattern = basic_sequential,
                  status = pending, duration = 300}
        ],
        expected_duration = 45000,
        complexity = medium
    }};
get_scenario_definition(data_pipeline) ->
    {ok, #scenario{
        name = data_pipeline,
        title = <<"ETL Data Pipeline">>,
        description = <<"Extract-Transform-Load pipeline with parallel data processing, "
                        "validation stages, and error handling.">>,
        patterns = [parallel_split, parallel_join, iterative_loop, multi_instance],
        steps = [
            #step{id = 1, name = <<"Extract Data">>, pattern = basic_sequential,
                  status = pending, duration = 1000},
            #step{id = 2, name = <<"Split Data Streams">>, pattern = parallel_split,
                  status = pending, duration = 400},
            #step{id = 3, name = <<"Validate Schema">>, pattern = multi_instance,
                  status = pending, duration = 1500},
            #step{id = 4, name = <<"Transform Records">>, pattern = iterative_loop,
                  status = pending, duration = 2000},
            #step{id = 5, name = <<"Apply Business Rules">>, pattern = parallel_split,
                  status = pending, duration = 1200},
            #step{id = 6, name = <<"Merge Results">>, pattern = parallel_join,
                  status = pending, duration = 800},
            #step{id = 7, name = <<"Quality Checks">>, pattern = iterative_loop,
                  status = pending, duration = 1000},
            #step{id = 8, name = <<"Load to Warehouse">>, pattern = basic_sequential,
                  status = pending, duration = 1500},
            #step{id = 9, name = <<"Update Metrics">>, pattern = basic_sequential,
                  status = pending, duration = 500}
        ],
        expected_duration = 60000,
        complexity = medium
    }};
get_scenario_definition(financial_audit) ->
    {ok, #scenario{
        name = financial_audit,
        title = <<"Financial Compliance Audit">>,
        description = <<"Comprehensive financial audit with transaction verification, "
                        "rule validation, anomaly detection, and reporting.">>,
        patterns = [parallel_split, exclusive_choice, discriminator,
                    cancelation_block, milestone],
        steps = [
            #step{id = 1, name = <<"Initiate Audit">>, pattern = basic_sequential,
                  status = pending, duration = 500},
            #step{id = 2, name = <<"Gather Transactions">>, pattern = basic_sequential,
                  status = pending, duration = 1200},
            #step{id = 3, name = <<"Parallel Verification">>, pattern = parallel_split,
                  status = pending, duration = 800},
            #step{id = 4, name = <<"Check Compliance Rules">>, pattern = multi_instance,
                  status = pending, duration = 2500},
            #step{id = 5, name = <<"Anomaly Detection">>, pattern = iterative_loop,
                  status = pending, duration = 2000},
            #step{id = 6, name = <<"Risk Assessment">>, pattern = exclusive_choice,
                  status = pending, duration = 1000},
            #step{id = 7, name = <<"Milestone Review">>, pattern = milestone,
                  status = pending, duration = 700},
            #step{id = 8, name = <<"Generate Findings">>, pattern = discriminator,
                  status = pending, duration = 1500},
            #step{id = 9, name = <<"Approve Report">>, pattern = exclusive_choice,
                  status = pending, duration = 800},
            #step{id = 10, name = <<"Handle Exceptions">>, pattern = cancelation_block,
                  status = pending, duration = 600},
            #step{id = 11, name = <<"Finalize Audit">>, pattern = basic_sequential,
                  status = pending, duration = 500}
        ],
        expected_duration = 90000,
        complexity = high
    }};
get_scenario_definition(_) ->
    {error, not_found}.

%%====================================================================
%% Scenario Execution
%%====================================================================

%% @private Execute a scenario with visual feedback
execute_scenario(Scenario) ->
    #scenario{
        name = Name,
        title = Title,
        description = Description,
        patterns = Patterns,
        steps = Steps,
        expected_duration = Duration,
        complexity = Complexity
    } = Scenario,

    %% Print scenario header
    print_scenario_header(Name, Title, Description, Patterns, Duration, Complexity),

    %% Print initial status
    io:format("~n", []),
    print_steps_header(Steps),

    %% Execute each step with progress
    StartTime = erlang:monotonic_time(millisecond),
    {ExecutedSteps, Results} = execute_steps(Steps, 1, []),
    EndTime = erlang:monotonic_time(millisecond),
    ActualDuration = EndTime - StartTime,

    %% Print results summary
    print_scenario_summary(Name, Results, ActualDuration, Duration),

    {ok, #{
        scenario => Name,
        steps_executed => length(ExecutedSteps),
        total_steps => length(Steps),
        results => Results,
        duration => ActualDuration,
        expected_duration => Duration
    }}.

%% @private Execute steps sequentially with visual feedback
execute_steps([], _Index, Acc) ->
    {lists:reverse(Acc), Acc};
execute_steps([Step | Rest], Index, Acc) ->
    #step{
        id = Id,
        name = Name,
        pattern = Pattern,
        duration = Duration
    } = Step,

    %% Print running indicator
    print_step_running(Index, Name, Pattern),
    timer:sleep(Duration div 10),  %% Speed up for demo

    %% Simulate step execution
    Result = execute_step(Step),

    %% Print completion status
    case Result of
        {ok, _} ->
            print_step_passed(Index, Name);
        {error, _} ->
            print_step_failed(Index, Name)
    end,

    %% Update progress bar
    Progress = calculate_progress(Index, length([Step | Rest])),
    print_progress_bar(Progress),

    execute_steps(Rest, Index + 1, [Result | Acc]).

%% @private Execute a single step
execute_step(#step{pattern = Pattern}) ->
    try
        %% Simulate pattern execution
        case validate_pattern_execution(Pattern) of
            true -> {ok, Pattern};
            false -> {error, {pattern_failed, Pattern}}
        end
    catch
        _:_ -> {error, {execution_error, Pattern}}
    end.

%% @private Validate pattern execution (demo simulation)
validate_pattern_execution(Pattern) ->
    %% In demo mode, most patterns succeed
    %% Simulate occasional validation checks
    case Pattern of
        cancelation_block -> rand:uniform(10) > 1;  %% 90% success
        _ -> true
    end.

%%====================================================================
%% Printing Functions
%%====================================================================

%% @private Print scenario header with colors
print_scenario_header(Name, Title, Description, Patterns, Duration, Complexity) ->
    io:format("~n~s=== YAWL Demo Scenario ===~s~n", [?BRIGHT_CYAN, ?RESET]),
    io:format("~n~sName:~s ~p~n", [?BOLD, ?RESET, Name]),
    io:format("~sTitle:~s ~s~n", [?BOLD, ?RESET, Title]),
    io:format("~sDescription:~s ~s~n", [?BOLD, ?RESET, Description]),
    io:format("~sPatterns:~s ~p~n", [?BOLD, ?RESET, Patterns]),
    io:format("~sExpected Duration:~s ~p ms~n", [?BOLD, ?RESET, Duration]),
    io:format("~sComplexity:~s ~p~n", [?BOLD, ?RESET, Complexity]),
    io:format("~s~s─────────────────────────────────────────────────────────~s~n",
              [?DIM, ?BRIGHT_CYAN, ?RESET]).

%% @private Print steps table header
print_steps_header(Steps) ->
    io:format("~n~sStep  Status~s Pattern                  Name~n",
              [?BOLD, ?RESET]),
    io:format("~s    ~s─────────────────────────────────────────────────────~n",
              [?DIM, ?RESET]),
    lists:foreach(fun(#step{id = Id, name = Name, pattern = Pattern}) ->
        io:format("~s[~2d]~s ~s ~-24s ~s~n",
                  [?DIM, Id, ?RESET, ?WAIT, format_pattern(Pattern), Name])
    end, Steps).

%% @private Print step running status
print_step_running(Index, Name, Pattern) ->
    io:format("~s[~2d]~s ~s ~-24s ~s~n",
              [?DIM, Index, ?RESET, ?RUNNING, format_pattern(Pattern), Name]).

%% @private Print step passed status
print_step_passed(Index, Name) ->
    io:format("~s[~2d]~s ~s ~s~n", [?DIM, Index, ?RESET, ?CHECK, Name]).

%% @private Print step failed status
print_step_failed(Index, Name) ->
    io:format("~s[~2d]~s ~s ~s~n", [?DIM, Index, ?RESET, ?CROSS, Name]).

%% @private Print progress bar
print_progress_bar(Percentage) ->
    Filled = round((Percentage / 100) * ?PROGRESS_WIDTH),
    Empty = ?PROGRESS_WIDTH - Filled,
    Bar = lists:duplicate(Filled, ?PROGRESS_FULL) ++
          [?PROGRESS_HEAD] ++
          lists:duplicate(Empty, ?PROGRESS_EMPTY),
    io:format("~sProgress: [~s~s] ~3d%%~s~n~n",
              [?DIM, ?BRIGHT_CYAN, lists:flatten(Bar), Percentage, ?RESET]).

%% @private Print scenario summary
print_scenario_summary(Name, Results, ActualDuration, ExpectedDuration) ->
    Passed = length([R || R <- Results, element(1, R) =:= ok]),
    Failed = length(Results) - Passed,
    Total = length(Results),

    io:format("~n~s─────────────────────────────────────────────────────────~s~n",
              [?BRIGHT_CYAN, ?RESET]),
    io:format("~sScenario Summary: ~p~s~n", [?BOLD, Name, ?RESET]),
    io:format("~n  Total Steps:    ~p~n", [Total]),
    io:format("~s  Passed:         ~s~p~n", [?GREEN, ?RESET, Passed]),
    case Failed of
        0 -> ok;
        _ -> io:format("~s  Failed:         ~s~p~n", [?RED, ?RESET, Failed])
    end,
    io:format("  Duration:       ~p ms~n", [ActualDuration]),
    io:format("  Expected:       ~p ms~n", [ExpectedDuration]),
    io:format("  Performance:    ~s~n", [format_performance(ActualDuration, ExpectedDuration)]),

    case Failed of
        0 ->
            io:format("~n~s✓ Scenario completed successfully!~s~n", [?BRIGHT_GREEN, ?RESET]);
        _ ->
            io:format("~n~s! Scenario completed with ~p failures~s~n",
                      [?BRIGHT_YELLOW, Failed, ?RESET])
    end,
    io:format("~n").

%% @private Print error message
print_error(Format, Args) ->
    io:format("~s~s~s~n", [?RED, io_lib:format(Format, Args), ?RESET]).

%%====================================================================
%% Utility Functions
%%====================================================================

%% @private Format pattern atom for display
format_pattern(Pattern) when is_atom(Pattern) ->
    PatternStr = atom_to_list(Pattern),
    %% Capitalize first letter and replace underscores with spaces
    Formatted = string:titlecase(string:replace(PatternStr, "_", " ")),
    %% Truncate if too long
    case length(Formatted) > 24 of
        true -> string:slice(Formatted, 0, 21) ++ "...";
        false -> Formatted
    end.

%% @private Calculate progress percentage
calculate_progress(Current, Total) ->
    round((Current / Total) * 100).

%% @private Format performance comparison
format_performance(Actual, Expected) ->
    Ratio = Actual / Expected,
    if
        Ratio < 0.8 ->
            io_lib:format("~sFaster than expected (~.1f%)~s",
                          [?BRIGHT_GREEN, (1 - Ratio) * 100, ?RESET]);
        Ratio > 1.2 ->
            io_lib:format("~sSlower than expected (~.1f%)~s",
                          [?BRIGHT_YELLOW, (Ratio - 1) * 100, ?RESET]);
        true ->
            io_lib:format("~sAs expected~s", [?GREEN, ?RESET])
    end.

%% @private Check if a module is loaded
module_loaded(Module) ->
    case code:is_loaded(Module) of
        {file, _} -> true;
        false -> false
    end.
