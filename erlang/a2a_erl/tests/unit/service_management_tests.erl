%%%-------------------------------------------------------------------
%%% @doc
%%% Service Management Unit Tests (Chicago-Style TDD)
%%%
%%% These tests are written FIRST (before implementation) following
%%% Chicago-School TDD principles. Tests SHOULD fail initially,
%%% then drive the implementation to make them pass.
%%%
%%% Test Categories:
%%% 1. Start/Stop Services
%%% 2. Supervision Tree Verification
%%% 3. Process Registration
%%% 4. Service Discovery
%%% 5. Lifecycle Events
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(service_management_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(SERVICE_TIMEOUT, 5000).
-define(TEST_SERVICE_NAME, <<"test_service">>).
-define(TEST_SERVICE_TYPE, workflow_engine).

%%====================================================================
%% Test Fixtures
%%====================================================================

%% @doc Setup before each test - starts all YAWL services
setup_all_services() ->
    %% Start Mnesia first
    application:stop(mnesia),
    mnesia:delete_schema([node()]),
    {ok, _} = yawl_persistence:create_schema(),
    {ok, _} = yawl_persistence:create_tables(),
    {ok, _} = yawl_persistence:wait_for_tables(),

    %% Start all YAWL services
    {ok, OrchPid} = yawl_orchestrator:start_link(),
    {ok, PersistPid} = yawl_persistence:start_link(),
    {ok, ResourcePid} = yawl_resource_manager:start_link(),
    {ok, RegistryPid} = yawl_service_registry:start_link(),

    #{
        orchestrator => OrchPid,
        persistence => PersistPid,
        resource_manager => ResourcePid,
        service_registry => RegistryPid
    }.

%% @doc Teardown after each test
cleanup_all_services(#{orchestrator := OrchPid,
                       persistence := PersistPid,
                       resource_manager := ResourcePid,
                       service_registry := RegistryPid}) ->
    gen_server:stop(OrchPid),
    gen_server:stop(PersistPid),
    gen_server:stop(ResourcePid),
    gen_server:stop(RegistryPid),
    mnesia:stop(),
    ok.

%%====================================================================
%% Start/Stop Service Tests
%%====================================================================

start_stop_service_test_() ->
    {"Start orchestrator service",
     fun test_start_orchestrator_service/0},
    {"Stop orchestrator service",
     fun test_stop_orchestrator_service/0},
    {"Start persistence service",
     fun test_start_persistence_service/0},
    {"Stop persistence service",
     fun test_stop_persistence_service/0},
    {"Start resource manager service",
     fun test_start_resource_manager_service/0},
    {"Start service registry",
     fun test_start_service_registry/0},
    {"Start all services in sequence",
     fun test_start_all_services_sequence/0},
    {"Stop all services in sequence",
     fun test_stop_all_services_sequence/0}.

%% @doc FAILING TEST: Start orchestrator service
%% This test SHOULD fail before implementation is complete
test_start_orchestrator_service() ->
    %% Arrange & Act
    Result = yawl_orchestrator:start_link(),

    %% Assert - Test drives the requirement
    ?assertMatch({ok, Pid} when is_pid(Pid), Result),

    %% Cleanup
    {ok, Pid} = Result,
    gen_server:stop(Pid).

%% @doc FAILING TEST: Stop orchestrator service gracefully
test_stop_orchestrator_service() ->
    %% Arrange
    {ok, Pid} = yawl_orchestrator:start_link(),

    %% Act
    Result = gen_server:stop(Pid),

    %% Assert - Service should stop gracefully
    ?assertEqual(ok, Result),

    %% Verify process is truly dead
    ?assertNot(is_process_alive(Pid)).

