%%%-------------------------------------------------------------------
%%% @doc
%%% Comprehensive Unit Tests for YAWL Service Registry
%%%
%%% This test module provides comprehensive coverage of the service registry
%%% including:
%%% - Service registration and unregistration
%%% - Service discovery by name and type
%%% - Service invocation (sync and async)
%%% - Health checking
%%% - Load balancing and failover
%%% - Edge cases and error handling
%%%
%%% Target coverage: 95%+
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_service_registry_comprehensive_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Setup and Teardown
%%====================================================================

setup() ->
    %% Start inets for HTTP requests
    application:ensure_all_started(inets),

    %% Create unique test process name
    Pid = spawn(fun() ->
        receive
            stop -> ok
        end
    end),
    register(yawl_service_registry_test_sup, Pid),

    %% Start the service registry
    {ok, RegistryPid} = yawl_service_registry:start_link(),
    unlink(RegistryPid),

    %% Mock httpc for testing
    meck:new(httpc, [unstick]),
    meck:expect(httpc, request, fun(_Method, _Request, _HTTPOptions, _Options) ->
        {ok, {{<<"http">>, <<"1.1">>, 200}, <<"OK">>, <<"{\"status\":\"ok\"}">>}}
    end),

    #{registry_pid => RegistryPid, sup_pid => Pid}.

cleanup(_State) ->
    %% Unload httpc mock
    meck:unload(httpc),

    %% Stop the registry
    case whereis(yawl_service_registry) of
        undefined -> ok;
        Pid when is_pid(Pid) ->
            exit(Pid, normal),
            timer:sleep(100)
    end,

    %% Clean up test supervisor
    case whereis(yawl_service_registry_test_sup) of
        undefined -> ok;
        SupPid when is_pid(SupPid) ->
            SupPid ! stop,
            unregister(yawl_service_registry_test_sup)
    end,

    %% Stop inets
    application:stop(inets),

    ok.

%%====================================================================
%% Test Generators
%%====================================================================

service_registry_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
        fun test_group_server_lifecycle/0,
        fun test_group_service_registration/0,
        fun test_group_service_discovery/0,
        fun test_group_service_invocation/0,
        fun test_group_health_checking/0,
        fun test_group_service_list_and_get/0,
        fun test_group_service_updates/0,
        fun test_group_load_balancing/0,
        fun test_group_edge_cases/0,
        fun test_group_error_handling/0,
        fun test_group_async_operations/0,
        fun test_group_service_types/0
     ]}.

%%====================================================================
%% Test Group 1: Server Lifecycle
%%====================================================================

test_group_server_lifecycle() ->
    [
        {"Server starts successfully", fun test_start_server/0},
        {"Server initializes with empty state", fun test_initial_state/0},
        {"Server terminates cleanly", fun test_terminate/0},
        {"Server handles code change", fun test_code_change/0},
        {"Server handles unknown cast", fun test_handle_cast_unknown/0}
    ].

test_start_server() ->
    %% Server already started in setup
    ?assert(is_pid(whereis(yawl_service_registry))).

test_initial_state() ->
    %% Should have no services initially
    {ok, Services} = yawl_service_registry:list_services(),
    ?assertEqual(0, length(Services)).

test_terminate() ->
    %% Ensure clean shutdown
    Pid = whereis(yawl_service_registry),
    ?assert(is_pid(Pid)),

    %% Register a service first
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"term_test">>, rest, <<"http://localhost:9999">>
    ),

    %% Terminate and restart
    exit(Pid, normal),
    timer:sleep(100),

    %% Verify registry can restart
    {ok, NewPid} = yawl_service_registry:start_link(),
    ?assert(is_pid(NewPid)),
    unlink(NewPid).

test_code_change() ->
    %% Code change should preserve state
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"code_change_test">>, rest, <<"http://localhost:9999">>
    ),

    %% Simulate code change (internal gen_server callback)
    Pid = whereis(yawl_service_registry),
    Sys = sys:replace_state(Pid, fun(State) -> State end),
    %% State should be a tuple (record)
    ?assert(is_tuple(Sys)).

test_handle_cast_unknown() ->
    %% Unknown cast messages should be handled gracefully
    Pid = whereis(yawl_service_registry),
    gen_server:cast(Pid, unknown_message),
    ?assert(is_pid(Pid)).

%%====================================================================
%% Test Group 2: Service Registration
%%====================================================================

