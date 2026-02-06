%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Metrics REST Handler
%%%
%%% This module provides HTTP REST API endpoints for accessing YAWL
%%% system metrics. It supports multiple output formats including JSON
%%% and Prometheus text format.
%%%
%%% ## Endpoints
%%%
%%% - `GET /metrics` - Get all metrics (JSON or Prometheus format)
%%% - `GET /metrics/workflows` - Get workflow metrics
%%% - `GET /metrics/services` - Get service metrics
%%% - `GET /metrics/resources` - Get resource metrics
%%% - `DELETE /metrics` - Reset all metrics
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_metrics_handler).
-author("A2A Team").

%% Cowboy handler exports
-export([
    init/2,
    allowed_methods/2,
    content_types_provided/2,
    resource_exists/2,
    delete_resource/2,
    to_json/2,
    to_prometheus/2
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    method :: cowboy_http:method(),
    metrics_type :: binary() | undefined,
    format :: json | prometheus
}).

%%====================================================================
%% Cowboy Handler Callbacks
%%====================================================================

%% @private
init(Req, State) ->
    Method = cowboy_req:method(Req),
    MetricsType = cowboy_req:binding(metrics_type, Req),

    %% Determine format from query string or Accept header
    {QS, _} = cowboy_req:qs(Req),
    Format = case string:find(QS, "format=prometheus") of
        nomatch ->
            case cowboy_req:parse_header(<<"accept">>, Req) of
                {ok, [{<<"application">>, <<"prometheus">>, _}]} -> prometheus;
                {ok, [{<<"text">>, <<"plain">>, _}]} -> prometheus;
                {ok, [{<<"application">>, <<"json">>, _}]} -> json;
                _ -> json
            end;
        _ -> prometheus
    end,

    NewState = #state{
        method = Method,
        metrics_type = MetricsType,
        format = Format
    },

    {cowboy_rest, Req, NewState}.

%% @private
allowed_methods(Req, State) ->
    Methods = case State#state.metrics_type of
        undefined ->
            %% /metrics - GET, DELETE
            [<<"GET">>, <<"DELETE">>, <<"HEAD">>, <<"OPTIONS">>];
        _ ->
            %% /metrics/{type} - GET
            [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>]
    end,
    {Methods, Req, State}.

%% @private
content_types_provided(Req, State) ->
    {[
        {{<<"application">>, <<"json">>, '*'}, to_json},
        {{<<"text">>, <<"plain">>, '*'}, to_prometheus},
        {{<<"application">>, <<"prometheus">>, '*'}, to_prometheus}
    ], Req, State}.

%% @private
resource_exists(Req, State) ->
    %% Metrics endpoint always exists
    {true, Req, State}.

%% @private
delete_resource(Req, State) ->
    case State#state.metrics_type of
        undefined ->
            %% Reset all metrics
            case yawl_metrics:reset_metrics() of
                ok ->
                    Response = #{
                        status => ok,
                        message => <<"Metrics reset successfully">>
                    },
                    Req2 = response_json(Req, 200, Response),
                    {true, Req2, State};
                {error, Reason} ->
                    Response = #{error => to_binary(Reason)},
                    Req2 = response_json(Req, 500, Response),
                    {false, Req2, State}
            end;
        _ ->
            Response = #{error => <<"method_not_allowed">>},
            Req2 = response_json(Req, 405, Response),
            {false, Req2, State}
    end.

%% @private
to_json(Req, State) ->
    Response = build_json_response(State),
    ResponseBody = jiffy:encode(Response),
    {ResponseBody, Req, State}.

%% @private
to_prometheus(Req, State) ->
    Response = build_prometheus_response(State),
    ResponseBody = case is_binary(Response) of
        true -> Response;
        false -> jiffy:encode(Response)
    end,
    {ResponseBody, Req, State}.

%%====================================================================
%% Response Builders
%%====================================================================

%% @private
build_json_response(#state{metrics_type = undefined}) ->
    %% Get all metrics
    {ok, AllMetrics} = yawl_metrics:get_all_metrics(),
    AllMetrics#{
        timestamp => erlang:system_time(millisecond),
        uptime => get_uptime()
    };

build_json_response(#state{metrics_type = <<"workflows">>}) ->
    {ok, WorkflowMetrics} = yawl_metrics:get_workflow_metrics(),
    #{
        metrics_type => workflows,
        metrics => WorkflowMetrics,
        timestamp => erlang:system_time(millisecond)
    };

build_json_response(#state{metrics_type = <<"services">>}) ->
    {ok, ServiceMetrics} = yawl_metrics:get_service_metrics(),
    #{
        metrics_type => services,
        metrics => ServiceMetrics,
        timestamp => erlang:system_time(millisecond)
    };

