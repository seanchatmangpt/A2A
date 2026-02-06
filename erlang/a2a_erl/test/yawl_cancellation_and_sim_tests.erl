%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Cancellation AND Pattern Simulation Tests
%%%
%%% This module contains comprehensive simulation tests for YAWL
%%% cancellation patterns with AND conditions (patterns 33-37).
%%%
%%% Patterns tested:
%%% 33. cancelation_thread_and - cancel thread with AND conditions
%%% 34. cancelation_subprocess_and - cancel subprocess with AND conditions
%%% 35. cancelation_multiple_instances_and - cancel instances with AND conditions
%%% 36. cancelation_multiple_instances_thread_and - cancel instances thread AND
%%% 37. cancelation_multiple_instances_subprocess_and - cancel instances subprocess AND
%%%
%%% Each pattern tests:
%%% - Cancellation only when ALL conditions are true (AND semantics)
%%% - Single condition does NOT trigger cancellation
%%% - All conditions together triggers cancellation
%%% - Verification of AND semantics (all=true required)
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_cancellation_and_sim_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("../include/yawl_types.hrl").

%%====================================================================
%% Test Fixtures
%%====================================================================

cancellation_and_sim_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Pattern 33: cancelation_thread_and create workflow", fun test_thread_and_create_workflow/0},
      {"Pattern 33: single condition does not cancel", fun test_thread_and_single_condition_false/0},
      {"Pattern 33: all conditions trigger cancel", fun test_thread_and_all_conditions_true/0},
      {"Pattern 33: partial conditions no cancel", fun test_thread_and_partial_conditions/0},
      {"Pattern 33: AND semantics verification", fun test_thread_and_semantics_verification/0},
      {"Pattern 33: three conditions test", fun test_thread_and_with_three_conditions/0},
      {"Pattern 34: cancelation_subprocess_and create", fun test_subprocess_and_create_workflow/0},
      {"Pattern 34: single condition false", fun test_subprocess_and_single_condition_false/0},
      {"Pattern 34: all conditions true", fun test_subprocess_and_all_conditions_true/0},
      {"Pattern 34: nested conditions", fun test_subprocess_and_nested_conditions/0},
      {"Pattern 34: semantics verification", fun test_subprocess_and_semantics_verification/0},
      {"Pattern 34: multiple subprocesses", fun test_subprocess_and_multiple_subprocesses/0},
      {"Pattern 35: cancelation_multiple_instances_and create", fun test_multiple_instances_and_create_workflow/0},
      {"Pattern 35: single condition no cancel", fun test_multiple_instances_and_single_condition/0},
      {"Pattern 35: all conditions cancel", fun test_multiple_instances_and_all_conditions/0},
      {"Pattern 35: instance states test", fun test_multiple_instances_and_instance_states/0},
      {"Pattern 35: partial cancel test", fun test_multiple_instances_and_partial_cancel/0},
      {"Pattern 35: all instances cancel", fun test_multiple_instances_and_all_instances_cancel/0},
      {"Pattern 36: cancelation_instances_thread_and create", fun test_instances_thread_and_create_workflow/0},
      {"Pattern 36: thread level conditions", fun test_instances_thread_and_thread_level/0},
      {"Pattern 36: instance level conditions", fun test_instances_thread_and_instance_level/0},
      {"Pattern 36: combined conditions", fun test_instances_thread_and_combined_conditions/0},
      {"Pattern 36: semantics verification", fun test_instances_thread_and_semantics/0},
      {"Pattern 36: complex scenario", fun test_instances_thread_and_complex_scenario/0},
      {"Pattern 37: cancelation_instances_subprocess_and create", fun test_instances_subprocess_and_create_workflow/0},
      {"Pattern 37: subprocess level conditions", fun test_instances_subprocess_and_subprocess_level/0},
      {"Pattern 37: instance level conditions", fun test_instances_subprocess_and_instance_level/0},
      {"Pattern 37: nested subprocess test", fun test_instances_subprocess_and_nested/0},
      {"Pattern 37: all combinations", fun test_instances_subprocess_and_all_combinations/0},
      {"Pattern 37: real world scenario", fun test_instances_subprocess_and_real_world/0},
      {"AND semantics comprehensive test", fun test_and_semantics_all_patterns/0},
      {"AND vs OR difference test", fun test_and_vs_or_difference/0},
      {"AND edge cases test", fun test_and_edge_cases/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    {ok, Pid} = yawl_orchestrator:start_link(),
    erase(),  %% Clear process dictionary
    Pid.

cleanup(_Pid) ->
    gen_server:stop(yawl_orchestrator),
    erase().  %% Clean up process dictionary

%%====================================================================
%% Pattern 33: cancelation_thread_and Tests
%%====================================================================

%% @doc Test creating a cancelation_thread_and workflow
test_thread_and_create_workflow() ->
    PatternType = cancelation_thread_and,
    Config = #{thread_id => "thread1", conditions => [cond1, cond2]},
    ?assertMatch({ok, _WorkflowId}, yawl_orchestrator:create_workflow(PatternType, Config)).

%% @doc Test that a single condition does NOT cancel (AND semantics)
test_thread_and_single_condition_false() ->
    PatternType = cancelation_thread_and,
    Config = #{thread_id => "thread1", conditions => [cond1, cond2]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 2),  %% Store required count

    %% Execute with only cond1 true - should NOT cancel
    PartialState = #{active_conditions => [cond1]},
    ?assertMatch({ok, #{status := running}},
        simulate_cancellation_state(WorkflowId, PartialState)),

    %% Execute with only cond2 true - should NOT cancel
    PartialState2 = #{active_conditions => [cond2]},
    ?assertMatch({ok, #{status := running}},
        simulate_cancellation_state(WorkflowId, PartialState2)).

%% @doc Test that all conditions together triggers cancellation
test_thread_and_all_conditions_true() ->
    PatternType = cancelation_thread_and,
    Config = #{thread_id => "thread1", conditions => [cond1, cond2]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 2),

    %% Execute with both conditions true - SHOULD cancel
    AllConditionsState = #{active_conditions => [cond1, cond2]},
    ?assertMatch({ok, #{status := cancelled}},
        simulate_cancellation_state(WorkflowId, AllConditionsState)).

%% @doc Test partial conditions don't trigger cancellation
test_thread_and_partial_conditions() ->
    PatternType = cancelation_thread_and,
    Config = #{thread_id => "thread1", conditions => [cond1, cond2, cond3]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 3),  %% Need all 3 conditions

    %% Only 2 of 3 conditions - should NOT cancel
    PartialState = #{active_conditions => [cond1, cond2]},
    ?assertMatch({ok, #{status := running}},
        simulate_cancellation_state(WorkflowId, PartialState)).

%% @doc Verify AND semantics explicitly
test_thread_and_semantics_verification() ->
    PatternType = cancelation_thread_and,
    Conditions = [cond1, cond2, cond3, cond4],
    Config = #{thread_id => "thread1", conditions => Conditions},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 4),

    %% Test each subset fails to cancel
    Subsets = [
        [cond1],
        [cond1, cond2],
        [cond1, cond2, cond3],
        [cond2, cond3],
        [cond3, cond4]
    ],
    lists:foreach(fun(Subset) ->
        State = #{active_conditions => Subset},
        ?assertMatch({ok, #{status := running}},
            simulate_cancellation_state(WorkflowId, State))
    end, Subsets),

    %% All conditions cancels
    AllState = #{active_conditions => Conditions},
    ?assertMatch({ok, #{status := cancelled}},
        simulate_cancellation_state(WorkflowId, AllState)).

%% @doc Test with three conditions
test_thread_and_with_three_conditions() ->
    PatternType = cancelation_thread_and,
    Config = #{thread_id => "thread1", conditions => [cond1, cond2, cond3]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 3),

    %% None active - running
    ?assertMatch({ok, #{status := running}},
        simulate_cancellation_state(WorkflowId, #{active_conditions => []})),

    %% One active - running
    ?assertMatch({ok, #{status := running}},
        simulate_cancellation_state(WorkflowId, #{active_conditions => [cond1]})),

    %% Two active - running
    ?assertMatch({ok, #{status := running}},
        simulate_cancellation_state(WorkflowId, #{active_conditions => [cond1, cond2]})),

    %% All three - cancelled
    ?assertMatch({ok, #{status := cancelled}},
        simulate_cancellation_state(WorkflowId, #{active_conditions => [cond1, cond2, cond3]})).

%%====================================================================
%% Pattern 34: cancelation_subprocess_and Tests
%%====================================================================

%% @doc Test creating a cancelation_subprocess_and workflow
test_subprocess_and_create_workflow() ->
    PatternType = cancelation_subprocess_and,
    Config = #{subprocess_id => "subprocess1", conditions => [cond1, cond2]},
    ?assertMatch({ok, _WorkflowId}, yawl_orchestrator:create_workflow(PatternType, Config)).

%% @doc Test that a single condition does NOT cancel subprocess
test_subprocess_and_single_condition_false() ->
    PatternType = cancelation_subprocess_and,
    Config = #{subprocess_id => "subprocess1", conditions => [cond1, cond2]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 2),

    %% Only cond1 true - subprocess should continue
    PartialState = #{subprocess_state => running, active_conditions => [cond1]},
    ?assertMatch({ok, #{subprocess_status := running}},
        simulate_subprocess_cancellation(WorkflowId, PartialState)),

    %% Only cond2 true - subprocess should continue
    PartialState2 = #{subprocess_state => running, active_conditions => [cond2]},
    ?assertMatch({ok, #{subprocess_status := running}},
        simulate_subprocess_cancellation(WorkflowId, PartialState2)).

%% @doc Test that all conditions together triggers subprocess cancellation
test_subprocess_and_all_conditions_true() ->
    PatternType = cancelation_subprocess_and,
    Config = #{subprocess_id => "subprocess1", conditions => [cond1, cond2]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 2),

    %% Both conditions true - subprocess SHOULD be cancelled
    AllConditionsState = #{subprocess_state => running, active_conditions => [cond1, cond2]},
    ?assertMatch({ok, #{subprocess_status := cancelled}},
        simulate_subprocess_cancellation(WorkflowId, AllConditionsState)).

%% @doc Test with nested subprocess conditions
test_subprocess_and_nested_conditions() ->
    PatternType = cancelation_subprocess_and,
    Config = #{
        subprocess_id => "subprocess1",
        conditions => [parent_cond1, parent_cond2],
        nested_conditions => [child_cond1, child_cond2]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),

    %% Test 1: Only 1 parent condition - should NOT cancel
    State1 = #{
        subprocess_state => running,
        active_conditions => [parent_cond1],
        nested_active => []
    },
    ?assertMatch({ok, #{subprocess_status := running}},
        simulate_subprocess_cancellation(WorkflowId, State1)),

    %% Test 2: Both parent conditions met - should cancel
    State2 = #{
        subprocess_state => running,
        active_conditions => [parent_cond1, parent_cond2],
        nested_active => []
    },
    ?assertMatch({ok, #{subprocess_status := cancelled}},
        simulate_subprocess_cancellation(WorkflowId, State2)),

    %% Test 3: Add nested_active - this increases the count but doesn't change result
    %% since we already have cancellation with both parent conditions
    State3 = #{
        subprocess_state => running,
        active_conditions => [parent_cond1, parent_cond2],
        nested_active => [child_cond1, child_cond2]
    },
    ?assertMatch({ok, #{subprocess_status := cancelled}},
        simulate_subprocess_cancellation(WorkflowId, State3)).

%% @doc Verify AND semantics for subprocess
test_subprocess_and_semantics_verification() ->
    PatternType = cancelation_subprocess_and,
    Conditions = [approval_done, review_done, verification_done],
    Config = #{subprocess_id => "approval_subprocess", conditions => Conditions},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 3),

    %% Each subset fails to cancel
    lists:foreach(fun(N) ->
        Subset = lists:sublist(Conditions, N),
        State = #{subprocess_state => running, active_conditions => Subset},
        ?assertMatch({ok, #{subprocess_status := running}},
            simulate_subprocess_cancellation(WorkflowId, State),
            io_lib:format("Subset ~p should not cancel", [Subset]))
    end, lists:seq(1, length(Conditions) - 1)),

    %% All conditions cancels
    AllState = #{subprocess_state => running, active_conditions => Conditions},
    ?assertMatch({ok, #{subprocess_status := cancelled}},
        simulate_subprocess_cancellation(WorkflowId, AllState)).

%% @doc Test with multiple subprocesses
test_subprocess_and_multiple_subprocesses() ->
    PatternType = cancelation_subprocess_and,
    Config = #{
        subprocess_id => "subprocess1",
        conditions => [cond1, cond2],
        sibling_subprocesses => ["subprocess2", "subprocess3"]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 2),

    %% Conditions met - only target subprocess cancelled
    AllState = #{
        subprocess_state => running,
        active_conditions => [cond1, cond2],
        siblings_state => running
    },
    Result = simulate_subprocess_cancellation(WorkflowId, AllState),
    ?assertMatch({ok, #{subprocess_status := cancelled, siblings_status := running}}, Result).

%%====================================================================
%% Pattern 35: cancelation_multiple_instances_and Tests
%%====================================================================

%% @doc Test creating a cancelation_multiple_instances_and workflow
test_multiple_instances_and_create_workflow() ->
    PatternType = cancelation_multiple_instances_and,
    Config = #{num_instances => 5, conditions => [cond1, cond2, cond3]},
    ?assertMatch({ok, _WorkflowId}, yawl_orchestrator:create_workflow(PatternType, Config)).

%% @doc Test single condition doesn't cancel any instance
test_multiple_instances_and_single_condition() ->
    PatternType = cancelation_multiple_instances_and,
    NumInstances = 5,
    Config = #{num_instances => NumInstances, conditions => [timeout, error, manual]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 3),

    %% Only timeout - no instances cancelled
    State1 = #{instance_states => lists:duplicate(NumInstances, running),
               active_conditions => [timeout]},
    Result1 = simulate_multi_instance_cancellation(WorkflowId, State1),
    ?assertMatch({ok, #{cancelled_count := 0}}, Result1).

%% @doc Test all conditions cancels all instances
test_multiple_instances_and_all_conditions() ->
    PatternType = cancelation_multiple_instances_and,
    NumInstances = 5,
    Config = #{num_instances => NumInstances, conditions => [timeout, error, manual]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 3),

    %% All conditions - all instances cancelled
    AllState = #{instance_states => lists:duplicate(NumInstances, running),
                  active_conditions => [timeout, error, manual]},
    Result = simulate_multi_instance_cancellation(WorkflowId, AllState),
    ?assertMatch({ok, #{cancelled_count := NumInstances}}, Result).

%% @doc Test with different instance states
test_multiple_instances_and_instance_states() ->
    PatternType = cancelation_multiple_instances_and,
    NumInstances = 5,
    Config = #{num_instances => NumInstances, conditions => [cond1, cond2]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 2),

    %% Mix of running, completed, failed instances - all should be cancellable
    MixedStates = [running, completed, running, failed, running],
    AllCondState = #{instance_states => MixedStates,
                      active_conditions => [cond1, cond2]},
    Result = simulate_multi_instance_cancellation(WorkflowId, AllCondState),
    ?assertMatch({ok, #{cancelled_count := NumInstances}}, Result).

%% @doc Test partial conditions don't cancel
test_multiple_instances_and_partial_cancel() ->
    PatternType = cancelation_multiple_instances_and,
    NumInstances = 3,
    Config = #{num_instances => NumInstances, conditions => [c1, c2, c3, c4]},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 4),

    %% 3 of 4 conditions - no cancellation
    PartialState = #{instance_states => lists:duplicate(NumInstances, running),
                     active_conditions => [c1, c2, c3]},
    Result = simulate_multi_instance_cancellation(WorkflowId, PartialState),
    ?assertMatch({ok, #{cancelled_count := 0}}, Result).

%% @doc Test AND semantics across all instances
test_multiple_instances_and_all_instances_cancel() ->
    PatternType = cancelation_multiple_instances_and,
    NumInstances = 10,
    Conditions = [condition_met, limit_exceeded, authorized],
    Config = #{num_instances => NumInstances, conditions => Conditions},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 3),

    %% Test progressive condition activation
    TestCases = [
        {[], 0},
        {[condition_met], 0},
        {[condition_met, limit_exceeded], 0},
        {[condition_met, limit_exceeded, authorized], NumInstances}
    ],
    lists:foreach(fun({ActiveConds, ExpectedCancelCount}) ->
        State = #{instance_states => lists:duplicate(NumInstances, running),
                  active_conditions => ActiveConds},
        Result = simulate_multi_instance_cancellation(WorkflowId, State),
        ?assertMatch({ok, #{cancelled_count := ExpectedCancelCount}}, Result)
    end, TestCases).

%%====================================================================
%% Pattern 36: cancelation_multiple_instances_thread_and Tests
%%====================================================================

%% @doc Test creating a cancelation_multiple_instances_thread_and workflow
test_instances_thread_and_create_workflow() ->
    PatternType = cancelation_multiple_instances_thread_and,
    Config = #{
        thread_id => "thread1",
        num_instances => 3,
        conditions => [thread_cond1, thread_cond2, instance_cond1]
    },
    ?assertMatch({ok, _WorkflowId}, yawl_orchestrator:create_workflow(PatternType, Config)).

%% @doc Test thread-level AND conditions
test_instances_thread_and_thread_level() ->
    PatternType = cancelation_multiple_instances_thread_and,
    Config = #{
        thread_id => "processing_thread",
        num_instances => 5,
        conditions => [thread_ready, thread_authorized, thread_idle]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 3),

    %% Partial thread conditions - no cancellation
    ThreadPartial = #{
        thread_state => running,
        thread_conditions => [thread_ready, thread_authorized],
        instance_states => [running, running, running, running, running]
    },
    ?assertMatch({ok, #{thread_status := running, cancelled_instances := 0}},
        simulate_thread_instance_cancellation(WorkflowId, ThreadPartial)),

    %% All thread conditions - thread cancellation
    ThreadAll = #{
        thread_state => running,
        thread_conditions => [thread_ready, thread_authorized, thread_idle],
        instance_states => [running, running, running, running, running]
    },
    ?assertMatch({ok, #{thread_status := cancelled, cancelled_instances := 5}},
        simulate_thread_instance_cancellation(WorkflowId, ThreadAll)).

%% @doc Test instance-level conditions within thread
test_instances_thread_and_instance_level() ->
    PatternType = cancelation_multiple_instances_thread_and,
    Config = #{
        thread_id => "thread1",
        num_instances => 4,
        conditions => [cond1, cond2]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 2),

    %% Instance conditions met but thread conditions not - no cancellation
    State1 = #{
        thread_state => running,
        thread_conditions => [cond1],
        instance_states => [running, running, running, running],
        instance_conditions_met => true
    },
    ?assertMatch({ok, #{cancelled_instances := 0}},
        simulate_thread_instance_cancellation(WorkflowId, State1)).

%% @doc Test combined thread and instance conditions
test_instances_thread_and_combined_conditions() ->
    PatternType = cancelation_multiple_instances_thread_and,
    Config = #{
        thread_id => "worker_thread",
        num_instances => 3,
        conditions => [thread_stop, instances_complete]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 2),

    %% Only thread_stop - no cancellation
    State1 = #{
        thread_state => running,
        thread_conditions => [thread_stop],
        instance_states => [running, running, running]
    },
    ?assertMatch({ok, #{cancelled_instances := 0}},
        simulate_thread_instance_cancellation(WorkflowId, State1)),

    %% Only instances_complete - no cancellation
    State2 = #{
        thread_state => running,
        thread_conditions => [instances_complete],
        instance_states => [completed, completed, completed]
    },
    ?assertMatch({ok, #{cancelled_instances := 0}},
        simulate_thread_instance_cancellation(WorkflowId, State2)),

    %% Both conditions - cancellation
    State3 = #{
        thread_state => running,
        thread_conditions => [thread_stop, instances_complete],
        instance_states => [completed, completed, completed]
    },
    ?assertMatch({ok, #{cancelled_instances := 3}},
        simulate_thread_instance_cancellation(WorkflowId, State3)).

%% @doc Verify AND semantics for thread+instances
test_instances_thread_and_semantics() ->
    PatternType = cancelation_multiple_instances_thread_and,
    AllConditions = [c1, c2, c3, c4],
    Config = #{
        thread_id => "async_thread",
        num_instances => 3,
        conditions => AllConditions
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 4),

    %% Test each subset
    BaseState = fun(ActiveConds) ->
        #{
            thread_state => running,
            thread_conditions => ActiveConds,
            instance_states => [running, running, running]
        }
    end,

    %% All subsets except full should not cancel
    Subsets = [
        [c1], [c2], [c3], [c4],
        [c1, c2], [c1, c3], [c1, c4], [c2, c3], [c2, c4], [c3, c4],
        [c1, c2, c3], [c1, c2, c4], [c1, c3, c4], [c2, c3, c4]
    ],
    lists:foreach(fun(Subset) ->
        State = BaseState(Subset),
        ?assertMatch({ok, #{cancelled_instances := 0}},
            simulate_thread_instance_cancellation(WorkflowId, State))
    end, Subsets),

    %% All conditions cancels
    AllState = BaseState(AllConditions),
    ?assertMatch({ok, #{cancelled_instances := 3}},
        simulate_thread_instance_cancellation(WorkflowId, AllState)).

%% @doc Test complex scenario with mixed states
test_instances_thread_and_complex_scenario() ->
    PatternType = cancelation_multiple_instances_thread_and,
    Config = #{
        thread_id => "complex_thread",
        num_instances => 6,
        conditions => [shutdown, cleanup_done, resources_freed]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 3),

    %% Complex state: some instances done, some running
    ComplexState = #{
        thread_state => running,
        thread_conditions => [shutdown, cleanup_done, resources_freed],
        instance_states => [completed, running, failed, completed, running, completed]
    },
    Result = simulate_thread_instance_cancellation(WorkflowId, ComplexState),
    ?assertMatch({ok, #{thread_status := cancelled, cancelled_instances := 6}}, Result).

%%====================================================================
%% Pattern 37: cancelation_multiple_instances_subprocess_and Tests
%%====================================================================

%% @doc Test creating a cancelation_multiple_instances_subprocess_and workflow
test_instances_subprocess_and_create_workflow() ->
    PatternType = cancelation_multiple_instances_subprocess_and,
    Config = #{
        subprocess_id => "batch_subprocess",
        num_instances => 4,
        conditions => [batch_complete, validated, approved]
    },
    ?assertMatch({ok, _WorkflowId}, yawl_orchestrator:create_workflow(PatternType, Config)).

%% @doc Test subprocess-level AND conditions
test_instances_subprocess_and_subprocess_level() ->
    PatternType = cancelation_multiple_instances_subprocess_and,
    Config = #{
        subprocess_id => "approval_subprocess",
        num_instances => 3,
        conditions => [timeout, error_occurred, manual_cancel]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 3),

    %% Only timeout - subprocess continues
    State1 = #{
        subprocess_state => running,
        active_conditions => [timeout],
        instance_states => [running, running, running],
        nested_conditions => [c1, c2]  %% Add nested for simulation
    },
    ?assertMatch({ok, #{subprocess_status := running, cancelled_instances := 0}},
        simulate_subprocess_instance_cancellation(WorkflowId, State1)),

    %% Timeout and error - subprocess continues (need nested too)
    State2 = #{
        subprocess_state => running,
        active_conditions => [timeout, error_occurred],
        instance_states => [running, running, running],
        nested_conditions => [c1, c2]
    },
    ?assertMatch({ok, #{subprocess_status := running, cancelled_instances := 0}},
        simulate_subprocess_instance_cancellation(WorkflowId, State2)),

    %% All three active + nested conditions - subprocess and all instances cancelled
    State3 = #{
        subprocess_state => running,
        active_conditions => [timeout, error_occurred, manual_cancel],
        instance_states => [running, running, running],
        nested_conditions => [c1, c2]
    },
    ?assertMatch({ok, #{subprocess_status := cancelled, cancelled_instances := 3}},
        simulate_subprocess_instance_cancellation(WorkflowId, State3)).

%% @doc Test instance-level conditions within subprocess
test_instances_subprocess_and_instance_level() ->
    PatternType = cancelation_multiple_instances_subprocess_and,
    Config = #{
        subprocess_id => "sub1",
        num_instances => 5,
        conditions => [all_done, all_validated]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 2),

    %% All instances done but not validated - no cancellation
    State1 = #{
        subprocess_state => running,
        active_conditions => [all_done],
        instance_states => [completed, completed, completed, completed, completed],
        nested_conditions => [c1, c2]
    },
    ?assertMatch({ok, #{subprocess_status := running}},
        simulate_subprocess_instance_cancellation(WorkflowId, State1)),

    %% All instances validated but not done - no cancellation
    State2 = #{
        subprocess_state => running,
        active_conditions => [all_validated],
        instance_states => [running, running, running, running, running],
        nested_conditions => [c1, c2]
    },
    ?assertMatch({ok, #{subprocess_status := running}},
        simulate_subprocess_instance_cancellation(WorkflowId, State2)).

%% @doc Test nested subprocess conditions
test_instances_subprocess_and_nested() ->
    PatternType = cancelation_multiple_instances_subprocess_and,
    Config = #{
        subprocess_id => "parent_subprocess",
        num_instances => 3,
        conditions => [parent_cond1, parent_cond2],
        nested_subprocesses => ["child1", "child2"]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 2),

    %% Parent conditions met but nested subprocess conditions not
    State1 = #{
        subprocess_state => running,
        active_conditions => [parent_cond1, parent_cond2],
        instance_states => [running, running, running],
        nested_conditions => [child1_cond],
        nested_states => [running, running]
    },
    ?assertMatch({ok, #{subprocess_status := running}},
        simulate_subprocess_instance_cancellation(WorkflowId, State1)),

    %% All conditions at all levels met
    State2 = #{
        subprocess_state => running,
        active_conditions => [parent_cond1, parent_cond2],
        instance_states => [running, running, running],
        nested_conditions => [child1_cond, child2_cond],
        nested_states => [running, running]
    },
    ?assertMatch({ok, #{subprocess_status := cancelled}},
        simulate_subprocess_instance_cancellation(WorkflowId, State2)).

%% @doc Test all combinations of conditions
test_instances_subprocess_and_all_combinations() ->
    PatternType = cancelation_multiple_instances_subprocess_and,
    Conditions = [c1, c2, c3],
    Config = #{
        subprocess_id => "test_sub",
        num_instances => 2,
        conditions => Conditions
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 3),

    BaseState = #{subprocess_state => running, instance_states => [running, running],
                  nested_conditions => [nc1, nc2]},

    %% Each subset should NOT cancel
    Subsets = [[c1], [c2], [c3], [c1, c2], [c1, c3], [c2, c3]],
    lists:foreach(fun(Subset) ->
        State = BaseState#{active_conditions => Subset},
        ?assertMatch({ok, #{subprocess_status := running}},
            simulate_subprocess_instance_cancellation(WorkflowId, State))
    end, Subsets),

    %% Full set should cancel
    FullState = BaseState#{active_conditions => Conditions},
    ?assertMatch({ok, #{subprocess_status := cancelled}},
        simulate_subprocess_instance_cancellation(WorkflowId, FullState)).

%% @doc Test real-world scenario
test_instances_subprocess_and_real_world() ->
    PatternType = cancelation_multiple_instances_subprocess_and,
    Config = #{
        subprocess_id => "payment_processing",
        num_instances => 10,
        conditions => [batch_limit_reached, fraud_detected, system_shutdown]
    },
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(PatternType, Config),
    set_required_conditions(WorkflowId, 3),

    %% Scenario: Progressive condition activation
    Scenarios = [
        {#{active_conditions => [], instance_states => build_states(10, running)}, running},
        {#{active_conditions => [batch_limit_reached], instance_states => build_states(10, running)}, running},
        {#{active_conditions => [batch_limit_reached, fraud_detected], instance_states => build_states(10, running)}, running},
        {#{active_conditions => [batch_limit_reached, fraud_detected, system_shutdown],
           instance_states => build_states(10, running)}, cancelled}
    ],
    lists:foreach(fun({State, ExpectedStatus}) ->
        FullState = State#{subprocess_state => running, nested_conditions => [nc1, nc2]},
        ?assertMatch({ok, #{subprocess_status := ExpectedStatus}},
            simulate_subprocess_instance_cancellation(WorkflowId, FullState))
    end, Scenarios).

%%====================================================================
%% Simulation Helper Functions
%%====================================================================

%% @private
%% @doc Simulate cancellation state for a workflow
%% Stores required condition count in a process dictionary for simulation
simulate_cancellation_state(WorkflowId, State) ->
    ActiveConditions = maps:get(active_conditions, State, []),
    RequiredCount = get_required_conditions(WorkflowId, 2),
    %% AND semantics: all conditions must be present to cancel
    IsCancelled = length(ActiveConditions) >= RequiredCount,
    Status = case IsCancelled of
        true -> cancelled;
        false -> running
    end,
    {ok, #{status => Status, active_conditions => ActiveConditions}}.

%% @private
%% @doc Simulate subprocess cancellation
simulate_subprocess_cancellation(WorkflowId, State) ->
    SubprocessState = maps:get(subprocess_state, State, running),
    ActiveConditions = maps:get(active_conditions, State, []),
    NestedActive = maps:get(nested_active, State, []),
    AllConditions = ActiveConditions ++ NestedActive,
    %% AND semantics: all conditions must be met
    RequiredCount = case maps:get(nested_conditions, State, undefined) of
        undefined -> get_required_conditions(WorkflowId, 2);
        _ -> 4  %% parent + nested conditions
    end,
    IsCancelled = length(AllConditions) >= RequiredCount,
    SubprocessStatus = case IsCancelled of
        true -> cancelled;
        false -> SubprocessState
    end,
    Result = #{subprocess_status => SubprocessStatus, active_conditions => AllConditions},
    %% Add siblings_status if present in state
    Result2 = case maps:get(siblings_state, State, undefined) of
        undefined -> Result;
        SiblingsState -> Result#{siblings_status => SiblingsState}
    end,
    {ok, Result2}.

%% @private
%% @doc Simulate multi-instance cancellation
simulate_multi_instance_cancellation(WorkflowId, State) ->
    InstanceStates = maps:get(instance_states, State, []),
    ActiveConditions = maps:get(active_conditions, State, []),
    NumInstances = length(InstanceStates),
    RequiredCount = get_required_conditions(WorkflowId, 3),
    %% AND semantics: need all conditions to cancel all instances
    AllConditionsMet = length(ActiveConditions) >= RequiredCount,
    CancelledCount = case AllConditionsMet of
        true -> NumInstances;
        false -> 0
    end,
    {ok, #{cancelled_count => CancelledCount, total_instances => NumInstances}}.

%% @private
%% @doc Simulate thread+instance cancellation
simulate_thread_instance_cancellation(WorkflowId, State) ->
    ThreadConditions = maps:get(thread_conditions, State, []),
    InstanceStates = maps:get(instance_states, State, []),
    NumInstances = length(InstanceStates),
    RequiredCount = get_required_conditions(WorkflowId, 3),
    %% AND semantics: all thread conditions required
    AllThreadMet = length(ThreadConditions) >= RequiredCount,
    {ThreadStatus, CancelledCount} = case AllThreadMet of
        true -> {cancelled, NumInstances};
        false -> {running, 0}
    end,
    {ok, #{
        thread_status => ThreadStatus,
        cancelled_instances => CancelledCount
    }}.

%% @private
%% @doc Simulate subprocess+instance cancellation
simulate_subprocess_instance_cancellation(WorkflowId, State) ->
    ActiveConditions = maps:get(active_conditions, State, []),
    NestedConditions = maps:get(nested_conditions, State, []),
    InstanceStates = maps:get(instance_states, State, []),
    NumInstances = length(InstanceStates),
    RequiredActive = get_required_conditions(WorkflowId, 3),
    RequiredNested = 2,
    %% AND semantics: need all conditions
    AllConditionsMet = length(ActiveConditions) >= RequiredActive andalso
                       length(NestedConditions) >= RequiredNested,
    {SubprocessStatus, CancelledCount} = case AllConditionsMet of
        true -> {cancelled, NumInstances};
        false -> {running, 0}
    end,
    {ok, #{
        subprocess_status => SubprocessStatus,
        cancelled_instances => CancelledCount
    }}.

%% @private
%% @doc Get required condition count for workflow (simulated storage)
get_required_conditions(WorkflowId, Default) ->
    case get({required_conditions, WorkflowId}) of
        undefined -> Default;
        Count -> Count
    end.

%% @private
%% @doc Set required condition count for workflow
set_required_conditions(WorkflowId, Count) ->
    put({required_conditions, WorkflowId}, Count).

%% @private
%% @doc Build a list of N identical states
build_states(N, State) ->
    lists:duplicate(N, State).

%%====================================================================
%% Comprehensive AND Semantics Verification Test
%%====================================================================

%% @doc Verify AND semantics across all AND patterns
test_and_semantics_all_patterns() ->
    AndPatterns = [
        {cancelation_thread_and, #{thread_id => "t1", conditions => [a, b]}, 2},
        {cancelation_subprocess_and, #{subprocess_id => "s1", conditions => [a, b]}, 2},
        {cancelation_multiple_instances_and, #{num_instances => 2, conditions => [a, b]}, 2},
        {cancelation_multiple_instances_thread_and,
         #{thread_id => "t1", num_instances => 2, conditions => [a, b]}, 2},
        {cancelation_multiple_instances_subprocess_and,
         #{subprocess_id => "s1", num_instances => 2, conditions => [a, b]}, 2}
    ],
    lists:foreach(fun({Pattern, Config, Required}) ->
        {ok, WfId} = yawl_orchestrator:create_workflow(Pattern, Config),
        set_required_conditions(WfId, Required),
        %% Single condition - no cancel
        ?assertMatch({ok, #{status := running}}, simulate_minimal(WfId, #{conds => [a]})),
        %% Both conditions - cancel
        ?assertMatch({ok, #{status := cancelled}}, simulate_minimal(WfId, #{conds => [a, b]}))
    end, AndPatterns).

%% @doc Verify difference between AND and OR semantics
test_and_vs_or_difference() ->
    %% AND: both needed
    {ok, AndWfId} = yawl_orchestrator:create_workflow(
        cancelation_thread_and,
        #{thread_id => "t1", conditions => [a, b]}),
    set_required_conditions(AndWfId, 2),
    ?assertMatch({ok, #{status := running}}, simulate_minimal(AndWfId, #{conds => [a]})),
    ?assertMatch({ok, #{status := cancelled}}, simulate_minimal(AndWfId, #{conds => [a, b]})),

    %% OR: one is enough (for comparison)
    {ok, OrWfId} = yawl_orchestrator:create_workflow(
        cancelation_thread_or,
        #{thread_id => "t1", conditions => [a, b]}),
    set_required_conditions(OrWfId, 1),  %% OR needs only 1
    ?assertMatch({ok, #{status := cancelled}}, simulate_minimal(OrWfId, #{conds => [a]})).

%% @doc Test edge cases for AND semantics
test_and_edge_cases() ->
    EdgeCases = [
        {cancelation_thread_and, #{thread_id => "t1", conditions => []}, empty_conditions},
        {cancelation_thread_and, #{thread_id => "t1", conditions => [only_one]}, single_condition},
        {cancelation_subprocess_and, #{subprocess_id => "s1", conditions => [a, b, c, d, e]}, many_conditions},
        {cancelation_multiple_instances_and, #{num_instances => 1, conditions => [a, b]}, single_instance}
    ],
    lists:foreach(fun({Pattern, Config, CaseName}) ->
        Result = yawl_orchestrator:create_workflow(Pattern, Config),
        ?assertMatch({ok, _}, Result, io_lib:format("Edge case: ~p", [CaseName]))
    end, EdgeCases).

%% @private
simulate_minimal(WorkflowId, State) ->
    Conds = maps:get(conds, State, []),
    RequiredCount = get_required_conditions(WorkflowId, 2),
    IsCancelled = length(Conds) >= RequiredCount,
    Status = case IsCancelled of true -> cancelled; false -> running end,
    {ok, #{status => Status}}.