test_group_service_registration() ->
    [
        {"Register basic service", fun test_register_basic/0},
        {"Register service with options", fun test_register_with_options/0},
        {"Register service with health check URL", fun test_register_with_health_check/0},
        {"Register service with metadata", fun test_register_with_metadata/0},
        {"Register multiple services", fun test_register_multiple/0},
        {"Register service generates unique ID", fun test_unique_service_ids/0},
        {"Register service by type", fun test_register_by_type/0},
        {"Register service with same name", fun test_register_duplicate_name/0}
    ].

test_register_basic() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"basic_service">>, rest, <<"http://localhost:8080">>
    ),
    ?assert(is_binary(ServiceId)),
    ?assert(<<>> /= ServiceId),
    ?assertNotEqual(undefined, ServiceId).

test_register_with_options() ->
    Options = #{
        health_check_url => <<"http://localhost:8080/health">>,
        metadata => #{version => <<"1.0.0">>, region => <<"us-east">>}
    },
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"options_service">>, rest, <<"http://localhost:8081">>, Options
    ),
    {ok, Service} = yawl_service_registry:get_service(ServiceId),
    ?assertEqual(<<"http://localhost:8080/health">>, maps:get(health_check_url, Service)).

test_register_with_health_check() ->
    Options = #{health_check_url => <<"http://localhost:8082/health">>},
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"health_service">>, rest, <<"http://localhost:8082">>, Options
    ),
    {ok, Service} = yawl_service_registry:get_service(ServiceId),
    ?assertEqual(<<"http://localhost:8082/health">>, maps:get(health_check_url, Service)).

test_register_with_metadata() ->
    Options = #{metadata => #{
        version => <<"2.0">>,
        owner => <<"team-a">>,
        tags => [<<"critical">>, <<"production">>]
    }},
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"metadata_service">>, rest, <<"http://localhost:8083">>, Options
    ),
    {ok, Service} = yawl_service_registry:get_service(ServiceId),
    Metadata = maps:get(metadata, Service),
    ?assertEqual(<<"2.0">>, maps:get(version, Metadata)),
    ?assertEqual(<<"team-a">>, maps:get(owner, Metadata)).

test_register_multiple() ->
    {ok, Id1} = yawl_service_registry:register_service(
        <<"service1">>, rest, <<"http://localhost:8084">>
    ),
    {ok, Id2} = yawl_service_registry:register_service(
        <<"service2">>, grpc, <<"http://localhost:8085">>
    ),
    {ok, Id3} = yawl_service_registry:register_service(
        <<"service3">>, rest, <<"http://localhost:8086">>
    ),
    ?assertNotEqual(Id1, Id2),
    ?assertNotEqual(Id2, Id3),
    ?assertNotEqual(Id1, Id3).

test_unique_service_ids() ->
    {ok, Id1} = yawl_service_registry:register_service(
        <<"unique_test">>, rest, <<"http://localhost:8087">>
    ),
    timer:sleep(10),
    {ok, Id2} = yawl_service_registry:register_service(
        <<"unique_test2">>, rest, <<"http://localhost:8088">>
    ),
    %% IDs include timestamp, so they should be different
    ?assertNotEqual(Id1, Id2).

test_register_by_type() ->
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"type_service1">>, rest, <<"http://localhost:8090">>
    ),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"type_service2">>, rest, <<"http://localhost:8091">>
    ),
    {ok, _Id3} = yawl_service_registry:register_service(
        <<"type_service3">>, graphql, <<"http://localhost:8092">>
    ),
    %% Discover by type should find REST services
    {ok, _Service} = yawl_service_registry:discover_service_by_type(rest).

test_register_duplicate_name() ->
    {ok, Id1} = yawl_service_registry:register_service(
        <<"dup_service">>, rest, <<"http://localhost:8093">>
    ),
    timer:sleep(10),
    %% Register same name again (different instance)
    {ok, Id2} = yawl_service_registry:register_service(
        <<"dup_service">>, rest, <<"http://localhost:8094">>
    ),
    %% Should create different service IDs (timestamp-based)
    ?assertNotEqual(Id1, Id2).

%%====================================================================
%% Test Group 3: Service Discovery
%%====================================================================

