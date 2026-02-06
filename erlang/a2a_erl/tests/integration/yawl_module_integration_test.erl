%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Module Integration Tests
%%%
%%% This module contains integration tests that verify coordination
%%% between different YAWL modules:
%%% - Patterns ↔ Orchestrator
%%% - Orchestrator ↔ Workflow Instance
%%% - Pattern validation ↔ Workflow creation
%%% - Subscription ↔ Workflow events
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_module_integration_test).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(TEST_TIMEOUT, 10000).  % 10 seconds timeout
-define(DEFAULT_CONFIG, #{task1_name => "task1", task2_name => "task2"}).

%%====================================================================
%% Basic Integration Tests
%%====================================================================

integration_test_() ->
    [{"Start orchestrator and verify module coordination",
      fun test_orchestrator_startup/0},
     {"Patterns and orchestrator information consistency",
      fun test_patterns_orchestrator_consistency/0},
     "Workflow creation through orchestrator uses pattern validation",
      fun test_workflow_creation_validation_integration/0}].

test_orchestrator_startup() ->
    %% Start the orchestrator
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Verify orchestrator is running
        ?assert(is_pid(OrchestratorPid)),
        ?assert(is_process_alive(OrchestratorPid)),

        %% Get patterns from orchestrator and verify they match patterns module
        OrchestratorPatterns = case yawl_orchestrator:list_patterns() of
            {ok, Patterns} -> Patterns;
            _ -> []
        end,

        PatternsModulePatterns = yawl_patterns:list_patterns(),

        %% They should contain the same patterns
        ?assertEqual(length(OrchestratorPatterns), length(PatternsModulePatterns)),
        lists:foreach(fun(Pattern) ->
            ?assert(lists:member(Pattern, PatternsModulePatterns))
        end, OrchestratorPatterns),

        %% Get pattern info through both modules and verify consistency
        case PatternType = basic_sequential of
            _ ->
                {ok, OrchestratorInfo} = yawl_orchestrator:get_pattern_info(PatternType),
                PatternsModuleInfo = yawl_patterns:get_pattern_info(PatternType),

                %% Names should match
                ?assertEqual(maps:get(name, OrchestratorInfo), maps:get(name, PatternsModuleInfo)),

                %% Complexity should match
                ?assertEqual(maps:get(complexity, OrchestratorInfo), maps:get(complexity, PatternsModuleInfo))
        end
    after
        %% Stop the orchestrator
        gen_server:stop(OrchestratorPid)
    end.

test_patterns_orchestrator_consistency() ->
    %% Test that pattern information is consistent between modules
    PatternTypes = [basic_sequential, parallel_split, parallel_join, exclusive_choice],

    lists:foreach(fun(PatternType) ->
        %% Get info from patterns module
        PatternsInfo = yawl_patterns:get_pattern_info(PatternType),

        %% Get info from orchestrator
        {ok, OrchestratorInfo} = yawl_orchestrator:get_pattern_info(PatternType),

        %% Verify consistency
        ?assertEqual(maps:get(name, PatternsInfo), maps:get(name, OrchestratorInfo)),
        ?assertEqual(maps:get(complexity, PatternsInfo), maps:get(complexity, OrchestratorInfo))
    end, PatternTypes).

test_workflow_creation_validation_integration() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Test 1: Valid pattern should pass validation and creation
        ValidConfig = #{pattern_config => #{}, task_names => ["task1", "task2"]},
        ValidationResult1 = yawl_orchestrator:validate_pattern(basic_sequential, ValidConfig),
        CreationResult1 = yawl_orchestrator:create_workflow(basic_sequential, ValidConfig),

        ?assertMatch({ok, true}, ValidationResult1),
        ?assertMatch({ok, _WorkflowId}, CreationResult1),

        %% Test 2: Invalid pattern should fail validation
        InvalidConfig = #{pattern_config => #{branches => 1}},  % Invalid for parallel_split
        ValidationResult2 = yawl_orchestrator:validate_pattern(parallel_split, InvalidConfig),

        ?assertMatch({ok, false}, ValidationResult2),

        %% Test 3: Unknown pattern should fail both validation and creation
        UnknownConfig = #{},
        ValidationResult3 = yawl_orchestrator:validate_pattern(unknown_pattern, UnknownConfig),
        CreationResult3 = yawl_orchestrator:create_workflow(unknown_pattern, UnknownConfig),

        ?assertMatch({ok, false}, ValidationResult3),
        ?assertMatch({error, {unknown_pattern, unknown_pattern}}, CreationResult3)
    after
        gen_server:stop(OrchestratorPid)
    end.

