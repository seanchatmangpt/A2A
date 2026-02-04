%%% @doc Performance Integration Module
%%% Integrates performance monitoring into existing Craftplan MCP + A2A systems

-module(performance_integration).
-export([start_integration/0, stop_integration/0]).
-export([enable_monitoring/0, disable_monitoring/0]).
-export([integrate_mcp_server/0, integrate_a2a_server/0]).
-export([get_performance_summary/0, get_system_health/0]).

%%====================================================================
%% API
%%====================================================================

start_integration() ->
    %% Start all performance monitoring components
    start_performance_components(),
    integrate_systems(),
    register_alerts(),

    io:format("Performance integration started~n"),
    ok.

stop_integration() ->
    %% Stop all performance monitoring components
    stop_performance_components(),

    io:format("Performance integration stopped~n"),
    ok.

enable_monitoring() ->
    %% Enable performance monitoring
    enable_system_monitoring(),
    enable_cache_monitoring(),
    enable_connection_monitoring(),

    io:format("Performance monitoring enabled~n"),
    ok.

disable_monitoring() ->
    %% Disable performance monitoring
    disable_system_monitoring(),
    disable_cache_monitoring(),
    disable_connection_monitoring(),

    io:format("Performance monitoring disabled~n"),
    ok.

integrate_mcp_server() ->
    %% Integrate performance monitoring into MCP server
    update_mcp_server(),
    configure_mcp_caching(),
    optimize_mcp_connections(),

    io:format("MCP server performance integration complete~n"),
    ok.

integrate_a2a_server() ->
    %% Integrate performance monitoring into A2A server
    update_a2a_server(),
    configure_a2a_queue(),
    optimize_a2a_task_processing(),

    io:format("A2A server performance integration complete~n"),
    ok.

get_performance_summary() ->
    %% Get comprehensive performance summary
    Metrics = performance_metrics:get_metrics(),
    Dashboard = performance_monitor:get_dashboard_data(),
    Alerts = performance_monitor:get_alerts(),

    #{
        <<"timestamp">> => os:system_time(millisecond),
        <<"metrics">> => Metrics,
        <<"dashboard">> => Dashboard,
        <<"alerts">> => Alerts,
        <<"system_health">> => get_system_health(),
        <<"recommendations">> => generate_performance_recommendations(Metrics, Dashboard)
    }.

get_system_health() ->
    %% Get overall system health status
    HealthStatus = #{
        <<"overall">> => calculate_overall_health(),
        <<"mcp_health">> => get_mcp_health(),
        <<"a2a_health">> => get_a2a_health(),
        <<"api_health">> => get_api_health(),
        <<"system_health">> => get_host_system_health()
    },

    HealthStatus.

%%====================================================================
%% Internal Functions
%%====================================================================

start_performance_components() ->
    %% Start all performance monitoring components
    ok = performance_metrics:start_link(),
    ok = performance_monitor:start_link(),
    ok = cache_manager:start_link(),
    ok = http_pool:start_link(),
    ok = dashboard:start_link(),
    ok = load_test:start_link(),

    %% Initialize configurations
    initialize_performance_configurations(),
    ok.

stop_performance_components() ->
    %% Stop all performance monitoring components
    load_test:stop(),
    dashboard:stop(),
    http_pool:stop(),
    cache_manager:stop(),
    performance_monitor:stop(),
    performance_metrics:stop(),

    ok.

integrate_systems() ->
    %% Integrate performance monitoring into existing systems
    integrate_with_mcp_server(),
    integrate_with_a2a_server(),
    integrate_with_api_client(),

    ok.

register_alerts() ->
    %% Register comprehensive alerting
    register_mcp_alerts(),
    register_a2a_alerts(),
    register_api_alerts(),
    register_system_alerts(),

    ok.

enable_system_monitoring() ->
    %% Enable system-level monitoring
    enable_memory_monitoring(),
    enable_cpu_monitoring(),
    enable_network_monitoring(),
    enable_disk_monitoring(),

    ok.

disable_system_monitoring() ->
    %% Disable system-level monitoring
    disable_memory_monitoring(),
    disable_cpu_monitoring(),
    disable_network_monitoring(),
    disable_disk_monitoring(),

    ok.