build_json_response(#state{metrics_type = <<"resources">>}) ->
    {ok, ResourceMetrics} = yawl_metrics:get_resource_metrics(),
    #{
        metrics_type => resources,
        metrics => ResourceMetrics,
        timestamp => erlang:system_time(millisecond)
    };

build_json_response(#state{metrics_type = <<"health">>}) ->
    %% System health summary
    {ok, Services} = yawl_service_registry:list_services(),
    {ok, WorkflowMetrics} = yawl_metrics:get_workflow_metrics(),

    %% Calculate health stats
    ActiveServices = lists:filter(fun(S) ->
        maps:get(status, S, active) =:= active
    end, Services),

    TotalExecutions = lists:foldl(fun(W, Acc) ->
        Acc + maps:get(total_executions, W, 0)
    end, 0, WorkflowMetrics),

    SuccessRate = case TotalExecutions of
        0 -> 1.0;
        _ ->
            Successful = lists:foldl(fun(W, Acc) ->
                Acc + maps:get(successful_executions, W, 0)
            end, 0, WorkflowMetrics),
            Successful / TotalExecutions
    end,

    #{
        status => case {ActiveServices, SuccessRate} of
            {[], _} -> unhealthy;
            {_, Rate} when Rate < 0.5 -> degraded;
            _ -> healthy
        end,
        services => #{
            total => length(Services),
            active => length(ActiveServices),
            inactive => length(Services) - length(ActiveServices)
        },
        workflows => #{
            total_executions => TotalExecutions,
            success_rate => SuccessRate
        },
        system => #{
            uptime => get_uptime(),
            memory => get_memory_usage(),
            processes => erlang:system_info(process_count)
        },
        timestamp => erlang:system_time(millisecond)
    };

build_json_response(#state{metrics_type = Type}) ->
    #{
        error => <<"unknown_metrics_type">>,
        metrics_type => Type
    }.

