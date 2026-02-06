%%%-------------------------------------------------------------------
%%% @doc
%%% Comprehensive Simulation Tests for YAWL Resource Allocation Patterns
%%%
%%% This module contains simulation tests for resource allocation patterns:
%%% - Pattern 38: implicit_merge_with_allocation
%%% - Pattern 39: implicit_merge_without_allocation
%%% - Pattern 40: multiple_merge_with_allocation
%%% - Pattern 41: multiple_merge_without_allocation
%%% - Pattern 42: deferred_choice_with_allocation
%%% - Pattern 43: deferred_choice_without_allocation
%%%
%%% Each pattern test includes:
%%% - Resource acquisition before task execution
%%% - Resource constraints enforcement
%%% - Resource deallocation after task completion
%%% - Resource pool exhaustion scenarios
%%% - Resource contention between parallel tasks
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_resource_patterns_sim_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include_lib("yawl_types.hrl").
-include_lib("yawl_schema.hrl").

%%====================================================================
%% Test Generators
%%====================================================================

resource_patterns_sim_test_() ->
    {setup,
     fun setup_all/0,
     fun cleanup_all/1,
     [
      {"Pattern 38: Implicit merge with allocation - resource lifecycle",
       fun test_implicit_merge_with_allocation_lifecycle/0},
      {"Pattern 38: Implicit merge with allocation - pool exhaustion",
       fun test_implicit_merge_with_allocation_exhaustion/0},
      {"Pattern 38: Implicit merge with allocation - parallel contention",
       fun test_implicit_merge_with_allocation_contention/0},
      {"Pattern 38: Implicit merge with allocation - constraints enforced",
       fun test_implicit_merge_with_allocation_constraints/0},

      {"Pattern 39: Implicit merge without allocation - basic execution",
       fun test_implicit_merge_without_allocation_basic/0},
      {"Pattern 39: Implicit merge without allocation - no resource dependency",
       fun test_implicit_merge_without_allocation_no_resource/0},

      {"Pattern 40: Multiple merge with allocation - resource lifecycle",
       fun test_multiple_merge_with_allocation_lifecycle/0},
      {"Pattern 40: Multiple merge with allocation - pool exhaustion",
       fun test_multiple_merge_with_allocation_exhaustion/0},
      {"Pattern 40: Multiple merge with allocation - parallel contention",
       fun test_multiple_merge_with_allocation_contention/0},
      {"Pattern 40: Multiple merge with allocation - multiple merge points",
       fun test_multiple_merge_with_allocation_merge_points/0},

      {"Pattern 41: Multiple merge without allocation - basic execution",
       fun test_multiple_merge_without_allocation_basic/0},
      {"Pattern 41: Multiple merge without allocation - merge synchronization",
       fun test_multiple_merge_without_allocation_sync/0},

      {"Pattern 42: Deferred choice with allocation - resource lifecycle",
       fun test_deferred_choice_with_allocation_lifecycle/0},
      {"Pattern 42: Deferred choice with allocation - choice with resources",
       fun test_deferred_choice_with_allocation_choice/0},
      {"Pattern 42: Deferred choice with allocation - pool exhaustion",
       fun test_deferred_choice_with_allocation_exhaustion/0},
      {"Pattern 42: Deferred choice with allocation - contention on choice",
       fun test_deferred_choice_with_allocation_contention/0},

      {"Pattern 43: Deferred choice without allocation - basic execution",
       fun test_deferred_choice_without_allocation_basic/0},
      {"Pattern 43: Deferred choice without allocation - deferred decision",
       fun test_deferred_choice_without_allocation_decision/0},

      {"Resource Manager Mock - basic operations",
       fun test_mock_resource_manager_basic/0},
      {"Resource Manager Mock - allocation strategies",
       fun test_mock_resource_manager_strategies/0},
      {"Resource Manager Mock - contention handling",
       fun test_mock_resource_manager_contention/0},

      {"Pattern simulation - end-to-end resource flow",
       fun test_end_to_end_resource_flow/0},
      {"Pattern simulation - stress test resource pool",
       fun test_stress_resource_pool/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup_all() ->
    %% Start the mock resource manager
    {ok, Pid} = yawl_mock_resource_manager:start_link(),
    Pid.

cleanup_all(_Pid) ->
    %% Stop the mock resource manager and clean up
    catch gen_server:stop(yawl_mock_resource_manager),
    ok.

%%====================================================================
%% Pattern 38: Implicit Merge With Allocation Tests
%%====================================================================

%% @doc Test the complete resource lifecycle for implicit merge with allocation
test_implicit_merge_with_allocation_lifecycle() ->
    %% Create a resource pool with limited capacity
    ResourceManager = whereis(yawl_mock_resource_manager),
    ?assertNotEqual(undefined, ResourceManager),

    %% Register resources
    {ok, ResourceId} = yawl_mock_resource_manager:register_resource(
        <<"test_processor">>, service, #{max_capacity => 2, capabilities => [process_task]}),

    %% Simulate workflow start
    WorkflowId = <<"workflow_implicit_merge_alloc">>,
    yawl_mock_resource_manager:start_workflow_simulation(WorkflowId, implicit_merge_with_allocation),

    %% Step 1: Resource acquisition before task execution
    WorkitemId1 = <<"$workitem_task1">>,
    {ok, AllocatedId1, _Resource} = yawl_mock_resource_manager:allocate_resource(
        WorkitemId1, [process_task]),
    ?assertEqual(ResourceId, AllocatedId1),

    %% Verify resource is marked as allocated
    {ok, ResourceState} = yawl_mock_resource_manager:get_resource_state(ResourceId),
    ?assertEqual(1, maps:get(current_load, ResourceState)),
    ?assertEqual(allocated, maps:get(allocation_status, ResourceState)),

    %% Step 2: Simulate task execution
    yawl_mock_resource_manager:record_workitem_start(WorkitemId1),
    ?assertEqual({ok, running}, yawl_mock_resource_manager:get_workitem_status(WorkitemId1)),

    %% Step 3: Task completion and resource deallocation
    yawl_mock_resource_manager:record_workitem_complete(WorkitemId1),
    ok = yawl_mock_resource_manager:release_resource(WorkitemId1),

    %% Verify resource is released
    {ok, ResourceStateAfter} = yawl_mock_resource_manager:get_resource_state(ResourceId),
    ?assertEqual(0, maps:get(current_load, ResourceStateAfter)),
    ?assertEqual(available, maps:get(allocation_status, ResourceStateAfter)),

    %% Verify workflow completion
    {ok, completed} = yawl_mock_resource_manager:end_workflow_simulation(WorkflowId),

    %% Cleanup
    ok = yawl_mock_resource_manager:unregister_resource(ResourceId),
    ok.

%% @doc Test resource pool exhaustion for implicit merge with allocation
test_implicit_merge_with_allocation_exhaustion() ->
    %% Create a resource pool with capacity of 1
    {ok, ResourceId} = yawl_mock_resource_manager:register_resource(
        <<"limited_processor">>, service, #{max_capacity => 1, capabilities => [exclusive_task]}),

    %% First workitem should succeed
    WorkitemId1 = <<"$workitem_exhaustive_1">>,
    {ok, ResourceId, _} = yawl_mock_resource_manager:allocate_resource(
        WorkitemId1, [exclusive_task]),

    %% Second workitem should fail due to pool exhaustion
    WorkitemId2 = <<"$workitem_exhaustive_2">>,
    Result = yawl_mock_resource_manager:allocate_resource(WorkitemId2, [exclusive_task]),
    ?assertMatch({error, no_available_resources}, Result),

    %% Release first resource
    ok = yawl_mock_resource_manager:release_resource(WorkitemId1),

    %% Now second workitem should succeed
    {ok, ResourceId, _} = yawl_mock_resource_manager:allocate_resource(
        WorkitemId2, [exclusive_task]),

    %% Cleanup
    ok = yawl_mock_resource_manager:release_resource(WorkitemId2),
    ok = yawl_mock_resource_manager:unregister_resource(ResourceId),
    ok.

%% @doc Test resource contention between parallel tasks for implicit merge with allocation
test_implicit_merge_with_allocation_contention() ->
    %% Create a resource pool with capacity of 2
    {ok, ResourceId} = yawl_mock_resource_manager:register_resource(
        <<"shared_processor">>, service, #{max_capacity => 2, capabilities => [shared_task]}),

    %% Start two parallel workitems
    WorkitemId1 = <<"$workitem_parallel_1">>,
    WorkitemId2 = <<"$workitem_parallel_2">>,

    %% Both should succeed within capacity
    {ok, ResourceId, _} = yawl_mock_resource_manager:allocate_resource(
        WorkitemId1, [shared_task]),
    {ok, ResourceId, _} = yawl_mock_resource_manager:allocate_resource(
        WorkitemId2, [shared_task]),

    %% Third should fail
    WorkitemId3 = <<"$workitem_parallel_3">>,
    ?assertMatch({error, no_available_resources},
        yawl_mock_resource_manager:allocate_resource(WorkitemId3, [shared_task])),

    %% Verify both allocations are tracked
    {ok, ResourceState} = yawl_mock_resource_manager:get_resource_state(ResourceId),
    ?assertEqual(2, maps:get(current_load, ResourceState)),

    %% Release both
    ok = yawl_mock_resource_manager:release_resource(WorkitemId1),
    ok = yawl_mock_resource_manager:release_resource(WorkitemId2),

    %% Cleanup
    ok = yawl_mock_resource_manager:unregister_resource(ResourceId),
    ok.

%% @doc Test resource constraints enforcement for implicit merge with allocation
test_implicit_merge_with_allocation_constraints() ->
    %% Create resources with specific capabilities
    {ok, ResourceA} = yawl_mock_resource_manager:register_resource(
        <<"resource_a">>, service, #{max_capacity => 1, capabilities => [task_a]}),
    {ok, ResourceB} = yawl_mock_resource_manager:register_resource(
        <<"resource_b">>, service, #{max_capacity => 1, capabilities => [task_b]}),

    %% Task with capability task_a should only get resource_a
    WorkitemA = <<"$workitem_a">>,
    {ok, AllocatedA, _} = yawl_mock_resource_manager:allocate_resource(
        WorkitemA, [task_a]),
    ?assertEqual(ResourceA, AllocatedA),

    %% Task with capability task_b should only get resource_b
    WorkitemB = <<"$workitem_b">>,
    {ok, AllocatedB, _} = yawl_mock_resource_manager:allocate_resource(
        WorkitemB, [task_b]),
    ?assertEqual(ResourceB, AllocatedB),

    %% Task with wrong capability should fail
    WorkitemC = <<"$workitem_c">>,
    ?assertMatch({error, no_available_resources},
        yawl_mock_resource_manager:allocate_resource(WorkitemC, [task_c])),

    %% Cleanup
    ok = yawl_mock_resource_manager:release_resource(WorkitemA),
    ok = yawl_mock_resource_manager:release_resource(WorkitemB),
    ok = yawl_mock_resource_manager:unregister_resource(ResourceA),
    ok = yawl_mock_resource_manager:unregister_resource(ResourceB),
    ok.

%%====================================================================
%% Pattern 39: Implicit Merge Without Allocation Tests
%%====================================================================

%% @doc Test basic execution for implicit merge without allocation
test_implicit_merge_without_allocation_basic() ->
    %% No resource registration needed for this pattern
    WorkflowId = <<"workflow_implicit_merge_no_alloc">>,

    %% Simulate workflow without resource allocation
    yawl_mock_resource_manager:start_workflow_simulation(
        WorkflowId, implicit_merge_without_allocation),

    %% Workitems execute without resource allocation
    WorkitemId1 = <<"$workitem_no_alloc_1">>,
    yawl_mock_resource_manager:record_workitem_start(WorkitemId1),
    yawl_mock_resource_manager:record_workitem_complete(WorkitemId1),

    WorkitemId2 = <<"$workitem_no_alloc_2">>,
    yawl_mock_resource_manager:record_workitem_start(WorkitemId2),
    yawl_mock_resource_manager:record_workitem_complete(WorkitemId2),

    %% Verify no resource was allocated
    ?assertEqual({error, workitem_not_allocated},
        yawl_mock_resource_manager:get_allocated_resource(WorkitemId1)),

    {ok, completed} = yawl_mock_resource_manager:end_workflow_simulation(WorkflowId),
    ok.

%% @doc Test no resource dependency for implicit merge without allocation
test_implicit_merge_without_allocation_no_resource() ->
    %% Verify workflow can execute when no resources exist
    WorkflowId = <<"workflow_no_resource_dep">>,

    yawl_mock_resource_manager:start_workflow_simulation(
        WorkflowId, implicit_merge_without_allocation),

    %% Execute multiple workitems
    lists:foreach(fun(I) ->
        WorkitemId = <<"$no_alloc_wi_", (integer_to_binary(I))/binary>>,
        yawl_mock_resource_manager:record_workitem_start(WorkitemId),
        yawl_mock_resource_manager:record_workitem_complete(WorkitemId)
    end, lists:seq(1, 5)),

    {ok, completed} = yawl_mock_resource_manager:end_workflow_simulation(WorkflowId),
    ok.

%%====================================================================
%% Pattern 40: Multiple Merge With Allocation Tests
%%====================================================================

%% @doc Test the complete resource lifecycle for multiple merge with allocation
test_multiple_merge_with_allocation_lifecycle() ->
    %% Create resources for multiple merge points
    {ok, ResourceId} = yawl_mock_resource_manager:register_resource(
        <<"multi_merge_resource">>, service, #{
            max_capacity => 3,
            capabilities => [merge_task_a, merge_task_b]
        }),

    WorkflowId = <<"workflow_multiple_merge_alloc">>,
    yawl_mock_resource_manager:start_workflow_simulation(
        WorkflowId, multiple_merge_with_allocation),

    %% Allocate for first merge point
    WorkitemA1 = <<"$workitem_merge_a1">>,
    {ok, ResourceId, _} = yawl_mock_resource_manager:allocate_resource(
        WorkitemA1, [merge_task_a]),

    %% Allocate for second merge point
    WorkitemB1 = <<"$workitem_merge_b1">>,
    {ok, ResourceId, _} = yawl_mock_resource_manager:allocate_resource(
        WorkitemB1, [merge_task_b]),

    %% Execute and release
    yawl_mock_resource_manager:record_workitem_start(WorkitemA1),
    yawl_mock_resource_manager:record_workitem_complete(WorkitemA1),
    ok = yawl_mock_resource_manager:release_resource(WorkitemA1),

    yawl_mock_resource_manager:record_workitem_start(WorkitemB1),
    yawl_mock_resource_manager:record_workitem_complete(WorkitemB1),
    ok = yawl_mock_resource_manager:release_resource(WorkitemB1),

    %% Verify all resources released
    {ok, ResourceState} = yawl_mock_resource_manager:get_resource_state(ResourceId),
    ?assertEqual(0, maps:get(current_load, ResourceState)),

    {ok, completed} = yawl_mock_resource_manager:end_workflow_simulation(WorkflowId),

    %% Cleanup
    ok = yawl_mock_resource_manager:unregister_resource(ResourceId),
    ok.

%% @doc Test resource pool exhaustion for multiple merge with allocation
test_multiple_merge_with_allocation_exhaustion() ->
    %% Limited capacity resource
    {ok, ResourceId} = yawl_mock_resource_manager:register_resource(
        <<"limited_multi_merge">>, service, #{
            max_capacity => 2,
            capabilities => [multi_task]
        }),

    %% Allocate up to capacity
    WI1 = <<"$multi_wi_1">>,
    WI2 = <<"$multi_wi_2">>,
    WI3 = <<"$multi_wi_3">>,

    {ok, ResourceId, _} = yawl_mock_resource_manager:allocate_resource(WI1, [multi_task]),
    {ok, ResourceId, _} = yawl_mock_resource_manager:allocate_resource(WI2, [multi_task]),

    %% Third should fail
    ?assertMatch({error, no_available_resources},
        yawl_mock_resource_manager:allocate_resource(WI3, [multi_task])),

    %% Release one and retry
    ok = yawl_mock_resource_manager:release_resource(WI1),
    {ok, ResourceId, _} = yawl_mock_resource_manager:allocate_resource(WI3, [multi_task]),

    %% Cleanup
    ok = yawl_mock_resource_manager:release_resource(WI2),
    ok = yawl_mock_resource_manager:release_resource(WI3),
    ok = yawl_mock_resource_manager:unregister_resource(ResourceId),
    ok.

%% @doc Test resource contention between parallel tasks for multiple merge with allocation
test_multiple_merge_with_allocation_contention() ->
    %% Create a pool with limited capacity
    {ok, ResourcePool} = yawl_mock_resource_manager:register_resource(
        <<"contention_pool">>, service, #{
            max_capacity => 3,
            capabilities => [contention_task]
        }),

    %% Simulate concurrent workitems from multiple merge branches
    Workitems = [
        <<"$merge_branch_1_wi_1">>,
        <<"$merge_branch_2_wi_1">>,
        <<"$merge_branch_1_wi_2">>,
        <<"$merge_branch_2_wi_2">>,
        <<"$merge_branch_1_wi_3">>
    ],

    %% Allocate sequentially up to capacity
    AllocResults = lists:map(fun(WI) ->
        yawl_mock_resource_manager:allocate_resource(WI, [contention_task])
    end, Workitems),

    %% First 3 should succeed, last 2 should fail
    SuccessCount = length([X || {ok, _, _} = X <- AllocResults]),
    FailCount = length([X || {error, _} = X <- AllocResults]),
    ?assertEqual(3, SuccessCount),
    ?assertEqual(2, FailCount),

    %% Release successful allocations
    lists:foreach(fun(WI) ->
        case yawl_mock_resource_manager:get_allocated_resource(WI) of
            {ok, _} -> yawl_mock_resource_manager:release_resource(WI);
            _ -> ok
        end
    end, Workitems),

    %% Cleanup
    ok = yawl_mock_resource_manager:unregister_resource(ResourcePool),
    ok.

%% @doc Test multiple merge points for multiple merge with allocation
test_multiple_merge_with_allocation_merge_points() ->
    %% Create resources for different merge points
    {ok, Resource1} = yawl_mock_resource_manager:register_resource(
        <<"merge_point_1">>, service, #{
            max_capacity => 2,
            capabilities => [point1_task]
        }),
    {ok, Resource2} = yawl_mock_resource_manager:register_resource(
        <<"merge_point_2">>, service, #{
            max_capacity => 2,
            capabilities => [point2_task]
        }),

    %% Workitems for merge point 1
    WI1A = <<"$mp1_wi_a">>,
    WI1B = <<"$mp1_wi_b">>,
    {ok, Resource1, _} = yawl_mock_resource_manager:allocate_resource(WI1A, [point1_task]),
    {ok, Resource1, _} = yawl_mock_resource_manager:allocate_resource(WI1B, [point1_task]),

    %% Workitems for merge point 2
    WI2A = <<"$mp2_wi_a">>,
    WI2B = <<"$mp2_wi_b">>,
    {ok, Resource2, _} = yawl_mock_resource_manager:allocate_resource(WI2A, [point2_task]),
    {ok, Resource2, _} = yawl_mock_resource_manager:allocate_resource(WI2B, [point2_task]),

    %% Verify each merge point has correct load
    {ok, State1} = yawl_mock_resource_manager:get_resource_state(Resource1),
    ?assertEqual(2, maps:get(current_load, State1)),

    {ok, State2} = yawl_mock_resource_manager:get_resource_state(Resource2),
    ?assertEqual(2, maps:get(current_load, State2)),

    %% Cleanup
    lists:foreach(fun(WI) -> yawl_mock_resource_manager:release_resource(WI) end,
        [WI1A, WI1B, WI2A, WI2B]),
    ok = yawl_mock_resource_manager:unregister_resource(Resource1),
    ok = yawl_mock_resource_manager:unregister_resource(Resource2),
    ok.

%%====================================================================
%% Pattern 41: Multiple Merge Without Allocation Tests
%%====================================================================

%% @doc Test basic execution for multiple merge without allocation
test_multiple_merge_without_allocation_basic() ->
    WorkflowId = <<"workflow_multi_merge_no_alloc">>,
    yawl_mock_resource_manager:start_workflow_simulation(
        WorkflowId, multiple_merge_without_allocation),

    %% Execute workitems at multiple merge points
    MergePoints = [
        {<<"merge1">>, [<<"wi1">>, <<"wi2">>]},
        {<<"merge2">>, [<<"wi3">>, <<"wi4">>]}
    ],

    lists:foreach(fun({MP, WIs}) ->
        lists:foreach(fun(I) ->
            WI = <<"$", MP/binary, "_", I/binary>>,
            yawl_mock_resource_manager:record_workitem_start(WI),
            yawl_mock_resource_manager:record_workitem_complete(WI)
        end, WIs)
    end, MergePoints),

    {ok, completed} = yawl_mock_resource_manager:end_workflow_simulation(WorkflowId),
    ok.

%% @doc Test merge synchronization for multiple merge without allocation
test_multiple_merge_without_allocation_sync() ->
    %% Simulate synchronization at multiple merge points
    %% without resource allocation

    %% Track merge point completion
    Merge1Complete = erlang:make_ref(),
    Merge2Complete = erlang:make_ref(),

    %% Simulate parallel execution to merge point 1
    spawn(fun() ->
        lists:foreach(fun(_) ->
            timer:sleep(10),
            yawl_mock_resource_manager:record_workitem_complete(
                <<"$sync_merge1_wi">>)
        end, lists:seq(1, 3)),
        erlang:send_after(50, self(), Merge1Complete)
    end),

    %% Simulate parallel execution to merge point 2
    spawn(fun() ->
        lists:foreach(fun(_) ->
            timer:sleep(15),
            yawl_mock_resource_manager:record_workitem_complete(
                <<"$sync_merge2_wi">>)
        end, lists:seq(1, 3)),
        erlang:send_after(50, self(), Merge2Complete)
    end),

    %% Wait for sync
    timer:sleep(200),

    %% Verify completion tracking
    ?assertEqual(3, length(yawl_mock_resource_manager:get_completed_workitems(
        <<"$sync_merge1_wi">>))),
    ?assertEqual(3, length(yawl_mock_resource_manager:get_completed_workitems(
        <<"$sync_merge2_wi">>))),
    ok.

%%====================================================================
%% Pattern 42: Deferred Choice With Allocation Tests
%%====================================================================

%% @doc Test the complete resource lifecycle for deferred choice with allocation
test_deferred_choice_with_allocation_lifecycle() ->
    %% Create resources for different choice options
    {ok, ResourceA} = yawl_mock_resource_manager:register_resource(
        <<"choice_resource_a">>, service, #{
            max_capacity => 1,
            capabilities => [choice_a]
        }),
    {ok, ResourceB} = yawl_mock_resource_manager:register_resource(
        <<"choice_resource_b">>, service, #{
            max_capacity => 1,
            capabilities => [choice_b]
        }),

    WorkflowId = <<"workflow_deferred_choice_alloc">>,
    yawl_mock_resource_manager:start_workflow_simulation(
        WorkflowId, deferred_choice_with_allocation),

    %% Defer choice until resource is available
    %% Simulate choosing option A
    WorkitemA = <<"$deferred_choice_a">>,
    {ok, ResourceA, _} = yawl_mock_resource_manager:allocate_resource(
        WorkitemA, [choice_a]),

    %% Execute chosen option
    yawl_mock_resource_manager:record_workitem_start(WorkitemA),
    yawl_mock_resource_manager:record_workitem_complete(WorkitemA),

    %% Release resource
    ok = yawl_mock_resource_manager:release_resource(WorkitemA),

    %% Verify resource B remains untouched
    {ok, StateB} = yawl_mock_resource_manager:get_resource_state(ResourceB),
    ?assertEqual(0, maps:get(current_load, StateB)),

    {ok, completed} = yawl_mock_resource_manager:end_workflow_simulation(WorkflowId),

    %% Cleanup
    ok = yawl_mock_resource_manager:unregister_resource(ResourceA),
    ok = yawl_mock_resource_manager:unregister_resource(ResourceB),
    ok.

%% @doc Test deferred choice with resources
test_deferred_choice_with_allocation_choice() ->
    %% Create resources with different capabilities
    {ok, Resource1} = yawl_mock_resource_manager:register_resource(
        <<"option1_resource">>, service, #{
            max_capacity => 1,
            capabilities => [option1]
        }),
    {ok, Resource2} = yawl_mock_resource_manager:register_resource(
        <<"option2_resource">>, service, #{
            max_capacity => 1,
            capabilities => [option2]
        }),
    {ok, Resource3} = yawl_mock_resource_manager:register_resource(
        <<"option3_resource">>, service, #{
            max_capacity => 1,
            capabilities => [option3]
        }),

    %% Simulate evaluating options at runtime
    AvailableOptions = [
        {option1, Resource1},
        {option2, Resource2},
        {option3, Resource3}
    ],

    %% Choose option 2
    {Choice, Resource} = lists:keyfind(option2, 1, AvailableOptions),

    Workitem = <<"$deferred_wi">>,
    {ok, Allocated, _} = yawl_mock_resource_manager:allocate_resource(
        Workitem, [Choice]),
    ?assertEqual(Resource, Allocated),

    %% Execute
    yawl_mock_resource_manager:record_workitem_start(Workitem),
    yawl_mock_resource_manager:record_workitem_complete(Workitem),
    ok = yawl_mock_resource_manager:release_resource(Workitem),

    %% Cleanup
    ok = yawl_mock_resource_manager:unregister_resource(Resource1),
    ok = yawl_mock_resource_manager:unregister_resource(Resource2),
    ok = yawl_mock_resource_manager:unregister_resource(Resource3),
    ok.

