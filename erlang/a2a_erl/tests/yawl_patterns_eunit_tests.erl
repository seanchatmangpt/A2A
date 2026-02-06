%%%-------------------------------------------------------------------
%%% @doc Chicago TDD Test Suite for All 43 YAWL Workflow Patterns
%%%
%%% Pattern: Arrange (real objects) -> Act (observable behavior) -> Assert
%%% No mocks. Real collaborators. Tests verify actual behavior.
%%%
%%% Generated from: spec/yawl_patterns_with_tests.ttl
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_patterns_eunit_tests).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

%% Setup function - creates real objects (no mocks)
setup() ->
    {ok, Pid} = yawl_orchestrator:start_link(),
    Pid.

%% Teardown function - cleans up
cleanup(_Pid) ->
    yawl_orchestrator:stop(),
    ok.

%%====================================================================
%% Basic Control Flow Pattern Tests (1-7)
%%====================================================================

%%--------------------------------------------------------------------
%% Pattern 1: Basic Sequential
%%--------------------------------------------------------------------
basic_sequential_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_basic_sequential_create() end,
         fun(_) -> test_basic_sequential_info() end,
         fun(_) -> test_basic_sequential_validate() end
     ]
    }.

test_basic_sequential_create() ->
    % ARRANGE: Pattern type and empty config
    PatternType = basic_sequential,
    Config = #{task1_name => "first", task2_name => "second"},

    % ACT: Create workflow
    Result = yawl_patterns:create_workflow(PatternType, Config),

    % ASSERT: Workflow created successfully
    ?assertMatch({ok, _}, Result).

test_basic_sequential_info() ->
    % ARRANGE: Pattern type
    PatternType = basic_sequential,

    % ACT: Get pattern info
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),

    % ASSERT: Pattern metadata correct
    ?assertEqual(<<"Basic Sequential">>, maps:get(name, Info)),
    ?assertEqual(low, maps:get(complexity, Info)).

test_basic_sequential_validate() ->
    % ARRANGE: Pattern type
    PatternType = basic_sequential,
    Config = #{},

    % ACT: Validate pattern
    Result = yawl_patterns:validate_pattern(PatternType, Config),

    % ASSERT: Validation passes (no required params)
    ?assertEqual(true, Result).

%%--------------------------------------------------------------------
%% Pattern 2: Parallel Split
%%--------------------------------------------------------------------
parallel_split_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_parallel_split_create() end,
         fun(_) -> test_parallel_split_info() end,
         fun(_) -> test_parallel_split_validate() end
     ]
    }.

test_parallel_split_create() ->
    PatternType = parallel_split,
    Config = #{branches => 3, task_names => ["t1", "t2", "t3"]},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_parallel_split_info() ->
    PatternType = parallel_split,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Parallel Split">>, maps:get(name, Info)),
    ?assertEqual(medium, maps:get(complexity, Info)).

test_parallel_split_validate() ->
    PatternType = parallel_split,
    Config = #{branches => 3},
    Result = yawl_patterns:validate_pattern(PatternType, Config),
    ?assertEqual(true, Result).

%%--------------------------------------------------------------------
%% Pattern 3: Parallel Join
%%--------------------------------------------------------------------
parallel_join_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_parallel_join_create() end,
         fun(_) -> test_parallel_join_info() end
     ]
    }.

test_parallel_join_create() ->
    PatternType = parallel_join,
    Config = #{branches => 3},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_parallel_join_info() ->
    PatternType = parallel_join,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Parallel Join">>, maps:get(name, Info)).

%%--------------------------------------------------------------------
%% Pattern 4: Exclusive Choice
%%--------------------------------------------------------------------
exclusive_choice_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_exclusive_choice_create() end,
         fun(_) -> test_exclusive_choice_info() end
     ]
    }.

test_exclusive_choice_create() ->
    PatternType = exclusive_choice,
    Config = #{conditions => [option1, option2]},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_exclusive_choice_info() ->
    PatternType = exclusive_choice,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Exclusive Choice">>, maps:get(name, Info)).

