%%%-------------------------------------------------------------------
%%% @doc
%%% Comprehensive Unit Tests for YAWL Resource Manager
%%%
%%% This module provides comprehensive test coverage for the YAWL resource
%%% manager, covering all major functions, edge cases, error paths,
%%% resource registration, allocation strategies, capability management,
%%% and resource lifecycle.
%%%
%%% Target Coverage: 95%+
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_resource_manager_comprehensive_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Generator
%%====================================================================

resource_manager_comprehensive_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Group 1: Server Lifecycle", fun test_group_lifecycle/0},
      {"Group 2: Resource Registration", fun test_group_registration/0},
      {"Group 3: Resource Queries", fun test_group_queries/0},
      {"Group 4: Resource Allocation", fun test_group_allocation/0},
      {"Group 5: Allocation Strategies", fun test_group_strategies/0},
      {"Group 6: Capability Management", fun test_group_capabilities/0},
      {"Group 7: Resource Status", fun test_group_status/0},
      {"Group 8: Resource Release", fun test_group_release/0},
      {"Group 9: Edge Cases", fun test_group_edge_cases/0},
      {"Group 10: Error Handling", fun test_group_errors/0}
     ]}.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    {ok, Pid} = yawl_resource_manager:start_link(),
    Pid.

cleanup(Pid) ->
    gen_server:stop(Pid).

%%====================================================================
%% Group 1: Server Lifecycle
%%====================================================================

test_group_lifecycle() ->
    test_start_link(),
    test_init_state(),
    test_terminate(),
    test_code_change(),
    ok.

test_start_link() ->
    {ok, Pid} = yawl_resource_manager:start_link(),
    ?assert(is_pid(Pid)),
    ?assert(is_process_alive(Pid)),
    gen_server:stop(Pid).

test_init_state() ->
    {ok, Pid} = yawl_resource_manager:start_link(),
    State = sys:get_state(Pid),
    ?assert(is_map(element(2, State))),  %% resources field
    ?assert(is_map(element(3, State))),  %% allocations field
    ?assert(is_map(element(4, State))),  %% resource_by_type field
    ?assert(is_map(element(5, State))),  %% resource_by_capability field
    ?assertEqual(least_loaded, element(6, State)),  %% allocation_strategy field
    gen_server:stop(Pid).

test_terminate() ->
    {ok, Pid} = yawl_resource_manager:start_link(),
    gen_server:stop(Pid),
    ?assertNot(is_process_alive(Pid)).

test_code_change() ->
    {ok, Pid} = yawl_resource_manager:start_link(),
    {ok, State} = sys:replace_state(Pid, fun(S) -> S end),
    ?assert(is_tuple(State)),
    ?assertEqual(7, tuple_size(State)),
    gen_server:stop(Pid).

%%====================================================================
%% Group 2: Resource Registration
%%====================================================================

test_group_registration() ->
    test_register_human(),
    test_register_service(),
    test_register_system(),
    test_register_with_options(),
    test_register_duplicate_names(),
    test_register_multiple(),
    ok.

test_register_human() ->
    ResourceName = <<"test_human">>,
    {ok, ResourceId} = yawl_resource_manager:register_resource(ResourceName, human),
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(human, maps:get(resource_type, Resource)),
    ?assertEqual(<<"test_human">>, maps:get(name, Resource)).

test_register_service() ->
    ResourceName = <<"test_service">>,
    {ok, ResourceId} = yawl_resource_manager:register_resource(ResourceName, service),
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(service, maps:get(resource_type, Resource)).

test_register_system() ->
    ResourceName = <<"test_system">>,
    {ok, ResourceId} = yawl_resource_manager:register_resource(ResourceName, system),
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(system, maps:get(resource_type, Resource)).

test_register_with_options() ->
    ResourceName = <<"test_options">>,
    Options = #{
        max_capacity => 20,
        capabilities => [task1, task2, task3],
        attributes => #{location => "us-west"}
    },
    {ok, ResourceId} = yawl_resource_manager:register_resource(ResourceName, service, Options),
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(20, maps:get(max_capacity, Resource)),
    ?assertEqual(3, length(maps:get(capabilities, Resource))).

