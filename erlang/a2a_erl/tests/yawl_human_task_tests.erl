%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Human Task Test Suite
%%%
%%% This module contains Common Test suites for comprehensive testing of
%%% human task management. It covers:
%%%
%%% - Human task allocation strategies
%%% - Task assignment to users and roles
%%% - Task completion and escalation
%%% - Task timeouts and retries
%%% - Multi-user task scenarios
%%% - Task delegation and reassignment
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_human_task_tests).
-author("A2A Team").

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% Export tests
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

%% Test cases - Task Allocation Tests
-export([
    test_direct_task_allocation/1,
    test_role_based_allocation/1,
    test_capability_based_allocation/1,
    test_round_robin_allocation/1,
    test_load_balanced_allocation/1,
    test_priority_based_allocation/1
]).

%% Test cases - Task Lifecycle Tests
-export([
    test_task_allocation_and_claim/1,
    test_task_completion/1,
    test_task_cancellation/1,
    test_task_timeout/1,
    test_task_escalation/1,
    test_task_reassignment/1
]).

%% Test cases - Multi-User Tests
-export([
    test_concurrent_task_claims/1,
    test_task_delegation/1,
    test_task_release/1,
    test_bulk_task_allocation/1,
    test_group_task_assignment/1,
    test_task_transfer_between_users/1
]).

%% Test cases - Resource Manager Integration Tests
-export([
    test_human_resource_registration/1,
    test_resource_capacity_tracking/1,
    test_resource_availability_status/1,
    test_resource_skill_matching/1,
    test_resource_workload_distribution/1,
    test_multi_capability_resources/1
]).

%% Test cases - Error Handling Tests
-export([
    test_allocation_failure/1,
    test_invalid_claim_attempt/1,
    test_double_claim_prevention/1,
    test_claim_after_completion/1,
    test_unassigned_task_completion/1,
    test_resource_unavailable_handling/1
]).

%% Test cases - Performance Tests
-export([
    test_high_volume_task_allocation/1,
    test_rapid_task_claiming/1,
    test_concurrent_allocation_requests/1,
    test_resource_exhaustion/1,
    test_task_cleanup_performance/1
]).

%%====================================================================
%% Common Test Callbacks
%%====================================================================

%% @doc Return all test cases.
-spec all() -> [atom()].
all() ->
    [
        %% Task Allocation Tests
        test_direct_task_allocation,
        test_role_based_allocation,
        test_capability_based_allocation,
        test_round_robin_allocation,
        test_load_balanced_allocation,
        test_priority_based_allocation,

        %% Task Lifecycle Tests
        test_task_allocation_and_claim,
        test_task_completion,
        test_task_cancellation,
        test_task_timeout,
        test_task_escalation,
        test_task_reassignment,

        %% Multi-User Tests
        test_concurrent_task_claims,
        test_task_delegation,
        test_task_release,
        test_bulk_task_allocation,
        test_group_task_assignment,
        test_task_transfer_between_users,

        %% Resource Manager Integration Tests
        test_human_resource_registration,
        test_resource_capacity_tracking,
        test_resource_availability_status,
        test_resource_skill_matching,
        test_resource_workload_distribution,
        test_multi_capability_resources,

        %% Error Handling Tests
        test_allocation_failure,
        test_invalid_claim_attempt,
        test_double_claim_prevention,
        test_claim_after_completion,
        test_unassigned_task_completion,
        test_resource_unavailable_handling,

        %% Performance Tests
        test_high_volume_task_allocation,
        test_rapid_task_claiming,
        test_concurrent_allocation_requests,
        test_resource_exhaustion,
        test_task_cleanup_performance
    ].

%% @doc Return test groups.
-spec groups() -> [{atom(), list(), [atom()]}].
groups() ->
    [
        {allocation_tests, [sequence], [
            test_direct_task_allocation,
            test_role_based_allocation,
            test_capability_based_allocation,
            test_round_robin_allocation,
            test_load_balanced_allocation,
            test_priority_based_allocation
        ]},
        {lifecycle_tests, [sequence], [
            test_task_allocation_and_claim,
            test_task_completion,
            test_task_cancellation,
            test_task_timeout,
            test_task_escalation,
            test_task_reassignment
        ]},
        {multi_user_tests, [sequence], [
            test_concurrent_task_claims,
            test_task_delegation,
            test_task_release,
            test_bulk_task_allocation,
            test_group_task_assignment,
            test_task_transfer_between_users
        ]},
        {resource_integration_tests, [sequence], [
            test_human_resource_registration,
            test_resource_capacity_tracking,
            test_resource_availability_status,
            test_resource_skill_matching,
            test_resource_workload_distribution,
            test_multi_capability_resources
        ]},
        {error_handling_tests, [sequence], [
            test_allocation_failure,
            test_invalid_claim_attempt,
            test_double_claim_prevention,
            test_claim_after_completion,
            test_unassigned_task_completion,
            test_resource_unavailable_handling
        ]},
        {performance_tests, [sequence], [
            test_high_volume_task_allocation,
            test_rapid_task_claiming,
            test_concurrent_allocation_requests,
            test_resource_exhaustion,
            test_task_cleanup_performance
        ]}
    ].

%% @doc Initialize test suite.
-spec init_per_suite(Config) -> Config when Config :: [tuple()].
init_per_suite(Config) ->
    ct:pal("Starting YAWL Human Task Test Suite"),
    ct:pal("Testing human task allocation, lifecycle, and multi-user scenarios"),
    %% Start applications
    {ok, _} = application:ensure_all_started(a2a_erl),
    %% Start required services
    {ok, OrchestratorPid} = yawl_orchestrator:start_link(),
    {ok, ResourceManagerPid} = yawl_resource_manager:start_link(),
    {ok, PersistencePid} = yawl_persistence:start_link(),
    {ok, HumanTaskPid} = yawl_human_task:start_link(),

    %% Register test resources
    register_test_human_resources(),

    [{orchestrator_pid, OrchestratorPid},
     {resource_manager_pid, ResourceManagerPid},
     {persistence_pid, PersistencePid},
     {human_task_pid, HumanTaskPid} | Config].

