%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Metrics Collection Module
%%%
%%% This module provides comprehensive metrics collection for YAWL workflows,
%%% services, and system resources. It tracks execution times, success rates,
%%% resource usage, and provides aggregation capabilities.
%%%
%%% Features:
%%% - Workflow execution metrics (counters, gauges, histograms)
%%% - Service invocation metrics
%%% - Resource utilization metrics
%%% - Custom metric registration
%%% - Time-series aggregation
%%% - Prometheus-compatible export
%%% - ETS-based persistent storage
%%% - JSON export for monitoring systems
%%%
%%% Metric Types:
%%% - Counters: Monotonically increasing values (workflows created, completed, failed)
%%% - Gauges: Point-in-time values (active workflows, queued tasks)
%%% - Histograms: Distribution values (execution times, response sizes)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_metrics).
-author("A2A Team").
-behaviour(gen_server).

%% Metric table name for ETS storage
-define(METRICS_TABLE, yawl_metrics_table).
-define(METRICS_TABLE_OPTIONS, [set, public, named_table, {read_concurrency, true}]).

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

%% API exports - Workflow metrics
-export([
    record_workflow_start/1,
    record_workflow_complete/2,
    record_workflow_fail/2,
    get_workflow_metrics/0,
    get_workflow_metrics/1
]).

%% API exports - Service metrics
-export([
    record_service_call/3,
    record_service_success/2,
    record_service_failure/2,
    get_service_metrics/0,
    get_service_metrics/1
]).

%% API exports - Resource metrics
-export([
    record_resource_allocation/2,
    record_resource_release/2,
    record_resource_utilization/2,
    get_resource_metrics/0
]).

%% API exports - Custom metrics
-export([
    increment_counter/1,
    increment_counter/2,
    set_gauge/2,
    record_histogram/2,
    record_timing/2
]).

%% API exports - Metrics export
-export([
    get_all_metrics/0,
    export_prometheus/0,
    export_json/0,
    reset_metrics/0
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    %% Workflow metrics: #{workflow_id => workflow_metrics()}
    workflow_metrics = #{} :: map(),

    %% Service metrics: #{service_name => service_metrics()}
    service_metrics = #{} :: map(),

    %% Resource metrics: #{resource_id => resource_metrics()}
    resource_metrics = #{} :: map(),

    %% Counters: #{counter_name => value()}
    counters = #{} :: map(),

    %% Gauges: #{gauge_name => value()}
    gauges = #{} :: map(),

    %% Histograms: #{name => #{bucket => count}}
    histograms = #{} :: map(),

    %% Timing data: #{name => [milliseconds]}
    timings = #{} :: map(),

    %% Aggregation settings
    aggregation_window :: integer(),
    last_aggregation :: integer()
}).

-record(workflow_metrics, {
    workflow_id :: binary(),
    pattern_type :: atom(),
    total_executions = 0 :: non_neg_integer(),
    successful_executions = 0 :: non_neg_integer(),
    failed_executions = 0 :: non_neg_integer(),
    total_execution_time = 0 :: non_neg_integer(),
    min_execution_time :: undefined | integer(),
    max_execution_time :: undefined | integer(),
    avg_execution_time :: float(),
    last_execution_time :: undefined | integer(),
    last_execution_status :: pending | completed | failed
}).

-record(service_metrics, {
    service_name :: binary(),
    service_type :: atom(),
    total_calls = 0 :: non_neg_integer(),
    successful_calls = 0 :: non_neg_integer(),
    failed_calls = 0 :: non_neg_integer(),
    total_response_time = 0 :: non_neg_integer(),
    avg_response_time :: float(),
    success_rate :: float(),
    last_call_time :: undefined | integer(),
    last_call_status :: undefined | success | failure
}).

-record(resource_metrics, {
    resource_id :: binary(),
    resource_type :: human | service | system,
    total_allocations = 0 :: non_neg_integer(),
    current_allocations = 0 :: non_neg_integer(),
    peak_allocations = 0 :: non_neg_integer(),
    total_utilization_time = 0 :: non_neg_integer(),
    avg_utilization :: float()
}).

%%====================================================================
%% API Functions - Workflow Metrics
%%====================================================================

%% @doc Start the metrics collector.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Record workflow start.
-spec record_workflow_start(binary()) -> ok.
record_workflow_start(WorkflowId) ->
    gen_server:cast(?MODULE, {workflow_start, WorkflowId}).