%% @doc Test resource pool exhaustion for deferred choice with allocation
test_deferred_choice_with_allocation_exhaustion() ->
    %% Create limited resources for choices
    {ok, Resource1} = yawl_mock_resource_manager:register_resource(
        <<"exhausted_option1">>, service, #{
            max_capacity => 0,  %% Already at capacity
            capabilities => [exhausted_choice1]
        }),
    {ok, Resource2} = yawl_mock_resource_manager:register_resource(
        <<"available_option2">>, service, #{
            max_capacity => 1,
            capabilities => [exhausted_choice2]
        }),

    %% First choice should fail
    WI1 = <<"$exhausted_choice1">>,
    ?assertMatch({error, no_available_resources},
        yawl_mock_resource_manager:allocate_resource(WI1, [exhausted_choice1])),

    %% Second choice should succeed
    WI2 = <<"$exhausted_choice2">>,
    {ok, Resource2, _} = yawl_mock_resource_manager:allocate_resource(
        WI2, [exhausted_choice2]),

    %% Cleanup
    ok = yawl_mock_resource_manager:release_resource(WI2),
    ok = yawl_mock_resource_manager:unregister_resource(Resource1),
    ok = yawl_mock_resource_manager:unregister_resource(Resource2),
    ok.

%% @doc Test resource contention on deferred choice
test_deferred_choice_with_allocation_contention() ->
    %% Create a shared resource for multiple deferred choices
    {ok, SharedResource} = yawl_mock_resource_manager:register_resource(
        <<"shared_choice_resource">>, service, #{
            max_capacity => 1,
            capabilities => [shared_choice]
        }),

    %% First workflow makes a choice and allocates
    WI1 = <<"$choice_contention_1">>,
    {ok, SharedResource, _} = yawl_mock_resource_manager:allocate_resource(
        WI1, [shared_choice]),

    %% Second workflow's choice is blocked
    WI2 = <<"$choice_contention_2">>,
    ?assertMatch({error, no_available_resources},
        yawl_mock_resource_manager:allocate_resource(WI2, [shared_choice])),

    %% First completes
    ok = yawl_mock_resource_manager:release_resource(WI1),

    %% Second can now proceed
    {ok, SharedResource, _} = yawl_mock_resource_manager:allocate_resource(
        WI2, [shared_choice]),

    %% Cleanup
    ok = yawl_mock_resource_manager:release_resource(WI2),
    ok = yawl_mock_resource_manager:unregister_resource(SharedResource),
    ok.

