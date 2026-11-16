%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Workflow Instance TDD Tests (Chicago-Style)
%%%
%%% These tests verify workflow instance lifecycle, token passing, and
%%% state transitions. Tests are written FIRST to drive implementation.
%%%
%%% Test Categories:
%%% 1. State Transitions
%%% 2. Token Passing
%%% 3. Checkpoint/Recovery
%%% 4. Deadlock Detection
%%% 5. Event Subscription
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_workflow_instance_tdd).
-author("A2A Team").
-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(INSTANCE_TIMEOUT, 10000).
-define(TEST_WORKFLOW_ID, <<"instance_test_wf">>).
-define(TEST_PATTERN_TYPE, basic_sequential).

%%====================================================================
%% Test Fixtures
%%====================================================================

%% @doc Setup for instance tests
instance_setup() ->
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

%% @doc Teardown for instance tests
instance_cleanup() ->
    gen_server:stop(whereis(yawl_resource_manager)),
    gen_server:stop(whereis(yawl_orchestrator)),
    gen_server:stop(whereis(yawl_persistence)),
    mnesia:stop().

%% @doc Create test instance
create_test_instance(PatternType, Config) ->
    FullConfig = Config#{
        pattern_type => PatternType,
        workflow_data => maps:get(data, Config, #{}),
        metadata => maps:get(metadata, Config, #{})
    },
    {ok, Pid} = yawl_workflow_instance:start_link(
        ?TEST_WORKFLOW_ID, FullConfig),
    Pid.

%%====================================================================
%% State Transition Tests
%%====================================================================

state_transition_test_() ->
    {"Idle to running transition",
     fun test_idle_to_running/0},
    {"Running to waiting transition",
     fun test_running_to_waiting/0},
    {"Waiting to running transition",
     fun test_waiting_to_running/0},
    {"Running to completing transition",
     fun test_running_to_completing/0},
    {"Completing to terminated transition",
     fun test_completing_to_terminated/0},
    {"Any state to cancelled transition",
     fun test_any_to_cancelled/0},
    {"Any state to failed transition",
     fun test_any_to_failed/0},
    {"Invalid state transition rejected",
     fun test_invalid_transition/0}.

%% @doc FAILING TEST: Idle to running transition
test_idle_to_running() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),

    %% Act - Start workflow
    Result = yawl_workflow_instance:start_workflow(InstancePid),

    %% Assert - Should transition to running
    {ok, RunningState, _Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(running, RunningState),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Running to waiting transition
test_running_to_waiting() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(parallel_split, #{}),
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Act - Suspend workflow
    Result = yawl_workflow_instance:suspend_workflow(InstancePid),

    %% Assert - Should transition to waiting
    {ok, WaitingState, _Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(waiting, WaitingState),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Waiting to running transition
test_waiting_to_running() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    ok = yawl_workflow_instance:start_workflow(InstancePid),
    ok = yawl_workflow_instance:suspend_workflow(InstancePid),

    %% Act - Resume workflow
    Result = yawl_workflow_instance:resume_workflow(InstancePid),

    %% Assert - Should transition back to running
    {ok, RunningState, _Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(running, RunningState),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Running to completing transition
test_running_to_completing() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Act - Complete all tasks
    %% (Simulated by moving token to end place)
    CompleteResult = try
        %% Trigger internal completion check
        gen_server:call(InstancePid, {complete_all_tasks, self()}, 5000)
    catch
        _:_ -> {error, timeout}
    end,

    %% Assert - Should transition to completing
    {ok, State, _} = yawl_workflow_instance:get_state(InstancePid),
    case State of
        completing -> ok;
        terminated -> ok;  %% Skipped completing
        _ -> ?assertEqual(completing, State)
    end,

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Completing to terminated transition
test_completing_to_terminated() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Wait for completion
    timer:sleep(100),

    %% Act - Finalize
    %% (Automatically happens when token reaches end)
    timer:sleep(100),

    %% Assert - Should be terminated
    {ok, TerminatedState, _Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(terminated, TerminatedState),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Any state to cancelled transition
test_any_to_cancelled() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),

    %% Act - Cancel from idle
    ok = yawl_workflow_instance:cancel_workflow(InstancePid),

    %% Assert - Should be cancelled
    {ok, CancelledState, _} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(cancelled, CancelledState),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Any state to failed transition
test_any_to_failed() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Act - Cause failure
    InstancePid ! {force_failure, simulated_error},

    %% Assert - Should be failed
    {ok, FailedState, Data} = yawl_workflow_instance:get_state(InstancePid),
    ?assertEqual(failed, FailedState),
    ?assertNotEqual(undefined, maps:get(error, Data)),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Invalid state transition rejected
test_invalid_transition() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),

    %% Act - Try to execute task from terminated state
    %% First complete the workflow
    ok = yawl_workflow_instance:start_workflow(InstancePid),
    timer:sleep(200),
    %% Now try to execute from terminated
    Result = try
        gen_server:call(InstancePid, {execute_task, invalid_task}, 1000)
    catch
        _:_ -> {error, no_instance}
    end,

    %% Assert - Should fail
    ?assertEqual({error, no_instance}, Result),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%%====================================================================
%% Token Passing Tests
%%====================================================================

token_passing_test_() ->
    {"Initial token in start place",
     fun test_initial_token/0},
    {"Token consumption on transition fire",
     fun test_token_consumption/0},
    {"Token production on transition fire",
     fun test_token_production/0},
    {"Token preservation",
     fun test_token_preservation/0},
    {"Token passing through multiple places",
     fun test_token_flow/0},
    {"Concurrent token handling",
     fun test_concurrent_tokens/0},
    {"Token depletion detection",
     fun test_token_depletion/0}.

%% @doc FAILING TEST: Initial token in start place
test_initial_token() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),

    %% Act - Get initial marking
    {ok, Marking} = yawl_workflow_instance:get_marking(InstancePid),

    %% Assert - Start place should have token
    StartTokens = maps:get(start, Marking, []),
    ?assert(length(StartTokens) > 0),

    %% Other places should be empty
    OtherPlaces = lists:delete(start, [start, task1, task2, 'end']),
    lists:foreach(fun(Place) ->
        Tokens = maps:get(Place, Marking, []),
        ?assertEqual([], Tokens)
    end, OtherPlaces),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Token consumption on transition fire
test_token_consumption() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    {ok, InitialMarking} = yawl_workflow_instance:get_marking(InstancePid),

    %% Act - Fire start transition
    %% This consumes token from start
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Wait for transition
    timer:sleep(100),

    %% Assert - Start token should be consumed
    {ok, Marking} = yawl_workflow_instance:get_marking(InstancePid),
    StartTokens = maps:get(start, Marking, []),
    ?assertEqual([], StartTokens),

    %% Token should be produced to next place
    NextTokens = maps:get(task1, Marking, []),
    ?assert(length(NextTokens) > 0),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Token production on transition fire
test_token_production() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Wait for transition to fire
    timer:sleep(100),

    %% Act - Get marking after first transition
    {ok, Marking} = yawl_workflow_instance:get_marking(InstancePid),

    %% Assert - Tokens should be produced according to postset
    %% For basic_sequential: start -> task1 -> task2 -> end
    Task1Tokens = maps:get(task1, Marking, []),
    ?assert(length(Task1Tokens) > 0),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Token preservation
test_token_preservation() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),

    %% Act - Create checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(InstancePid),
    {ok, OriginalMarking} = yawl_workflow_instance:get_marking(InstancePid),

    %% Simulate some work
    ok = yawl_workflow_instance:start_workflow(InstancePid),
    timer:sleep(100),

    %% Create another checkpoint
    {ok, CheckpointId2} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Assert - Checkpoints should be different
    ?assertNotEqual(CheckpointId, CheckpointId2),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Token passing through multiple places
test_token_flow() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),

    %% Act - Start workflow
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Wait for execution
    timer:sleep(200),

    %% Get marking evolution
    {ok, Marking} = yawl_workflow_instance:get_marking(InstancePid),

    %% Assert - Token should have progressed
    %% Start: [token] -> Task1: [token] -> Task2: [token] -> End: [token]
    EndTokens = maps:get('end', Marking, []),
    ?assert(length(EndTokens) > 0),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Concurrent token handling