%%====================================================================
%% Workflow Lifecycle Integration Tests
%%====================================================================

workflow_lifecycle_test_() ->
    [{"Complete workflow lifecycle with pattern validation",
      fun test_complete_workflow_lifecycle/0},
     "Multiple patterns in single orchestrator instance",
      fun test_multiple_patterns_integration/0},
     "Workflow status transitions with pattern-specific logic",
      fun test_workflow_status_transitions_integration/0}].

test_complete_workflow_lifecycle() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Step 1: Create workflow
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, ?DEFAULT_CONFIG),

        %% Step 2: Verify creation
        {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
        ?assertEqual(pending, Status),

        %% Step 3: List workflows
        {ok, AllWorkflows} = yawl_orchestrator:list_workflows(),
        ?assert(lists:member(WorkflowId, AllWorkflows)),

        %% Step 4: Subscribe to workflow
        ?assertMatch({ok, _}, yawl_orchestrator:subscribe_to_workflow(WorkflowId, self())),

        %% Step 5: Execute workflow
        {ok, ExecutionInfo} = yawl_orchestrator:execute_workflow(WorkflowId),
        ?assertMatch(#{status := running, instance := _}, ExecutionInfo),

        %% Step 6: Cancel workflow
        ?assertMatch({ok, _}, yawl_orchestrator:cancel_workflow(WorkflowId)),
        ?assertMatch({ok, cancelled}, yawl_orchestrator:get_status(WorkflowId)),

        %% Step 7: Cleanup workflow
        ?assertMatch({ok, _}, yawl_orchestrator:cleanup_workflow(WorkflowId)),

        %% Step 8: Verify cleanup
        ?assertEqual({error, workflow_not_found}, yawl_orchestrator:get_status(WorkflowId))
    after
        gen_server:stop(OrchestratorPid)
    end.

test_multiple_patterns_integration() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Create workflows with different patterns
        Config1 = #{task1_name => "task1", task2_name => "task2"},
        Config2 = #{branches => 3, task_names => ["taskA", "taskB", "taskC"]},
        Config3 = #{conditions => [option1, option2], default_branch => option1},

        {ok, WorkflowId1} = yawl_orchestrator:create_workflow(basic_sequential, Config1),
        {ok, WorkflowId2} = yawl_orchestrator:create_workflow(parallel_split, Config2),
        {ok, WorkflowId3} = yawl_orchestrator:create_workflow(exclusive_choice, Config3),

        %% Verify all patterns are supported
        {ok, AllPatterns} = yawl_orchestrator:list_patterns(),
        ?assert(lists:member(basic_sequential, AllPatterns)),
        ?assert(lists:member(parallel_split, AllPatterns)),
        ?assert(lists:member(exclusive_choice, AllPatterns)),

        %% Verify all workflows exist
        {ok, AllWorkflows} = yawl_orchestrator:list_workflows(),
        ?assertEqual(3, length(AllWorkflows)),
        ?assert(lists:member(WorkflowId1, AllWorkflows)),
        ?assert(lists:member(WorkflowId2, AllWorkflows)),
        ?assert(lists:member(WorkflowId3, AllWorkflows)),

        %% Execute all workflows
        {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId1),
        {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId2),
        {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId3),

        %% Cancel all workflows
        {ok, _} = yawl_orchestrator:cancel_workflow(WorkflowId1),
        {ok, _} = yawl_orchestrator:cancel_workflow(WorkflowId2),
        {ok, _} = yawl_orchestrator:cancel_workflow(WorkflowId3),

        %% Cleanup all workflows
        {ok, _} = yawl_orchestrator:cleanup_workflow(WorkflowId1),
        {ok, _} = yawl_orchestrator:cleanup_workflow(WorkflowId2),
        {ok, _} = yawl_orchestrator:cleanup_workflow(WorkflowId3)

        %% Verify all cleaned up
        {ok, FinalWorkflows} = yawl_orchestrator:list_workflows(),
        ?assertEqual(0, length(FinalWorkflows))
    after
        gen_server:stop(OrchestratorPid)
    end.

test_workflow_status_transitions_integration() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Create a workflow
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, ?DEFAULT_CONFIG),

        %% Initial status
        ?assertMatch({ok, pending}, yawl_orchestrator:get_status(WorkflowId)),

        %% Execute workflow
        {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
        ?assertMatch({ok, running}, yawl_orchestrator:get_status(WorkflowId)),

        %% Cancel workflow
        ?assertMatch({ok, _}, yawl_orchestrator:cancel_workflow(WorkflowId)),
        ?assertMatch({ok, cancelled}, yawl_orchestrator:get_status(WorkflowId)),

        %% Try to execute cancelled workflow (should work but might fail in real implementation)
        %% For now, we just verify the status doesn't change back to running
        {ok, StatusAfterCancel} = yawl_orchestrator:get_status(WorkflowId),
        ?assertEqual(cancelled, StatusAfterCancel)
    after
        gen_server:stop(OrchestratorPid)
    end.

%%====================================================================
 Error Handling Integration Tests
%%====================================================================

error_handling_integration_test_() ->
    {"Error propagation between modules",
      fun test_error_propagation_integration/0},
     "Invalid workflow IDs across modules",
      fun test_invalid_workflow_ids_integration/0},
     "Concurrent error scenarios",
      fun test_concurrent_error_scenarios/0}].

