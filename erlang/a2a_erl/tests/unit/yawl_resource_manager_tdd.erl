%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Resource Manager TDD Tests (Chicago-Style)
%%%
%%% These tests verify resource allocation, capabilities, and strategies.
%%% Tests are written FIRST to drive the resource manager implementation.
%%%
%%% Test Categories:
%%% 1. Resource Registration
%%% 2. Resource Allocation
%%% 3. Capability Management
%%% 4. Allocation Strategies
%%% 5. Resource Release
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_resource_manager_tdd).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(RESOURCE_TIMEOUT, 5000).
-define(TEST_RESOURCE_NAME, <<"test_resource">>).
-define(TEST_RESOURCE_TYPE, human).
-define(TEST_MAX_CAPACITY, 10).

%%====================================================================
%% Test Fixtures
%%====================================================================

%% @doc Setup for resource manager tests
resource_setup() ->
    %% Start Mnesia
    application:stop(mnesia),
    mnesia:delete_schema([node()]),
    {ok, _} = yawl_persistence:create_schema(),
    {ok, _} = yawl_persistence:create_tables(),
    {ok, _} = yawl_persistence:wait_for_tables(),

    %% Start resource manager
    {ok, Pid} = yawl_resource_manager:start_link(),
    #{pid => Pid}.

%% @doc Teardown for resource manager tests
resource_cleanup(#{pid := Pid}) ->
    gen_server:stop(Pid),
    mnesia:stop().

%%====================================================================
%% Resource Registration Tests
%%====================================================================

resource_registration_test_() ->
    {"Register human resource",
     fun test_register_human_resource/0},
    {"Register service resource",
     fun test_register_service_resource/0},
    {"Register system resource",
     fun test_register_system_resource/0},
    {"Register with capabilities",
     fun test_register_with_capabilities/0},
    {"Register with attributes",
     fun test_register_with_attributes/0},
    {"Register duplicate resource fails",
     fun test_duplicate_registration_fails/0},
    {"Unregister resource",
     fun test_unregister_resource/0},
    {"Get resource by ID",
     fun test_get_resource/0}.

%% @doc FAILING TEST: Register human resource
test_register_human_resource() ->
    %% Arrange
    State = resource_setup(),

    %% Act - Register human resource
    Result = yawl_resource_manager:register_resource(
        <<"john_doe">>, human, #{
            capabilities => [review, approve],
            max_capacity => 5
        }
    ),

    %% Assert
    ?assertMatch({ok, _ResourceId}, Result),
    {ok, ResourceId} = Result,

    %% Verify resource is retrievable
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(<<"john_doe">>, maps:get(name, Resource)),
    ?assertEqual(human, maps:get(resource_type, Resource)),
    ?assertEqual([review, approve], maps:get(capabilities, Resource)),

    %% Cleanup
    resource_cleanup(State).

%% @doc FAILING TEST: Register service resource
test_register_service_resource() ->
    %% Arrange
    State = resource_setup(),

    %% Act - Register service resource
    Result = yawl_resource_manager:register_resource(
        <<"payment_service">>, service, #{
            endpoint => <<"http://localhost:8080">>,
            capabilities => [process_payment],
            max_capacity => 100
        }
    ),

    %% Assert
    ?assertMatch({ok, _ResourceId}, Result),
    {ok, ResourceId} = Result,

    %% Verify
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(<<"http://localhost:8080">>, maps:get(endpoint, Resource)),
    ?assertEqual(service, maps:get(resource_type, Resource)),

    %% Cleanup
    resource_cleanup(State).

%% @doc FAILING TEST: Register system resource
test_register_system_resource() ->
    %% Arrange
    State = resource_setup(),

    %% Act - Register system resource
    Result = yawl_resource_manager:register_resource(
        <<"notification_system">>, system, #{
            capabilities => [send_notification, log_event],
            max_capacity => 1000
        }
    ),

    %% Assert
    ?assertMatch({ok, _ResourceId}, Result),
    {ok, ResourceId} = Result,

    %% Verify
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(system, maps:get(resource_type, Resource)),

    %% Cleanup
    resource_cleanup(State).