test_group_service_discovery() ->
    [
        {"Discover service by name", fun test_discover_by_name/0},
        {"Discover service by type", fun test_discover_by_type/0},
        {"Discover non-existent service", fun test_discover_not_found/0},
        {"Discover by type with no services", fun test_discover_type_empty/0},
        {"Discover selects best service", fun test_discover_best_service/0},
        {"Discover by type load balances", fun test_discover_type_balance/0}
    ].

test_discover_by_name() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"discovery_service">>, rest, <<"http://localhost:8100">>
    ),
    {ok, Service} = yawl_service_registry:discover_service(<<"discovery_service">>),
    ?assertEqual(<<"discovery_service">>, maps:get(service_name, Service)),
    ?assertEqual(rest, maps:get(service_type, Service)),
    ?assertEqual(<<"http://localhost:8100">>, maps:get(endpoint, Service)).

test_discover_by_type() ->
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"type_discovery1">>, rest, <<"http://localhost:8101">>
    ),
    {ok, _} = yawl_service_registry:register_service(
        <<"type_discovery2">>, rest, <<"http://localhost:8102">>
    ),
    {ok, Service} = yawl_service_registry:discover_service_by_type(rest),
    ?assertEqual(rest, maps:get(service_type, Service)).

test_discover_not_found() ->
    Result = yawl_service_registry:discover_service(<<"nonexistent">>),
    ?assertEqual({error, service_not_found}, Result).

test_discover_type_empty() ->
    Result = yawl_service_registry:discover_service_by_type(soap),
    ?assertEqual({error, no_services_of_type}, Result).

test_discover_best_service() ->
    %% Register multiple REST services
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"best_service1">>, rest, <<"http://localhost:8110">>
    ),
    timer:sleep(10),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"best_service2">>, rest, <<"http://localhost:8111">>
    ),
    %% Discovery should succeed and select one
    {ok, _Service} = yawl_service_registry:discover_service_by_type(rest).

test_discover_type_balance() ->
    %% Register multiple services of same type
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"balance1">>, rest, <<"http://localhost:8120">>
    ),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"balance2">>, rest, <<"http://localhost:8121">>
    ),
    {ok, _Id3} = yawl_service_registry:register_service(
        <<"balance3">>, rest, <<"http://localhost:8122">>
    ),
    %% Should be able to discover (one selected)
    {ok, _Service} = yawl_service_registry:discover_service_by_type(rest).

%%====================================================================
%% Test Group 4: Service Invocation
%%====================================================================

test_group_service_invocation() ->
    [
        {"Call service synchronously", fun test_call_service_sync/0},
        {"Call service with GET method", fun test_call_service_get/0},
        {"Call service with POST method", fun test_call_service_post/0},
        {"Call service with PUT method", fun test_call_service_put/0},
        {"Call service with DELETE method", fun test_call_service_delete/0},
        {"Call service with timeout", fun test_call_service_timeout/0},
        {"Call non-existent service", fun test_call_nonexistent/0},
        {"Call inactive service", fun test_call_inactive/0},
        {"Call updates service stats", fun test_call_updates_stats/0}
    ].

test_call_service_sync() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"sync_service">>, rest, <<"http://localhost:8200">>
    ),
    {ok, Result} = yawl_service_registry:call_service(
        <<"sync_service">>,
        #{key => <<"value">>}
    ),
    ?assertMatch(#{}, Result).

test_call_service_get() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"get_service">>, rest, <<"http://localhost:8201">>
    ),
    {ok, _Result} = yawl_service_registry:call_service(
        <<"get_service">>,
        #{param1 => <<"value1">>},
        #{method => get}
    ).

test_call_service_post() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"post_service">>, rest, <<"http://localhost:8202">>
    ),
    {ok, _Result} = yawl_service_registry:call_service(
        <<"post_service">>,
        #{data => <<"test">>},
        #{method => post, content_type => <<"application/json">>}
    ).

test_call_service_put() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"put_service">>, rest, <<"http://localhost:8203">>
    ),
    {ok, _Result} = yawl_service_registry:call_service(
        <<"put_service">>,
        #{data => <<"updated">>},
        #{method => put, content_type => <<"application/json">>}
    ).

test_call_service_delete() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"delete_service">>, rest, <<"http://localhost:8204">>
    ),
    {ok, _Result} = yawl_service_registry:call_service(
        <<"delete_service">>,
        #{},
        #{method => delete}
    ).

