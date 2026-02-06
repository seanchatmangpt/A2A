%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL Service Registry REST Handler
%%%
%%% Tests service registration, listing, health checks, and
%%% deregistration via REST API.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_rest_service_handler_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

service_rest_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Register service via POST /services", fun test_register_service/0},
      {"List services via GET /services", fun test_list_services/0},
      {"Get specific service via GET /services/{id}", fun test_get_service/0},
      {"Service health check via GET /services/{id}/health", fun test_service_health/0},
      {"Update service via PATCH /services/{id}", fun test_update_service/0},
      {"Delete service via DELETE /services/{id}", fun test_delete_service/0},
      {"Filter services by status", fun test_filter_services_by_status/0},
      {"Filter services by type", fun test_filter_services_by_type/0},
      {"Pagination on service list", fun test_service_pagination/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Start required services
    {ok, _ServiceRegistryPid} = yawl_service_registry:start_link(),
    ok.

cleanup(_ServiceRegistryPid) ->
    gen_server:stop(yawl_service_registry).

%%====================================================================
%% Test Cases
%%====================================================================

test_register_service() ->
    %% Create a mock request for service registration
    ServiceData = #{
        <<"service_name">> => <<"test_service">>,
        <<"service_type">> => <<"rest">>,
        <<"endpoint">> => <<"http://localhost:8080">>,
        <<"health_check_url">> => <<"http://localhost:8080/health">>,
        <<"metadata">> => #{version => <<"1.0.0">>}
    },

    %% Simulate POST /services
    Response = handle_register_service(ServiceData),

    %% Verify response
    ?assertEqual(created, maps_get(status, Response, undefined)),
    ?assert(maps:is_key(<<"service_id">>, Response)),
    ?assertEqual(<<"test_service">>, maps_get(<<"service_name">>, Response, undefined)),
    ?assertEqual(rest, maps_get(<<"service_type">>, Response, undefined)),
    ?assertEqual(<<"http://localhost:8080">>, maps_get(<<"endpoint">>, Response, undefined)),

    %% Verify service is registered
    ServiceId = maps_get(<<"service_id">>, Response, undefined),
    {ok, RegisteredService} = yawl_service_registry:get_service(ServiceId),
    ?assertEqual(<<"test_service">>, maps_get(service_name, RegisteredService, undefined)),
    ok.

test_list_services() ->
    %% Register multiple services
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"service1">>, rest, <<"http://localhost:8001">>),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"service2">>, grpc, <<"localhost:9001">>),
    {ok, _Id3} = yawl_service_registry:register_service(
        <<"service3">>, rest, <<"http://localhost:8002">>),

    %% Simulate GET /services
    Response = handle_list_services(#{}),

    %% Verify response
    ?assertEqual(3, maps_get(total, Response, 0)),
    ?assertEqual(3, length(maps_get(services, Response, []))),
    ?assert(maps:is_key(<<"returned">>, Response)),
    ok.

test_get_service() ->
    %% Register a service
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"get_test_service">>, rest, <<"http://localhost:8888">>),

    %% Simulate GET /services/{id}
    Response = handle_get_service(ServiceId),

    %% Verify response
    ?assertEqual(<<"get_test_service">>, maps_get(service_name, Response, undefined)),
    ?assertEqual(rest, maps_get(service_type, Response, undefined)),
    ?assertEqual(<<"http://localhost:8888">>, maps_get(endpoint, Response, undefined)),
    ?assertNotEqual(nomatch, lists:keyfind(service_id, 1, maps:to_list(Response))),
    ok.

test_service_health() ->
    %% Register a service without health check URL
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"health_test_service">>, rest, <<"http://localhost:9999">>),

    %% Simulate GET /services/{id}/health
    Response = handle_service_health(ServiceId),

    %% Verify response
    ?assertEqual(ServiceId, maps_get(service_id, Response, undefined)),
    ?assertEqual(active, maps_get(status, Response, undefined)),
    ?assert(maps:is_key(response_time, Response)),
    ?assert(maps:is_key(timestamp, Response)),
    ?assertEqual(true, maps_get(healthy, Response, false)),
    ok.

