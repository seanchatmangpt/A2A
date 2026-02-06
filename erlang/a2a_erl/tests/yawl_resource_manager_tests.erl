%%%-------------------------------------------------------------------
%%% @doc
%%% Unit Tests for YAWL Resource Manager
%%%
%%% Tests resource registration, allocation, and management.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_resource_manager_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

-ifdef(PROPER).
-include_lib("proper/include/proper.hrl").
-endif.

%%====================================================================
%% Test Fixtures
%%====================================================================

resource_manager_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Register and retrieve resource", fun test_register_resource/0},
      {"Allocate resource to work item", fun test_allocate_resource/0},
      {"List resources by type", fun test_list_by_type/0},
      {"Resource capability management", fun test_capabilities/0},
      {"Update resource status", fun test_update_status/0},
      {"Release resource allocation", fun test_release_resource/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    {ok, Pid} = yawl_resource_manager:start_link(),
    Pid.

cleanup(_Pid) ->
    gen_server:stop(yawl_resource_manager).

%%====================================================================
%% Test Cases
%%====================================================================

test_register_resource() ->
    ResourceName = <<"test_service">>,
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        ResourceName, service, #{max_capacity => 5}),
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(service, maps:get(resource_type, Resource)),
    ?assertEqual(<<"test_service">>, maps:get(name, Resource)),
    ?assertEqual(5, maps:get(max_capacity, Resource)),
    ok.

test_allocate_resource() ->
    %% Register a resource
    ResourceName = <<"allocation_test_service">>,
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        ResourceName, service, #{max_capacity => 2, capabilities => [task1]}),

    %% Allocate it
    WorkitemId = <<"$workitem_1">>,
    {ok, AllocatedId, Resource} = yawl_resource_manager:allocate_resource(WorkitemId, [task1]),
    ?assertEqual(ResourceId, AllocatedId),
    ?assertEqual(1, maps:get(current_load, Resource)),
    ok.

test_list_by_type() ->
    %% Register multiple resources of same type
    {ok, _} = yawl_resource_manager:register_resource(<<"service1">>, service, #{}),
    {ok, _} = yawl_resource_manager:register_resource(<<"service2">>, service, #{}),
    {ok, _} = yawl_resource_manager:register_resource(<<"human1">>, human, #{}),

    {ok, Services} = yawl_resource_manager:list_resources_by_type(service),
    ?assertEqual(2, length(Services)),

    {ok, Humans} = yawl_resource_manager:list_resources_by_type(human),
    ?assertEqual(1, length(Humans)),
    ok.

test_capabilities() ->
    %% Register resource with capabilities
    ResourceName = <<"capable_service">>,
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        ResourceName, service, #{capabilities => [task1, task2]}),

    %% Add capability
    ?assertEqual(ok, yawl_resource_manager:add_capability(ResourceId, task3)),

    %% Find by capability
    {ok, Resources} = yawl_resource_manager:find_resources_by_capability(task3),
    ?assertEqual(1, length(Resources)),

    %% Remove capability
    ?assertEqual(ok, yawl_resource_manager:remove_capability(ResourceId, task3)),
    ok.

test_update_status() ->
    ResourceName = <<"status_service">>,
    {ok, ResourceId} = yawl_resource_manager:register_resource(ResourceName, service, #{}),

    %% Update to busy
    ?assertEqual(ok, yawl_resource_manager:update_resource_status(ResourceId, busy)),
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(busy, maps:get(status, Resource)),
    ok.

test_release_resource() ->
    %% Register and allocate
    ResourceName = <<"release_service">>,
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        ResourceName, service, #{max_capacity => 1}),
    WorkitemId = <<"$workitem_release">>,
    {ok, _, _} = yawl_resource_manager:allocate_resource(WorkitemId, [task1]),

    %% Release
    ?assertEqual(ok, yawl_resource_manager:release_resource(WorkitemId)),
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(0, maps:get(current_load, Resource)),
    ok.

%%====================================================================
%% Property-Based Tests
%%====================================================================

-ifdef(PROPER).
prop_resource_allocation() ->
    ?FORALL({NumResources, NumWorkitems},
        {nat(), nat()},
        begin
            Resources = lists:map(fun(I) ->
                Name = <<"res_", (integer_to_binary(I))/binary>>,
                {ok, Id} = yawl_resource_manager:register_resource(
                    Name, service, #{capabilities => [task]}),
                Id
            end, lists:seq(1, min(NumResources, 10))),

            Workitems = lists:map(fun(I) ->
                <<"$wi_", (integer_to_binary(I))/binary>>
            end, lists:seq(1, min(NumWorkitems, 20))),

            %% Allocate resources
            Allocated = lists:map(fun(Wi) ->
                case yawl_resource_manager:allocate_resource(Wi, [task]) of
                    {ok, _, _} -> true;
                    {error, _} -> false
                end
            end, Workitems),

            %% All workitems should either be allocated or fail gracefully
            lists:all(fun(R) -> R =:= true orelse R =:= false end, Allocated)
        end).
-endif.