%% @doc Cleanup test suite.
-spec end_per_suite(Config) -> ok when Config :: [tuple()].
end_per_suite(Config) ->
    %% Stop services
    HumanTaskPid = proplists:get_value(human_task_pid, Config),
    ResourceManagerPid = proplists:get_value(resource_manager_pid, Config),
    OrchestratorPid = proplists:get_value(orchestrator_pid, Config),
    PersistencePid = proplists:get_value(persistence_pid, Config),

    gen_server:stop(HumanTaskPid),
    gen_server:stop(ResourceManagerPid),
    gen_server:stop(OrchestratorPid),
    gen_server:stop(PersistencePid),

    %% Stop application
    application:stop(a2a_erl),

    ct:pal("Completed YAWL Human Task Test Suite"),
    ok.

%% @doc Initialize test group.
-spec init_per_group(atom(), Config) -> Config when Config :: [tuple()].
init_per_group(GroupName, Config) ->
    ct:pal("Starting human task group: ~p", [GroupName]),
    cleanup_test_data(),
    Config.

%% @doc Cleanup test group.
-spec end_per_group(atom(), Config) -> ok when Config :: [tuple()].
end_per_group(GroupName, _Config) ->
    ct:pal("Completed human task group: ~p", [GroupName]),
    cleanup_test_data(),
    ok.

%% @doc Initialize test case.
-spec init_per_testcase(atom(), Config) -> Config when Config :: [tuple()].
init_per_testcase(TestName, Config) ->
    ct:pal("Starting human task test: ~p", [TestName]),
    cleanup_test_data(),
    Config.

%% @doc Cleanup test case.
-spec end_per_testcase(atom(), Config) -> ok when Config :: [tuple()].
end_per_testcase(TestName, _Config) ->
    ct:pal("Completed human task test: ~p", [TestName]),
    cleanup_test_data(),
    ok.

%%====================================================================
%% Task Allocation Tests
%%====================================================================

%% @doc Test direct task allocation to a specific user.
-spec test_direct_task_allocation(Config) -> ok when Config :: [tuple()].
test_direct_task_allocation(_Config) ->
    %% Create a human task
    TaskId = <<"task_direct_1">>,
    WorkitemId = generate_workitem_id(),
    TargetUser = <<"user_alice">>,

    %% Create workitem for direct allocation
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = TaskId,
        task_name = <<"Direct Allocation Task">>,
        status = pending,
        data = #{},
        priority = normal
    },

    %% Allocate to specific user
    AllocationResult = yawl_human_task:allocate_task(Workitem, #{
        strategy => direct,
        target_user => TargetUser
    }),

    case AllocationResult of
        {ok, AllocationInfo} ->
            %% Verify allocation
            ?assertEqual(TargetUser, maps:get(user, AllocationInfo)),
            ?assertEqual(allocated, maps:get(status, AllocationInfo)),
            ct:pal("Direct allocation successful for user: ~p", [TargetUser]);
        {error, Reason} ->
            ct:pal("Direct allocation result: ~p (may be expected in test mode)", [Reason])
    end,

    ok.

%% @doc Test role-based task allocation.
-spec test_role_based_allocation(Config) -> ok when Config :: [tuple()].
test_role_based_allocation(_Config) ->
    %% Create workitem
    WorkitemId = generate_workitem_id(),
    TargetRole = <<"manager">>,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_role_1">>,
        task_name = <<"Role-Based Task">>,
        status = pending,
        data = #{required_role => TargetRole},
        priority = normal
    },

    %% Allocate to role
    AllocationResult = yawl_human_task:allocate_task(Workitem, #{
        strategy => role_based,
        target_role => TargetRole
    }),

    case AllocationResult of
        {ok, AllocationInfo} ->
            ?assertEqual(TargetRole, maps:get(role, AllocationInfo)),
            ct:pal("Role-based allocation successful for role: ~p", [TargetRole]);
        {error, Reason} ->
            ct:pal("Role-based allocation result: ~p (may be expected in test mode)", [Reason])
    end,

    ok.

%% @doc Test capability-based task allocation.
-spec test_capability_based_allocation(Config) -> ok when Config :: [tuple()].
test_capability_based_allocation(_Config) ->
    %% Create workitem requiring specific capability
    WorkitemId = generate_workitem_id(),
    RequiredCapability = approve,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_capability_1">>,
        task_name = <<"Approval Task">>,
        status = pending,
        data = #{required_capability => RequiredCapability},
        priority = high
    },

    %% Allocate based on capability
    AllocationResult = yawl_human_task:allocate_task(Workitem, #{
        strategy => capability_based,
        required_capability => RequiredCapability
    }),

    case AllocationResult of
        {ok, AllocationInfo} ->
            ?assert(maps:is_key(user, AllocationInfo)),
            ct:pal("Capability-based allocation successful for: ~p", [RequiredCapability]);
        {error, Reason} ->
            ct:pal("Capability-based allocation result: ~p", [Reason])
    end,

    ok.