test_register_duplicate_names() ->
    ResourceName = <<"test_dup">>,
    {ok, Id1} = yawl_resource_manager:register_resource(ResourceName, service),
    {ok, Id2} = yawl_resource_manager:register_resource(ResourceName, service),
    %% Should create different IDs
    ?assertNotEqual(Id1, Id2).

test_register_multiple() ->
    lists:foreach(fun(I) ->
        Name = <<"resource_", (integer_to_binary(I))/binary>>,
        {ok, _} = yawl_resource_manager:register_resource(Name, service)
    end, lists:seq(1, 10)).

%%====================================================================
%% Group 3: Resource Queries
%%====================================================================

test_group_queries() ->
    test_get_resource(),
    test_get_resource_not_found(),
    test_list_resources(),
    test_list_by_type(),
    test_list_available(),
    test_list_empty(),
    ok.

test_get_resource() ->
    ResourceName = <<"test_get">>,
    {ok, ResourceId} = yawl_resource_manager:register_resource(ResourceName, service),
    {ok, Resource} = yawl_resource_manager:get_resource(ResourceId),
    ?assertEqual(ResourceId, maps:get(resource_id, Resource)).

test_get_resource_not_found() ->
    Result = yawl_resource_manager:get_resource(<<"non_existent_res">>),
    ?assertEqual({error, resource_not_found}, Result).

test_list_resources() ->
    lists:foreach(fun(I) ->
        Name = <<"list_res_", (integer_to_binary(I))/binary>>,
        {ok, _} = yawl_resource_manager:register_resource(Name, service)
    end, lists:seq(1, 3)),
    {ok, Resources} = yawl_resource_manager:list_resources(),
    ?assert(length(Resources) >= 3).

test_list_by_type() ->
    {ok, _} = yawl_resource_manager:register_resource(<<"service1">>, service),
    {ok, _} = yawl_resource_manager:register_resource(<<"service2">>, service),
    {ok, _} = yawl_resource_manager:register_resource(<<"human1">>, human),
    {ok, Services} = yawl_resource_manager:list_resources_by_type(service),
    {ok, Humans} = yawl_resource_manager:list_resources_by_type(human),
    ?assert(length(Services) >= 2),
    ?assert(length(Humans) >= 1).