test_error_propagation_integration() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Test 1: Get pattern info for non-existent pattern
        Result1 = yawl_orchestrator:get_pattern_info(unknown_pattern),
        ?assertEqual({error, pattern_not_found}, Result1),

        %% Test 2: Create workflow with invalid pattern (error already handled at validation step)
        InvalidConfig = #{},
        ValidationResult = yawl_orchestrator:validate_pattern(unknown_pattern, InvalidConfig),
        ?assertMatch({ok, false}, ValidationResult),

        %% Test 3: Operations on non-existent workflow
        NonExistentId = <<"non_existent_id">>,

        StatusResult = yawl_orchestrator:get_status(NonExistentId),
        ?assertEqual({error, workflow_not_found}, StatusResult),

        ExecuteResult = yawl_orchestrator:execute_workflow(NonExistentId),
        ?assertEqual({error, workflow_not_found}, ExecuteResult),

        CancelResult = yawl_orchestrator:cancel_workflow(NonExistentId),
        ?assertEqual({error, workflow_not_found}, CancelResult),

        CleanupResult = yawl_orchestrator:cleanup_workflow(NonExistentId),
        ?assertEqual({error, workflow_not_found}, CleanupResult),

        %% Test 4: Get result for non-completed workflow
        CreateResult = yawl_orchestrator:create_workflow(basic_sequential, ?DEFAULT_CONFIG),
        {ok, ValidWorkflowId} = CreateResult,

        ResultResult = yawl_orchestrator:get_workflow_result(ValidWorkflowId),
        ?assertEqual({error, workflow_not_completed}, ResultResult)
    after
        gen_server:stop(OrchestratorPid)
    end.

test_invalid_workflow_ids_integration() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Test various invalid IDs across all operations
        InvalidIds = [undefined, "not_binary", <<>>, 123, []],

        OperationResults = lists:map(fun(Id) ->
            Status = yawl_orchestrator:get_status(Id),
            Execute = yawl_orchestrator:execute_workflow(Id),
            Cancel = yawl_orchestrator:cancel_workflow(Id),
            Cleanup = yawl_orchestrator:cleanup_workflow(Id),
            Result = yawl_orchestrator:get_workflow_result(Id),
            Subscribe = yawl_orchestrator:subscribe_to_workflow(Id, self()),
            Unsubscribe = yawl_orchestrator:unsubscribe_from_workflow(Id, self()),

            #{
                status => Status,
                execute => Execute,
                cancel => Cancel,
                cleanup => Cleanup,
                result => Result,
                subscribe => Subscribe,
                unsubscribe => Unsubscribe
            }
        end, InvalidIds),

        %% All operations should fail with workflow_not_found or similar error
        lists:foreach(fun(Result) ->
            ?assertEqual({error, workflow_not_found}, maps:get(status, Result)),
            ?assertEqual({error, workflow_not_found}, maps:get(execute, Result)),
            ?assertEqual({error, workflow_not_found}, maps:get(cancel, Result)),
            ?assertEqual({error, workflow_not_found}, maps:get(cleanup, Result)),
            ?assertEqual({error, workflow_not_found}, maps:get(result, Result)),
            ?assertEqual({error, workflow_not_found}, maps:get(subscribe, Result)),
            ?assertEqual({error, workflow_not_found}, maps:get(unsubscribe, Result))
        end, OperationResults)
    after
        gen_server:stop(OrchestratorPid)
    end.