%% @doc Record workflow completion with execution time.
-spec record_workflow_complete(binary(), integer()) -> ok.
record_workflow_complete(WorkflowId, ExecutionTime) ->
    gen_server:cast(?MODULE, {workflow_complete, WorkflowId, ExecutionTime}).

%% @doc Record workflow failure.
-spec record_workflow_fail(binary(), integer()) -> ok.
record_workflow_fail(WorkflowId, ExecutionTime) ->
    gen_server:cast(?MODULE, {workflow_fail, WorkflowId, ExecutionTime}).

%% @doc Get all workflow metrics.
-spec get_workflow_metrics() -> {ok, [map()]}.
get_workflow_metrics() ->
    gen_server:call(?MODULE, get_workflow_metrics).

%% @doc Get metrics for a specific workflow.
-spec get_workflow_metrics(binary()) -> {ok, map()} | {error, not_found}.
get_workflow_metrics(WorkflowId) ->
    gen_server:call(?MODULE, {get_workflow_metrics, WorkflowId}).

%%====================================================================
%% API Functions - Service Metrics
%%====================================================================

%% @doc Record a service call attempt.
-spec record_service_call(binary(), atom(), integer()) -> ok.
record_service_call(ServiceName, ServiceType, StartTime) ->
    gen_server:cast(?MODULE, {service_call, ServiceName, ServiceType, StartTime}).

%% @doc Record a successful service call.
-spec record_service_success(binary(), integer()) -> ok.
record_service_success(ServiceName, ResponseTime) ->
    gen_server:cast(?MODULE, {service_success, ServiceName, ResponseTime}).

%% @doc Record a failed service call.
-spec record_service_failure(binary(), integer()) -> ok.
record_service_failure(ServiceName, ResponseTime) ->
    gen_server:cast(?MODULE, {service_failure, ServiceName, ResponseTime}).

%% @doc Get all service metrics.
-spec get_service_metrics() -> {ok, [map()]}.
get_service_metrics() ->
    gen_server:call(?MODULE, get_service_metrics).

%% @doc Get metrics for a specific service.
-spec get_service_metrics(binary()) -> {ok, map()} | {error, not_found}.
get_service_metrics(ServiceName) ->
    gen_server:call(?MODULE, {get_service_metrics, ServiceName}).

%%====================================================================
%% API Functions - Resource Metrics
%%====================================================================

%% @doc Record resource allocation.
-spec record_resource_allocation(binary(), atom()) -> ok.
record_resource_allocation(ResourceId, ResourceType) ->
    gen_server:cast(?MODULE, {resource_allocate, ResourceId, ResourceType}).

%% @doc Record resource release.
-spec record_resource_release(binary(), atom()) -> ok.
record_resource_release(ResourceId, ResourceType) ->
    gen_server:cast(?MODULE, {resource_release, ResourceId, ResourceType}).

%% @doc Record current resource utilization.
-spec record_resource_utilization(binary(), integer()) -> ok.
record_resource_utilization(ResourceId, UtilizationPercent) ->
    gen_server:cast(?MODULE, {resource_utilization, ResourceId, UtilizationPercent}).

%% @doc Get all resource metrics.
-spec get_resource_metrics() -> {ok, [map()]}.
get_resource_metrics() ->
    gen_server:call(?MODULE, get_resource_metrics).

%%====================================================================
%% API Functions - Custom Metrics
%%====================================================================

%% @doc Increment a counter by 1.
-spec increment_counter(atom() | binary()) -> ok.
increment_counter(CounterName) ->
    increment_counter(CounterName, 1).

%% @doc Increment a counter by a specific value.
-spec increment_counter(atom() | binary(), integer()) -> ok.
increment_counter(CounterName, Value) ->
    gen_server:cast(?MODULE, {increment_counter, to_binary(CounterName), Value}).

%% @doc Set a gauge value.
-spec set_gauge(atom() | binary(), number()) -> ok.
set_gauge(GaugeName, Value) ->
    gen_server:cast(?MODULE, {set_gauge, to_binary(GaugeName), Value}).

%% @doc Record a histogram value.
-spec record_histogram(atom() | binary(), number()) -> ok.
record_histogram(HistogramName, Value) ->
    gen_server:cast(?MODULE, {record_histogram, to_binary(HistogramName), Value}).

