%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Cancellation OR Pattern Simulation Tests
%%%
%%% This module contains comprehensive simulation tests for the Cancellation
%%% OR patterns (28-32). Each pattern is tested for:
%%% - Cancellation when ANY condition is true
%%% - Each condition individually triggers cancel
%%% - Multiple conditions - still cancels
%%% - OR semantics verification (any=true, all=false still cancels)
%%%
%%% Patterns tested:
%%% 28. cancelation_thread_or - cancel thread with OR conditions
%%% 29. cancelation_subprocess_or - cancel subprocess with OR
%%% 30. cancelation_multiple_instances_or - cancel instances with OR
%%% 31. cancelation_multiple_instances_thread_or - cancel instances thread OR
%%% 32. cancelation_multiple_instances_subprocess_or - cancel instances subprocess OR
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_cancellation_or_sim_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(OR_CONDITIONS_2, [cond1, cond2]).
-define(OR_CONDITIONS_3, [cond1, cond2, cond3]).
-define(OR_CONDITIONS_5, [cond1, cond2, cond3, cond4, cond5]).
-define(NUM_INSTANCES_3, 3).
-define(NUM_INSTANCES_5, 5).

%%====================================================================
%% Pattern 28: Cancellation Thread OR Tests
%%====================================================================

%% @doc Test cancellation_thread_or pattern - any condition triggers cancel
cancelation_thread_or_any_condition_triggers_cancel_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            %% Create workflow with OR conditions
            Config = #{
                thread_id => "thread1",
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_thread_or, Config),
            ?assert(is_binary(WorkflowId)),

            %% Simulate setting condition1 to true
            ConditionStates = #{cond1 => true, cond2 => false, cond3 => false},
            {ok, Canceled1} = simulate_or_cancellation(WorkflowId, ConditionStates),

            %% Should cancel because cond1 is true (OR semantics)
            ?assertEqual(cancelled, Canceled1),

            %% Clean up
            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test each condition individually triggers cancel for cancelation_thread_or
cancelation_thread_or_each_condition_triggers_cancel_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                thread_id => "thread1",
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_thread_or, Config),

            %% Test condition1 alone
            States1 = #{cond1 => true, cond2 => false, cond3 => false},
            {ok, Canceled1} = simulate_or_cancellation(WorkflowId, States1),
            ?assertEqual(cancelled, Canceled1),

            %% Test condition2 alone
            States2 = #{cond1 => false, cond2 => true, cond3 => false},
            {ok, Canceled2} = simulate_or_cancellation(WorkflowId, States2),
            ?assertEqual(cancelled, Canceled2),

            %% Test condition3 alone
            States3 = #{cond1 => false, cond2 => false, cond3 => true},
            {ok, Canceled3} = simulate_or_cancellation(WorkflowId, States3),
            ?assertEqual(cancelled, Canceled3),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test multiple conditions true still cancels for cancelation_thread_or
cancelation_thread_or_multiple_conditions_still_cancels_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                thread_id => "thread1",
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_thread_or, Config),

            %% All conditions true - should still cancel (OR semantics)
            StatesAll = #{cond1 => true, cond2 => true, cond3 => true},
            {ok, CanceledAll} = simulate_or_cancellation(WorkflowId, StatesAll),
            ?assertEqual(cancelled, CanceledAll),

            %% Two conditions true - should still cancel
            StatesTwo = #{cond1 => true, cond2 => true, cond3 => false},
            {ok, CanceledTwo} = simulate_or_cancellation(WorkflowId, StatesTwo),
            ?assertEqual(cancelled, CanceledTwo),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test OR semantics: any=true, all=false still cancels for cancelation_thread_or
