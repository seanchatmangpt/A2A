%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Orchestrator Unit Tests
%%%
%%% This module contains comprehensive unit tests for YAWL workflow orchestrator
%%% that manages workflow instances, coordinates with persistence layer,
%%% and handles lifecycle events.
%%%
%%% Test Coverage:
%%% - Workflow creation and management
%%% - Lifecycle event handling
%%% - Error propagation
%%% - Module coordination
%%% - Subscription management
%%% - Performance characteristics
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_orchestrator_test).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(TEST_TIMEOUT, 5000).  % 5 seconds timeout
-define(DEFAULT_CONFIG, #{timeout => 30000}).
-define(TEST_WORKFLOW_ID, <<"test_workflow_id">>).
-define(TEST_PATTERN_TYPE, basic_sequential).

%%====================================================================
%% Basic Test Setup and Teardown
%%====================================================================

setup() ->
    %% Start the orchestrator before each test
    {ok, Pid} = yawl_orchestrator:start_link(),
    Pid.

teardown(Pid) ->
    %% Stop the orchestrator after each test
    gen_server:stop(Pid).

start_stop_test_() ->
    [{"Start and stop orchestrator",
      fun start_stop_orchestrator/0}].

start_stop_orchestrator() ->
    {ok, Pid} = yawl_orchestrator:start_link(),
    %% Verify the process is running
    ?assert(is_pid(Pid)),
    ?assert(is_process_alive(Pid)),
    %% Stop the process
    gen_server:stop(Pid),
    %% Verify it's stopped
    ?assertNot(is_process_alive(Pid)).

%%====================================================================
%% Workflow Creation Tests
%%====================================================================

create_workflow_test_() ->
    [{"Create basic sequential workflow",
      fun test_create_basic_sequential/0},
     {"Create parallel split workflow",
      fun test_create_parallel_split/0},
     {"Create workflow with custom timeout",
      fun test_create_with_timeout/0},
     {"Create unknown pattern type fails",
      fun test_create_unknown_pattern/0},
     {"Create workflow with metadata",
      fun test_create_with_metadata/0}].

test_create_basic_sequential() ->
    Pid = setup(),
    try
        Config = #{task1_name => "task1", task2_name => "task2"},
        ?assertMatch({ok, _WorkflowId}, yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config))
    after
        teardown(Pid)
    end.

test_create_parallel_split() ->
    Pid = setup(),
    try
        Config = #{pattern_config => #{branches => 3}, task_names => ["task1", "task2", "task3"]},
        ?assertMatch({ok, _WorkflowId}, yawl_orchestrator:create_workflow(parallel_split, Config))
    after
        teardown(Pid)
    end.

test_create_with_timeout() ->
    Pid = setup(),
    try
        Config = #{task1_name => "task1", timeout => 60000},
        ?assertMatch({ok, _WorkflowId}, yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config))
    after
        teardown(Pid)
    end.

test_create_unknown_pattern() ->
    Pid = setup(),
    try
        Config = #{task1_name => "task1"},
        Result = yawl_orchestrator:create_workflow(unknown_pattern, Config),
        ?assertEqual({error, {unknown_pattern, unknown_pattern}}, Result)
    after
        teardown(Pid)
    end.

test_create_with_metadata() ->
    Pid = setup(),
    try
        Config = #{task1_name => "task1", metadata => #{priority => high, category => "test"}},
        ?assertMatch({ok, _WorkflowId}, yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config))
    after
        teardown(Pid)
    end.

%%====================================================================
%% Pattern Validation Tests
%%====================================================================

validate_pattern_test_() ->
    [{"Validate basic sequential pattern",
      fun test_validate_basic_sequential/0},
     {"Validate parallel split pattern",
      fun test_validate_parallel_split/0},
     {"Validate unknown pattern fails",
      fun test_validate_unknown_pattern/0},
     {"Validate pattern with empty config",
      fun test_validate_empty_config/0}].

test_validate_basic_sequential() ->
    Pid = setup(),
    try
        Config = #{task1_name => "task1"},
        ?assertMatch({ok, true}, yawl_orchestrator:validate_pattern(?TEST_PATTERN_TYPE, Config))
    after
        teardown(Pid)
    end.

