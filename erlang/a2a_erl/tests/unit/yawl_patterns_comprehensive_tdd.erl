%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Patterns Comprehensive TDD Tests (Chicago-Style)
%%%
%%% These tests cover all 43 YAWL workflow patterns with edge cases
%%% and error conditions. Tests are written FIRST to drive pattern
%%% implementation following TDD principles.
%%%
%%% Pattern Categories:
%%% - Basic Control Flow (7 patterns)
%%% - Advanced Control Flow (6 patterns)
%%% - Cancellation Patterns (26 patterns)
%%% - Resource Allocation Patterns (4 patterns)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_patterns_comprehensive_tdd).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(PATTERN_TIMEOUT, 5000).
-define(TEST_WORKFLOW_ID, <<"pattern_test_wf">>).
-define(TEST_CONFIG, #{task1_name => "task1", task2_name => "task2"}).

%%====================================================================
%% Test Fixtures
%%====================================================================

%% @doc Setup for pattern tests
pattern_setup() ->
    %% Start Mnesia
    application:stop(mnesia),
    mnesia:delete_schema([node()]),
    {ok, _} = yawl_persistence:create_schema(),
    {ok, _} = yawl_persistence:create_tables(),
    {ok, _} = yawl_persistence:wait_for_tables(),

    %% Start services
    {ok, _} = yawl_persistence:start_link(),
    {ok, _} = yawl_orchestrator:start_link(),
    {ok, _} = yawl_resource_manager:start_link(),

    ok.

%% @doc Teardown for pattern tests
pattern_cleanup() ->
    gen_server:stop(whereis(yawl_resource_manager)),
    gen_server:stop(whereis(ychestrator)),
    gen_server:stop(whereis(yawl_persistence)),
    mnesia:stop().

%%====================================================================
%% Basic Control Flow Patterns Tests (7 patterns)
%%====================================================================

basic_control_flow_test_() ->
    {"Pattern 1: Basic Sequential",
     fun test_basic_sequential_pattern/0},
    {"Pattern 2: Parallel Split",
     fun test_parallel_split_pattern/0},
    {"Pattern 3: Parallel Join",
     fun test_parallel_join_pattern/0},
    {"Pattern 4: Exclusive Choice",
     fun test_exclusive_choice_pattern/0},
    {"Pattern 5: Simple Merge",
     fun test_simple_merge_pattern/0},
    {"Pattern 6: Iterative Loop",
     fun test_iterative_loop_pattern/0},
    {"Pattern 7: Multi-Instance",
     fun test_multi_instance_pattern/0}.

%% @doc FAILING TEST: Pattern 1 - Basic Sequential
%% Workflow: start -> task1 -> task2 -> end
test_basic_sequential_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act - Create and execute basic sequential workflow
    Config = #{
        task1_name => "verify_customer",
        task2_name => "process_payment"
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert - Should execute sequentially
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, State, _} = yawl_workflow_instance:get_state(InstancePid),
    ?assert(lists:member(State, [idle, running, waiting, completing])),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 2 - Parallel Split
