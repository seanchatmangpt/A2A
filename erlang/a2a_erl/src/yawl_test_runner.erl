%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Test Runner
%%%
%%% This module provides comprehensive test execution for YAWL workflow
%%% patterns. It runs pattern tests, combinatoric tests, business
%%% scenario tests, and performance benchmarks.
%%%
%%% ## Example Usage
%%%
%%% ```
%%% %% Run all pattern tests
%%% {ok, Results} = yawl_test_runner:run_pattern_tests().
%%'
%%%
%%% %% Run business scenario tests
%%% {ok, Results} = yawl_test_runner:run_business_tests(all).
%%'
%%%
%%% %% Generate test report
%%% {ok, Report} = yawl_test_runner:generate_report().
%%'
%%% ```
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_test_runner).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([
    start_link/0,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% API exports
-export([
    run_pattern_tests/0,
    run_combination_tests/1,
    run_business_tests/1,
    run_performance_tests/1,
    generate_report/0,
    run_all_tests/0,
    get_test_status/0,
    cancel_test_run/0,
    get_test_summary/0
]).

%% Include type definitions
-include("yawl_types.hrl").

%% State record
-record(state, {
    current_test :: undefined | binary(),
    test_results :: [#yawl_test_result{}],
    running :: boolean(),
    config :: map(),
    start_time :: undefined | integer()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the test runner.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Run all pattern tests.
-spec run_pattern_tests() -> {ok, [map()]} | {error, term()}.
run_pattern_tests() ->
    gen_server:call(?MODULE, run_pattern_tests, infinity).

%% @doc Run combination tests.
-spec run_combination_tests(map()) -> {ok, [map()]} | {error, term()}.
run_combination_tests(Config) ->
    gen_server:call(?MODULE, {run_combination_tests, Config}, infinity).

%% @doc Run business scenario tests.
-spec run_business_tests(all | [business_domain()]) -> {ok, [map()]} | {error, term()}.
run_business_tests(Domains) ->
    gen_server:call(?MODULE, {run_business_tests, Domains}, infinity).

%% @doc Run performance tests.
-spec run_performance_tests(map()) -> {ok, [map()]} | {error, term()}.
run_performance_tests(Config) ->
    gen_server:call(?MODULE, {run_performance_tests, Config}, infinity).

%% @doc Generate test report.
-spec generate_report() -> {ok, map()} | {error, term()}.
generate_report() ->
    gen_server:call(?MODULE, generate_report).

%% @doc Run all tests.
-spec run_all_tests() -> {ok, map()} | {error, term()}.
run_all_tests() ->
    gen_server:call(?MODULE, run_all_tests, infinity).

%% @doc Get current test status.
-spec get_test_status() -> {ok, map()} | {error, term()}.
get_test_status() ->
    gen_server:call(?MODULE, get_test_status).

%% @doc Cancel current test run.
-spec cancel_test_run() -> ok | {error, term()}.
cancel_test_run() ->
    gen_server:call(?MODULE, cancel_test_run).

%% @doc Get test summary.
-spec get_test_summary() -> {ok, map()} | {error, term()}.
get_test_summary() ->
    gen_server:call(?MODULE, get_test_summary).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    State = #state{
        current_test = undefined,
        test_results = [],
        running = false,
        config = get_default_config(),
        start_time = undefined
    },
    {ok, State}.

%% @private
handle_call(run_pattern_tests, _From, State) ->
    {Reply, NewState} = do_run_pattern_tests(State),
    {reply, Reply, NewState};

handle_call({run_combination_tests, Config}, _From, State) ->
    {Reply, NewState} = do_run_combination_tests(Config, State),
    {reply, Reply, NewState};

handle_call({run_business_tests, Domains}, _From, State) ->
    {Reply, NewState} = do_run_business_tests(Domains, State),
    {reply, Reply, NewState};

handle_call({run_performance_tests, Config}, _From, State) ->
    {Reply, NewState} = do_run_performance_tests(Config, State),
    {reply, Reply, NewState};

handle_call(generate_report, _From, State) ->
    Reply = do_generate_report(State),
    {reply, Reply, State};

handle_call(run_all_tests, _From, State) ->
    {Reply, NewState} = do_run_all_tests(State),
    {reply, Reply, NewState};

handle_call(get_test_status, _From, State) ->
    Status = #{
        current_test => State#state.current_test,
        running => State#state.running,
        total_tests => length(State#state.test_results),
        elapsed_time => case State#state.start_time of
            undefined -> 0;
            StartTime -> erlang:monotonic_time(millisecond) - StartTime
        end
    },
    {reply, {ok, Status}, State};

handle_call(cancel_test_run, _From, State) ->
    NewState = State#state{running = false},
    {reply, ok, NewState};

handle_call(get_test_summary, _From, State) ->
    Reply = generate_test_summary(State),
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
get_default_config() ->
    #{
        parallel_execution => true,
        max_parallel_tests => 10,
        test_timeout => 30000,
        verbose => true
    }.

%% @private
do_run_pattern_tests(State) ->
    StartTime = erlang:monotonic_time(millisecond),
    RunningState = State#state{
        running = true,
        start_time = StartTime,
        test_results = []
    },
    Results = lists:map(fun(Pattern) ->
        test_pattern(Pattern, RunningState#state.config)
    end, ?YAWL_PATTERNS),
    NewState = RunningState#state{
        running = false,
        test_results = Results
    },
    {{ok, Results}, NewState}.

%% @private
test_pattern(Pattern, _Config) ->
    StartTime = erlang:monotonic_time(millisecond),
    try
        TestConfig = get_pattern_test_config(Pattern),
        case yawl_orchestrator:create_workflow(Pattern, TestConfig) of
            {ok, WorkflowId} ->
                case yawl_orchestrator:execute_workflow(WorkflowId) of
                    {ok, Result} ->
                        EndTime = erlang:monotonic_time(millisecond),
                        #yawl_test_result{
                            test_id = generate_test_id(),
                            pattern_type = Pattern,
                            status = passed,
                            execution_time = EndTime - StartTime,
                            result = Result,
                            validation_result = #{valid => true},
                            performance_metrics = calculate_performance_metrics(EndTime - StartTime),
                            timestamp = EndTime
                        };
                    {error, Reason} ->
                        EndTime = erlang:monotonic_time(millisecond),
                        #yawl_test_result{
                            test_id = generate_test_id(),
                            pattern_type = Pattern,
                            status = failed,
                            execution_time = EndTime - StartTime,
                            error_reason = Reason,
                            validation_result = #{valid => false, errors => [Reason]},
                            performance_metrics = #{},
                            timestamp = EndTime
                        }
                end;
            {error, Reason} ->
                EndTime = erlang:monotonic_time(millisecond),
                #yawl_test_result{
                    test_id = generate_test_id(),
                    pattern_type = Pattern,
                    status = failed,
                    execution_time = EndTime - StartTime,
                    error_reason = {create_failed, Reason},
                    validation_result = #{valid => false, errors => [Reason]},
                    performance_metrics = #{},
                    timestamp = EndTime
                }
        end
    catch
        _:Error ->
            CatchEndTime = erlang:monotonic_time(millisecond),
            #yawl_test_result{
                test_id = generate_test_id(),
                pattern_type = Pattern,
                status = failed,
                execution_time = CatchEndTime - StartTime,
                error_reason = Error,
                validation_result = #{valid => false, errors => [Error]},
                performance_metrics = #{},
                timestamp = CatchEndTime
            }
    end.