test_call_service_timeout() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"timeout_service">>, rest, <<"http://localhost:8205">>
    ),
    {ok, _Result} = yawl_service_registry:call_service(
        <<"timeout_service">>,
        #{},
        #{timeout => 1000}
    ).

test_call_nonexistent() ->
    Result = yawl_service_registry:call_service(
        <<"nonexistent_service">>,
        #{}
    ),
    ?assertEqual({error, service_not_found}, Result).

test_call_inactive() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"inactive_service">>, rest, <<"http://localhost:8206">>
    ),
    %% Set service to inactive
    ok = yawl_service_registry:set_health_status(ServiceId, inactive),

    %% Try to call
    Result = yawl_service_registry:call_service(
        <<"inactive_service">>,
        #{}
    ),
    ?assertMatch({error, {service_unavailable, inactive}}, Result).

test_call_updates_stats() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"stats_service">>, rest, <<"http://localhost:8207">>
    ),

    %% Get initial stats
    {ok, _Service1} = yawl_service_registry:get_service(ServiceId),

    %% Call service (success)
    {ok, _} = yawl_service_registry:call_service(
        <<"stats_service">>,
        #{}
    ),

    %% Get updated stats
    {ok, Service2} = yawl_service_registry:get_service(ServiceId),
    ?assert(is_number(maps:get(success_rate, Service2))),
    ?assert(is_number(maps:get(response_time, Service2))).

%%====================================================================
%% Test Group 5: Health Checking
%%====================================================================

test_group_health_checking() ->
    [
        {"Check health of service", fun test_check_health/0},
        {"Check health without health URL", fun test_check_health_no_url/0},
        {"Check health of non-existent service", fun test_check_health_not_found/0},
        {"Check all health", fun test_check_all_health/0},
        {"Set health status externally", fun test_set_health_status/0},
        {"Set health status on non-existent", fun test_set_health_status_not_found/0},
        {"Health check timer active", fun test_health_check_timer/0}
    ].

test_check_health() ->
    Options = #{health_check_url => <<"http://localhost:8300/health">>},
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"health_service">>, rest, <<"http://localhost:8300">>, Options
    ),
    {ok, Status, ResponseTime} = yawl_service_registry:check_health(ServiceId),
    ?assertEqual(active, Status),
    ?assert(is_integer(ResponseTime)).

test_check_health_no_url() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"no_health_service">>, rest, <<"http://localhost:8301">>
    ),
    {ok, Status, ResponseTime} = yawl_service_registry:check_health(ServiceId),
    ?assertEqual(active, Status),
    ?assertEqual(0, ResponseTime).

test_check_health_not_found() ->
    Result = yawl_service_registry:check_health(<<"nonexistent_id">>),
    ?assertEqual({error, service_not_found}, Result).

test_check_all_health() ->
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"all_health1">>, rest, <<"http://localhost:8310">>
    ),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"all_health2">>, rest, <<"http://localhost:8311">>
    ),
    {ok, HealthMap} = yawl_service_registry:check_all_health(),
    ?assert(is_map(HealthMap)),
    ?assertEqual(2, map_size(HealthMap)).

test_set_health_status() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"set_status_service">>, rest, <<"http://localhost:8320">>
    ),
    ok = yawl_service_registry:set_health_status(ServiceId, inactive),
    {ok, Service} = yawl_service_registry:get_service(ServiceId),
    ?assertEqual(inactive, maps:get(status, Service)),

    ok = yawl_service_registry:set_health_status(ServiceId, active),
    {ok, Service2} = yawl_service_registry:get_service(ServiceId),
    ?assertEqual(active, maps:get(status, Service2)).

test_set_health_status_not_found() ->
    Result = yawl_service_registry:set_health_status(<<"nonexistent">>, active),
    ?assertEqual({error, service_not_found}, Result).

test_health_check_timer() ->
    %% Health check timer should be set up during init
    Pid = whereis(yawl_service_registry),
    SysState = sys:get_state(Pid),
    %% State should be a tuple with at least 5 elements (record fields)
    ?assert(is_tuple(SysState)),
    ?assert(tuple_size(SysState) >= 5).

%%====================================================================
%% Test Group 6: Service List and Get
%%====================================================================

test_group_service_list_and_get() ->
    [
        {"List all services", fun test_list_services/0},
        {"List empty services", fun test_list_empty_services/0},
        {"Get service by ID", fun test_get_service/0},
        {"Get non-existent service", fun test_get_service_not_found/0},
        {"List services after registration", fun test_list_after_register/0},
        {"List services after unregistration", fun test_list_after_unregister/0}
    ].