%% @doc FAILING TEST: Register with capabilities
test_register_with_capabilities() ->
    %% Arrange
    State = resource_setup(),

    %% Act - Register with multiple capabilities
    Capabilities = [data_analysis, report_generation, email_sending],
    Result = yawl_resource_manager:register_resource(
        <<"analyst_1">>, human, #{
            capabilities => Capabilities,
            max_capacity => 3
        }
    ),

    %% Assert
    ?assertMatch({ok, _ResourceId}, Result),
    {ok, ResourceId} = Result,

    %% Verify all capabilities registered
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    RegisteredCaps = maps:get(capabilities, Resource),
    ?assertEqual(Capabilities, RegisteredCaps),

    %% Cleanup
    resource_cleanup(State).

%% @doc FAILING TEST: Register with attributes
test_register_with_attributes() ->
    %% Arrange
    State = resource_setup(),

    %% Act - Register with attributes
    Attributes = #{
        department => "finance",
        location => "NY",
        skill_level => senior,
        hourly_rate => 100.0
    },
    Result = yawl_resource_manager:register_resource(
        <<"analyst_2">>, human, #{
            capabilities => [review],
            attributes => Attributes
        }
    ),

    %% Assert
    ?assertMatch({ok, _ResourceId}, Result),
    {ok, ResourceId} = Result,

    %% Verify attributes preserved
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(Attributes, maps:get(attributes, Resource)),

    %% Cleanup
    resource_cleanup(State).

%% @doc FAILING TEST: Duplicate registration fails
test_duplicate_registration_fails() ->
    %% Arrange
    State = resource_setup(),

    %% Act - Register same resource twice
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        <<"duplicate_res">>, human, #{}),
    DuplicateResult = yawl_resource_manager:register_resource(
        <<"duplicate_res">>, human, #{}),

    %% Assert - Second registration should fail
    case DuplicateResult of
        {ok, _} ->
            ?assert(false, "Duplicate registration should fail");
        {error, {resource_exists, ResourceId}} ->
            ok;  %% Expected
        {error, _} ->
            ok
    end,

    %% Cleanup
    yawl_resource_manager:unregister_resource(ResourceId),
    resource_cleanup(State).

%% @doc FAILING TEST: Unregister resource
test_unregister_resource() ->
    %% Arrange
    State = resource_setup(),

    %% Register then unregister
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        <<"temp_res">>, human, #{}),
    UnregisterResult = yawl_resource_manager:unregister_resource(ResourceId),

    %% Assert
    ?assertEqual(ok, UnregisterResult),

    %% Resource should not exist after unregister
    Result = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual({error, resource_not_found}, Result),

    %% Cleanup
    resource_cleanup(State).

%% @doc FAILING TEST: Get resource by ID
test_get_resource() ->
    %% Arrange
    State = resource_setup(),

    %% Register resource
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        <<"get_test_res">>, service, #{}),

    %% Act - Get resource
    Result = yawl_resource_manager:get_resource(ResourceId),

    %% Assert
    ?assertMatch({ok, _Resource}, Result),

    %% Get non-existent resource
    NotFoundResult = yawl_resource_manager:get_resource(<<"nonexistent">>),
    ?assertEqual({error, resource_not_found}, NotFoundResult),

    %% Cleanup
    yawl_resource_manager:unregister_resource(ResourceId),
    resource_cleanup(State).

%%====================================================================
%% Resource Allocation Tests
%%====================================================================

resource_allocation_test_() ->
    {"Allocate single resource",
     fun test_allocate_single_resource/0},
    {"Allocate with required capabilities",
     fun test_allocate_with_capabilities/0},
    {"Allocate with specific type",
     fun test_allocate_by_type/0},
    {"Allocate when no available resources",
     fun test_allocate_no_resources/0},
    {"Allocate updates load",
     fun test_allocate_updates_load/0},
    {"Allocate beyond capacity fails",
     fun test_allocate_beyond_capacity/0}.

%% @doc FAILING TEST: Allocate single resource
test_allocate_single_resource() ->
    %% Arrange
    State = resource_setup(),

    %% Register a resource
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        <<"allocator_res">>, human, #{
            capabilities => [allocate],
            max_capacity => 1
        }
    ),

    %% Act - Allocate for workitem
    WorkitemId = <<"workitem_1">>,
    Result = yawl_resource_manager:allocate_resource(WorkitemId, [allocate]),

    %% Assert
    ?assertMatch({ok, ResourceId, _ResourceMap}, Result),

    %% Resource should be marked busy
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(busy, maps:get(status, Resource)),

    %% Cleanup
    yawl_resource_manager:release_resource(WorkitemId),
    yawl_resource_manager:unregister_resource(ResourceId),
    resource_cleanup(State).