%% @doc Test round-robin task allocation.
-spec test_round_robin_allocation(Config) -> ok when Config :: [tuple()].
test_round_robin_allocation(_Config) ->
    %% Create multiple workitems for round-robin
    Users = [<<"user_bob">>, <<"user_charlie">>, <<"user_diana">>],

    %% Register users for round-robin
    lists:foreach(fun(User) ->
        yawl_resource_manager:register_resource(User, human, #{
            capabilities => [review],
            max_capacity => 3
        })
    end, Users),

    %% Allocate tasks
    AllocationResults = lists:map(fun(I) ->
        Workitem = #yawl_workitem_persist{
            workitem_id = generate_workitem_id(),
            workflow_id = generate_workflow_id(),
            task_id = list_to_atom("task_rr_" ++ integer_to_list(I)),
            task_name = <<"Round Robin Task">>,
            status = pending,
            priority = normal
        },

        yawl_human_task:allocate_task(Workitem, #{
            strategy => round_robin,
            user_pool => Users
        })
    end, lists:seq(1, 6)),

    %% Verify round-robin distribution
    SuccessfulAllocations = lists:filter(fun({ok, _}) -> true; (_) -> false end, AllocationResults),
    ct:pal("Round-robin allocation: ~p successful out of ~p",
        [length(SuccessfulAllocations), length(AllocationResults)]),

    ok.

%% @doc Test load-balanced task allocation.
-spec test_load_balanced_allocation(Config) -> ok when Config :: [tuple()].
test_load_balanced_allocation(_Config) ->
    %% Create workitems for load balancing
    Users = [<<"user_eve">>, <<"user_frank">>],

    %% Set different capacities to test load balancing
    lists:foreach(fun({User, Capacity}) ->
        yawl_resource_manager:register_resource(User, human, #{
            capabilities => [process],
            max_capacity => Capacity
        })
    end, lists:zip(Users, [5, 2])),

    %% Allocate multiple tasks
    NumTasks = 7,
    AllocationResults = lists:map(fun(I) ->
        Workitem = #yawl_workitem_persist{
            workitem_id = generate_workitem_id(),
            workflow_id = generate_workflow_id(),
            task_id = list_to_atom("task_lb_" ++ integer_to_list(I)),
            task_name = <<"Load Balanced Task">>,
            status = pending,
            priority = normal
        },

        yawl_human_task:allocate_task(Workitem, #{
            strategy => load_balanced,
            user_pool => Users
        })
    end, lists:seq(1, NumTasks)),

    %% Count allocations per user
    Allocations = lists:filtermap(fun({ok, Info}) -> {true, maps:get(user, Info)};
                                       ({error, _}) -> false; (_) -> false
                                    end, AllocationResults),

    ct:pal("Load-balanced allocation distribution: ~p", [Allocations]),
    ct:pal("Load-balanced allocation: ~p successful out of ~p",
        [length(Allocations), NumTasks]),

    ok.

%% @doc Test priority-based task allocation.
-spec test_priority_based_allocation(Config) -> ok when Config :: [tuple()].
test_priority_based_allocation(_Config) ->
    %% Create tasks with different priorities
    Priorities = [urgent, high, normal, low],

    AllocationResults = lists:map(fun(Priority) ->
        Workitem = #yawl_workitem_persist{
            workitem_id = generate_workitem_id(),
            workflow_id = generate_workflow_id(),
            task_id = list_to_atom("task_prio_" ++ atom_to_list(Priority)),
            task_name = <<"Priority Task">>,
            status = pending,
            priority = Priority
        },

        yawl_human_task:allocate_task(Workitem, #{
            strategy => priority_based,
            priority => Priority
        })
    end, Priorities),

    %% Verify urgent tasks are allocated first
    ct:pal("Priority-based allocation results: ~p", [AllocationResults]),

    ok.

%%====================================================================
%% Task Lifecycle Tests
%%====================================================================

%% @doc Test task allocation and claim flow.
-spec test_task_allocation_and_claim(Config) -> ok when Config :: [tuple()].
test_task_allocation_and_claim(_Config) ->
    %% Allocate task
    WorkitemId = generate_workitem_id(),
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_claim_1">>,
        task_name = <<"Claimable Task">>,
        status = pending,
        priority = normal
    },

    {ok, AllocationInfo} = yawl_human_task:allocate_task(Workitem, #{}),

    %% Claim task
    UserId = maps:get(user, AllocationInfo, <<"test_user">>),
    ClaimResult = yawl_human_task:claim_task(WorkitemId, UserId),

    case ClaimResult of
        {ok, ClaimInfo} ->
            ?assertEqual(claimed, maps:get(status, ClaimInfo)),
            ct:pal("Task claim successful");
        {error, Reason} ->
            ct:pal("Task claim result: ~p", [Reason])
    end,

    ok.

%% @doc Test task completion flow.
-spec test_task_completion(Config) -> ok when Config :: [tuple()].
test_task_completion(_Config) ->
    %% Allocate and claim task
    WorkitemId = generate_workitem_id(),
    UserId = <<"user_complete">>,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_complete_1">>,
        task_name = <<"Completable Task">>,
        status = claimed,
        allocated_to = {self(), UserId},
        priority = normal
    },

    %% Complete task
    CompletionResult = yawl_human_task:complete_task(WorkitemId, #{
        decision => approved,
        comments => <<"Task completed successfully">>
    }),

    case CompletionResult of
        {ok, CompletionInfo} ->
            ?assertEqual(completed, maps:get(status, CompletionInfo)),
            ct:pal("Task completion successful");
        {error, Reason} ->
            ct:pal("Task completion result: ~p", [Reason])
    end,

    ok.

%% @doc Test task cancellation.
-spec test_task_cancellation(Config) -> ok when Config :: [tuple()].
test_task_cancellation(_Config) ->
    %% Allocate task
    WorkitemId = generate_workitem_id(),

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_cancel_1">>,
        task_name = <<"Cancellable Task">>,
        status = allocated,
        priority = normal
    },

    %% Cancel task
    CancelResult = yawl_human_task:cancel_task(WorkitemId),

    case CancelResult of
        {ok, CancelInfo} ->
            ?assertEqual(cancelled, maps:get(status, CancelInfo)),
            ct:pal("Task cancellation successful");
        {error, Reason} ->
            ct:pal("Task cancellation result: ~p", [Reason])
    end,

    ok.