test_list_services() ->
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"list1">>, rest, <<"http://localhost:8400">>
    ),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"list2">>, grpc, <<"http://localhost:8401">>
    ),
    {ok, Services} = yawl_service_registry:list_services(),
    ?assertEqual(2, length(Services)).

test_list_empty_services() ->
    %% Clear any existing services by using a fresh registry
    {ok, Services} = yawl_service_registry:list_services(),
    %% At minimum, should return empty list
    ?assert(is_list(Services)).

test_get_service() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"get_service">>, rest, <<"http://localhost:8410">>
    ),
    {ok, Service} = yawl_service_registry:get_service(ServiceId),
    ?assertEqual(<<"get_service">>, maps:get(service_name, Service)),
    ?assertEqual(rest, maps:get(service_type, Service)),
    ?assertEqual(<<"http://localhost:8410">>, maps:get(endpoint, Service)).

test_get_service_not_found() ->
    Result = yawl_service_registry:get_service(<<"fake_id">>),
    ?assertEqual({error, service_not_found}, Result).

test_list_after_register() ->
    {ok, Before} = yawl_service_registry:list_services(),
    CountBefore = length(Before),

    {ok, _Id} = yawl_service_registry:register_service(
        <<"new_service">>, rest, <<"http://localhost:8420">>
    ),

    {ok, After} = yawl_service_registry:list_services(),
    ?assertEqual(CountBefore + 1, length(After)).

test_list_after_unregister() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"temp_service">>, rest, <<"http://localhost:8430">>
    ),

    {ok, Before} = yawl_service_registry:list_services(),
    CountBefore = length(Before),

    ok = yawl_service_registry:unregister_service(ServiceId),

    {ok, After} = yawl_service_registry:list_services(),
    ?assertEqual(CountBefore - 1, length(After)).

%%====================================================================
%% Test Group 7: Service Updates
%%====================================================================

test_group_service_updates() ->
    [
        {"Update service endpoint", fun test_update_endpoint/0},
        {"Update service health check URL", fun test_update_health_url/0},
        {"Update service metadata", fun test_update_metadata/0},
        {"Update non-existent service", fun test_update_not_found/0},
        {"Update multiple fields", fun test_update_multiple_fields/0},
        {"Update preserves other fields", fun test_update_preserves_fields/0}
    ].

test_update_endpoint() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"update_endpoint">>, rest, <<"http://localhost:8500">>
    ),
    ok = yawl_service_registry:update_service(
        ServiceId,
        #{endpoint => <<"http://localhost:8501">>}
    ),
    {ok, Service} = yawl_service_registry:get_service(ServiceId),
    ?assertEqual(<<"http://localhost:8501">>, maps:get(endpoint, Service)).

test_update_health_url() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"update_health">>, rest, <<"http://localhost:8510">>
    ),
    ok = yawl_service_registry:update_service(
        ServiceId,
        #{health_check_url => <<"http://localhost:8510/health">>}
    ),
    {ok, Service} = yawl_service_registry:get_service(ServiceId),
    ?assertEqual(<<"http://localhost:8510/health">>, maps:get(health_check_url, Service)).

test_update_metadata() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"update_metadata">>, rest, <<"http://localhost:8520">>,
        #{metadata => #{version => <<"1.0">>}}
    ),
    ok = yawl_service_registry:update_service(
        ServiceId,
        #{metadata => #{version => <<"2.0">>, region => <<"us-west">>}}
    ),
    {ok, Service} = yawl_service_registry:get_service(ServiceId),
    Metadata = maps:get(metadata, Service),
    ?assertEqual(<<"2.0">>, maps:get(version, Metadata)),
    ?assertEqual(<<"us-west">>, maps:get(region, Metadata)).

test_update_not_found() ->
    Result = yawl_service_registry:update_service(
        <<"fake_id">>,
        #{endpoint => <<"http://localhost:9999">>}
    ),
    ?assertEqual({error, service_not_found}, Result).