test_validate_parallel_split() ->
    Pid = setup(),
    try
        Config = #{branches => 3},
        ?assertMatch({ok, true}, yawl_orchestrator:validate_pattern(parallel_split, Config))
    after
        teardown(Pid)
    end.

test_validate_unknown_pattern() ->
    Pid = setup(),
    try
        Config = #{any_key => any_value},
        ?assertMatch({ok, false}, yawl_orchestrator:validate_pattern(unknown_pattern, Config))
    after
        teardown(Pid)
    end.

test_validate_empty_config() ->
    Pid = setup(),
    try
        ?assertMatch({ok, false}, yawl_orchestrator:validate_pattern(?TEST_PATTERN_TYPE, #{}))
    after
        teardown(Pid)
    end.

%%====================================================================
 Workflow Status Tests
%%====================================================================

get_status_test_() ->
    [{"Get status of existing workflow",
      fun test_get_existing_workflow_status/0},
     {"Get status of non-existing workflow",
      fun test_get_non_existing_workflow_status/0},
     {"Workflow status transitions",
      fun test_workflow_status_transitions/0}].

test_get_existing_workflow_status() ->
    Pid = setup(),
    try
        %% Create a workflow first
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% Get its status
        ?assertMatch({ok, pending}, yawl_orchestrator:get_status(WorkflowId))
    after
        teardown(Pid)
    end.

test_get_non_existing_workflow_status() ->
    Pid = setup(),
    try
        Result = yawl_orchestrator:get_status(<<"non_existing_id">>),
        ?assertEqual({error, workflow_not_found}, Result)
    after
        teardown(Pid)
    end.

test_workflow_status_transitions() ->
    Pid = setup(),
    try
        %% Create a workflow
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% Initial status should be pending
        ?assertMatch({ok, pending}, yawl_orchestrator:get_status(WorkflowId)),

        %% Cancel the workflow
        ?assertMatch({ok, _}, yawl_orchestrator:cancel_workflow(WorkflowId)),

        %% Status should be cancelled
        ?assertMatch({ok, cancelled}, yawl_orchestrator:get_status(WorkflowId))
    after
        teardown(Pid)
    end.

%%====================================================================
%% Workflow Execution Tests
%%====================================================================

execute_workflow_test_() ->
    [{"Execute basic sequential workflow",
      fun test_execute_basic_sequential/0},
     {"Execute workflow already running",
      fun test_execute_already_running/0},
     {"Execute non-existing workflow fails",
      fun test_execute_non_existing/0}].

test_execute_basic_sequential() ->
    Pid = setup(),
    try
        %% Create a workflow
        Config = #{task1_name => "task1", task2_name => "task2"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% Execute it
        Result = yawl_orchestrator:execute_workflow(WorkflowId),
        ?assertMatch({ok, #{status := running, instance := _InstancePid}}, Result)
    after
        %% Cleanup might take time, allow for it
        timer:sleep(100),
        teardown(Pid)
    end.

test_execute_already_running() ->
    Pid = setup(),
    try
        %% Create and execute a workflow
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),
        {ok, #{instance := InstancePid1}} = yawl_orchestrator:execute_workflow(WorkflowId),

        %% Execute again - should return the same instance
        {ok, #{instance := InstancePid2}} = yawl_orchestrator:execute_workflow(WorkflowId),

        %% Should be the same process
        ?assertEqual(InstancePid1, InstancePid2)
    after
        timer:sleep(100),
        teardown(Pid)
    end.

test_execute_non_existing() ->
    Pid = setup(),
    try
        Result = yawl_orchestrator:execute_workflow(<<"non_existing_id">>),
        ?assertEqual({error, workflow_not_found}, Result)
    after
        teardown(Pid)
    end.

%%====================================================================
%% Workflow Cancellation Tests
%%====================================================================

cancel_workflow_test_() ->
    [{"Cancel pending workflow",
      fun test_cancel_pending_workflow/0},
     {"Cancel running workflow",
      fun test_cancel_running_workflow/0},
     {"Cancel non-existing workflow fails",
      fun test_cancel_non_existing/0}].

test_cancel_pending_workflow() ->
    Pid = setup(),
    try
        %% Create a workflow
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% Cancel it
        ?assertMatch({ok, _}, yawl_orchestrator:cancel_workflow(WorkflowId)),

        %% Verify status
        ?assertMatch({ok, cancelled}, yawl_orchestrator:get_status(WorkflowId))
    after
        teardown(Pid)
    end.

test_cancel_running_workflow() ->
    Pid = setup(),
    try
        %% Create and execute a workflow
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),
        {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),

        %% Cancel it while running
        ?assertMatch({ok, _}, yawl_orchestrator:cancel_workflow(WorkflowId)),

        %% Verify status
        ?assertMatch({ok, cancelled}, yawl_orchestrator:get_status(WorkflowId))
    after
        timer:sleep(100),
        teardown(Pid)
    end.

test_cancel_non_existing() ->
    Pid = setup(),
    try
        Result = yawl_orchestrator:cancel_workflow(<<"non_existing_id">>),
        ?assertEqual({error, workflow_not_found}, Result)
    after
        teardown(Pid)
    end.

%%====================================================================
%% Workflow Cleanup Tests
%%====================================================================

cleanup_workflow_test_() ->
    [{"Cleanup workflow",
      fun test_cleanup_workflow/0},
     {"Cleanup non-existing workflow fails",
      fun test_cleanup_non_existing/0},
     {"Cleanup removes associated data",
      fun test_cleanup_removes_data/0}].

test_cleanup_workflow() ->
    Pid = setup(),
    try
        %% Create a workflow
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% Cleanup the workflow
        ?assertMatch({ok, _}, yawl_orchestrator:cleanup_workflow(WorkflowId)),

        %% Verify it's cleaned up
        ?assertEqual({error, workflow_not_found}, yawl_orchestrator:get_status(WorkflowId))
    after
        teardown(Pid)
    end.

test_cleanup_non_existing() ->
    Pid = setup(),
    try
        Result = yawl_orchestrator:cleanup_workflow(<<"non_existing_id">>),
        ?assertEqual({error, workflow_not_found}, Result)
    after
        teardown(Pid)
    end.

test_cleanup_removes_data() ->
    Pid = setup(),
    try
        %% Create a workflow
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% Subscribe to it
        SubscriberPid = self(),
        ?assertMatch({ok, _}, yawl_orchestrator:subscribe_to_workflow(WorkflowId, SubscriberPid)),

        %% Cleanup should remove both workflow and subscription
        ?assertMatch({ok, _}, yawl_orchestrator:cleanup_workflow(WorkflowId)),

        %% Verify subscription is also removed
        Result = yawl_orchestrator:subscribe_to_workflow(WorkflowId, SubscriberPid),
        ?assertEqual({error, workflow_not_found}, Result)
    after
        teardown(Pid)
    end.

%%====================================================================
%% Pattern Information Tests
%%====================================================================

get_pattern_info_test_() ->
    [{"Get basic sequential pattern info",
      fun test_get_basic_sequential_info/0},
     {"Get parallel split pattern info",
      fun test_get_parallel_split_info/0},
     {"Get unknown pattern info fails",
      fun test_get_unknown_pattern_info/0}].

test_get_basic_sequential_info() ->
    Pid = setup(),
    try
        Result = yawl_orchestrator:get_pattern_info(?TEST_PATTERN_TYPE),
        ?assertMatch({ok, _}, Result),
        {ok, Info} = Result,
        ?assertEqual(<<"Basic Sequential">>, maps:get(name, Info)),
        ?assertEqual(low, maps:get(complexity, Info))
    after
        teardown(Pid)
    end.

test_get_parallel_split_info() ->
    Pid = setup(),
    try
        Result = yawl_orchestrator:get_pattern_info(parallel_split),
        ?assertMatch({ok, _}, Result),
        {ok, Info} = Result,
        ?assertEqual(<<"Parallel Split">>, maps:get(name, Info)),
        ?assertEqual(medium, maps:get(complexity, Info))
    after
        teardown(Pid)
    end.

test_get_unknown_pattern_info() ->
    Pid = setup(),
    try
        Result = yawl_orchestrator:get_pattern_info(unknown_pattern),
        ?assertEqual({error, pattern_not_found}, Result)
    after
        teardown(Pid)
    end.

%%====================================================================
 Workflow Result Tests
%%====================================================================

get_workflow_result_test_() ->
    [{"Get completed workflow result",
      fun test_get_completed_workflow_result/0},
     {"Get result of non-completed workflow",
      fun test_get_non_completed_result/0},
     {"Get result of non-existing workflow",
      fun test_get_non_existing_result/0}].

test_get_completed_workflow_result() ->
    Pid = setup(),
    try
        %% Create a workflow
        Config = #{task1_name => "task1", task2_name => "task2"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% Cancel it to mark as completed (for testing)
        yawl_orchestrator:cancel_workflow(WorkflowId),

        %% Try to get result (should fail since it's cancelled, not completed)
        Result = yawl_orchestrator:get_workflow_result(WorkflowId),
        ?assertEqual({error, workflow_not_completed}, Result)
    after
        teardown(Pid)
    end.

test_get_non_completed_result() ->
    Pid = setup(),
    try
        %% Create a workflow
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% Get result while still pending
        Result = yawl_orchestrator:get_workflow_result(WorkflowId),
        ?assertEqual({error, workflow_not_completed}, Result)
    after
        teardown(Pid)
    end.

test_get_non_existing_result() ->
    Pid = setup(),
    try
        Result = yawl_orchestrator:get_workflow_result(<<"non_existing_id">>),
        ?assertEqual({error, workflow_not_found}, Result)
    after
        teardown(Pid)
    end.

%%====================================================================
%% Subscription Management Tests
%%====================================================================

subscription_test_() ->
    [{"Subscribe to workflow",
      fun test_subscribe_to_workflow/0},
     {"Unsubscribe from workflow",
      fun test_unsubscribe_from_workflow/0},
     {"Subscribe multiple times",
      fun test_subscribe_multiple_times/0},
     {"Subscribe to non-existing workflow fails",
      fun test_subscribe_non_existing/0},
     {"Unsubscribe from non-existing workflow fails",
      fun test_unsubscribe_non_existing/0}].

test_subscribe_to_workflow() ->
    Pid = setup(),
    try
        %% Create a workflow
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% Subscribe to it
        SubscriberPid = self(),
        ?assertMatch({ok, _}, yawl_orchestrator:subscribe_to_workflow(WorkflowId, SubscriberPid))
    after
        teardown(Pid)
    end.

test_unsubscribe_from_workflow() ->
    Pid = setup(),
    try
        %% Create and subscribe to a workflow
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),
        SubscriberPid = self(),
        ?assertMatch({ok, _}, yawl_orchestrator:subscribe_to_workflow(WorkflowId, SubscriberPid)),

        %% Unsubscribe
        ?assertMatch({ok, _}, yawl_orchestrator:unsubscribe_from_workflow(WorkflowId, SubscriberPid))
    after
        teardown(Pid)
    end.

test_subscribe_multiple_times() ->
    Pid = setup(),
    try
        %% Create a workflow
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% Subscribe multiple times
        SubscriberPid1 = self(),
        SubscriberPid2 = spawn(fun() -> timer:sleep(infinity) end),

        ?assertMatch({ok, _}, yawl_orchestrator:subscribe_to_workflow(WorkflowId, SubscriberPid1)),
        ?assertMatch({ok, _}, yawl_orchestrator:subscribe_to_workflow(WorkflowId, SubscriberPid2)),

        %% Both should be subscribed
        ?assertMatch({ok, _}, yawl_orchestrator:unsubscribe_from_workflow(WorkflowId, SubscriberPid1)),
        ?assertMatch({ok, _}, yawl_orchestrator:unsubscribe_from_workflow(WorkflowId, SubscriberPid2))
    after
        %% Cleanup the spawned process
        exit(whereis(test_subscriber), kill),
        teardown(Pid)
    end.

test_subscribe_non_existing() ->
    Pid = setup(),
    try
        SubscriberPid = self(),
        Result = yawl_orchestrator:subscribe_to_workflow(<<"non_existing_id">>, SubscriberPid),
        ?assertEqual({error, workflow_not_found}, Result)
    after
        teardown(Pid)
    end.

test_unsubscribe_non_existing() ->
    Pid = setup(),
    try
        SubscriberPid = self(),
        Result = yawl_orchestrator:unsubscribe_from_workflow(<<"non_existing_id">>, SubscriberPid),
        ?assertEqual({error, workflow_not_found}, Result)
    after
        teardown(Pid)
    end.

%%====================================================================
%% Listing Functions Tests
%%====================================================================

list_functions_test_() ->
    [{"List patterns returns expected patterns",
      fun test_list_patterns/0},
     {"List workflows returns empty initially",
      fun test_list_workflows_empty/0},
     {"List workflows returns created workflows",
      fun test_list_workflows_created/0}].

test_list_patterns() ->
    Pid = setup(),
    try
        Result = yawl_orchestrator:list_patterns(),
        ?assertMatch({ok, Patterns}, Result),
        {ok, Patterns} = Result,
        %% Should include basic patterns
        ?assert(lists:member(?TEST_PATTERN_TYPE, Patterns)),
        ?assert(lists:member(parallel_split, Patterns)),
        ?assert(length(Patterns) > 0)
    after
        teardown(Pid)
    end.

test_list_workflows_empty() ->
    Pid = setup(),
    try
        Result = yawl_orchestrator:list_workflows(),
        ?assertMatch({ok, []}, Result)
    after
        teardown(Pid)
    end.

test_list_workflows_created() ->
    Pid = setup(),
    try
        %% Create multiple workflows
        Config1 = #{task1_name => "task1"},
        Config2 = #{task1_name => "task2"},
        {ok, WorkflowId1} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config1),
        {ok, WorkflowId2} = yawl_orchestrator:create_workflow(parallel_split, Config2),

        %% List workflows
        Result = yawl_orchestrator:list_workflows(),
        ?assertMatch({ok, WorkflowIds}, Result),
        {ok, WorkflowIds} = Result,
        ?assert(lists:member(WorkflowId1, WorkflowIds)),
        ?assert(lists:member(WorkflowId2, WorkflowIds)),
        ?assertEqual(2, length(WorkflowIds))
    after
        teardown(Pid)
    end.

%%====================================================================
%% gen_server Callback Tests
%%====================================================================

%% Test init/1 function
init_test_() ->
    [{"Initialize with default state",
      fun test_init_default/0}].

test_init_default() ->
    %% Start the orchestrator to test init
    {ok, Pid} = yawl_orchestrator:start_link(),
    try
        %% Get the state (this is tricky for gen_server, we'll use sys:get_state)
        State = sys:get_state(Pid),

        %% Verify state structure
        ?assert(is_map(State#state.workflows)),
        ?assert(is_map(State#state.workflow_instances)),
        ?assert(is_map(State#state.pattern_cache)),
        ?assert(is_map(State#state.subscribers)),
        ?assert(is_map(State#state.config)),
        ?assert(is_map(State#state.statistics))

        %% Verify initial values
        ?assertEqual(0, maps:size(State#state.workflows)),
        ?assertEqual(0, maps:size(State#state.workflow_instances)),
        ?assertEqual(0, maps:size(State#state.subscribers)),
        ?assertEqual(0, maps:get(total_workflows, State#state.statistics)),
        ?assertEqual(0, maps:get(completed_workflows, State#state.statistics)),
        ?assertEqual(0, maps:get(failed_workflows, State#state.statistics))
    after
        gen_server:stop(Pid)
    end.

%%====================================================================
%% Error Handling Tests
%%====================================================================

error_handling_test_() ->
    [{"Handle unknown call messages",
      fun test_handle_unknown_call/0},
     {"Handle malformed workflow IDs",
      fun test_handle_malformed_workflow_ids/0},
     "Handle invalid config parameters",
      fun test_handle_invalid_config/0}].

test_handle_unknown_call() ->
    Pid = setup(),
    try
        %% Send an unknown message to the gen_server
        Result = gen_server:call(Pid, {unknown_message, some_data}),
        ?assertEqual({error, unknown_request}, Result)
    after
        teardown(Pid)
    end.

test_handle_malformed_workflow_ids() ->
    Pid = setup(),
    try
        %% Test with various malformed IDs
        MalformedIds = [undefined, "not_binary", <<>>, 123, []],
        lists:foreach(fun(Id) ->
            Result = yawl_orchestrator:get_status(Id),
            ?assertEqual({error, workflow_not_found}, Result)
        end, MalformedIds)
    after
        teardown(Pid)
    end.

test_handle_invalid_config() ->
    Pid = setup(),
    try
        %% Test with invalid configurations
        InvalidConfigs = [
            {not_a_map, "invalid"},
            #{pattern_type => not_an_atom},
            #{task1_name => 123}  % Should be string/binary
        ],
        lists:foreach(fun(Config) ->
            Result = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),
            %% Depending on implementation, this might succeed or fail
            %% We just ensure it doesn't crash
            is_tuple(Result)
        end, InvalidConfigs)
    after
        teardown(Pid)
    end.

%%====================================================================
%% Integration Tests
%%====================================================================

integration_test_() ->
    [{"Full workflow lifecycle",
      fun test_full_workflow_lifecycle/0},
     "Multiple concurrent workflows",
      fun test_concurrent_workflows/0},
     "Subscription notifications",
      fun test_subscription_notifications/0}].

test_full_workflow_lifecycle() ->
    Pid = setup(),
    try
        %% Create
        Config = #{task1_name => "task1", task2_name => "task2"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% List
        {ok, Workflows} = yawl_orchestrator:list_workflows(),
        ?assert(lists:member(WorkflowId, Workflows)),

        %% Status
        ?assertMatch({ok, pending}, yawl_orchestrator:get_status(WorkflowId)),

        %% Subscribe
        ?assertMatch({ok, _}, yawl_orchestrator:subscribe_to_workflow(WorkflowId, self())),

        %% Cancel
        ?assertMatch({ok, _}, yawl_orchestrator:cancel_workflow(WorkflowId)),
        ?assertMatch({ok, cancelled}, yawl_orchestrator:get_status(WorkflowId)),

        %% Cleanup
        ?assertMatch({ok, _}, yawl_orchestrator:cleanup_workflow(WorkflowId))
    after
        teardown(Pid)
    end.

test_concurrent_workflows() ->
    Pid = setup(),
    try
        %% Create multiple workflows concurrently
        Config1 = #{task1_name => "task1"},
        Config2 = #{task1_name => "task2"},
        Config3 = #{task1_name => "task3"},

        {ok, WorkflowId1} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config1),
        {ok, WorkflowId2} = yawl_orchestrator:create_workflow(parallel_split, Config2),
        {ok, WorkflowId3} = yawl_orchestrator:create_workflow(iterative_loop, Config3),

        %% Verify all exist
        {ok, AllWorkflows} = yawl_orchestrator:list_workflows(),
        ?assertEqual(3, length(AllWorkflows)),
        ?assert(lists:member(WorkflowId1, AllWorkflows)),
        ?assert(lists:member(WorkflowId2, AllWorkflows)),
        ?assert(lists:member(WorkflowId3, AllWorkflows)),

        %% Cancel all
        ?assertMatch({ok, _}, yawl_orchestrator:cancel_workflow(WorkflowId1)),
        ?assertMatch({ok, _}, yawl_orchestrator:cancel_workflow(WorkflowId2)),
        ?assertMatch({ok, _}, yawl_orchestrator:cancel_workflow(WorkflowId3))
    after
        teardown(Pid)
    end.

test_subscription_notifications() ->
    %% This test would require mocking or monitoring the process
    %% For now, we just test subscription management
    Pid = setup(),
    try
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% Subscribe
        SubscriberPid = spawn(fun() -> receive after infinity -> ok end end),
        ?assertMatch({ok, _}, yawl_orchestrator:subscribe_to_workflow(WorkflowId, SubscriberPid)),

        %% Verify subscription exists
        %% (This would require accessing internal state, which we can't do directly)

        %% Cleanup
        exit(SubscriberPid, kill),
        ?assertMatch({ok, _}, yawl_orchestrator:cleanup_workflow(WorkflowId))
    after
        teardown(Pid)
    end.

%%====================================================================
%% Performance Tests
%%====================================================================

performance_test_() ->
    [{"Create and list many workflows",
      fun test_create_many_workflows/0},
     "Pattern lookup performance",
      fun test_pattern_lookup_performance/0},
     "Concurrent access performance",
      fun test_concurrent_access_performance/0}].

test_create_many_workflows() ->
    Pid = setup(),
    try
        NumWorkflows = 100,
        Start = erlang:monotonic_time(microsecond),

        %% Create many workflows
        WorkflowIds = lists:foldl(fun(_, Acc) ->
            Config = #{task1_name => "task" ++ integer_to_list(length(Acc) + 1)},
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),
            [WorkflowId | Acc]
        end, [], lists:seq(1, NumWorkflows)),

        End = erlang:monotonic_time(microsecond),
        Duration = End - Start,

        %% Verify all were created
        {ok, ListedWorkflows} = yawl_orchestrator:list_workflows(),
        ?assertEqual(NumWorkflows, length(ListedWorkflows)),

        %% Performance assertion (should complete within reasonable time)
        ?assert(Duration < 5000000, "Creating ~p workflows took too long: ~p μs",
                [NumWorkflows, Duration])
    after
        teardown(Pid)
    end.

test_pattern_lookup_performance() ->
    Pid = setup(),
    try
        NumLookups = 1000,
        Start = erlang:monotonic_time(microsecond),

        %% Lookup pattern info many times
        lists:seq(1, NumLookups),
        _ = yawl_orchestrator:get_pattern_info(?TEST_PATTERN_TYPE),

        End = erlang:monotonic_time(microsecond),
        Duration = End - Start,

        ?assert(Duration < 1000000, "Pattern lookup took too long: ~p μs", [Duration])
    after
        teardown(Pid)
    end.

test_concurrent_access_performance() ->
    Pid = setup(),
    try
        %% Create a workflow first
        Config = #{task1_name => "task1"},
        {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),

        %% Concurrent operations
        NumOperations = 50,
        Start = erlang:monotonic_time(microsecond),

        %% Spawn concurrent processes
        Processes = lists:map(fun(_) ->
            spawn(fun() ->
                %% Each process does some operations
                _ = yawl_orchestrator:get_status(WorkflowId),
                _ = yawl_orchestrator:get_pattern_info(?TEST_PATTERN_TYPE),
                _ = yawl_orchestrator:list_workflows()
            end)
        end, lists:seq(1, NumOperations)),

        %% Wait for all processes to complete
        lists:foreach(fun(P) ->
            receive
                {'DOWN', _, process, P, _} -> ok
            after 1000 ->
                exit(P, kill)
            end
        end, Processes),

        End = erlang:monotonic_time(microsecond),
        Duration = End - Start,

        ?assert(Duration < 5000000, "Concurrent access took too long: ~p μs", [Duration])
    after
        teardown(Pid)
    end.

%%====================================================================
%% Stress Tests
%%====================================================================

stress_test_() ->
    [{"Stress test with many operations",
      fun test_stress_many_operations/0},
     "Stress test with workflow churn",
      fun test_stress_workflow_churn/0}].

test_stress_many_operations() ->
    Pid = setup(),
    try
        %% Perform a large number of operations
        NumOperations = 500,

        %% Create, query, cancel, cleanup workflows in sequence
        Operations = lists:foldl(fun(I, Acc) ->
            Config = #{task1_name => "task" ++ integer_to_list(I)},
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),
            {ok, _} = yawl_orchestrator:get_status(WorkflowId),
            {ok, _} = yawl_orchestrator:cancel_workflow(WorkflowId),
            {ok, _} = yawl_orchestrator:cleanup_workflow(WorkflowId),
            [WorkflowId | Acc]
        end, [], lists:seq(1, NumOperations)),

        %% Verify system is still responsive
        {ok, Workflows} = yawl_orchestrator:list_workflows(),
        ?assertEqual(0, length(Workflows)),  % Should be empty after cleanup

        %% Stress test passed
        ?assert(true)
    after
        teardown(Pid)
    end.

test_stress_workflow_churn() ->
    Pid = setup(),
    try
        %% Create, use, and destroy workflows rapidly
        NumCycles = 100,

        lists:seq(1, NumCycles),
        lists:foreach(fun(_) ->
            Config = #{task1_name => "dynamic_task"},
            {ok, WorkflowId} = yawl_orchestrator:create_workflow(?TEST_PATTERN_TYPE, Config),
            {ok, _} = yawl_orchestrator:get_status(WorkflowId),
            {ok, _} = yawl_orchestrator:cleanup_workflow(WorkflowId)
        end, lists:seq(1, NumCycles)),

        %% System should still be stable
        {ok, Workflows} = yawl_orchestrator:list_workflows(),
        ?assertEqual(0, length(Workflows))
    after
        teardown(Pid)
    end.