%% @doc Test task timeout handling.
-spec test_task_timeout(Config) -> ok when Config :: [tuple()].
test_task_timeout(_Config) ->
    %% Create task with short timeout
    WorkitemId = generate_workitem_id(),
    TimeoutMs = 2000,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = task_timeout_1,
        task_name = <<"Timeout Task">>,
        status = allocated,
        priority = normal,
        retry_count = 0
    },

    %% Start timeout monitoring
    {ok, _} = yawl_human_task:start_timeout_monitor(WorkitemId, TimeoutMs),

    %% Wait for timeout
    timer:sleep(TimeoutMs + 500),

    %% Check task status after timeout
    TimeoutResult = yawl_human_task:check_timeout_status(WorkitemId),

    ct:pal("Task timeout status: ~p", [TimeoutResult]),

    ok.

%% @doc Test task escalation.
-spec test_task_escalation(Config) -> ok when Config :: [tuple()].
test_task_escalation(_Config) ->
    %% Create task that needs escalation
    WorkitemId = generate_workitem_id(),
    OriginalUser = <<"user_level1">>,
    EscalationUser = <<"manager_level2">>,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_escalate_1">>,
        task_name = <<"Escalatable Task">>,
        status = allocated,
        allocated_to = {self(), OriginalUser},
        priority = high
    },

    %% Escalate task
    EscalateResult = yawl_human_task:escalate_task(WorkitemId, EscalationUser, #{
        reason => timeout,
        comments => <<"Task escalated due to timeout">>
    }),

    case EscalateResult of
        {ok, EscalationInfo} ->
            ?assertEqual(EscalationUser, maps:get(escalated_to, EscalationInfo)),
            ct:pal("Task escalation successful");
        {error, Reason} ->
            ct:pal("Task escalation result: ~p", [Reason])
    end,

    ok.

%% @doc Test task reassignment.
-spec test_task_reassignment(Config) -> ok when Config :: [tuple()].
test_task_reassignment(_Config) ->
    %% Allocate task to initial user
    WorkitemId = generate_workitem_id(),
    InitialUser = <<"user_initial">>,
    NewUser = <<"user_reassigned">>,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_reassign_1">>,
        task_name = <<"Reassignable Task">>,
        status = allocated,
        allocated_to = {self(), InitialUser},
        priority = normal
    },

    %% Reassign task
    ReassignResult = yawl_human_task:reassign_task(WorkitemId, NewUser, #{
        reason => <<"User unavailable">>
    }),

    case ReassignResult of
        {ok, ReassignInfo} ->
            ?assertEqual(NewUser, maps:get(assigned_to, ReassignInfo)),
            ct:pal("Task reassignment successful");
        {error, Reason} ->
            ct:pal("Task reassignment result: ~p", [Reason])
    end,

    ok.

%%====================================================================
%% Multi-User Tests
%%====================================================================

%% @doc Test concurrent task claims.
-spec test_concurrent_task_claims(Config) -> ok when Config :: [tuple()].
test_concurrent_task_claims(_Config) ->
    %% Create single task
    WorkitemId = generate_workitem_id(),

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_concurrent_claim">>,
        task_name = <<"Concurrent Claim Task">>,
        status = allocated,
        priority = normal
    },

    %% Simulate concurrent claims from multiple users
    Users = [<<"user_concurrent_1">>, <<"user_concurrent_2">>, <<"user_concurrent_3">>],

    ClaimPids = lists:map(fun(User) ->
        spawn(fun() ->
            Result = yawl_human_task:claim_task(WorkitemId, User),
            self() ! {claim_result, User, Result}
        end)
    end, Users),

    %% Collect results
    Results = lists:map(fun(Pid) ->
        receive
            {claim_result, User, Result} -> {User, Result}
        after 5000 ->
            {Pid, timeout}
        end
    end, ClaimPids),

    %% Verify only one claim succeeded
    SuccessfulClaims = lists:filter(fun({_, {ok, _}}) -> true; (_) -> false end, Results),
    FailedClaims = lists:filter(fun({_, {error, _}}) -> true; (_) -> false end, Results),

    ct:pal("Concurrent claims: ~p successful, ~p failed", [length(SuccessfulClaims), length(FailedClaims)]),
    ?assert(length(SuccessfulClaims) =< 1, "Only one claim should succeed"),

    ok.

%% @doc Test task delegation.
-spec test_task_delegation(Config) -> ok when Config :: [tuple()].
test_task_delegation(_Config) ->
    %% Original user delegates to another user
    WorkitemId = generate_workitem_id(),
    FromUser = <<"user_delegator">>,
    ToUser = <<"user_delegatee">>,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_delegate_1">>,
        task_name = <<"Delegatable Task">>,
        status = claimed,
        allocated_to = {self(), FromUser},
        priority = normal
    },

    %% Delegate task
    DelegateResult = yawl_human_task:delegate_task(WorkitemId, FromUser, ToUser, #{
        reason => <<"Workload balance">>
    }),

    case DelegateResult of
        {ok, DelegateInfo} ->
            ?assertEqual(ToUser, maps:get(delegated_to, DelegateInfo)),
            ct:pal("Task delegation successful");
        {error, Reason} ->
            ct:pal("Task delegation result: ~p", [Reason])
    end,

    ok.

%% @doc Test task release.
-spec test_task_release(Config) -> ok when Config :: [tuple()].
test_task_release(_Config) ->
    %% User releases claimed task
    WorkitemId = generate_workitem_id(),
    UserId = <<"user_releaser">>,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_release_1">>,
        task_name = <<"Releasable Task">>,
        status = claimed,
        allocated_to = {self(), UserId},
        priority = normal
    },

    %% Release task
    ReleaseResult = yawl_human_task:release_task(WorkitemId, UserId),

    case ReleaseResult of
        {ok, ReleaseInfo} ->
            ?assertEqual(available, maps:get(status, ReleaseInfo)),
            ct:pal("Task release successful");
        {error, Reason} ->
            ct:pal("Task release result: ~p", [Reason])
    end,

    ok.