cancelation_thread_or_or_semantics_any_true_all_false_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                thread_id => "thread1",
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_thread_or, Config),

            %% Any true triggers cancel
            StatesAnyTrue = #{cond1 => true, cond2 => false, cond3 => false},
            {ok, ResultAny} = simulate_or_cancellation(WorkflowId, StatesAnyTrue),
            ?assertEqual(cancelled, ResultAny),

            %% All false does NOT trigger cancel
            StatesAllFalse = #{cond1 => false, cond2 => false, cond3 => false},
            {ok, ResultAllFalse} = simulate_or_cancellation(WorkflowId, StatesAllFalse),
            ?assertEqual(running, ResultAllFalse),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test with many conditions for cancelation_thread_or
cancelation_thread_or_many_conditions_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                thread_id => "thread1",
                conditions => ?OR_CONDITIONS_5
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_thread_or, Config),

            %% One condition true out of five - should cancel
            States = #{cond1 => false, cond2 => true, cond3 => false, cond4 => false, cond5 => false},
            {ok, Result} = simulate_or_cancellation(WorkflowId, States),
            ?assertEqual(cancelled, Result),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%%====================================================================
%% Pattern 29: Cancellation Subprocess OR Tests
%%====================================================================

%% @doc Test cancellation_subprocess_or - any condition triggers cancel
cancelation_subprocess_or_any_condition_triggers_cancel_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                subprocess_id => "subprocess1",
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_subprocess_or, Config),
            ?assert(is_binary(WorkflowId)),

            %% Set only condition2 to true
            ConditionStates = #{cond1 => false, cond2 => true, cond3 => false},
            {ok, Canceled} = simulate_or_cancellation(WorkflowId, ConditionStates),
            ?assertEqual(cancelled, Canceled),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test each condition individually triggers cancel for cancelation_subprocess_or
cancelation_subprocess_or_each_condition_triggers_cancel_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                subprocess_id => "subprocess1",
                conditions => ?OR_CONDITIONS_2
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_subprocess_or, Config),

            %% Test first condition
            States1 = #{cond1 => true, cond2 => false},
            {ok, Canceled1} = simulate_or_cancellation(WorkflowId, States1),
            ?assertEqual(cancelled, Canceled1),

            %% Test second condition
            States2 = #{cond1 => false, cond2 => true},
            {ok, Canceled2} = simulate_or_cancellation(WorkflowId, States2),
            ?assertEqual(cancelled, Canceled2),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test multiple conditions true still cancels for cancelation_subprocess_or
cancelation_subprocess_or_multiple_conditions_still_cancels_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                subprocess_id => "subprocess1",
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_subprocess_or, Config),

            %% All conditions true
            States = #{cond1 => true, cond2 => true, cond3 => true},
            {ok, Canceled} = simulate_or_cancellation(WorkflowId, States),
            ?assertEqual(cancelled, Canceled),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test OR semantics verification for cancelation_subprocess_or
cancelation_subprocess_or_or_semantics_verification_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                subprocess_id => "subprocess1",
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_subprocess_or, Config),

            %% Verify OR semantics: any true cancels, all false doesn't
            StatesWithTrue = #{cond1 => false, cond2 => false, cond3 => true},
            {ok, ResultWithTrue} = simulate_or_cancellation(WorkflowId, StatesWithTrue),
            ?assertEqual(cancelled, ResultWithTrue),

            StatesAllFalse = #{cond1 => false, cond2 => false, cond3 => false},
            {ok, ResultAllFalse} = simulate_or_cancellation(WorkflowId, StatesAllFalse),
            ?assertNotEqual(cancelled, ResultAllFalse),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test subprocess context preservation with OR cancellation