test_concurrent_error_scenarios() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Create a valid workflow
        {ok, ValidWorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, ?DEFAULT_CONFIG),

        %% Concurrent operations that might cause errors
        NumProcesses = 10,
        Processes = lists:map(fun(_) ->
            spawn(fun() ->
                %% Each process tries various operations
                _ = yawl_orchestrator:get_status(ValidWorkflowId),
                _ = yawl_orchestrator:get_pattern_info(basic_sequential),
                _ = yawl_orchestrator:list_workflows(),
                _ = yawl_orchestrator:get_workflow_result(ValidWorkflowId)  % This might fail
            end)
        end, lists:seq(1, NumProcesses)),

        %% Wait for all processes to complete or timeout
        lists:foreach(fun(Pid) ->
            receive
                {'DOWN', _, process, Pid, _} -> ok
            after 5000 ->
                exit(Pid, kill)
            end
        end, Processes),

        %% The orchestrator should still be functional
        ?assertMatch({ok, pending}, yawl_orchestrator:get_status(ValidWorkflowId))
    after
        gen_server:stop(OrchestratorPid)
    end.

%%====================================================================
 Performance Integration Tests
%%====================================================================

performance_integration_test_() ->
    {"Performance test with multiple patterns",
      fun test_multiple_patterns_performance/0},
     "Concurrent workflow operations performance",
      fun test_concurrent_operations_performance/0},
     "Large workflow list performance",
      fun test_large_workflow_list_performance/0}].

test_multiple_patterns_performance() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Test pattern info retrieval for all patterns
        Patterns = yawl_patterns:list_patterns(),
        Start = erlang:monotonic_time(microsecond),

        %% Get pattern info for all patterns through orchestrator
        PatternInfoResults = lists:map(fun(Pattern) ->
            {Pattern, yawl_orchestrator:get_pattern_info(Pattern)}
        end, Patterns),

        End = erlang:monotonic_time(microsecond),
        Duration = End - Start,

        %% Verify all results
        lists:foreach(fun({Pattern, Result}) ->
            case Pattern of
                _ when is_atom(Pattern) ->
                    case Result of
                        {ok, _} -> ok;
                        {error, pattern_not_found} -> ok  % Some patterns might not be in orchestrator
                    end
            end
        end, PatternInfoResults),

        %% Performance assertion (should complete within 5 seconds)
        ?assert(Duration < 5000000, "Pattern info retrieval took too long: ~p μs", [Duration]),
        io:format("Retrieved ~p pattern infos in ~p μs~n", [length(Patterns), Duration])
    after
        gen_server:stop(OrchestratorPid)
    end.

test_concurrent_operations_performance() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Create a base workflow
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, ?DEFAULT_CONFIG),

        %% Concurrent operations
        NumOperations = 50,
        Start = erlang:monotonic_time(microsecond),

        Operations = lists:map(fun(_) ->
            spawn(fun() ->
                %% Each process does multiple operations
                _ = yawl_orchestrator:get_status(WorkflowId),
                _ = yawl_orchestrator:get_pattern_info(basic_sequential),
                _ = yawl_orchestrator:list_workflows(),
                _ = yawl_orchestrator:validate_pattern(basic_sequential, ?DEFAULT_CONFIG)
            end)
        end, lists:seq(1, NumOperations)),

        %% Wait for all operations to complete
        lists:foreach(fun(Pid) ->
            receive
                {'DOWN', _, process, Pid, _} -> ok
            after 10000 ->
                exit(Pid, kill)
            end
        end, Operations),

        End = erlang:monotonic_time(microsecond),
        Duration = End - Start,

        ?assert(Duration < 10000000, "Concurrent operations took too long: ~p μs", [Duration]),
        io:format("Completed ~p concurrent operations in ~p μs~n", [NumOperations * 4, Duration])
    after
        gen_server:stop(OrchestratorPid)
    end.