%% @private
get_pattern_test_config(basic_sequential) ->
    #{task1_name => "task1", task2_name => "task2"};
get_pattern_test_config(parallel_split) ->
    #{branches => 3, task_names => ["task1", "task2", "task3"]};
get_pattern_test_config(parallel_join) ->
    #{branches => 3};
get_pattern_test_config(exclusive_choice) ->
    #{conditions => [option1, option2, option3], default_branch => option1};
get_pattern_test_config(simple_merge) ->
    #{branches => 3};
get_pattern_test_config(iterative_loop) ->
    #{condition => "continue", max_iterations => 5};
get_pattern_test_config(multi_instance) ->
    #{num_instances => 3, data => [item1, item2, item3]};
get_pattern_test_config(interleaved_parallelism) ->
    #{tasks => ["task1", "task2", "task3"], ordering => any};
get_pattern_test_config(implicit_merge) ->
    #{};
get_pattern_test_config(multiple_merge) ->
    #{branches => 3};
get_pattern_test_config(deferred_choice) ->
    #{options => [opt1, opt2, opt3], choice_strategy => runtime};
get_pattern_test_config(interleaved_routing) ->
    #{routes => [route1, route2, route3], interleaving_strategy => round_robin};
get_pattern_test_config(milestone) ->
    #{milestone_condition => "reached", milestone_actions => [notify]};