%%====================================================================
%% Pattern 43: Deferred Choice Without Allocation Tests
%%====================================================================

%% @doc Test basic execution for deferred choice without allocation
test_deferred_choice_without_allocation_basic() ->
    WorkflowId = <<"workflow_deferred_choice_no_alloc">>,
    yawl_mock_resource_manager:start_workflow_simulation(
        WorkflowId, deferred_choice_without_allocation),

    %% Simulate deferred choice without resource allocation
    %% Choose option at runtime
    Choice = option_a,
    Workitem = <<"$deferred_no_alloc_wi">>,

    yawl_mock_resource_manager:record_choice(Workitem, Choice),
    yawl_mock_resource_manager:record_workitem_start(Workitem),
    yawl_mock_resource_manager:record_workitem_complete(Workitem),

    %% Verify choice was recorded
    {ok, RecordedChoice} = yawl_mock_resource_manager:get_workitem_choice(Workitem),
    ?assertEqual(Choice, RecordedChoice),

    {ok, completed} = yawl_mock_resource_manager:end_workflow_simulation(WorkflowId),
    ok.

%% @doc Test deferred decision for deferred choice without allocation
test_deferred_choice_without_allocation_decision() ->
    %% Simulate runtime decision making
    DecisionCriteria = #{
        priority => high,
        urgency => immediate,
        complexity => low
    },

    %% Evaluate options based on criteria
    Choice = case DecisionCriteria of
        #{priority := high, urgency := immediate} -> fast_path;
        #{priority := normal} -> standard_path;
        _ -> default_path
    end,

    ?assertEqual(fast_path, Choice),

    %% Execute without resource allocation
    Workitem = <<"$deferred_decision_wi">>,
    yawl_mock_resource_manager:record_choice(Workitem, Choice),
    yawl_mock_resource_manager:record_workitem_start(Workitem),
    yawl_mock_resource_manager:record_workitem_complete(Workitem),

    ok.

