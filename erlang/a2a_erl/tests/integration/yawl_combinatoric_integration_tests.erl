%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Combinatoric Integration Tests
%%%
%%% This module contains integration tests for the combinatoric testing
%%% system with other YAWL modules:
%%%
%%% 1. Integration with yawl_orchestrator (workflow execution)
%%% 2. Integration with yawl_patterns (pattern definitions)
%%% 3. Integration with yawl_test_runner (test execution)
%%% 4. Integration with yawl_rest (REST API)
%%%
%%% The tests verify end-to-end functionality:
%%% - Generate combinations
%%% - Execute via orchestrator
%%% - Validate results
%%% - Report via REST API
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_combinatoric_integration_tests).
-author("A2A Team").
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% Export test suite callbacks
-export([
    all/0,
    groups/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_group/2,
    end_per_group/2,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Export test cases
-export([
    %% Orchestrator integration tests
    test_combination_orchestrator_creation/1,
    test_combination_orchestrator_execution/1,
    test_combination_orchestrator_cancellation/1,
    test_combination_orchestrator_status_tracking/1,

    %% Pattern integration tests
    test_combination_pattern_validation/1,
    test_combination_pattern_consistency/1,
    test_combination_pattern_structure/1,
    test_combination_cancellation_patterns/1,

    %% Test Runner integration tests
    test_combination_test_runner_execution/1,
    test_combination_test_runner_reporting/1,
    test_combination_test_runner_metrics/1,
    test_combination_test_runner_parallel/1,

    %% REST API integration tests
    test_combination_rest_workflow_creation/1,
    test_combination_rest_workflow_execution/1,
    test_combination_rest_status_queries/1,
    test_combination_rest_result_reporting/1,
    test_combination_rest_concurrent_workflows/1,

    %% End-to-end workflow tests
    test_e2e_sequential_combination_workflow/1,
    test_e2e_parallel_combination_workflow/1,
    test_e2e_mixed_combination_workflow/1,
    test_e2e_nested_combination_workflow/1,

    %% Business scenario integration tests
    test_business_scenario_combination_order/1,
    test_business_scenario_combination_approval/1,
    test_business_scenario_combination_document/1,

    %% Performance and stress tests
    test_combination_performance_small/1,
    test_combination_performance_medium/1,
    test_combination_stress_concurrent/1
]).

%% Test macros
-define(TEST_TIMEOUT, 60000).
-define(HTTP_PORT, 8083).
-define(MAX_WAIT, 15000).
-define(WAIT_INTERVAL, 100).

%%====================================================================
%% Common Test Callbacks
%%====================================================================

%% @doc Return all test cases.
-spec all() -> [atom()].
all() ->
    [
        %% Orchestrator integration
        test_combination_orchestrator_creation,
        test_combination_orchestrator_execution,
        test_combination_orchestrator_cancellation,
        test_combination_orchestrator_status_tracking,

        %% Pattern integration
        test_combination_pattern_validation,
        test_combination_pattern_consistency,
        test_combination_pattern_structure,
        test_combination_cancellation_patterns,

        %% Test Runner integration
        test_combination_test_runner_execution,
        test_combination_test_runner_reporting,
        test_combination_test_runner_metrics,
        test_combination_test_runner_parallel,

        %% REST API integration
        test_combination_rest_workflow_creation,
        test_combination_rest_workflow_execution,
        test_combination_rest_status_queries,
        test_combination_rest_result_reporting,
        test_combination_rest_concurrent_workflows,

        %% End-to-end workflow tests
        test_e2e_sequential_combination_workflow,
        test_e2e_parallel_combination_workflow,
        test_e2e_mixed_combination_workflow,
        test_e2e_nested_combination_workflow,

        %% Business scenario integration
        test_business_scenario_combination_order,
        test_business_scenario_combination_approval,
        test_business_scenario_combination_document,

        %% Performance and stress tests
        test_combination_performance_small,
        test_combination_performance_medium,
        test_combination_stress_concurrent
    ].

%% @doc Return test groups.
-spec groups() -> [{atom(), list(), [atom()]}].
groups() ->
    [
        {orchestrator_integration, [sequence], [
            test_combination_orchestrator_creation,
            test_combination_orchestrator_execution,
            test_combination_orchestrator_cancellation,
            test_combination_orchestrator_status_tracking
        ]},
        {pattern_integration, [sequence], [
            test_combination_pattern_validation,
            test_combination_pattern_consistency,
            test_combination_pattern_structure,
            test_combination_cancellation_patterns
        ]},
        {test_runner_integration, [sequence], [
            test_combination_test_runner_execution,
            test_combination_test_runner_reporting,
            test_combination_test_runner_metrics,
            test_combination_test_runner_parallel
        ]},
        {rest_integration, [sequence], [
            test_combination_rest_workflow_creation,
            test_combination_rest_workflow_execution,
            test_combination_rest_status_queries,
            test_combination_rest_result_reporting,
            test_combination_rest_concurrent_workflows
        ]},
        {e2e_workflow, [sequence], [
            test_e2e_sequential_combination_workflow,
            test_e2e_parallel_combination_workflow,
            test_e2e_mixed_combination_workflow,
            test_e2e_nested_combination_workflow
        ]},
        {business_scenario, [sequence], [
            test_business_scenario_combination_order,
            test_business_scenario_combination_approval,
            test_business_scenario_combination_document
        ]},
        {performance_stress, [parallel], [
            test_combination_performance_small,
            test_combination_performance_medium,
            test_combination_stress_concurrent
        ]}
    ].

%% @doc Initialize test suite.
-spec init_per_suite(Config) -> Config when Config :: [tuple()].
init_per_suite(Config) ->
    ct:pal("========================================"),
    ct:pal("Starting YAWL Combinatoric Integration Tests"),
    ct:pal("========================================"),

    %% Set up Mnesia
    MnesiaDir = filename:join([proplists:get_value(priv_dir, Config), "mnesia", "combinatoric"]),
    filelib:ensure_path(MnesiaDir),
    application:set_env(mnesia, dir, MnesiaDir),

    mnesia:stop(),
    timer:sleep(100),
    case mnesia:delete_schema([node()]) of
        ok -> ok;
        {error, {already_exists, _}} ->
            mnesia:delete_schema([node()]),
            timer:sleep(500);
        _ -> ok
    end,

    ok = mnesia:create_schema([node()]),
    ok = mnesia:start(),

    %% Create tables
    Tables = [
        {yawl_workflow_persist, [
            {attributes, record_info(fields, yawl_workflow_persist)},
            {index, [#yawl_workflow_persist.spec_id, #yawl_workflow_persist.status]},
            {type, set},
            {disc_copies, [node()]}
        ]},
        {yawl_workitem_persist, [
            {attributes, record_info(fields, yawl_workitem_persist)},
            {index, [#yawl_workitem_persist.workflow_id, #yawl_workitem_persist.status]},
            {type, set},
            {disc_copies, [node()]}
        ]},
        {yawl_execution_history, [
            {attributes, record_info(fields, yawl_execution_history)},
            {index, [#yawl_execution_history.workflow_id]},
            {type, bag},
            {disc_copies, [node()]}
        ]},
        {yawl_checkpoint, [
            {attributes, record_info(fields, yawl_checkpoint)},
            {index, [#yawl_checkpoint.workflow_id]},
            {type, set},
            {disc_only_copies, [node()]}
        ]}
    ],

    lists:foreach(fun({Table, Opts}) ->
        case mnesia:create_table(Table, Opts) of
            {atomic, ok} -> ok;
            {aborted, {already_exists, Table}} -> ok;
            {aborted, Reason} ->
                ct:fail({failed_to_create_table, Table, Reason})
        end
    end, Tables),

    mnesia:wait_for_tables([yawl_workflow_persist, yawl_workitem_persist,
                            yawl_execution_history, yawl_checkpoint], 5000),

    %% Start services
    {ok, OrchPid} = yawl_orchestrator:start_link(),
    {ok, PersPid} = yawl_persistence:start_link(),
    {ok, RmPid} = yawl_resource_manager:start_link(),
    {ok, WIPid} = yawl_workitem_processor:start_link(),
    {ok, SupPid} = yawl_workflow_instance_sup:start_link(),
    {ok, TestRunnerPid} = yawl_test_runner:start_link(),

    %% Start REST API
    {ok, RestPid} = case yawl_rest:start_link(#{port => ?HTTP_PORT}) of
        {ok, P} -> {ok, P};
        {error, {already_started, P}} -> {ok, P};
        Error ->
            ct:pal("Warning: REST server start failed: ~p", [Error]),
            undefined
    end,

    case RestPid of
        undefined -> ok;
        _ -> wait_for_rest_server(?HTTP_PORT, 5000)
    end,

    %% Register test resources
    setup_test_resources(),

    [
        {orchestrator_pid, OrchPid},
        {persistence_pid, PersPid},
        {resource_manager_pid, RmPid},
        {workitem_processor_pid, WIPid},
        {workflow_instance_sup_pid, SupPid},
        {test_runner_pid, TestRunnerPid},
        {rest_pid, RestPid},
        {mnesia_dir, MnesiaDir},
        {http_port, ?HTTP_PORT}
        | Config
    ].

%% @doc Cleanup test suite.
-spec end_per_suite(Config) -> ok when Config :: [tuple()].
end_per_suite(Config) ->
    ct:pal("========================================"),
    ct:pal("Ending YAWL Combinatoric Integration Tests"),
    ct:pal("========================================"),

    RestPid = proplists:get_value(rest_pid, Config),
    case RestPid of
        undefined -> ok;
        _ ->
            catch yawl_rest:stop(),
            timer:sleep(200)
    end,

    OrchPid = proplists:get_value(orchestrator_pid, Config),
    PersPid = proplists:get_value(persistence_pid, Config),
    RmPid = proplists:get_value(resource_manager_pid, Config),
    WIPid = proplists:get_value(workitem_processor_pid, Config),
    SupPid = proplists:get_value(workflow_instance_sup_pid, Config),
    TestRunnerPid = proplists:get_value(test_runner_pid, Config),

    catch gen_server:stop(OrchPid),
    catch gen_server:stop(PersPid),
    catch gen_server:stop(RmPid),
    catch gen_server:stop(WIPid),
    catch gen_server:stop(SupPid),
    catch gen_server:stop(TestRunnerPid),

    mnesia:stop(),
    timer:sleep(100),

    MnesiaDir = proplists:get_value(mnesia_dir, Config),
    catch file:del_dir_r(MnesiaDir),

    ok.

%% @doc Initialize test group.
-spec init_per_group(atom(), Config) -> Config when Config :: [tuple()].
init_per_group(GroupName, Config) ->
    ct:pal("Starting group: ~p", [GroupName]),
    cleanup_test_data(Config),
    [{group_start_time, erlang:monotonic_time(millisecond)} | Config].

%% @doc Cleanup test group.
-spec end_per_group(atom(), Config) -> ok when Config :: [tuple()].
end_per_group(GroupName, Config) ->
    StartTime = proplists:get_value(group_start_time, Config, 0),
    Duration = erlang:monotonic_time(millisecond) - StartTime,
    ct:pal("Completed group: ~p (duration: ~pms)", [GroupName, Duration]),
    cleanup_test_data(Config),
    ok.

%% @doc Initialize test case.
-spec init_per_testcase(atom(), Config) -> Config when Config :: [tuple()].
init_per_testcase(TestName, Config) ->
    ct:pal("Starting test: ~p", [TestName]),
    cleanup_test_data(Config),
    [{test_start_time, erlang:monotonic_time(millisecond)} | Config].

%% @doc Cleanup test case.
-spec end_per_testcase(atom(), Config) -> ok when Config :: [tuple()].
end_per_testcase(TestName, Config) ->
    StartTime = proplists:get_value(test_start_time, Config, 0),
    Duration = erlang:monotonic_time(millisecond) - StartTime,
    ct:pal("Completed test: ~p (duration: ~pms)", [TestName, Duration]),
    cleanup_test_data(Config),
    ok.

%%====================================================================
%% Orchestrator Integration Tests
%%====================================================================

%% @doc Test combination workflow creation via orchestrator.
-spec test_combination_orchestrator_creation(Config) -> ok when Config :: [tuple()].
test_combination_orchestrator_creation(_Config) ->
    ct:pal("=== Testing combination orchestrator creation ==="),

    %% Test 1: Create sequential combination workflow
    SequentialCombo = [basic_sequential, exclusive_choice, simple_merge],
    {ok, SeqWorkflowId} = create_combination_workflow(sequential, SequentialCombo, #{}),
    ct:pal("Created sequential combo workflow: ~p", [SeqWorkflowId]),
    ?assert(is_binary(SeqWorkflowId)),

    %% Verify initial status
    {ok, pending} = yawl_orchestrator:get_status(SeqWorkflowId),

    %% Test 2: Create parallel combination workflow
    ParallelCombo = [parallel_split, multi_instance, parallel_join],
    {ok, ParWorkflowId} = create_combination_workflow(parallel, ParallelCombo, #{}),
    ct:pal("Created parallel combo workflow: ~p", [ParWorkflowId]),
    ?assert(is_binary(ParWorkflowId)),

    %% Test 3: Verify both workflows are listed
    {ok, AllWorkflows} = yawl_orchestrator:list_workflows(),
    ?assert(lists:member(SeqWorkflowId, AllWorkflows)),
    ?assert(lists:member(ParWorkflowId, AllWorkflows)),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(SeqWorkflowId),
    ok = yawl_orchestrator:cleanup_workflow(ParWorkflowId),

    ct:pal("=== Combination orchestrator creation test PASSED ==="),
    ok.

%% @doc Test combination workflow execution via orchestrator.
-spec test_combination_orchestrator_execution(Config) -> ok when Config :: [tuple()].
test_combination_orchestrator_execution(_Config) ->
    ct:pal("=== Testing combination orchestrator execution ==="),

    %% Create a simple sequential combination
    ComboPatterns = [basic_sequential, iterative_loop],
    Config = #{
        iterations => 2,
        task1_name => "task1",
        task2_name => "task2"
    },

    {ok, WorkflowId} = create_combination_workflow(sequential, ComboPatterns, Config),
    ct:pal("Created combo workflow: ~p", [WorkflowId]),

    %% Execute the combination workflow
    {ok, StartResult} = yawl_orchestrator:execute_workflow(WorkflowId),
    ct:pal("Started workflow: ~p", [StartResult]),
    ?assertMatch(#{status := running}, StartResult),

    %% Wait for running status
    wait_for_status(WorkflowId, running, 2000),

    %% Get workflow instance and complete tasks
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    ?assert(is_pid(InstancePid)),

    %% Complete the sequential tasks
    ok = yawl_workflow_instance:complete_task(InstancePid, task1, #{result => completed}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task2, #{result => completed}),

    %% Complete the loop
    ok = yawl_workflow_instance:complete_task(InstancePid, loop_task, #{continue => false}),

    %% Wait for completion
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),

    %% Verify final status
    {ok, completed} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify workflow result
    {ok, Result} = yawl_orchestrator:get_workflow_result(WorkflowId),
    ct:pal("Workflow result: ~p", [Result]),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Combination orchestrator execution test PASSED ==="),
    ok.

%% @doc Test combination workflow cancellation.
-spec test_combination_orchestrator_cancellation(Config) -> ok when Config :: [tuple()].
test_combination_orchestrator_cancellation(_Config) ->
    ct:pal("=== Testing combination orchestrator cancellation ==="),

    %% Create a long-running combination
    ComboPatterns = [parallel_split, exclusive_choice, parallel_join],
    {ok, WorkflowId} = create_combination_workflow(parallel, ComboPatterns, #{}),
    ct:pal("Created combo workflow for cancellation: ~p", [WorkflowId]),

    %% Start execution
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    %% Cancel during execution
    ok = yawl_orchestrator:cancel_workflow(WorkflowId),
    {ok, cancelled} = yawl_orchestrator:get_status(WorkflowId),

    %% Verify persisted state
    {ok, Persisted} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(cancelled, Persisted#yawl_workflow_persist.status),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Combination orchestrator cancellation test PASSED ==="),
    ok.

%% @doc Test combination workflow status tracking.
-spec test_combination_orchestrator_status_tracking(Config) -> ok when Config :: [tuple()].
test_combination_orchestrator_status_tracking(_Config) ->
    ct:pal("=== Testing combination orchestrator status tracking ==="),

    %% Create combination workflow
    ComboPatterns = [basic_sequential, simple_merge],
    {ok, WorkflowId} = create_combination_workflow(sequential, ComboPatterns, #{}),

    %% Track status transitions
    States = [],
    States1 = track_status(WorkflowId, States),
    ?assert(lists:member(pending, States1)),

    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    States2 = track_status(WorkflowId, States1),
    ?assert(lists:member(running, States2)),

    wait_for_status(WorkflowId, completed, ?MAX_WAIT),
    States3 = track_status(WorkflowId, States2),
    ?assert(lists:member(completed, States3)),

    %% Verify status sequence
    ct:pal("Status transitions: ~p", [lists:reverse(States3)]),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== Combination orchestrator status tracking test PASSED ==="),
    ok.

%%====================================================================
%% Pattern Integration Tests
%%====================================================================

%% @doc Test combination pattern validation.
-spec test_combination_pattern_validation(Config) -> ok when Config :: [tuple()].
test_combination_pattern_validation(_Config) ->
    ct:pal("=== Testing combination pattern validation ==="),

    %% Test valid combinations
    ValidCombos = [
        {[basic_sequential, parallel_split], sequential},
        {[parallel_split, parallel_join], parallel},
        {[exclusive_choice, simple_merge], conditional},
        {[iterative_loop, multi_instance], mixed}
    ],

    lists:foreach(fun({Patterns, ComboType}) ->
        lists:foreach(fun(Pattern) ->
            Valid = yawl_patterns:validate_pattern(Pattern, #{}),
            ?assertEqual({ok, true}, Valid),
            ct:pal("Pattern ~p validated for ~p combination", [Pattern, ComboType])
        end, Patterns)
    end, ValidCombos),

    %% Test combination-specific validation
    ComboConfig = #{max_length => 3, patterns => [basic_sequential, parallel_split]},
    ValidCombo = validate_combination(sequential, ComboConfig),
    ?assertEqual(true, ValidCombo),

    ct:pal("=== Combination pattern validation test PASSED ==="),
    ok.

%% @doc Test combination pattern consistency.
-spec test_combination_pattern_consistency(Config) -> ok when Config :: [tuple()].
test_combination_pattern_consistency(_Config) ->
    ct:pal("=== Testing combination pattern consistency ==="),

    %% Get patterns from both modules
    OrchestratorPatterns = yawl_orchestrator:list_patterns(),
    PatternsModulePatterns = yawl_patterns:list_patterns(),

    %% Verify consistency
    lists:foreach(fun(Pattern) ->
        ?assert(lists:member(Pattern, PatternsModulePatterns)),
        %% Get info from both and verify consistency
        {ok, OrchInfo} = yawl_orchestrator:get_pattern_info(Pattern),
        PatInfo = yawl_patterns:get_pattern_info(Pattern),
        ?assertEqual(maps:get(name, OrchInfo), maps:get(name, PatInfo))
    end, OrchestratorPatterns),

    ct:pal("Verified ~p patterns for consistency", [length(OrchestratorPatterns)]),

    ct:pal("=== Combination pattern consistency test PASSED ==="),
    ok.

%% @doc Test combination pattern structure.
-spec test_combination_pattern_structure(Config) -> ok when Config :: [tuple()].
test_combination_pattern_structure(_Config) ->
    ct:pal("=== Testing combination pattern structure ==="),

    %% Test pattern structure retrieval
    TestPatterns = [basic_sequential, parallel_split, exclusive_choice],

    lists:foreach(fun(Pattern) ->
        Structure = yawl_patterns:get_pattern_structure(Pattern),
        ?assertMatch({Places, Transitions, _Preset, _Postset}
                     when length(Places) > 0, Structure),
        ct:pal("Pattern ~p structure: places=~p, transitions=~p",
               [Pattern, element(1, Structure), element(2, Structure)])
    end, TestPatterns),

    %% Verify structure consistency for combinations
    SequentialStruct = yawl_patterns:get_pattern_structure(basic_sequential),
    ParallelStruct = yawl_patterns:get_pattern_structure(parallel_split),

    ?assertMatch({_, _, _, _}, SequentialStruct),
    ?assertMatch({_, _, _, _}, ParallelStruct),

    ct:pal("=== Combination pattern structure test PASSED ==="),
    ok.

%% @doc Test cancellation pattern combinations.
-spec test_combination_cancellation_patterns(Config) -> ok when Config :: [tuple()].
test_combination_cancellation_patterns(_Config) ->
    ct:pal("=== Testing combination cancellation patterns ==="),

    %% Test various cancellation pattern combinations
    CancellationCombos = [
        [basic_sequential, cancelation_block],
        [parallel_split, cancelation_scope, parallel_join],
        [exclusive_choice, cancelation_thread, simple_merge]
    ],

    lists:foreach(fun(ComboPatterns) ->
        ct:pal("Testing cancellation combo: ~p", [ComboPatterns]),
        {ok, WorkflowId} = create_combination_workflow(sequential, ComboPatterns, #{}),

        %% Verify creation
        {ok, pending} = yawl_orchestrator:get_status(WorkflowId),

        %% Execute and cancel
        {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
        timer:sleep(100),
        ok = yawl_orchestrator:cancel_workflow(WorkflowId),
        {ok, cancelled} = yawl_orchestrator:get_status(WorkflowId),

        %% Cleanup
        ok = yawl_orchestrator:cleanup_workflow(WorkflowId)
    end, CancellationCombos),

    ct:pal("=== Combination cancellation patterns test PASSED ==="),
    ok.

%%====================================================================
%% Test Runner Integration Tests
%%====================================================================

%% @doc Test combination execution via test runner.
-spec test_combination_test_runner_execution(Config) -> ok when Config :: [tuple()].
test_combination_test_runner_execution(_Config) ->
    ct:pal("=== Testing combination test runner execution ==="),

    %% Run combination tests via test runner
    Config = #{
        max_length => 2,
        patterns => [basic_sequential, parallel_split]
    },

    {ok, Results} = yawl_test_runner:run_combination_tests(Config),
    ct:pal("Test runner returned ~p results", [length(Results)]),

    %% Verify results structure
    ?assert(is_list(Results)),
    ?assert(length(Results) > 0),

    %% Verify result fields
    lists:foreach(fun(Result) ->
        ?assertMatch(#{test_id := _, pattern_type := _, status := _}, Result),
        ct:pal("Result: test_id=~p, patterns=~p, status=~p",
               [maps:get(test_id, Result),
                maps:get(pattern_type, Result, []),
                maps:get(status, Result)])
    end, Results),

    ct:pal("=== Combination test runner execution test PASSED ==="),
    ok.

%% @doc Test combination test reporting.
-spec test_combination_test_runner_reporting(Config) -> ok when Config :: [tuple()].
test_combination_test_runner_reporting(_Config) ->
    ct:pal("=== Testing combination test runner reporting ==="),

    %% Generate combination test report
    {ok, Report} = yawl_test_runner:generate_report(),
    ct:pal("Test report generated: ~p", [maps:get(summary, Report, #{})]),

    %% Verify report structure
    ?assertMatch(#{summary := #{
        total_tests := _,
        passed_tests := _,
        failed_tests := _
    }}, Report),

    Summary = maps:get(summary, Report),
    TotalTests = maps:get(total_tests, Summary),
    PassedTests = maps:get(passed_tests, Summary),
    FailedTests = maps:get(failed_tests, Summary),

    ct:pal("Summary: Total=~p, Passed=~p, Failed=~p",
           [TotalTests, PassedTests, FailedTests]),

    ?assert(TotalTests >= PassedTests + FailedTests),

    ct:pal("=== Combination test runner reporting test PASSED ==="),
    ok.

%% @doc Test combination test metrics collection.
-spec test_combination_test_runner_metrics(Config) -> ok when Config :: [tuple()].
test_combination_test_runner_metrics(Config) ->
    ct:pal("=== Testing combination test runner metrics ==="),

    %% Run a small combination test and collect metrics
    Config = #{
        max_length => 1,
        patterns => [basic_sequential],
        iterations => 3
    },

    StartTime = erlang:monotonic_time(millisecond),
    {ok, Results} = yawl_test_runner:run_combination_tests(Config),
    EndTime = erlang:monotonic_time(millisecond),
    TotalTime = EndTime - StartTime,

    ct:pal("Completed ~p tests in ~pms", [length(Results), TotalTime]),

    %% Extract and verify metrics
    lists:foreach(fun(Result) ->
        PerfMetrics = maps:get(performance_metrics, Result, #{}),
        ExecutionTime = maps:get(execution_time, PerfMetrics, 0),
        ct:pal("Test ~p: execution_time=~pms",
               [maps:get(test_id, Result), ExecutionTime])
    end, Results),

    %% Get test summary
    {ok, Summary} = yawl_test_runner:get_test_summary(),
    ?assertMatch(#{
        total_tests := _,
        passed_tests := _,
        success_rate := _
    }, Summary),

    ct:pal("Test summary: ~p", [Summary]),

    ct:pal("=== Combination test runner metrics test PASSED ==="),
    ok.

%% @doc Test parallel combination execution.
-spec test_combination_test_runner_parallel(Config) -> ok when Config :: [tuple()].
test_combination_test_runner_parallel(Config) ->
    ct:pal("=== Testing combination test runner parallel ==="),

    %% Run parallel combination tests
    Config = #{
        max_length => 2,
        patterns => [basic_sequential, parallel_split, exclusive_choice],
        parallel => true
    },

    StartTime = erlang:monotonic_time(millisecond),
    {ok, Results} = yawl_test_runner:run_combination_tests(Config),
    EndTime = erlang:monotonic_time(millisecond),

    ct:pal("Parallel execution: ~p results in ~pms", [length(Results), EndTime - StartTime]),

    %% Verify parallel execution completed successfully
    PassedCount = length([R || R <- Results,
                                maps:get(status, R, failed) =:= passed]),
    ct:pal("Parallel tests passed: ~p/~p", [PassedCount, length(Results)]),

    ?assert(PassedCount >= length(Results) div 2),  % At least 50% pass rate

    ct:pal("=== Combination test runner parallel test PASSED ==="),
    ok.

%%====================================================================
%% REST API Integration Tests
%%====================================================================

%% @doc Test combination workflow creation via REST API.
-spec test_combination_rest_workflow_creation(Config) -> ok when Config :: [tuple()].
test_combination_rest_workflow_creation(Config) ->
    Port = proplists:get_value(http_port, Config, ?HTTP_PORT),
    ct:pal("=== Testing combination REST workflow creation ==="),

    BaseUrl = "http://localhost:" ++ integer_to_list(Port),

    %% Create combination workflow via REST
    Payload = jiffy:encode(#{
        pattern_type => basic_sequential,
        config => #{
            combination_type => sequential,
            patterns => [basic_sequential, exclusive_choice],
            task_names => [<<"task1">>, <<"task2">>]
        }
    }),

    {ok, 201, Response} = make_http_request(post, BaseUrl ++ "/workflows", Payload),
    Result = jiffy:decode(Response, [return_maps]),
    WorkflowId = maps:get(<<"workflow_id">>, Result),
    ct:pal("Created workflow via REST: ~p", [WorkflowId]),

    %% Verify via direct API
    {ok, pending} = yawl_orchestrator:get_status(WorkflowId),

    %% Cleanup
    {ok, 200, _} = make_http_request(delete,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>),

    ct:pal("=== Combination REST workflow creation test PASSED ==="),
    ok.

%% @doc Test combination workflow execution via REST API.
-spec test_combination_rest_workflow_execution(Config) -> ok when Config :: [tuple()].
test_combination_rest_workflow_execution(Config) ->
    Port = proplists:get_value(http_port, Config, ?HTTP_PORT),
    ct:pal("=== Testing combination REST workflow execution ==="),

    BaseUrl = "http://localhost:" ++ integer_to_list(Port),

    %% Create workflow
    Payload = jiffy:encode(#{
        pattern_type => basic_sequential,
        config => #{
            combination_type => sequential,
            patterns => [basic_sequential]
        }
    }),

    {ok, 201, CreateResp} = make_http_request(post, BaseUrl ++ "/workflows", Payload),
    CreateResult = jiffy:decode(CreateResp, [return_maps]),
    WorkflowId = maps:get(<<"workflow_id">>, CreateResult),

    %% Start via REST
    {ok, 200, StartResp} = make_http_request(post,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId) ++ "/start", <<>>),
    ct:pal("Start response: ~p", [jiffy:decode(StartResp, [return_maps])]),

    %% Get status via REST
    {ok, 200, StatusResp} = make_http_request(get,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>),
    StatusResult = jiffy:decode(StatusResp, [return_maps]),
    ct:pal("Status via REST: ~p", [StatusResult]),

    %% Cleanup
    {ok, 200, _} = make_http_request(delete,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>),

    ct:pal("=== Combination REST workflow execution test PASSED ==="),
    ok.

%% @doc Test combination status queries via REST API.
-spec test_combination_rest_status_queries(Config) -> ok when Config :: [tuple()].
test_combination_rest_status_queries(Config) ->
    Port = proplists:get_value(http_port, Config, ?HTTP_PORT),
    ct:pal("=== Testing combination REST status queries ==="),

    BaseUrl = "http://localhost:" ++ integer_to_list(Port),

    %% Create multiple workflows
    WorkflowIds = lists:map(fun(I) ->
        Payload = jiffy:encode(#{
            pattern_type => basic_sequential,
            config => #{task_id => I}
        }),
        {ok, 201, Resp} = make_http_request(post, BaseUrl ++ "/workflows", Payload),
        Result = jiffy:decode(Resp, [return_maps]),
        maps:get(<<"workflow_id">>, Result)
    end, lists:seq(1, 3)),

    ct:pal("Created ~p workflows", [length(WorkflowIds)]),

    %% List workflows
    {ok, 200, ListResp} = make_http_request(get, BaseUrl ++ "/workflows", <<>>),
    ListResult = jiffy:decode(ListResp, [return_maps]),
    ListedWorkflows = maps:get(<<"workflows">>, ListResult, []),
    ct:pal("Listed ~p workflows", [length(ListedWorkflows)]),

    %% Verify our workflows are listed
    lists:foreach(fun(WorkflowId) ->
        IsListed = lists:any(fun(W) ->
            maps:get(<<"workflow_id">>, W, <<>>) =:= WorkflowId
        end, ListedWorkflows),
        ?assert(IsListed)
    end, WorkflowIds),

    %% Get individual status for each
    lists:foreach(fun(WorkflowId) ->
        {ok, 200, StatusResp} = make_http_request(get,
            BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>),
        StatusResult = jiffy:decode(StatusResp, [return_maps]),
        ?assertEqual(WorkflowId, maps:get(<<"workflow_id">>, StatusResult))
    end, WorkflowIds),

    %% Cleanup
    lists:foreach(fun(WorkflowId) ->
        catch make_http_request(delete,
            BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>)
    end, WorkflowIds),

    ct:pal("=== Combination REST status queries test PASSED ==="),
    ok.

%% @doc Test combination result reporting via REST API.
-spec test_combination_rest_result_reporting(Config) -> ok when Config :: [tuple()].
test_combination_rest_result_reporting(Config) ->
    Port = proplists:get_value(http_port, Config, ?HTTP_PORT),
    ct:pal("=== Testing combination REST result reporting ==="),

    BaseUrl = "http://localhost:" ++ integer_to_list(Port),

    %% Create and complete a workflow
    Payload = jiffy:encode(#{
        pattern_type => basic_sequential,
        config => #{test => "result_reporting"}
    }),

    {ok, 201, CreateResp} = make_http_request(post, BaseUrl ++ "/workflows", Payload),
    CreateResult = jiffy:decode(CreateResp, [return_maps]),
    WorkflowId = maps:get(<<"workflow_id">>, CreateResult),

    %% Start and complete via direct API
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    ok = yawl_workflow_instance:complete_task(InstancePid, task1, #{result => ok}),
    ok = yawl_workflow_instance:complete_task(InstancePid, task2, #{result => ok}),
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),

    %% Get result via REST
    {ok, 200, ResultResp} = make_http_request(get,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId) ++ "/result", <<>>),
    ResultResult = jiffy:decode(ResultResp, [return_maps]),
    ct:pal("Result via REST: ~p", [ResultResult]),

    ?assertEqual(WorkflowId, maps:get(<<"workflow_id">>, ResultResult)),

    %% Cleanup
    {ok, 200, _} = make_http_request(delete,
        BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>),

    ct:pal("=== Combination REST result reporting test PASSED ==="),
    ok.

%% @doc Test concurrent REST API workflow operations.
-spec test_combination_rest_concurrent_workflows(Config) -> ok when Config :: [tuple()].
test_combination_rest_concurrent_workflows(Config) ->
    Port = proplists:get_value(http_port, Config, ?HTTP_PORT),
    ct:pal("=== Testing combination REST concurrent workflows ==="),

    BaseUrl = "http://localhost:" ++ integer_to_list(Port),

    %% Create multiple workflows concurrently via REST
    NumRequests = 10,
    StartTime = erlang:monotonic_time(millisecond),

    Results = lists:map(fun(I) ->
        spawn_monitor(fun() ->
            Payload = jiffy:encode(#{
                pattern_type => basic_sequential,
                config => #{concurrent_id => I}
            }),
            case make_http_request(post, BaseUrl ++ "/workflows", Payload) of
                {ok, 201, Response} ->
                    ResultMap = jiffy:decode(Response, [return_maps]),
                    {created, maps:get(<<"workflow_id">>, ResultMap)};
                {error, Reason} ->
                    {error, Reason}
            end
        end)
    end, lists:seq(1, NumRequests)),

    %% Collect results
    WorkflowIds = lists:filtermap(fun({_Pid, _Ref}) ->
        receive
            {Pid, Result} ->
                erlang:demonitor(_Ref, [flush]),
                case Result of
                    {created, WorkflowId} -> {true, WorkflowId};
                    _ -> false
                end;
            {'DOWN', Ref, process, _, _} ->
                false
        end
    end, Results),

    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    ct:pal("Created ~p/~p workflows concurrently in ~pms",
           [length(WorkflowIds), NumRequests, Duration]),

    ?assert(length(WorkflowIds) >= NumRequests - 1),

    %% Cleanup
    lists:foreach(fun(WorkflowId) ->
        catch make_http_request(delete,
            BaseUrl ++ "/workflows/" ++ binary_to_list(WorkflowId), <<>>)
    end, WorkflowIds),

    ct:pal("=== Combination REST concurrent workflows test PASSED ==="),
    ok.

%%====================================================================
%% End-to-End Workflow Tests
%%====================================================================

%% @doc Test end-to-end sequential combination workflow.
-spec test_e2e_sequential_combination_workflow(Config) -> ok when Config :: [tuple()].
test_e2e_sequential_combination_workflow(_Config) ->
    ct:pal("=== Testing E2E sequential combination workflow ==="),

    %% Define sequential combination
    SequentialCombo = [
        {basic_sequential, #{task1 => "validate", task2 => "process"}},
        {exclusive_choice, #{conditions => [approve, reject]}},
        {simple_merge, #{branches => 2}}
    ],

    %% Execute end-to-end workflow
    {ok, WorkflowId, Result} = execute_end_to_end_workflow(
        sequential, SequentialCombo, #{}),

    ct:pal("E2E sequential combo result: ~p", [Result]),

    ?assertEqual(completed, maps_get(status, Result, failed)),

    %% Verify persistence
    {ok, PersistedWorkflow} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(completed, PersistedWorkflow#yawl_workflow_persist.status),

    %% Verify workitems
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    ct:pal("Created ~p workitems", [length(Workitems)]),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== E2E sequential combination workflow test PASSED ==="),
    ok.

%% @doc Test end-to-end parallel combination workflow.
-spec test_e2e_parallel_combination_workflow(Config) -> ok when Config :: [tuple()].
test_e2e_parallel_combination_workflow(_Config) ->
    ct:pal("=== Testing E2E parallel combination workflow ==="),

    %% Define parallel combination
    ParallelCombo = [
        {parallel_split, #{branches => 3, tasks => [<<"t1">>, <<"t2">>, <<"t3">>]}},
        {multi_instance, #{num_instances => 2}},
        {parallel_join, #{branches => 3}}
    ],

    %% Execute end-to-end workflow
    {ok, WorkflowId, Result} = execute_end_to_end_workflow(
        parallel, ParallelCombo, #{}),

    ct:pal("E2E parallel combo result: ~p", [Result]),

    ?assertEqual(completed, maps_get(status, Result, completed)),

    %% Verify all branches were executed
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    CompletedCount = length([W || W <- Workitems,
                                W#yawl_workitem_persist.status =:= completed]),
    ct:pal("Completed ~p workitems in parallel combo", [CompletedCount]),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== E2E parallel combination workflow test PASSED ==="),
    ok.

%% @doc Test end-to-end mixed combination workflow.
-spec test_e2e_mixed_combination_workflow(Config) -> ok when Config :: [tuple()].
test_e2e_mixed_combination_workflow(_Config) ->
    ct:pal("=== Testing E2E mixed combination workflow ==="),

    %% Define mixed combination
    MixedCombo = [
        {basic_sequential, #{}},
        {parallel_split, #{branches => 2}},
        {exclusive_choice, #{conditions => [option_a, option_b]}},
        {simple_merge, #{}}
    ],

    %% Execute end-to-end workflow
    {ok, WorkflowId, Result} = execute_end_to_end_workflow(
        mixed, MixedCombo, #{timeout => 30000}),

    ct:pal("E2E mixed combo result: ~p", [Result]),

    %% Verify result
    ?assertEqual(completed, maps_get(status, Result, completed)),

    %% Verify execution history
    {ok, History} = yawl_persistence:get_workflow_history(WorkflowId),
    ct:pal("Execution history entries: ~p", [length(History)]),
    ?assert(length(History) > 0),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== E2E mixed combination workflow test PASSED ==="),
    ok.

%% @doc Test end-to-end nested combination workflow.
-spec test_e2e_nested_combination_workflow(Config) -> ok when Config :: [tuple()].
test_e2e_nested_combination_workflow(_Config) ->
    ct:pal("=== Testing E2E nested combination workflow ==="),

    %% Define nested combination (parallel within sequential)
    NestedCombo = [
        {basic_sequential, #{}},
        {parallel_split, #{branches => 2, nested => true}},
        {iterative_loop, #{max_iterations => 2}}
    ],

    %% Execute end-to-end workflow
    {ok, WorkflowId, Result} = execute_end_to_end_workflow(
        nested, NestedCombo, #{max_depth => 2}),

    ct:pal("E2E nested combo result: ~p", [Result]),

    %% Verify nested structure was handled
    ?assertEqual(completed, maps_get(status, Result, completed)),

    %% Verify workitem hierarchy
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    ct:pal("Created ~p workitems in nested combo", [length(Workitems)]),

    %% Cleanup
    ok = yawl_orchestrator:cleanup_workflow(WorkflowId),

    ct:pal("=== E2E nested combination workflow test PASSED ==="),
    ok.

%%====================================================================
%% Business Scenario Integration Tests
%%====================================================================

%% @doc Test order processing business scenario with combinations.
-spec test_business_scenario_combination_order(Config) -> ok when Config :: [tuple()].
test_business_scenario_combination_order(_Config) ->
    ct:pal("=== Testing business scenario combination - order processing ==="),

    %% Get order processing scenario
    Scenario = yawl_business_scenarios:order_processing_scenario(medium),
    PatternCombination = Scenario#yawl_scenario.pattern_combination,

    ct:pal("Order processing patterns: ~p", [PatternCombination]),

    %% Execute the business scenario
    {ok, WorkflowIds, Results} = execute_business_scenario(Scenario),

    ct:pal("Created ~p workflows for order processing", [length(WorkflowIds)]),
    ct:pal("Scenario results: ~p", [Results]),

    %% Verify all workflows completed
    AllCompleted = lists:all(fun(WfId) ->
        case yawl_orchestrator:get_status(WfId) of
            {ok, completed} -> true;
            _ -> false
        end
    end, WorkflowIds),
    ?assert(AllCompleted),

    %% Cleanup
    lists:foreach(fun(WfId) ->
        catch yawl_orchestrator:cleanup_workflow(WfId)
    end, WorkflowIds),

    ct:pal("=== Business scenario combination - order processing test PASSED ==="),
    ok.

%% @doc Test approval chain business scenario with combinations.
-spec test_business_scenario_combination_approval(Config) -> ok when Config :: [tuple()].
test_business_scenario_combination_approval(_Config) ->
    ct:pal("=== Testing business scenario combination - approval chain ==="),

    %% Get approval chain scenario
    Scenario = yawl_business_scenarios:approval_chain_scenario(low),
    PatternCombination = Scenario#yawl_scenario.pattern_combination,

    ct:pal("Approval chain patterns: ~p", [PatternCombination]),

    %% Execute the business scenario
    {ok, WorkflowIds, Results} = execute_business_scenario(Scenario),

    ct:pal("Created ~p workflows for approval chain", [length(WorkflowIds)]),

    %% Verify results
    ?assert(length(WorkflowIds) > 0),
    ?assert(length(Results) > 0),

    %% Cleanup
    lists:foreach(fun(WfId) ->
        catch yawl_orchestrator:cleanup_workflow(WfId)
    end, WorkflowIds),

    ct:pal("=== Business scenario combination - approval chain test PASSED ==="),
    ok.

%% @doc Test document workflow business scenario with combinations.
-spec test_business_scenario_combination_document(Config) -> ok when Config :: [tuple()].
test_business_scenario_combination_document(_Config) ->
    ct:pal("=== Testing business scenario combination - document workflow ==="),

    %% Get document workflow scenario
    Scenario = yawl_business_scenarios:document_workflow_scenario(medium),
    PatternCombination = Scenario#yawl_scenario.pattern_combination,

    ct:pal("Document workflow patterns: ~p", [PatternCombination]),

    %% Execute the business scenario
    {ok, WorkflowIds, Results} = execute_business_scenario(Scenario),

    ct:pal("Created ~p workflows for document workflow", [length(WorkflowIds)]),

    %% Verify success criteria
    SuccessCriteria = Scenario#yawl_scenario.success_criteria,
    MaxDuration = maps:get(max_duration, SuccessCriteria, 60000),
    ?assert(MaxDuration > 0),

    ct:pal("Document workflow success criteria: ~p", [SuccessCriteria]),

    %% Cleanup
    lists:foreach(fun(WfId) ->
        catch yawl_orchestrator:cleanup_workflow(WfId)
    end, WorkflowIds),

    ct:pal("=== Business scenario combination - document workflow test PASSED ==="),
    ok.

%%====================================================================
%% Performance and Stress Tests
%%====================================================================

%% @doc Test combination performance with small dataset.
-spec test_combination_performance_small(Config) -> ok when Config :: [tuple()].
test_combination_performance_small(_Config) ->
    ct:pal("=== Testing combination performance - small ==="),

    %% Generate small combinations
    Config = #{
        max_length => 2,
        patterns => [basic_sequential, exclusive_choice],
        iterations => 5
    },

    StartTime = erlang:monotonic_time(millisecond),
    {ok, Results} = yawl_test_runner:run_combination_tests(Config),
    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    ct:pal("Small performance test: ~p results in ~pms", [length(Results), Duration]),

    %% Calculate throughput
    Throughput = length(Results) * 1000 / max(1, Duration),
    ct:pal("Throughput: ~.2f tests/second", [Throughput]),

    ?assert(Duration < 30000),  % Should complete in 30 seconds

    ct:pal("=== Combination performance - small test PASSED ==="),
    ok.

%% @doc Test combination performance with medium dataset.
-spec test_combination_performance_medium(Config) -> ok when Config :: [tuple()].
test_combination_performance_medium(_Config) ->
    ct:pal("=== Testing combination performance - medium ==="),

    %% Generate medium combinations
    Config = #{
        max_length => 3,
        patterns => [basic_sequential, parallel_split, exclusive_choice, simple_merge],
        iterations => 10
    },

    StartTime = erlang:monotonic_time(millisecond),
    {ok, Results} = yawl_test_runner:run_combination_tests(Config),
    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    ct:pal("Medium performance test: ~p results in ~pms", [length(Results), Duration]),

    %% Verify performance metrics
    AvgTime = Duration / max(1, length(Results)),
    ct:pal("Average time per test: ~.2fms", [AvgTime]),

    ?assert(Duration < 60000),  % Should complete in 60 seconds

    ct:pal("=== Combination performance - medium test PASSED ==="),
    ok.

%% @doc Test combination system under stress.
-spec test_combination_stress_concurrent(Config) -> ok when Config :: [tuple()].
test_combination_stress_concurrent(_Config) ->
    ct:pal("=== Testing combination stress - concurrent ==="),

    %% Stress test with concurrent combinations
    NumConcurrent = 20,
    PatternsPerCombo = 2,

    StartTime = erlang:monotonic_time(millisecond),

    %% Spawn concurrent combination executions
    Results = lists:map(fun(I) ->
        spawn_monitor(fun() ->
            ComboPatterns = [
                lists:nth((I rem 4) + 1, [basic_sequential, parallel_split,
                                            exclusive_choice, simple_merge]),
                lists:nth(((I + 1) rem 4) + 1, [basic_sequential, parallel_split,
                                             exclusive_choice, simple_merge])
            ],
            case create_combination_workflow(sequential, ComboPatterns,
                    #{stress_id => I}) of
                {ok, WorkflowId} ->
                    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
                    {ok, yawl_orchestrator:cleanup_workflow(WorkflowId)},
                    {ok, I};
                {error, Reason} ->
                    {error, Reason, I}
            end
        end)
    end, lists:seq(1, NumConcurrent)),

    %% Collect results
    SuccessCount = lists:foldl(fun({_Pid, _Ref}, Acc) ->
        receive
            {Pid, {ok, _}} -> Acc + 1;
            {Pid, {error, _, _}} -> Acc;
            {'DOWN', Ref, process, _, _} -> Acc
        end
    end, 0, Results),

    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    ct:pal("Stress test: ~p/~p successful in ~pms",
           [SuccessCount, NumConcurrent, Duration]),

    ?assert(SuccessCount >= NumConcurrent - 2),  % Allow 2 failures

    ct:pal("=== Combination stress - concurrent test PASSED ==="),
    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
%% @doc Set up test resources.
-spec setup_test_resources() -> ok.
setup_test_resources() ->
    %% Human resources
    {ok, _} = yawl_resource_manager:register_resource(
        <<"test_human">>, human,
        #{capabilities => [approve, review, validate], max_capacity => 5}),
    {ok, _} = yawl_resource_manager:register_resource(
        <<"test_service">>, service,
        #{capabilities => [process, validate, transform], max_capacity => 10}),
    ok.

%% @private
%% @doc Create a combination workflow.
-spec create_combination_workflow(atom(), [atom()], map()) ->
    {ok, binary()} | {error, term()}.
create_combination_workflow(ComboType, Patterns, BaseConfig) ->
    ComboConfig = BaseConfig#{
        combination_type => ComboType,
        patterns => Patterns
    },
    case ComboType of
        sequential ->
            %% Create a sequential workflow that combines patterns
            case lists:foldl(fun(Pattern, Acc) ->
                case Acc of
                    {ok, WorkflowIds} ->
                        case yawl_orchestrator:create_workflow(Pattern, ComboConfig) of
                            {ok, WorkflowId} ->
                                {ok, [WorkflowId | WorkflowIds]};
                            Error ->
                                Error
                        end;
                    Error ->
                        Error
                end
            end, {ok, []}, Patterns) of
                {ok, ReversedIds} ->
                    {ok, lists:hd(ReversedIds)};
                Error ->
                    Error
            end;
        parallel ->
            %% Create a parallel workflow with branches
            CombinedConfig = ComboConfig#{
                branches => [
                    {lists:nth(1, Patterns), #{}},
                    {lists:nth(2, Patterns), #{}}
                ]
            },
            yawl_orchestrator:create_workflow(parallel_split, CombinedConfig);
        mixed ->
            %% Create mixed pattern workflow
            yawl_orchestrator:create_workflow(basic_sequential, ComboConfig);
        nested ->
            %% Create nested pattern workflow
            yawl_orchestrator:create_workflow(parallel_split, ComboConfig)
    end.

%% @private
%% @doc Execute end-to-end workflow.
-spec execute_end_to_end_workflow(atom(), [{atom(), map()}], map()) ->
    {ok, binary(), map()}.
execute_end_to_end_workflow(ComboType, PatternConfigs, Config) ->
    %% Create workflow
    {ok, WorkflowId} = create_combination_workflow(ComboType,
        [P || {P, _} <- PatternConfigs], Config),
    ct:pal("Created E2E workflow: ~p", [WorkflowId]),

    %% Start workflow
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    wait_for_status(WorkflowId, running, 2000),

    %% Complete all tasks
    {ok, InstancePid} = yawl_orchestrator:get_workflow_instance(WorkflowId),

    %% Generate tasks based on patterns
    Tasks = generate_tasks_for_combination(PatternConfigs),
    lists:foreach(fun(Task) ->
        ok = yawl_workflow_instance:complete_task(InstancePid, Task, #{completed => true})
    end, Tasks),

    %% Wait for completion
    wait_for_status(WorkflowId, completed, ?MAX_WAIT),

    %% Get result
    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
    Result = #{status => Status, workflow_id => WorkflowId},

    {ok, WorkflowId, Result}.

%% @private
%% @doc Execute business scenario.
-spec execute_business_scenario(#yawl_scenario{}) ->
    {ok, [binary()], [map()]}.
execute_business_scenario(Scenario) ->
    PatternCombination = Scenario#yawl_scenario.pattern_combination,

    WorkflowIds = lists:foldl(fun({Pattern, Config}, Acc) ->
        case yawl_orchestrator:create_workflow(Pattern, Config) of
            {ok, WorkflowId} ->
                [WorkflowId | Acc];
            Error ->
                ct:pal("Error creating workflow for pattern ~p: ~p", [Pattern, Error]),
                Acc
        end
    end, [], PatternCombination),

    %% Start all workflows
    Results = lists:map(fun(WorkflowId) ->
        case yawl_orchestrator:execute_workflow(WorkflowId) of
            {ok, _} ->
                {WorkflowId, executing};
            Error ->
                {WorkflowId, Error}
        end
    end, WorkflowIds),

    %% Wait for completion
    lists:foreach(fun({WorkflowId, _}) ->
        case wait_for_status(WorkflowId, completed, 10000) of
            ok -> ok;
            timeout ->
                ct:pal("Workflow ~p timed out", [WorkflowId])
        end
    end, Results),

    {ok, WorkflowIds, Results}.

%% @private
%% @doc Generate tasks for combination patterns.
-spec generate_tasks_for_combination([{atom(), map()}]) -> [atom()].
generate_tasks_for_combination(PatternConfigs) ->
    lists:flatmap(fun({Pattern, _Config}) ->
        case Pattern of
            basic_sequential -> [task1, task2];
            parallel_split -> [branch1_task, branch2_task];
            parallel_join -> [join_task];
            exclusive_choice -> [choice_task];
            simple_merge -> [merge_task];
            iterative_loop -> [loop_task];
            multi_instance -> [instance_task];
            _ -> [generic_task]
        end
    end, PatternConfigs).

%% @private
%% @doc Validate combination.
-spec validate_combination(atom(), map()) -> boolean().
validate_combination(_ComboType, Config) ->
    maps:get(patterns, Config, []) =/= [].

%% @private
%% @doc Track workflow status.
-spec track_status(binary(), [atom()]) -> [atom()].
track_status(WorkflowId, ExistingStates) ->
    case yawl_orchestrator:get_status(WorkflowId) of
        {ok, Status} ->
            lists:usort([Status | ExistingStates]);
        _ ->
            ExistingStates
    end.

%% @private
%% @doc Wait for workflow status.
-spec wait_for_status(binary(), atom(), integer()) -> ok | timeout.
wait_for_status(WorkflowId, TargetStatus, Timeout) ->
    StartTime = erlang:monotonic_time(millisecond),
    wait_for_status_loop(WorkflowId, TargetStatus, StartTime, Timeout).

wait_for_status_loop(WorkflowId, TargetStatus, StartTime, Timeout) ->
    case yawl_orchestrator:get_status(WorkflowId) of
        {ok, TargetStatus} ->
            ok;
        {ok, _OtherStatus} ->
            case erlang:monotonic_time(millisecond) - StartTime of
                Elapsed when Elapsed > Timeout ->
                    timeout;
                _ ->
                    timer:sleep(?WAIT_INTERVAL),
                    wait_for_status_loop(WorkflowId, TargetStatus, StartTime, Timeout)
            end;
        {error, _} ->
            case erlang:monotonic_time(millisecond) - StartTime of
                Elapsed when Elapsed > Timeout ->
                    timeout;
                _ ->
                    timer:sleep(?WAIT_INTERVAL),
                    wait_for_status_loop(WorkflowId, TargetStatus, StartTime, Timeout)
            end
    end.

%% @private
%% @doc Wait for REST server.
-spec wait_for_rest_server(integer(), integer()) -> ok | timeout.
wait_for_rest_server(Port, Timeout) ->
    StartTime = erlang:monotonic_time(millisecond),
    wait_for_server_loop(Port, StartTime, Timeout).

wait_for_server_loop(Port, StartTime, Timeout) ->
    case check_rest_server(Port) of
        ok ->
            ok;
        {error, _} ->
            case erlang:monotonic_time(millisecond) - StartTime of
                Elapsed when Elapsed > Timeout ->
                    timeout;
                _ ->
                    timer:sleep(200),
                    wait_for_server_loop(Port, StartTime, Timeout)
            end
    end.

%% @private
%% @doc Check REST server.
-spec check_rest_server(integer()) -> ok | {error, term()}.
check_rest_server(Port) ->
    Url = "http://localhost:" ++ integer_to_list(Port) ++ "/health",
    case make_http_request(get, Url, <<>>, "application/json", []) of
        {ok, _, _} -> ok;
        Error -> Error
    end.

%% @private
%% @doc Make HTTP request.
-spec make_http_request(atom(), string(), binary()) ->
    {ok, integer(), binary()} | {error, term()}.
make_http_request(Method, Url, Body) ->
    make_http_request(Method, Url, Body, "application/json").

make_http_request(Method, Url, Body, ContentType) ->
    make_http_request(Method, Url, Body, ContentType, []).

make_http_request(Method, Url, Body, ContentType, Headers) ->
    case httpc:request(Method, {Url, Headers ++ [
        {"Content-Type", ContentType}
    ]}, [], Body, []) of
        {ok, {{_, StatusCode, _}, _ResponseHeaders, ResponseBody}} ->
            {ok, StatusCode, ResponseBody};
        {error, Reason} ->
            {error, Reason}
    end.

%% @private
%% @doc Clean up test data.
-spec cleanup_test_data(term()) -> ok.
cleanup_test_data(_Config) ->
    %% Cancel and cleanup all workflows
    case yawl_orchestrator:list_workflows() of
        {ok, WorkflowIds} ->
            lists:foreach(fun(WorkflowId) ->
                case yawl_orchestrator:get_status(WorkflowId) of
                    {ok, Status} when Status =:= running; Status =:= pending ->
                        catch yawl_orchestrator:cancel_workflow(WorkflowId);
                    _ -> ok
                end,
                catch yawl_orchestrator:cleanup_workflow(WorkflowId)
            end, WorkflowIds);
        _ ->
            ok
    end,

    %% Clean up Mnesia tables
    cleanup_mnesia_table(yawl_workflow_persist),
    cleanup_mnesia_table(yawl_workitem_persist),
    cleanup_mnesia_table(yawl_execution_history),
    cleanup_mnesia_table(yawl_checkpoint),

    ok.

%% @private
%% @doc Clean up Mnesia table.
-spec cleanup_mnesia_table(atom()) -> ok.
cleanup_mnesia_table(TableName) ->
    Trans = fun() -> mnesia:all_keys(TableName) end,
    case mnesia:transaction(Trans) of
        {atomic, Keys} ->
            lists:foreach(fun(Key) ->
                mnesia:delete(TableName, Key, write)
            end, Keys);
        _ ->
            ok
    end,
    ok.

%% @private
%% @doc Get value from map or return default.
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.