get_pattern_test_config(cancelation_block) ->
    #{scope => "test_scope", cancel_condition => "never"};
get_pattern_test_config(cancelation_scope) ->
    #{scope => "test_scope", scope_actions => [action1, action2]};
get_pattern_test_config(cancelation_thread) ->
    #{thread_id => "thread1"};
get_pattern_test_config(cancelation_subprocess) ->
    #{subprocess_id => "subprocess1"};
get_pattern_test_config(cancelation_multiple_instances) ->
    #{num_instances => 3, cancel_strategy => all};
get_pattern_test_config(cancelation_multiple_instances_scope) ->
    #{scope => "test_scope", num_instances => 3};
get_pattern_test_config(cancelation_multiple_instances_thread) ->
    #{thread_id => "thread1", num_instances => 3};
get_pattern_test_config(cancelation_multiple_instances_subprocess) ->
    #{subprocess_id => "subprocess1", num_instances => 3};
get_pattern_test_config(cancelation_point) ->
    #{};
get_pattern_test_config(cancelation_end) ->
    #{};
get_pattern_test_config(cancelation_cancel) ->
    #{};
get_pattern_test_config(cancelation_thread_after) ->
    #{thread_id => "thread1", trigger_condition => "completed"};
get_pattern_test_config(cancelation_subprocess_after) ->
    #{subprocess_id => "subprocess1", trigger_condition => "completed"};
get_pattern_test_config(cancelation_multiple_instances_after) ->
    #{num_instances => 3, trigger_condition => "completed"};
get_pattern_test_config(cancelation_multiple_instances_thread_after) ->
    #{thread_id => "thread1", num_instances => 3, trigger_condition => "completed"};
get_pattern_test_config(cancelation_multiple_instances_subprocess_after) ->
    #{subprocess_id => "subprocess1", num_instances => 3, trigger_condition => "completed"};
get_pattern_test_config(cancelation_thread_or) ->
    #{thread_id => "thread1", conditions => [cond1, cond2]};
get_pattern_test_config(cancelation_subprocess_or) ->
    #{subprocess_id => "subprocess1", conditions => [cond1, cond2]};
get_pattern_test_config(cancelation_multiple_instances_or) ->
    #{num_instances => 3, conditions => [cond1, cond2]};
get_pattern_test_config(cancelation_multiple_instances_thread_or) ->
    #{thread_id => "thread1", num_instances => 3, conditions => [cond1, cond2]};
get_pattern_test_config(cancelation_multiple_instances_subprocess_or) ->
    #{subprocess_id => "subprocess1", num_instances => 3, conditions => [cond1, cond2]};
get_pattern_test_config(cancelation_thread_and) ->
    #{thread_id => "thread1", conditions => [cond1, cond2]};
get_pattern_test_config(cancelation_subprocess_and) ->
    #{subprocess_id => "subprocess1", conditions => [cond1, cond2]};
get_pattern_test_config(cancelation_multiple_instances_and) ->
    #{num_instances => 3, conditions => [cond1, cond2]};
get_pattern_test_config(cancelation_multiple_instances_thread_and) ->
    #{thread_id => "thread1", num_instances => 3, conditions => [cond1, cond2]};
get_pattern_test_config(cancelation_multiple_instances_subprocess_and) ->
    #{subprocess_id => "subprocess1", num_instances => 3, conditions => [cond1, cond2]}.

%% @private
do_run_combination_tests(Config, State) ->
    StartTime = erlang:monotonic_time(millisecond),
    RunningState = State#state{
        running = true,
        start_time = StartTime,
        test_results = []
    },
    MaxLength = maps:get(max_length, Config, 3),
    Patterns = maps:get(patterns, Config, [basic_sequential, parallel_split, exclusive_choice]),
    Combinations = generate_combinations(Patterns, MaxLength),
    Results = lists:map(fun(Combo) ->
        test_combination(Combo, Config)
    end, Combinations),
    NewState = RunningState#state{
        running = false,
        test_results = Results
    },
    {{ok, Results}, NewState}.

%% @private
generate_combinations(Patterns, MaxLength) ->
    generate_combinations_recursive(Patterns, MaxLength, 1, []).

generate_combinations_recursive(_Patterns, MaxLength, Length, _Acc) when Length > MaxLength ->
    [];
