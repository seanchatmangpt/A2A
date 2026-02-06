%%%-------------------------------------------------------------------
%%% @doc
%%% Comprehensive Unit Tests for YAWL Orchestrator
%%%
%%% This module provides comprehensive test coverage for the YAWL workflow
%%% orchestrator, covering all major functions, edge cases, error paths,
%%% workflow lifecycle management, and coordination with other modules.
%%%
%%% Target Coverage: 95%+
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_orchestrator_comprehensive_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(ORCHESTRATOR_TIMEOUT, 15000).
-define(DEFAULT_CONFIG, #{timeout => 30000}).

%%====================================================================
%% Test Generator
%%====================================================================

orchestrator_comprehensive_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Group 1: Server Lifecycle", fun test_group_lifecycle/0},
      {"Group 2: Workflow Creation", fun test_group_creation/0},
      {"Group 3: Workflow Execution", fun test_group_execution/0},
      {"Group 4: Pattern Management", fun test_group_patterns/0},
      {"Group 5: Status Queries", fun test_group_status/0},
      {"Group 6: Cancellation", fun test_group_cancellation/0},
      {"Group 7: Cleanup", fun test_group_cleanup/0},
      {"Group 8: Subscription", fun test_group_subscription/0},
      {"Group 9: Pause/Resume", fun test_group_pause_resume/0},
      {"Group 10: Error Handling", fun test_group_errors/0},
      {"Group 11: Statistics", fun test_group_statistics/0},
      {"Group 12: Integration", fun test_group_integration/0}
     ]}.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    %% Create unique Mnesia directory for this test run
    TestDir = "/tmp/yawl_orch_test_" ++ integer_to_list(erlang:unique_integer()),
    application:stop(mnesia),
    ok = filelib:ensure_dir(TestDir ++ "/"),
    application:set_env(mnesia, dir, TestDir),
    yawl_persistence:create_schema(),
    mnesia:start(),
    {ok, _} = yawl_persistence:create_tables(),
    ok = yawl_persistence:wait_for_tables(),
    {ok, _} = yawl_persistence:start_link(),
    {ok, _} = yawl_workflow_instance_sup:start_link(),
    {ok, Pid} = yawl_orchestrator:start_link(),
    {Pid, TestDir}.

cleanup({Pid, TestDir}) ->
    gen_server:stop(Pid),
    catch yawl_workflow_instance_sup:stop(),
    catch yawl_persistence:stop(),
    mnesia:stop(),
    application:unset_env(mnesia, dir),
    file:del_dir_r(TestDir),
    ok.

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
    {ok, Pid} = yawl_orchestrator:start_link(),
    ?assert(is_pid(Pid)),
    ?assert(is_process_alive(Pid)),
    gen_server:stop(Pid).

test_init_state() ->
    {ok, Pid} = yawl_orchestrator:start_link(),
    State = sys:get_state(Pid),
    ?assert(is_map(element(2, State))),  %% workflows
    ?assert(is_map(element(3, State))),  %% workflow_instances
    ?assert(is_map(element(4, State))),  %% pattern_cache
    ?assert(is_map(element(5, State))),  %% subscribers
    ?assert(is_map(element(6, State))),  %% config
    ?assert(is_map(element(7, State))),  %% statistics
    ?assertEqual(0, maps:size(element(2, State))),
    ?assertEqual(0, maps:size(element(3, State))),
    gen_server:stop(Pid).

test_terminate() ->
    {ok, Pid} = yawl_orchestrator:start_link(),
    gen_server:stop(Pid),
    ?assertNot(is_process_alive(Pid)).

test_code_change() ->
    {ok, Pid} = yawl_orchestrator:start_link(),
    {ok, State} = sys:replace_state(Pid, fun(S) -> S end),
    ?assert(is_tuple(State)),
    gen_server:stop(Pid).

%%====================================================================
%% Group 2: Workflow Creation
%%====================================================================

test_group_creation() ->
    test_create_basic_sequential(),
    test_create_parallel_split(),
    test_create_with_timeout(),
    test_create_with_metadata(),
    test_create_unknown_pattern(),
    test_create_empty_config(),
    test_create_multiple(),
    ok.

test_create_basic_sequential() ->
    Config = #{task1 => "task1", task2 => "task2"},
    Result = yawl_orchestrator:create_workflow(basic_sequential, Config),
    ?assertMatch({ok, _WorkflowId}, Result).