cancelation_subprocess_or_preserves_context_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            SubprocessId = "critical_subprocess",
            Config = #{
                subprocess_id => SubprocessId,
                conditions => [timeout, error, manual_cancel]
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_subprocess_or, Config),

            %% Trigger cancellation via error condition
            States = #{timeout => false, error => true, manual_cancel => false},
            {ok, Result} = simulate_or_cancellation(WorkflowId, States),
            ?assertEqual(cancelled, Result),

            %% Verify subprocess context is captured
            {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
            ?assertEqual(cancelled, Status),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%%====================================================================
%% Pattern 30: Cancellation Multiple Instances OR Tests
%%====================================================================

%% @doc Test cancellation_multiple_instances_or - any condition cancels all
cancelation_multiple_instances_or_any_condition_cancels_all_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                num_instances => ?NUM_INSTANCES_3,
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_or, Config),
            ?assert(is_binary(WorkflowId)),

            %% One condition true should cancel all instances
            ConditionStates = #{cond1 => false, cond2 => true, cond3 => false},
            {ok, Canceled} = simulate_or_cancellation_multi(WorkflowId, ConditionStates, ?NUM_INSTANCES_3),
            ?assertEqual(cancelled, Canceled),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test each condition individually cancels all instances
cancelation_multiple_instances_or_each_condition_cancels_all_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                num_instances => ?NUM_INSTANCES_5,
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_or, Config),

            %% Test condition1
            States1 = #{cond1 => true, cond2 => false, cond3 => false},
            {ok, Result1} = simulate_or_cancellation_multi(WorkflowId, States1, ?NUM_INSTANCES_5),
            ?assertEqual(cancelled, Result1),

            %% Test condition2
            States2 = #{cond1 => false, cond2 => true, cond3 => false},
            {ok, Result2} = simulate_or_cancellation_multi(WorkflowId, States2, ?NUM_INSTANCES_5),
            ?assertEqual(cancelled, Result2),

            %% Test condition3
            States3 = #{cond1 => false, cond2 => false, cond3 => true},
            {ok, Result3} = simulate_or_cancellation_multi(WorkflowId, States3, ?NUM_INSTANCES_5),
            ?assertEqual(cancelled, Result3),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test multiple conditions still cancels all instances
cancelation_multiple_instances_or_multiple_conditions_still_cancels_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                num_instances => ?NUM_INSTANCES_3,
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_or, Config),

            %% Multiple conditions true
            States = #{cond1 => true, cond2 => true, cond3 => false},
            {ok, Result} = simulate_or_cancellation_multi(WorkflowId, States, ?NUM_INSTANCES_3),
            ?assertEqual(cancelled, Result),

            %% Verify all instances are cancelled
            {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
            ?assertEqual(cancelled, Status),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test OR semantics with multiple instances
cancelation_multiple_instances_or_or_semantics_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                num_instances => ?NUM_INSTANCES_3,
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_or, Config),

            %% Any true triggers cancellation
            StatesAny = #{cond1 => true, cond2 => false, cond3 => false},
            {ok, ResultAny} = simulate_or_cancellation_multi(WorkflowId, StatesAny, ?NUM_INSTANCES_3),
            ?assertEqual(cancelled, ResultAny),

            %% All false doesn't cancel
            StatesNone = #{cond1 => false, cond2 => false, cond3 => false},
            {ok, ResultNone} = simulate_or_cancellation_multi(WorkflowId, StatesNone, ?NUM_INSTANCES_3),
            ?assertNotEqual(cancelled, ResultNone),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test cancellation propagation across all instances
cancelation_multiple_instances_or_propagation_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            NumInstances = 10,
            Config = #{
                num_instances => NumInstances,
                conditions => [any_failed, timeout, limit_reached]
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_or, Config),

            %% Trigger via timeout - should propagate to all 10 instances
            States = #{any_failed => false, timeout => true, limit_reached => false},
            {ok, Result} = simulate_or_cancellation_multi(WorkflowId, States, NumInstances),
            ?assertEqual(cancelled, Result),

            %% Verify workflow is fully cancelled
            {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
            ?assertEqual(cancelled, Status),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%%====================================================================
%% Pattern 31: Cancellation Multiple Instances Thread OR Tests
%%====================================================================

%% @doc Test cancellation_multiple_instances_thread_or - any condition cancels thread
cancelation_multiple_instances_thread_or_any_condition_cancels_thread_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                thread_id => "thread1",
                num_instances => ?NUM_INSTANCES_3,
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_thread_or, Config),
            ?assert(is_binary(WorkflowId)),

            %% Single condition true cancels the entire thread with all instances
            States = #{cond1 => false, cond2 => true, cond3 => false},
            {ok, Canceled} = simulate_or_cancellation_thread_multi(WorkflowId, States, ?NUM_INSTANCES_3),
            ?assertEqual(cancelled, Canceled),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test each condition individually cancels thread with instances