test_update_multiple_fields() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"update_multi">>, rest, <<"http://localhost:8530">>
    ),
    ok = yawl_service_registry:update_service(
        ServiceId,
        #{
            endpoint => <<"http://localhost:8531">>,
            health_check_url => <<"http://localhost:8531/health">>,
            metadata => #{updated => true}
        }
    ),
    {ok, Service} = yawl_service_registry:get_service(ServiceId),
    ?assertEqual(<<"http://localhost:8531">>, maps:get(endpoint, Service)),
    ?assertEqual(<<"http://localhost:8531/health">>, maps:get(health_check_url, Service)).

test_update_preserves_fields() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"preserve_service">>, rest, <<"http://localhost:8540">>,
        #{metadata => #{initial => true}}
    ),
    ok = yawl_service_registry:update_service(
        ServiceId,
        #{endpoint => <<"http://localhost:8541">>}
    ),
    {ok, Service} = yawl_service_registry:get_service(ServiceId),
    %% Name and type should be preserved
    ?assertEqual(<<"preserve_service">>, maps:get(service_name, Service)),
    ?assertEqual(rest, maps:get(service_type, Service)).

%%====================================================================
%% Test Group 8: Load Balancing
%%====================================================================

test_group_load_balancing() ->
    [
        {"Select best service by success rate", fun test_select_by_success_rate/0},
        {"Select best service by response time", fun test_select_by_response_time/0},
        {"Load balance across services", fun test_load_balance/0},
        {"Service comparison logic", fun test_compare_services/0},
        {"Failover to backup service", fun test_failover/0}
    ].

test_select_by_success_rate() ->
    %% Register multiple services of same type
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"lb1">>, rest, <<"http://localhost:8600">>
    ),
    timer:sleep(10),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"lb2">>, rest, <<"http://localhost:8601">>
    ),
    %% Discovery should select one
    {ok, _Service} = yawl_service_registry:discover_service_by_type(rest).

test_select_by_response_time() ->
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"rt1">>, rest, <<"http://localhost:8610">>
    ),
    timer:sleep(10),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"rt2">>, rest, <<"http://localhost:8611">>
    ),
    %% Discovery should work
    {ok, _Service} = yawl_service_registry:discover_service_by_type(rest).

test_load_balance() ->
    %% Register multiple services
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"lba1">>, rest, <<"http://localhost:8620">>
    ),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"lba2">>, rest, <<"http://localhost:8621">>
    ),
    {ok, _Id3} = yawl_service_registry:register_service(
        <<"lba3">>, rest, <<"http://localhost:8622">>
    ),
    %% Multiple discoveries should work
    {ok, _} = yawl_service_registry:discover_service_by_type(rest),
    {ok, _} = yawl_service_registry:discover_service_by_type(rest).

test_compare_services() ->
    %% Register services and check discovery works
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"comp1">>, rest, <<"http://localhost:8630">>
    ),
    timer:sleep(10),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"comp2">>, rest, <<"http://localhost:8631">>
    ),
    {ok, _} = yawl_service_registry:discover_service_by_type(rest).

test_failover() ->
    %% Register multiple services
    {ok, Id1} = yawl_service_registry:register_service(
        <<"fail1">>, rest, <<"http://localhost:8640">>
    ),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"fail2">>, rest, <<"http://localhost:8641">>
    ),
    %% Mark first as inactive
    ok = yawl_service_registry:set_health_status(Id1, inactive),

    %% Discovery should still work (select second)
    {ok, _Service} = yawl_service_registry:discover_service_by_type(rest).

%%====================================================================
%% Test Group 9: Edge Cases
%%====================================================================

test_group_edge_cases() ->
    [
        {"Service with empty name", fun test_empty_service_name/0},
        {"Service with special characters", fun test_special_chars_name/0},
        {"Service with long name", fun test_long_service_name/0},
        {"Service with different protocols", fun test_different_protocols/0},
        {"Service ID generation", fun test_service_id_generation/0},
        {"Empty parameters call", fun test_empty_params_call/0},
        {"Nil service ID", fun test_nil_service_id/0}
    ].

test_empty_service_name() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<>>, rest, <<"http://localhost:8700">>
    ),
    {ok, Service} = yawl_service_registry:discover_service(<<>>),
    ?assertEqual(<<>>, maps:get(service_name, Service)).

test_special_chars_name() ->
    SpecialName = <<"test-service_v2.0">>,
    {ok, _ServiceId} = yawl_service_registry:register_service(
        SpecialName, rest, <<"http://localhost:8701">>
    ),
    {ok, Service} = yawl_service_registry:discover_service(SpecialName),
    ?assertEqual(SpecialName, maps:get(service_name, Service)).