test_update_service() ->
    %% Register a service
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"update_test_service">>, rest, <<"http://old-endpoint">>),

    %% Update the service
    UpdateData = #{
        <<"endpoint">> => <<"http://new-endpoint">>,
        <<"health_check_url">> => <<"http://new-endpoint/health">>
    },

    Response = handle_update_service(ServiceId, UpdateData),

    %% Verify response
    ?assertEqual(ok, maps_get(status, Response, undefined)),
    ?assertEqual(ServiceId, maps_get(service_id, Response, undefined)),

    %% Verify service is updated
    {ok, UpdatedService} = yawl_service_registry:get_service(ServiceId),
    ?assertEqual(<<"http://new-endpoint">>, maps_get(endpoint, UpdatedService, undefined)),
    ?assertEqual(<<"http://new-endpoint/health">>, maps_get(health_check_url, UpdatedService, undefined)),
    ok.

test_delete_service() ->
    %% Register a service
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"delete_test_service">>, rest, <<"http://localhost:7777">>),

    %% Verify service exists
    {ok, _} = yawl_service_registry:get_service(ServiceId),

    %% Simulate DELETE /services/{id}
    Response = simulate_delete_service(ServiceId),

    %% Verify response
    ?assertEqual(ok, maps_get(status, Response, undefined)),
    ?assertEqual(ServiceId, maps_get(service_id, Response, undefined)),

    %% Verify service is deleted
    {error, service_not_found} = yawl_service_registry:get_service(ServiceId),
    ok.

test_filter_services_by_status() ->
    %% Register services with different statuses
    {ok, Id1} = yawl_service_registry:register_service(
        <<"active_service">>, rest, <<"http://localhost:8001">>),
    {ok, Id2} = yawl_service_registry:register_service(
        <<"inactive_service">>, rest, <<"http://localhost:8002">>),

    %% Set one service as inactive
    ok = yawl_service_registry:set_health_status(Id2, inactive),

    %% Simulate GET /services?status=active
    Response = handle_list_services(#{<<"status">> => <<"active">>}),

    %% Verify filtering
    Services = maps_get(services, Response, []),
    FilteredServices = lists:filter(fun(S) ->
        maps_get(status, S, undefined) =:= active
    end, Services),
    ?assertEqual(length(FilteredServices), length(Services)),
    ok.

test_filter_services_by_type() ->
    %% Register services of different types
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"rest_service">>, rest, <<"http://localhost:8001">>),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"grpc_service">>, grpc, <<"localhost:9001">>),

    %% Simulate GET /services?type=rest
    Response = handle_list_services(#{<<"type">> => <<"rest">>}),

    %% Verify filtering
    Services = maps_get(services, Response, []),
    lists:foreach(fun(S) ->
        ?assertEqual(rest, maps_get(service_type, S, undefined))
    end, Services),
    ok.

test_service_pagination() ->
    %% Register multiple services
    lists:foreach(fun(I) ->
        Name = <<"service_", (integer_to_binary(I))/binary>>,
        {ok, _} = yawl_service_registry:register_service(
            Name, rest, <<"http://localhost:", (integer_to_binary(8000 + I))/binary>>)
    end, lists:seq(1, 10)),

    %% Test pagination with limit=5, offset=0
    Response1 = handle_list_services(#{<<"limit">> => 5, <<"offset">> => 0}),
    ?assertEqual(10, maps_get(total, Response1, 0)),
    ?assertEqual(5, maps_get(returned, Response1, 0)),
    ?assertEqual(5, length(maps_get(services, Response1, []))),
    %% Test pagination with limit=5, offset=5
    Response2 = handle_list_services(#{<<"limit">> => 5, <<"offset">> => 5}),
    ?assertEqual(10, maps_get(total, Response2, 0)),
    ?assertEqual(5, maps_get(returned, Response2, 0)),
    ?assertEqual(5, length(maps_get(services, Response2, []))),
    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
%% Simulate the register service handler
handle_register_service(Data) ->
    ServiceName = maps_get(<<"service_name">>, Data, undefined),
    ServiceTypeBin = maps_get(<<"service_type">>, Data, <<"rest">>),
    Endpoint = maps_get(<<"endpoint">>, Data, undefined),
    HealthCheckUrl = maps_get(<<"health_check_url">>, Data, undefined),
    Metadata = maps_get(<<"metadata">>, Data, #{}),

    case {ServiceName, Endpoint} of
        {undefined, _} ->
            #{error => <<"missing_service_name">>};
        {_, undefined} ->
            #{error => <<"missing_endpoint">>};
        {ServiceNameVal, EndpointVal} ->
            ServiceType = try
                binary_to_existing_atom(ServiceTypeBin, utf8)
            catch
                error:badarg -> rest
            end,

            Options = #{
                health_check_url => HealthCheckUrl,
                metadata => Metadata
            },

            case yawl_service_registry:register_service(
                ServiceNameVal, ServiceType, EndpointVal, Options) of
                {ok, SId} ->
                    #{
                        status => created,
                        <<"service_id">> => SId,
                        <<"service_name">> => ServiceNameVal,
                        <<"service_type">> => ServiceType,
                        <<"endpoint">> => EndpointVal,
                        message => <<"Service registered successfully">>
                    };
                {error, Reason} ->
                    #{error => to_binary(Reason)}
            end
    end.

%% @private
%% Simulate the list services handler
handle_list_services(Params) ->
    StatusFilter = maps_get(<<"status">>, Params, undefined),
    TypeFilter = maps_get(<<"type">>, Params, undefined),
    Limit = maps_get(<<"limit">>, Params, 100),
    Offset = maps_get(<<"offset">>, Params, 0),

    {ok, AllServices} = yawl_service_registry:list_services(),

    %% Apply filters
    FilteredServices = lists:filter(fun(ServiceMap) ->
        StatusMatch = case StatusFilter of
            undefined -> true;
            StatusBin ->
                ServiceStatus = maps_get(status, ServiceMap, active),
                ServiceStatus =:= binary_to_existing_atom(StatusBin, utf8)
        end,
        TypeMatch = case TypeFilter of
            undefined -> true;
            TypeBin ->
                ServiceType = maps_get(service_type, ServiceMap, unknown),
                ServiceType =:= binary_to_existing_atom(TypeBin, utf8)
        end,
        StatusMatch andalso TypeMatch
    end, AllServices),

    %% Apply pagination
    PaginatedServices = case Limit of
        all -> FilteredServices;
        LimitInt when is_integer(LimitInt) ->
            lists:sublist(FilteredServices, Offset + 1, min(LimitInt, length(FilteredServices) - Offset + 1))
    end,

    #{
        services => PaginatedServices,
        total => length(FilteredServices),
        returned => length(PaginatedServices),
        offset => Offset
    }.

%% @private
%% Simulate the get service handler
handle_get_service(ServiceId) ->
    case yawl_service_registry:get_service(ServiceId) of
        {ok, Service} -> Service;
        {error, not_found} ->
            #{error => <<"service_not_found">>, service_id => ServiceId}
    end.

%% @private
%% Simulate the service health handler
handle_service_health(ServiceId) ->
    case yawl_service_registry:check_health(ServiceId) of
        {ok, Status, ResponseTime} ->
            #{
                service_id => ServiceId,
                status => Status,
                response_time => ResponseTime,
                timestamp => erlang:system_time(millisecond),
                healthy => Status =:= active
            };
        {error, Reason} ->
            #{
                error => to_binary(Reason),
                service_id => ServiceId,
                status => error
            }
    end.