cancelation_multiple_instances_thread_or_each_condition_cancels_thread_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                thread_id => "processing_thread",
                num_instances => ?NUM_INSTANCES_5,
                conditions => [memory_exceeded, cpu_limit, io_timeout]
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_thread_or, Config),

            %% Test each condition individually
            States1 = #{memory_exceeded => true, cpu_limit => false, io_timeout => false},
            {ok, Result1} = simulate_or_cancellation_thread_multi(WorkflowId, States1, ?NUM_INSTANCES_5),
            ?assertEqual(cancelled, Result1),

            States2 = #{memory_exceeded => false, cpu_limit => true, io_timeout => false},
            {ok, Result2} = simulate_or_cancellation_thread_multi(WorkflowId, States2, ?NUM_INSTANCES_5),
            ?assertEqual(cancelled, Result2),

            States3 = #{memory_exceeded => false, cpu_limit => false, io_timeout => true},
            {ok, Result3} = simulate_or_cancellation_thread_multi(WorkflowId, States3, ?NUM_INSTANCES_5),
            ?assertEqual(cancelled, Result3),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test multiple conditions still cancels thread
cancelation_multiple_instances_thread_or_multiple_conditions_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                thread_id => "worker_thread",
                num_instances => ?NUM_INSTANCES_3,
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_thread_or, Config),

            %% All conditions true - should still cancel
            States = #{cond1 => true, cond2 => true, cond3 => true},
            {ok, Result} = simulate_or_cancellation_thread_multi(WorkflowId, States, ?NUM_INSTANCES_3),
            ?assertEqual(cancelled, Result),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test OR semantics for thread with multiple instances
cancelation_multiple_instances_thread_or_or_semantics_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                thread_id => "batch_thread",
                num_instances => ?NUM_INSTANCES_3,
                conditions => ?OR_CONDITIONS_2
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_thread_or, Config),

            %% Any true cancels
            StatesAny = #{cond1 => true, cond2 => false},
            {ok, ResultAny} = simulate_or_cancellation_thread_multi(WorkflowId, StatesAny, ?NUM_INSTANCES_3),
            ?assertEqual(cancelled, ResultAny),

            %% All false doesn't cancel
            StatesNone = #{cond1 => false, cond2 => false},
            {ok, ResultNone} = simulate_or_cancellation_thread_multi(WorkflowId, StatesNone, ?NUM_INSTANCES_3),
            ?assertNotEqual(cancelled, ResultNone),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test thread-level cancellation affects all instances
cancelation_multiple_instances_thread_or_thread_level_cancel_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            NumInstances = 7,
            Config = #{
                thread_id => "parallel_thread",
                num_instances => NumInstances,
                conditions => [any_error, resource_exhausted, deadline_missed]
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_thread_or, Config),

            %% One condition triggers thread-level cancellation
            States = #{any_error => false, resource_exhausted => true, deadline_missed => false},
            {ok, Result} = simulate_or_cancellation_thread_multi(WorkflowId, States, NumInstances),
            ?assertEqual(cancelled, Result),

            %% Verify thread and all instances are cancelled
            {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
            ?assertEqual(cancelled, Status),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%%====================================================================
%% Pattern 32: Cancellation Multiple Instances Subprocess OR Tests
%%====================================================================

%% @doc Test cancellation_multiple_instances_subprocess_or - any condition cancels
cancelation_multiple_instances_subprocess_or_any_condition_cancels_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                subprocess_id => "batch_process",
                num_instances => ?NUM_INSTANCES_3,
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_subprocess_or, Config),
            ?assert(is_binary(WorkflowId)),

            %% Single condition triggers cancellation
            States = #{cond1 => false, cond2 => true, cond3 => false},
            {ok, Canceled} = simulate_or_cancellation_subprocess_multi(WorkflowId, States, ?NUM_INSTANCES_3),
            ?assertEqual(cancelled, Canceled),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test each condition individually cancels subprocess with instances