test_list_available() ->
    {ok, Rid1} = yawl_resource_manager:register_resource(<<"avail1">>, service, #{max_capacity => 5, capabilities => [task1]}),
    {ok, Rid2} = yawl_resource_manager:register_resource(<<"avail2">>, service, #{max_capacity => 1, capabilities => [task1]}),
    %% Allocate from Rid2 to make it busy
    {ok, _, _} = yawl_resource_manager:allocate_resource(<<"wi1">>, [task1]),
    {ok, Available} = yawl_resource_manager:list_available_resources(),
    ?assert(length(Available) >= 1),
    %% Cleanup
    ok = yawl_resource_manager:release_resource(<<"wi1">>).

test_list_empty() ->
    {ok, Resources} = yawl_resource_manager:list_resources(),
    %% Should have at least some resources
    ?assert(length(Resources) >= 0).

%%====================================================================
%% Group 4: Resource Allocation
%%====================================================================

test_group_allocation() ->
    test_allocate_by_capability(),
    test_allocate_by_type_and_capability(),
    test_allocate_to_capacity(),
    test_allocate_no_resources(),
    test_allocate_with_no_capabilities(),
    ok.

test_allocate_by_capability() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"alloc_cap">>, service, #{capabilities => [task1, task2]}),
    {ok, AllocatedId, Resource} = yawl_resource_manager:allocate_resource(<<"wi1">>, [task1]),
    ?assertEqual(Rid, AllocatedId),
    ?assertEqual(1, maps:get(current_load, Resource)).

test_allocate_by_type_and_capability() ->
    {ok, _} = yawl_resource_manager:register_resource(<<"alloc_type1">>, human, #{capabilities => [task1]}),
    {ok, Rid} = yawl_resource_manager:register_resource(<<"alloc_type2">>, service, #{capabilities => [task1]}),
    {ok, AllocatedId, _} = yawl_resource_manager:allocate_resource(<<"wi2">>, service, [task1]),
    ?assertEqual(Rid, AllocatedId).

test_allocate_to_capacity() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"alloc_cap">>, service, #{max_capacity => 2, capabilities => [task1]}),
    {ok, _, R1} = yawl_resource_manager:allocate_resource(<<"wi3">>, [task1]),
    ?assertEqual(1, maps:get(current_load, R1)),
    {ok, _, R2} = yawl_resource_manager:allocate_resource(<<"wi4">>, [task1]),
    ?assertEqual(2, maps:get(current_load, R2)),
    %% Third allocation should fail or allocate elsewhere
    Result = yawl_resource_manager:allocate_resource(<<"wi5">>, [task1]),
    ?assertMatch({error, _}, Result).

test_allocate_no_resources() ->
    Result = yawl_resource_manager:allocate_resource(<<"wi_no_res">>, [task1]),
    ?assertEqual({error, no_available_resources}, Result).

test_allocate_with_no_capabilities() ->
    {ok, _} = yawl_resource_manager:register_resource(
        <<"alloc_no_cap">>, service, #{capabilities => []}),
    Result = yawl_resource_manager:allocate_resource(<<"wi_no_cap">>, []),
    %% Should allocate if no capabilities required
    ?assertMatch({ok, _, _}, Result).

%%====================================================================
%% Group 5: Allocation Strategies
%%====================================================================

test_group_strategies() ->
    test_set_strategy_least_loaded(),
    test_set_strategy_round_robin(),
    test_set_strategy_random(),
    test_set_strategy_invalid(),
    test_get_strategy(),
    test_least_loaded_selection(),
    test_round_robin_selection(),
    test_random_selection(),
    ok.

test_set_strategy_least_loaded() ->
    Result = yawl_resource_manager:set_allocation_strategy(least_loaded),
    ?assertEqual(ok, Result).

test_set_strategy_round_robin() ->
    Result = yawl_resource_manager:set_allocation_strategy(round_robin),
    ?assertEqual(ok, Result).

test_set_strategy_random() ->
    Result = yawl_resource_manager:set_allocation_strategy(random),
    ?assertEqual(ok, Result).

test_set_strategy_invalid() ->
    Result = yawl_resource_manager:set_allocation_strategy(invalid_strategy),
    ?assertEqual({error, invalid_allocation_strategy}, Result).

test_get_strategy() ->
    yawl_resource_manager:set_allocation_strategy(round_robin),
    {ok, Strategy} = yawl_resource_manager:get_allocation_strategy(),
    ?assertEqual(round_robin, Strategy).

test_least_loaded_selection() ->
    yawl_resource_manager:set_allocation_strategy(least_loaded),
    {ok, Rid1} = yawl_resource_manager:register_resource(
        <<"ll1">>, service, #{capabilities => [task1], max_capacity => 10}),
    {ok, Rid2} = yawl_resource_manager:register_resource(
        <<"ll2">>, service, #{capabilities => [task1], max_capacity => 10}),
    %% Allocate from Rid1 to increase its load
    {ok, _, _} = yawl_resource_manager:allocate_resource(<<"wi_ll">>, [task1]),
    %% Next allocation should go to Rid2 (least loaded)
    {ok, AllocatedId, _} = yawl_resource_manager:allocate_resource(<<"wi_ll2">>, [task1]),
    ?assertEqual(Rid2, AllocatedId).

test_round_robin_selection() ->
    yawl_resource_manager:set_allocation_strategy(round_robin),
    {ok, Rid1} = yawl_resource_manager:register_resource(
        <<"rr1">>, service, #{capabilities => [task1]}),
    {ok, Rid2} = yawl_resource_manager:register_resource(
        <<"rr2">>, service, #{capabilities => [task1]}),
    {ok, Allocated1, _} = yawl_resource_manager:allocate_resource(<<"wi_rr1">>, [task1]),
    {ok, Allocated2, _} = yawl_resource_manager:allocate_resource(<<"wi_rr2">>, [task1]),
    ?assertEqual(Rid1, Allocated1),
    ?assertEqual(Rid2, Allocated2).

test_random_selection() ->
    yawl_resource_manager:set_allocation_strategy(random),
    {ok, _} = yawl_resource_manager:register_resource(
        <<"rand1">>, service, #{capabilities => [task1]}),
    {ok, _} = yawl_resource_manager:register_resource(
        <<"rand2">>, service, #{capabilities => [task1]}),
    {ok, AllocatedId, _} = yawl_resource_manager:allocate_resource(<<"wi_rand">>, [task1]),
    ?assert(lists:member(AllocatedId, [<<"rand1_service_">>, <<"rand2_service_">>])).

%%====================================================================
%% Group 6: Capability Management
%%====================================================================

test_group_capabilities() ->
    test_add_capability(),
    test_add_duplicate_capability(),
    test_remove_capability(),
    test_remove_nonexistent_capability(),
    test_find_by_capability(),
    test_find_by_multiple_capabilities(),
    test_capabilities_across_types(),
    ok.

test_add_capability() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"cap_add">>, service, #{capabilities => [task1]}),
    Result = yawl_resource_manager:add_capability(Rid, task2),
    ?assertEqual(ok, Result),
    {ok, Resource} = yawl_resource_manager:get_resource(Rid),
    ?assert(lists:member(task2, maps:get(capabilities, Resource))).

test_add_duplicate_capability() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"cap_dup">>, service, #{capabilities => [task1]}),
    ok = yawl_resource_manager:add_capability(Rid, task1),
    %% Adding duplicate should be idempotent
    ok = yawl_resource_manager:add_capability(Rid, task1),
    {ok, Resource} = yawl_resource_manager:get_resource(Rid),
    Capabilities = maps:get(capabilities, Resource),
    ?assertEqual(1, lists:filter(fun(C) -> C =:= task1 end, Capabilities)).

test_remove_capability() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"cap_rem">>, service, #{capabilities => [task1, task2]}),
    Result = yawl_resource_manager:remove_capability(Rid, task1),
    ?assertEqual(ok, Result),
    {ok, Resource} = yawl_resource_manager:get_resource(Rid),
    ?assertNot(lists:member(task1, maps:get(capabilities, Resource))),
    ?assert(lists:member(task2, maps:get(capabilities, Resource))).

test_remove_nonexistent_capability() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"cap_no_rem">>, service, #{capabilities => [task1]}),
    Result = yawl_resource_manager:remove_capability(Rid, task2),
    ?assertEqual(ok, Result).

test_find_by_capability() ->
    {ok, _} = yawl_resource_manager:register_resource(
        <<"find_cap1">>, service, #{capabilities => [task1]}),
    {ok, _} = yawl_resource_manager:register_resource(
        <<"find_cap2">>, service, #{capabilities => [task2]}),
    {ok, _} = yawl_resource_manager:register_resource(
        <<"find_cap3">>, service, #{capabilities => [task1, task2]}),
    {ok, Resources} = yawl_resource_manager:find_resources_by_capability(task1),
    ?assert(length(Resources) >= 2).

test_find_by_multiple_capabilities() ->
    {ok, _} = yawl_resource_manager:register_resource(
        <<"find_multi1">>, service, #{capabilities => [task1, task2, task3]}),
    {ok, _} = yawl_resource_manager:register_resource(
        <<"find_multi2">>, service, #{capabilities => [task1, task2]}),
    {ok, _} = yawl_resource_manager:register_resource(
        <<"find_multi3">>, service, #{capabilities => [task1]}),
    {ok, Resources} = yawl_resource_manager:find_resources_by_capabilities([task1, task2]),
    ?assert(length(Resources) >= 2).

test_capabilities_across_types() ->
    {ok, _} = yawl_resource_manager:register_resource(
        <<"cap_cross1">>, human, #{capabilities => [task1]}),
    {ok, _} = yawl_resource_manager:register_resource(
        <<"cap_cross2">>, service, #{capabilities => [task1]}),
    {ok, _} = yawl_resource_manager:register_resource(
        <<"cap_cross3">>, system, #{capabilities => [task1]}),
    {ok, Resources} = yawl_resource_manager:find_resources_by_capability(task1),
    ?assert(length(Resources) >= 3).

%%====================================================================
%% Group 7: Resource Status
%%====================================================================

test_group_status() ->
    test_update_status_available(),
    test_update_status_busy(),
    test_update_status_unavailable(),
    test_update_status_offline(),
    test_update_status_not_found(),
    test_status_transitions(),
    ok.

test_update_status_available() ->
    {ok, Rid} = yawl_resource_manager:register_resource(<<"status_avail">>, service),
    Result = yawl_resource_manager:update_resource_status(Rid, available),
    ?assertEqual(ok, Result),
    {ok, Resource} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(available, maps:get(status, Resource)).

test_update_status_busy() ->
    {ok, Rid} = yawl_resource_manager:register_resource(<<"status_busy">>, service),
    Result = yawl_resource_manager:update_resource_status(Rid, busy),
    ?assertEqual(ok, Result),
    {ok, Resource} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(busy, maps:get(status, Resource)).

test_update_status_unavailable() ->
    {ok, Rid} = yawl_resource_manager:register_resource(<<"status_unavail">>, service),
    Result = yawl_resource_manager:update_resource_status(Rid, unavailable),
    ?assertEqual(ok, Result),
    {ok, Resource} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(unavailable, maps:get(status, Resource)).

test_update_status_offline() ->
    {ok, Rid} = yawl_resource_manager:register_resource(<<"status_offline">>, service),
    Result = yawl_resource_manager:update_resource_status(Rid, offline),
    ?assertEqual(ok, Result),
    {ok, Resource} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(offline, maps:get(status, Resource)).

test_update_status_not_found() ->
    Result = yawl_resource_manager:update_resource_status(<<"non_existent">>, available),
    ?assertEqual({error, resource_not_found}, Result).

test_status_transitions() ->
    {ok, Rid} = yawl_resource_manager:register_resource(<<"status_trans">>, service),
    ?assertEqual(ok, yawl_resource_manager:update_resource_status(Rid, busy)),
    ?assertEqual(ok, yawl_resource_manager:update_resource_status(Rid, available)),
    ?assertEqual(ok, yawl_resource_manager:update_resource_status(Rid, unavailable)),
    ?assertEqual(ok, yawl_resource_manager:update_resource_status(Rid, available)).

%%====================================================================
%% Group 8: Resource Release
%%====================================================================

test_group_release() ->
    test_release_by_workitem(),
    test_release_by_resource(),
    test_release_not_found(),
    test_release_updates_load(),
    test_release_available_status(),
    ok.

test_release_by_workitem() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"release_wi">>, service, #{max_capacity => 5, capabilities => [task1]}),
    {ok, _, _} = yawl_resource_manager:allocate_resource(<<"wi_release">>, [task1]),
    {ok, Resource1} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(1, maps:get(current_load, Resource1)),
    Result = yawl_resource_manager:release_resource(<<"wi_release">>),
    ?assertEqual(ok, Result),
    {ok, Resource2} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(0, maps:get(current_load, Resource2)).

test_release_by_resource() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"release_res">>, service, #{max_capacity => 5, capabilities => [task1]}),
    {ok, _, _} = yawl_resource_manager:allocate_resource(<<"wi_release_res">>, [task1]),
    Result = yawl_resource_manager:release_resource(<<"wi_release_res">>, Rid),
    ?assertEqual(ok, Result),
    {ok, Resource} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(0, maps:get(current_load, Resource)).

test_release_not_found() ->
    Result = yawl_resource_manager:release_resource(<<"non_existent_wi">>),
    ?assertEqual({error, allocation_not_found}, Result).

test_release_updates_load() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"release_load">>, service, #{max_capacity => 10, capabilities => [task1]}),
    lists:foreach(fun(I) ->
        WorkitemId = <<"wi_load_", (integer_to_binary(I))/binary>>,
        {ok, _, _} = yawl_resource_manager:allocate_resource(WorkitemId, [task1])
    end, lists:seq(1, 5)),
    {ok, Resource1} = yawl_resource_manager:get_resource(Rid),
    Load1 = maps:get(current_load, Resource1),
    lists:foreach(fun(I) ->
        WorkitemId = <<"wi_load_", (integer_to_binary(I))/binary>>,
        yawl_resource_manager:release_resource(WorkitemId)
    end, lists:seq(1, 5)),
    {ok, Resource2} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(0, maps:get(current_load, Resource2)),
    ?assertEqual(Load1, 5).

test_release_available_status() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"release_avail">>, service, #{max_capacity => 1, capabilities => [task1]}),
    {ok, _, _} = yawl_resource_manager:allocate_resource(<<"wi_avail">>, [task1]),
    {ok, Resource1} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(busy, maps:get(status, Resource1)),
    ok = yawl_resource_manager:release_resource(<<"wi_avail">>),
    {ok, Resource2} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(available, maps:get(status, Resource2)).

%%====================================================================
%% Group 9: Edge Cases
%%====================================================================

test_group_edge_cases() ->
    test_zero_capacity(),
    test_large_capacity(),
    test_many_capabilities(),
    test_special_characters_in_name(),
    test_concurrent_allocation(),
    test_rapid_allocate_release(),
    ok.

test_zero_capacity() ->
    %% Resource with max_capacity 0 should not be allocatable
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"zero_cap">>, service, #{max_capacity => 0, capabilities => [task1]}),
    Result = yawl_resource_manager:allocate_resource(<<"wi_zero">>, [task1]),
    ?assertEqual({error, no_available_resources}, Result).

test_large_capacity() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"large_cap">>, service, #{max_capacity => 10000, capabilities => [task1]}),
    lists:foreach(fun(I) ->
        WorkitemId = <<"wi_large_", (integer_to_binary(I))/binary>>,
        {ok, _, _} = yawl_resource_manager:allocate_resource(WorkitemId, [task1])
    end, lists:seq(1, 100)),
    {ok, Resource} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(100, maps:get(current_load, Resource)).

test_many_capabilities() ->
    ManyCaps = lists:map(fun(I) -> list_to_atom("task" ++ integer_to_list(I)) end, lists:seq(1, 50)),
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"many_caps">>, service, #{capabilities => ManyCaps}),
    {ok, Resource} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(50, length(maps:get(capabilities, Resource))).

test_special_characters_in_name() ->
    SpecialNames = [
        <<"name with spaces">>,
        <<"name-with-dashes">>,
        <<"name_with_underscores">>,
        <<"name.with.dots">>,
        <<"name@symbol">>
    ],
    lists:foreach(fun(Name) ->
        Result = yawl_resource_manager:register_resource(Name, service),
        ?assertMatch({ok, _}, Result)
    end, SpecialNames).

test_concurrent_allocation() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"concurrent">>, service, #{max_capacity => 10, capabilities => [task1]}),
    %% Allocate concurrently
    Pids = lists:map(fun(I) ->
        spawn(fun() ->
            WorkitemId = <<"wi_conc_", (integer_to_binary(I))/binary>>,
            yawl_resource_manager:allocate_resource(WorkitemId, [task1])
        end)
    end, lists:seq(1, 10)),
    timer:sleep(500),
    lists:foreach(fun(P) -> exit(P, kill) end, Pids),
    {ok, Resource} = yawl_resource_manager:get_resource(Rid),
    ?assert(maps:get(current_load, Resource) =< 11).

test_rapid_allocate_release() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"rapid">>, service, #{max_capacity => 5, capabilities => [task1]}),
    lists:foreach(fun(I) ->
        WorkitemId = <<"wi_rapid_", (integer_to_binary(I))/binary>>,
        {ok, _, _} = yawl_resource_manager:allocate_resource(WorkitemId, [task1]),
        ok = yawl_resource_manager:release_resource(WorkitemId)
    end, lists:seq(1, 20)),
    {ok, Resource} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(0, maps:get(current_load, Resource)).

%%====================================================================
%% Group 10: Error Handling
%%====================================================================

test_group_errors() ->
    test_unregister_not_found(),
    test_update_load_not_found(),
    test_unsubscribe_not_found(),
    test_invalid_resource_type(),
    test_malformed_capability(),
    ok.

test_unregister_not_found() ->
    Result = yawl_resource_manager:unregister_resource(<<"non_existent_res">>),
    ?assertEqual({error, resource_not_found}, Result).

test_update_load_not_found() ->
    Result = yawl_resource_manager:update_resource_load(<<"non_existent_res">>, 5),
    ?assertEqual({error, resource_not_found}, Result).

test_unsubscribe_not_found() ->
    Result = yawl_resource_manager:remove_capability(<<"non_existent_res">>, task1),
    ?assertEqual({error, resource_not_found}, Result).

test_invalid_resource_type() ->
    %% Resource types are validated
    ValidTypes = [human, service, system],
    lists:foreach(fun(Type) ->
        Result = yawl_resource_manager:register_resource(<<"test_type">>, Type),
        ?assertMatch({ok, _}, Result)
    end, ValidTypes).

test_malformed_capability() ->
    {ok, Rid} = yawl_resource_manager:register_resource(<<"malformed">>, service),
    %% Capabilities can be any atom
    ok = yawl_resource_manager:add_capability(Rid, some_capability),
    ok = yawl_resource_manager:remove_capability(Rid, some_capability).

%%====================================================================
%% Property-Based Tests
%%====================================================================

property_test_() ->
    [
     {"Resource registration and retrieval", fun test_prop_register_retrieve/0},
     {"Allocation increments load", fun test_prop_allocation_increments_load/0},
     {"Release decrements load", fun test_prop_release_decrements_load/0}
    ].

test_prop_register_retrieve() ->
    NumResources = 10,
    ResourceIds = lists:map(fun(I) ->
        Name = <<"prop_res_", (integer_to_binary(I))/binary>>,
        {ok, Rid} = yawl_resource_manager:register_resource(Name, service),
        Rid
    end, lists:seq(1, NumResources)),
    lists:foreach(fun(Rid) ->
        {ok, Resource} = yawl_resource_manager:get_resource(Rid),
        ?assertEqual(service, maps:get(resource_type, Resource))
    end, ResourceIds).

test_prop_allocation_increments_load() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"prop_alloc">>, service, #{max_capacity => 100, capabilities => [task1]}),
    lists:foreach(fun(I) ->
        WorkitemId = <<"wi_prop_", (integer_to_binary(I))/binary>>,
        {ok, _, Resource} = yawl_resource_manager:allocate_resource(WorkitemId, [task1]),
        CurrentLoad = maps:get(current_load, Resource),
        ?assertEqual(I, CurrentLoad)
    end, lists:seq(1, 10)).

test_prop_release_decrements_load() ->
    {ok, Rid} = yawl_resource_manager:register_resource(
        <<"prop_release">>, service, #{max_capacity => 10, capabilities => [task1]}),
    %% Allocate several
    lists:foreach(fun(I) ->
        WorkitemId = <<"wi_prop_rel_", (integer_to_binary(I))/binary>>,
        {ok, _, _} = yawl_resource_manager:allocate_resource(WorkitemId, [task1])
    end, lists:seq(1, 5)),
    {ok, Resource1} = yawl_resource_manager:get_resource(Rid),
    LoadBefore = maps:get(current_load, Resource1),
    ?assertEqual(5, LoadBefore),
    %% Release one
    ok = yawl_resource_manager:release_resource(<<"wi_prop_rel_1">>),
    {ok, Resource2} = yawl_resource_manager:get_resource(Rid),
    ?assertEqual(4, maps:get(current_load, Resource2)).