%%====================================================================
%% Mock Resource Manager Tests
%%====================================================================

%% @doc Test mock resource manager basic operations
test_mock_resource_manager_basic() ->
    %% Register resource
    {ok, ResourceId} = yawl_mock_resource_manager:register_resource(
        <<"test_basic">>, service, #{max_capacity => 5}),

    %% Allocate
    WI = <<"$test_basic_wi">>,
    {ok, AllocatedId, _} = yawl_mock_resource_manager:allocate_resource(
        WI, [any_task]),
    ?assertEqual(ResourceId, AllocatedId),

    %% Get state
    {ok, State} = yawl_mock_resource_manager:get_resource_state(ResourceId),
    ?assertEqual(1, maps:get(current_load, State)),

    %% Release
    ok = yawl_mock_resource_manager:release_resource(WI),
    {ok, StateAfter} = yawl_mock_resource_manager:get_resource_state(ResourceId),
    ?assertEqual(0, maps:get(current_load, StateAfter)),

    %% Unregister
    ok = yawl_mock_resource_manager:unregister_resource(ResourceId),
    ?assertMatch({error, _}, yawl_mock_resource_manager:get_resource_state(ResourceId)),
    ok.

%% @doc Test mock resource manager allocation strategies
test_mock_resource_manager_strategies() ->
    %% Test least_loaded strategy
    ok = yawl_mock_resource_manager:set_allocation_strategy(least_loaded),

    {ok, R1} = yawl_mock_resource_manager:register_resource(
        <<"least_loaded_1">>, service, #{max_capacity => 10}),
    {ok, R2} = yawl_mock_resource_manager:register_resource(
        <<"least_loaded_2">>, service, #{max_capacity => 10}),

    %% Allocate to R1
    WI1 = <<"$strategy_wi_1">>,
    {ok, R1, _} = yawl_mock_resource_manager:allocate_resource(WI1, [any_task]),

    %% Next allocation should prefer R2 (least loaded)
    WI2 = <<"$strategy_wi_2">>,
    {ok, Allocated, _} = yawl_mock_resource_manager:allocate_resource(WI2, [any_task]),
    ?assertEqual(R2, Allocated),

    %% Cleanup
    ok = yawl_mock_resource_manager:release_resource(WI1),
    ok = yawl_mock_resource_manager:release_resource(WI2),
    ok = yawl_mock_resource_manager:unregister_resource(R1),
    ok = yawl_mock_resource_manager:unregister_resource(R2),
    ok.

%% @doc Test mock resource manager contention handling
test_mock_resource_manager_contention() ->
    %% Create a resource pool
    {ok, Pool} = yawl_mock_resource_manager:register_resource(
        <<"contention_pool">>, service, #{max_capacity => 3}),

    %% Allocate to capacity
    WIs = [<<"$cont_wi_", (integer_to_binary(I))/binary>> || I <- lists:seq(1, 5)],

    Results = lists:map(fun(WI) ->
        yawl_mock_resource_manager:allocate_resource(WI, [any_task])
    end, WIs),

    %% First 3 succeed, last 2 fail
    ?assertEqual(3, length([ok || {ok, _, _} <- Results])),
    ?assertEqual(2, length([error || {error, _} <- Results])),

    %% Release all
    lists:foreach(fun(WI) ->
        case yawl_mock_resource_manager:get_allocated_resource(WI) of
            {ok, _} -> yawl_mock_resource_manager:release_resource(WI);
            _ -> ok
        end
    end, WIs),

    %% Now all should succeed
    Results2 = lists:map(fun(WI) ->
        yawl_mock_resource_manager:allocate_resource(WI, [any_task])
    end, WIs),

    ?assertEqual(5, length([ok || {ok, _, _} <- Results2])),

    %% Cleanup
    lists:foreach(fun(WI) -> yawl_mock_resource_manager:release_resource(WI) end, WIs),
    ok = yawl_mock_resource_manager:unregister_resource(Pool),
    ok.

%%====================================================================
%% End-to-End Simulation Tests
%%====================================================================

%% @doc Test end-to-end resource flow through a workflow
test_end_to_end_resource_flow() ->
    %% Setup resource pool
    {ok, Processor} = yawl_mock_resource_manager:register_resource(
        <<"e2e_processor">>, service, #{
            max_capacity => 2,
            capabilities => [process]
        }),

    %% Simulate complete workflow with multiple tasks
    WorkflowId = <<"e2e_workflow">>,
    yawl_mock_resource_manager:start_workflow_simulation(
        WorkflowId, implicit_merge_with_allocation),

    %% Task 1: Allocate and execute
    WI1 = <<"$e2e_task_1">>,
    {ok, Processor, _} = yawl_mock_resource_manager:allocate_resource(
        WI1, [process]),
    yawl_mock_resource_manager:record_workitem_start(WI1),
    timer:sleep(10),
    yawl_mock_resource_manager:record_workitem_complete(WI1),
    ok = yawl_mock_resource_manager:release_resource(WI1),

    %% Task 2: Allocate and execute
    WI2 = <<"$e2e_task_2">>,
    {ok, Processor, _} = yawl_mock_resource_manager:allocate_resource(
        WI2, [process]),
    yawl_mock_resource_manager:record_workitem_start(WI2),
    timer:sleep(10),
    yawl_mock_resource_manager:record_workitem_complete(WI2),
    ok = yawl_mock_resource_manager:release_resource(WI2),

    %% Verify workflow completion
    {ok, completed} = yawl_mock_resource_manager:end_workflow_simulation(WorkflowId),

    %% Verify resource state
    {ok, FinalState} = yawl_mock_resource_manager:get_resource_state(Processor),
    ?assertEqual(0, maps:get(current_load, FinalState)),
    ?assertEqual(available, maps:get(allocation_status, FinalState)),

    %% Cleanup
    ok = yawl_mock_resource_manager:unregister_resource(Processor),
    ok.

%% @doc Test stress on resource pool
test_stress_resource_pool() ->
    %% Create a small resource pool
    {ok, SmallPool} = yawl_mock_resource_manager:register_resource(
        <<"stress_pool">>, service, #{
            max_capacity => 3,
            capabilities => [stress_task]
        }),

    %% Simulate high load
    NumWorkitems = 20,
    WIs = [<<"$stress_wi_", (integer_to_binary(I))/binary>>
           || I <- lists:seq(1, NumWorkitems)],

    %% Allocate all
    AllocResults = lists:map(fun(WI) ->
        yawl_mock_resource_manager:allocate_resource(WI, [stress_task])
    end, WIs),

    %% Count successes and failures
    SuccessCount = length([ok || {ok, _, _} <- AllocResults]),
    FailCount = length([error || {error, _} <- AllocResults]),

    ?assertEqual(3, SuccessCount),
    ?assertEqual(17, FailCount),

    %% Release and reallocate
    lists:foreach(fun(WI) ->
        case yawl_mock_resource_manager:get_allocated_resource(WI) of
            {ok, _} -> yawl_mock_resource_manager:release_resource(WI);
            _ -> ok
        end
    end, WIs),

    %% Now all should succeed
    AllocResults2 = lists:map(fun(WI) ->
        yawl_mock_resource_manager:allocate_resource(WI, [stress_task])
    end, WIs),

    SuccessCount2 = length([ok || {ok, _, _} <- AllocResults2]),
    ?assertEqual(NumWorkitems, SuccessCount2),

    %% Cleanup
    lists:foreach(fun(WI) -> yawl_mock_resource_manager:release_resource(WI) end, WIs),
    ok = yawl_mock_resource_manager:unregister_resource(SmallPool),
    ok.