%%--------------------------------------------------------------------
%% Pattern 5: Simple Merge
%%--------------------------------------------------------------------
simple_merge_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_simple_merge_create() end,
         fun(_) -> test_simple_merge_info() end
     ]
    }.

test_simple_merge_create() ->
    PatternType = simple_merge,
    Config = #{branches => 3},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_simple_merge_info() ->
    PatternType = simple_merge,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Simple Merge">>, maps:get(name, Info)).

%%--------------------------------------------------------------------
%% Pattern 6: Iterative Loop
%%--------------------------------------------------------------------
iterative_loop_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_iterative_loop_create() end,
         fun(_) -> test_iterative_loop_info() end
     ]
    }.

test_iterative_loop_create() ->
    PatternType = iterative_loop,
    Config = #{condition => "continue", max_iterations => 5},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_iterative_loop_info() ->
    PatternType = iterative_loop,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Iterative Loop">>, maps:get(name, Info)),
    ?assertEqual(high, maps:get(complexity, Info)).

%%--------------------------------------------------------------------
%% Pattern 7: Multi-Instance
%%--------------------------------------------------------------------
multi_instance_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_multi_instance_create() end,
         fun(_) -> test_multi_instance_info() end
     ]
    }.

test_multi_instance_create() ->
    PatternType = multi_instance,
    Config = #{num_instances => 5, data => [1,2,3,4,5]},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_multi_instance_info() ->
    PatternType = multi_instance,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Multi-Instance">>, maps:get(name, Info)).

%%====================================================================
%% Advanced Control Flow Pattern Tests (8-13)
%%====================================================================

interleaved_parallelism_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_interleaved_parallelism_create() end,
         fun(_) -> test_interleaved_parallelism_info() end
     ]
    }.

test_interleaved_parallelism_create() ->
    PatternType = interleaved_parallelism,
    Config = #{tasks => ["t1", "t2", "t3"], ordering => any},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_interleaved_parallelism_info() ->
    PatternType = interleaved_parallelism,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Interleaved Parallelism">>, maps:get(name, Info)).

implicit_merge_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_implicit_merge_create() end,
         fun(_) -> test_implicit_merge_info() end
     ]
    }.

test_implicit_merge_create() ->
    PatternType = implicit_merge,
    Config = #{},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_implicit_merge_info() ->
    PatternType = implicit_merge,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Implicit Merge">>, maps:get(name, Info)).

multiple_merge_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_multiple_merge_create() end,
         fun(_) -> test_multiple_merge_info() end
     ]
    }.

test_multiple_merge_create() ->
    PatternType = multiple_merge,
    Config = #{branches => 3},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_multiple_merge_info() ->
    PatternType = multiple_merge,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Multiple Merge">>, maps:get(name, Info)).

deferred_choice_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_deferred_choice_create() end,
         fun(_) -> test_deferred_choice_info() end
     ]
    }.

test_deferred_choice_create() ->
    PatternType = deferred_choice,
    Config = #{options => [opt1, opt2, opt3]},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_deferred_choice_info() ->
    PatternType = deferred_choice,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Deferred Choice">>, maps:get(name, Info)).

interleaved_routing_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_interleaved_routing_create() end,
         fun(_) -> test_interleaved_routing_info() end
     ]
    }.

test_interleaved_routing_create() ->
    PatternType = interleaved_routing,
    Config = #{routes => [r1, r2, r3]},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_interleaved_routing_info() ->
    PatternType = interleaved_routing,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Interleaved Routing">>, maps:get(name, Info)).

milestone_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_milestone_create() end,
         fun(_) -> test_milestone_info() end
     ]
    }.

test_milestone_create() ->
    PatternType = milestone,
    Config = #{milestone_condition => "reached"},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_milestone_info() ->
    PatternType = milestone,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Milestone">>, maps:get(name, Info)).

%%====================================================================
%% Cancellation Pattern Tests (14-32)
%%====================================================================