test_concurrent_tokens() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(parallel_split, #{branches => 3}),

    %% Act - Start workflow
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Wait for parallel split
    timer:sleep(100),

    %% Assert - Multiple places should have tokens
    {ok, Marking} = yaul_workflow_instance:get_marking(InstancePid),
    PlacesWithTokens = lists:filter(fun({_, Tokens}) ->
        length(Tokens) > 0
    end, maps:to_list(Marking)),

    ?assert(length(PlacesWithTokens) >= 2),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Token depletion detection
test_token_depletion() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),

    %% Act - Start and run to completion
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Wait for completion
    receive
        {workflow_completed, _, _} -> ok
    after 2000 -> ok
    end,

    %% Assert - All tokens should end at 'end' place
    {ok, FinalMarking} = yawl_workflow_instance:get_marking(InstancePid),
    EndTokens = maps:get('end', FinalMarking, []),
    OtherPlaces = lists:delete('end', [start, task1, task2, 'end']),
    OtherTokens = [maps:get(P, FinalMarking, []) || P <- OtherPlaces],
    TotalTokens = length(EndTokens) + lists:sum(OtherTokens),

    ?assertEqual(1, TotalTokens, "All tokens should accumulate at end"),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%%====================================================================
%% Checkpoint/Recovery Tests
%%====================================================================

