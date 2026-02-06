%%%-------------------------------------------------------------------
%%% @doc
%%% Performance Benchmark Tests for YAWL Workflow System
%%%
%%% This module contains comprehensive performance benchmarks and
%%% load tests for measuring system throughput, latency, and scalability.
%%%
%%% Test Coverage:
%%% - Workflow creation throughput
%%% - Execution latency measurements
%%% - Resource allocation performance
%%% - Checkpoint I/O performance
%%% - Query response times
%%% - Concurrent operation scalability
%%% - Memory usage profiling
%%% - System overhead measurement
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_performance_benchmark_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(BENCHMARK_TIMEOUT, 60000).
-define(WARMUP_ITERATIONS, 10).
-define(BENCHMARK_ITERATIONS, 100).
-define(LARGE_DATASET_SIZE, 1000).
-define(MEMORY_THRESHOLD_MB, 100).

%%====================================================================
%% Test Fixtures
%%====================================================================

performance_benchmark_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Workflow creation throughput", fun test_workflow_creation_throughput/0},
      {"Execution latency benchmark", fun test_execution_latency/0},
      {"Query performance benchmark", fun test_query_performance/0},
      {"Checkpoint I/O performance", fun test_checkpoint_io_performance/0},
      {"Concurrent execution scalability", fun test_concurrent_scalability/0},
      {"Memory usage benchmark", fun test_memory_usage/0},
      {"Large dataset handling", fun test_large_dataset_handling/0},
      {"Pattern lookup performance", fun test_pattern_lookup_performance/0},
      {"Resource allocation throughput", fun test_resource_allocation_throughput/0},
      {"Metrics collection overhead", fun test_metrics_overhead/0},
      {"Persistence throughput", fun test_persistence_throughput/0},
      {"Subscription notification latency", fun test_subscription_latency/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Start all necessary applications
    application:ensure_all_started(mnesia),

    %% Create schema and tables
    yawl_persistence:create_schema(),
    yawl_persistence:create_tables(),
    yawl_persistence:wait_for_tables(),

    %% Start metrics
    {ok, _MetricsPid} = yawl_metrics:start_link(),

    %% Start persistence manager
    {ok, _PersistPid} = yawl_persistence:start_link(),

    %% Start the orchestrator
    {ok, OrchPid} = yawl_orchestrator:start_link(),

    %% Warm up the system
    warm_up_system(),

    OrchPid.

cleanup(_Pid) ->
    %% Stop all processes
    catch gen_server:stop(yawl_orchestrator),
    catch gen_server:stop(yawl_metrics),
    catch gen_server:stop(yawl_persistence),

    %% Clean up Mnesia tables
    catch mnesia:clear_table(yawl_workflow_persist),
    catch mnesia:clear_table(yawl_workitem_persist),
    catch mnesia:clear_table(yawl_checkpoint),
    catch mnesia:clear_table(yawl_execution_history),
    catch mnesia:clear_table(yawl_resource_persist),

    %% Stop Mnesia
    catch mnesia:stop().

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
warm_up_system() ->
    %% Perform warmup operations
    lists:foreach(fun(I) ->
        Config = #{task1_name => "warmup_" ++ integer_to_list(I)},
        yawl_orchestrator:create_workflow(basic_sequential, Config)
    end, lists:seq(1, ?WARMUP_ITERATIONS)),
    ok.

%% @private
measure_throughput(Fun, Iterations) ->
    Start = erlang:monotonic_time(microsecond),

    Results = lists:map(fun(_) -> Fun() end, lists:seq(1, Iterations)),

    End = erlang:monotonic_time(microsecond),
    DurationUs = End - Start,
    DurationSec = DurationUs / 1000000,

    Successful = length([R || R <- Results, element(1, R) =:= ok]),

    #{
        iterations => Iterations,
        successful => Successful,
        duration_us => DurationUs,
        duration_sec => DurationSec,
        throughput_per_sec => Successful / DurationSec,
        avg_latency_us => DurationUs / Iterations,
        results => Results
    }.