%% @doc Record a timing value in milliseconds.
-spec record_timing(atom() | binary(), integer()) -> ok.
record_timing(TimingName, Milliseconds) ->
    gen_server:cast(?MODULE, {record_timing, to_binary(TimingName), Milliseconds}).

%%====================================================================
%% API Functions - Metrics Export
%%====================================================================

%% @doc Get all metrics as a map.
-spec get_all_metrics() -> {ok, map()}.
get_all_metrics() ->
    gen_server:call(?MODULE, get_all_metrics).

%% @doc Export metrics in Prometheus text format.
-spec export_prometheus() -> binary().
export_prometheus() ->
    gen_server:call(?MODULE, export_prometheus).

%% @doc Export metrics as JSON.
-spec export_json() -> binary().
export_json() ->
    gen_server:call(?MODULE, export_json).

%% @doc Reset all metrics.
-spec reset_metrics() -> ok.
reset_metrics() ->
    gen_server:call(?MODULE, reset_metrics).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    AggregationWindow = application:get_env(a2a_erl, metrics_aggregation_window, 60000),
    {ok, #state{
        aggregation_window = AggregationWindow,
        last_aggregation = erlang:monotonic_time(millisecond)
    }}.

%% @private
handle_call(get_workflow_metrics, _From, State) ->
    Metrics = [workflow_metrics_to_map(Id, M) || Id <- maps:keys(State#state.workflow_metrics),
                                                 M <- [maps:get(Id, State#state.workflow_metrics)]],
    {reply, {ok, Metrics}, State};

handle_call({get_workflow_metrics, WorkflowId}, _From, State) ->
    case maps:get(WorkflowId, State#state.workflow_metrics, undefined) of
        undefined -> {reply, {error, not_found}, State};
        Metrics -> {reply, {ok, workflow_metrics_to_map(WorkflowId, Metrics)}, State}
    end;

handle_call(get_service_metrics, _From, State) ->
    Metrics = [service_metrics_to_map(Name, M) || Name <- maps:keys(State#state.service_metrics),
                                                   M <- [maps:get(Name, State#state.service_metrics)]],
    {reply, {ok, Metrics}, State};

handle_call({get_service_metrics, ServiceName}, _From, State) ->
    case maps:get(ServiceName, State#state.service_metrics, undefined) of
        undefined -> {reply, {error, not_found}, State};
        Metrics -> {reply, {ok, service_metrics_to_map(ServiceName, Metrics)}, State}
    end;

handle_call(get_resource_metrics, _From, State) ->
    Metrics = [resource_metrics_to_map(Id, M) || Id <- maps:keys(State#state.resource_metrics),
                                                   M <- [maps:get(Id, State#state.resource_metrics)]],
    {reply, {ok, Metrics}, State};

handle_call(get_all_metrics, _From, State) ->
    AllMetrics = #{
        workflows => [workflow_metrics_to_map(Id, M) || Id <- maps:keys(State#state.workflow_metrics),
                                                        M <- [maps:get(Id, State#state.workflow_metrics)]],
        services => [service_metrics_to_map(Name, M) || Name <- maps:keys(State#state.service_metrics),
                                                         M <- [maps:get(Name, State#state.service_metrics)]],
        resources => [resource_metrics_to_map(Id, M) || Id <- maps:keys(State#state.resource_metrics),
                                                          M <- [maps:get(Id, State#state.resource_metrics)]],
        counters => State#state.counters,
        gauges => State#state.gauges,
        histograms => State#state.histograms,
        timings => timings_to_summary(State#state.timings)
    },
    {reply, {ok, AllMetrics}, State};

handle_call(export_prometheus, _From, State) ->
    Output = build_prometheus_export(State),
    {reply, Output, State};

handle_call(export_json, _From, State) ->
    {ok, AllMetrics} = get_all_metrics_data(State),
    {reply, jiffy:encode(AllMetrics), State};

handle_call(reset_metrics, _From, _State) ->
    {reply, ok, #state{
        aggregation_window = _State#state.aggregation_window,
        last_aggregation = erlang:monotonic_time(millisecond)
    }};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({workflow_start, WorkflowId}, State) ->
    NewWorkflowMetrics = maps:put(WorkflowId, #workflow_metrics{
        workflow_id = WorkflowId,
        pattern_type = unknown,
        last_execution_status = running
    }, State#state.workflow_metrics),
    {noreply, State#state{workflow_metrics = NewWorkflowMetrics}};

handle_cast({workflow_complete, WorkflowId, ExecutionTime}, State) ->
    NewWorkflowMetrics = update_workflow_metrics(WorkflowId, ExecutionTime, success, State),
    {noreply, State#state{workflow_metrics = NewWorkflowMetrics}};

handle_cast({workflow_fail, WorkflowId, ExecutionTime}, State) ->
    NewWorkflowMetrics = update_workflow_metrics(WorkflowId, ExecutionTime, failure, State),
    {noreply, State#state{workflow_metrics = NewWorkflowMetrics}};

handle_cast({service_call, ServiceName, ServiceType, _StartTime}, State) ->
    NewServiceMetrics = update_service_call_start(ServiceName, ServiceType, State),
    {noreply, State#state{service_metrics = NewServiceMetrics}};

handle_cast({service_success, ServiceName, ResponseTime}, State) ->
    NewServiceMetrics = update_service_call(ServiceName, ResponseTime, success, State),
    {noreply, State#state{service_metrics = NewServiceMetrics}};

handle_cast({service_failure, ServiceName, ResponseTime}, State) ->
    NewServiceMetrics = update_service_call(ServiceName, ResponseTime, failure, State),
    {noreply, State#state{service_metrics = NewServiceMetrics}};

handle_cast({resource_allocate, ResourceId, ResourceType}, State) ->
    NewResourceMetrics = update_resource_allocation(ResourceId, ResourceType, allocate, State),
    {noreply, State#state{resource_metrics = NewResourceMetrics}};

handle_cast({resource_release, ResourceId, ResourceType}, State) ->
    NewResourceMetrics = update_resource_allocation(ResourceId, ResourceType, release, State),
    {noreply, State#state{resource_metrics = NewResourceMetrics}};

handle_cast({resource_utilization, ResourceId, UtilizationPercent}, State) ->
    %% Could track utilization over time
    NewGauges = maps:put(<<"resource_utilization_", ResourceId/binary>>, UtilizationPercent, State#state.gauges),
    {noreply, State#state{gauges = NewGauges}};

handle_cast({increment_counter, CounterName, Value}, State) ->
    CurrentValue = maps:get(CounterName, State#state.counters, 0),
    NewCounters = maps:put(CounterName, CurrentValue + Value, State#state.counters),
    {noreply, State#state{counters = NewCounters}};

handle_cast({set_gauge, GaugeName, Value}, State) ->
    NewGauges = maps:put(GaugeName, Value, State#state.gauges),
    {noreply, State#state{gauges = NewGauges}};

handle_cast({record_histogram, HistogramName, Value}, State) ->
    CurrentHistogram = maps:get(HistogramName, State#state.histograms, #{}),
    Bucket = get_histogram_bucket(Value),
    CurrentCount = maps:get(Bucket, CurrentHistogram, 0),
    NewHistogram = maps:put(Bucket, CurrentCount + 1, CurrentHistogram),
    NewHistograms = maps:put(HistogramName, NewHistogram, State#state.histograms),
    {noreply, State#state{histograms = NewHistograms}};

handle_cast({record_timing, TimingName, Milliseconds}, State) ->
    CurrentTimings = maps:get(TimingName, State#state.timings, []),
    %% Keep only last 1000 timings per name to prevent unbounded growth
    NewTimings = lists:sublist([Milliseconds | CurrentTimings], 1000),
    NewTimingsMap = maps:put(TimingName, NewTimings, State#state.timings),
    {noreply, State#state{timings = NewTimingsMap}};

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
update_workflow_metrics(WorkflowId, ExecutionTime, Result, State) ->
    Current = maps:get(WorkflowId, State#state.workflow_metrics,
        #workflow_metrics{workflow_id = WorkflowId, pattern_type = unknown}),

    TotalExec = Current#workflow_metrics.total_executions + 1,
    {SuccessExec, FailedExec} = case Result of
        success -> {Current#workflow_metrics.successful_executions + 1, Current#workflow_metrics.failed_executions};
        failure -> {Current#workflow_metrics.successful_executions, Current#workflow_metrics.failed_executions + 1}
    end,

    TotalTime = Current#workflow_metrics.total_execution_time + ExecutionTime,
    AvgTime = TotalTime / TotalExec,

    MinTime = case Current#workflow_metrics.min_execution_time of
        undefined -> ExecutionTime;
        Min -> min(Min, ExecutionTime)
    end,

    MaxTime = case Current#workflow_metrics.max_execution_time of
        undefined -> ExecutionTime;
        Max -> max(Max, ExecutionTime)
    end,

    NewStatus = case Result of
        success -> completed;
        failure -> failed
    end,

    maps:put(WorkflowId, Current#workflow_metrics{
        total_executions = TotalExec,
        successful_executions = SuccessExec,
        failed_executions = FailedExec,
        total_execution_time = TotalTime,
        min_execution_time = MinTime,
        max_execution_time = MaxTime,
        avg_execution_time = AvgTime,
        last_execution_time = ExecutionTime,
        last_execution_status = NewStatus
    }, State#state.workflow_metrics).

%% @private
update_service_call_start(ServiceName, ServiceType, _State) ->
    %% Initialize service metrics if not exists
    InitialMetrics = #service_metrics{
        service_name = ServiceName,
        service_type = ServiceType
    },
    maps:put(ServiceName, InitialMetrics, _State#state.service_metrics).

%% @private
update_service_call(ServiceName, ResponseTime, Result, State) ->
    Current = maps:get(ServiceName, State#state.service_metrics,
        #service_metrics{service_name = ServiceName, service_type = unknown}),

    TotalCalls = Current#service_metrics.total_calls + 1,
    {SuccessCalls, FailedCalls} = case Result of
        success -> {Current#service_metrics.successful_calls + 1, Current#service_metrics.failed_calls};
        failure -> {Current#service_metrics.successful_calls, Current#service_metrics.failed_calls + 1}
    end,

    TotalTime = Current#service_metrics.total_response_time + ResponseTime,
    AvgTime = TotalTime / TotalCalls,
    SuccessRate = SuccessCalls / TotalCalls,

    maps:put(ServiceName, Current#service_metrics{
        total_calls = TotalCalls,
        successful_calls = SuccessCalls,
        failed_calls = FailedCalls,
        total_response_time = TotalTime,
        avg_response_time = AvgTime,
        success_rate = SuccessRate,
        last_call_time = ResponseTime,
        last_call_status = Result
    }, State#state.service_metrics).

%% @private
update_resource_allocation(ResourceId, ResourceType, Action, State) ->
    Current = maps:get(ResourceId, State#state.resource_metrics,
        #resource_metrics{resource_id = ResourceId, resource_type = ResourceType}),

    {TotalAlloc, CurrentAlloc, PeakAlloc} = case Action of
        allocate ->
            NewCurrent = Current#resource_metrics.current_allocations + 1,
            NewPeak = max(NewCurrent, Current#resource_metrics.peak_allocations),
            {Current#resource_metrics.total_allocations + 1, NewCurrent, NewPeak};
        release ->
            NewCurrent = max(0, Current#resource_metrics.current_allocations - 1),
            {Current#resource_metrics.total_allocations, NewCurrent, Current#resource_metrics.peak_allocations}
    end,

    maps:put(ResourceId, Current#resource_metrics{
        total_allocations = TotalAlloc,
        current_allocations = CurrentAlloc,
        peak_allocations = PeakAlloc
    }, State#state.resource_metrics).

%% @private
get_histogram_bucket(Value) when Value < 1 -> <<"le=\"0.1\"">>;
get_histogram_bucket(Value) when Value < 5 -> <<"le=\"1\"">>;
get_histogram_bucket(Value) when Value < 10 -> <<"le=\"5\"">>;
get_histogram_bucket(Value) when Value < 50 -> <<"le=\"10\"">>;
get_histogram_bucket(Value) when Value < 100 -> <<"le=\"50\"">>;
get_histogram_bucket(Value) when Value < 500 -> <<"le=\"100\"">>;
get_histogram_bucket(Value) when Value < 1000 -> <<"le=\"500\"">>;
get_histogram_bucket(Value) when Value < 5000 -> <<"le=\"1000\"">>;
get_histogram_bucket(Value) when Value < 10000 -> <<"le=\"5000\"">>;
get_histogram_bucket(_Value) -> <<"le=\"+Inf\"">>.

%% @private
build_prometheus_export(State) ->
    Lines = [
        build_counter_prometheus(State#state.counters),
        build_gauge_prometheus(State#state.gauges),
        build_workflow_prometheus(State#state.workflow_metrics),
        build_service_prometheus(State#state.service_metrics),
        build_resource_prometheus(State#state.resource_metrics)
    ],
    iolist_to_binary(lists:join(<<"\n">>, [L || L <- Lines, L =/= <<>>])).

%% @private
build_counter_prometheus(Counters) ->
    Lines = maps:fold(fun(Name, Value, Acc) ->
        [<<Name/binary, " ", (integer_to_binary(Value))/binary>> | Acc]
    end, [], Counters),
    iolist_to_binary(lists:reverse(Lines)).

%% @private
build_gauge_prometheus(Gauges) ->
    Lines = maps:fold(fun(Name, Value, Acc) ->
        FormattedValue = case is_float(Value) of
            true -> float_to_binary(Value, [{decimals, 2}, compact]);
            false -> integer_to_binary(Value)
        end,
        [<<Name/binary, " ", FormattedValue/binary>> | Acc]
    end, [], Gauges),
    iolist_to_binary(lists:reverse(Lines)).

%% @private
build_workflow_prometheus(WorkflowMetrics) ->
    Lines = maps:fold(fun(_Id, Metrics, Acc) ->
        [
            <<"yawl_workflow_executions_total{pattern=\"",
              (atom_to_binary(Metrics#workflow_metrics.pattern_type, utf8))/binary,
              "\"} ", (integer_to_binary(Metrics#workflow_metrics.total_executions))/binary>>,
            <<"yawl_workflow_executions_successful{pattern=\"",
              (atom_to_binary(Metrics#workflow_metrics.pattern_type, utf8))/binary,
              "\"} ", (integer_to_binary(Metrics#workflow_metrics.successful_executions))/binary>>,
            <<"yawl_workflow_executions_failed{pattern=\"",
              (atom_to_binary(Metrics#workflow_metrics.pattern_type, utf8))/binary,
              "\"} ", (integer_to_binary(Metrics#workflow_metrics.failed_executions))/binary>>,
            <<"yawl_workflow_duration_avg{pattern=\"",
              (atom_to_binary(Metrics#workflow_metrics.pattern_type, utf8))/binary,
              "\"} ", (float_to_binary(Metrics#workflow_metrics.avg_execution_time, [{decimals, 2}, compact]))/binary>>
        ] ++ Acc
    end, [], WorkflowMetrics),
    iolist_to_binary(lists:reverse(Lines)).

%% @private
build_service_prometheus(ServiceMetrics) ->
    Lines = maps:fold(fun(_Name, Metrics, Acc) ->
        ServiceName = Metrics#service_metrics.service_name,
        ServiceType = atom_to_binary(Metrics#service_metrics.service_type, utf8),
        TotalCalls = integer_to_binary(Metrics#service_metrics.total_calls),
        SuccessfulCalls = integer_to_binary(Metrics#service_metrics.successful_calls),
        AvgResponseTime = float_to_binary(Metrics#service_metrics.avg_response_time, [{decimals, 2}, compact]),
        SuccessRate = float_to_binary(Metrics#service_metrics.success_rate, [{decimals, 3}, compact]),
        [
            <<"yawl_service_calls_total{service=\"", ServiceName/binary,
              "\",type=\"", ServiceType/binary,
              "\"} ", TotalCalls/binary>>,
            <<"yawl_service_calls_successful{service=\"", ServiceName/binary,
              "\"} ", SuccessfulCalls/binary>>,
            <<"yawl_service_duration_avg{service=\"", ServiceName/binary,
              "\"} ", AvgResponseTime/binary>>,
            <<"yawl_service_success_rate{service=\"", ServiceName/binary,
              "\"} ", SuccessRate/binary>>
        ] ++ Acc
    end, [], ServiceMetrics),
    iolist_to_binary(lists:reverse(Lines)).

%% @private
build_resource_prometheus(ResourceMetrics) ->
    Lines = maps:fold(fun(_Id, Metrics, Acc) ->
        ResourceId = Metrics#resource_metrics.resource_id,
        TotalAllocations = integer_to_binary(Metrics#resource_metrics.total_allocations),
        CurrentAllocations = integer_to_binary(Metrics#resource_metrics.current_allocations),
        PeakAllocations = integer_to_binary(Metrics#resource_metrics.peak_allocations),
        [
            <<"yawl_resource_allocations_total{resource=\"", ResourceId/binary,
              "\"} ", TotalAllocations/binary>>,
            <<"yawl_resource_allocations_current{resource=\"", ResourceId/binary,
              "\"} ", CurrentAllocations/binary>>,
            <<"yawl_resource_allocations_peak{resource=\"", ResourceId/binary,
              "\"} ", PeakAllocations/binary>>
        ] ++ Acc
    end, [], ResourceMetrics),
    iolist_to_binary(lists:reverse(Lines)).

%% @private
get_all_metrics_data(State) ->
    {ok, #{
        workflows => [workflow_metrics_to_map(Id, M) || Id <- maps:keys(State#state.workflow_metrics),
                                                        M <- [maps:get(Id, State#state.workflow_metrics)]],
        services => [service_metrics_to_map(Name, M) || Name <- maps:keys(State#state.service_metrics),
                                                         M <- [maps:get(Name, State#state.service_metrics)]],
        resources => [resource_metrics_to_map(Id, M) || Id <- maps:keys(State#state.resource_metrics),
                                                          M <- [maps:get(Id, State#state.resource_metrics)]],
        counters => State#state.counters,
        gauges => State#state.gauges,
        histograms => State#state.histograms,
        timings => timings_to_summary(State#state.timings)
    }}.

%% @private
timings_to_summary(Timings) ->
    maps:map(fun(_Name, Values) ->
        case Values of
            [] -> #{count => 0, min => 0, max => 0, avg => 0.0, p50 => 0, p95 => 0, p99 => 0};
            _ ->
                Sorted = lists:sort(Values),
                Count = length(Sorted),
                #{count => Count,
                  min => lists:min(Values),
                  max => lists:max(Values),
                  avg => lists:sum(Values) / Count,
                  p50 => percentile(Sorted, 50),
                  p95 => percentile(Sorted, 95),
                  p99 => percentile(Sorted, 99)}
        end
    end, Timings).

%% @private
percentile(SortedList, Percentile) ->
    Index = max(1, round(Percentile / 100 * length(SortedList))),
    lists:nth(Index, SortedList).

%% @private
workflow_metrics_to_map(Id, #workflow_metrics{} = M) ->
    #{
        workflow_id => Id,
        pattern_type => M#workflow_metrics.pattern_type,
        total_executions => M#workflow_metrics.total_executions,
        successful_executions => M#workflow_metrics.successful_executions,
        failed_executions => M#workflow_metrics.failed_executions,
        total_execution_time => M#workflow_metrics.total_execution_time,
        min_execution_time => M#workflow_metrics.min_execution_time,
        max_execution_time => M#workflow_metrics.max_execution_time,
        avg_execution_time => M#workflow_metrics.avg_execution_time,
        last_execution_time => M#workflow_metrics.last_execution_time,
        last_execution_status => M#workflow_metrics.last_execution_status,
        success_rate => case M#workflow_metrics.total_executions of
            0 -> 0.0;
            Total -> M#workflow_metrics.successful_executions / Total
        end
    }.

%% @private
service_metrics_to_map(Name, #service_metrics{} = M) ->
    #{
        service_name => Name,
        service_type => M#service_metrics.service_type,
        total_calls => M#service_metrics.total_calls,
        successful_calls => M#service_metrics.successful_calls,
        failed_calls => M#service_metrics.failed_calls,
        total_response_time => M#service_metrics.total_response_time,
        avg_response_time => M#service_metrics.avg_response_time,
        success_rate => M#service_metrics.success_rate,
        last_call_time => M#service_metrics.last_call_time,
        last_call_status => M#service_metrics.last_call_status
    }.

%% @private
resource_metrics_to_map(Id, #resource_metrics{} = M) ->
    #{
        resource_id => Id,
        resource_type => M#resource_metrics.resource_type,
        total_allocations => M#resource_metrics.total_allocations,
        current_allocations => M#resource_metrics.current_allocations,
        peak_allocations => M#resource_metrics.peak_allocations,
        total_utilization_time => M#resource_metrics.total_utilization_time,
        avg_utilization => M#resource_metrics.avg_utilization
    }.

%% @private
to_binary(Term) when is_binary(Term) -> Term;
to_binary(Term) when is_atom(Term) -> atom_to_binary(Term, utf8);
to_binary(Term) when is_integer(Term) -> integer_to_binary(Term);
to_binary(Term) when is_list(Term) -> list_to_binary(Term);
to_binary(Term) -> io_lib:format("~p", [Term]).