%% @private
build_prometheus_response(#state{metrics_type = undefined}) ->
    %% Export all metrics in Prometheus format
    yawl_metrics:export_prometheus();

build_prometheus_response(#state{metrics_type = <<"health">>}) ->
    %% Export health metrics in Prometheus format
    HealthJson = build_json_response(#state{metrics_type = <<"health">>}),

    StatusValue = case maps:get(status, HealthJson, healthy) of
        healthy -> 1;
        degraded -> 0.5;
        unhealthy -> 0
    end,

    ServicesTotal = maps:get(total, maps:get(services, HealthJson, #{}), 0),
    ServicesActive = maps:get(active, maps:get(services, HealthJson, #{}), 0),

    WorkflowExecs = maps:get(total_executions, maps:get(workflows, HealthJson, #{}), 0),
    WorkflowSuccessRate = maps:get(success_rate, maps:get(workflows, HealthJson, #{}), 1.0),

    [
        <<"# YAWL Health Metrics\n">>,
        <<"yawl_health_status ", (float_to_binary(StatusValue, [{decimals, 1}, compact]))/binary, "\n">>,
        <<"yawl_services_total ", (integer_to_binary(ServicesTotal))/binary, "\n">>,
        <<"yawl_services_active ", (integer_to_binary(ServicesActive))/binary, "\n">>,
        <<"yawl_workflow_executions_total ", (integer_to_binary(WorkflowExecs))/binary, "\n">>,
        <<"yawl_workflow_success_rate ", (float_to_binary(WorkflowSuccessRate, [{decimals, 3}, compact]))/binary, "\n">>,
        <<"yawl_system_uptime_ms ", (integer_to_binary(get_uptime()))/binary, "\n">>,
        <<"yawl_system_memory_mb ", (integer_to_binary(get_memory_usage()))/binary, "\n">>,
        <<"yawl_system_processes ", (integer_to_binary(erlang:system_info(process_count)))/binary, "\n">>
    ];

build_prometheus_response(#state{metrics_type = Type}) ->
    %% For specific metric types, convert JSON to Prometheus format
    JsonMetrics = build_json_response(#state{metrics_type = Type}),
    metrics_map_to_prometheus(JsonMetrics, Type).

%% @private
metrics_map_to_prometheus(#{metrics := Metrics}, MetricsType) when is_list(Metrics) ->
    Lines = lists:map(fun(Metric) ->
        maps_to_prometheus_lines(Metric, MetricsType)
    end, Metrics),
    iolist_to_binary(lists:join(<<"\n">>, lists:flatten(Lines))).

%% @private
maps_to_prometheus_lines(Metric, <<"workflows">>) ->
    WorkflowId = maps:get(workflow_id, Metric, <<"unknown">>),
    PatternType = maps:get(pattern_type, Metric, unknown),
    TotalExec = maps:get(total_executions, Metric, 0),
    SuccessExec = maps:get(successful_executions, Metric, 0),
    FailedExec = maps:get(failed_executions, Metric, 0),
    AvgTime = maps:get(avg_execution_time, Metric, 0.0),

    [
        <<"yawl_workflow_executions_total{workflow_id=\"", WorkflowId/binary,
          "\",pattern=\"", (atom_to_binary(PatternType, utf8))/binary,
          "\"} ", (integer_to_binary(TotalExec))/binary>>,
        <<"yawl_workflow_executions_successful{workflow_id=\"", WorkflowId/binary,
          "\"} ", (integer_to_binary(SuccessExec))/binary>>,
        <<"yawl_workflow_executions_failed{workflow_id=\"", WorkflowId/binary,
          "\"} ", (integer_to_binary(FailedExec))/binary>>,
        <<"yawl_workflow_duration_avg{workflow_id=\"", WorkflowId/binary,
          "\"} ", (float_to_binary(AvgTime, [{decimals, 2}, compact]))/binary>>
    ];

maps_to_prometheus_lines(Metric, <<"services">>) ->
    ServiceName = maps:get(service_name, Metric, <<"unknown">>),
    ServiceType = maps:get(service_type, Metric, unknown),
    TotalCalls = maps:get(total_calls, Metric, 0),
    SuccessCalls = maps:get(successful_calls, Metric, 0),
    AvgResponse = maps:get(avg_response_time, Metric, 0.0),
    SuccessRate = maps:get(success_rate, Metric, 1.0),

    [
        <<"yawl_service_calls_total{service=\"", ServiceName/binary,
          "\",type=\"", (atom_to_binary(ServiceType, utf8))/binary,
          "\"} ", (integer_to_binary(TotalCalls))/binary>>,
        <<"yawl_service_calls_successful{service=\"", ServiceName/binary,
          "\"} ", (integer_to_binary(SuccessCalls))/binary>>,
        <<"yawl_service_duration_avg{service=\"", ServiceName/binary,
          "\"} ", (float_to_binary(AvgResponse, [{decimals, 2}, compact]))/binary>>,
        <<"yawl_service_success_rate{service=\"", ServiceName/binary,
          "\"} ", (float_to_binary(SuccessRate, [{decimals, 3}, compact]))/binary>>
    ];

maps_to_prometheus_lines(Metric, <<"resources">>) ->
    ResourceId = maps:get(resource_id, Metric, <<"unknown">>),
    ResourceType = maps:get(resource_type, Metric, unknown),
    TotalAlloc = maps:get(total_allocations, Metric, 0),
    CurrentAlloc = maps:get(current_allocations, Metric, 0),
    PeakAlloc = maps:get(peak_allocations, Metric, 0),

    [
        <<"yawl_resource_allocations_total{resource=\"", ResourceId/binary,
          "\",type=\"", (atom_to_binary(ResourceType, utf8))/binary,
          "\"} ", (integer_to_binary(TotalAlloc))/binary>>,
        <<"yawl_resource_allocations_current{resource=\"", ResourceId/binary,
          "\"} ", (integer_to_binary(CurrentAlloc))/binary>>,
        <<"yawl_resource_allocations_peak{resource=\"", ResourceId/binary,
          "\"} ", (integer_to_binary(PeakAlloc))/binary>>
    ].

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
get_uptime() ->
    case application:get_key(a2a_erl, start_time) of
        {ok, StartTime} ->
            erlang:monotonic_time(millisecond) - StartTime;
        undefined ->
            %% Fallback to system time
            case application:which_applications() of
                [] -> 0;
                Apps ->
                    case lists:keyfind(a2a_erl, 1, Apps) of
                        {a2a_erl, _, _} ->
                            %% Approximate uptime from process info
                            0;
                        _ ->
                            0
                    end
            end
    end.

%% @private
get_memory_usage() ->
    Memory = erlang:memory(total),
    %% Convert bytes to megabytes
    Memory div (1024 * 1024).

%% @private
response_json(Req, StatusCode, Body) ->
    EncodedBody = jiffy:encode(Body),
    cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, EncodedBody, Req).

%% @private
to_binary(Term) when is_binary(Term) -> Term;
to_binary(Term) when is_atom(Term) -> atom_to_binary(Term, utf8);
to_binary(Term) when is_list(Term) -> list_to_binary(Term);
to_binary(Term) -> io_lib:format("~p", [Term]).