%% @doc FAILING TEST: Start persistence service
test_start_persistence_service() ->
    %% Setup Mnesia
    application:stop(mnesia),
    mnesia:delete_schema([node()]),
    {ok, _} = yawl_persistence:create_schema(),

    %% Act
    Result = yawl_persistence:start_link(),

    %% Assert
    ?assertMatch({ok, Pid} when is_pid(Pid), Result),

    %% Cleanup
    {ok, Pid} = Result,
    gen_server:stop(Pid),
    mnesia:stop().

%% @doc FAILING TEST: Stop persistence service
test_stop_persistence_service() ->
    %% Setup
    application:stop(mnesia),
    mnesia:delete_schema([node()]),
    {ok, _} = yawl_persistence:create_schema(),
    {ok, Pid} = yawl_persistence:start_link(),

    %% Act
    Result = gen_server:stop(Pid),

    %% Assert
    ?assertEqual(ok, Result),
    ?assertNot(is_process_alive(Pid)),

    %% Cleanup
    mnesia:stop().

%% @doc FAILING TEST: Start resource manager service
test_start_resource_manager_service() ->
    %% Act
    Result = yawl_resource_manager:start_link(),

    %% Assert
    ?assertMatch({ok, Pid} when is_pid(Pid), Result),

    %% Cleanup
    {ok, Pid} = Result,
    gen_server:stop(Pid).

%% @doc FAILING TEST: Start service registry
test_start_service_registry() ->
    %% Act
    Result = yawl_service_registry:start_link(),

    %% Assert
    ?assertMatch({ok, Pid} when is_pid(Pid), Result),

    %% Cleanup
    {ok, Pid} = Result,
    gen_server:stop(Pid).

%% @doc FAILING TEST: Start all services in correct order
test_start_all_services_sequence() ->
    %% Arrange
    application:stop(mnesia),
    mnesia:delete_schema([node()]),

    %% Act - Start in dependency order
    {ok, _} = yawl_persistence:create_schema(),
    {ok, _} = yawl_persistence:create_tables(),
    {ok, _} = yawl_persistence:wait_for_tables(),

    {ok, PersistPid} = yawl_persistence:start_link(),
    {ok, OrchPid} = yawl_orchestrator:start_link(),
    {ok, ResPid} = yawl_resource_manager:start_link(),
    {ok, RegPid} = yawl_service_registry:start_link(),

    %% Assert - All should be alive
    ?assert(is_process_alive(PersistPid)),
    ?assert(is_process_alive(OrchPid)),
    ?assert(is_process_alive(ResPid)),
    ?assert(is_process_alive(RegPid)),

    %% Cleanup
    gen_server:stop(OrchPid),
    gen_server:stop(PersistPid),
    gen_server:stop(ResPid),
    gen_server:stop(RegPid),
    mnesia:stop().

%% @doc FAILING TEST: Stop all services in reverse order
test_stop_all_services_sequence() ->
    %% Setup
    application:stop(mnesia),
    mnesia:delete_schema([node()]),
    {ok, _} = yawl_persistence:create_schema(),
    {ok, _} = yawl_persistence:create_tables(),
    {ok, _} = yawl_persistence:wait_for_tables(),

    {ok, PersistPid} = yawl_persistence:start_link(),
    {ok, OrchPid} = yawl_orchestrator:start_link(),
    {ok, ResPid} = yawl_resource_manager:start_link(),
    {ok, RegPid} = yawl_service_registry:start_link(),

    %% Act - Stop in reverse dependency order
    ok = gen_server:stop(RegPid),
    ok = gen_server:stop(ResPid),
    ok = gen_server:stop(OrchPid),
    ok = gen_server:stop(PersistPid),

    %% Assert - All should be stopped
    ?assertNot(is_process_alive(RegPid)),
    ?assertNot(is_process_alive(ResPid)),
    ?assertNot(is_process_alive(OrchPid)),
    ?assertNot(is_process_alive(PersistPid)),

    %% Cleanup
    mnesia:stop().

%%====================================================================
%% Supervision Tree Tests
%%====================================================================