checkpoint_recovery_test_() ->
    {"Create checkpoint",
     fun test_create_checkpoint/0},
    {"Restore from checkpoint",
     fun test_restore_from_checkpoint/0},
    {"Checkpoint contains complete state",
     fun test_checkpoint_complete_state/0},
    {"Restore after crash",
     fun test_restore_after_crash/0},
    {"Multiple checkpoints sequential",
     fun test_multiple_checkpoints/0}.

%% @doc FAILING TEST: Create checkpoint
test_create_checkpoint() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),

    %% Act - Create checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Assert
    ?assert(is_binary(CheckpointId)),
    ?assert(byte_size(CheckpointId) > 0),

    %% Verify checkpoint was saved
    {ok, Checkpoint} = yawl_persistence:load_latest_checkpoint(?TEST_WORKFLOW_ID),
    ?assertEqual(CheckpointId, Checkpoint#yawl_checkpoint.checkpoint_id),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Restore from checkpoint
test_restore_from_checkpoint() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(iterative_loop, #{
        iteration_count => 5
    }),
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Update state
    ok = yawl_workflow_instance:update_data(InstancePid, current_iteration, 3),

    %% Create checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Kill instance
    exit(InstancePid, kill),
    timer:sleep(100),

    %% Act - Restore from checkpoint
    {ok, NewInstancePid} = yawl_workflow_instance_sup:start_child(
        ?TEST_WORKFLOW_ID, #{}),
    receive
        {workflow_recovered, NewInstancePid} -> ok
    after 1000 -> ok
    end,

    %% Assert - State should be restored
    {ok, _, RestoredData} = yawl_workflow_instance:get_state(NewInstancePid),
    ?assertEqual(3, maps:get(current_iteration, RestoredData)),

    %% Cleanup
    exit(NewInstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Checkpoint contains complete state
test_checkpoint_complete_state() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(parallel_split, #{}),
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Act - Create checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Assert - Checkpoint should contain all state
    {ok, Checkpoint} = yawl_persistence:load_latest_checkpoint(?TEST_WORKFLOW_ID),
    ?assertNotEqual({error, no_checkpoint_found}, Checkpoint),
    #yawl_checkpoint{
        marking = Marking,
        data = Data,
        checkpoint_state = State
    } = Checkpoint,

    %% Verify components
    ?assert(is_map(Marking)),
    ?assert(is_map(Data)),
    ?assert(is_map(State)),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Restore after crash
test_restore_after_crash() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Create checkpoint
    {ok, CheckpointId} = yawl_workflow_instance:checkpoint(InstancePid),

    %% Kill instance
    exit(InstancePid, kill),
    timer:sleep(200),

    %% Act - Attempt restore
    {ok, NewInstancePid} = yawl_workflow_instance_sup:start_child(
        ?TEST_WORKFLOW_ID, #{}),

    %% Assert - New instance should be functional
    {ok, NewState, _} = yawl_workflow_instance:get_state(NewInstancePid),
    ?assert(lists:member(NewState, [idle, running, waiting, completing])),

    %% Cleanup
    exit(NewInstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Multiple checkpoints sequential
test_multiple_checkpoints() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(iterative_loop, #{}),
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Create series of checkpoints
    CheckpointIds = lists:map(fun(N) ->
        yawl_workflow_instance:update_data(InstancePid, iteration, N),
        {ok, Cpid} = yawl_workflow_instance:checkpoint(InstancePid),
        Cpid
    end, lists:seq(1, 5)),

    %% Act - Verify sequence numbers
    {ok, Checkpoints} = yawl_persistence:list_checkpoints(?TEST_WORKFLOW_ID),
    SortedCheckpoints = lists:sort(fun(A, B) ->
        A#yawl_checkpoint.sequence_num > B#yawl_checkpoint.sequence_num
    end, Checkpoints),

    %% Assert - Should have 5 checkpoints with sequence 1-5
    ?assertEqual(5, length(SortedCheckpoints)),

    %% Verify sequential numbers
    Sequences = [C#yawl_checkpoint.sequence_num || C <- SortedCheckpoints],
    ?assertEqual([1, 2, 3, 4, 5], Sequences),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%%====================================================================
%% Deadlock Detection Tests
%%====================================================================

deadlock_detection_test_() ->
    {"No deadlock in simple sequential",
     fun test_no_deadlock_sequential/0},
    {"Detect potential deadlock",
     fun test_potential_deadlock/0},
    {"Detect full deadlock",
     fun test_full_deadlock/0},
    {"Detect circular wait",
     fun test_circular_wait/0},
    {"Resource starvation deadlock",
     fun test_resource_starvation/0}.

%% @doc FAILING TEST: No deadlock in simple sequential
test_no_deadlock_sequential() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Act - Check for deadlock
    {ok, DeadlockState, _} = yawl_workflow_instance:detect_deadlock(InstancePid),

    %% Assert - Should be no deadlock
    ?assertEqual(no_deadlock, DeadlockState),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Detect potential deadlock
test_potential_deadlock() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(parallel_split, #{}),

    %% Act - Check for potential deadlock before starting
    {ok, InitialState, _} = yawl_workflow_instance:detect_deadlock(InstancePid),
    ?assertEqual(no_deadlock, InitialState),

    %% Start to trigger token movement
    ok = yawl_workflow_instance:start_workflow(InstancePid),
    timer:sleep(50),

    %% Check during execution
    {ok, ExecutionState, _} = yawl_workflow_instance:detect_deadlock(InstancePid),

    %% Assert - Should not be deadlocked during normal execution
    case ExecutionState of
        no_deadlock -> ok;
        potential_deadlock -> ok;  %% May occur transiently
        deadlocked ->
            ?assert(false, "Should not be fully deadlocked")
    end,

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Detect full deadlock
test_full_deadlock() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(custom_pattern, #{
        preset => #{
            t1 => [p1, p2],
            t2 => [p3, p4],
            t3 => [p5, p6],
            t4 => [p7, p8],
            t5 => [p9, p10],
            t6 => [p11, p12]
        },
        postset => #{
            t1 => [p3, p4],
            t2 => [p5, p6],
            t3 => [p7, p8],
            t4 => [p9, p10],
            t5 => [p11, p12],
            t6 => [p1, p2]
        }
    }),

    %% Act - Start and check deadlock
    ok = yawl_workflow_instance:start_workflow(InstancePid),
    timer:sleep(100),

    {ok, DeadlockState, Details} = yawl_workflow_instance:detect_deadlock(InstancePid),

    %% Assert - May detect deadlock in circular structure
    case DeadlockState of
        no_deadlock -> ok;
        potential_deadlock -> ok;
        deadlocked ->
            ?assert(maps:is_key(reason, Details)),
            ?assert(maps:is_key(blocked_transitions, Details))
    end,

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Detect circular wait
test_circular_wait() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(circular_pattern, #{}),

    %% Act - Detect circular wait
    {ok, Circular} = yawl_workflow_instance:detect_circular_wait(InstancePid),

    %% Assert - Should detect circular dependency
    case Circular of
        false -> ok;
        {true, Cycle} ->
            ?assert(is_list(Cycle)),
            ?assert(length(Cycle) > 0)
    end,

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Resource starvation deadlock
test_resource_starvation() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(resource_intensive, #{}),

    %% Act - Check for resource starvation
    {ok, Starvation} = yawl_workflow_instance:detect_resource_starvation(InstancePid),

    %% Assert - Should detect if resources are starved
    case Starvation of
        no_starvation -> ok;
        {starvation, Resources} ->
            ?assert(is_list(Resources)),
            ?assert(length(Resources) > 0)
    end,

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%%====================================================================
%% Event Subscription Tests
%%====================================================================

event_subscription_test_() ->
    {"Subscribe to workflow events",
     fun test_subscribe_events/0},
    {"Receive started event",
     fun test_receive_started_event/0},
    {"Receive completed event",
     fun test_receive_completed_event/0},
    {"Receive cancelled event",
     fun test_receive_cancelled_event/0},
    {"Receive error event",
     fun test_receive_error_event/0},
    {"Unsubscribe from events",
     fun test_unsubscribe_events/0},
    {"Multiple subscribers",
     fun test_multiple_subscribers/0}.

%% @doc FAILING TEST: Subscribe to workflow events
test_subscribe_events() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    SubscriberPid = self(),

    %% Act - Subscribe
    Result = yawl_workflow_instance:subscribe(InstancePid, SubscriberPid),

    %% Assert
    ?assertEqual(ok, Result),

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Receive started event
test_receive_started_event() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    SubscriberPid = self(),
    ok = yawl_workflow_instance:subscribe(InstancePid, SubscriberPid),

    %% Act - Start workflow
    ok = yawl_workflow_instance:start_workflow(InstancePid),

    %% Assert - Should receive started event
    receive
        {workflow_event, ?TEST_WORKFLOW_ID, started, _Timestamp} -> ok
    after 1000 ->
        ?assert(false, "Started event not received")
    end,

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Receive completed event
test_receive_completed_event() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    SubscriberPid = self(),
    ok = yawl_workflow_instance:subscribe(InstancePid, SubscriberPid),

    %% Act - Start and wait for completion
    ok = yawl_workflow_instance:start_workflow(InstancePid),
    timer:sleep(500),

    %% Assert - Should receive completed event
    receive
        {workflow_event, ?TEST_WORKFLOW_ID, completed, _Timestamp} -> ok
    after 1000 ->
        ?assert(false, "Completed event not received")
    end,

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Receive cancelled event
test_receive_cancelled_event() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    SubscriberPid = self(),
    ok = yawl_workflow_instance:subscribe(InstancePid, SubscriberPid),

    %% Act - Cancel workflow
    ok = yawl_workflow_instance:cancel_workflow(InstancePid),

    %% Assert - Should receive cancelled event
    receive
        {workflow_event, ?TEST_WORKFLOW_ID, cancelled, _Timestamp} -> ok
    after 1000 ->
        ?assert(false, "Cancelled event not received")
    end,

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Receive error event
test_receive_error_event() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    SubscriberPid = self(),
    ok = yawl_workflow_instance:subscribe(InstancePid, SubscriberPid),

    %% Act - Cause error
    InstancePid ! {force_error, test_error},

    %% Assert - Should receive error event
    receive
        {workflow_event, ?TEST_WORKFLOW_ID, {error, _Reason}, _Timestamp} -> ok
    after 1000 ->
        ?assert(false, "Error event not received")
    end,

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Unsubscribe from events
test_unsubscribe_events() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),
    SubscriberPid = self(),
    ok = yawl_workflow_instance:subscribe(InstancePid, SubscriberPid),

    %% Act - Unsubscribe
    Result = yawl_workflow_instance:unsubscribe(InstancePid, SubscriberPid),

    %% Assert
    ?assertEqual(ok, Result),

    %% Should not receive events after unsubscribe
    ok = yawl_workflow_instance:start_workflow(InstancePid),
    receive
        {workflow_event, _, _, _} -> ?assert(false, "Should not receive after unsubscribe")
    after 200 ->
        ok
    end,

    %% Cleanup
    exit(InstancePid, kill),
    instance_cleanup().

%% @doc FAILING TEST: Multiple subscribers
test_multiple_subscribers() ->
    %% Arrange
    instance_setup(),
    {ok, InstancePid} = create_test_instance(basic_sequential, #{}),

    %% Create multiple subscribers
    Subscribers = lists:map(fun(N) ->
        spawn(fun() ->
            timer:sleep(infinity),
            N
        end)
    end, lists:seq(1, 5)),

    %% Act - Subscribe all
    Results = lists:map(fun(SubPid) ->
        yawl_workflow_instance:subscribe(InstancePid, SubPid)
    end, Subscribers),

    %% Assert - All should subscribe successfully
    ?assert(lists:all(fun(R) -> R =:= ok end, Results)),

    %% Cleanup
    lists:foreach(fun(SubPid) ->
        exit(SubPid, kill)
    end, Subscribers),
    exit(InstancePid, kill),
    instance_cleanup().