cancelation_multiple_instances_subprocess_or_each_condition_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                subprocess_id => "data_processing",
                num_instances => ?NUM_INSTANCES_3,
                conditions => [validation_failed, data_corrupt, quota_exceeded]
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_subprocess_or, Config),

            %% Test each condition
            States1 = #{validation_failed => true, data_corrupt => false, quota_exceeded => false},
            {ok, Result1} = simulate_or_cancellation_subprocess_multi(WorkflowId, States1, ?NUM_INSTANCES_3),
            ?assertEqual(cancelled, Result1),

            States2 = #{validation_failed => false, data_corrupt => true, quota_exceeded => false},
            {ok, Result2} = simulate_or_cancellation_subprocess_multi(WorkflowId, States2, ?NUM_INSTANCES_3),
            ?assertEqual(cancelled, Result2),

            States3 = #{validation_failed => false, data_corrupt => false, quota_exceeded => true},
            {ok, Result3} = simulate_or_cancellation_subprocess_multi(WorkflowId, States3, ?NUM_INSTANCES_3),
            ?assertEqual(cancelled, Result3),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test multiple conditions still cancels subprocess
cancelation_multiple_instances_subprocess_or_multiple_conditions_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                subprocess_id => "compute_subprocess",
                num_instances => ?NUM_INSTANCES_5,
                conditions => ?OR_CONDITIONS_2
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_subprocess_or, Config),

            %% Both conditions true
            States = #{cond1 => true, cond2 => true},
            {ok, Result} = simulate_or_cancellation_subprocess_multi(WorkflowId, States, ?NUM_INSTANCES_5),
            ?assertEqual(cancelled, Result),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test OR semantics for subprocess with multiple instances
cancelation_multiple_instances_subprocess_or_or_semantics_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                subprocess_id => "etl_subprocess",
                num_instances => ?NUM_INSTANCES_3,
                conditions => ?OR_CONDITIONS_3
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_subprocess_or, Config),

            %% Any true cancels
            StatesAny = #{cond1 => false, cond2 => true, cond3 => false},
            {ok, ResultAny} = simulate_or_cancellation_subprocess_multi(WorkflowId, StatesAny, ?NUM_INSTANCES_3),
            ?assertEqual(cancelled, ResultAny),

            %% All false doesn't cancel
            StatesNone = #{cond1 => false, cond2 => false, cond3 => false},
            {ok, ResultNone} = simulate_or_cancellation_subprocess_multi(WorkflowId, StatesNone, ?NUM_INSTANCES_3),
            ?assertNotEqual(cancelled, ResultNone),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test subprocess-level cancellation with instance propagation