supervision_tree_test_() ->
    {"Verify supervisor exists",
     fun test_supervisor_exists/0},
    {"Verify orchestrator is supervised",
     fun test_orchestrator_supervised/0},
    {"Verify persistence is supervised",
     fun test_persistence_supervised/0},
    {"Verify resource manager is supervised",
     fun test_resource_manager_supervised/0},
    {"Verify service registry is supervised",
     fun test_service_registry_supervised/0},
    {"Test auto-restart on crash",
     fun test_auto_restart_on_crash/0},
    {"Test supervisor shutdown propagation",
     fun test_supervisor_shutdown_propagation/0}.

%% @doc FAILING TEST: Verify main supervisor exists
test_supervisor_exists() ->
    %% Act
    Result = whereis(a2a_erl_sup),

    %% Assert - Main supervisor should be registered
    ?assertNotEqual(undefined, Result),
    ?assert(is_process_alive(Result)).

%% @doc FAILING TEST: Verify orchestrator is under supervision
test_orchestrator_supervised() ->
    %% Arrange
    {ok, SupPid} = ensure_supervisor_started(),

    %% Act - Find orchestrator under supervisor
    Children = supervisor:which_children(a2a_erl_sup),

    %% Assert - Orchestrator should be a child
    OrchChild = lists:keyfind(yawl_orchestrator, 1, Children),
    ?assertNotEqual(false, OrchChild),
    {yawl_orchestrator, OrchPid, worker, [yawl_orchestrator]} = OrchChild,
    ?assert(is_process_alive(OrchPid)).

%% @doc FAILING TEST: Verify persistence is under supervision
test_persistence_supervised() ->
    %% Arrange
    {ok, _} = ensure_supervisor_started(),

    %% Act
    Children = supervisor:which_children(a2a_erl_sup),

    %% Assert
    PersistChild = lists:keyfind(yawl_persistence, 1, Children),
    ?assertNotEqual(false, PersistChild),
    {yawl_persistence, PersistPid, worker, [yawl_persistence]} = PersistChild,
    ?assert(is_process_alive(PersistPid)).

%% @doc FAILING TEST: Verify resource manager is under supervision
test_resource_manager_supervised() ->
    %% Arrange
    {ok, _} = ensure_supervisor_started(),

    %% Act
    Children = supervisor:which_children(a2a_erl_sup),

    %% Assert
    ResourceChild = lists:keyfind(yawl_resource_manager, 1, Children),
    ?assertNotEqual(false, ResourceChild),
    {yawl_resource_manager, ResourcePid, worker, [yawl_resource_manager]} = ResourceChild,
    ?assert(is_process_alive(ResourcePid)).

%% @doc FAILING TEST: Verify service registry is under supervision
test_service_registry_supervised() ->
    %% Arrange
    {ok, _} = ensure_supervisor_started(),

    %% Act
    Children = supervisor:which_children(a2a_erl_sup),

    %% Assert
    RegistryChild = lists:keyfind(yawl_service_registry, 1, Children),
    ?assertNotEqual(false, RegistryChild),
    {yawl_service_registry, RegistryPid, worker, [yawl_service_registry]} = RegistryChild,
    ?assert(is_process_alive(RegistryPid)).

%% @doc FAILING TEST: Test auto-restart on crash
test_auto_restart_on_crash() ->
    %% Arrange
    {ok, _} = ensure_supervisor_started(),
    Children = supervisor:which_children(a2a_erl_sup),
    {yawl_orchestrator, OrigPid, _, _} = lists:keyfind(yawl_orchestrator, 1, Children),

    %% Act - Kill the orchestrator
    exit(OrigPid, kill),

    %% Wait for restart
    timer:sleep(100),

    %% Assert - Should be restarted with new PID
    NewChildren = supervisor:which_children(a2a_erl_sup),
    {yawl_orchestrator, NewPid, _, _} = lists:keyfind(yawl_orchestrator, 1, NewChildren),
    ?assertNotEqual(OrigPid, NewPid),
    ?assert(is_process_alive(NewPid)).