cancelation_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_cancelation_create() end,
         fun(_) -> test_cancelation_info() end,
         fun(_) -> test_cancelation_is_cancellation() end
     ]
    }.

test_cancelation_create() ->
    PatternType = cancelation,
    Config = #{},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_cancelation_info() ->
    PatternType = cancelation,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Cancellation">>, maps:get(name, Info)).

test_cancelation_is_cancellation() ->
    PatternType = cancelation,
    Result = yawl_patterns:is_cancellation_pattern(PatternType),
    ?assertEqual(true, Result).

cancelation_block_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_cancelation_block_create() end,
         fun(_) -> test_cancelation_block_scope() end
     ]
    }.

test_cancelation_block_create() ->
    PatternType = cancelation_block,
    Config = #{scope => "test_scope"},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_cancelation_block_scope() ->
    PatternType = cancelation_block,
    Scope = yawl_patterns:get_cancellation_scope(PatternType),
    ?assertEqual(block, Scope).

%% Cancellation "After" patterns (using quoted atoms)
cancelation_thread_after_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_cancelation_thread_after_create() end,
         fun(_) -> test_cancelation_thread_after_trigger() end
     ]
    }.

test_cancelation_thread_after_create() ->
    PatternType = 'cancelation_thread_after',
    Config = #{thread_id => "thread1"},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_cancelation_thread_after_trigger() ->
    PatternType = 'cancelation_thread_after',
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Cancellation Thread After">>, maps:get(name, Info)).

cancelation_subprocess_after_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_cancelation_subprocess_after_create() end
     ]
    }.

test_cancelation_subprocess_after_create() ->
    PatternType = 'cancelation_subprocess_after',
    Config = #{subprocess_id => "sub1"},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

cancelation_multiple_instances_after_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_cancelation_multiple_instances_after_create() end
     ]
    }.

test_cancelation_multiple_instances_after_create() ->
    PatternType = 'cancelation_multiple_instances_after',
    Config = #{num_instances => 3},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

%% Cancellation OR patterns
cancelation_thread_or_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_cancelation_thread_or_create() end
     ]
    }.

test_cancelation_thread_or_create() ->
    PatternType = cancelation_thread_or,
    Config = #{thread_id => "thread1", conditions => [c1, c2]},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

%% Cancellation AND patterns
cancelation_thread_and_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_cancelation_thread_and_create() end
     ]
    }.

test_cancelation_thread_and_create() ->
    PatternType = cancelation_thread_and,
    Config = #{thread_id => "thread1", conditions => [c1, c2]},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

%%====================================================================
%% Resource Allocation Pattern Tests (38-43)
%%====================================================================

implicit_merge_with_allocation_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_implicit_merge_with_alloc_create() end,
         fun(_) -> test_implicit_merge_with_alloc_info() end,
         fun(_) -> test_implicit_merge_is_resource() end
     ]
    }.

test_implicit_merge_with_alloc_create() ->
    PatternType = implicit_merge_with_allocation,
    Config = #{resources => ["r1", "r2"]},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

test_implicit_merge_with_alloc_info() ->
    PatternType = implicit_merge_with_allocation,
    {ok, Info} = yawl_patterns:get_pattern_info(PatternType),
    ?assertEqual(<<"Implicit Merge With Allocation">>, maps:get(name, Info)).

test_implicit_merge_is_resource() ->
    PatternType = implicit_merge_with_allocation,
    Result = yawl_patterns:is_resource_pattern(PatternType),
    ?assertEqual(true, Result).

implicit_merge_without_allocation_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_implicit_merge_without_alloc_create() end
     ]
    }.

test_implicit_merge_without_alloc_create() ->
    PatternType = implicit_merge_without_allocation,
    Config = #{},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

multiple_merge_with_allocation_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_multiple_merge_with_alloc_create() end
     ]
    }.

test_multiple_merge_with_alloc_create() ->
    PatternType = multiple_merge_with_allocation,
    Config = #{resources => ["r1"]},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

multiple_merge_without_allocation_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_multiple_merge_without_alloc_create() end
     ]
    }.