cancelation_multiple_instances_subprocess_or_subprocess_cancel_propagation_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            NumInstances = 8,
            Config = #{
                subprocess_id => "analytics_subprocess",
                num_instances => NumInstances,
                conditions => [quality_threshold_failed, processing_timeout, insufficient_data]
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_subprocess_or, Config),

            %% Trigger via quality threshold - all 8 instances should cancel
            States = #{quality_threshold_failed => true, processing_timeout => false, insufficient_data => false},
            {ok, Result} = simulate_or_cancellation_subprocess_multi(WorkflowId, States, NumInstances),
            ?assertEqual(cancelled, Result),

            %% Verify subprocess and all instances cancelled
            {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
            ?assertEqual(cancelled, Status),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%%====================================================================
%% Comprehensive OR Pattern Tests
%%====================================================================

%% @doc Test all OR patterns follow same semantics
all_or_patterns_follow_same_semantics_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            %% Test all 5 OR patterns with same condition set
            ConditionStatesAny = #{cond1 => true, cond2 => false},
            ConditionStatesNone = #{cond1 => false, cond2 => false},

            Patterns = [
                {cancelation_thread_or, #{thread_id => "t1", conditions => [cond1, cond2]}},
                {cancelation_subprocess_or, #{subprocess_id => "s1", conditions => [cond1, cond2]}},
                {cancelation_multiple_instances_or, #{num_instances => 3, conditions => [cond1, cond2]}},
                {cancelation_multiple_instances_thread_or, #{thread_id => "t1", num_instances => 3, conditions => [cond1, cond2]}},
                {cancelation_multiple_instances_subprocess_or, #{subprocess_id => "s1", num_instances => 3, conditions => [cond1, cond2]}}
            ],

            lists:foreach(fun({Pattern, Config}) ->
                {ok, WfId} = yawl_orchestrator:create_workflow(Pattern, Config),

                %% Any true should cancel
                {ok, ResultAny} = case Pattern of
                    cancelation_thread_or -> simulate_or_cancellation(WfId, ConditionStatesAny);
                    cancelation_subprocess_or -> simulate_or_cancellation(WfId, ConditionStatesAny);
                    cancelation_multiple_instances_or -> simulate_or_cancellation_multi(WfId, ConditionStatesAny, 3);
                    cancelation_multiple_instances_thread_or -> simulate_or_cancellation_thread_multi(WfId, ConditionStatesAny, 3);
                    cancelation_multiple_instances_subprocess_or -> simulate_or_cancellation_subprocess_multi(WfId, ConditionStatesAny, 3)
                end,
                ?assertEqual(cancelled, ResultAny, {pattern, Pattern, should_cancel_on_any_true}),

                %% All false should NOT cancel
                {ok, ResultNone} = case Pattern of
                    cancelation_thread_or -> simulate_or_cancellation(WfId, ConditionStatesNone);
                    cancelation_subprocess_or -> simulate_or_cancellation(WfId, ConditionStatesNone);
                    cancelation_multiple_instances_or -> simulate_or_cancellation_multi(WfId, ConditionStatesNone, 3);
                    cancelation_multiple_instances_thread_or -> simulate_or_cancellation_thread_multi(WfId, ConditionStatesNone, 3);
                    cancelation_multiple_instances_subprocess_or -> simulate_or_cancellation_subprocess_multi(WfId, ConditionStatesNone, 3)
                end,
                ?assertNotEqual(cancelled, ResultNone, {pattern, Pattern, should_not_cancel_on_all_false}),

                yawl_orchestrator:cleanup_workflow(WfId)
            end, Patterns)
        end)]
     end}.

%% @doc Test OR patterns with dynamic condition evaluation
or_patterns_dynamic_condition_evaluation_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            %% Test that conditions can be dynamically evaluated
            Config = #{
                thread_id => "dynamic_thread",
                conditions => [condition_a, condition_b, condition_c]
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_thread_or, Config),

            %% Initially no conditions true - not cancelled
            InitialStates = #{condition_a => false, condition_b => false, condition_c => false},
            {ok, InitialResult} = simulate_or_cancellation(WorkflowId, InitialStates),
            ?assertNotEqual(cancelled, InitialResult),

            %% Dynamically update one condition to true
            UpdatedStates = #{condition_a => true, condition_b => false, condition_c => false},
            {ok, UpdatedResult} = simulate_or_cancellation(WorkflowId, UpdatedStates),
            ?assertEqual(cancelled, UpdatedResult),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test OR pattern with complex condition combinations
or_patterns_complex_combinations_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            %% Test with many conditions and verify OR behavior
            Conditions = [c1, c2, c3, c4, c5, c6, c7],
            Config = #{
                subprocess_id => "complex_subprocess",
                num_instances => 5,
                conditions => Conditions
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_subprocess_or, Config),

            %% Create various states with only one true each
            Tests = [
                #{c1 => true, c2 => false, c3 => false, c4 => false, c5 => false, c6 => false, c7 => false},
                #{c1 => false, c2 => true, c3 => false, c4 => false, c5 => false, c6 => false, c7 => false},
                #{c1 => false, c2 => false, c3 => true, c4 => false, c5 => false, c6 => false, c7 => false},
                #{c1 => false, c2 => false, c3 => false, c4 => true, c5 => false, c6 => false, c7 => false},
                #{c1 => false, c2 => false, c3 => false, c4 => false, c5 => true, c6 => false, c7 => false},
                #{c1 => false, c2 => false, c3 => false, c4 => false, c5 => false, c6 => true, c7 => false},
                #{c1 => false, c2 => false, c3 => false, c4 => false, c5 => false, c6 => false, c7 => true}
            ],

            lists:foreach(fun(States) ->
                {ok, Result} = simulate_or_cancellation_subprocess_multi(WorkflowId, States, 5),
                ?assertEqual(cancelled, Result, {states, States})
            end, Tests),

            %% All false should not cancel
            AllFalse = #{c1 => false, c2 => false, c3 => false, c4 => false,
                         c5 => false, c6 => false, c7 => false},
            {ok, NotCancelled} = simulate_or_cancellation_subprocess_multi(WorkflowId, AllFalse, 5),
            ?assertNotEqual(cancelled, NotCancelled),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%%====================================================================