generate_combinations_recursive(Patterns, MaxLength, Length, Acc) ->
    lists:map(fun(P) -> [P] end, Patterns) ++
    generate_combinations_recursive(Patterns, MaxLength, Length + 1, Acc).

%% @private
test_combination(Patterns, Config) ->
    StartTime = erlang:monotonic_time(millisecond),
    try
        %% Create a combined workflow
        _ComboConfig = maps:get(combination_config, Config, #{}),
        Results = lists:map(fun(Pattern) ->
            TestConfig = get_pattern_test_config(Pattern),
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(Pattern, TestConfig),
            {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),
            {Pattern, Result}
        end, Patterns),
        EndTime = erlang:monotonic_time(millisecond),
        #yawl_test_result{
            test_id = generate_test_id(),
            pattern_type = Patterns,
            status = passed,
            execution_time = EndTime - StartTime,
            result = #{combinations => Results},
            validation_result = #{valid => true},
            performance_metrics = calculate_performance_metrics(EndTime - StartTime),
            timestamp = EndTime
        }
    catch
        _:Error ->
            CatchEndTime = erlang:monotonic_time(millisecond),
            #yawl_test_result{
                test_id = generate_test_id(),
                pattern_type = Patterns,
                status = failed,
                execution_time = CatchEndTime - StartTime,
                error_reason = Error,
                validation_result = #{valid => false, errors => [Error]},
                performance_metrics = #{},
                timestamp = CatchEndTime
            }
    end.

%% @private
do_run_business_tests(Domains, State) ->
    StartTime = erlang:monotonic_time(millisecond),
    RunningState = State#state{
        running = true,
        start_time = StartTime,
        test_results = []
    },
    TestDomains = case Domains of
        all -> ?BUSINESS_DOMAINS;
        _ -> Domains
    end,
    Results = lists:flatmap(fun(Domain) ->
        test_business_domain(Domain, low) ++
        test_business_domain(Domain, medium) ++
        test_business_domain(Domain, high)
    end, TestDomains),
    NewState = RunningState#state{
        running = false,
        test_results = Results
    },
    {{ok, Results}, NewState}.

%% @private
test_business_domain(Domain, Complexity) ->
    StartTime = erlang:monotonic_time(millisecond),
    Scenario = yawl_business_scenarios:get_scenario_template(Domain, Complexity),
    PatternCombination = Scenario#yawl_scenario.pattern_combination,
    TestResults = lists:map(fun({Pattern, _Config}) ->
        TestConfig = get_pattern_test_config(Pattern),
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(Pattern, TestConfig),
        {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),
        #{
            pattern => Pattern,
            result => Result
        }
    end, PatternCombination),
    EndTime = erlang:monotonic_time(millisecond),
    [#yawl_test_result{
        test_id = generate_test_id(),
        pattern_type = Domain,
        status = passed,
        execution_time = EndTime - StartTime,
        result = #{scenario => Scenario, tests => TestResults},
        validation_result = #{valid => true},
        performance_metrics = calculate_performance_metrics(EndTime - StartTime),
        timestamp = EndTime
    }].

%% @private
do_run_performance_tests(Config, State) ->
    StartTime = erlang:monotonic_time(millisecond),
    RunningState = State#state{
        running = true,
        start_time = StartTime,
        test_results = []
    },
    Iterations = maps:get(iterations, Config, 10),
    Patterns = maps:get(patterns, Config, [basic_sequential, parallel_split, multi_instance]),
    Results = lists:flatmap(fun(Pattern) ->
        lists:map(fun(I) ->
            run_performance_test(Pattern, I, Config)
        end, lists:seq(1, Iterations))
    end, Patterns),
    NewState = RunningState#state{
        running = false,
        test_results = Results
    },
    {{ok, Results}, NewState}.

%% @private
run_performance_test(Pattern, _Iteration, _Config) ->
    StartTime = erlang:monotonic_time(millisecond),
    TestConfig = get_pattern_test_config(Pattern),
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(Pattern, TestConfig),
    {ok, Result} = yawl_orchestrator:execute_workflow(WorkflowId),
    EndTime = erlang:monotonic_time(millisecond),
    #yawl_test_result{
        test_id = generate_test_id(),
        pattern_type = Pattern,
        status = passed,
        execution_time = EndTime - StartTime,
        result = Result,
        validation_result = #{valid => true},
        performance_metrics = calculate_performance_metrics(EndTime - StartTime),
        timestamp = EndTime
    }.