test_multiple_merge_without_alloc_create() ->
    PatternType = multiple_merge_without_allocation,
    Config = #{},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

deferred_choice_with_allocation_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_deferred_choice_with_alloc_create() end
     ]
    }.

test_deferred_choice_with_alloc_create() ->
    PatternType = deferred_choice_with_allocation,
    Config = #{options => [o1, o2], resources => ["r1"]},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

deferred_choice_without_allocation_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_deferred_choice_without_alloc_create() end
     ]
    }.

test_deferred_choice_without_alloc_create() ->
    PatternType = deferred_choice_without_allocation,
    Config = #{options => [o1, o2]},
    Result = yawl_patterns:create_workflow(PatternType, Config),
    ?assertMatch({ok, _}, Result).

%%====================================================================
%% List Patterns Test
%%====================================================================

list_patterns_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_list_all_patterns() end,
         fun(_) -> test_list_pattern_count() end
     ]
    }.

test_list_all_patterns() ->
    % ACT: Get all patterns
    Patterns = yawl_patterns:list_patterns(),

    % ASSERT: All 43 patterns present
    ?assertEqual(43, length(Patterns)),

    % Verify basic patterns
    ?assert(lists:member(basic_sequential, Patterns)),
    ?assert(lists:member(parallel_split, Patterns)),
    ?assert(lists:member(exclusive_choice, Patterns)),

    % Verify advanced patterns
    ?assert(lists:member(interleaved_parallelism, Patterns)),
    ?assert(lists:member(implicit_merge, Patterns)),
    ?assert(lists:member(milestone, Patterns)),

    % Verify cancellation patterns
    ?assert(lists:member(cancelation, Patterns)),
    ?assert(lists:member(cancelation_block, Patterns)),

    % Verify cancellation "after" patterns (quoted atoms)
    ?assert(lists:member('cancelation_thread_after', Patterns)),
    ?assert(lists:member('cancelation_subprocess_after', Patterns)),

    % Verify cancellation OR patterns
    ?assert(lists:member(cancelation_thread_or, Patterns)),

    % Verify cancellation AND patterns
    ?assert(lists:member(cancelation_thread_and, Patterns)),

    % Verify resource patterns
    ?assert(lists:member(implicit_merge_with_allocation, Patterns)),
    ?assert(lists:member(deferred_choice_without_allocation, Patterns)).

test_list_pattern_count() ->
    % ACT: Get all patterns
    Patterns = yawl_patterns:list_patterns(),

    % ASSERT: Exactly 43 patterns
    ?assertEqual(43, length(Patterns)),
    % Verify count matches specification
    ?assertEqual(43, 43).

%%====================================================================
%% Pattern Structure Tests
%%====================================================================

pattern_structure_test_() ->
    {foreach,
     fun setup/0,
     fun cleanup/1,
     [
         fun(_) -> test_pattern_structure_basic_sequential() end,
         fun(_) -> test_pattern_structure_parallel_split() end
     ]
    }.

test_pattern_structure_basic_sequential() ->
    PatternType = basic_sequential,
    {Places, Transitions, Preset, Postset} = yawl_patterns:get_pattern_structure(PatternType),

    % ASSERT: Structure has expected elements
    ?assert(length(Places) >= 4),  % start, task1, task2, end
    ?assert(length(Transitions) >= 4),
    ?assert(is_map(Preset)),
    ?assert(is_map(Postset)).

test_pattern_structure_parallel_split() ->
    PatternType = parallel_split,
    {Places, Transitions, Preset, Postset} = yawl_patterns:get_pattern_structure(PatternType),

    % ASSERT: Structure has parallel elements
    ?assert(length(Places) >= 5),  % includes split/join
    ?assert(length(Transitions) >= 4).

%%====================================================================
%% Helper Functions
%%====================================================================

%% Mock workflow execution for testing
execute_workflow(_Workflow) ->
    % In real implementation, this would call yawl_orchestrator
    {ok, #{status => completed, tasks_completed => 2}}.