%% @doc FAILING TEST: Test supervisor shutdown propagates to children
test_supervisor_shutdown_propagation() ->
    %% Arrange
    {ok, SupPid} = ensure_supervisor_started(),
    Children = supervisor:which_children(a2a_erl_sup),

    %% Get child PIDs
    ChildPids = [Pid || {_, Pid, _, _} <- Children, is_pid(Pid)],

    %% Act - Stop supervisor
    ok = supervisor:stop(SupPid),

    %% Assert - All children should be stopped
    timer:sleep(100),
    ?assertNot(lists:any(fun is_process_alive/1, ChildPids)).

%%====================================================================
%% Process Registration Tests
%%====================================================================

process_registration_test_() ->
    {"Orchestrator registered locally",
     fun test_orchestrator_registered/0},
    {"Persistence registered locally",
     fun test_persistence_registered/0},
    {"Resource manager registered locally",
     fun test_resource_manager_registered/0},
    {"Service registry registered locally",
     fun test_service_registry_registered/0},
    {"Workflow instance supervisor registered",
     fun test_workflow_instance_sup_registered/0},
    {"No duplicate registrations",
     fun test_no_duplicate_registrations/0},
    {"Registered processes respond to calls",
     fun test_registered_responsive/0}.

%% @doc FAILING TEST: Orchestrator registered with local name
test_orchestrator_registered() ->
    %% Arrange & Act
    Result = whereis(yawl_orchestrator),

    %% Assert
    ?assertNotEqual(undefined, Result),
    ?assert(is_process_alive(Result)).

%% @doc FAILING TEST: Persistence registered with local name
test_persistence_registered() ->
    %% Arrange & Act
    Result = whereis(yawl_persistence),

    %% Assert
    ?assertNotEqual(undefined, Result),
    ?assert(is_process_alive(Result)).

%% @doc FAILING TEST: Resource manager registered with local name
test_resource_manager_registered() ->
    %% Arrange & Act
    Result = whereis(yawl_resource_manager),

    %% Assert
    ?assertNotEqual(undefined, Result),
    ?assert(is_process_alive(Result)).

%% @doc FAILING TEST: Service registry registered with local name
test_service_registry_registered() ->
    %% Arrange & Act
    Result = whereis(yawl_service_registry),

    %% Assert
    ?assertNotEqual(undefined, Result),
    ?assert(is_process_alive(Result)).

%% @doc FAILING TEST: Workflow instance supervisor registered
test_workflow_instance_sup_registered() ->
    %% Arrange & Act
    Result = whereis(yawl_workflow_instance_sup),

    %% Assert
    ?assertNotEqual(undefined, Result),
    ?assert(is_process_alive(Result)).

%% @doc FAILING TEST: No duplicate registrations allowed
test_no_duplicate_registrations() ->
    %% Arrange - First registration
    {ok, Pid1} = yawl_orchestrator:start_link(),

    %% Act - Try to register again
    Result = yawl_orchestrator:start_link(),

    %% Assert - Should fail or return existing PID
    case Result of
        {ok, Pid1} -> ok;  % Same PID returned
        {error, {already_started, Pid1}} -> ok;  % Already started error
        _ -> ?assert(false, "Duplicate registration should fail")
    end,

    %% Cleanup
    gen_server:stop(Pid1).

%% @doc FAILING TEST: Registered processes respond to calls
test_registered_responsive() ->
    %% Arrange
    Pids = [
        {yawl_orchestrator, fun() -> yawl_orchestrator:list_patterns() end},
        {yawl_persistence, fun() -> yawl_persistence:list_workflows() end},
        {yawl_resource_manager, fun() -> yawl_resource_manager:list_resources() end},
        {yawl_service_registry, fun() -> yawl_service_registry:list_services() end}
    ],

    %% Act & Assert - All should respond
    lists:foreach(fun({Name, CallFun}) ->
        Pid = whereis(Name),
        ?assertNotEqual(undefined, Pid),
        Result = try CallFun() catch _:_ -> {error, no_response} end,
        ?assertNotEqual({error, no_response}, Result,
                       io_lib:format("~s should respond to calls", [Name]))
    end, Pids).