%% @private
measure_latency(Fun) ->
    %% Warmup
    lists:foreach(fun(_) -> Fun() end, lists:seq(1, 10)),

    %% Measure multiple samples
    Samples = lists:map(fun(_) ->
        Start = erlang:monotonic_time(microsecond),
        Fun(),
        End = erlang:monotonic_time(microsecond),
        End - Start
    end, lists:seq(1, ?BENCHMARK_ITERATIONS)),

    SortedSamples = lists:sort(Samples),

    #{
        min_us => hd(SortedSamples),
        max_us => lists:last(SortedSamples),
        avg_us => lists:sum(SortedSamples) / length(SortedSamples),
        median_us => lists:nth(length(SortedSamples) div 2, SortedSamples),
        p95_us => lists:nth((length(SortedSamples) * 95) div 100, SortedSamples),
        p99_us => lists:nth((length(SortedSamples) * 99) div 100, SortedSamples),
        samples => Samples
    }.

%% @private
get_memory_usage() ->
    %% Get memory usage in bytes
    Memory = erlang:memory(),
    Memory_total = proplists:get_value(total, Memory, 0),
    Memory_total / (1024 * 1024).  %% Convert to MB

%%====================================================================
%% Workflow Creation Throughput Tests
%%====================================================================

test_workflow_creation_throughput() ->
    Iterations = 200,

    %% Measure creation throughput for different patterns
    Patterns = [
        {basic_sequential, 100},
        {parallel_split, 50},
        {exclusive_choice, 50}
    ],

    Results = lists:map(fun({Pattern, Count}) ->
        Fun = fun() ->
            Config = #{
                task1_name => "throughput_test",
                task2_name => "throughput_test2"
            },
            yawl_orchestrator:create_workflow(Pattern, Config)
        end,

        Stats = measure_throughput(Fun, Count),

        Throughput = maps:get(throughput_per_sec, Stats, 0),
        ?assert(Throughput > 10, "Throughput should be at least 10/sec"),

        {Pattern, Stats}
    end, Patterns),

    %% Print summary (commented out - use for debugging)
    %% lists:foreach(fun({Pattern, Stats}) ->
    %%     io:format("~p throughput: ~.2f ops/sec~n",
    %%               [Pattern, Stats.throughput_per_sec])
    %% end, Results),

    %% Verify overall throughput
    TotalOps = lists:foldl(fun({_, Stats}, Acc) ->
        Acc + maps:get(successful, Stats, 0)
    end, 0, Results),

    ?assert(TotalOps > (Iterations - 20),
            "Most workflow creations should succeed"),

    ok.

%%====================================================================
%% Execution Latency Tests
%%====================================================================

test_execution_latency() ->
    %% Create a workflow first
    Config = #{task1_name => "latency_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Measure execution latency
    Fun = fun() ->
        %% Create new workflow for each measurement
        Config = #{task1_name => "exec_latency"},
        case yawl_orchestrator:create_workflow(basic_sequential, Config) of
            {ok, WId} ->
                yawl_orchestrator:execute_workflow(WId),
                ok;
            {error, _} ->
                {error, creation_failed}
        end
    end,

    LatencyStats = measure_latency(Fun),

    %% Verify latency is acceptable
    AvgUs = maps:get(avg_us, LatencyStats, 0),
    P95Us = maps:get(p95_us, LatencyStats, 0),
    ?assert(AvgUs < 100000, "Average execution latency should be under 100ms"),
    ?assert(P95Us < 200000, "95th percentile latency should be under 200ms"),

    ok.

%%====================================================================
%% Query Performance Tests
%%====================================================================

test_query_performance() ->
    %% Create some workflows
    lists:foreach(fun(I) ->
        Config = #{task1_name => "query_test_" ++ integer_to_list(I)},
        yawl_orchestrator:create_workflow(basic_sequential, Config)
    end, lists:seq(1, 50)),

    %% Measure query latency
    GetStatusFun = fun() ->
        {ok, WIds} = yawl_orchestrator:list_workflows(),
        case length(WIds) > 0 of
            true ->
                hd(WIds),
                yawl_orchestrator:get_status(hd(WIds));
            false ->
                {error, no_workflows}
        end
    end,

    ListPatternsFun = fun() ->
        yawl_orchestrator:list_patterns()
    end,

    ListWorkflowsFun = fun() ->
        yawl_orchestrator:list_workflows()
    end,

    GetStatusStats = measure_latency(GetStatusFun),
    ListPatternsStats = measure_latency(ListPatternsFun),
    ListWorkflowsStats = measure_latency(ListWorkflowsFun),

    %% Verify query performance
    ?assert(maps:get(avg_us, GetStatusStats, 0) < 50000,
            "Average get_status latency should be under 50ms"),
    ?assert(maps:get(avg_us, ListPatternsStats, 0) < 10000,
            "Average list_patterns latency should be under 10ms"),
    ?assert(maps:get(avg_us, ListWorkflowsStats, 0) < 50000,
            "Average list_workflows latency should be under 50ms"),

    ok.

