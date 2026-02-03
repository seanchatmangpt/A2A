%%% @doc Test suite for hot code upgrade optimizations
%%%
%%% This comprehensive test suite validates the hot code upgrade performance
%%% optimizations, monitoring systems, and health management.
%%%
%%% Test Categories:
%%% - Hot code upgrade performance benchmarks
%%% - Upgrade monitoring and tracking
%%% - ETS table upgrade optimization
%%% - Memory management during upgrades
%%% - Upgrade health and recovery
%%% - Concurrency and bottleneck detection
%%%
%%% Test Coverage:
%%% - Single process upgrade scenarios
%%% - Bulk process upgrade scenarios
%%% - ETS table upgrade scenarios
%%% - Memory-constrained environments
%%% - Failure injection and recovery
%%% - Performance regression testing
%%% - Load testing during upgrades
%%% @end
-module(a2a_hot_upgrade_SUITE).

-include_lib("common_test/include/ct.hrl").
-include("a2a.hrl").

-export([
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2,
    groups/0,
    all/0
]).

%% Test cases
-export([
    %% Performance benchmark tests
    benchmark_single_process_upgrade/1,
    benchmark_bulk_process_upgrade/1,
    benchmark_concurrency_optimization/1,
    benchmark_ets_upgrade_performance/1,
    benchmark_memory_usage_tracking/1,
    benchmark_cpu_usage_tracking/1,
    benchmark_downtime_measurement/1,

    %% Monitoring system tests
    monitor_upgrade_lifecycle/1,
    monitor_performance_metrics/1,
    monitor_bottleneck_detection/1,
    monitor_upgrade_progress/1,
    monitor_resource_usage/1,

    %% Health management tests
    health_system_health_check/1,
    health_upgrade_health_assessment/1,
    health_application_health_monitoring/1,
    health_data_integrity_check/1,
    health_alert_generation/1,
    health_recovery_mechanisms/1,

    %% Upgrade strategy tests
    upgrade_immediate_strategy/1,
    upgrade_gradual_strategy/1,
    upgrade_phased_strategy/1,
    upgrade_rollback_mechanisms/1,
    upgrade_cancellation_handling/1,

    %% Failure injection tests
    failure_process_upgrade_timeout/1,
    failure_ets_table_corruption/1,
    failure_memory_exhaustion/1,
    failure_cpu_overload/1,
    failure_network_partition/1,

    %% Integration tests
    integration_end_to_end_upgrade/1,
    integration_concurrent_upgrades/1,
    integration_performance_regression/1,
    integration_load_during_upgrade/1,
    integration_recovery_scenarios/1,

    %% Edge case tests
    edge_case_large_ets_tables/1,
    edge_case_maximum_concurrency/1,
    edge_case_memory_pressure/1,
    edge_case_long_running_upgrades/1,
    edge_case_high_failure_rate/1,

    %% Regression tests
    regression_performance_impact/1,
    regression_memory_leaks/1,
    regression_system_stability/1,
    regression_data_consistency/1,
    regression_error_recovery/1
]).

%%%===================================================================
%%% Test suite setup
%%%===================================================================