enable_cache_monitoring() ->
    %% Enable cache monitoring
    enable_mcp_cache_monitoring(),
    enable_api_cache_monitoring(),
    enable_session_cache_monitoring(),

    ok.

disable_cache_monitoring() ->
    %% Disable cache monitoring
    disable_mcp_cache_monitoring(),
    disable_api_cache_monitoring(),
    disable_session_cache_monitoring(),

    ok.

enable_connection_monitoring() ->
    %% Enable connection monitoring
    enable_http_connection_monitoring(),
    enable_websocket_connection_monitoring(),
    enable_database_connection_monitoring(),

    ok.

disable_connection_monitoring() ->
    %% Disable connection monitoring
    disable_http_connection_monitoring(),
    disable_websocket_connection_monitoring(),
    disable_database_connection_monitoring(),

    ok.

update_mcp_server() ->
    %% Update MCP server with performance optimizations
    configure_mcp_server_optimizations(),
    optimize_mcp_request_handling(),
    enhance_mcp_error_handling(),
    improve_mcp_caching_strategy(),

    ok.

update_a2a_server() ->
    %% Update A2A server with performance optimizations
    configure_a2a_server_optimizations(),
    optimize_a2a_task_queue(),
    enhance_a2a_error_handling(),
    improve_a2a_retry_mechanism(),

    ok.

configure_mcp_caching() ->
    %% Configure MCP caching for performance
    configure_mcp_cache_strategy(),
    set_mcp_cache_policies(),
    optimize_mcp_cache_eviction(),

    ok.

optimize_mcp_connections() ->
    %% Optimize MCP server connections
    configure_mcp_connection_pool(),
    set_mcp_connection_limits(),
    optimize_mcp_connection_timeout(),

    ok.

configure_a2a_queue() ->
    %% Configure A2A task queue for performance
    configure_a2a_queue_strategy(),
    set_a2a_queue_priorities(),
    optimize_a2a_queue_processing(),

    ok.

optimize_a2a_task_processing() ->
    %% Optimize A2A task processing
    configure_a2a_concurrency_limits(),
    set_a2a_task_timeouts(),
    optimize_a2a_task_retry(),

    ok.

generate_performance_recommendations(Metrics, Dashboard) ->
    %% Generate performance recommendations based on metrics
    Recommendations = #{
        <<"mcp_recommendations">> => generate_mcp_recommendations(Metrics),
        <<"a2a_recommendations">> => generate_a2a_recommendations(Metrics),
        <<"api_recommendations">> => generate_api_recommendations(Metrics),
        <<"system_recommendations">> => generate_system_recommendations(Metrics),
        <<"optimization_actions">> => generate_optimization_actions()
    },

    Recommendations.

calculate_overall_health() ->
    %% Calculate overall system health score
    Metrics = performance_metrics:get_metrics(),
    Dashboard = performance_monitor:get_dashboard_data(),

    HealthFactors = [
        calculate_mcp_health(Metrics),
        calculate_a2a_health(Metrics),
        calculate_api_health(Metrics),
        calculate_system_health(Metrics)
    ],

    Score = lists:sum(HealthFactors) / length(HealthFactors),

    case Score of
        Score when Score >= 0.8 -> <<"excellent">>;
        Score when Score >= 0.6 -> <<"good">>;
        Score when Score >= 0.4 -> <<"fair">>;
        _ -> <<"poor">>
    end.