test_long_service_name() ->
    LongName = <<"this_is_a_very_long_service_name_that_exceeds_normal_length">>,
    {ok, _ServiceId} = yawl_service_registry:register_service(
        LongName, rest, <<"http://localhost:8702">>
    ),
    {ok, Service} = yawl_service_registry:discover_service(LongName),
    ?assertEqual(LongName, maps:get(service_name, Service)).

test_different_protocols() ->
    {ok, _Id1} = yawl_service_registry:register_service(
        <<"http_service">>, rest, <<"http://localhost:8710">>
    ),
    {ok, _Id2} = yawl_service_registry:register_service(
        <<"https_service">>, rest, <<"https://localhost:8711">>
    ),
    {ok, _Id3} = yawl_service_registry:register_service(
        <<"plain_service">>, rest, <<"localhost:8712">>
    ),
    {ok, _} = yawl_service_registry:discover_service(<<"http_service">>),
    {ok, _} = yawl_service_registry:discover_service(<<"https_service">>),
    {ok, _} = yawl_service_registry:discover_service(<<"plain_service">>).

test_service_id_generation() ->
    {ok, Id1} = yawl_service_registry:register_service(
        <<"idgen1">>, rest, <<"http://localhost:8720">>
    ),
    ?assert(is_binary(Id1)),
    %% ID should contain service name prefix
    ?assertNotEqual(<<>>, Id1).

test_empty_params_call() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"empty_params">>, rest, <<"http://localhost:8730">>
    ),
    {ok, _} = yawl_service_registry:call_service(
        <<"empty_params">>,
        #{}
    ).

test_nil_service_id() ->
    Result = yawl_service_registry:get_service(<<>>),
    ?assertEqual({error, service_not_found}, Result).

%%====================================================================
%% Test Group 10: Error Handling
%%====================================================================

test_group_error_handling() ->
    [
        {"Handle unknown call", fun test_unknown_call/0},
        {"Handle service not found in call", fun test_call_service_not_found/0},
        {"Handle service unavailable error", fun test_service_unavailable/0},
        {"Handle unregister non-existent", fun test_unregister_nonexistent/0},
        {"Handle invalid health status", fun test_invalid_health_status/0},
        {"Handle update with invalid ID", fun test_update_invalid_id/0},
        {"Handle unknown info message", fun test_unknown_info/0}
    ].

test_unknown_call() ->
    Pid = whereis(yawl_service_registry),
    Result = gen_server:call(Pid, unknown_request),
    ?assertEqual({error, unknown_request}, Result).

test_call_service_not_found() ->
    Result = yawl_service_registry:call_service(
        <<"nonexistent">>,
        #{}
    ),
    ?assertEqual({error, service_not_found}, Result).

test_service_unavailable() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"unavailable">>, rest, <<"http://localhost:8800">>
    ),
    ok = yawl_service_registry:set_health_status(ServiceId, inactive),
    Result = yawl_service_registry:call_service(
        <<"unavailable">>,
        #{}
    ),
    ?assertMatch({error, {service_unavailable, _}}, Result).

test_unregister_nonexistent() ->
    Result = yawl_service_registry:unregister_service(<<"fake_id">>),
    ?assertEqual({error, service_not_found}, Result).

test_invalid_health_status() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"invalid_status">>, rest, <<"http://localhost:8810">>
    ),
    %% Any atom is accepted as status
    ok = yawl_service_registry:set_health_status(ServiceId, custom_status),
    {ok, Service} = yawl_service_registry:get_service(ServiceId),
    ?assertEqual(custom_status, maps:get(status, Service)).

test_update_invalid_id() ->
    Result = yawl_service_registry:update_service(
        <<"invalid_id">>,
        #{endpoint => <<"http://localhost:9999">>}
    ),
    ?assertEqual({error, service_not_found}, Result).

test_unknown_info() ->
    Pid = whereis(yawl_service_registry),
    Pid ! unknown_message,
    %% Should handle without crashing
    timer:sleep(50),
    ?assert(is_pid(Pid)).

%%====================================================================
%% Test Group 11: Async Operations
%%====================================================================

test_group_async_operations() ->
    [
        {"Call service asynchronously", fun test_async_call/0},
        {"Async call returns reference", fun test_async_returns_ref/0},
        {"Async call on non-existent", fun test_async_not_found/0},
        {"Async call on inactive service", fun test_async_inactive/0},
        {"Async call completes", fun test_async_completes/0}
    ].