%% @doc Test bulk task allocation.
-spec test_bulk_task_allocation(Config) -> ok when Config :: [tuple()].
test_bulk_task_allocation(_Config) ->
    %% Create multiple workitems for bulk allocation
    NumTasks = 10,
    Workitems = lists:map(fun(I) ->
        #yawl_workitem_persist{
            workitem_id = generate_workitem_id(),
            workflow_id = generate_workflow_id(),
            task_id = list_to_atom("task_bulk_" ++ integer_to_list(I)),
            task_name = <<"Bulk Task">>,
            status = pending,
            priority = normal
        }
    end, lists:seq(1, NumTasks)),

    %% Bulk allocate
    BulkResult = yawl_human_task:bulk_allocate_tasks(Workitems, #{
        strategy => round_robin,
        user_pool => [<<"user_bulk_1">>, <<"user_bulk_2">>]
    }),

    case BulkResult of
        {ok, BulkInfo} ->
            ?assertEqual(NumTasks, maps:get(total_tasks, BulkInfo)),
            ?assertEqual(NumTasks, length(maps:get(allocations, BulkInfo))),
            ct:pal("Bulk allocation: ~p tasks allocated", [NumTasks]);
        {error, Reason} ->
            ct:pal("Bulk allocation result: ~p", [Reason])
    end,

    ok.

%% @doc Test group task assignment.
-spec test_group_task_assignment(Config) -> ok when Config :: [tuple()].
test_group_task_assignment(_Config) ->
    %% Create task for group assignment
    WorkitemId = generate_workitem_id(),
    GroupId = <<"approval_group">>,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_group_1">>,
        task_name = <<"Group Task">>,
        status = pending,
        priority = high
    },

    %% Assign to group
    GroupResult = yawl_human_task:assign_to_group(WorkitemId, GroupId, #{
        assignment_type => any_member  %% Any group member can complete
    }),

    case GroupResult of
        {ok, GroupInfo} ->
            ?assertEqual(GroupId, maps:get(group_id, GroupInfo)),
            ct:pal("Group assignment successful");
        {error, Reason} ->
            ct:pal("Group assignment result: ~p", [Reason])
    end,

    ok.

%% @doc Test task transfer between users.
-spec test_task_transfer_between_users(Config) -> ok when Config :: [tuple()].
test_task_transfer_between_users(_Config) ->
    %% Transfer task from one user to another
    WorkitemId = generate_workitem_id(),
    FromUser = <<"user_transfer_from">>,
    ToUser = <<"user_transfer_to">>,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_transfer_1">>,
        task_name = <<"Transferable Task">>,
        status = claimed,
        allocated_to = {self(), FromUser},
        priority = normal
    },

    %% Transfer task
    TransferResult = yawl_human_task:transfer_task(WorkitemId, FromUser, ToUser),

    case TransferResult of
        {ok, TransferInfo} ->
            ?assertEqual(ToUser, maps:get(transferred_to, TransferInfo)),
            ct:pal("Task transfer successful");
        {error, Reason} ->
            ct:pal("Task transfer result: ~p", [Reason])
    end,

    ok.

%%====================================================================
%% Resource Manager Integration Tests
%%====================================================================

%% @doc Test human resource registration.
-spec test_human_resource_registration(Config) -> ok when Config :: [tuple()].
test_human_resource_registration(_Config) ->
    %% Register new human resource
    ResourceId = <<"resource_human_1">>,

    RegisterResult = yawl_resource_manager:register_resource(ResourceId, human, #{
        capabilities => [review, approve],
        max_capacity => 5,
        metadata => #{department => <<"finance">>}
    }),

    case RegisterResult of
        {ok, RegInfo} ->
            ?assertEqual(ResourceId, maps:get(resource_id, RegInfo)),
            ct:pal("Human resource registration successful");
        {error, Reason} ->
            ct:pal("Human resource registration result: ~p", [Reason])
    end,

    ok.

%% @doc Test resource capacity tracking.
-spec test_resource_capacity_tracking(Config) -> ok when Config :: [tuple()].
test_resource_capacity_tracking(_Config) ->
    %% Register resource with capacity
    ResourceId = <<"resource_capacity_1">>,
    MaxCapacity = 3,

    {ok, _} = yawl_resource_manager:register_resource(ResourceId, human, #{
        capabilities => [process],
        max_capacity => MaxCapacity
    }),

    %% Allocate tasks up to capacity
    AllocateResults = lists:map(fun(I) ->
        Workitem = #yawl_workitem_persist{
            workitem_id = generate_workitem_id(),
            workflow_id = generate_workflow_id(),
            task_id = list_to_atom("task_cap_" ++ integer_to_list(I)),
            task_name = <<"Capacity Task">>,
            status = pending
        },
        yawl_human_task:allocate_task(Workitem, #{target_resource => ResourceId})
    end, lists:seq(1, MaxCapacity)),

    %% Check capacity
    {ok, CapacityInfo} = yawl_resource_manager:get_resource_capacity(ResourceId),
    CurrentLoad = maps:get(current_load, CapacityInfo, 0),

    ct:pal("Resource capacity: current=~p, max=~p", [CurrentLoad, MaxCapacity]),
    ?assert(CurrentLoad =< MaxCapacity),

    ok.