get_mcp_health() ->
    %% Get MCP-specific health status
    Metrics = performance_metrics:get_metrics(),

    #{
        <<"status">> => calculate_mcp_health_status(Metrics),
        <<"requests">> => maps:get(<<"mcp.requests">>, Metrics#{"counters"}, 0),
        <<"errors">> => maps:get(<<"mcp.errors">>, Metrics#{"counters"}, 0),
        <<"avg_response_time">> => calculate_mcp_avg_response_time(Metrics),
        <<"cache_hit_rate">> => calculate_mcp_cache_hit_rate(Metrics)
    }.

get_a2a_health() ->
    %% Get A2A-specific health status
    Metrics = performance_metrics:get_metrics(),

    #{
        <<"status">> => calculate_a2a_health_status(Metrics),
        <<"tasks_submitted">> => maps.get(<<"a2a.tasks_submitted">>, Metrics#{"counters"}, 0),
        <<"tasks_completed">> => maps.get(<<"a2a.tasks_completed">>, Metrics#{"counters"}, 0),
        <<"tasks_failed">> => maps.get(<<"a2a.tasks_failed">>, Metrics#{"counters"}, 0),
        <<"queue_size">> => maps.get(<<"a2a.queue_size">>, Metrics#{"counters"}, 0),
        <<"avg_task_time">> => calculate_a2a_avg_task_time(Metrics)
    }.

get_api_health() ->
    %% Get API-specific health status
    Metrics = performance_metrics:get_metrics(),

    #{
        <<"status">> => calculate_api_health_status(Metrics),
        <<"call_rate">> => maps.get(<<"api.call_rate">>, Metrics#{"counters"}, 0),
        <<"error_rate">> => maps.get(<<"api.api_error_rate">>, Metrics#{"counters"}, 0),
        <<"avg_response_time">> => calculate_api_avg_response_time(Metrics)
    }.

get_host_system_health() ->
    %% Get host system health status
    {TotalMemory, ProcessesMemory, SystemMemory} = erlang:memory(),
    ProcessCount = length(processes()),
    CpuUsage = calculate_cpu_usage(),

    #{
        <<"memory_usage">> => #{
            <<"total">> => TotalMemory,
            <<"processes">> => ProcessesMemory,
            <<"system">> => SystemMemory,
            <<"utilization">> => calculate_memory_utilization(TotalMemory)
        },
        <<"process_count">> => ProcessCount,
        <<"cpu_usage">> => CpuUsage,
        <<"system_load">> => calculate_system_load(),
        <<"status">> => calculate_system_health_status()
    }.

initialize_performance_configurations() ->
    %% Initialize performance monitoring configurations
    set_default_performance_settings(),
    configure_performance_thresholds(),
    set_optimization_policies(),

    ok.

integrate_with_mcp_server() ->
    %% Integrate performance monitoring with MCP server
    patch_mcp_server_calls(),
    add_mcp_server_metrics(),
    configure_mcp_server_monitoring(),

    ok.

integrate_with_a2a_server() ->
    %% Integrate performance monitoring with A2A server
    patch_a2a_server_calls(),
    add_a2a_server_metrics(),
    configure_a2a_server_monitoring(),

    ok.

integrate_with_api_client() ->
    %% Integrate performance monitoring with API client
    patch_api_client_calls(),
    add_api_client_metrics(),
    configure_api_client_monitoring(),

    ok.

register_mcp_alerts() ->
    %% Register MCP-specific alerts
    performance_monitor:register_alert(<<"mcp_high_error_rate">>, <<"mcp.error_rate">>, #{
        type => threshold,
        operator => '>',
        value => 0.05,
        duration => 300000,
        enabled => true
    }),

    performance_monitor:register_alert(<<"mcp_high_latency">>, <<"mcp.avg_response_time">>, #{
        type => threshold,
        operator => '>',
        value => 500,
        duration => 300000,
        enabled => true
    }),

    ok.

register_a2a_alerts() ->
    %% Register A2A-specific alerts
    performance_monitor:register_alert(<<"a2a_high_queue">>, <<"a2a.queue_size">>, #{
        type => threshold,
        operator => '>',
        value => 100,
        duration => 300000,
        enabled => true
    }),

    performance_monitor:register_alert(<<"a2a_high_failure_rate">>, <<"a2a.task_error_rate">>, #{
        type => threshold,
        operator => '>',
        value => 0.02,
        duration => 300000,
        enabled => true
    }),

    ok.

register_api_alerts() ->
    %% Register API-specific alerts
    performance_monitor:register_alert(<<"api_high_error_rate">>, <<"api.api_error_rate">>, #{
        type => threshold,
        operator => '>',
        value => 0.01,
        duration => 300000,
        enabled => true
    }),

    performance_monitor:register_alert(<<"api_high_latency">>, <<"api.avg_response_time">>, #{
        type => threshold,
        operator => '>',
        value => 1000,
        duration => 300000,
        enabled => true
    }),

    ok.