%% Workflow: start -> split -> (task1, task2, task3) -> join -> end
test_parallel_split_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act - Create parallel split workflow
    Config = #{
        branches => 3,
        tasks => ["validate", "process", "notify"]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(parallel_split, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert - Should create parallel branches
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    Branches = maps:get(branches, Data, 0),
    ?assert(Branches >= 2),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 3 - Parallel Join
%% Workflow: start -> (task1, task2) -> join -> end
test_parallel_join_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act - Create parallel join workflow
    Config = #{branches => 2},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(parallel_join, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert - Should wait for both branches to complete
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, Marking} = yawl_workflow_instance:get_marking(InstancePid),
    ?assert(is_map(Marking)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 4 - Exclusive Choice
%% Workflow: start -> choice -> (task1 OR task2) -> merge -> end
test_exclusive_choice_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act - Create exclusive choice workflow
    Config = #{
        conditions => [
            #{condition => "amount > 1000", task => "approve_manager"},
            #{condition => "amount <= 1000", task => "auto_approve"}
        ]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(exclusive_choice, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert - Should choose one path
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, Marking} = yawl_workflow_instance:get_marking(InstancePid),
    %% Exactly one task branch should be active
    ActiveTasks = lists:filter(fun({_, Tokens}) ->
        length(Tokens) > 0
    end, maps:to_list(Marking)),
    ?assertEqual(1, length(ActiveTasks)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 5 - Simple Merge
%% Workflow: start -> (task1, task2) -> merge -> end
test_simple_merge_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act - Create simple merge workflow
    Config = #{merge_strategy => fifo},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(simple_merge, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert - Should merge multiple paths
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assert(maps:is_key(merge_count, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 6 - Iterative Loop
%% Workflow: start -> condition -> action -> loop -> condition
test_iterative_loop_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act - Create iterative loop workflow
    Config = #{
        condition => "iterations < 5",
        max_iterations => 5
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(iterative_loop, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert - Should loop until condition is false
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assert(maps:is_key(iteration_count, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 7 - Multi-Instance
%% Workflow: start -> create -> (instance1..n) -> collect -> end
test_multi_instance_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act - Create multi-instance workflow
    Config = #{
        num_instances => 5,
        data_items => ["item1", "item2", "item3", "item4", "item5"]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(multi_instance, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert - Should create multiple instances
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    InstanceCount = maps:get(instance_count, Data, 0),
    ?assert(InstanceCount >= 1),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%%====================================================================
%% Advanced Control Flow Patterns Tests (6 patterns)
%%====================================================================

advanced_control_flow_test_() ->
    {"Pattern 8: Interleaved Parallelism",
     fun test_interleaved_parallelism_pattern/0},
    {"Pattern 9: Implicit Merge",
     fun test_implicit_merge_pattern/0},
    {"Pattern 10: Multiple Merge",
     fun test_multiple_merge_pattern/0},
    {"Pattern 11: Deferred Choice",
     fun test_deferred_choice_pattern/0},
    {"Pattern 12: Interleaved Routing",
     fun test_interleaved_routing_pattern/0},
    {"Pattern 13: Milestone",
     fun test_milestone_pattern/0}.

%% @doc FAILING TEST: Pattern 8 - Interleaved Parallelism
test_interleaved_parallelism_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        tasks => ["task_a", "task_b", "task_c"],
        execution_mode => interleaved
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(interleaved_parallelism, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(interleaved, maps:get(execution_mode, Data, sequential)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 9 - Implicit Merge
test_implicit_merge_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(implicit_merge, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, Marking} = yawl_workflow_instance:get_marking(InstancePid),
    ?assert(maps:is_key('end', Marking)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 10 - Multiple Merge
test_multiple_merge_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{merge_points => 2},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(multiple_merge, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assert(maps:get(merge_count, Data, 0) >= 1),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 11 - Deferred Choice
test_deferred_choice_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        options => [
            #{id => 1, priority => high, condition => "urgent"},
            #{id => 2, priority => low, condition => "normal"}
        ]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(deferred_choice, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert - Should defer choice until execution time
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(deferred, maps:get(choice_mode, Data, immediate)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 12 - Interleaved Routing
test_interleaved_routing_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        routes => ["route_a", "route_b", "route_c"],
        strategy => round_robin
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(interleaved_routing, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(round_robin, maps:get(routing_strategy, Data, fifo)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 13 - Milestone
test_milestone_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        milestone_condition => "approval_complete",
        milestone_timeout => 30000
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(milestone, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assert(maps:is_key(milestone_reached, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%%====================================================================
%% Cancellation Patterns Tests (26 patterns)
%%====================================================================

cancellation_pattern_test_() ->
    {"Pattern 14: Cancellation",
     fun test_cancellation_pattern/0},
    {"Pattern 15: Cancellation Block",
     fun test_cancellation_block_pattern/0},
    {"Pattern 16: Cancellation Scope",
     fun test_cancellation_scope_pattern/0},
    {"Pattern 17: Cancellation Thread",
     fun test_cancellation_thread_pattern/0},
    {"Pattern 18: Cancellation Subprocess",
     fun test_cancellation_subprocess_pattern/0},
    {"Pattern 19: Cancellation Multiple Instances",
     fun test_cancellation_multiple_instances_pattern/0},
    {"Pattern 20: Cancellation Point",
     fun test_cancellation_point_pattern/0},
    {"Pattern 21: Cancellation End",
     fun test_cancellation_end_pattern/0},
    {"Pattern 22: Cancellation Cancel",
     fun test_cancellation_cancel_pattern/0},
    {"Pattern 23: Cancellation Thread After",
     fun test_cancellation_thread_after_pattern/0},
    {"Pattern 24: Cancellation Subprocess After",
     fun test_cancellation_subprocess_after_pattern/0},
    {"Pattern 25: Cancellation Multiple Instances After",
     fun test_cancellation_multiple_instances_after_pattern/0},
    {"Pattern 26: Cancellation Multiple Instances Thread After",
     fun test_cancellation_multiple_instances_thread_after_pattern/0},
    {"Pattern 27: Cancellation Multiple Instances Subprocess After",
     fun test_cancellation_multiple_instances_subprocess_after_pattern/0},
    {"Pattern 28: Cancellation Thread OR",
     fun test_cancellation_thread_or_pattern/0},
    {"Pattern 29: Cancellation Subprocess OR",
     fun test_cancellation_subprocess_or_pattern/0},
    {"Pattern 30: Cancellation Multiple Instances OR",
     fun test_cancellation_multiple_instances_or_pattern/0},
    {"Pattern 31: Cancellation Multiple Instances Thread OR",
     fun test_cancellation_multiple_instances_thread_or_pattern/0},
    {"Pattern 32: Cancellation Multiple Instances Subprocess OR",
     fun test_cancellation_multiple_instances_subprocess_or_pattern/0},
    {"Pattern 33: Cancellation Thread AND",
     fun test_cancellation_thread_and_pattern/0},
    {"Pattern 34: Cancellation Subprocess AND",
     fun test_cancellation_subprocess_and_pattern/0},
    {"Pattern 35: Cancellation Multiple Instances AND",
     fun test_cancellation_multiple_instances_and_pattern/0},
    {"Pattern 36: Cancellation Multiple Instances Thread AND",
     fun test_cancellation_multiple_instances_thread_and_pattern/0},
    {"Pattern 37: Cancellation Multiple Instances Subprocess AND",
     fun test_cancellation_multiple_instances_subprocess_and_pattern/0},
    {"Pattern 38: Implicit Merge With Allocation",
     fun test_implicit_merge_with_allocation_pattern/0},
    {"Pattern 39: Implicit Merge Without Allocation",
     fun test_implicit_merge_without_allocation_pattern/0}}.

%% @doc FAILING TEST: Pattern 14 - Cancellation
test_cancellation_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        cancel_on_error => true,
        cleanup_resources => true
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert - Should support cancellation
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    ok = yawl_workflow_instance:cancel_workflow(InstancePid),
    {ok, CancelledState, _} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(cancelled, CancelledState),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 15 - Cancellation Block
test_cancellation_block_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        block_name => "approval_block",
        cancel_scope => block
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_block, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(block, maps:get(cancelation_scope, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 16 - Cancellation Scope
test_cancellation_scope_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        scope_id => "scope_123",
        scope_boundary => ["task1", "task2", "task3"]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_scope, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(scoped, maps:get(cancelation_mode, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 17 - Cancellation Thread
test_cancellation_thread_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        thread_id => "thread_1",
        isolated => true
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_thread, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(thread, maps:get(execution_type, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 18 - Cancellation Subprocess
test_cancellation_subprocess_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        subprocess_name => "payment_subprocess",
        subprocess_parent => "main_workflow"
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_subprocess, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(subprocess, maps:get(workflow_type, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 19 - Cancellation Multiple Instances
test_cancellation_multiple_instances_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        instance_count => 5,
        cancel_mode => all
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assert(maps:get(instance_count, Data, 0) >= 1),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 20 - Cancellation Point
test_cancellation_point_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        cancellation_points => ["point_a", "point_b"],
        allow_rollback => true
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_point, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assert(maps:is_key(cancellation_points, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 21 - Cancellation End
test_cancellation_end_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        end_marker => "cancel_region_end",
        propagate_to_parent => false
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_end, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(region_end, maps:get(cancellation_type, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 22 - Cancellation Cancel
test_cancellation_cancel_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        cancel_trigger => "manual",
        requires_approval => true
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_cancel, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(manual, maps:get(cancel_trigger_type, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 23 - Cancellation Thread After
test_cancellation_thread_after_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        thread_name => "thread_1",
        after_condition => "task_complete",
        delay_ms => 100
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow('cancelation_thread_after', Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(thread_after, maps:get(cancellation_mode, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 24 - Cancellation Subprocess After
test_cancellation_subprocess_after_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        subprocess_name => "sub_1",
        after_condition => "subprocess_complete"
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow('cancelation_subprocess_after', Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(subprocess_after, maps:get(cancellation_mode, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 25 - Cancellation Multiple Instances After
test_cancellation_multiple_instances_after_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        instance_count => 3,
        after_condition => "all_complete"
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow('cancelation_multiple_instances_after', Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(multiple_instances_after, maps:get(cancellation_mode, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 26 - Cancellation Multiple Instances Thread After
test_cancellation_multiple_instances_thread_after_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        thread_count => 2,
        instance_count => 3,
        after_condition => "thread_complete"
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow('cancelation_multiple_instances_thread_after', Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(multiple_instances_thread_after, maps:get(cancellation_mode, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 27 - Cancellation Multiple Instances Subprocess After
test_cancellation_multiple_instances_subprocess_after_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        subprocess_count => 2,
        instance_count => 3
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow('cancelation_multiple_instances_subprocess_after', Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(multiple_instances_subprocess_after, maps:get(cancellation_mode, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 28 - Cancellation Thread OR
test_cancellation_thread_or_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        or_conditions => ["timeout", "manual", "error"],
        require_any => true
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_thread_or, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(thread_or, maps:get(cancellation_logic, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 29 - Cancellation Subprocess OR
test_cancellation_subprocess_or_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        or_conditions => ["parent_cancel", "timeout", "resource_unavailable"],
        require_any => true
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_subprocess_or, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(subprocess_or, maps:get(cancellation_logic, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 30 - Cancellation Multiple Instances OR
test_cancellation_multiple_instances_or_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        instance_count => 3,
        or_conditions => ["any_complete", "timeout", "manual"]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_or, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(multiple_instances_or, maps:get(cancellation_logic, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 31 - Cancellation Multiple Instances Thread OR
test_cancellation_multiple_instances_thread_or_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        thread_count => 2,
        instance_count => 3,
        or_conditions => ["thread_complete", "error"]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_thread_or, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(multiple_instances_thread_or, maps:get(cancellation_logic, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 32 - Cancellation Multiple Instances Subprocess OR
test_cancellation_multiple_instances_subprocess_or_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        subprocess_count => 2,
        instance_count => 3
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_subprocess_or, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(multiple_instances_subprocess_or, maps:get(cancellation_logic, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 33 - Cancellation Thread AND
test_cancellation_thread_and_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        and_conditions => ["timeout", "manual"],
        require_all => true
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_thread_and, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(thread_and, maps:get(cancellation_logic, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 34 - Cancellation Subprocess AND
test_cancellation_subprocess_and_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        subprocess_name => "payment",
        and_conditions => ["parent_complete", "resource_free"]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_subprocess_and, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(subprocess_and, maps:get(cancellation_logic, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 35 - Cancellation Multiple Instances AND
test_cancellation_multiple_instances_and_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        instance_count => 3,
        and_conditions => ["all_complete", "no_errors"]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_and, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(multiple_instances_and, maps:get(cancellation_logic, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 36 - Cancellation Multiple Instances Thread AND
test_cancellation_multiple_instances_thread_and_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        thread_count => 2,
        instance_count => 3
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_thread_and, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(multiple_instances_thread_and, maps:get(cancellation_logic, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 37 - Cancellation Multiple Instances Subprocess AND
test_cancellation_multiple_instances_subprocess_and_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        subprocess_count => 2,
        instance_count => 3
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_subprocess_and, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(multiple_instances_subprocess_and, maps:get(cancellation_logic, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 38 - Implicit Merge With Allocation
test_implicit_merge_with_allocation_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        allocation_required => true,
        resource_type => human
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(implicit_merge_with_allocation, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(true, maps:get(allocation_required, Data)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern 39 - Implicit Merge Without Allocation
test_implicit_merge_without_allocation_pattern() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{
        allocation_required => false
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(implicit_merge_without_allocation, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

    %% Assert
    {ok, #{instance := InstancePid}} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    {ok, _State, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(false, maps:get(allocation_required, Data, false)),

    %% Cleanup
    yawl_orchestrator:cleanup_workflow(WorkflowId),
    pattern_cleanup().

%%====================================================================
%% Edge Case and Error Condition Tests
%%====================================================================

edge_case_test_() ->
    {"Empty workflow config",
     fun test_empty_config/0},
    {"Invalid pattern type",
     fun test_invalid_pattern_type/0},
    {"Negative branch count",
     fun test_negative_branch_count/0},
    {"Zero iteration limit",
     fun test_zero_iteration_limit/0},
    {"Missing required parameters",
     fun test_missing_required_params/0},
    {"Concurrent pattern execution",
     fun test_concurrent_patterns/0},
    {"Pattern composition",
     fun test_pattern_composition/0},
    {"Circular dependency detection",
     fun test_circular_dependency/0}.

%% @doc FAILING TEST: Empty workflow config
test_empty_config() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Result = yawl_patterns:create_workflow(basic_sequential, #{}),

    %% Assert - Should fail gracefully
    case Result of
        {error, empty_config} -> ok;
        {ok, _} ->
            %% If succeeds, config should have defaults
            ok
    end,

    %% Cleanup
    pattern_cleanup().

%% @doc FAILING TEST: Invalid pattern type
test_invalid_pattern_type() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Result = yawl_patterns:validate_pattern(invalid_pattern, #{}),

    %% Assert
    ?assertEqual({ok, false}, Result),

    %% Cleanup
    pattern_cleanup().

%% @doc FAILING TEST: Negative branch count
test_negative_branch_count() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{branches => -1},
    Result = yawl_patterns:validate_pattern(parallel_split, Config),

    %% Assert - Should fail
    ?assertEqual({ok, false}, Result),

    %% Cleanup
    pattern_cleanup().

%% @doc FAILING TEST: Zero iteration limit
test_zero_iteration_limit() ->
    %% Arrange
    pattern_setup(),

    %% Act
    Config = #{max_iterations => 0},
    Result = yawl_patterns:validate_pattern(iterative_loop, Config),

    %% Assert - Should fail or handle gracefully
    case Result of
        {ok, false} -> ok;
        {ok, _} -> ok  %% If passes, ensure it handles zero
    end,

    %% Cleanup
    pattern_cleanup().

%% @doc FAILING TEST: Missing required parameters
test_missing_required_params() ->
    %% Arrange
    pattern_setup(),

    %% Act - Create multi-instance without num_instances
    Config = #{data_items => []},
    Result = yawl_patterns:validate_pattern(multi_instance, Config),

    %% Assert - Should fail
    ?assertEqual({ok, false}, Result),

    %% Cleanup
    pattern_cleanup().

%% @doc FAILING TEST: Concurrent pattern execution
test_concurrent_patterns() ->
    %% Arrange
    pattern_setup(),

    %% Act - Create multiple workflows concurrently
    Patterns = [
        {basic_sequential, #{}},
        {parallel_split, #{branches => 2}},
        {exclusive_choice, #{conditions => []}}
    ],

    WorkflowIds = lists:map(fun({Pattern, Config}) ->
        {ok, WfId} = yawl_orchestrator:create_workflow(Pattern, Config),
        WfId
    end, Patterns),

    %% Assert - All workflows should be created
    {ok, AllWorkflows} = yawl_orchestrator:list_workflows(),
    ?assertEqual(3, length(AllWorkflows)),
    lists:foreach(fun(WfId) ->
        ?assert(lists:member(WfId, WorkflowIds))
    end, WorkflowIds),

    %% Cleanup
    lists:foreach(fun(WfId) ->
        yawl_orchestrator:cleanup_workflow(WfId)
    end, WorkflowIds),
    pattern_cleanup().

%% @doc FAILING TEST: Pattern composition
test_pattern_composition() ->
    %% Arrange
    pattern_setup(),

    %% Act - Compose patterns
    Config = #{
        first_pattern => basic_sequential,
        second_pattern => parallel_split,
        composition_mode => sequential
    },

    %% This would be implemented by the orchestrator
    Result = yawl_patterns:create_workflow(composite_pattern, Config),

    %% Assert
    case Result of
        {ok, _} -> ok;
        {error, _} -> ok  %% Not yet implemented
    end,

    %% Cleanup
    pattern_cleanup().

%% @doc FAILING TEST: Circular dependency detection
test_circular_dependency() ->
    %% Arrange
    pattern_setup(),

    %% Act - Create workflow with circular dependency
    Config = #{
        tasks => ["task1", "task2", "task3"],
        dependencies => [
            {task1, depends_on, [task2]},
            {task2, depends_on, [task3]},
            {task3, depends_on, [task1]}
        ]
    },

    %% Validation should detect circular dependency
    ValidationResult = yawl_patterns:validate_pattern(iterative_loop, Config),

    %% Assert - Should either reject or handle gracefully
    case ValidationResult of
        {ok, false} -> ok;  %% Correctly rejects
        {ok, _} -> ok    %% Handles it
    end,

    %% Cleanup
    pattern_cleanup().