%% @doc FAILING TEST: Allocate with required capabilities
test_allocate_with_capabilities() ->
    %% Arrange
    State = resource_setup(),

    %% Register resources with different capabilities
    {ok, _} = yawl_resource_manager:register_resource(
        <<"reviewer1">>, human, #{capabilities => [review]}),
    {ok, _} = yawl_resource_manager:register_resource(
        <<"approver1">>, human, #{capabilities => [approve]}),
    {ok, _} = yawl_resource_manager:register_resource(
        @"multi_task">>, human, #{capabilities => [review, approve]}),

    %% Act - Allocate requiring both capabilities
    WorkitemId = <<"workitem_multi">>,
    Result = yawl_resource_manager:allocate_resource(
        WorkitemId, [review, approve]),

    %% Assert - Should get multi-task resource
    ?assertMatch({ok, MultiTaskId, _}, Result),
    {ok, MultiTaskResource} = yawl_resource_manager:get_resource(MultiTaskId),
    ?assert(lists:member(review, maps:get(capabilities, MultiTaskResource))),
    ?assert(lists:member(approve, maps:get(capabilities, MultiTaskResource)),

    %% Cleanup
    lists:foreach(fun(Id) ->
        yawl_resource_manager:unregister_resource(Id)
    end, [<<"reviewer1">>, <<"approver1">>, <<"multi_task">>]),
    resource_cleanup(State).

%% @doc FAILING TEST: Allocate with specific type
test_allocate_by_type() ->
    %% Arrange
    State = resource_setup(),

    %% Register resources of different types
    {ok, HumanId} = yawl_resource_manager:register_resource(
        <<"human_1">>, human, #{}),
    {ok, ServiceId} = yawl_resource_manager:register_resource(
        <<"service_1">>, service, #{}),
    {ok, SystemId} = yawl_resource_manager:register_resource(
        <<"system_1">>, system, #{}),

    %% Act - Allocate human type specifically
    WorkitemId = <<"workitem_human">>,
    Result = yawl_resource_manager:allocate_resource(
        WorkitemId, human, [task1]),

    %% Assert - Should get human resource
    ?assertMatch({ok, HumanId, _}, Result),

    %% Cleanup
    lists:foreach(fun(Id) ->
        yawl_resource_manager:unregister_resource(Id)
    end, [HumanId, ServiceId, SystemId]),
    resource_cleanup(State).

%% @doc FAILING TEST: Allocate when no available resources
test_allocate_no_resources() ->
    %% Arrange
    State = resource_setup(),

    %% Don't register any resources

    %% Act - Try to allocate
    WorkitemId = <<"workitem_no_res">>,
    Result = yawl_resource_manager:allocate_resource(
        WorkitemId, [task1]),

    %% Assert - Should fail
    ?assertEqual({error, no_available_resources}, Result),

    %% Cleanup
    resource_cleanup(State).

%% @doc FAILING TEST: Allocate updates load
test_allocate_updates_load() ->
    %% Arrange
    State = resource_setup(),

    %% Register resource with capacity 5
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        <<"load_test_res">>, human, #{
            capabilities => [task],
            max_capacity => 5
        }
    ),

    %% Act - Allocate up to capacity
    lists:foreach(fun(N) ->
        WorkitemId = <<"workitem_", (integer_to_binary(N))/binary>>,
        ?assertMatch({ok, ResourceId, _},
            yawl_resource_manager:allocate_resource(WorkitemId, [task]))
    end, lists:seq(1, 5)),

    %% Assert - Resource should be busy after 5 allocations
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    CurrentLoad = maps:get(current_load, Resource),
    ?assertEqual(5, CurrentLoad),
    ?assertEqual(busy, maps:get(status, Resource)),

    %% Next allocation should fail
    Result6 = yawl_resource_manager:allocate_resource(
        <<"workitem_6">>, [task]),
    ?assertEqual({error, no_available_resources}, Result6),

    %% Cleanup
    lists:foreach(fun(N) ->
        WorkitemId = <<"workitem_", (integer_to_binary(N))/binary>>,
        yawl_resource_manager:release_resource(WorkitemId)
    end, lists:seq(1, 5)),
    yawl_resource_manager:unregister_resource(ResourceId),
    resource_cleanup(State).

%% @doc FAILING TEST: Allocate beyond capacity fails
test_allocate_beyond_capacity() ->
    %% Arrange
    State = resource_setup(),

    %% Register resource with capacity 1
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        <<"capacity_1_res">>, human, #{
            capabilities => [single_task],
            max_capacity => 1
        }
    ),

    %% Act - First allocation succeeds
    {ok, ResourceId, _} =
        yawl_resource_manager:allocate_resource(
            <<"workitem_1">>, [single_task]),

    %% Second should fail (capacity exceeded)
    Result2 = yawl_resource_manager:allocate_resource(
        <<"workitem_2">>, [single_task]),
    ?assertEqual({error, no_available_resources}, Result2),

    %% Cleanup
    yawl_resource_manager:release_resource(<<"workitem_1">>),
    yawl_resource_manager:unregister_resource(ResourceId),
    resource_cleanup(State).

%%====================================================================
%% Capability Management Tests
%%====================================================================

capability_management_test_() ->
    {"Add capability to resource",
     fun test_add_capability/0},
    {"Remove capability from resource",
     fun test_remove_capability/0},
    {"Find resources by capability",
     fun test_find_by_capability/0},
    {"Find resources by multiple capabilities",
     fun test_find_by_multiple_capabilities/0},
    {"Capability-based allocation",
     fun test_capability_based_allocation/0}.

%% @doc FAILING TEST: Add capability to resource
test_add_capability() ->
    %% Arrange
    State = resource_setup(),

    %% Register resource without capability
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        <<"capability_res">>, human, #{}),

    %% Act - Add capability
    Result = yawl_resource_manager:add_capability(ResourceId, advanced_analysis),

    %% Assert
    ?assertEqual(ok, Result),

    %% Verify capability was added
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    Capabilities = maps:get(capabilities, Resource),
    ?assert(lists:member(advanced_analysis, Capabilities)),

    %% Cleanup
    yawl_resource_manager:unregister_resource(ResourceId),
    resource_cleanup(State).

%% @doc FAILING TEST: Remove capability from resource
test_remove_capability() ->
    %% Arrange
    State = resource_setup(),

    %% Register resource with capability
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        <<"remove_cap_res">>, human, #{
            capabilities => [cap1, cap2, cap3]
        }
    ),

    %% Act - Remove capability
    Result = yawl_resource_manager:remove_capability(ResourceId, cap2),

    %% Assert
    ?assertEqual(ok, Result),

    %% Verify capability removed
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    Capabilities = maps:get(capabilities, Resource),
    ?assertNotEqual(true, lists:member(cap2, Capabilities)),
    ?assert(lists:member(cap1, Capabilities)),
    ?assert(lists:member(cap3, Capabilities)),

    %% Cleanup
    yawl_resource_manager:unregister_resource(ResourceId),
    resource_cleanup(State).

%% @doc FAILING TEST: Find resources by capability
test_find_by_capability() ->
    %% Arrange
    State = resource_setup(),

    %% Register resources with different capabilities
    lists:foreach(fun({Name, Caps}) ->
        {ok, _} = yawl_resource_manager:register_resource(Name, human, #{
            capabilities => Caps
        })
    end, [
        {<<"res_review">>, [review]},
        {<<"res_approve">>, [approve]},
        {<<"res_multi">>, [review, approve]},
        {<<"res_analyze">>, [analyze, report]}
    ]),

    %% Act - Find by review capability
    {ok, ReviewResources} = yawl_resource_manager:find_resources_by_capability(review),

    %% Assert - Should find res_review and res_multi
    ?assert(length(ReviewResources) >= 2),

    %% Names should contain review resources
    Names = [maps:get(name, R) || R <- ReviewResources],
    ?assert(lists:member(<<"res_review">>, Names)),
    ?assert(lists:member(<<"res_multi">>, Names)),

    %% Cleanup
    lists:foreach(fun({Name, _}) ->
        yawl_resource_manager:unregister_resource(Name)
    end, [
        {<<"res_review">>, _},
        {<<"res_approve">>, _},
        {<<"res_multi">>, _},
        {<<"res_analyze">>, _}
    ]),
    resource_cleanup(State).