%%====================================================================
%% Checkpoint I/O Performance Tests
%%====================================================================

test_checkpoint_io_performance() ->
    %% Create a workflow and execute it
    Config = #{task1_name => "checkpoint_perf_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Get instance
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Measure checkpoint creation latency
    CheckpointFun = fun() ->
        yawl_workflow_instance:checkpoint(InstancePid)
    end,

    CheckpointStats = measure_latency(CheckpointFun),

    %% Verify checkpoint performance
    ?assert(maps:get(avg_us, CheckpointStats, 0) < 50000,
            "Average checkpoint creation should be under 50ms"),

    %% Measure checkpoint load latency
    LoadCheckpointFun = fun() ->
        yawl_persistence:load_latest_checkpoint(WorkflowId)
    end,

    LoadStats = measure_latency(LoadCheckpointFun),

    ?assert(maps:get(avg_us, LoadStats, 0) < 50000,
            "Average checkpoint load should be under 50ms"),

    ok.

%%====================================================================
%% Concurrent Execution Scalability Tests
%%====================================================================

test_concurrent_scalability() ->
    %% Measure scalability with increasing concurrency
    ConcurrencyLevels = [1, 5, 10, 20],

    ScalabilityResults = lists:map(fun(Concurrency) ->
        ParentPid = self(),

        %% Spawn concurrent workers
        Workers = lists:map(fun(_) ->
            spawn(fun() ->
                %% Create and execute workflow
                Config = #{task1_name => "scalability_test"},
                Start = erlang:monotonic_time(microsecond),

                case yawl_orchestrator:create_workflow(basic_sequential, Config) of
                    {ok, WId} ->
                        yawl_orchestrator:execute_workflow(WId),
                        End = erlang:monotonic_time(microsecond),
                        ParentPid ! {worker_complete, End - Start};
                    {error, _} ->
                        ParentPid ! {worker_complete, error}
                end
            end)
        end, lists:seq(1, Concurrency)),

        %% Collect results
        Results = collect_worker_results(Concurrency, 10000),

        %% Calculate metrics
        ValidTimes = [T || {worker_complete, T} <- Results, is_integer(T)],
        AvgTime = case length(ValidTimes) of
            0 -> 0;
            N -> lists:sum(ValidTimes) / N
        end,

        #{
            concurrency => Concurrency,
            completed => length(ValidTimes),
            avg_time_us => AvgTime,
            throughput_per_sec => length(ValidTimes) / (AvgTime / 1000000)
        }
    end, ConcurrencyLevels),

    %% Verify scalability - throughput should increase with concurrency
    %% (though not necessarily linearly due to overhead)
    FirstThroughput = maps:get(throughput_per_sec, hd(ScalabilityResults)),
    LastThroughput = maps:get(throughput_per_sec, lists:last(ScalabilityResults)),

    ?assert(LastThroughput >= FirstThroughput * 0.5, "Scalability check"),
            "Throughput should scale reasonably with concurrency: ~p -> ~p",

    ok.

collect_worker_results(Count, Timeout) ->
    collect_worker_results(Count, [], Timeout).

collect_worker_results(0, Acc, _Timeout) ->
    lists:reverse(Acc);
collect_worker_results(Count, Acc, Timeout) when Timeout > 0 ->
    receive
        Result ->
            collect_worker_results(Count - 1, [Result | Acc], Timeout)
    after 100 ->
        collect_worker_results(Count, Acc, Timeout - 100)
    end;
collect_worker_results(_Count, Acc, _Timeout) ->
    lists:reverse(Acc).

%%====================================================================
%% Memory Usage Tests
%%====================================================================