register_system_alerts() ->
    %% Register system-wide alerts
    performance_monitor:register_alert(<<"high_memory_usage">>, <<"system.memory.processes">>, #{
        type => threshold,
        operator => '>',
        value => 1000000000, % 1GB
        duration => 300000,
        enabled => true
    }),

    performance_monitor:register_alert(<<"high_cpu_usage">>, <<"system.cpu.usage">>, #{
        type => threshold,
        operator => '>',
        value => 80,
        duration => 300000,
        enabled => true
    }),

    ok.

%% Helper functions for health calculations
calculate_mcp_health(Metrics) ->
    Requests = maps:get(<<"mcp.requests">>, Metrics#{"counters"}, 0),
    Errors = maps:get(<<"mcp.errors">>, Metrics#{"counters"}, 0),

    case Requests > 0 of
        true ->
            1.0 - (Errors / Requests);
        false ->
            1.0
    end.

calculate_a2a_health(Metrics) ->
    Submitted = maps:get(<<"a2a.tasks_submitted">>, Metrics#{"counters"}, 0),
    Failed = maps:get(<<"a2a.tasks_failed">>, Metrics#{"counters"}, 0),

    case Submitted > 0 of
        true ->
            1.0 - (Failed / Submitted);
        false ->
            1.0
    end.

calculate_api_health(Metrics) ->
    Calls = maps:get(<<"api.call_rate">>, Metrics#{"counters"}, 0),
    Errors = maps:get(<<"api.api_error_rate">>, Metrics#{"counters"}, 0),

    case Calls > 0 of
        true ->
            1.0 - (Errors / Calls);
        false ->
            1.0
    end.

calculate_system_health(Metrics) ->
    Memory = maps:get(<<"system.memory.processes">>, Metrics#{"gauges"}, 0),
    Cpu = maps:get(<<"system.cpu.usage">>, Metrics#{"gauges"}, 0),

    MemoryScore = case Memory > 1000000000 of
        true -> 0.5;
        false -> 1.0
    end,

    CpuScore = case Cpu > 80 of
        true -> 0.5;
        false -> 1.0
    end,

    (MemoryScore + CpuScore) / 2.

calculate_cpu_usage() ->
    %% Simple CPU usage calculation
    PrevCpu = get(prev_cpu_usage, 0),
    PrevTime = get(prev_cpu_time, os:system_time(millisecond)),

    CurrentCpu = process_info(self(), total_heap_size),
    CurrentTime = os:system_time(millisecond),

    case PrevCpu =/= 0 andalso PrevTime =/= 0 of
        true ->
            CpuDiff = CurrentCpu - PrevCpu,
            TimeDiff = CurrentTime - PrevTime,
            Usage = (CpuDiff / TimeDiff) * 100,
            put(prev_cpu_usage, CurrentCpu),
            put(prev_cpu_time, CurrentTime),
            min(max(Usage, 0), 100);
        false ->
            put(prev_cpu_usage, CurrentCpu),
            put(prev_cpu_time, CurrentTime),
            0
    end.

calculate_memory_utilization(TotalMemory) ->
    %% Calculate memory utilization percentage
    Used = erlang:memory(processes),
    (Used / TotalMemory) * 100.

calculate_system_load() ->
    %% Calculate system load average
    case os:type() of
        {unix, _} ->
            case file:read_file("/proc/loadavg") of
                {ok, Content} ->
                    case string:split(binary_to_list(Content), " ", leading) of
                        [Load | _] -> list_to_float(Load);
                        _ -> 0.0
                    end;
                _ -> 0.0
            end;
        _ -> 0.0
    end.

calculate_system_health_status() ->
    %% Determine overall system health status
    Health = get_system_health(),
    Overall = maps:get(<<"overall">>, Health),

    case Overall of
        <<"excellent">> -> 100;
        <<"good">> -> 80;
        <<"fair">> -> 60;
        _ -> 40
    end.

%% Additional helper functions would be implemented here
generate_mcp_recommendations(_Metrics) -> [].
generate_a2a_recommendations(_Metrics) -> [].
generate_api_recommendations(_Metrics) -> [].
generate_system_recommendations(_Metrics) -> [].
generate_optimization_actions() -> [].