%% @doc FAILING TEST: Find resources by multiple capabilities
test_find_by_multiple_capabilities() ->
    %% Arrange
    State = resource_setup(),

    %% Register resources
    lists:foreach(fun({Name, Caps}) ->
        {ok, _} = yawl_resource_manager:register_resource(Name, human, #{
            capabilities => Caps
        })
    end, [
        {<<"full_stack">>, [review, approve, analyze, report]},
        {<<"partial_stack">>, [review, approve]},
        {<<"analyst_only">>, [analyze, report]}
    ]),

    %% Act - Find requiring both review AND approve
    {ok, MultiCapResources} = yawl_resource_manager:find_resources_by_capabilities(
        [review, approve]),

    %% Assert - Should get full_stack only
    ?assertEqual(1, length(MultiCapResources)),
    {<<"full_stack">>, _} = lists:keyfind(
        fun(_, R) -> maps:get(name, R) =:= <<"full_stack">> end,
        MultiCapResources),

    %% Cleanup
    lists:foreach(fun({Name, _}) ->
        yawl_resource_manager:unregister_resource(Name)
    end, [
        {<<"full_stack">>, _},
        {<<"partial_stack">>, _},
        {<<"analyst_only">>, _}
    ]),
    resource_cleanup(State).

%% @doc FAILING TEST: Capability-based allocation
test_capability_based_allocation() ->
    %% Arrange
    State = resource_setup(),

    %% Register resources
    {ok, _} = yawl_resource_manager:register_resource(
        @"can_review">>, human, #{capabilities => [review]}),
    {ok, _} = yawl_resource_manager:register_resource(
        @"can_approve">>, human, #{capabilities => [approve]}),
    {ok, _} = yawl_resource_manager:register_resource(
        @"can_do_both">>, human, #{capabilities => [review, approve]}),

    %% Act - Allocate requiring both capabilities
    WorkitemId = <<"cap_alloc_test">>,
    {ok, ResourceId, _} =
        yawl_resource_manager:allocate_resource(WorkitemId, [review, approve]),

    %% Assert - Should get resource that has both
    ?assertEqual(@"can_do_both">>, ResourceId),

    %% Cleanup
    yawl_resource_manager:release_resource(WorkitemId),
    lists:foreach(fun(Name) ->
        yawl_resource_manager:unregister_resource(Name)
    end, [@"can_review">>, @"can_approve">>, @"can_do_both">>]),
    resource_cleanup(State).

%%====================================================================
%% Allocation Strategy Tests
%%====================================================================

allocation_strategy_test_() ->
    {"Set round-robin strategy",
     fun test_round_robin_strategy/0},
    {"Set least-loaded strategy",
     fun test_least_loaded_strategy/0},
    {"Set random strategy",
     fun test_random_strategy/0},
    {"Invalid strategy rejected",
     fun test_invalid_strategy_rejected/0},
    {"Round-robin distributes load",
     fun test_round_robin_distribution/0},
    {"Least-loaded selection",
     fun test_least_loaded_selection/0}.

%% @doc FAILING TEST: Set round-robin strategy
test_round_robin_strategy() ->
    %% Arrange
    State = resource_setup(),

    %% Act - Set strategy
    Result = yawl_resource_manager:set_allocation_strategy(round_robin),

    %% Assert
    ?assertEqual(ok, Result),

    %% Verify strategy was set
    {ok, Strategy} = yawl_resource_manager:get_allocation_strategy(),
    ?assertEqual(round_robin, Strategy),

    %% Cleanup
    resource_cleanup(State).

%% @doc FAILING TEST: Set least-loaded strategy
test_least_loaded_strategy() ->
    %% Arrange
    State = resource_setup(),

    %% Act - Set strategy
    Result = yawl_resource_manager:set_allocation_strategy(least_loaded),

    %% Assert
    ?assertEqual(ok, Result),

    %% Verify
    {ok, Strategy} = yawl_resource_manager:get_allocation_strategy(),
    ?assertEqual(least_loaded, Strategy),

    %% Cleanup
    resource_cleanup(State).

%% @doc FAILING TEST: Set random strategy
test_random_strategy() ->
    %% Arrange
    State = resource_setup(),

    %% Act - Set strategy
    Result = yawl_resource_manager:set_allocation_strategy(random),

    %% Assert
    ?assertEqual(ok, Result),

    %% Verify
    {ok, Strategy} = yawl_resource_manager:get_allocation_strategy(),
    ?assertEqual(random, Strategy),

    %% Cleanup
    resource_cleanup(State).

%% @doc FAILING TEST: Invalid strategy rejected
test_invalid_strategy_rejected() ->
    %% Arrange
    State = resource_setup(),

    %% Act - Try to set invalid strategy
    Result = yawl_resource_manager:set_allocation_strategy(invalid_strategy),

    %% Assert
    ?assertEqual({error, invalid_allocation_strategy}, Result),

    %% Cleanup
    resource_cleanup(State).

%% @doc FAILING TEST: Round-robin distributes load
test_round_robin_distribution() ->
    %% Arrange
    State = resource_setup(),

    %% Register multiple resources
    lists:foreach(fun(N) ->
        Name = <<"rr_res_", (integer_to_binary(N))/binary>>,
        {ok, _} = yawl_resource_manager:register_resource(
            Name, human, #{capabilities => [task], max_capacity => 10})
    end, lists:seq(1, 3)),

    %% Set round-robin strategy
    ok = yawl_resource_manager:set_allocation_strategy(round_robin),

    %% Act - Allocate multiple workitems
    AllocResults = lists:map(fun(N) ->
        WorkitemId = <<"rr_work_", (integer_to_binary(N))/binary>>,
        yawl_resource_manager:allocate_resource(WorkitemId, [task])
    end, lists:seq(1, 9)),

    %% Assert - Load should be distributed
    %% Each resource should get approximately 3 allocations
    ResourceCounts = maps:foldl(fun({_, ResourceId}, Acc) ->
        Acc#{ResourceId => maps:get(ResourceId, Acc, 0) + 1}
    end, #{}, AllocResults),

    Counts = maps:values(ResourceCounts),
    %% Allow some variance but should be roughly equal
    MaxCount = lists:max(Counts),
    MinCount = lists:min(Counts),
    ?assert(MaxCount - MinCount =< 2, "Load distribution too uneven"),

    %% Cleanup
    lists:foreach(fun(N) ->
        Name = <<"rr_res_", (integer_to_binary(N))/binary>>,
        yawl_resource_manager:unregister_resource(Name)
    end, lists:seq(1, 3)),
    resource_cleanup(State).

%% @doc FAILING TEST: Least-loaded selection
test_least_loaded_selection() ->
    %% Arrange
    State = resource_setup(),

    %% Register resources with different loads
    {ok, R1} = yawl_resource_manager:register_resource(
        @"least1">>, human, #{max_capacity => 10}),
    {ok, R2} = yawl_resource_manager:register_resource(
        @"least2">>, human, #{max_capacity => 10}),
    {ok, R3} = yawl_resource_manager:register_resource(
        @"least3">>, human, #{max_capacity => 10}),

    %% Load R1 heavily
    lists:foreach(fun(_) ->
        {ok, _} = yawl_resource_manager:allocate_resource(
            <<"load_task">>, [task]),
        ok = yawl_resource_manager:release_resource(<<"load_task">>)
    end, lists:seq(1, 8)),

    %% Set least-loaded strategy
    ok = yawl_resource_manager:set_allocation_strategy(least_loaded),

    %% Act - Allocate new task
    {ok, SelectedId, _} =
        yawl_resource_manager:allocate_resource(<<"new_task">>, [task]),

    %% Assert - Should select least loaded (R2 or R3)
    ?assert(lists:member(SelectedId, [R2, R3]), "Should select least loaded"),
    ?assertNotEqual(<<"least1">>, SelectedId, "Should not select heavily loaded"),

    %% Cleanup
    lists:foreach(fun(Name) ->
        yawl_resource_manager:unregister_resource(Name)
    end, [@"least1">>, @"least2">>, @"least3">>]),
    resource_cleanup(State).

%%====================================================================
%% Resource Release Tests
%%====================================================================

resource_release_test_() ->
    {"Release single allocation",
     fun test_release_single/0},
    {"Release frees up capacity",
     fun test_release_frees_capacity/0},
    {"Release non-existent allocation",
     fun test_release_nonexistent/0},
    {"Release after completion",
     fun test_release_after_completion/0},
    {"Batch release",
     fun test_batch_release/0}.

%% @doc FAILING TEST: Release single allocation
test_release_single() ->
    %% Arrange
    State = resource_setup(),

    %% Register and allocate
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        @"release_res">>, human, #{
            capabilities => [task],
            max_capacity => 5
        }),
    {ok, ResourceId, _} =
        yawl_resource_manager:allocate_resource(<<"wi1">>, [task]),

    %% Get initial load
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    InitialLoad = maps:get(current_load, Resource),

    %% Act - Release allocation
    Result = yawl_resource_manager:release_resource(<<"wi1">>),

    %% Assert
    ?assertEqual(ok, Result),

    %% Load should decrease
    {ok, UpdatedResource} = yawl_resource_manager:get_resource(ResourceId),
    ?assert(UpdatedResource#yawl_resource_persist.current_load < InitialLoad),

    %% Cleanup
    yawl_resource_manager:unregister_resource(ResourceId),
    resource_cleanup(State).

%% @doc FAILING TEST: Release frees up capacity
test_release_frees_capacity() ->
    %% Arrange
    State = resource_setup(),

    %% Register resource
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        @"capacity_res">>, human, #{
            capabilities => [task],
            max_capacity => 3
        }),

    %% Fill to capacity
    lists:foreach(fun(N) ->
        {ok, ResourceId, _} =
            yawl_resource_manager:allocate_resource(
                <<"wi_", (integer_to_binary(N))/binary>>, [task])
    end, lists:seq(1, 3)),

    %% Verify at capacity
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(3, maps:get(current_load, Resource)),

    %% Act - Release one allocation
    ok = yawl_resource_manager:release_resource(<<"wi_2">>),

    %% Assert - Capacity should be freed
    {ok, UpdatedResource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(2, maps:get(current_load, UpdatedResource)),
    ?assertEqual(available, maps:get(status, UpdatedResource)),

    %% Cleanup
    yawl_resource_manager:unregister_resource(ResourceId),
    resource_cleanup(State).

%% @doc FAILING TEST: Release non-existent allocation
test_release_nonexistent() ->
    %% Arrange
    State = resource_setup(),

    %% Act - Try to release non-existent allocation
    Result = yawl_resource_manager:release_resource(<<"nonexistent">>),

    %% Assert
    ?assertEqual({error, allocation_not_found}, Result),

    %% Cleanup
    resource_cleanup(State).

%% @doc FAILING TEST: Release after completion
test_release_after_completion() ->
    %% Arrange
    State = resource_setup(),

    %% Register and allocate
    {ok, ResourceId} = yawl_resource_manager:register_resource(
        @"auto_release_res">>, human, #{
            capabilities => [task],
            max_capacity => 1
        }),
    {ok, ResourceId, _} =
        yawl_resource_manager:allocate_resource(<<"wi_auto">>, [task]),

    %% Mark workitem as completed
    ok = yawl_persistence:update_workitem_status(
        <<"wi_auto">>, completed),

    %% Act - Release should auto-trigger (in real implementation)
    %% For now, manual release
    Result = yawl_resource_manager:release_resource(<<"wi_auto">>),

    %% Assert
    ?assertEqual(ok, Result),

    %% Resource should be available again
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(available, maps:get(status, Resource)),

    %% Cleanup
    yawl_resource_manager:unregister_resource(ResourceId),
    resource_cleanup(State).

%% @doc FAILING TEST: Batch release
test_batch_release() ->
    %% Arrange
    State = resource_setup(),

    %% Register resources and allocate multiple
    Resources = lists:map(fun(N) ->
        Name = <<"batch_res_", (integer_to_binary(N))/binary>>,
        {ok, Rid} = yawl_resource_manager:register_resource(
            Name, human, #{capabilities => [task], max_capacity => 2}),
        {N, Rid}
    end, lists:seq(1, 5)),

    %% Allocate for each resource
    lists:foreach(fun({N, _}) ->
        {ok, _, _} =
            yawl_resource_manager:allocate_resource(
                <<"batch_wi_", (integer_to_binary(N))/binary>>, [task])
    end, Resources),

    %% Act - Batch release
    Results = lists:map(fun({N, _}) ->
        yawl_resource_manager:release_resource(
            <<"batch_wi_", (integer_to_binary(N))/binary>>)
    end, lists:seq(1, 5)),

    %% Assert - All releases should succeed
    ?assert(lists:all(fun(R) -> R =:= ok end, Results)),

    %% All resources should be available again
    {ok, AvailableResources} = yawl_resource_manager:list_available_resources(),
    ?assert(length(AvailableResources) >= 5),

    %% Cleanup
    lists:foreach(fun({_, Rid}) ->
        yawl_resource_manager:unregister_resource(Rid)
    end, Resources),
    resource_cleanup(State).