%% @private
do_run_all_tests(State) ->
    StartTime = erlang:monotonic_time(millisecond),
    RunningState = State#state{
        running = true,
        start_time = StartTime,
        test_results = []
    },
    %% Run pattern tests
    {ok, PatternResults} = do_run_pattern_tests(RunningState),
    %% Run combination tests
    {ok, CombinationResults} = do_run_combination_tests(#{max_length => 2}, RunningState),
    %% Run business tests
    {ok, BusinessResults} = do_run_business_tests([order_processing, document_workflow], RunningState),
    AllResults = PatternResults ++ CombinationResults ++ BusinessResults,
    EndTime = erlang:monotonic_time(millisecond),
    Report = #{
        total_tests => length(AllResults),
        passed_tests => length([R || R <- AllResults, R#yawl_test_result.status =:= passed]),
        failed_tests => length([R || R <- AllResults, R#yawl_test_result.status =:= failed]),
        total_time => EndTime - StartTime,
        success_rate => calculate_success_rate(AllResults),
        results => AllResults
    },
    NewState = RunningState#state{
        running = false,
        test_results = AllResults
    },
    {{ok, Report}, NewState}.

%% @private
do_generate_report(State) ->
    Results = State#state.test_results,
    TotalTests = length(Results),
    PassedTests = length([R || R <- Results, R#yawl_test_result.status =:= passed]),
    FailedTests = length([R || R <- Results, R#yawl_test_result.status =:= failed]),
    SkippedTests = length([R || R <- Results, R#yawl_test_result.status =:= skipped]),
    TotalTime = lists:sum([R#yawl_test_result.execution_time || R <- Results]),
    Report = #{
        summary => #{
            total_tests => TotalTests,
            passed_tests => PassedTests,
            failed_tests => FailedTests,
            skipped_tests => SkippedTests,
            success_rate => calculate_success_rate(Results),
            total_time => TotalTime,
            average_time => case TotalTests of 0 -> 0; _ -> TotalTime / TotalTests end
        },
        pattern_results => group_results_by_pattern(Results),
        failed_tests => [R || R <- Results, R#yawl_test_result.status =:= failed],
        performance_analysis => analyze_performance(Results),
        timestamp => erlang:system_time(millisecond)
    },
    {ok, Report}.

%% @private
calculate_success_rate(Results) ->
    case length(Results) of
        0 -> 0.0;
        Total ->
            Passed = length([R || R <- Results, R#yawl_test_result.status =:= passed]),
            Passed / Total
    end.

%% @private
group_results_by_pattern(Results) ->
    lists:foldl(fun(Result, Acc) ->
        Pattern = Result#yawl_test_result.pattern_type,
        PatternResults = maps:get(Pattern, Acc, []),
        Acc#{Pattern => [Result | PatternResults]}
    end, #{}, Results).

%% @private
calculate_performance_metrics(ExecutionTime) ->
    #{
        execution_time => ExecutionTime,
        throughput => 1000 / max(ExecutionTime, 1),
        memory_usage => case erlang:process_info(self(), memory) of
            {memory, Mem} -> Mem;
            _ -> 0
        end
    }.

%% @private
analyze_performance(Results) ->
    Times = [R#yawl_test_result.execution_time || R <- Results],
    case Times of
        [] -> #{};
        _ ->
            SortedTimes = lists:sort(Times),
            #{
                min_time => hd(SortedTimes),
                max_time => lists:last(SortedTimes),
                avg_time => lists:sum(Times) / length(Times),
                median_time => lists:nth(length(SortedTimes) div 2 + 1, SortedTimes),
                p95_time => lists:nth(max(1, (length(SortedTimes) * 95) div 100), SortedTimes),
                p99_time => lists:nth(max(1, (length(SortedTimes) * 99) div 100), SortedTimes)
            }
    end.

%% @private
generate_test_summary(State) ->
    Results = State#state.test_results,
    TotalTests = length(Results),
    PassedTests = length([R || R <- Results, R#yawl_test_result.status =:= passed]),
    FailedTests = length([R || R <- Results, R#yawl_test_result.status =:= failed]),
    #{
        total_tests => TotalTests,
        passed_tests => PassedTests,
        failed_tests => FailedTests,
        success_rate => calculate_success_rate(Results),
        running => State#state.running,
        current_test => State#state.current_test
    }.

%% @private
generate_test_id() ->
    UniqueId = erlang:unique_integer([positive, monotonic]),
    <<UniqueId:64>>.