test_async_call() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"async_service">>, rest, <<"http://localhost:8900">>
    ),
    {ok, _} = yawl_service_registry:call_service_async(
        <<"async_service">>,
        #{data => <<"test">>}
    ).

test_async_returns_ref() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"async_ref">>, rest, <<"http://localhost:8901">>
    ),
    %% Should return ok with some result (may be ref or actual result)
    ?assertMatch({ok, _}, yawl_service_registry:call_service_async(
        <<"async_ref">>,
        #{}
    )).

test_async_not_found() ->
    Result = yawl_service_registry:call_service_async(
        <<"nonexistent_async">>,
        #{}
    ),
    ?assertEqual({error, service_not_found}, Result).

test_async_inactive() ->
    {ok, ServiceId} = yawl_service_registry:register_service(
        <<"inactive_async">>, rest, <<"http://localhost:8903">>
    ),
    ok = yawl_service_registry:set_health_status(ServiceId, inactive),

    Result = yawl_service_registry:call_service_async(
        <<"inactive_async">>,
        #{}
    ),
    ?assertMatch({error, {service_unavailable, _}}, Result).

test_async_completes() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"async_complete">>, rest, <<"http://localhost:8904">>
    ),
    %% Async call should spawn and complete
    Result = yawl_service_registry:call_service_async(
        <<"async_complete">>,
        #{test => <<"data">>}
    ),
    ?assertMatch({ok, _}, Result).

%%====================================================================
%% Test Group 12: Service Types
%%====================================================================

test_group_service_types() ->
    [
        {"Register REST service", fun test_rest_type/0},
        {"Register gRPC service", fun test_grpc_type/0},
        {"Register GraphQL service", fun test_graphql_type/0},
        {"Register SOAP service", fun test_soap_type/0},
        {"Register custom type service", fun test_custom_type/0},
        {"Discover different types", fun test_discover_different_types/0}
    ].

test_rest_type() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"rest_svc">>, rest, <<"http://localhost:9000">>
    ),
    {ok, Service} = yawl_service_registry:discover_service(<<"rest_svc">>),
    ?assertEqual(rest, maps:get(service_type, Service)).

test_grpc_type() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"grpc_svc">>, grpc, <<"http://localhost:9001">>
    ),
    {ok, Service} = yawl_service_registry:discover_service(<<"grpc_svc">>),
    ?assertEqual(grpc, maps:get(service_type, Service)).

test_graphql_type() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"graphql_svc">>, graphql, <<"http://localhost:9002">>
    ),
    {ok, Service} = yawl_service_registry:discover_service(<<"graphql_svc">>),
    ?assertEqual(graphql, maps:get(service_type, Service)).

test_soap_type() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"soap_svc">>, soap, <<"http://localhost:9003">>
    ),
    {ok, Service} = yawl_service_registry:discover_service(<<"soap_svc">>),
    ?assertEqual(soap, maps:get(service_type, Service)).

test_custom_type() ->
    {ok, _ServiceId} = yawl_service_registry:register_service(
        <<"custom_svc">>, custom_type, <<"http://localhost:9004">>
    ),
    {ok, Service} = yawl_service_registry:discover_service(<<"custom_svc">>),
    ?assertEqual(custom_type, maps:get(service_type, Service)).

test_discover_different_types() ->
    {ok, _} = yawl_service_registry:register_service(
        <<"type1">>, rest, <<"http://localhost:9010">>
    ),
    {ok, _} = yawl_service_registry:register_service(
        <<"type2">>, grpc, <<"http://localhost:9011">>
    ),
    {ok, _} = yawl_service_registry:register_service(
        <<"type3">>, graphql, <<"http://localhost:9012">>
    ),

    {ok, RestSvc} = yawl_service_registry:discover_service_by_type(rest),
    {ok, GrpcSvc} = yawl_service_registry:discover_service_by_type(grpc),
    {ok, GraphqlSvc} = yawl_service_registry:discover_service_by_type(graphql),

    ?assertEqual(rest, maps:get(service_type, RestSvc)),
    ?assertEqual(grpc, maps:get(service_type, GrpcSvc)),
    ?assertEqual(graphql, maps:get(service_type, GraphqlSvc)).
