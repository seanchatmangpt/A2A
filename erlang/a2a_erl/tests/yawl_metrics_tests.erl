%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL Metrics Collection
%%%
%%% Tests workflow metrics, service metrics, resource metrics,
%%% custom metrics, and export functionality.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_metrics_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

metrics_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Workflow metrics - record and retrieve", fun test_workflow_metrics/0},
      {"Service metrics - record and retrieve", fun test_service_metrics/0},
      {"Resource metrics - record and retrieve", fun test_resource_metrics/0},
      {"Custom counters", fun test_counters/0},
      {"Custom gauges", fun test_gauges/0},
      {"Histogram metrics", fun test_histograms/0},
      {"Timing metrics", fun test_timings/0},
      {"Metrics export to JSON", fun test_json_export/0},
      {"Metrics export to Prometheus", fun test_prometheus_export/0},
      {"Reset all metrics", fun test_reset_metrics/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    {ok, Pid} = yawl_metrics:start_link(),
    Pid.

cleanup(_Pid) ->
    gen_server:stop(yawl_metrics).

%%====================================================================
%% Test Cases
%%====================================================================

test_workflow_metrics() ->
    %% Record workflow start
    WorkflowId = <<"workflow_test_1">>,
    ?assertEqual(ok, yawl_metrics:record_workflow_start(WorkflowId)),

    %% Record workflow completion
    ?assertEqual(ok, yawl_metrics:record_workflow_complete(WorkflowId, 1500)),

    %% Get workflow metrics
    {ok, [Metrics]} = yawl_metrics:get_workflow_metrics(),
    ?assertEqual(WorkflowId, maps:get(workflow_id, Metrics)),
    ?assertEqual(1, maps:get(total_executions, Metrics)),
    ?assertEqual(1, maps:get(successful_executions, Metrics)),
    ?assertEqual(0, maps:get(failed_executions, Metrics)),
    ?assertEqual(1500, maps:get(last_execution_time, Metrics)),

    %% Record another workflow
    WorkflowId2 = <<"workflow_test_2">>,
    ?assertEqual(ok, yawl_metrics:record_workflow_start(WorkflowId2)),
    ?assertEqual(ok, yawl_metrics:record_workflow_complete(WorkflowId2, 2000)),

    %% Check multiple workflows
    {ok, AllMetrics} = yawl_metrics:get_workflow_metrics(),
    ?assertEqual(2, length(AllMetrics)),

    %% Record a failed workflow
    ?assertEqual(ok, yawl_metrics:record_workflow_start(WorkflowId)),
    ?assertEqual(ok, yawl_metrics:record_workflow_fail(WorkflowId, 500)),

    %% Check failure counts
    {ok, [UpdatedMetrics | _]} = yawl_metrics:get_workflow_metrics(),
    ?assertEqual(2, maps:get(total_executions, UpdatedMetrics)),
    ?assertEqual(1, maps:get(failed_executions, UpdatedMetrics)),
    ok.

test_service_metrics() ->
    %% Record service calls
    ServiceName = <<"test_service">>,
    ServiceType = rest,
    ?assertEqual(ok, yawl_metrics:record_service_call(ServiceName, ServiceType, 0)),
    ?assertEqual(ok, yawl_metrics:record_service_success(ServiceName, 100)),

    %% Get service metrics
    {ok, [Metrics]} = yawl_metrics:get_service_metrics(),
    ?assertEqual(ServiceName, maps:get(service_name, Metrics)),
    ?assertEqual(ServiceType, maps:get(service_type, Metrics)),
    ?assertEqual(1, maps:get(total_calls, Metrics)),
    ?assertEqual(1, maps:get(successful_calls, Metrics)),
    ?assertEqual(0, maps:get(failed_calls, Metrics)),
    ?assertEqual(100.0, maps:get(avg_response_time, Metrics)),
    ?assertEqual(1.0, maps:get(success_rate, Metrics)),

    %% Record more calls including failures
    ?assertEqual(ok, yawl_metrics:record_service_call(ServiceName, ServiceType, 0)),
    ?assertEqual(ok, yawl_metrics:record_service_success(ServiceName, 200)),
    ?assertEqual(ok, yawl_metrics:record_service_call(ServiceName, ServiceType, 0)),
    ?assertEqual(ok, yawl_metrics:record_service_failure(ServiceName, 50)),

    %% Check updated metrics
    {ok, [UpdatedMetrics]} = yawl_metrics:get_service_metrics(),
    ?assertEqual(3, maps:get(total_calls, UpdatedMetrics)),
    ?assertEqual(2, maps:get(successful_calls, UpdatedMetrics)),
    ?assertEqual(1, maps:get(failed_calls, UpdatedMetrics)),
    ?assertEqual(2.0 / 3.0, maps:get(success_rate, UpdatedMetrics)),
    ok.

test_resource_metrics() ->
    %% Record resource allocation
    ResourceId = <<"resource_test_1">>,
    ResourceType = human,
    ?assertEqual(ok, yawl_metrics:record_resource_allocation(ResourceId, ResourceType)),

    %% Get resource metrics
    {ok, [Metrics]} = yawl_metrics:get_resource_metrics(),
    ?assertEqual(ResourceId, maps:get(resource_id, Metrics)),
    ?assertEqual(ResourceType, maps:get(resource_type, Metrics)),
    ?assertEqual(1, maps:get(total_allocations, Metrics)),
    ?assertEqual(1, maps:get(current_allocations, Metrics)),
    ?assertEqual(1, maps:get(peak_allocations, Metrics)),

    %% Record more allocations
    ?assertEqual(ok, yawl_metrics:record_resource_allocation(ResourceId, ResourceType)),
    ?assertEqual(ok, yawl_metrics:record_resource_allocation(ResourceId, ResourceType)),

    %% Check allocation counts
    {ok, [UpdatedMetrics]} = yawl_metrics:get_resource_metrics(),
    ?assertEqual(3, maps:get(total_allocations, UpdatedMetrics)),
    ?assertEqual(3, maps:get(current_allocations, UpdatedMetrics)),
    ?assertEqual(3, maps:get(peak_allocations, UpdatedMetrics)),

    %% Record releases
    ?assertEqual(ok, yawl_metrics:record_resource_release(ResourceId, ResourceType)),
    ?assertEqual(ok, yawl_metrics:record_resource_release(ResourceId, ResourceType)),

    %% Check release counts
    {ok, [FinalMetrics]} = yawl_metrics:get_resource_metrics(),
    ?assertEqual(3, maps:get(total_allocations, FinalMetrics)),
    ?assertEqual(1, maps:get(current_allocations, FinalMetrics)),
    ?assertEqual(3, maps:get(peak_allocations, FinalMetrics)),
    ok.

test_counters() ->
    %% Test counter increments
    ?assertEqual(ok, yawl_metrics:increment_counter(<<"test_counter">>)),
    ?assertEqual(ok, yawl_metrics:increment_counter(<<"test_counter">>, 5)),

    %% Get all metrics and check counter
    {ok, AllMetrics} = yawl_metrics:get_all_metrics(),
    Counters = maps:get(counters, AllMetrics),
    ?assertEqual(6, maps:get(<<"test_counter">>, Counters)),

    %% Test atom counter name
    ?assertEqual(ok, yawl_metrics:increment_counter(atom_counter, 10)),
    {ok, AllMetrics2} = yawl_metrics:get_all_metrics(),
    Counters2 = maps:get(counters, AllMetrics2),
    ?assertEqual(10, maps:get(<<"atom_counter">>, Counters2)),
    ok.

test_gauges() ->
    %% Test setting gauges
    ?assertEqual(ok, yawl_metrics:set_gauge(<<"test_gauge">>, 42)),
    ?assertEqual(ok, yawl_metrics:set_gauge(<<"temperature">>, 98.6)),

    %% Get all metrics and check gauges
    {ok, AllMetrics} = yawl_metrics:get_all_metrics(),
    Gauges = maps:get(gauges, AllMetrics),
    ?assertEqual(42, maps:get(<<"test_gauge">>, Gauges)),
    ?assertEqual(98.6, maps:get(<<"temperature">>, Gauges)),

    %% Update gauge
    ?assertEqual(ok, yawl_metrics:set_gauge(<<"test_gauge">>, 100)),
    {ok, AllMetrics2} = yawl_metrics:get_all_metrics(),
    Gauges2 = maps:get(gauges, AllMetrics2),
    ?assertEqual(100, maps:get(<<"test_gauge">>, Gauges2)),
    ok.

test_histograms() ->
    %% Test histogram recording
    ?assertEqual(ok, yawl_metrics:record_histogram(<<"response_size">>, 150)),
    ?assertEqual(ok, yawl_metrics:record_histogram(<<"response_size">>, 5)),
    ?assertEqual(ok, yawl_metrics:record_histogram(<<"response_size">>, 750)),
    ?assertEqual(ok, yawl_metrics:record_histogram(<<"response_size">>, 5000)),
    ?assertEqual(ok, yawl_metrics:record_histogram(<<"response_size">>, 10000)),

    %% Get all metrics and check histogram
    {ok, AllMetrics} = yawl_metrics:get_all_metrics(),
    Histograms = maps:get(histograms, AllMetrics),
    ResponseSizeHistogram = maps:get(<<"response_size">>, Histograms),

    %% Check bucket distribution
    %% 150 goes to le="1" bucket
    %% 5 goes to le="1" bucket
    %% 750 goes to le="10" bucket
    %% 5000 goes to le="1000" bucket
    %% 10000 goes to le="+Inf" bucket
    ?assert(maps:is_key(<<"le=\"1\"">>, ResponseSizeHistogram)),
    ?assert(maps:is_key(<<"le=\"10\"">>, ResponseSizeHistogram)),
    ?assert(maps:is_key(<<"le=\"+Inf\"">>, ResponseSizeHistogram)),

    %% Check counts in buckets
    ?assertEqual(2, maps:get(<<"le=\"1\"">>, ResponseSizeHistogram)),
    ?assertEqual(1, maps:get(<<"le=\"10\"">>, ResponseSizeHistogram)),
    ?assertEqual(1, maps:get(<<"le=\"1000\"">>, ResponseSizeHistogram)),
    ?assertEqual(1, maps:get(<<"le=\"+Inf\"">>, ResponseSizeHistogram)),
    ok.

test_timings() ->
    %% Test timing recording
    Timings = [50, 100, 150, 200, 250, 300, 350, 400, 450, 500],
    lists:foreach(fun(T) ->
        ?assertEqual(ok, yawl_metrics:record_timing(<<"operation_duration">>, T))
    end, Timings),

    %% Get all metrics and check timing summary
    {ok, AllMetrics} = yawl_metrics:get_all_metrics(),
    TimingsMap = maps:get(timings, AllMetrics),
    TimingSummary = maps:get(<<"operation_duration">>, TimingsMap),

    %% Check statistics
    ?assertEqual(10, maps:get(count, TimingSummary)),
    ?assertEqual(50, maps:get(min, TimingSummary)),
    ?assertEqual(500, maps:get(max, TimingSummary)),
    ?assert(275.0 =< maps:get(avg, TimingSummary)),
    ?assert(275.0 >= maps:get(avg, TimingSummary)),

    %% Check percentiles (sorted: [50, 100, 150, 200, 250, 300, 350, 400, 450, 500])
    ?assertEqual(250, maps:get(p50, TimingSummary)),
    ?assertEqual(450, maps:get(p95, TimingSummary)),
    ?assertEqual(500, maps:get(p99, TimingSummary)),
    ok.

test_json_export() ->
    %% Record some metrics
    ?assertEqual(ok, yawl_metrics:increment_counter(<<"test_counter">>, 5)),
    ?assertEqual(ok, yawl_metrics:set_gauge(<<"test_gauge">>, 42)),

    %% Export as JSON
    JsonExport = yawl_metrics:export_json(),
    ?assert(is_binary(JsonExport)),

    %% Parse JSON and verify structure
    Decoded = jiffy:decode(JsonExport, [return_maps]),
    ?assert(maps:is_key(<<"workflows">>, Decoded)),
    ?assert(maps:is_key(<<"services">>, Decoded)),
    ?assert(maps:is_key(<<"resources">>, Decoded)),
    ?assert(maps:is_key(<<"counters">>, Decoded)),
    ?assert(maps:is_key(<<"gauges">>, Decoded)),
    ?assert(maps:is_key(<<"histograms">>, Decoded)),
    ?assert(maps:is_key(<<"timings">>, Decoded)),

    %% Check counter value
    Counters = maps:get(<<"counters">>, Decoded),
    ?assertEqual(5, maps:get(<<"test_counter">>, Counters)),

    %% Check gauge value
    Gauges = maps:get(<<"gauges">>, Decoded),
    ?assertEqual(42, maps:get(<<"test_gauge">>, Gauges)),
    ok.

test_prometheus_export() ->
    %% Record workflow and service metrics
    WorkflowId = <<"workflow_prom_test">>,
    ?assertEqual(ok, yawl_metrics:record_workflow_start(WorkflowId)),
    ?assertEqual(ok, yawl_metrics:record_workflow_complete(WorkflowId, 1000)),

    ServiceName = <<"service_prom_test">>,
    ?assertEqual(ok, yawl_metrics:record_service_call(ServiceName, rest, 0)),
    ?assertEqual(ok, yawl_metrics:record_service_success(ServiceName, 250)),

    %% Export as Prometheus format
    PrometheusExport = yawl_metrics:export_prometheus(),
    ?assert(is_binary(PrometheusExport)),

    %% Verify Prometheus format contains expected metrics
    ?assertNotEqual(nomatch, binary:match(PrometheusExport, <<"yawl_workflow_executions_total">>)),
    ?assertNotEqual(nomatch, binary:match(PrometheusExport, <<"yawl_service_calls_total">>)),
    ?assertNotEqual(nomatch, binary:match(PrometheusExport, <<"yawl_workflow_duration_avg">>)),
    ?assertNotEqual(nomatch, binary:match(PrometheusExport, <<"yawl_service_duration_avg">>)),
    ok.

test_reset_metrics() ->
    %% Record some metrics
    ?assertEqual(ok, yawl_metrics:increment_counter(<<"reset_counter">>, 10)),
    ?assertEqual(ok, yawl_metrics:set_gauge(<<"reset_gauge">>, 100)),

    %% Verify metrics exist
    {ok, AllMetrics1} = yawl_metrics:get_all_metrics(),
    Counters1 = maps:get(counters, AllMetrics1),
    ?assertEqual(10, maps:get(<<"reset_counter">>, Counters1)),

    %% Reset metrics
    ?assertEqual(ok, yawl_metrics:reset_metrics()),

    %% Verify metrics are cleared
    {ok, AllMetrics2} = yawl_metrics:get_all_metrics(),
    ?assertEqual(#{}, maps:get(workflows, AllMetrics2)),
    ?assertEqual(#{}, maps:get(services, AllMetrics2)),
    ?assertEqual(#{}, maps:get(resources, AllMetrics2)),
    ?assertEqual(#{}, maps:get(counters, AllMetrics2)),
    ?assertEqual(#{}, maps:get(gauges, AllMetrics2)),
    ok.