test_large_workflow_list_performance() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Create many workflows
        NumWorkflows = 100,
        WorkflowIds = lists:foldl(fun(_, Acc) ->
            Config = #{task1_name => "task" ++ integer_to_list(length(Acc) + 1)},
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
            [WorkflowId | Acc]
        end, [], lists:seq(1, NumWorkflows)),

        %% Test list_workflows performance
        Start = erlang:monotonic_time(microsecond),
        {ok, ListedWorkflows} = yawl_orchestrator:list_workflows(),
        End = erlang:monotonic_time(microsecond),
        ListDuration = End - Start,

        %% Verify we got all workflows
        ?assertEqual(NumWorkflows, length(ListedWorkflows)),
        lists:foreach(fun(Id) ->
            ?assert(lists:member(Id, ListedWorkflows))
        end, WorkflowIds),

        ?assert(ListDuration < 500000, "List workflows took too long: ~p μs", [ListDuration]),
        io:format("Listed ~p workflows in ~p μs~n", [NumWorkflows, ListDuration])
    after
        %% Cleanup
        lists:foreach(fun(Id) ->
            _ = yawl_orchestrator:cleanup_workflow(Id)
        end, WorkflowIds),
        gen_server:stop(OrchestratorPid)
    end.

%%====================================================================
 Stress Integration Tests
%%====================================================================

stress_integration_test_() ->
    {"Stress test with rapid workflow churn",
      fun test_rapid_workflow_churn/0},
     "Stress test with concurrent creation and cancellation",
      fun test_concurrent_creation_cancellation/0},
     "Stress test with large number of subscriptions",
      fun test_large_subscription_stress/0}].

test_rapid_workflow_churn() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Rapidly create, execute, cancel, and cleanup workflows
        NumCycles = 50,
        Start = erlang:monotonic_time(microsecond),

        lists:seq(1, NumCycles),
        lists:foreach(fun(_) ->
            Config = #{task1_name => "task" ++ integer_to_list(rand:uniform(1000))},
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
            {ok, _} = yawl_orchestrator:get_status(WorkflowId),
            {ok, _} = yawl_orchestrator:cancel_workflow(WorkflowId),
            {ok, _} = yawl_orchestrator:cleanup_workflow(WorkflowId)
        end, lists:seq(1, NumCycles)),

        End = erlang:monotonic_time(microsecond),
        Duration = End - Start,

        %% Verify system is still stable
        {ok, FinalWorkflows} = yawl_orchestrator:list_workflows(),
        ?assertEqual(0, length(FinalWorkflows)),

        io:format("Completed ~p churn cycles in ~p μs~n", [NumCycles, Duration])
    after
        gen_server:stop(OrchestratorPid)
    end.

test_concurrent_creation_cancellation() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Spawn processes that create and cancel workflows
        NumProcesses = 20,
        Start = erlang:monotonic_time(microsecond),

        Processes = lists:map(fun(PidNum) ->
            spawn(fun() ->
                Config = #{task1_name => "task" ++ integer_to_list(PidNum)},
                {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
                timer:sleep(rand:uniform(100)),  % Small delay
                {ok, _} = yawl_orchestrator:cancel_workflow(WorkflowId),
                {ok, _} = yawl_orchestrator:cleanup_workflow(WorkflowId)
            end)
        end, lists:seq(1, NumProcesses)),

        %% Wait for all processes
        lists:foreach(fun(Pid) ->
            receive
                {'DOWN', _, process, Pid, _} -> ok
            after 10000 ->
                exit(Pid, kill)
            end
        end, Processes),

        End = erlang:monotonic_time(microsecond),
        Duration = End - Start,

        %% System should be stable
        {ok, FinalWorkflows} = yawl_orchestrator:list_workflows(),
        ?assertEqual(0, length(FinalWorkflows)),

        io:format("Completed ~p concurrent creation/cancellation operations in ~p μs~n",
                 [NumProcesses, Duration])
    after
        gen_server:stop(OrchestratorPid)
    end.

test_large_subscription_stress() ->
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),

    try
        %% Create a workflow
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, ?DEFAULT_CONFIG),

        Subscribe many subscribers
        NumSubscribers = 100,
        Subscribers = lists:map(fun(_) ->
            Pid = spawn(fun() -> receive after infinity -> ok end end),
            ?assertMatch({ok, _}, yawl_orchestrator:subscribe_to_workflow(WorkflowId, Pid)),
            Pid
        end, lists:seq(1, NumSubscribers)),

        %% Verify subscription (by checking if unsubscribe works)
        lists:foreach(fun(Pid) ->
            ?assertMatch({ok, _}, yawl_orchestrator:unsubscribe_from_workflow(WorkflowId, Pid)),
            exit(Pid, kill)
        end, Subscribers),

        %% System should handle this fine
        {ok, Workflows} = yawl_orchestrator:list_workflows(),
        ?assertEqual(1, length(Workflows)),

        io:format("Successfully handled ~p subscriptions~n", [NumSubscribers])
    after
        gen_server:stop(OrchestratorPid)
    end.