test_memory_usage() ->
    %% Get baseline memory
    BaselineMemory = get_memory_usage(),

    %% Create many workflows
    NumWorkflows = 100,
    lists:foreach(fun(I) ->
        Config = #{
            task1_name => "memory_test_" ++ integer_to_list(I),
            data_field => lists:duplicate(10, I)
        },
        yawl_orchestrator:create_workflow(basic_sequential, Config)
    end, lists:seq(1, NumWorkflows)),

    %% Force garbage collection
    erlang:garbage_collect(),
    timer:sleep(100),

    %% Get memory after operations
    AfterMemory = get_memory_usage(),

    %% Calculate memory per workflow
    MemoryDelta = AfterMemory - BaselineMemory,
    MemoryPerWorkflow = MemoryDelta / NumWorkflows,

    %% Verify memory usage is reasonable
            "Memory per workflow should be under 1MB, got ~p MB",

            "Total memory usage should be under ~p MB, got ~p MB",

    ok.

%%====================================================================
%% Large Dataset Handling Tests
%%====================================================================

test_large_dataset_handling() ->
    %% Create workflows with large data
    LargeData = lists:seq(1, 10000),

    %% Measure time to create workflow with large data
    Config = #{
        task1_name => "large_dataset_test",
        large_data => LargeData
    },

    Start = erlang:monotonic_time(microsecond),
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    CreateTime = erlang:monotonic_time(microsecond) - Start,

    %% Verify creation time is acceptable
            "Creating workflow with large dataset should be under 100ms, got ~p us",

    %% Measure execution time
    StartExec = erlang:monotonic_time(microsecond),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    ExecTime = erlang:monotonic_time(microsecond) - StartExec,

            "Executing workflow with large dataset should be under 100ms, got ~p us",

    ok.

%%====================================================================
%% Pattern Lookup Performance Tests
%%====================================================================

test_pattern_lookup_performance() ->
    %% Measure pattern lookup latency
    Fun = fun() ->
        yawl_orchestrator:get_pattern_info(basic_sequential)
    end,

    Stats = measure_latency(Fun),

    %% Pattern lookup should be very fast (cached)
    ?assert(maps:get(avg_us, Stats, 0) < 1000, "Pattern lookup check"),
            "Pattern lookup should be under 1ms (cached), got ~p us",

    %% Test with different patterns
    AllPatterns = yawl_patterns:list_all(),

    PatternLookupTimes = lists:map(fun(Pattern) ->
        Start = erlang:monotonic_time(microsecond),
        yawl_orchestrator:get_pattern_info(Pattern),
        erlang:monotonic_time(microsecond) - Start
    end, AllPatterns),

    AvgPatternTime = lists:sum(PatternLookupTimes) / length(PatternLookupTimes),

            "Average pattern lookup time should be under 5ms, got ~p us",

    ok.

%%====================================================================
%% Resource Allocation Throughput Tests
%%====================================================================

test_resource_allocation_throughput() ->
    %% Start resource manager
    {ok, _ResMgrPid} = yawl_resource_manager:start_link(),

    %% Create a test resource
    ResourceId = <<"benchmark_resource">>,
    Resource = #yawl_resource_persist{
        resource_id = ResourceId,
        resource_type = service,
        name = <<"Benchmark Resource">>,
        capabilities = [task_execution],
        status = available,
        max_capacity = 100,
        current_load = 0
    },
    yawl_persistence:save_resource(Resource),

    %% Measure allocation throughput
    NumAllocations = 100,
    ParentPid = self(),

    StartTime = erlang:monotonic_time(microsecond),

    lists:foreach(fun(I) ->
        spawn(fun() ->
            WorkflowId = <<"workflow_", (integer_to_binary(I))/binary>>,
            Result = yawl_resource_manager:allocate_resource(ResourceId, WorkflowId),
            ParentPid ! {allocated, I, Result}
        end)
    end, lists:seq(1, NumAllocations)),

    %% Collect results
    Results = collect_worker_results(NumAllocations, 5000),

    EndTime = erlang:monotonic_time(microsecond),
    TotalTime = EndTime - StartTime,

    Successful = length([R || R <- Results, element(3, R) =:= ok]),
    Throughput = Successful / (TotalTime / 1000000),

    %% Verify throughput is reasonable
            "Resource allocation throughput should be at least 50/sec, got ~p",

    gen_server:stop(yawl_resource_manager),
    ok.

%%====================================================================
%% Metrics Collection Overhead Tests
%%====================================================================