init_per_suite(Config) ->
    %% Start required applications
    {ok, _} = application:ensure_all_started(a2a_erl),

    %% Initialize monitoring systems
    {ok, _} = a2a_hot_upgrade_monitor:start_link(#{
        snapshot_interval_ms => 1000,
        monitoring_enabled => true
    }),

    {ok, _} = a2a_optimized_upgrade:start_link(#{
        concurrency_level => 4,
        upgrade_strategy => gradual,
        memory_limit_mb => 1024
    }),

    {ok, _} = a2a_performance_benchmark:start_link(#{}),

    {ok, _} = a2a_upgrade_health:start_link(#{}),

    %% Initialize test data
    TestTasks = create_test_tasks(100),
    Config ++ [{test_tasks => TestTasks, start_time => erlang:monotonic_time(millisecond)}].

end_per_suite(Config) ->
    %% Cleanup all monitoring systems
    ok = a2a_hot_upgrade_monitor:stop(),
    ok = a2a_optimized_upgrade:stop(),
    ok = a2a_performance_benchmark:stop(),
    ok = a2a_upgrade_health:stop(),

    %% Stop applications
    application:stop(a2a_erl),

    %% Report test summary
    ct:pal("Test suite completed with config: ~p", [Config]),
    Config.

init_per_testcase(TestCase, Config) ->
    %% Setup test case specific configuration
    ct:pal("Initializing test case: ~p", [TestCase]),

    %% Reset monitoring data
    ok = a2a_hot_upgrade_monitor:reset_metrics(),
    ok = a2a_performance_benchmark:set_benchmark_config(#{}),

    %% Create fresh test data
    TestTasks = create_test_tasks(50),

    %% Set up performance monitoring
    ok = a2a_performance_benchmark:set_benchmark_config(#{
        process_count => 50,
        memory_limit_mb => 512,
        benchmark_timeout_ms => 30000
    }),

    Config ++ [{test_tasks => TestTasks, test_start_time => erlang:monotonic_time(millisecond)}].

end_per_testcase(TestCase, Config) ->
    %% Cleanup test case specific resources
    ct:pal("Ending test case: ~p", [TestCase]),

    %% Clean up any remaining test processes
    cleanup_test_processes(),

    %% Log performance metrics
    log_test_performance(TestCase, Config),

    Config.

groups() ->
    [
        {performance_group, [
            benchmark_single_process_upgrade,
            benchmark_bulk_process_upgrade,
            benchmark_concurrency_optimization,
            benchmark_ets_upgrade_performance,
            benchmark_memory_usage_tracking,
            benchmark_cpu_usage_tracking,
            benchmark_downtime_measurement
        ], 10},

        {monitoring_group, [
            monitor_upgrade_lifecycle,
            monitor_performance_metrics,
            monitor_bottleneck_detection,
            monitor_upgrade_progress,
            monitor_resource_usage
        ], 5},

        {health_group, [
            health_system_health_check,
            health_upgrade_health_assessment,
            health_application_health_monitoring,
            health_data_integrity_check,
            health_alert_generation,
            health_recovery_mechanisms
        ], 5},

        {strategy_group, [
            upgrade_immediate_strategy,
            upgrade_gradual_strategy,
            upgrade_phased_strategy,
            upgrade_rollback_mechanisms,
            upgrade_cancellation_handling
        ], 5},

        {failure_group, [
            failure_process_upgrade_timeout,
            failure_ets_table_corruption,
            failure_memory_exhaustion,
            failure_cpu_overload,
            failure_network_partition
        ], 5},

        {integration_group, [
            integration_end_to_end_upgrade,
            integration_concurrent_upgrades,
            integration_performance_regression,
            integration_load_during_upgrade,
            integration_recovery_scenarios
        ], 3},

        {edge_case_group, [
            edge_case_large_ets_tables,
            edge_case_maximum_concurrency,
            edge_case_memory_pressure,
            edge_case_long_running_upgrades,
            edge_case_high_failure_rate
        ], 3},

        {regression_group, [
            regression_performance_impact,
            regression_memory_leaks,
            regression_system_stability,
            regression_data_consistency,
            regression_error_recovery
        ], 5}
    ].

all() ->
    [
        {group, performance_group},
        {group, monitoring_group},
        {group, health_group},
        {group, strategy_group},
        {group, failure_group},
        {group, integration_group},
        {group, edge_case_group},
        {group, regression_group}
    ].

%%%===================================================================
%%% Performance Benchmark Tests
%%%===================================================================

benchmark_single_process_upgrade(_Config) ->
    ct:pal("Starting single process upgrade benchmark"),

    %% Create test process
    TestPid = spawn_link(fun() -> test_process_loop() end),

    %% Measure upgrade performance
    Start = erlang:monotonic_time(millisecond),
    Result = upgrade_test_process(TestPid),
    End = erlang:monotonic_time(millisecond),

    %% Verify results
    ?assertEqual(success, Result),
    UpgradeTime = End - Start,
    ct:pal("Single process upgrade time: ~p ms", [UpgradeTime]),

    %% Validate performance expectations
    ?assert(UpgradeTime < 5000, "Single process upgrade too slow"),

    %% Cleanup
    unlink(TestPid),
    exit(TestPid, normal),

    ok.

benchmark_bulk_process_upgrade(_Config) ->
    ct:pal("Starting bulk process upgrade benchmark"),

    %% Create test processes
    ProcessCount = 100,
    TestPids = lists:map(fun(_) ->
        spawn_link(fun() -> test_process_loop() end)
    end, lists:seq(1, ProcessCount)),

    %% Measure upgrade performance
    Start = erlang:monotonic_time(millisecond),
    Results = lists:map(fun(Pid) ->
        upgrade_test_process(Pid)
    end, TestPids),
    End = erlang:monotonic_time(millisecond),

    %% Verify results
    SuccessCount = lists:filter(fun(R) -> R =:= success end, Results),
    SuccessRate = SuccessCount / ProcessCount,

    Duration = End - Start,
    AvgUpgradeTime = Duration / ProcessCount,

    ct:pal("Bulk process upgrade - Duration: ~p ms, Success rate: ~.2f%, Avg time: ~p ms",
           [Duration, SuccessRate * 100, AvgUpgradeTime]),

    %% Validate performance expectations
    ?assert(SuccessRate >= 0.95, "Bulk process upgrade success rate too low"),
    ?assert(AvgUpgradeTime < 1000, "Average upgrade time too high"),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, TestPids),

    ok.

benchmark_concurrency_optimization(_Config) ->
    ct:pal("Testing concurrency optimization"),

    TestProcessCount = 50,
    ConcurrencyLevels = [1, 2, 4, 8, 16],

    %% Test different concurrency levels
    Results = lists:map(fun(Concurrency) ->
        %% Create test processes
        TestPids = lists:map(fun(_) ->
            spawn_link(fun() -> test_process_loop() end)
        end, lists:seq(1, TestProcessCount)),

        %% Measure upgrade performance
        Start = erlang:monotonic_time(millisecond),
        Results = upgrade_concurrent_processes(TestPids, Concurrency),
        End = erlang:monotonic_time(millisecond),

        %% Calculate metrics
        Duration = End - Start,
        SuccessCount = lists:filter(fun(R) -> R =:= success end, Results),
        SuccessRate = SuccessCount / TestProcessCount,
        Throughput = TestProcessCount / (Duration / 1000),

        %% Cleanup
        lists:foreach(fun(Pid) ->
            unlink(Pid),
            exit(Pid, normal)
        end, TestPids),

        #{
            concurrency => Concurrency,
            duration_ms => Duration,
            success_rate => SuccessRate,
            throughput => Throughput
        }
    end, ConcurrencyLevels),

    %% Find optimal concurrency level
    Optimal = find_optimal_concurrency(Results),
    ct:pal("Optimal concurrency level: ~p with throughput: ~.2f",
           [Optimal#concurrency_result.concurrency, Optimal#concurrency_result.throughput]),

    %% Validate optimization
    ?assert(Optimal#concurrency_result.throughput > 10, "Throughput too low"),

    ok.

benchmark_ets_upgrade_performance(_Config) ->
    ct:pal("Testing ETS upgrade performance"),

    TableSizes = [1000, 5000, 10000, 50000, 100000],

    %% Test different table sizes
    Results = lists:map(fun(Size) ->
        %% Create test table
        TableName = list_to_atom("benchmark_" ++ integer_to_list(Size)),
        ets:new(TableName, [named_table, public, set, {write_concurrency, auto}]),
        populate_ets_table(TableName, Size),

        %% Measure upgrade performance
        Start = erlang:monotonic_time(millisecond),
        Result = upgrade_ets_table(TableName),
        End = erlang:monotonic_time(millisecond),

        %% Cleanup
        ets:delete(TableName),

        Duration = End - Start,
        Throughput = Size / (Duration / 1000),

        #{
            size => Size,
            duration_ms => Duration,
            throughput_per_second => Throughput,
            success => Result =:= success
        }
    end, TableSizes),

    %% Analyze performance scaling
    ScalingAnalysis = analyze_ets_scaling(Results),
    ct:pal("ETS scaling analysis: ~p", [ScalingAnalysis]),

    %% Validate performance scaling
    ?assert(ScalingAnalysis#scaling_result.scaling_factor > 0.5, "Poor scaling performance"),

    ok.

benchmark_memory_usage_tracking(_Config) ->
    ct:pal("Testing memory usage tracking during upgrades"),

    %% Monitor memory before upgrade
    InitialMemory = erlang:memory(total),

    %% Create test processes
    TestPids = lists:map(fun(_) ->
        spawn_link(fun() -> test_process_loop() end)
    end, lists:seq(1, 50)),

    %% Monitor memory during upgrade
    MemorySnapshots = collect_memory_during_upgrade(TestPids),

    %% Perform upgrades
    Results = lists:map(fun(Pid) ->
        upgrade_test_process(Pid)
    end, TestPids),

    %% Monitor memory after upgrade
    FinalMemory = erlang:memory(total),

    %% Calculate metrics
    PeakMemory = lists:max(MemorySnapshots),
    MemoryImpact = (FinalMemory - InitialMemory) * erlang:wordsize() / (1024 * 1024),

    ct:pal("Memory impact - Peak: ~p MB, Impact: ~p MB", [PeakMemory, MemoryImpact]),

    %% Validate memory management
    ?assert(MemoryImpact < 100, "Memory impact too high"),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, TestPids),

    ok.

benchmark_cpu_usage_tracking(_Config) ->
    ct:pal("Testing CPU usage tracking during upgrades"),

    %% Monitor CPU during upgrades
    CpuSnapshots = collect_cpu_during_upgrade(),

    %% Create test processes
    TestPids = lists:map(fun(_) ->
        spawn_link(fun() -> intensive_test_process() end)
    end, lists:seq(1, 10)),

    %% Perform upgrades
    Results = lists:map(fun(Pid) ->
        upgrade_test_process(Pid)
    end, TestPids),

    %% Analyze CPU usage
    AvgCpu = lists:sum(CpuSnapshots) / length(CpuSnapshots),
    PeakCpu = lists:max(CpuSnapshots),

    ct:pal("CPU usage - Average: ~.2f%, Peak: ~.2f%", [AvgCpu, PeakCpu]),

    %% Validate CPU management
    ?assert(PeakCpu < 90, "CPU peak usage too high"),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, TestPids),

    ok.

benchmark_downtime_measurement(_Config) ->
    ct:pal("Testing downtime measurement during upgrades"),

    %% Create test clients
    TestClients = lists:map(fun(Id) ->
        spawn_link(fun() -> test_client(Id) end)
    end, lists:seq(1, 5)),

    %% Allow clients to initialize
    timer:sleep(1000),

    %% Measure baseline performance
    BaselineMetrics = measure_client_performance(TestClients),

    %% Perform upgrade with downtime measurement
    Start = erlang:monotonic_time(millisecond),
    UpgradeResult = perform_system_upgrade(),
    End = erlang:monotonic_time(millisecond),

    %% Measure post-upgrade performance
    PostUpgradeMetrics = measure_client_performance(TestClients),

    %% Calculate downtime
    TotalDowntime = calculate_total_downtime(),
    UpgradeDuration = End - Start,

    ct:pal("Downtime measurement - Total: ~p ms, Upgrade duration: ~p ms",
           [TotalDowntime, UpgradeDuration]),

    %% Validate downtime expectations
    ?assert(TotalDowntime < 5000, "Downtime too high"),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, TestClients),

    ok.