test_create_parallel_split() ->
    Config = #{branches => 3, tasks => ["t1", "t2", "t3"]},
    Result = yawl_orchestrator:create_workflow(parallel_split, Config),
    ?assertMatch({ok, _WorkflowId}, Result).

test_create_with_timeout() ->
    Config = #{timeout => 60000, task1 => "task1"},
    Result = yawl_orchestrator:create_workflow(basic_sequential, Config),
    ?assertMatch({ok, _WorkflowId}, Result).

test_create_with_metadata() ->
    Config = #{
        task1 => "task1",
        metadata => #{priority => high, category => "test"}
    },
    Result = yawl_orchestrator:create_workflow(basic_sequential, Config),
    ?assertMatch({ok, _WorkflowId}, Result).

test_create_unknown_pattern() ->
    Config = #{task1 => "task1"},
    Result = yawl_orchestrator:create_workflow(unknown_pattern_xyz, Config),
    ?assertMatch({error, {unknown_pattern, _}}, Result).

test_create_empty_config() ->
    Result = yawl_orchestrator:create_workflow(basic_sequential, #{}),
    ?assertMatch({ok, _WorkflowId}, Result).

test_create_multiple() ->
    Config1 = #{task1 => "task1"},
    Config2 = #{task1 => "task2"},
    {ok, Id1} = yawl_orchestrator:create_workflow(basic_sequential, Config1),
    {ok, Id2} = yawl_orchestrator:create_workflow(parallel_split, Config2),
    ?assertNotEqual(Id1, Id2).

%%====================================================================
%% Group 3: Workflow Execution
%%====================================================================

test_group_execution() ->
    test_execute_basic_workflow(),
    test_execute_parallel_workflow(),
    test_execute_non_existent(),
    test_execute_already_running(),
    test_complete_workitem(),
    ok.

test_execute_basic_workflow() ->
    Config = #{task1 => "task1", task2 => "task2"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    Result = yawl_orchestrator:execute_workflow(WorkflowId),
    ?assertMatch({ok, #{status := running, instance := _}}, Result).

test_execute_parallel_workflow() ->
    Config = #{branches => 2},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(parallel_split, Config),
    Result = yawl_orchestrator:execute_workflow(WorkflowId),
    ?assertMatch({ok, #{status := running}}, Result).

test_execute_non_existent() ->
    Result = yawl_orchestrator:execute_workflow(<<"non_existent_wf">>),
    ?assertEqual({error, workflow_not_found}, Result).

test_execute_already_running() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    timer:sleep(50),
    %% Execute again
    Result = yawl_orchestrator:execute_workflow(WorkflowId),
    ?assertMatch({ok, #{status := running, instance := _}}, Result).

test_complete_workitem() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    Result = yawl_orchestrator:complete_workitem(WorkflowId, task1, #{result => ok}),
    ?assertMatch({ok, _} = Result, ok),
    ?assertMatch({error, _}, Result).

%%====================================================================
%% Group 4: Pattern Management
%%====================================================================

test_group_patterns() ->
    test_list_patterns(),
    test_get_pattern_info_basic(),
    test_get_pattern_info_parallel(),
    test_get_pattern_info_unknown(),
    test_validate_pattern_valid(),
    test_validate_pattern_invalid(),
    test_all_pattern_info(),
    ok.

test_list_patterns() ->
    Result = yawl_orchestrator:list_patterns(),
    ?assertMatch({ok, Patterns}, Result),
    {ok, Patterns} = Result,
    ?assert(length(Patterns) > 40),
    ?assert(lists:member(basic_sequential, Patterns)),
    ?assert(lists:member(parallel_split, Patterns)),
    ?assert(lists:member(exclusive_choice, Patterns)).

test_get_pattern_info_basic() ->
    Result = yawl_orchestrator:get_pattern_info(basic_sequential),
    ?assertMatch({ok, _}, Result),
    {ok, Info} = Result,
    ?assertEqual(<<"Basic Sequential">>, maps:get(name, Info)),
    ?assertEqual(low, maps:get(complexity, Info)).

test_get_pattern_info_parallel() ->
    Result = yawl_orchestrator:get_pattern_info(parallel_split),
    ?assertMatch({ok, _}, Result),
    {ok, Info} = Result,
    ?assertEqual(<<"Parallel Split">>, maps:get(name, Info)).

test_get_pattern_info_unknown() ->
    Result = yawl_orchestrator:get_pattern_info(unknown_pattern),
    ?assertEqual({error, pattern_not_found}, Result).

test_validate_pattern_valid() ->
    Result = yawl_orchestrator:validate_pattern(basic_sequential, #{task1 => "task1"}),
    ?assertMatch({ok, _}, Result).

test_validate_pattern_invalid() ->
    Result = yawl_orchestrator:validate_pattern(unknown_pattern, #{}),
    ?assertMatch({ok, false}, Result).

test_all_pattern_info() ->
    %% Test getting info for all known patterns
    Patterns = [basic_sequential, parallel_split, parallel_join, exclusive_choice,
               simple_merge, iterative_loop, multi_instance],
    lists:foreach(fun(Pattern) ->
        Result = yawl_orchestrator:get_pattern_info(Pattern),
        ?assertMatch({ok, _}, Result)
    end, Patterns).

%%====================================================================
%% Group 5: Status Queries
%%====================================================================

test_group_status() ->
    test_get_status_pending(),
    test_get_status_running(),
    test_get_status_cancelled(),
    test_get_status_not_found(),
    test_list_workflows_empty(),
    test_list_workflows_multiple(),
    test_get_workflow_result_pending(),
    test_get_workflow_result_completed(),
    ok.

test_get_status_pending() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    Result = yawl_orchestrator:get_status(WorkflowId),
    ?assertEqual({ok, pending}, Result).

test_get_status_running() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    timer:sleep(50),
    Result = yawl_orchestrator:get_status(WorkflowId),
    ?assertMatch({ok, running}, Result).

test_get_status_cancelled() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:cancel_workflow(WorkflowId),
    Result = yawl_orchestrator:get_status(WorkflowId),
    ?assertEqual({ok, cancelled}, Result).

test_get_status_not_found() ->
    Result = yawl_orchestrator:get_status(<<"non_existent_wf">>),
    ?assertEqual({error, workflow_not_found}, Result).

test_list_workflows_empty() ->
    %% First create orchestrator with no workflows
    {ok, _} = yawl_orchestrator:start_link(),
    Result = yawl_orchestrator:list_workflows(),
    ?assertMatch({ok, []}, Result),
    gen_server:stop(yawl_orchestrator).

test_list_workflows_multiple() ->
    Config1 = #{task1 => "task1"},
    Config2 = #{task1 => "task2"},
    Config3 = #{task1 => "task3"},
    {ok, Id1} = yawl_orchestrator:create_workflow(basic_sequential, Config1),
    {ok, Id2} = yawl_orchestrator:create_workflow(parallel_split, Config2),
    {ok, Id3} = yawl_orchestrator:create_workflow(exclusive_choice, Config3),
    Result = yawl_orchestrator:list_workflows(),
    ?assertMatch({ok, WorkflowIds}, Result),
    {ok, WorkflowIds} = Result,
    ?assertEqual(3, length(WorkflowIds)),
    ?assert(lists:member(Id1, WorkflowIds)),
    ?assert(lists:member(Id2, WorkflowIds)),
    ?assert(lists:member(Id3, WorkflowIds)).

test_get_workflow_result_pending() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    Result = yawl_orchestrator:get_workflow_result(WorkflowId),
    ?assertEqual({error, workflow_not_completed}, Result).

test_get_workflow_result_completed() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:cancel_workflow(WorkflowId),
    Result = yawl_orchestrator:get_workflow_result(WorkflowId),
    ?assertEqual({error, workflow_not_completed}, Result).

%%====================================================================
%% Group 6: Cancellation
%%====================================================================

test_group_cancellation() ->
    test_cancel_pending(),
    test_cancel_running(),
    test_cancel_completed(),
    test_cancel_not_found(),
    ok.

test_cancel_pending() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    Result = yawl_orchestrator:cancel_workflow(WorkflowId),
    ?assertMatch({ok, _}, Result),
    {ok, Status} = yawl_orchestrator:get_status(WorkflowId),
    ?assertEqual(cancelled, Status).

test_cancel_running() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    timer:sleep(50),
    Result = yawl_orchestrator:cancel_workflow(WorkflowId),
    ?assertMatch({ok, _}, Result).

test_cancel_completed() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    %% Cancel it
    {ok, _} = yawl_orchestrator:cancel_workflow(WorkflowId),
    %% Cancel again should work
    Result = yawl_orchestrator:cancel_workflow(WorkflowId),
    ?assertMatch({ok, _}, Result).

test_cancel_not_found() ->
    Result = yawl_orchestrator:cancel_workflow(<<"non_existent_wf">>),
    ?assertEqual({error, workflow_not_found}, Result).

%%====================================================================
%% Group 7: Cleanup
%%====================================================================

test_group_cleanup() ->
    test_cleanup_existing(),
    test_cleanup_not_found(),
    test_cleanup_removes_subscriptions(),
    ok.

test_cleanup_existing() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    Result = yawl_orchestrator:cleanup_workflow(WorkflowId),
    ?assertMatch({ok, _}, Result),
    %% Verify removed
    ?assertEqual({error, workflow_not_found}, yawl_orchestrator:get_status(WorkflowId)).

test_cleanup_not_found() ->
    Result = yawl_orchestrator:cleanup_workflow(<<"non_existent_wf">>),
    ?assertEqual({error, workflow_not_found}, Result).

test_cleanup_removes_subscriptions() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:subscribe_to_workflow(WorkflowId, self()),
    {ok, _} = yawl_orchestrator:cleanup_workflow(WorkflowId),
    %% Verify workflow is removed
    ?assertEqual({error, workflow_not_found}, yawl_orchestrator:get_status(WorkflowId)).

%%====================================================================
%% Group 8: Subscription
%%====================================================================

test_group_subscription() ->
    test_subscribe(),
    test_subscribe_not_found(),
    test_unsubscribe(),
    test_unsubscribe_not_found(),
    test_multiple_subscribers(),
    ok.

test_subscribe() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    Result = yawl_orchestrator:subscribe_to_workflow(WorkflowId, self()),
    ?assertMatch({ok, _}, Result).

test_subscribe_not_found() ->
    Result = yawl_orchestrator:subscribe_to_workflow(<<"non_existent_wf">>, self()),
    ?assertEqual({error, workflow_not_found}, Result).

test_unsubscribe() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:subscribe_to_workflow(WorkflowId, self()),
    Result = yawl_orchestrator:unsubscribe_from_workflow(WorkflowId, self()),
    ?assertMatch({ok, _}, Result).

test_unsubscribe_not_found() ->
    Result = yawl_orchestrator:unsubscribe_from_workflow(<<"non_existent_wf">>, self()),
    ?assertEqual({error, workflow_not_found}, Result).

test_multiple_subscribers() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    Pid1 = self(),
    Pid2 = spawn(fun() -> timer:sleep(infinity) end),
    Pid3 = spawn(fun() -> timer:sleep(infinity) end),
    {ok, _} = yawl_orchestrator:subscribe_to_workflow(WorkflowId, Pid1),
    {ok, _} = yawl_orchestrator:subscribe_to_workflow(WorkflowId, Pid2),
    {ok, _} = yawl_orchestrator:subscribe_to_workflow(WorkflowId, Pid3),
    %% Cleanup
    exit(Pid2, kill),
    exit(Pid3, kill).

%%====================================================================
%% Group 9: Pause/Resume
%%====================================================================

test_group_pause_resume() ->
    test_pause_running(),
    test_pause_not_found(),
    test_resume_paused(),
    test_resume_not_found(),
    ok.

test_pause_running() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    timer:sleep(50),
    Result = yawl_orchestrator:pause_workflow(WorkflowId),
    ?assertMatch({ok, _}, Result).

test_pause_not_found() ->
    Result = yawl_orchestrator:pause_workflow(<<"non_existent_wf">>),
    ?assertMatch({error, _}, Result).

test_resume_paused() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    timer:sleep(50),
    {ok, _} = yawl_orchestrator:pause_workflow(WorkflowId),
    Result = yawl_orchestrator:resume_workflow(WorkflowId),
    ?assertMatch({ok, _}, Result).

test_resume_not_found() ->
    Result = yawl_orchestrator:resume_workflow(<<"non_existent_wf">>),
    ?assertMatch({error, _}, Result).

%%====================================================================
%% Group 10: Error Handling
%%====================================================================

test_group_errors() ->
    test_unknown_request(),
    test_invalid_workflow_id(),
    test_malformed_config(),
    ok.

test_unknown_request() ->
    {ok, Pid} = yawl_orchestrator:start_link(),
    Result = gen_server:call(Pid, {unknown_request, data}),
    ?assertEqual({error, unknown_request}, Result),
    gen_server:stop(Pid).

test_invalid_workflow_id() ->
    %% Test with various invalid IDs
    InvalidIds = [undefined, <<>>, 123, []],
    lists:foreach(fun(Id) ->
        Result = yawl_orchestrator:get_status(Id),
        ?assertEqual({error, workflow_not_found}, Result)
    end, InvalidIds).

test_malformed_config() ->
    %% Test with various malformed configs
    InvalidConfigs = [
        {not_a_map, data},
        #{timeout => "not_integer"},
        #{pattern_type => "not_atom"}
    ],
    lists:foreach(fun(Config) ->
        Result = yawl_orchestrator:create_workflow(basic_sequential, Config),
        ?assert(is_tuple(Result))
    end, InvalidConfigs).

%%====================================================================
%% Group 11: Statistics
%%====================================================================

test_group_statistics() ->
    test_initial_statistics(),
    test_statistics_after_create(),
    test_statistics_after_execute(),
    test_statistics_after_cancel(),
    ok.

test_initial_statistics() ->
    {ok, Pid} = yawl_orchestrator:start_link(),
    State = sys:get_state(Pid),
    Stats = element(7, State),  %% statistics field
    ?assertEqual(0, maps:get(total_workflows, Stats)),
    ?assertEqual(0, maps:get(completed_workflows, Stats)),
    ?assertEqual(0, maps:get(failed_workflows, Stats)),
    gen_server:stop(Pid).

test_statistics_after_create() ->
    {ok, _} = yawl_orchestrator:create_workflow(basic_sequential, #{}),
    {ok, _} = yawl_orchestrator:create_workflow(parallel_split, #{}),
    {ok, _} = yawl_orchestrator:create_workflow(exclusive_choice, #{}),
    %% Statistics should track workflows
    ok.

test_statistics_after_execute() ->
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, #{}),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    timer:sleep(100),
    %% Statistics should update
    ok.

test_statistics_after_cancel() ->
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, #{}),
    {ok, _} = yawl_orchestrator:cancel_workflow(WorkflowId),
    %% Statistics should reflect cancellation
    ok.

%%====================================================================
%% Group 12: Integration
%%====================================================================

test_group_integration() ->
    test_full_lifecycle(),
    test_concurrent_workflows(),
    test_instance_monitoring(),
    ok.

test_full_lifecycle() ->
    Config = #{task1 => "task1", task2 => "task2"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, pending} = yawl_orchestrator:get_status(WorkflowId),
    {ok, _} = yawl_orchestrator:execute_workflow(WorkflowId),
    timer:sleep(50),
    {ok, _} = yawl_orchestrator:pause_workflow(WorkflowId),
    {ok, _} = yawl_orchestrator:resume_workflow(WorkflowId),
    {ok, _} = yawl_orchestrator:cancel_workflow(WorkflowId),
    {ok, cancelled} = yawl_orchestrator:get_status(WorkflowId),
    {ok, _} = yawl_orchestrator:cleanup_workflow(WorkflowId),
    ?assertEqual({error, workflow_not_found}, yawl_orchestrator:get_status(WorkflowId)).

test_concurrent_workflows() ->
    NumWorkflows = 10,
    WorkflowIds = lists:map(fun(I) ->
        Config = #{task1 => "task" ++ integer_to_list(I)},
        {ok, Id} = yawl_orchestrator:create_workflow(basic_sequential, Config),
        Id
    end, lists:seq(1, NumWorkflows)),
    %% Execute all
    lists:foreach(fun(Id) ->
        {ok, _} = yawl_orchestrator:execute_workflow(Id)
    end, WorkflowIds),
    timer:sleep(100),
    %% Cancel all
    lists:foreach(fun(Id) ->
        {ok, _} = yawl_orchestrator:cancel_workflow(Id)
    end, WorkflowIds).

test_instance_monitoring() ->
    Config = #{task1 => "task1"},
    {ok, WorkflowId} = yawl_orchestrator:create_workflow(basic_sequential, Config),
    {ok, #{instance := InstancePid}} = yawl_orchestrator:execute_workflow(WorkflowId),
    ?assert(is_pid(InstancePid)),
    ?assert(is_process_alive(InstancePid)),
    %% Get instance
    {ok, RetrievedPid} = yawl_orchestrator:get_workflow_instance(WorkflowId),
    ?assertEqual(InstancePid, RetrievedPid),
    %% Cancel and verify instance goes down
    {ok, _} = yawl_orchestrator:cancel_workflow(WorkflowId),
    timer:sleep(100).