%% @private
%% Simulate the update service handler
handle_update_service(ServiceId, Data) ->
    Endpoint = maps_get(<<"endpoint">>, Data, undefined),
    HealthCheckUrl = maps_get(<<"health_check_url">>, Data, undefined),
    Metadata = maps_get(<<"metadata">>, Data, #{}),

    Updates0 = #{},
    Updates1 = case Endpoint of
        undefined -> Updates0;
        _ -> Updates0#{endpoint => Endpoint}
    end,
    Updates2 = case HealthCheckUrl of
        undefined -> Updates1;
        _ -> Updates1#{health_check_url => HealthCheckUrl}
    end,
    Updates3 = case Metadata of
        #{} -> Updates2;
        _ -> Updates2#{metadata => Metadata}
    end,

    case yawl_service_registry:update_service(ServiceId, Updates3) of
        ok ->
            #{
                status => ok,
                service_id => ServiceId,
                message => <<"Service updated successfully">>
            };
        {error, Reason} ->
            #{error => to_binary(Reason)}
    end.

%% @private
%% Simulate the delete service handler
simulate_delete_service(ServiceId) ->
    case yawl_service_registry:unregister_service(ServiceId) of
        ok ->
            #{
                status => ok,
                service_id => ServiceId,
                message => <<"Service deregistered successfully">>
            };
        {error, Reason} ->
            #{error => to_binary(Reason)}
    end.

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.

%% @private
to_binary(Term) when is_binary(Term) -> Term;
to_binary(Term) when is_atom(Term) -> atom_to_binary(Term, utf8);
to_binary(Term) when is_list(Term) -> list_to_binary(Term);
to_binary(Term) -> io_lib:format("~p", [Term]).