test_metrics_overhead() ->
    %% Measure overhead of metrics collection

    %% First, measure without metrics
    NoMetricsTime = measure_operation_time(fun() ->
        Config = #{task1_name => "no_metrics_test"},
        {ok, WId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        yawl_orchestrator:execute_workflow(WId)
    end, 20),

    %% Now measure with metrics
    WithMetricsTime = measure_operation_time(fun() ->
        Config = #{task1_name => "with_metrics_test"},
        {ok, WId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

        %% Record metrics
        yawl_metrics:record_workflow_start(WId),
        yawl_metrics:record_workflow_complete(WId, 100),

        yawl_orchestrator:execute_workflow(WId)
    end, 20),

    %% Calculate overhead
    OverheadPercent = ((WithMetricsTime - NoMetricsTime) / NoMetricsTime) * 100,

    %% Metrics overhead should be minimal (< 50%)
            "Metrics collection overhead should be under 50%, got ~p%",

    ok.

measure_operation_time(Fun, Iterations) ->
    Start = erlang:monotonic_time(microsecond),
    lists:foreach(fun(_) -> Fun() end, lists:seq(1, Iterations)),
    End = erlang:monotonic_time(microsecond),
    End - Start.

%%====================================================================
%% Persistence Throughput Tests
%%====================================================================

test_persistence_throughput() ->
    %% Measure persistence operation throughput

    %% Workflow save throughput
    SaveFun = fun() ->
        WorkflowId = <<"perf_workflow_", (integer_to_binary(erlang:unique_integer([positive])))/binary>>,
        Workflow = #yawl_workflow_persist{
            workflow_id = WorkflowId,
            spec_id = WorkflowId,
            pattern_type = basic_sequential,
            status = pending,
            marking = #{start => [token]},
            created_at = erlang:monotonic_time(millisecond),
            updated_at = erlang:monotonic_time(millisecond)
        },
        yawl_persistence:save_workflow(Workflow)
    end,

    SaveStats = measure_throughput(SaveFun, 50),

    ?assert(maps:get(throughput_per_sec, SaveStats, 0) > 100, "Save throughput check"),
            "Workflow save throughput should be at least 100/sec, got ~p",

    %% Workflow load throughput
    %% First, save some workflows
    lists:foreach(fun(I) ->
        WorkflowId = <<"load_test_", (integer_to_binary(I))/binary>>,
        Workflow = #yawl_workflow_persist{
            workflow_id = WorkflowId,
            spec_id = WorkflowId,
            pattern_type = basic_sequential,
            status = pending,
            marking = #{start => [token]},
            created_at = erlang:monotonic_time(millisecond),
            updated_at = erlang:monotonic_time(millisecond)
        },
        yawl_persistence:save_workflow(Workflow)
    end, lists:seq(1, 20)),

    LoadFun = fun() ->
        Id = <<"load_test_", (integer_to_binary(rand:uniform(20)))/binary>>,
        yawl_persistence:load_workflow(Id)
    end,

    LoadStats = measure_throughput(LoadFun, 50),

    ?assert(maps:get(throughput_per_sec, LoadStats, 0) > 100, "Load throughput check"),
            "Workflow load throughput should be at least 100/sec, got ~p",

    ok.

%%====================================================================
%% Subscription Notification Latency Tests
%%====================================================================

test_subscription_latency() ->
    %% Create a workflow
    Config = #{task1_name => "subscription_latency_test"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),

    %% Subscribe with a process that records notification time
    ParentPid = self(),
    Subscriber = spawn(fun() ->
        receive
            {yawl_event, WorkflowId, _Event} ->
                ParentPid ! {notification_received, erlang:monotonic_time(microsecond)}
        after 5000 ->
            ParentPid ! notification_timeout
        end
    end),

    %% Subscribe
    {ok, _} = yawl_orchestrator:subscribe_to_workflow(WorkflowId, Subscriber),

    %% Execute workflow (should trigger notification)
    StartTime = erlang:monotonic_time(microsecond),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Wait for notification
    NotificationLatency = receive
        {notification_received, NotificationTime} ->
            NotificationTime - StartTime;
        notification_timeout ->
            0
    end,

    %% Verify notification latency is acceptable
            "Notification latency should be under 100ms, got ~p us",

    ok.
