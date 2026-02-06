%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL Service Registry
%%%
%%% Tests service registration, discovery, and invocation.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_service_registry_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

service_registry_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Register and discover service", fun test_register_discover/0},
      {"List all services", fun test_list_services/0},
      {"Find service by type", fun test_find_by_type/0},
      {"Update service", fun test_update_service/0},
      {"Unregister service", fun test_unregister_service/0},
      {"Health check operations", fun test_health_check/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    {ok, Pid} = yawl_service_registry:start_link(),
    Pid.

cleanup(_Pid) ->
    gen_server:stop(yawl_service_registry).

%%====================================================================
%% Test Cases
%%====================================================================

test_register_discover() ->
    ServiceName = <<"test_service">>,
    {ok, ServiceId} = yawl_service_registry:register_service(
        ServiceName, rest, <<"http://localhost:8080">>),

    {ok, Service} = yawl_service_registry:discover_service(ServiceName),
    ?assertEqual(ServiceName, maps:get(service_name, Service)),
    ?assertEqual(rest, maps:get(service_type, Service)),
    ?assertEqual(<<"http://localhost:8080">>, maps:get(endpoint, Service)),
    ok.

test_list_services() ->
    {ok, _} = yawl_service_registry:register_service(<<"svc1">>, rest, <<"http://localhost:1">>),
    {ok, _} = yawl_service_registry:register_service(<<"svc2">>, rest, <<"http://localhost:2">>),

    {ok, Services} = yawl_service_registry:list_services(),
    ?assertEqual(2, length(Services)),
    ok.

test_find_by_type() ->
    {ok, _} = yawl_service_registry:register_service(<<"rest_svc">>, rest, <<"http://localhost:8080">>),
    {ok, _} = yawl_service_registry:register_service(<<"grpc_svc">>, grpc, <<"localhost:9090">>),

    {ok, RestService} = yawl_service_registry:discover_service_by_type(rest),
    ?assertEqual(rest, maps:get(service_type, RestService)),

    {ok, GrpcService} = yawl_service_registry:discover_service_by_type(grpc),
    ?assertEqual(grpc, maps:get(service_type, GrpcService)),
    ok.

test_update_service() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"update_test">>, rest, <<"http://old-endpoint">>),

    ?assertEqual(ok, yawl_service_registry:update_service(
        ServiceId, #{endpoint => <<"http://new-endpoint">>})),

    {ok, Service} = yawl_service_registry:get_service(ServiceId),
    ?assertEqual(<<"http://new-endpoint">>, maps:get(endpoint, Service)),
    ok.

test_unregister_service() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"temp_service">>, rest, <<"http://temp">>),

    ?assertEqual(ok, yawl_service_registry:unregister_service(ServiceId)),

    {error, service_not_found} = yawl_service_registry:get_service(ServiceId),
    ok.

test_health_check() ->
    %% Register service without health check URL
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"no_health_service">>, rest, <<"http://localhost:9999">>),

    {ok, Status, _Time} = yawl_service_registry:check_health(ServiceId),
    ?assertEqual(active, Status),
    ok.