%%====================================================================
%% Service Discovery Tests
%%====================================================================

service_discovery_test_() ->
    {"Discover all registered services",
     fun test_discover_all_services/0},
    {"Discover service by type",
     fun test_discover_by_type/0},
    {"Discover service by capability",
     fun test_discover_by_capability/0},
    {"Service health check",
     fun test_service_health_check/0},
    {"Non-existent service returns error",
     fun test_discover_nonexistent_service/0}.

%% @doc FAILING TEST: Discover all registered services
test_discover_all_services() ->
    %% Arrange
    {ok, _} = ensure_all_services_started(),

    %% Act
    {ok, Services} = yawl_service_registry:list_services(),

    %% Assert - Should have at least core services
    ?assert(length(Services) >= 4).

%% @doc FAILING TEST: Discover service by type
test_discover_by_type() ->
    %% Arrange
    {ok, _} = ensure_all_services_started(),
    ok = yawl_service_registry:register_service(
        <<"test_workflow">>, workflow_engine, <<"http://localhost:8080">>, #{}),

    %% Act
    {ok, Services} = yawl_service_registry:discover_service_by_type(workflow_engine),

    %% Assert
    ?assert(length(Services) > 0).

%% @doc FAILING TEST: Discover service by capability
test_discover_by_capability() ->
    %% Arrange
    {ok, _} = ensure_all_services_started(),
    {ok, _} = yawl_resource_manager:register_resource(
        <<"test_resource">>, human, #{capabilities => [approval, review]}),

    %% Act
    {ok, Resources} = yawl_resource_manager:find_resources_by_capability(approval),

    %% Assert
    ?assert(length(Resources) > 0).

%% @doc FAILING TEST: Service health check
test_service_health_check() ->
    %% Arrange
    {ok, _} = ensure_all_services_started(),

    %% Act - Check health of each service
    OrchHealth = check_process_health(yawl_orchestrator),
    PersistHealth = check_process_health(yawl_persistence),
    ResHealth = check_process_health(yawl_resource_manager),
    RegHealth = check_process_health(yawl_service_registry),

    %% Assert - All should be healthy
    ?assertEqual(healthy, OrchHealth),
    ?assertEqual(healthy, PersistHealth),
    ?assertEqual(healthy, ResHealth),
    ?assertEqual(healthy, RegHealth).

%% @doc FAILING TEST: Non-existent service returns error
test_discover_nonexistent_service() ->
    %% Arrange
    {ok, _} = ensure_all_services_started(),

    %% Act
    Result = yawl_service_registry:discover_service(<<"nonexistent_service">>),

    %% Assert
    ?assertEqual({error, service_not_found}, Result).

%%====================================================================
%% Lifecycle Event Tests
%%====================================================================

lifecycle_event_test_() ->
    {"Service started event",
     fun test_service_started_event/0},
    {"Service stopped event",
     fun test_service_stopped_event/0},
    {"Service crashed event",
     fun test_service_crashed_event/0},
    {"Service restarted event",
     fun test_service_restarted_event/0},
    {"Subscribe to lifecycle events",
     fun test_subscribe_lifecycle_events/0}.

%% @doc FAILING TEST: Service started event is emitted
test_service_started_event() ->
    %% Arrange
    Self = self(),
    {ok, _} = ensure_supervisor_started(),

    %% Act - Start a service and listen for event
    %% (In real implementation, this would subscribe to events)
    {ok, Pid} = yawl_orchestrator:start_link(),

    %% Assert - Event should be emitted
    receive
        {service_started, yawl_orchestrator, Pid} -> ok
    after 500 ->
        ?assert(false, "Service started event not received")
    end,

    %% Cleanup
    gen_server:stop(Pid).

%% @doc FAILING TEST: Service stopped event is emitted
test_service_stopped_event() ->
    %% Arrange
    {ok, Pid} = yawl_orchestrator:start_link(),

    %% Act
    gen_server:stop(Pid),

    %% Assert
    receive
        {service_stopped, yawl_orchestrator, Pid} -> ok
    after 500 ->
        ?assert(false, "Service stopped event not received")
    end.

%% @doc FAILING TEST: Service crashed event is emitted
test_service_crashed_event() ->
    %% Arrange
    {ok, Pid} = yawl_orchestrator:start_link(),

    %% Act - Kill the service
    exit(Pid, brutal_kill),

    %% Assert
    receive
        {service_crashed, yawl_orchestrator, Pid, _Reason} -> ok
    after 500 ->
        ?assert(false, "Service crashed event not received")
    end.

%% @doc FAILING TEST: Service restarted event is emitted
test_service_restarted_event() ->
    %% Arrange
    {ok, OldPid} = yawl_orchestrator:start_link(),

    %% Act - Kill and wait for restart
    exit(OldPid, kill),
    timer:sleep(100),

    %% Assert
    receive
        {service_restarted, yawl_orchestrator, OldPid, NewPid} when is_pid(NewPid) -> ok
    after 500 ->
        ?assert(false, "Service restarted event not received")
    end.

%% @doc FAILING TEST: Subscribe to lifecycle events
test_subscribe_lifecycle_events() ->
    %% Arrange
    Self = self(),
    {ok, _} = ensure_supervisor_started(),

    %% Act - Subscribe to events
    ok = subscribe_to_lifecycle_events(Self),

    %% Trigger an event
    {ok, Pid} = yawl_orchestrator:start_link(),
    gen_server:stop(Pid),

    %% Assert - Should receive events
    Started = receive
        {service_started, _, _} -> true
    after 100 -> false
    end,
    Stopped = receive
        {service_stopped, _, _} -> true
    after 100 -> false
    end,

    ?assert(Started),
    ?assert(Stopped).

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
ensure_supervisor_started() ->
    case whereis(a2a_erl_sup) of
        undefined ->
            {ok, _} = application:ensure_all_started(a2a_erl),
            {ok, whereis(a2a_erl_sup)};
        Pid when is_pid(Pid) ->
            {ok, Pid}
    end.

%% @private
ensure_all_services_started() ->
    {ok, _} = ensure_supervisor_started(),

    %% Ensure Mnesia is ready
    case mnesia:system_info(is_running) of
        true -> ok;
        false ->
            mnesia:delete_schema([node()]),
            {ok, _} = yawl_persistence:create_schema(),
            {ok, _} = yawl_persistence:create_tables(),
            {ok, _} = yawl_persistence:wait_for_tables()
    end,

    %% Ensure all services are running
    case whereis(yawl_orchestrator) of
        undefined -> {ok, _} = yawl_orchestrator:start_link();
        _ -> ok
    end,

    case whereis(yawl_resource_manager) of
        undefined -> {ok, _} = yawl_resource_manager:start_link();
        _ -> ok
    end,

    case whereis(yawl_service_registry) of
        undefined -> {ok, _} = yawl_service_registry:start_link();
        _ -> ok
    end,

    {ok, all_services_started}.

%% @private
check_process_health(ProcessName) ->
    case whereis(ProcessName) of
        undefined -> unhealthy;
        Pid when is_pid(Pid) ->
            case is_process_alive(Pid) of
                true -> healthy;
                false -> unhealthy
            end
    end.

%% @private
subscribe_to_lifecycle_events(SubscriberPid) ->
    %% This would be implemented by the service registry
    ok.