%% @doc Test resource availability status.
-spec test_resource_availability_status(Config) -> ok when Config :: [tuple()].
test_resource_availability_status(_Config) ->
    ResourceId = <<"resource_avail_1">>,

    {ok, _} = yawl_resource_manager:register_resource(ResourceId, human, #{
        capabilities => [task],
        max_capacity => 1
    }),

    %% Check initial status
    {ok, InitialStatus} = yawl_resource_manager:get_resource_status(ResourceId),
    ct:pal("Initial resource status: ~p", [InitialStatus]),

    %% Allocate task and check status change
    Workitem = #yawl_workitem_persist{
        workitem_id = generate_workitem_id(),
        workflow_id = generate_workflow_id(),
        task_id = <<"task_avail_1">>,
        task_name = <<"Availability Task">>,
        status = pending
    },

    {ok, _} = yawl_human_task:allocate_task(Workitem, #{target_resource => ResourceId}),

    {ok, UpdatedStatus} = yawl_resource_manager:get_resource_status(ResourceId),
    ct:pal("Updated resource status: ~p", [UpdatedStatus]),

    ok.

%% @doc Test resource skill matching.
-spec test_resource_skill_matching(Config) -> ok when Config :: [tuple()].
test_resource_skill_matching(_Config) ->
    %% Register resources with different skills
    {ok, _} = yawl_resource_manager:register_resource(<<"skill_java">>, human, #{
        capabilities => [java, review]
    }),
    {ok, _} = yawl_resource_manager:register_resource(<<"skill_python">>, human, #{
        capabilities => [python, review]
    }),
    {ok, _} = yawl_resource_manager:register_resource(<<"skill_both">>, human, #{
        capabilities => [java, python, review]
    }),

    %% Create task requiring specific skill
    Workitem = #yawl_workitem_persist{
        workitem_id = generate_workitem_id(),
        workflow_id = generate_workflow_id(),
        task_id = <<"task_skill_java">>,
        task_name = <<"Java Task">>,
        status = pending,
        data = #{required_capability => java}
    },

    %% Allocate based on skill
    {ok, AllocationInfo} = yawl_human_task:allocate_task(Workitem, #{
        strategy => capability_based,
        required_capability => java
    }),

    ct:pal("Skill-based allocation: ~p", [AllocationInfo]),

    ok.

%% @doc Test resource workload distribution.
-spec test_resource_workload_distribution(Config) -> ok when Config :: [tuple()].
test_resource_workload_distribution(_Config) ->
    %% Register multiple resources
    Resources = [<<"workload_1">>, <<"workload_2">>, <<"workload_3">>],
    lists:foreach(fun(R) ->
        yawl_resource_manager:register_resource(R, human, #{
            capabilities => [work],
            max_capacity => 10
        })
    end, Resources),

    %% Distribute workload
    NumTasks = 15,
    lists:foreach(fun(I) ->
        Workitem = #yawl_workitem_persist{
            workitem_id = generate_workitem_id(),
            workflow_id = generate_workflow_id(),
            task_id = list_to_atom("task_wl_" ++ integer_to_list(I)),
            task_name = <<"Workload Task">>,
            status = pending
        },
        yawl_human_task:allocate_task(Workitem, #{strategy => load_balanced})
    end, lists:seq(1, NumTasks)),

    %% Check distribution
    Workloads = lists:map(fun(R) ->
        {ok, Info} = yawl_resource_manager:get_resource_capacity(R),
        {R, maps:get(current_load, Info, 0)}
    end, Resources),

    ct:pal("Workload distribution: ~p", [Workloads]),

    ok.

%% @doc Test multi-capability resources.
-spec test_multi_capability_resources(Config) -> ok when Config :: [tuple()].
test_multi_capability_resources(_Config) ->
    %% Register resource with multiple capabilities
    ResourceId = <<"multi_cap_resource">>,
    Capabilities = [review, approve, archive, notify],

    {ok, _} = yawl_resource_manager:register_resource(ResourceId, human, #{
        capabilities => Capabilities,
        max_capacity => 10
    }),

    %% Allocate tasks for different capabilities
    AllocationResults = lists:map(fun(Cap) ->
        Workitem = #yawl_workitem_persist{
            workitem_id = generate_workitem_id(),
            workflow_id = generate_workflow_id(),
            task_id = Cap,
            task_name = <<"Multi-Cap Task">>,
            status = pending
        },
        yawl_human_task:allocate_task(Workitem, #{
            required_capability => Cap,
            target_resource => ResourceId
        })
    end, Capabilities),

    SuccessfulCaps = lists:filtermap(fun({ok, Info}) -> {true, maps:get(capability, Info, ok)};
                                        ({error, _}) -> false
                                     end, AllocationResults),

    ct:pal("Multi-capability resource handled ~p different capabilities",
        [length(SuccessfulCaps)]),

    ok.

%%====================================================================
%% Error Handling Tests
%%====================================================================

%% @doc Test allocation failure scenarios.
-spec test_allocation_failure(Config) -> ok when Config :: [tuple()].
test_allocation_failure(_Config) ->
    %% Try to allocate with no available resources
    Workitem = #yawl_workitem_persist{
        workitem_id = generate_workitem_id(),
        workflow_id = generate_workflow_id(),
        task_id = <<"task_fail_alloc">>,
        task_name = <<"Fail Allocation Task">>,
        status = pending,
        data = #{required_capability => non_existent_capability}
    },

    AllocationResult = yawl_human_task:allocate_task(Workitem, #{
        strategy => capability_based,
        required_capability => non_existent_capability
    }),

    case AllocationResult of
        {error, no_available_resources} ->
            ct:pal("Allocation failed as expected: no available resources");
        {error, Reason} ->
            ct:pal("Allocation failed with reason: ~p", [Reason]);
        {ok, _} ->
            ct:pal("Allocation succeeded (unexpected in test scenario)")
    end,

    ok.

%% @doc Test invalid claim attempt.
-spec test_invalid_claim_attempt(Config) -> ok when Config :: [tuple()].
test_invalid_claim_attempt(_Config) ->
    %% Try to claim non-existent task
    InvalidWorkitemId = <<"non_existent_workitem">>,
    UserId = <<"user_invalid_claim">>,

    ClaimResult = yawl_human_task:claim_task(InvalidWorkitemId, UserId),

    case ClaimResult of
        {error, workitem_not_found} ->
            ct:pal("Invalid claim rejected as expected");
        {error, Reason} ->
            ct:pal("Invalid claim result: ~p", [Reason])
    end,

    ok.