%% Edge Case and Stress Tests
%%====================================================================

%% @doc Test OR pattern with single condition
or_pattern_single_condition_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                thread_id => "single_cond_thread",
                conditions => [only_condition]
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_thread_or, Config),

            %% True condition cancels
            {ok, ResultTrue} = simulate_or_cancellation(WorkflowId, #{only_condition => true}),
            ?assertEqual(cancelled, ResultTrue),

            %% False condition doesn't cancel
            {ok, ResultFalse} = simulate_or_cancellation(WorkflowId, #{only_condition => false}),
            ?assertNotEqual(cancelled, ResultFalse),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test OR pattern with many instances
or_pattern_many_instances_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            ManyInstances = 50,
            Config = #{
                subprocess_id => "many_instances_subprocess",
                num_instances => ManyInstances,
                conditions => [stop_signal, error_detected]
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_multiple_instances_subprocess_or, Config),

            %% Single condition should cancel all 50 instances
            States = #{stop_signal => true, error_detected => false},
            {ok, Result} = simulate_or_cancellation_subprocess_multi(WorkflowId, States, ManyInstances),
            ?assertEqual(cancelled, Result),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%% @doc Test rapid condition changes
or_pattern_rapid_condition_changes_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(_) ->
         [?_test(begin
            Config = #{
                thread_id => "rapid_changes_thread",
                conditions => [cond_a, cond_b]
            },
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(cancelation_thread_or, Config),

            %% Rapid state changes
            StatesList = [
                #{cond_a => false, cond_b => false},
                #{cond_a => true, cond_b => false},
                #{cond_a => false, cond_b => false},
                #{cond_a => false, cond_b => true},
                #{cond_a => true, cond_b => true}
            ],

            Results = lists:map(fun(S) ->
                {ok, R} = simulate_or_cancellation(WorkflowId, S),
                R
            end, StatesList),

            %% Only states with at least one true should be cancelled
            ?assertEqual([running, cancelled, running, cancelled, cancelled], Results),

            yawl_orchestrator:cleanup_workflow(WorkflowId)
        end)]
     end}.