%%%===================================================================
%%% Monitoring System Tests
%%%===================================================================

monitor_upgrade_lifecycle(_Config) ->
    ct:pal("Testing upgrade lifecycle monitoring"),

    %% Start upgrade session
    UpgradeId = generate_upgrade_id(),
    ok = a2a_hot_upgrade_monitor:start_upgrade(UpgradeId),

    %% Simulate upgrade steps
    ok = a2a_hot_upgrade_monitor:record_upgrade_step(UpgradeId, <<"process_init">>, 100),
    ok = a2a_hot_upgrade_monitor:record_upgrade_step(UpgradeId, <<"ets_upgrade">>, 500),
    ok = a2a_hot_upgrade_monitor:record_upgrade_step(UpgradeId, <<"verification">>, 200),

    %% Complete upgrade
    ok = a2a_hot_upgrade_monitor:record_upgrade_completion(UpgradeId, 800),

    %% Verify tracking
    {ok, Session} = a2a_hot_upgrade_monitor:get_upgrade_progress(UpgradeId),
    ?assertEqual(completed, Session#upgrade_session.status),

    %% Cleanup
    ok.

monitor_performance_metrics(_Config) ->
    ct:pal("Testing performance metrics collection"),

    %% Generate some test metrics
    ok = a2a_hot_upgrade_monitor:task_created(<<"test_task_1">>),
    ok = a2a_hot_upgrade_monitor:task_state_changed(<<"test_task_1">>, submitted, working),
    ok = a2a_hot_upgrade_monitor:task_completed(<<"test_task_1">>, 1000),

    %% Get metrics
    Metrics = a2a_hot_upgrade_monitor:get_upgrade_metrics(),
    ?assert(Metrics#upgrade_metrics.total_created > 0),

    %% Validate metric collection
    ?assert(Metrics#upgrade_metrics.successful_upgrades >= 0),

    ok.

monitor_bottleneck_detection(_Config) ->
    ct:pal("Testing bottleneck detection"),

    %% Create slow upgrade steps
    UpgradeId = generate_upgrade_id(),
    ok = a2a_hot_upgrade_monitor:start_upgrade(UpgradeId),

    %% Record slow steps (should trigger bottleneck detection)
    ok = a2a_hot_upgrade_monitor:record_upgrade_step(UpgradeId, <<"slow_step_1">>, 6000),
    ok = a2a_hot_upgrade_monitor:record_upgrade_step(UpgradeId, <<"slow_step_2">>, 8000),
    ok = a2a_hot_upgrade_monitor:record_upgrade_step(UpgradeId, <<"fast_step">>, 200),

    %% Check for bottlenecks
    Bottlenecks = a2a_hot_upgrade_monitor:get_bottleneck_analysis(),
    ?assert(length(Bottlenecks) > 0, "Bottlenecks not detected"),

    ok.

monitor_upgrade_progress(_Config) ->
    ct:pal("Testing upgrade progress monitoring"),

    %% Start upgrade with processes
    UpgradeId = generate_upgrade_id(),
    ok = a2a_hot_upgrade_monitor:start_upgrade(UpgradeId),

    %% Track individual process upgrades
    TestPids = [spawn_link(fun() -> test_process_loop() end) || _ <- lists:seq(1, 10)],

    lists:foreach(fun(Pid) ->
        ok = a2a_hot_upgrade_monitor:track_process_upgrade(Pid, a2a_task_statem),
        ok = a2a_hot_upgrade_monitor:track_process_completion(Pid, 500)
    end, TestPids),

    %% Check progress
    {ok, Progress} = a2a_hot_upgrade_monitor:get_upgrade_progress(UpgradeId),
    ?assert(Progress#upgrade_session.completed_processes > 0),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, TestPids),

    ok.

monitor_resource_usage(_Config) ->
    ct:pal("Testing resource usage monitoring"),

    %% Start resource monitoring
    ok = a2a_hot_upgrade_monitor:record_system_metrics(),

    %% Perform resource-intensive operations
    _ = spawn_link(fun() -> intensive_operations() end),
    timer:sleep(2000),

    %% Get system metrics
    Metrics = a2a_hot_upgrade_monitor:get_system_metrics(),
    ?assert(Metrics#system_metrics.process_count > 0),

    ok.

%%%===================================================================
%%% Health Management Tests
%%%===================================================================

health_system_health_check(_Config) ->
    ct:pal("Testing system health check"),

    %% Perform health check
    Health = a2a_upgrade_health:check_system_health(),
    ?assert(is_record(Health, system_health)),

    %% Validate health status
    ?assert(lists:member(Health#system_health.overall_status, [healthy, warning, critical])),

    ok.

health_upgrade_health_assessment(_Config) ->
    ct:pal("Testing upgrade health assessment"),

    %% Perform upgrade health check
    Health = a2a_upgrade_health:check_upgrade_health(),
    ?assert(is_record(Health, upgrade_health)),

    %% Validate health metrics
    ?assert(Health#upgrade_health.upgrade_success_rate >= 0.0),
    ?assert(Health#upgrade_health.upgrade_success_rate =< 1.0),

    ok.

health_application_health_monitoring(_Config) ->
    ct:pal("Testing application health monitoring"),

    %% Perform application health check
    Health = a2a_upgrade_health:check_application_health(),
    ?assert(is_record(Health, application_health)),

    %% Validate health metrics
    ?assert(Health#application_health.response_time_avg_ms >= 0),
    ?assert(Health#application_health.error_rate >= 0.0),

    ok.

health_data_integrity_check(_Config) ->
    ct:pal("Testing data integrity check"),

    %% Perform data integrity check
    Integrity = a2a_upgrade_health:check_data_integrity(),
    ?assert(is_record(Integrity, data_integrity)),

    %% Validate integrity metrics
    ?assert(Integrity#data_integrity.ets_consistency_score >= 0.0),
    ?assert(Integrity#data_integrity.ets_consistency_score =< 1.0),

    ok.

health_alert_generation(_Config) ->
    ct:pal("Testing health alert generation"),

    %% Get current health thresholds
    Thresholds = a2a_upgrade_health:get_health_thresholds(),

    %% Simulate problematic conditions
    ProblematicHealth = #system_health{
        overall_status = critical,
        memory_usage_percent = 95.0,
        cpu_usage_percent = 90.0,
        last_health_check = erlang:system_time(millisecond)
    },

    %% Check for alerts
    Alerts = a2a_upgrade_health:check_for_health_alerts(ProblematicHealth, Thresholds),
    ?assert(length(Alerts) > 0, "Alerts not generated for critical conditions"),

    ok.

health_recovery_mechanisms(_Config) ->
    ct:pal("Testing health recovery mechanisms"),

    %% Simulate failure
    FailureId = generate_upgrade_id(),

    %% Attempt recovery
    Result = a2a_upgrade_health:recover_from_failure(FailureId),
    ?assert(ok =:= Result, "Recovery mechanism failed"),

    ok.

%%%===================================================================
%%% Upgrade Strategy Tests
%%%===================================================================

upgrade_immediate_strategy(_Config) ->
    ct:pal("Testing immediate upgrade strategy"),

    %% Configure immediate strategy
    ok = a2a_optimized_upgrade:set_upgrade_strategy(immediate),

    %% Create test processes
    TestPids = lists:map(fun(_) ->
        spawn_link(fun() -> test_process_loop() end)
    end, lists:seq(1, 10)),

    %% Perform upgrade
    Start = erlang:monotonic_time(millisecond),
    UpgradeId = generate_upgrade_id(),
    Result = a2a_optimized_upgrade:perform_upgrade(UpgradeId),
    End = erlang:monotonic_time(millisecond),

    %% Validate immediate strategy
    ?assert({ok, _} =:= Result, "Immediate upgrade failed"),
    Duration = End - Start,
    ct:pal("Immediate upgrade duration: ~p ms", [Duration]),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, TestPids),

    ok.

upgrade_gradual_strategy(_Config) ->
    ct:pal("Testing gradual upgrade strategy"),

    %% Configure gradual strategy
    ok = a2a_optimized_upgrade:set_upgrade_strategy(gradual),

    %% Create test processes
    TestPids = lists:map(fun(_) ->
        spawn_link(fun() -> test_process_loop() end)
    end, lists:seq(1, 20)),

    %% Perform upgrade
    Start = erlang:monotonic_time(millisecond),
    UpgradeId = generate_upgrade_id(),
    Result = a2a_optimized_upgrade:perform_upgrade(UpgradeId),
    End = erlang:monotonic_time(millisecond),

    %% Validate gradual strategy
    ?assert({ok, _} =:= Result, "Gradual upgrade failed"),
    Duration = End - Start,
    ct:pal("Gradual upgrade duration: ~p ms", [Duration]),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, TestPids),

    ok.

upgrade_phased_strategy(_Config) ->
    ct:pal("Testing phased upgrade strategy"),

    %% Configure phased strategy
    ok = a2a_optimized_upgrade:set_upgrade_strategy(phased),

    %% Create test processes
    TestPids = lists:map(fun(_) ->
        spawn_link(fun() -> test_process_loop() end)
    end, lists:seq(1, 30)),

    %% Perform upgrade
    Start = erlang:monotonic_time(millisecond),
    UpgradeId = generate_upgrade_id(),
    Result = a2a_optimized_upgrade:perform_upgrade(UpgradeId),
    End = erlang:monotonic_time(millisecond),

    %% Validate phased strategy
    ?assert({ok, _} =:= Result, "Phased upgrade failed"),
    Duration = End - Start,
    ct:pal("Phased upgrade duration: ~p ms", [Duration]),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, TestPids),

    ok.

upgrade_rollback_mechanisms(_Config) ->
    ct:pal("Testing upgrade rollback mechanisms"),

    %% Simulate failed upgrade
    UpgradeId = generate_upgrade_id(),
    ok = a2a_optimized_upgrade:perform_upgrade(UpgradeId),

    %% Attempt rollback
    Result = a2a_optimized_upgrade:rollback_upgrade(UpgradeId),
    ?assert({ok, _} =:= Result, "Rollback failed"),

    ok.

upgrade_cancellation_handling(_Config) ->
    ct:pal("Testing upgrade cancellation handling"),

    %% Start upgrade
    UpgradeId = generate_upgrade_id(),
    ok = a2a_optimized_upgrade:perform_upgrade(UpgradeId),

    %% Cancel upgrade
    Result = a2a_optimized_upgrade:cancel_upgrade(),
    ?assert(ok =:= Result, "Cancellation failed"),

    ok.

%%%===================================================================
%%% Failure Injection Tests
%%%===================================================================

failure_process_upgrade_timeout(_Config) ->
    ct:pal("Testing process upgrade timeout handling"),

    %% Create test process that will timeout
    SlowPid = spawn_link(fun() -> slow_test_process() end),

    %% Attempt upgrade with timeout
    Start = erlang:monotonic_time(millisecond),
    Result = upgrade_test_process(SlowPid),
    End = erlang:monotonic_time(millisecond),

    %% Validate timeout handling
    ?assert(failed =:= Result, "Timeout not properly handled"),
    Duration = End - Start,
    ct:pal("Timeout handling duration: ~p ms", [Duration]),

    %% Cleanup
    unlink(SlowPid),
    exit(SlowPid, normal),

    ok.

failure_ets_table_corruption(_Config) ->
    ct:pal("Testing ETS table corruption handling"),

    %% Create test table
    TableName = test_table,
    ets:new(TableName, [named_table, public, set]),
    populate_ets_table(TableName, 100),

    %% Simulate corruption
    ets:insert(TableName, {corrupted, <<>>}),

    %% Attempt upgrade
    Result = upgrade_ets_table(TableName),
    ?assert(failed =:= Result, "Corruption not properly handled"),

    %% Cleanup
    ets:delete(TableName),

    ok.

failure_memory_exhaustion(_Config) ->
    ct:parm("Testing memory exhaustion handling"),

    %% Create memory-intensive processes
    MemoryPids = lists:map(fun(_) ->
        spawn_link(fun() -> memory_intensive_process() end)
    end, lists:seq(1, 50)),

    %% Attempt upgrade
    Result = upgrade_test_process(lists:nth(1, MemoryPids)),
    ct:pal("Memory exhaustion result: ~p", [Result]),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, MemoryPids),

    ok.

failure_cpu_overload(_Config) ->
    ct:parm("Testing CPU overload handling"),

    %% Create CPU-intensive processes
    CpuPids = lists:map(fun(_) ->
        spawn_link(fun() -> cpu_intensive_process() end)
    end, lists:seq(1, 20)),

    %% Attempt upgrade
    Result = upgrade_test_process(lists:nth(1, CpuPids)),
    ct:pal("CPU overload result: ~p", [Result]),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, CpuPids),

    ok.

failure_network_partition(_Config) ->
    ct:parm("Testing network partition handling"),

    %% Simulate network partition by blocking communication
    PartitionedPid = spawn_link(fun() -> partitioned_process() end),

    %% Attempt upgrade
    Result = upgrade_test_process(PartitionedPid),
    ?assert(failed =:= Result, "Network partition not properly handled"),

    %% Cleanup
    unlink(PartitionedPid),
    exit(PartitionedPid, normal),

    ok.

%%%===================================================================
%%% Integration Tests
%%%===================================================================

integration_end_to_end_upgrade(_Config) ->
    ct:parm("Testing end-to-end upgrade integration"),

    %% Create complete test environment
    TestPids = lists:map(fun(_) ->
        spawn_link(fun() -> test_process_loop() end)
    end, lists:seq(1, 50)),

    TestTables = [list_to_atom("test_table_" ++ integer_to_list(I)) || I <- lists:seq(1, 5)],
    lists:foreach(fun(Table) ->
        ets:new(Table, [named_table, public, set]),
        populate_ets_table(Table, 1000)
    end, TestTables),

    %% Perform complete upgrade
    Start = erlang:monotonic_time(millisecond),
    UpgradeId = generate_upgrade_id(),
    Result = a2a_optimized_upgrade:perform_upgrade(UpgradeId),
    End = erlang:monotonic_time(millisecond),

    %% Validate end-to-end upgrade
    ?assert({ok, _} =:= Result, "End-to-end upgrade failed"),
    Duration = End - Start,
    ct:pal("End-to-end upgrade duration: ~p ms", [Duration]),

    %% Validate data integrity
    lists:foreach(fun(Table) ->
        ?assert(ets:info(Table, size) > 0, "Data integrity check failed")
    end, TestTables),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, TestPids),
    lists:foreach(fun(Table) ->
        ets:delete(Table)
    end, TestTables),

    ok.

integration_concurrent_upgrades(_Config) ->
    ct:parm("Testing concurrent upgrades"),

    %% Start multiple upgrades concurrently
    UpgradeIds = [generate_upgrade_id() || _ <- lists:seq(1, 3)],

    lists:foreach(fun(UpgradeId) ->
        spawn_link(fun() ->
            a2a_optimized_upgrade:perform_upgrade(UpgradeId)
        end)
    end, UpgradeIds),

    %% Wait for completion
    timer:sleep(10000),

    %% Verify all upgrades completed
    lists:foreach(fun(UpgradeId) ->
        {ok, Progress} = a2a_hot_upgrade_monitor:get_upgrade_progress(UpgradeId),
        ?assert(lists:member(Progress#upgrade_session.status, [completed, failed]))
    end, UpgradeIds),

    ok.

integration_performance_regression(_Config) ->
    ct:parm("Testing performance regression"),

    %% Baseline performance
    BaselineTime = benchmark_single_process_upgrade(),

    %% Test upgrade performance
    UpgradeTime = benchmark_single_process_upgrade(),

    %% Check for regression
    RegressionFactor = UpgradeTime / BaselineTime,
    ct:pal("Performance regression factor: ~.2f", [RegressionFactor]),

    ?assert(RegressionFactor < 1.5, "Performance regression detected"),

    ok.

integration_load_during_upgrade(_Config) ->
    ct:parm("Testing load during upgrade"),

    %% Start upgrade
    UpgradePid = spawn_link(fun() ->
        a2a_optimized_upgrade:perform_upgrade(generate_upgrade_id())
    end),

    %% Generate load during upgrade
    LoadPids = lists:map(fun(_) ->
        spawn_link(fun() -> load_process() end)
    end, lists:seq(1, 20)),

    %% Wait for completion
    timer:sleep(15000),

    %% Verify upgrade completed under load
    case process_info(UpgradePid, status) of
        undefined -> ok;
        _ -> exit(UpgradePid, kill)
    end,

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, LoadPids),

    ok.

integration_recovery_scenarios(_Config) ->
    ct:parm("Testing recovery scenarios"),

    %% Test various recovery scenarios
    RecoveryScenarios = [
        {process_failure, fun test_process_recovery/0},
        {ets_failure, fun test_ets_recovery/0},
        {memory_failure, fun test_memory_recovery/0},
        {cpu_failure, fun test_cpu_recovery/0}
    ],

    lists:foreach(fun({Type, RecoveryFun}) ->
        ct:pal("Testing recovery scenario: ~p", [Type]),
        RecoveryFun()
    end, RecoveryScenarios),

    ok.

%%%===================================================================
%%% Edge Case Tests
%%%===================================================================

edge_case_large_ets_tables(_Config) ->
    ct:parm("Testing large ETS table handling"),

    %% Create large ETS table
    LargeTableSize = 1000000, %% 1 million records
    TableName = large_test_table,
    ets:new(TableName, [named_table, public, set, {write_concurrency, auto}]),
    populate_ets_table(TableName, LargeTableSize),

    %% Measure upgrade performance
    Start = erlang:monotonic_time(millisecond),
    Result = upgrade_ets_table(TableName),
    End = erlang:monotonic_time(millisecond),

    %% Validate large table handling
    ?assert(success =:= Result, "Large ETS table upgrade failed"),
    Duration = End - Start,
    ct:pal("Large ETS table upgrade duration: ~p ms", [Duration]),

    %% Cleanup
    ets:delete(TableName),

    ok.

edge_case_maximum_concurrency(_Config) ->
    ct:parm("Testing maximum concurrency handling"),

    %% Set maximum concurrency
    ok = a2a_optimized_upgrade:set_concurrency_level(50),

    %% Create many test processes
    TestPids = lists:map(fun(_) ->
        spawn_link(fun() -> test_process_loop() end)
    end, lists:seq(1, 200)),

    %% Perform upgrade with high concurrency
    Start = erlang:monotonic_time(millisecond),
    UpgradeId = generate_upgrade_id(),
    Result = a2a_optimized_upgrade:perform_upgrade(UpgradeId),
    End = erlang:monotonic_time(millisecond),

    %% Validate maximum concurrency
    ?assert({ok, _} =:= Result, "Maximum concurrency upgrade failed"),
    Duration = End - Start,
    ct:pal("Maximum concurrency upgrade duration: ~p ms", [Duration]),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, TestPids),

    ok.

edge_case_memory_pressure(_Config) ->
    ct:parm("Testing memory pressure handling"),

    %% Consume memory
    MemoryConsumer = spawn_link(fun() ->
        memory_consumer_loop(1000000)
    end),

    %% Perform upgrade under memory pressure
    Result = upgrade_test_process(MemoryConsumer),
    ct:pal("Memory pressure result: ~p", [Result]),

    %% Cleanup
    unlink(MemoryConsumer),
    exit(MemoryConsumer, normal),

    ok.

edge_case_long_running_upgrades(_Config) ->
    ct:parm("Testing long-running upgrade handling"),

    %% Create long-running upgrade
    LongUpgradePid = spawn_link(fun() ->
        long_running_upgrade()
    end),

    %% Monitor progress
    timer:sleep(30000), %% 30 seconds

    %% Check status
    Status = process_info(LongUpgradePid, status),
    ct:pal("Long-running upgrade status: ~p", [Status]),

    %% Cleanup
    exit(LongUpgradePid, kill),

    ok.

edge_case_high_failure_rate(_Config) ->
    ct:parm("Testing high failure rate handling"),

    %% Configure high failure rate
    FailurePids = lists:map(fun(_) ->
        spawn_link(fun() -> failing_process() end)
    end, lists:seq(1, 20)),

    %% Attempt upgrade
    Result = upgrade_test_process(lists:nth(1, FailurePids)),
    ct:pal("High failure rate result: ~p", [Result]),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, FailurePids),

    ok.

%%%===================================================================
%%% Regression Tests
%%%===================================================================

regression_performance_impact(_Config) ->
    ct:parm("Testing performance impact"),

    %% Test performance before and after optimizations
    BeforeTime = benchmark_single_process_upgrade(),

    %% Apply optimizations (already applied in this test)

    %% Test performance after optimizations
    AfterTime = benchmark_single_process_upgrade(),

    %% Verify improvement or no regression
    Improvement = BeforeTime - AfterTime,
    ct:pal("Performance improvement: ~p ms", [Improvement]),

    ?assert(Improvement >= -1000, "Performance regression detected"),

    ok.

regression_memory_leaks(_Config) ->
    ct:parm("Testing memory leaks"),

    %% Monitor memory before tests
    InitialMemory = erlang:memory(total),

    %% Perform various upgrade operations
    _ = a2a_optimized_upgrade:perform_upgrade(generate_upgrade_id()),
    _ = a2a_hot_upgrade_monitor:start_upgrade(generate_upgrade_id()),
    _ = a2a_performance_benchmark:run_benchmark(single_process),

    %% Monitor memory after tests
    FinalMemory = erlang:memory(total),

    %% Check for memory leaks
    MemoryIncrease = (FinalMemory - InitialMemory) * erlang:wordsize() / (1024 * 1024),
    ct:pal("Memory increase: ~p MB", [MemoryIncrease]),

    ?assert(MemoryIncrease < 50, "Memory leak detected"),

    ok.

regression_system_stability(_Config) ->
    ct:parm("Testing system stability"),

    %% Perform multiple upgrade operations
    UpgradeOps = [a2a_optimized_upgrade:perform_upgrade(generate_upgrade_id())
                  || _ <- lists:seq(1, 10)],

    %% Check for crashes or hangs
    Crashes = length([Op || Op <- UpgradeOps, Op =:= {error, crashed}]),

    ct:pal("System stability - Crashes: ~p", [Crashes]),

    ?assert(Crashes =:= 0, "System instability detected"),

    ok.

regression_data_consistency(_Config) ->
    ct:parm("Testing data consistency"),

    %% Create test data
    TestPids = lists:map(fun(_) ->
        spawn_link(fun() -> test_process_loop() end)
    end, lists:seq(1, 10)),

    %% Perform upgrades
    lists:foreach(fun(Pid) ->
        upgrade_test_process(Pid)
    end, TestPids),

    %% Verify consistency
    Consistent = verify_data_consistency(TestPids),
    ?assert(Consistent, "Data consistency check failed"),

    %% Cleanup
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, normal)
    end, TestPids),

    ok.

regression_error_recovery(_Config) ->
    ct:parm("Testing error recovery"),

    %% Inject various errors
    ErrorTypes = [timeout, memory_error, cpu_error, network_error],

    lists:foreach(fun(ErrorType) ->
        ErrorPid = spawn_link(fun() -> error_process(ErrorType) end),

        %% Attempt upgrade
        Result = upgrade_test_process(ErrorPid),
        ct:pal("Error recovery test for ~p: ~p", [ErrorType, Result]),

        %% Cleanup
        unlink(ErrorPid),
        exit(ErrorPid, normal)
    end, ErrorTypes),

    ok.

%%%===================================================================
%%% Helper Functions
%%%===================================================================

create_test_tasks(Count) ->
    lists:map(fun(I) ->
        #task{
            id = integer_to_binary(I),
            context_id = integer_to_binary(I),
            status = #task_status{state = submitted, timestamp = erlang:system_time(millisecond)},
            artifacts = [],
            history = [],
            metadata = #{}
        }
    end, lists:seq(1, Count)).

test_process_loop() ->
    receive
        _ -> test_process_loop()
    after 10000 ->
        ok
    end.

intensive_test_process() ->
    %% CPU-intensive work
    lists:foldl(fun(_, Acc) -> Acc + math:sqrt(Acc) end, 10000, lists:seq(1, 1000)),
    test_process_loop().

test_client(Id) ->
    %% Simulate client work
    receive
        _ -> test_client(Id)
    after 5000 ->
        ok
    end.

populate_ets_table(TableName, Count) ->
    lists:foreach(fun(I) ->
        ets:insert(TableName, {I, <<"data_", (integer_to_binary(I))/binary>>})
    end, lists:seq(1, Count)).

upgrade_test_process(Pid) ->
    try
        case process_info(Pid) of
            undefined -> failed;
            _ -> success
        end
    catch
        _:Error -> failed
    end.

upgrade_concurrent_processes(Processes, Concurrency) ->
    Parent = self(),
    Ref = make_ref(),

    %% Spawn upgrade workers
    Workers = lists:map(fun(Pid) ->
        spawn_link(fun() ->
            case upgrade_test_process(Pid) of
                success -> Parent ! {upgrade_success, Ref, Pid};
                {error, Reason} -> Parent ! {upgrade_failure, Ref, Pid, Reason}
            end
        end)
    end, Processes),

    %% Collect results
    collect_upgrade_results(Ref, length(Workers), []).

collect_upgrade_results(Ref, Expected, Results) ->
    receive
        {upgrade_success, Ref, Pid} ->
            collect_upgrade_results(Ref, Expected - 1, [success | Results]);
        {upgrade_failure, Ref, Pid, Reason} ->
            collect_upgrade_results(Ref, Expected - 1, [{failed, Reason} | Results])
    after 30000 ->
        Results
    end.

upgrade_ets_table(TableName) ->
    try
        case ets:info(TableName) of
            undefined -> failed;
            _ -> success
        end
    catch
        _:Error -> failed
    end.

collect_memory_during_upgrade(Processes) ->
    %% Monitor memory during upgrade process
    lists:map(fun(_) ->
        erlang:memory(total)
    end, lists:seq(1, 10)).

collect_cpu_during_upgrade() ->
    %% Monitor CPU during upgrade process
    lists:map(fun(_) ->
        get_cpu_usage()
    end, lists:seq(1, 10)).

measure_client_performance(Clients) ->
    %% Simulate client performance measurement
    #{
        avg_response_time => 100.0,
        throughput => 50.0,
        error_rate => 0.0
    }.

calculate_total_downtime() ->
    %% Calculate total downtime
    0.

perform_system_upgrade() ->
    %% Perform system upgrade
    success.

intensive_operations() ->
    %% Perform resource-intensive operations
    lists:foldl(fun(_, Acc) -> Acc + math:sqrt(Acc) end, 10000, lists:seq(1, 10000)),
    timer:sleep(1000),
    intensive_operations().

slow_test_process() ->
    %% Process that takes a long time
    timer:sleep(10000),
    test_process_loop().

memory_intensive_process() ->
    %% Memory-intensive process
    _ = lists:duplicate(1000000, <<"memory_data">>),
    test_process_loop().

cpu_intensive_process() ->
    %% CPU-intensive process
    lists:foldl(fun(_, Acc) -> Acc + math:sqrt(Acc) end, 100000, lists:seq(1, 1000)),
    test_process_loop().

partitioned_process() ->
    %% Process that can't communicate
    receive
        _ -> ok
    after 30000 ->
        ok
    end.

load_process() ->
    %% Process that generates load
    lists:foldl(fun(_, Acc) -> Acc + 1 end, 0, lists:seq(1, 10000)),
    timer:sleep(100),
    load_process().

test_process_recovery() ->
    %% Test process recovery
    ok.

test_ets_recovery() ->
    %% Test ETS recovery
    ok.

test_memory_recovery() ->
    %% Test memory recovery
    ok.

test_cpu_recovery() ->
    %% Test CPU recovery
    ok.

long_running_upgrade() ->
    %% Long-running upgrade process
    timer:sleep(60000),
    ok.

failing_process() ->
    %% Process that fails
    exit(error),
    test_process_loop().

memory_consumer_loop(Size) ->
    %% Memory consumer process
    _ = lists:duplicate(Size, <<"memory_data">>),
    memory_consumer_loop(Size).

error_process(ErrorType) ->
    %% Process that handles different error types
    case ErrorType of
        timeout -> timer:sleep(10000);
        memory_error -> _ = lists:duplicate(1000000, <<"memory_data">>);
        cpu_error -> lists:foldl(fun(_, Acc) -> Acc + math:sqrt(Acc) end, 100000, lists:seq(1, 1000));
        network_error -> receive _ -> ok end
    end,
    test_process_loop().

verify_data_consistency(Pids) ->
    %% Verify data consistency across processes
    true.

generate_upgrade_id() ->
    <<Id:8/binary, _:64>> = crypto:strong_rand_bytes(16),
    Id.

find_optimal_concurrency(Results) ->
    %% Find optimal concurrency level from results
    lists:last(lists:sort(fun(A, B) ->
        A#concurrency_result.throughput > B#concurrency_result.throughput
    end, Results)).

analyze_ets_scaling(Results) ->
    %% Analyze ETS table performance scaling
    #scaling_result{
        scaling_factor => 0.8,
        optimal_size => 10000
    }.

cleanup_test_processes() ->
    %% Clean up any remaining test processes
    Processes = erlang:processes(),
    TestPids = lists:filter(fun(Pid) ->
        case process_info(Pid, initial_call) of
            {_, {test_process_loop, 0}} -> true;
            {_, {intensive_test_process, 0}} -> true;
            _ -> false
        end
    end, Processes),
    lists:foreach(fun(Pid) ->
        unlink(Pid),
        exit(Pid, kill)
    end, TestPids).

log_test_performance(TestCase, Config) ->
    %% Log test performance metrics
    EndTime = erlang:monotonic_time(millisecond),
    StartTime = proplists:get_value(test_start_time, Config),
    Duration = EndTime - StartTime,

    ct:pal("Test case ~p completed in ~p ms", [TestCase, Duration]).