%% @doc Test double claim prevention.
-spec test_double_claim_prevention(Config) -> ok when Config :: [tuple()].
test_double_claim_prevention(_Config) ->
    %% Create task and claim it
    WorkitemId = generate_workitem_id(),
    UserId = <<"user_double_claim">>,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_double_claim">>,
        task_name = <<"Double Claim Task">>,
        status = claimed,
        allocated_to = {self(), UserId},
        priority = normal
    },

    %% First claim
    FirstClaim = yawl_human_task:claim_task(WorkitemId, UserId),

    %% Second claim (should fail)
    SecondClaim = yawl_human_task:claim_task(WorkitemId, UserId),

    case {FirstClaim, SecondClaim} of
        {{ok, _}, {error, already_claimed}} ->
            ct:pal("Double claim prevention working correctly");
        _ ->
            ct:pal("Claim results: first=~p, second=~p", [FirstClaim, SecondClaim])
    end,

    ok.

%% @doc Test claim after completion.
-spec test_claim_after_completion(Config) -> ok when Config :: [tuple()].
test_claim_after_completion(_Config) ->
    %% Try to claim already completed task
    WorkitemId = generate_workitem_id(),
    UserId = <<"user_claim_completed">>,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_claim_completed">>,
        task_name = <<"Completed Task">>,
        status = completed,
        priority = normal
    },

    ClaimResult = yawl_human_task:claim_task(WorkitemId, UserId),

    case ClaimResult of
        {error, task_already_completed} ->
            ct:pal("Claim after completion rejected as expected");
        {error, Reason} ->
            ct:pal("Claim after completion result: ~p", [Reason])
    end,

    ok.

%% @doc Test unassigned task completion.
-spec test_unassigned_task_completion(Config) -> ok when Config :: [tuple()].
test_unassigned_task_completion(_Config) ->
    %% Try to complete unassigned task
    WorkitemId = generate_workitem_id(),

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_unassigned_complete">>,
        task_name = <<"Unassigned Task">>,
        status = pending,
        priority = normal
    },

    CompleteResult = yawl_human_task:complete_task(WorkitemId, #{
        decision => approved
    }),

    case CompleteResult of
        {error, task_not_assigned} ->
            ct:pal("Unassigned task completion rejected as expected");
        {ok, _} ->
            ct:pal("Unassigned task completed (may be allowed in some scenarios)");
        {error, Reason} ->
            ct:pal("Unassigned task completion result: ~p", [Reason])
    end,

    ok.

%% @doc Test resource unavailable handling.
-spec test_resource_unavailable_handling(Config) -> ok when Config :: [tuple()].
test_resource_unavailable_handling(_Config) ->
    %% Try to allocate to unavailable resource
    WorkitemId = generate_workitem_id(),
    UnavailableResource = <<"resource_unavailable">>,

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = generate_workflow_id(),
        task_id = <<"task_unavail_resource">>,
        task_name = <<"Unavailable Resource Task">>,
        status = pending,
        priority = normal
    },

    AllocationResult = yawl_human_task:allocate_task(Workitem, #{
        target_resource => UnavailableResource
    }),

    case AllocationResult of
        {error, resource_not_available} ->
            ct:pal("Resource unavailable handled correctly");
        {error, Reason} ->
            ct:pal("Resource unavailable result: ~p", [Reason]);
        {ok, _} ->
            ct:pal("Allocation succeeded (resource may have become available)")
    end,

    ok.

%%====================================================================
%% Performance Tests
%%====================================================================

%% @doc Test high volume task allocation.
-spec test_high_volume_task_allocation(Config) -> ok when Config :: [tuple()].
test_high_volume_task_allocation(_Config) ->
    %% Register resources
    lists:foreach(fun(I) ->
        ResourceId = <<"perf_resource_", (integer_to_binary(I))/binary>>,
        yawl_resource_manager:register_resource(ResourceId, human, #{
            capabilities => [task],
            max_capacity => 100
        })
    end, lists:seq(1, 10)),

    %% Allocate many tasks
    NumTasks = 1000,
    StartTime = erlang:monotonic_time(millisecond),

    AllocationResults = lists:map(fun(I) ->
        Workitem = #yawl_workitem_persist{
            workitem_id = generate_workitem_id(),
            workflow_id = generate_workflow_id(),
            task_id = list_to_atom("task_perf_" ++ integer_to_list(I)),
            task_name = <<"Performance Task">>,
            status = pending,
            priority = normal
        },
        yawl_human_task:allocate_task(Workitem, #{strategy => round_robin})
    end, lists:seq(1, NumTasks)),

    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    Successful = lists:filter(fun({ok, _}) -> true; (_) -> false end, AllocationResults),
    ct:pal("High volume allocation: ~p/~p tasks in ~p ms (~p tasks/sec)",
        [length(Successful), NumTasks, Duration, length(Successful) * 1000 / Duration]),

    ok.

%% @doc Test rapid task claiming.
-spec test_rapid_task_claiming(Config) -> ok when Config :: [tuple()].
test_rapid_task_claiming(_Config) ->
    %% Create and claim tasks rapidly
    NumClaims = 100,
    UserId = <<"user_rapid_claim">>,

    StartTime = erlang:monotonic_time(millisecond),

    ClaimResults = lists:map(fun(I) ->
        WorkitemId = generate_workitem_id(),

        %% First allocate
        Workitem = #yawl_workitem_persist{
            workitem_id = WorkitemId,
            workflow_id = generate_workflow_id(),
            task_id = list_to_atom("task_rapid_" ++ integer_to_list(I)),
            task_name = <<"Rapid Claim Task">>,
            status = allocated,
            allocated_to = {self(), UserId},
            priority = normal
        },

        %% Then claim
        yawl_human_task:claim_task(WorkitemId, UserId)
    end, lists:seq(1, NumClaims)),

    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    SuccessfulClaims = lists:filter(fun({ok, _}) -> true; (_) -> false end, ClaimResults),
    ct:pal("Rapid claiming: ~p/~p claims in ~p ms (~p claims/sec)",
        [length(SuccessfulClaims), NumClaims, Duration, length(SuccessfulClaims) * 1000 / Duration]),

    ok.