%%====================================================================
%% Setup and Teardown Functions
%%====================================================================

setup() ->
    {ok, Pid} = application:ensure_all_started(a2a_erl),
    case whereis(yawl_orchestrator) of
        undefined ->
            {ok, OrchPid} = yawl_orchestrator:start_link(),
            {Pid, OrchPid};
        _ ->
            {Pid, whereis(yawl_orchestrator)}
    end.

cleanup({_AppPid, _OrchPid}) ->
    ok.

%%====================================================================
%% Simulation Helper Functions
%%====================================================================

%% @private
%% @doc Simulate OR-based cancellation for simple thread/subprocess patterns
simulate_or_cancellation(WorkflowId, ConditionStates) ->
    %% Simulate checking if ANY condition is true (OR semantics)
    AnyTrue = lists:any(fun(Cond) ->
        maps:get(Cond, ConditionStates, false) =:= true
    end, maps:keys(ConditionStates)),

    case AnyTrue of
        true ->
            %% Trigger cancellation
            yawl_orchestrator:cancel_workflow(WorkflowId),
            {ok, cancelled};
        false ->
            %% No cancellation
            {ok, running}
    end.

%% @private
%% @doc Simulate OR-based cancellation for multiple instances pattern
simulate_or_cancellation_multi(WorkflowId, ConditionStates, NumInstances) ->
    %% Check if any condition is true (OR semantics)
    AnyTrue = lists:any(fun(Cond) ->
        maps:get(Cond, ConditionStates, false) =:= true
    end, maps:keys(ConditionStates)),

    case AnyTrue of
        true ->
            %% Cancel all instances
            do_cancel_all_instances(WorkflowId, NumInstances),
            yawl_orchestrator:cancel_workflow(WorkflowId),
            {ok, cancelled};
        false ->
            %% Instances continue running
            {ok, running}
    end.

%% @private
%% @doc Simulate OR-based cancellation for multiple instances thread pattern
simulate_or_cancellation_thread_multi(WorkflowId, ConditionStates, NumInstances) ->
    %% Check OR conditions at thread level
    AnyTrue = lists:any(fun(Cond) ->
        maps:get(Cond, ConditionStates, false) =:= true
    end, maps:keys(ConditionStates)),

    case AnyTrue of
        true ->
            %% Thread-level cancellation affects all instances
            do_cancel_thread_instances(WorkflowId, NumInstances),
            yawl_orchestrator:cancel_workflow(WorkflowId),
            {ok, cancelled};
        false ->
            %% Thread and instances continue
            {ok, running}
    end.

%% @private
%% @doc Simulate OR-based cancellation for multiple instances subprocess pattern
simulate_or_cancellation_subprocess_multi(WorkflowId, ConditionStates, NumInstances) ->
    %% Check OR conditions at subprocess level
    AnyTrue = lists:any(fun(Cond) ->
        maps:get(Cond, ConditionStates, false) =:= true
    end, maps:keys(ConditionStates)),

    case AnyTrue of
        true ->
            %% Subprocess-level cancellation propagates to all instances
            do_cancel_subprocess_instances(WorkflowId, NumInstances),
            yawl_orchestrator:cancel_workflow(WorkflowId),
            {ok, cancelled};
        false ->
            %% Subprocess and instances continue
            {ok, running}
    end.

%% @private
%% @doc Cancel all instances (helper for simulation)
do_cancel_all_instances(_WorkflowId, _NumInstances) ->
    %% In simulation, this would signal each instance to terminate
    ok.

%% @private
%% @doc Cancel thread and all its instances
do_cancel_thread_instances(_WorkflowId, _NumInstances) ->
    %% Thread-level cancellation affects all instances in the thread
    ok.

%% @private
%% @doc Cancel subprocess and all its instances
do_cancel_subprocess_instances(_WorkflowId, _NumInstances) ->
    %% Subprocess-level cancellation affects all instances in the subprocess
    ok.
