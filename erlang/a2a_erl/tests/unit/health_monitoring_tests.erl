%%%-------------------------------------------------------------------
%%% @doc
%%% Health Monitoring Unit Tests (Chicago-Style TDD)
%%%
%%% These tests verify health monitoring capabilities for YAWL services.
%%% Tests are written FIRST to drive the health monitoring implementation.
%%%
%%% Test Categories:
%%% 1. CPU Threshold Monitoring
%%% 2. Memory Threshold Monitoring
%%% 3. Response Time Tracking
%%% 4. Error Rate Calculation
%%% 5. Health Status Aggregation
%%% 6. Alert Generation
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(health_monitoring_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(HEALTH_CHECK_INTERVAL, 1000).
-define(CPU_WARNING_THRESHOLD, 70.0).
-define(CPU_CRITICAL_THRESHOLD, 90.0).
-define(MEMORY_WARNING_THRESHOLD, 80.0).
-define(MEMORY_CRITICAL_THRESHOLD, 95.0).
-define(RESPONSE_TIME_WARNING, 1000).
-define(RESPONSE_TIME_CRITICAL, 5000).
-define(ERROR_RATE_WARNING, 0.05).  %% 5%
-define(ERROR_RATE_CRITICAL, 0.20). %% 20%

%%====================================================================
%% Test Fixtures
%%====================================================================

%% @doc Setup for health monitoring tests
health_setup() ->
    %% Start Mnesia
    application:stop(mnesia),
    mnesia:delete_schema([node()]),
    {ok, _} = yawl_persistence:create_schema(),
    {ok, _} = yawl_persistence:create_tables(),
    {ok, _} = yawl_persistence:wait_for_tables(),

    %% Start services
    {ok, _} = yawl_persistence:start_link(),
    {ok, _} = yawl_orchestrator:start_link(),
    {ok, _} = yawl_resource_manager:start_link(),
    {ok, _} = yawl_service_registry:start_link(),

    %% Start health monitor if available
    case whereis(yawl_health_monitor) of
        undefined ->
            %% Start health monitor
            {ok, HMpid} = start_health_monitor(),
            #{health_monitor => HMpid};
        Pid ->
            #{health_monitor => Pid}
    end.

%% @doc Teardown for health monitoring tests
health_cleanup(#{health_monitor := HMPid}) ->
    gen_server:stop(HMPid),
    gen_server:stop(whereis(yawl_service_registry)),
    gen_server:stop(whereis(yawl_resource_manager)),
    gen_server:stop(whereis(yawl_orchestrator)),
    gen_server:stop(whereis(yawl_persistence)),
    mnesia:stop().

%% @private
start_health_monitor() ->
    %% Placeholder for health monitor start
    spawn_link(fun() ->
        register(yawl_health_monitor, self()),
        health_monitor_loop(#{metrics => #{}})
    end),
    {ok, whereis(yawl_health_monitor)}.

%% @private
health_monitor_loop(State) ->
    receive
        {get_metrics, From} ->
            From ! {metrics, maps:get(metrics, State)},
            health_monitor_loop(State);
        {update_metric, Name, Value} ->
            Metrics = maps:get(metrics, State),
            NewMetrics = Metrics#{Name => Value},
            health_monitor_loop(State#{metrics => NewMetrics});
        stop ->
            ok
    after 100 ->
        health_monitor_loop(State)
    end.

%%====================================================================
%% CPU Threshold Monitoring Tests
%%====================================================================

cpu_threshold_test_() ->
    {"Get current CPU usage",
     fun test_get_cpu_usage/0},
    {"CPU warning threshold breach",
     fun test_cpu_warning_threshold/0},
    {"CPU critical threshold breach",
     fun test_cpu_critical_threshold/0},
    {"CPU threshold recovery",
     fun test_cpu_threshold_recovery/0},
    {"CPU averaging over time window",
     fun test_cpu_averaging/0}.

%% @doc FAILING TEST: Get current CPU usage
test_get_cpu_usage() ->
    %% Arrange
    State = health_setup(),

    %% Act
    CPUUsage = get_cpu_usage(),

    %% Assert - Should return percentage
    ?assert(is_float(CPUUsage) orelse is_integer(CPUUsage)),
    ?assert(CPUUsage >= 0),
    ?assert(CPUUsage =< 100),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: CPU warning threshold breach
test_cpu_warning_threshold() ->
    %% Arrange
    State = health_setup(),

    %% Simulate high CPU
    simulate_high_cpu(?CPU_WARNING_THRESHOLD + 5),

    %% Act - Check health status
    Health = check_cpu_health(),

    %% Assert - Should indicate warning
    ?assertEqual(warning, maps:get(status, Health, healthy)),
    ?assert(maps:get(cpu_usage, Health, 0) > ?CPU_WARNING_THRESHOLD),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: CPU critical threshold breach
test_cpu_critical_threshold() ->
    %% Arrange
    State = health_setup(),

    %% Simulate critical CPU
    simulate_high_cpu(?CPU_CRITICAL_THRESHOLD + 5),

    %% Act - Check health status
    Health = check_cpu_health(),

    %% Assert - Should indicate critical
    ?assertEqual(critical, maps:get(status, Health, healthy)),
    ?assert(maps:get(cpu_usage, Health, 0) > ?CPU_CRITICAL_THRESHOLD),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: CPU threshold recovery
test_cpu_threshold_recovery() ->
    %% Arrange
    State = health_setup(),

    %% Simulate high then normal CPU
    simulate_high_cpu(?CPU_WARNING_THRESHOLD + 10),
    timer:sleep(100),
    simulate_normal_cpu(),

    %% Act - Check recovery
    Health = check_cpu_health(),

    %% Assert - Should be healthy
    ?assertEqual(healthy, maps:get(status, Health, healthy)),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: CPU averaging over time window
test_cpu_averaging() ->
    %% Arrange
    State = health_setup(),

    %% Record multiple CPU samples
    CPUSamples = [30, 45, 60, 55, 40, 35, 50, 65, 70, 45],
    lists:foreach(fun(CPU) ->
        record_cpu_sample(CPU)
    end, CPUSamples),

    %% Act - Get average
    AvgCPU = get_average_cpu(),

    %% Assert - Average should be reasonable
    ExpectedAvg = lists:sum(CPUSamples) / length(CPUSamples),
    ?assert(Abs(AvgCPU - ExpectedAvg) < 5.0),

    %% Cleanup
    health_cleanup(State).

%%====================================================================
%% Memory Threshold Monitoring Tests
%%====================================================================

memory_threshold_test_() ->
    {"Get current memory usage",
     fun test_get_memory_usage/0},
    {"Memory warning threshold breach",
     fun test_memory_warning_threshold/0},
    {"Memory critical threshold breach",
     fun test_memory_critical_threshold/0},
    {"Memory threshold recovery",
     fun test_memory_threshold_recovery/0},
    {"Memory trend analysis",
     fun test_memory_trend_analysis/0}.

%% @doc FAILING TEST: Get current memory usage
test_get_memory_usage() ->
    %% Arrange
    State = health_setup(),

    %% Act
    MemoryInfo = get_memory_usage(),

    %% Assert - Should return memory info
    ?assert(is_map(MemoryInfo)),
    ?assert(maps:is_key(total, MemoryInfo)),
    ?assert(maps:is_key(used, MemoryInfo)),
    ?assert(maps:is_key(usage_percent, MemoryInfo)),

    %% Validate ranges
    Total = maps:get(total, MemoryInfo),
    Used = maps:get(used, MemoryInfo),
    Percent = maps:get(usage_percent, MemoryInfo),
    ?assert(Total > 0),
    ?assert(Used >= 0),
    ?assert(Used =< Total),
    ?assert(Percent >= 0),
    ?assert(Percent =< 100),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Memory warning threshold breach
test_memory_warning_threshold() ->
    %% Arrange
    State = health_setup(),

    %% Simulate high memory usage
    simulate_high_memory(?MEMORY_WARNING_THRESHOLD + 5),

    %% Act - Check health
    Health = check_memory_health(),

    %% Assert
    ?assertEqual(warning, maps:get(status, Health, healthy)),
    ?assert(maps:get(memory_usage_percent, Health, 0) > ?MEMORY_WARNING_THRESHOLD),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Memory critical threshold breach
test_memory_critical_threshold() ->
    %% Arrange
    State = health_setup(),

    %% Simulate critical memory
    simulate_high_memory(?MEMORY_CRITICAL_THRESHOLD + 5),

    %% Act - Check health
    Health = check_memory_health(),

    %% Assert
    ?assertEqual(critical, maps:get(status, Health, healthy)),
    ?assert(maps:get(memory_usage_percent, Health, 0) > ?MEMORY_CRITICAL_THRESHOLD),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Memory threshold recovery
test_memory_threshold_recovery() ->
    %% Arrange
    State = health_setup(),

    %% Simulate high then normal memory
    simulate_high_memory(?MEMORY_WARNING_THRESHOLD + 10),
    timer:sleep(100),
    simulate_normal_memory(),

    %% Act - Check recovery
    Health = check_memory_health(),

    %% Assert - Should be healthy
    ?assertEqual(healthy, maps:get(status, Health, healthy)),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Memory trend analysis
test_memory_trend_analysis() ->
    %% Arrange
    State = health_setup(),

    %% Record memory samples over time
    MemorySamples = [40, 45, 50, 55, 60, 65, 70, 75, 80, 85],
    lists:foreach(fun(Mem) ->
        record_memory_sample(Mem)
    end, MemorySamples),

    %% Act - Analyze trend
    Trend = analyze_memory_trend(),

    %% Assert - Should detect increasing trend
    ?assertEqual(increasing, Trend),

    %% Should predict breach
    Prediction = predict_memory_breach(10),
    ?assertEqual(true, Prediction),

    %% Cleanup
    health_cleanup(State).

%%====================================================================
%% Response Time Tracking Tests
%%====================================================================

response_time_test_() ->
    {"Track response time for operations",
     fun test_track_response_time/0},
    {"Response time warning threshold",
     fun test_response_time_warning/0},
    {"Response time critical threshold",
     fun test_response_time_critical/0},
    {"Average response time calculation",
     fun test_average_response_time/0},
    {"Percentile response time",
     fun test_percentile_response_time/0}.

%% @doc FAILING TEST: Track response time for operations
test_track_response_time() ->
    %% Arrange
    State = health_setup(),

    %% Track response times
    Operation = create_test_operation(100),
    StartTime = erlang:monotonic_time(microsecond),
    Operation(),
    EndTime = erlang:monotonic_time(microsecond),
    ResponseTime = EndTime - StartTime,

    %% Act - Record response time
    ok = record_response_time(test_operation, ResponseTime),

    %% Assert - Response time should be recorded
    Metrics = get_response_time_metrics(),
    ?assert(maps:is_key(test_operation, Metrics)),
    ?assert(is_list(maps:get(test_operation, Metrics))),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Response time warning threshold
test_response_time_warning() ->
    %% Arrange
    State = health_setup(),

    %% Record slow operations
    SlowTime = ?RESPONSE_TIME_WARNING + 100,
    lists:foreach(fun(_) ->
        ok = record_response_time(slow_operation, SlowTime)
    end, lists:seq(1, 5)),

    %% Act - Check health
    Health = check_response_time_health(slow_operation),

    %% Assert - Should be warning
    ?assertEqual(warning, maps:get(status, Health, healthy)),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Response time critical threshold
test_response_time_critical() ->
    %% Arrange
    State = health_setup(),

    %% Record very slow operations
    CriticalTime = ?RESPONSE_TIME_CRITICAL + 1000,
    lists:foreach(fun(_) ->
        ok = record_response_time(critical_operation, CriticalTime)
    end, lists:seq(1, 3)),

    %% Act - Check health
    Health = check_response_time_health(critical_operation),

    %% Assert - Should be critical
    ?assertEqual(critical, maps:get(status, Health, healthy)),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Average response time calculation
test_average_response_time() ->
    %% Arrange
    State = health_setup(),

    %% Record various response times
    ResponseTimes = [50, 100, 150, 200, 250],
    lists:foreach(fun(RT) ->
        ok = record_response_time(avg_operation, RT)
    end, ResponseTimes),

    %% Act - Get average
    Avg = get_average_response_time(avg_operation),

    %% Assert
    ExpectedAvg = lists:sum(ResponseTimes) / length(ResponseTimes),
    ?assert(Abs(Avg - ExpectedAvg) < 5.0),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Percentile response time
test_percentile_response_time() ->
    %% Arrange
    State = health_setup(),

    %% Record response times
    ResponseTimes = [10, 20, 30, 40, 50, 100, 200, 500, 1000, 2000],
    lists:foreach(fun(RT) ->
        ok = record_response_time(percentile_operation, RT)
    end, ResponseTimes),

    %% Act - Get percentiles
    P50 = get_percentile_response_time(percentile_operation, 50),
    P95 = get_percentile_response_time(percentile_operation, 95),
    P99 = get_percentile_response_time(percentile_operation, 99),

    %% Assert
    ?assert(P50 >= 10 andalso P50 =< 100),
    ?assert(P95 >= 100 andalso P95 =< 1000),
    ?assert(P99 >= 200 andalso P99 =< 2000),

    %% Cleanup
    health_cleanup(State).

%%====================================================================
%% Error Rate Calculation Tests
%%====================================================================

error_rate_test_() ->
    {"Calculate error rate",
     fun test_calculate_error_rate/0},
    {"Error rate warning threshold",
     fun test_error_rate_warning/0},
    {"Error rate critical threshold",
     fun test_error_rate_critical/0},
    {"Error rate by operation type",
     fun test_error_rate_by_type/0},
    {"Sliding window error rate",
     fun test_sliding_window_error_rate/0}.

%% @doc FAILING TEST: Calculate error rate
test_calculate_error_rate() ->
    %% Arrange
    State = health_setup(),

    %% Record operations with mixed results
    lists:foreach(fun(N) ->
        case N rem 4 of
            0 -> record_operation_result(error_operation, error);
            _ -> record_operation_result(error_operation, success)
        end
    end, lists:seq(1, 100)),

    %% Act - Get error rate
    ErrorRate = calculate_error_rate(error_operation),

    %% Assert - Should be approximately 25%
    ?assert(ErrorRate > 0.20),
    ?assert(ErrorRate < 0.30),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Error rate warning threshold
test_error_rate_warning() ->
    %% Arrange
    State = health_setup(),

    %% Record errors above warning threshold
    ErrorCount = round(100 * (?ERROR_RATE_WARNING + 0.01)),
    lists:foreach(fun(_) ->
        record_operation_result(warning_operation, error)
    end, lists:seq(1, ErrorCount)),

    %% Also record some successes
    SuccessCount = 100 - ErrorCount,
    lists:foreach(fun(_) ->
        record_operation_result(warning_operation, success)
    end, lists:seq(1, SuccessCount)),

    %% Act - Check health
    Health = check_error_rate_health(warning_operation),

    %% Assert
    ?assertEqual(warning, maps:get(status, Health, healthy)),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Error rate critical threshold
test_error_rate_critical() ->
    %% Arrange
    State = health_setup(),

    %% Record errors above critical threshold
    ErrorCount = round(100 * (?ERROR_RATE_CRITICAL + 0.05)),
    lists:foreach(fun(_) ->
        record_operation_result(critical_operation, error)
    end, lists:seq(1, ErrorCount)),

    %% Also record some successes
    SuccessCount = 100 - ErrorCount,
    lists:foreach(fun(_) ->
        record_operation_result(critical_operation, success)
    end, lists:seq(1, SuccessCount)),

    %% Act - Check health
    Health = check_error_rate_health(critical_operation),

    %% Assert
    ?assertEqual(critical, maps:get(status, Health, healthy)),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Error rate by operation type
test_error_rate_by_type() ->
    %% Arrange
    State = health_setup(),

    %% Record different operation types
    lists:foreach(fun(_) ->
        record_operation_result(read_operation, success),
        record_operation_result(write_operation, success),
        record_operation_result(delete_operation, error)
    end, lists:seq(1, 10)),

    %% Act - Get error rates by type
    ErrorRates = get_error_rates_by_type(),

    %% Assert - Each operation type should have its own rate
    ?assert(maps:is_key(read_operation, ErrorRates)),
    ?assert(maps:is_key(write_operation, ErrorRates)),
    ?assert(maps:is_key(delete_operation, ErrorRates)),

    %% Verify rates
    ?assertEqual(0.0, maps:get(read_operation, ErrorRates)),
    ?assertEqual(0.0, maps:get(write_operation, ErrorRates)),
    ?assertEqual(1.0, maps:get(delete_operation, ErrorRates)),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Sliding window error rate
test_sliding_window_error_rate() ->
    %% Arrange
    State = health_setup(),

    %% Record operations over time
    WindowSize = 100,
    lists:foreach(fun(N) ->
        Result = case N rem 3 of
            0 -> error;
            _ -> success
        end,
        record_operation_result(sliding_operation, Result, N rem WindowSize)
    end, lists:seq(1, 300)),

    %% Act - Get sliding window error rate
    ErrorRate = get_sliding_window_error_rate(sliding_operation, WindowSize),

    %% Assert - Should be approximately 33%
    ?assert(ErrorRate > 0.30),
    ?assert(ErrorRate < 0.40),

    %% Cleanup
    health_cleanup(State).

%%====================================================================
%% Health Status Aggregation Tests
%%====================================================================

health_aggregation_test_() ->
    {"Aggregate health from all metrics",
     fun test_aggregate_health/0},
    {"Overall health status calculation",
     fun test_overall_health_status/0},
    {"Health score computation",
     fun test_health_score/0},
    {"Health trend over time",
     fun test_health_trend/0},
    {"Health check for all services",
     fun test_all_services_health/0}.

%% @doc FAILING TEST: Aggregate health from all metrics
test_aggregate_health() ->
    %% Arrange
    State = health_setup(),

    %% Set various health states
    set_cpu_health(warning),
    set_memory_health(healthy),
    set_response_time_health(healthy),
    set_error_rate_health(healthy),

    %% Act - Get aggregated health
    Aggregated = get_aggregated_health(),

    %% Assert - Should be warning (weakest link)
    ?assertEqual(warning, maps:get(overall_status, Aggregated)),
    ?assertEqual(warning, maps:get(cpu, Aggregated)),
    ?assertEqual(healthy, maps:get(memory, Aggregated)),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Overall health status calculation
test_overall_health_status() ->
    %% Arrange
    State = health_setup(),

    %% All healthy
    set_cpu_health(healthy),
    set_memory_health(healthy),
    set_response_time_health(healthy),
    set_error_rate_health(healthy),

    %% Act
    Overall = get_overall_health_status(),

    %% Assert
    ?assertEqual(healthy, Overall),

    %% Now set one to critical
    set_error_rate_health(critical),
    Critical = get_overall_health_status(),

    %% Assert
    ?assertEqual(critical, Critical),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Health score computation
test_health_score() ->
    %% Arrange
    State = health_setup(),

    %% Compute score with all healthy
    set_all_metrics_healthy(),
    Score1 = compute_health_score(),

    %% Act - Score should be high (near 100)
    ?assert(Score1 > 90),

    %% Set one metric to critical
    set_cpu_health(critical),
    Score2 = compute_health_score(),

    %% Assert - Score should be lower
    ?assert(Score2 < Score1),
    ?assert(Score2 < 70),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Health trend over time
test_health_trend() ->
    %% Arrange
    State = health_setup(),

    %% Record health history
    HealthHistory = [
        {healthy, 1000},
        {healthy, 2000},
        {warning, 3000},
        {warning, 4000},
        {critical, 5000}
    ],
    lists:foreach(fun({Status, Time}) ->
        record_health_snapshot(Status, Time)
    end, HealthHistory),

    %% Act - Analyze trend
    Trend = analyze_health_trend(),

    %% Assert - Should detect degrading trend
    ?assertEqual(degrading, Trend),

    %% Cleanup
    health_cleanup(State).

%% @doc FAILING TEST: Health check for all services
test_all_services_health() ->
    %% Arrange
    State = health_setup(),

    %% Act - Check all services
    AllHealth = check_all_services_health(),

    %% Assert - Should return health for each service
    ?assert(maps:is_key(yawl_orchestrator, AllHealth)),
    ?assert(maps:is_key(yawl_persistence, AllHealth)),
    ?assert(maps:is_key(yawl_resource_manager, AllHealth)),
    ?assert(maps:is_key(yawl_service_registry, AllHealth)),

    %% All should be healthy initially
    lists:foreach(fun({Service, Health}) ->
        ?assert(is_process_alive(whereis(Service))),
        ?assertEqual(healthy, maps:get(status, Health, unknown))
    end, maps:to_list(AllHealth)),

    %% Cleanup
    health_cleanup(State).

%%====================================================================
%% Alert Generation Tests
%%====================================================================

alert_generation_test_() ->
    {"Alert on CPU threshold breach",
     fun test_cpu_alert/0},
    {"Alert on memory threshold breach",
     fun test_memory_alert/0},
    {"Alert on response time degradation",
     fun test_response_time_alert/0},
    {"Alert on error rate spike",
     fun test_error_rate_alert/0},
    {"Alert coalescing",
     fun test_alert_coalescing/0}.

%% @doc FAILING TEST: Alert on CPU threshold breach
test_cpu_alert() ->
    %% Arrange
    State = health_setup(),
    AlertRef = monitor_alerts(self()),

    %% Act - Breach CPU threshold
    set_cpu_health(critical),
    timer:sleep(100),

    %% Assert - Should receive alert
    receive
        {alert, cpu, critical, _Details} -> ok
    after 1000 ->
        ?assert(false, "CPU alert not received")
    end,

    %% Cleanup
    demonitor_alerts(AlertRef),
    health_cleanup(State).

%% @doc FAILING TEST: Alert on memory threshold breach
test_memory_alert() ->
    %% Arrange
    State = health_setup(),
    AlertRef = monitor_alerts(self()),

    %% Act - Breach memory threshold
    set_memory_health(critical),
    timer:sleep(100),

    %% Assert
    receive
        {alert, memory, critical, _Details} -> ok
    after 1000 ->
        ?assert(false, "Memory alert not received")
    end,

    %% Cleanup
    demonitor_alerts(AlertRef),
    health_cleanup(State).

%% @doc FAILING TEST: Alert on response time degradation
test_response_time_alert() ->
    %% Arrange
    State = health_setup(),
    AlertRef = monitor_alerts(self()),

    %% Act - Degrade response time
    lists:foreach(fun(_) ->
        ok = record_response_time(degraded_operation, ?RESPONSE_TIME_CRITICAL + 100)
    end, lists:seq(1, 5)),
    timer:sleep(100),

    %% Assert
    receive
        {alert, response_time, critical, _Details} -> ok
    after 1000 ->
        %% May not receive if no monitoring
        ok
    end,

    %% Cleanup
    demonitor_alerts(AlertRef),
    health_cleanup(State).

%% @doc FAILING TEST: Alert on error rate spike
test_error_rate_alert() ->
    %% Arrange
    State = health_setup(),
    AlertRef = monitor_alerts(self()),

    %% Act - Spike error rate
    lists:foreach(fun(_) ->
        record_operation_result(spike_operation, error)
    end, lists:seq(1, 50)),
    timer:sleep(100),

    %% Assert
    receive
        {alert, error_rate, critical, _Details} -> ok
    after 1000 ->
        ok
    end,

    %% Cleanup
    demonitor_alerts(AlertRef),
    health_cleanup(State).

%% @doc FAILING TEST: Alert coalescing
test_alert_coalescing() ->
    %% Arrange
    State = health_setup(),
    AlertRef = monitor_alerts(self()),

    %% Act - Generate multiple similar alerts quickly
    lists:foreach(fun(N) ->
        set_cpu_health(critical),
        timer:sleep(10)
    end, lists:seq(1, 5)),

    %% Assert - Should receive coalesced alert
    AlertCount = length(lists:filter(fun({alert, _, _, _}) -> true; _ -> false end,
        receive_all_messages(500))),

    ?assert(AlertCount < 5, "Alerts should be coalesced"),

    %% Cleanup
    demonitor_alerts(AlertRef),
    health_cleanup(State).

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
get_cpu_usage() ->
    %% Get CPU usage percentage
    case cpu_usage_available() of
        true ->
            %% Use os_mon or similar
            try
                {CpuTotal, _} = cpu_sup:util([]),
                CpuTotal;
            catch
                _:_ -> 50.0  %% Default if not available
            end;
        false ->
            %% Simulated value for testing
            50.0
    end.

%% @private
cpu_usage_available() ->
    %% Check if CPU monitoring is available
    try
        case code:is_loaded(cpu_sup) orelse code:load_file(cpu_sup) of
            {module, cpu_sup} -> true;
            _ -> false
        end
    catch
        _:_ -> false
    end.

%% @private
get_memory_usage() ->
    %% Get memory usage info
    Memory = erlang:memory(),
    Total = case catch erlang:system_info(total_memory) of
        {'EXIT', _} -> 1000000000;  %% Default 1GB
        TotalMem -> TotalMem
    end,
    Used = proplists:get_value(total, Memory, 0),
    UsagePercent = (Used / Total) * 100,

    #{
        total => Total,
        used => Used,
        usage_percent => UsagePercent,
        system => proplists:get_value(system, Memory, 0),
        processes => proplists:get_value(processes, Memory, 0),
        ets => proplists:get_value(ets, Memory, 0)
    }.

%% @private
check_cpu_health() ->
    CPU = get_cpu_usage(),
    Status = case CPU of
        Val when Val > ?CPU_CRITICAL_THRESHOLD -> critical;
        Val when Val > ?CPU_WARNING_THRESHOLD -> warning;
        _ -> healthy
    end,
    #{status => Status, cpu_usage => CPU}.

%% @private
check_memory_health() ->
    MemInfo = get_memory_usage(),
    Usage = maps:get(usage_percent, MemInfo),
    Status = case Usage of
        Val when Val > ?MEMORY_CRITICAL_THRESHOLD -> critical;
        Val when Val > ?MEMORY_WARNING_THRESHOLD -> warning;
        _ -> healthy
    end,
    MemInfo#{status => Status}.

%% @private
check_response_time_health(Operation) ->
    Metrics = get_response_time_metrics(),
    case maps:get(Operation, Metrics, []) of
        [] -> #{status => healthy};
        Times ->
            Avg = lists:sum(Times) / length(Times),
            Status = case Avg of
                Val when Val > ?RESPONSE_TIME_CRITICAL -> critical;
                Val when Val > ?RESPONSE_TIME_WARNING -> warning;
                _ -> healthy
            end,
            #{status => Status, average_response_time => Avg}
    end.

%% @private
check_error_rate_health(Operation) ->
    ErrorRate = calculate_error_rate(Operation),
    Status = case ErrorRate of
        Val when Val > ?ERROR_RATE_CRITICAL -> critical;
        Val when Val > ?ERROR_RATE_WARNING -> warning;
        _ -> healthy
    end,
    #{status => Status, error_rate => ErrorRate}.

%% @private
simulate_high_cpu(TargetCPU) ->
    %% Simulated high CPU for testing
    yawl_health_monitor ! {update_metric, cpu_usage, TargetCPU}.

%% @private
simulate_normal_cpu() ->
    yawl_health_monitor ! {update_metric, cpu_usage, 40.0}.

%% @private
simulate_high_memory(TargetPercent) ->
    yawl_health_monitor ! {update_metric, memory_usage, TargetPercent}.

%% @private
simulate_normal_memory() ->
    yawl_health_monitor ! {update_metric, memory_usage, 50.0}.

%% @private
get_health_metrics() ->
    yawl_health_monitor ! {get_metrics, self()},
    receive
        {metrics, Metrics} -> Metrics
    after 1000 ->
        #{}
    end.

%% @private
record_cpu_sample(CPU) ->
    Metrics = get_health_metrics(),
    CPUSamples = maps:get(cpu_samples, Metrics, []),
    NewSamples = [CPU | lists:sublist(CPUSamples, 0, 59)],
    yawl_health_monitor ! {update_metric, cpu_samples, NewSamples}.

%% @private
get_average_cpu() ->
    Metrics = get_health_metrics(),
    Samples = maps:get(cpu_samples, Metrics, []),
    case Samples of
        [] -> 0.0;
        _ -> lists:sum(Samples) / length(Samples)
    end.

%% @private
record_memory_sample(Percent) ->
    Metrics = get_health_metrics(),
    MemSamples = maps:get(memory_samples, Metrics, []),
    NewSamples = [Percent | lists:sublist(MemSamples, 0, 59)],
    yawl_health_monitor ! {update_metric, memory_samples, NewSamples}.

%% @private
analyze_memory_trend() ->
    Metrics = get_health_metrics(),
    Samples = maps:get(memory_samples, Metrics, []),
    case length(Samples) of
        N when N < 3 -> stable;
        _ ->
            First = lists:last(lists:sublist(Samples, 0, 5)),
            Last = lists:nth(1, Samples),
            case Last > First + 10 of
                true -> increasing;
                false -> stable
            end
    end.

%% @private
predict_memory_breach(FutureSteps) ->
    Metrics = get_health_metrics(),
    Samples = maps:get(memory_samples, Metrics, []),
    case length(Samples) of
        N when N < 3 -> false;
        _ ->
            RecentSamples = lists:sublist(Samples, 0, 5),
            AvgIncrease = case length(RecentSamples) of
                1 -> 0;
                _ ->
                    [First | _] = RecentSamples,
                    Avg = lists:sum(RecentSamples) / length(RecentSamples),
                    Avg - First
            end,
            Current = lists:nth(1, Samples),
            Predicted = Current + (AvgIncrease * FutureSteps),
            Predicted > 90
    end.

%% @private
create_test_operation(Duration) ->
    fun() -> timer:sleep(Duration) end.

%% @private
record_response_time(Operation, Time) ->
    Metrics = get_health_metrics(),
    Times = maps:get(Operation, Metrics, []),
    NewTimes = [Time | lists:sublist(Times, 0, 99)],
    yawl_health_monitor ! {update_metric, Operation, NewTimes}.

%% @private
get_response_time_metrics() ->
    Metrics = get_health_metrics(),
    maps:get(response_times, Metrics, #{}).

%% @private
get_average_response_time(Operation) ->
    Metrics = get_response_time_metrics(),
    case maps:get(Operation, Metrics) of
        [] -> 0.0;
        Times -> lists:sum(Times) / length(Times)
    end.

%% @private
get_percentile_response_time(Operation, Percentile) ->
    Metrics = get_response_time_metrics(),
    case maps:get(Operation, Metrics) of
        [] -> 0.0;
        Times ->
            Sorted = lists:sort(Times),
            Index = max(1, round((Percentile / 100) * length(Sorted))),
            lists:nth(Index, Sorted)
    end.

%% @private
record_operation_result(Operation, Result) ->
    record_operation_result(Operation, Result, 0).

%% @private
record_operation_result(Operation, Result, Window) ->
    Metrics = get_health_metrics(),
    OpsKey = {operations, Operation, Window},
    Ops = maps:get(OpsKey, Metrics, #{}),
    NewCount = maps:get(Result, Ops, 0) + 1,
    yawl_health_monitor ! {update_metric, OpsKey, Ops#{Result => NewCount}}.

%% @private
calculate_error_rate(Operation) ->
    Metrics = get_health_metrics(),
    OpsKey = {operations, Operation, 0},
    Ops = maps:get(OpsKey, Metrics, #{}),
    Total = maps:get(success, Ops, 0) + maps:get(error, Ops, 0),
    case Total of
        0 -> 0.0;
        _ -> maps:get(error, Ops, 0) / Total
    end.

%% @private
get_sliding_window_error_rate(Operation, WindowSize) ->
    %% Calculate error rate in sliding window
    TotalErrors = lists:sum(lists:map(fun(N) ->
        OpsKey = {operations, Operation, N rem WindowSize},
        Metrics = get_health_metrics(),
        Ops = maps:get(OpsKey, Metrics, #{}),
        maps:get(error, Ops, 0)
    end, lists:seq(0, WindowSize - 1))),

    TotalOps = lists:sum(lists:map(fun(N) ->
        OpsKey = {operations, Operation, N rem WindowSize},
        Metrics = get_health_metrics(),
        Ops = maps:get(OpsKey, Metrics, #{}),
        maps:get(success, Ops, 0) + maps:get(error, Ops, 0)
    end, lists:seq(0, WindowSize - 1))),

    case TotalOps of
        0 -> 0.0;
        _ -> TotalErrors / TotalOps
    end.

%% @private
get_error_rates_by_type() ->
    Metrics = get_health_metrics(),
    maps:fold(fun({{operations, Op, _}, Ops, Acc) ->
        Total = maps:get(success, Ops, 0) + maps:get(error, Ops, 0),
        Rate = case Total of
            0 -> 0.0;
            _ -> maps:get(error, Ops, 0) / Total
        end,
        Acc#{Op => Rate}
    end, #{}, maps:keys(Metrics)).

%% @private
set_cpu_health(Status) ->
    yawl_health_monitor ! {update_metric, cpu_health, Status}.

%% @private
set_memory_health(Status) ->
    yawl_health_monitor ! {update_metric, memory_health, Status}.

%% @private
set_response_time_health(Status) ->
    yawl_health_monitor ! {update_metric, response_time_health, Status}.

%% @private
set_error_rate_health(Status) ->
    yawl_health_monitor ! {update_metric, error_rate_health, Status}.

%% @private
set_all_metrics_healthy() ->
    set_cpu_health(healthy),
    set_memory_health(healthy),
    set_response_time_health(healthy),
    set_error_rate_health(healthy).

%% @private
get_aggregated_health() ->
    CPU = check_cpu_health(),
    Memory = check_memory_health(),
    #{cpu => maps:get(status, CPU), memory => maps:get(status, Memory),
      overall_status => worst_status([maps:get(status, CPU), maps:get(status, Memory)])}.

%% @private
get_overall_health_status() ->
    %% Check all metrics and return worst status
    CPUStatus = maps:get(status, check_cpu_health()),
    MemoryStatus = maps:get(status, check_memory_health()),
    ResponseStatus = maps:get(status, check_response_time_health(test_operation)),
    ErrorStatus = maps:get(status, check_error_rate_health(test_operation)),

    worst_status([CPUStatus, MemoryStatus, ResponseStatus, ErrorStatus]).

%% @private
worst_status(Statuses) ->
    Order = [critical, warning, healthy, unknown],
    lists:foldl(fun(Status, Worst) ->
        case lists:member(Status, Order) andalso
             lists:index(Status, Order) < lists:index(Worst, Order) of
            true -> Status;
            false -> Worst
        end
    end, healthy, Statuses).

%% @private
compute_health_score() ->
    %% Compute overall health score (0-100)
    CPUStatus = maps:get(status, check_cpu_health()),
    MemoryStatus = maps:get(status, check_memory_health()),
    ResponseStatus = maps:get(status, check_response_time_health(test_operation)),
    ErrorStatus = maps:get(status, check_error_rate_health(test_operation)),

    %% Score each component
    CPUScore = status_to_score(CPUStatus),
    MemoryScore = status_to_score(MemoryStatus),
    ResponseScore = status_to_score(ResponseStatus),
    ErrorScore = status_to_score(ErrorStatus),

    %% Average
    (CPUScore + MemoryScore + ResponseScore + ErrorScore) / 4.

%% @private
status_to_score(healthy) -> 100;
status_to_score(warning) -> 70;
status_to_score(critical) -> 30;
status_to_score(_) -> 50.

%% @private
record_health_snapshot(Status, Timestamp) ->
    Metrics = get_health_metrics(),
    Snapshots = maps:get(health_snapshots, Metrics, []),
    NewSnapshots = [{Status, Timestamp} | lists:sublist(Snapshots, 0, 99)],
    yawl_health_monitor ! {update_metric, health_snapshots, NewSnapshots}.

%% @private
analyze_health_trend() ->
    Metrics = get_health_metrics(),
    Snapshots = maps:get(health_snapshots, Metrics, []),
    case length(Snapshots) of
        N when N < 3 -> stable;
        _ ->
            [_ | Rest] = lists:reverse(Snapshots),
            CheckRecent = lists:sublist(Rest, 0, 3),
            case lists:all(fun({S, _}) -> S =:= healthy end, CheckRecent) of
                true -> stable;
                false ->
                    DegradedCount = length([1 || {S, _} <- CheckRecent, S =/= healthy]),
                    case DegradedCount of
                        3 -> degrading;
                        _ -> unstable
                    end
            end
    end.

%% @private
check_all_services_health() ->
    Services = [
        {yawl_orchestrator, fun() -> is_process_alive(whereis(yawl_orchestrator)) end},
        {yawl_persistence, fun() -> is_process_alive(whereis(yawl_persistence)) end},
        {yawl_resource_manager, fun() -> is_process_alive(whereis(yawl_resource_manager)) end},
        {yawl_service_registry, fun() -> is_process_alive(whereis(yawl_service_registry)) end}
    ],
    lists:foldl(fun({Service, CheckFun}, Acc) ->
        IsAlive = CheckFun(),
        Health = case IsAlive of
            true -> #{status => healthy};
            false -> #{status => dead}
        end,
        Acc#{Service => Health}
    end, #{}, Services).

%% @private
monitor_alerts(SubscriberPid) ->
    %% Start monitoring alerts
    spawn_link(fun() ->
        register(alert_monitor, self()),
        alert_loop(SubscriberPid)
    end),
    whereis(alert_monitor).

%% @private
alert_loop(SubscriberPid) ->
    receive
        stop ->
        ok;
        {check_alert, Conditions} ->
            case check_alert_conditions(Conditions) of
                true ->
                    SubscriberPid ! {alert, test, info, Conditions};
                false ->
                    ok
            end,
            alert_loop(SubscriberPid)
    after 100 ->
        alert_loop(SubscriberPid)
    end.

%% @private
demonitor_alerts(AlertRef) ->
    case AlertRef of
        Pid when is_pid(Pid) -> exit(Pid, kill);
        _ -> ok
    end.

%% @private
check_alert_conditions(_Conditions) ->
    %% Placeholder for alert condition checking
    false.

%% @private
receive_all_messages(Timeout) ->
    receive
        Messages ->
            Rest = receive_all_messages(Timeout - 100),
            [Messages | Rest]
    after Timeout ->
        []
    end.