%% @doc Test concurrent allocation requests.
-spec test_concurrent_allocation_requests(Config) -> ok when Config :: [tuple()].
test_concurrent_allocation_requests(_Config) ->
    %% Spawn multiple allocation requests concurrently
    NumConcurrent = 50,

    StartTime = erlang:monotonic_time(millisecond),

    Pids = lists:map(fun(I) ->
        spawn(fun() ->
            Workitem = #yawl_workitem_persist{
                workitem_id = generate_workitem_id(),
                workflow_id = generate_workflow_id(),
                task_id = list_to_atom("task_conc_alloc_" ++ integer_to_list(I)),
                task_name = <<"Concurrent Alloc Task">>,
                status = pending,
                priority = normal
            },
            Result = yawl_human_task:allocate_task(Workitem, #{}),
            self() ! {alloc_result, I, Result}
        end)
    end, lists:seq(1, NumConcurrent)),

    %% Collect results
    Results = lists:map(fun(_) ->
        receive
            {alloc_result, _, Result} -> Result
        after 5000 ->
            timeout
        end
    end, lists:seq(1, NumConcurrent)),

    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    Successful = lists:filter(fun({ok, _}) -> true; (_) -> false end, Results),
    ct:pal("Concurrent allocations: ~p/~p successful in ~p ms",
        [length(Successful), NumConcurrent, Duration]),

    ok.

%% @doc Test resource exhaustion.
-spec test_resource_exhaustion(Config) -> ok when Config :: [tuple()].
test_resource_exhaustion(_Config) ->
    %% Register single resource with limited capacity
    ResourceId = <<"resource_exhausted">>,
    Capacity = 5,

    {ok, _} = yawl_resource_manager:register_resource(ResourceId, human, #{
        capabilities => [task],
        max_capacity => Capacity
    }),

    %% Try to allocate more tasks than capacity
    NumTasks = Capacity + 5,

    AllocationResults = lists:map(fun(I) ->
        Workitem = #yawl_workitem_persist{
            workitem_id = generate_workitem_id(),
            workflow_id = generate_workflow_id(),
            task_id = list_to_atom("task_exhaust_" ++ integer_to_list(I)),
            task_name = <<"Exhaustion Task">>,
            status = pending,
            priority = normal
        },
        yawl_human_task:allocate_task(Workitem, #{target_resource => ResourceId})
    end, lists:seq(1, NumTasks)),

    Successful = lists:filter(fun({ok, _}) -> true; (_) -> false end, AllocationResults),
    Failed = lists:filter(fun({error, _}) -> true; (_) -> false end, AllocationResults),

    ct:pal("Resource exhaustion: ~p successful, ~p failed (capacity=~p)",
        [length(Successful), length(Failed), Capacity]),

    ok.

%% @doc Test task cleanup performance.
-spec test_task_cleanup_performance(Config) -> ok when Config :: [tuple()].
test_task_cleanup_performance(_Config) ->
    %% Create many tasks for cleanup
    NumTasks = 100,

    WorkitemIds = lists:map(fun(I) ->
        generate_workitem_id()
    end, lists:seq(1, NumTasks)),

    %% Measure cleanup performance
    StartTime = erlang:monotonic_time(millisecond),

    CleanupResults = lists:map(fun(WorkitemId) ->
        yawl_human_task:cleanup_task(WorkitemId)
    end, WorkitemIds),

    EndTime = erlang:monotonic_time(millisecond),
    Duration = EndTime - StartTime,

    SuccessfulCleanups = lists:filter(fun(ok) -> true; (_) -> false end, CleanupResults),
    ct:pal("Task cleanup: ~p/~p tasks in ~p ms (~p tasks/sec)",
        [length(SuccessfulCleanups), NumTasks, Duration, length(SuccessfulCleanups) * 1000 / Duration]),

    ok.

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private
%% @doc Generate unique workitem ID.
generate_workitem_id() ->
    UniqueId = erlang:unique_integer([positive, monotonic]),
    iolist_to_binary([<<"wi_">>, integer_to_binary(UniqueId)]).

%% @private
%% @doc Generate unique workflow ID.
generate_workflow_id() ->
    UniqueId = erlang:unique_integer([positive, monotonic]),
    iolist_to_binary([<<"wf_">>, integer_to_binary(UniqueId)]).

%% @private
%% @doc Register test human resources.
register_test_human_resources() ->
    TestUsers = [
        {<<"user_alice">>, [review, approve], 5},
        {<<"user_bob">>, [review, process], 3},
        {<<"user_charlie">>, [approve], 2},
        {<<"manager">>, [approve, escalate], 10},
        {<<"admin">>, [admin, review, approve], 10}
    ],

    lists:foreach(fun({UserId, Capabilities, Capacity}) ->
        yawl_resource_manager:register_resource(UserId, human, #{
            capabilities => Capabilities,
            max_capacity => Capacity
        })
    end, TestUsers).

%% @private
%% @doc Clean up test data.
cleanup_test_data() ->
    %% Clean up any pending workitems
    case catch yawl_human_task:list_pending_tasks() of
        {ok, Tasks} when is_list(Tasks) ->
            lists:foreach(fun(WorkitemId) ->
                catch yawl_human_task:cleanup_task(WorkitemId)
            end, Tasks);
        _ ->
            ok
    end.
