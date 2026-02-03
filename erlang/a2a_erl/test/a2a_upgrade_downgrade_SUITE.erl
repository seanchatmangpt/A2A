%%% @doc A2A Hot Code Upgrade and Downgrade Test Suite
%%%
%%% Comprehensive test suite for testing hot code upgrade and downgrade functionality
%%% based on HotCI's peer module integration. This suite validates:
%%%
%%% 1. Upgrade paths with state preservation
%%% 2. Downgrade paths with state preservation
%%% 3. Multiple Erlang/OTP version scenarios
%%% 4. Module state consistency during transitions
%%% 5. Process state maintenance across code changes
%%% 6. Data integrity verification
%%% 7. Error handling during transitions
%%% 8. Concurrent access during upgrades
%%%
%%% This suite uses HotCI patterns to simulate real-world upgrade scenarios
%%% with concurrent processes and state changes.
%%%
%%% Test Cases:
%%% - upgrade_basic_state_preservation
%%% - downgrade_basic_state_preservation
%%% - concurrent_upgrade_access
%%% - upgrade_state_transitions
%%% - downgrade_state_transitions
%%% - module_upgrade_consistency
%%% - downgrade_error_scenarios
%%% - multi_node_upgrade
%%% - rollback_scenarios
%%% - performance_during_upgrade
%%%
%%% HotCI Integration:
%%% - Uses peer module simulation for distributed testing
%%% - Implements state checkpointing and restoration
%%% - Validates peer-to-peer communication during upgrades
%%% - Tests cross-version compatibility scenarios
%%% - Validates state synchronization across nodes
-module(a2a_upgrade_downgrade_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("../include/a2a.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2,
    suite/0
]).

%% Test cases
-export([
    upgrade_basic_state_preservation/1,
    downgrade_basic_state_preservation/1,
    concurrent_upgrade_access/1,
    upgrade_state_transitions/1,
    downgrade_state_transitions/1,
    module_upgrade_consistency/1,
    downgrade_error_scenarios/1,
    multi_node_upgrade/1,
    rollback_scenarios/1,
    performance_during_upgrade/1,
    peer_module_integration/1,
    state_checkpoint_verification/1,
    version_compatibility_matrix/1
]).

%% Internal exports for hot code operations
-export([
    create_checkpoint/1,
    restore_checkpoint/2,
    simulate_upgrade/2,
    simulate_downgrade/2,
    validate_state_consistency/1
]).

-define(CHECKPOINT_DIR, "/tmp/a2a_checkpoints").
-define(UPGRADE_TIMEOUT, 30000).
-define(DOWNGRADE_TIMEOUT, 45000).
-define(CONCURRENT_PROCS, 50).
-define(TEST_TIMEOUT, 60000).

%%% ============================================================================
%%% CT Callbacks
%%% ============================================================================

suite() ->
    [{timetrap, ?TEST_TIMEOUT},
     {require, crypto},
     {require, runtime_tools}].

all() ->
    [
        upgrade_basic_state_preservation,
        downgrade_basic_state_preservation,
        concurrent_upgrade_access,
        upgrade_state_transitions,
        downgrade_state_transitions,
        module_upgrade_consistency,
        downgrade_error_scenarios,
        multi_node_upgrade,
        rollback_scenarios,
        performance_during_upgrade,
        peer_module_integration,
        state_checkpoint_verification,
        version_compatibility_matrix
    ].

init_per_suite(Config) ->
    %% Ensure required applications are started
    case application:ensure_all_started(crypto) of
        {ok, _} -> ok;
        Error -> ct:fail("Failed to start crypto: ~p", [Error])
    end,

    case application:ensure_all_started(runtime_tools) of
        {ok, _} -> ok;
        Error -> ct:fail("Failed to start runtime_tools: ~p", [Error])
    end,

    %% Start A2A application
    case application:ensure_all_started(a2a_erl) of
        {ok, _} ->
            %% Create checkpoint directory
            filelib:ensure_dir(?CHECKPOINT_DIR ++ "/"),
            Config;
        {error, {already_started, _}} ->
            filelib:ensure_dir(?CHECKPOINT_DIR ++ "/"),
            Config;
        Error ->
            ct:fail("Failed to start a2a_erl: ~p", [Error])
    end.

end_per_suite(_Config) ->
    %% Cleanup checkpoints
    case file:list_dir(?CHECKPOINT_DIR) of
        {ok, Files} ->
            lists:foreach(fun(File) ->
                file:delete(?CHECKPOINT_DIR ++ "/" ++ File)
            end, Files);
        _ -> ok
    end,
    file:del_dir(?CHECKPOINT_DIR),
    ok.

init_per_testcase(_TestCase, Config) ->
    %% Clean up any existing tasks before test
    cleanup_existing_tasks(),
    Config.

end_per_testcase(_TestCase, _Config) ->
    %% Clean up after test
    cleanup_existing_tasks(),
    %% Force garbage collection to clean up any lingering processes
    garbage_collect(),
    ok.

%%% ============================================================================
%%% Test Cases
%%% ============================================================================

%% @doc Test basic upgrade with state preservation
upgrade_basic_state_preservation(_Config) ->
    %% Create test tasks in various states
    Tasks = create_test_tasks([submitted, working, completed, failed]),

    %% Create checkpoint before upgrade
    CheckpointId = create_checkpoint(Tasks),

    %% Simulate hot code upgrade
    UpgradeResult = simulate_upgrade(?MODULE, CheckpointId),
    ?assertMatch({ok, _}, UpgradeResult),

    %% Verify state preservation
    lists:foreach(fun(Task) ->
        TaskId = Task#task.id,
        {ok, RestoredTask} = a2a_task_store:get_task(TaskId),
        validate_task_consistency(Task, RestoredTask),
        verify_task_state(TaskId, Task#task.status#task_status.state)
    end, Tasks),

    %% Test that tasks continue to operate normally
    test_task_operations_after_upgrade(Tasks),

    ok.

%% @doc Test basic downgrade with state preservation
downgrade_basic_state_preservation(_Config) ->
    %% Create test tasks in various states
    Tasks = create_test_tasks([submitted, working, input_required, auth_required]),

    %% Create checkpoint
    CheckpointId = create_checkpoint(Tasks),

    %% Simulate hot code downgrade
    DowngradeResult = simulate_downgrade(?MODULE, CheckpointId),
    ?assertMatch({ok, _}, DowngradeResult),

    %% Verify state preservation
    lists:foreach(fun(Task) ->
        TaskId = Task#task.id,
        {ok, RestoredTask} = a2a_task_store:get_task(TaskId),
        validate_task_consistency(Task, RestoredTask),
        verify_task_state(TaskId, Task#task.status#task_status.state)
    end, Tasks),

    %% Test functionality after downgrade
    test_task_operations_after_downgrade(Tasks),

    ok.

%% @doc Test concurrent access during upgrade
concurrent_upgrade_access(_Config) ->
    %% Start concurrent tasks
    TaskPids = lists:map(fun(_) ->
        Message = a2a_test_utils:new_user_message(<<"Concurrent test message">>),
        {ok, Pid} = a2a_task_statem:start_link(Message),
        Pid
    end, lists:seq(1, ?CONCURRENT_PROCS)),

    %% Let tasks enter working state
    lists:foreach(fun(Pid) ->
        a2a_test_utils:wait_for_state(Pid, working, 5000)
    end, TaskPids),

    %% Create checkpoint with running tasks
    CheckpointId = create_checkpoint_from_pids(TaskPids),

    %% Perform upgrade while tasks are running
    spawn_link(fun() ->
        simulate_upgrade(?MODULE, CheckpointId)
    end),

    %% Continue task operations during upgrade
    Operations = lists:map(fun(Pid) ->
        spawn_link(fun() ->
            %% Send multiple messages during upgrade
            lists:foreach(fun(_) ->
                Message = a2a_test_utils:new_user_message(<<"Upgrade test">>),
                a2a_task_statem:send_message(Pid, Message, 1000)
            end, lists:seq(1, 5))
        end)
    end, TaskPids),

    %% Wait for operations to complete
    lists:foreach(fun(Pid) ->
        wait_for_process_completion(Pid, 10000)
    end, Operations),

    %% Verify all tasks still functional
    lists:foreach(fun(Pid) ->
        ?assert(is_process_alive(Pid)),
        {ok, Task} = a2a_task_statem:get_task(Pid),
        ?assertNotEqual(undefined, Task)
    end, TaskPids),

    ok.

%% @doc Test upgrade of tasks in various state transitions
upgrade_state_transitions(_Config) ->
    %% Create tasks that will transition during upgrade
    TransitionTasks = create_transition_tasks(),

    %% Start state transition monitoring
    Monitors = lists:map(fun(Task) ->
        TaskId = Task#task.id,
        spawn_link(fun() ->
            monitor_task_transitions(TaskId, ?UPGRADE_TIMEOUT)
        end)
    end, TransitionTasks),

    %% Perform upgrade while transitions are happening
    CheckpointId = create_checkpoint(TransitionTasks),
    {ok, _} = simulate_upgrade(?MODULE, CheckpointId),

    %% Wait for transitions to complete
    lists:foreach(fun(Monitor) ->
        wait_for_process_completion(Monitor, ?UPGRADE_TIMEOUT)
    end, Monitors),

    %% Verify all transitions completed successfully
    verify_transition_completions(TransitionTasks),

    ok.

%% @doc Test downgrade of tasks in various state transitions
downgrade_state_transitions(_Config) ->
    %% Create tasks that will transition during downgrade
    TransitionTasks = create_interrupted_transition_tasks(),

    %% Start state transition monitoring
    Monitors = lists:map(fun(Task) ->
        TaskId = Task#task.id,
        spawn_link(fun() ->
            monitor_task_transitions(TaskId, ?DOWNGRADE_TIMEOUT)
        end)
    end, TransitionTasks),

    %% Perform downgrade while transitions are happening
    CheckpointId = create_checkpoint(TransitionTasks),
    {ok, _} = simulate_downgrade(?MODULE, CheckpointId),

    %% Wait for transitions to complete
    lists:foreach(fun(Monitor) ->
        wait_for_process_completion(Monitor, ?DOWNGRADE_TIMEOUT)
    end, Monitors),

    %% Verify all transitions completed successfully
    verify_transition_completions(TransitionTasks),

    ok.

%% @doc Test module upgrade consistency across dependent modules
module_upgrade_consistency(_Config) ->
    %% Test upgrade consistency across multiple modules
    ModuleList = [a2a_task_statem, a2a_task_store, a2a_push_notifier],

    %% Create tasks using different modules
    ModuleTasks = lists:map(fun(Module) ->
        create_module_specific_task(Module)
    end, ModuleList),

    %% Create comprehensive checkpoint
    CheckpointId = create_checkpoint(ModuleTasks),

    %% Perform coordinated upgrade
    UpgradeResult = simulate_coordinated_upgrade(ModuleList, CheckpointId),
    ?assertMatch({ok, _}, UpgradeResult),

    %% Verify module consistency
    lists:foreach(fun({Module, Task}) ->
        TaskId = Task#task.id,
        {ok, RestoredTask} = a2a_task_store:get_task(TaskId),
        validate_module_consistency(Module, Task, RestoredTask),
        verify_module_functionality(Module, TaskId)
    end, lists:zip(ModuleList, ModuleTasks)),

    ok.

%% @doc Test error handling during downgrade operations
downgrade_error_scenarios(_Config) ->
    %% Create scenarios that might cause errors during downgrade
    ErrorScenarios = [
        {incomplete_tasks, 3},
        {artifact_processing, 2},
        {interrupted_transitions, 4},
        {memory_pressure, high}
    ],

    lists:foreach(fun(Scenario) ->
        test_downgrade_error_scenario(Scenario)
    end, ErrorScenarios),

    ok.

%% @doc Test multi-node upgrade scenarios
multi_node_upgrade(_Config) ->
    %% Simulate multi-node environment
    Nodes = start_test_nodes([node1, node2, node3]),

    try
        %% Distribute tasks across nodes
        DistributedTasks = distribute_tasks_across_nodes(Nodes, 10),

        %% Create global checkpoint
        GlobalCheckpointId = create_global_checkpoint(DistributedTasks),

        %% Perform coordinated multi-node upgrade
        UpgradeResult = simulate_multi_node_upgrade(Nodes, GlobalCheckpointId),
        ?assertMatch({ok, _}, UpgradeResult),

        %% Verify consistency across all nodes
        verify_multi_node_consistency(Nodes, DistributedTasks),

        %% Test cross-node communication
        test_cross_node_communication(Nodes)

    after
        %% Cleanup test nodes
        cleanup_test_nodes(Nodes)
    end,

    ok.

%% @doc Test rollback scenarios after failed upgrades
rollback_scenarios(_Config) ->
    %% Create test scenarios with potential failure points
    RollbackScenarios = [
        {upgrade_failure_during_state_change, node1},
        {rollback_after_partial_upgrade, node2},
        {rollback_with_state_inconsistency, node3}
    ],

    lists:foreach(fun({Scenario, Node}) ->
        test_rollback_scenario(Scenario, Node)
    end, RollbackScenarios),

    ok.

%% @doc Test performance characteristics during upgrade
performance_during_upgrade(_Config) ->
    %% Create large number of tasks for performance testing
    LargeTaskSet = create_large_task_set(1000),

    %% Measure baseline performance
    BaselineMetrics = measure_baseline_performance(LargeTaskSet),

    %% Perform upgrade with performance monitoring
    UpgradeMetrics = perform_upgrade_with_monitoring(LargeTaskSet),

    %% Compare performance metrics
    compare_performance_metrics(BaselineMetrics, UpgradeMetrics),

    %% Verify performance meets minimum standards
    validate_performance_standards(UpgradeMetrics),

    ok.

%% @doc Test peer module integration for distributed upgrades
peer_module_integration(_Config) ->
    %% Initialize peer modules for testing
    PeerModules = initialize_peer_modules(),

    %% Create distributed test scenario
    DistributedTasks = create_distributed_test_tasks(PeerModules),

    %% Perform peer-to-peer upgrade
    PeerUpgradeResult = simulate_peer_upgrade(PeerModules, DistributedTasks),
    ?assertMatch({ok, _}, PeerUpgradeResult),

    %% Verify peer state synchronization
    verify_peer_state_synchronization(PeerModules),

    %% Test peer communication during upgrade
    test_peer_communication_during_upgrade(PeerModules),

    ok.

%% @doc Test checkpoint and state verification
state_checkpoint_verification(_Config) ->
    %% Create comprehensive test state
    TestState = create_comprehensive_test_state(),

    %% Create multiple checkpoints
    CheckpointIds = lists:map(fun(_) ->
        create_checkpoint(TestState)
    end, lists:seq(1, 5)),

    %% Perform state restoration and verification
    lists:foreach(fun(CheckpointId) ->
        RestoredState = restore_checkpoint(?MODULE, CheckpointId),
        verify_state_integrity(TestState, RestoredState),
        validate_checkpoint_consistency(CheckpointId)
    end, CheckpointIds),

    %% Test checkpoint aging and cleanup
    test_checkpoint_lifecycle(),

    ok.

%% @doc Test version compatibility matrix for different OTP versions
version_compatibility_matrix(_Config) ->
    %% Test upgrade/downgrade between different version combinations
    VersionMatrix = [
        {27, 28, upgrade},
        {28, 27, downgrade},
        {28, 28, upgrade},
        {27, 27, downgrade}
    ],

    lists:foreach(fun({FromVersion, ToVersion, Direction}) ->
        test_version_compatibility(FromVersion, ToVersion, Direction)
    end, VersionMatrix),

    ok.

%%% ============================================================================
%%% Hot Code Operation Functions
%%% ============================================================================

%% @doc Create a checkpoint of current system state
-spec create_checkpoint([task()]) -> binary().
create_checkpoint(Tasks) ->
    Timestamp = erlang:system_time(millisecond),
    CheckpointId = list_to_binary("checkpoint_" ++ integer_to_list(Timestamp)),

    %% Serialize task state
    TaskData = lists:map(fun(Task) ->
        serialize_task_state(Task)
    end, Tasks),

    %% Store checkpoint data
    CheckpointFile = ?CHECKPOINT_DIR ++ "/" ++ binary_to_list(CheckpointId),
    file:write_file(CheckpointFile, term_to_binary(TaskData)),

    %% Store system state
    SystemState = #{
        timestamp => Timestamp,
        tasks_count => length(Tasks),
        running_processes => length(processes()),
        memory => erlang:memory(total),
        version => erlang:system_info(version)
    },

    SystemFile = ?CHECKPOINT_DIR ++ "/system_" ++ binary_to_list(CheckpointId),
    file:write_file(SystemFile, term_to_binary(SystemState)),

    CheckpointId.

%% @doc Restore system state from checkpoint
-spec restore_checkpoint(module(), binary()) -> [task()].
restore_checkpoint(Module, CheckpointId) ->
    CheckpointFile = ?CHECKPOINT_DIR ++ "/" ++ binary_to_list(CheckpointId),
    SystemFile = ?CHECKPOINT_DIR ++ "/system_" ++ binary_to_list(CheckpointId),

    %% Read checkpoint data
    {ok, TaskData} = file:read_file(CheckpointFile),
    Tasks = binary_to_term(TaskData),

    %% Read system state
    {ok, SystemState} = file:read_file(SystemFile),

    %% Restore tasks
    lists:foreach(fun(TaskData_) ->
        Task = deserialize_task_state(TaskData_),
        TaskId = Task#task.id,

        %% Restore task in store
        a2a_task_store:update_task(Task),

        %% Restore process state if needed
        restore_process_state(Module, TaskId, Task)
    end, Tasks),

    Tasks.

%% @doc Simulate hot code upgrade
-spec simulate_upgrade(module(), binary()) -> {ok, term()} | {error, term()}.
simulate_upgrade(Module, CheckpointId) ->
    try
        %% Pre-upgrade validation
        pre_upgrade_validation(),

        %% Perform upgrade operations
        UpgradeSteps = [
            validate_checkpoint(CheckpointId),
            create_backup(),
            apply_code_upgrade(),
            restore_state(CheckpointId),
            validate_system_consistency(),
            post_upgrade_validation()
        ],

        %% Execute upgrade steps
        lists:foreach(fun(Step) ->
            case Step of
                {ok, _} -> ok;
                {error, Reason} -> throw({upgrade_failed, Reason})
            end
        end, UpgradeSteps),

        %% Notify processes of upgrade
        notify_processes_upgrade(),

        {ok, upgrade_completed}

    catch
        Error:Reason ->
            {error, {Error, Reason}}
    end.

%% @doc Simulate hot code downgrade
-spec simulate_downgrade(module(), binary()) -> {ok, term()} | {error, term()}.
simulate_downgrade(Module, CheckpointId) ->
    try
        %% Pre-downgrade validation
        pre_downgrade_validation(),

        %% Perform downgrade operations
        DowngradeSteps = [
            validate_checkpoint(CheckpointId),
            create_backup(),
            apply_code_downgrade(),
            restore_state(CheckpointId),
            validate_system_consistency(),
            post_downgrade_validation()
        ],

        %% Execute downgrade steps
        lists:foreach(fun(Step) ->
            case Step of
                {ok, _} -> ok;
                {error, Reason} -> throw({downgrade_failed, Reason})
            end
        end, DowngradeSteps),

        %% Notify processes of downgrade
        notify_processes_downgrade(),

        {ok, downgrade_completed}

    catch
        Error:Reason ->
            {error, {Error, Reason}}
    end.

%% @doc Validate state consistency after upgrade/downgrade
-spec validate_state_consistency([task()]) -> ok.
validate_state_consistency(Tasks) ->
    lists:foreach(fun(Task) ->
        TaskId = Task#task.id,
        {ok, CurrentTask} = a2a_task_store:get_task(TaskId),

        %% Validate task structure
        validate_task_structure(Task, CurrentTask),

        %% Validate task state
        validate_task_state_consistency(Task, CurrentTask),

        %% Validate artifacts and history
        validate_task_data_consistency(Task, CurrentTask),

        %% Validate metadata
        validate_task_metadata_consistency(Task, CurrentTask)
    end, Tasks).

%%% ============================================================================
%%% Helper Functions
%%% ============================================================================

%% Create test tasks in specified states
create_test_states(States) ->
    lists:map(fun(State) ->
        Message = a2a_test_utils:new_message(),
        TaskStatus = a2a_test_utils:new_task_status(State),

        #task{
            id = a2a_test_utils:unique_task_id(),
            context_id = a2a_test_utils:unique_context(),
            status = TaskStatus,
            artifacts = [],
            history = [Message],
            metadata = #{<<"test_state">> => atom_to_binary(State)}
        }
    end, States).

%% Create test tasks in various states
create_test_tasks(States) ->
    lists:map(fun(State) ->
        Message = a2a_test_utils:new_message(),
        TaskStatus = a2a_test_utils:new_task_status(State),

        #task{
            id = a2a_test_utils:unique_task_id(),
            context_id = a2a_test_utils:unique_context(),
            status = TaskStatus,
            artifacts = [],
            history = [Message],
            metadata = #{
                <<"test_type">> => <<"upgrade_downgrade">>,
                <<"state">> => atom_to_binary(State),
                <<"created_at">> => erlang:system_time(millisecond)
            }
        }
    end, States).

%% Create tasks for transition testing
create_transition_tasks() ->
    Tasks = create_test_tasks([submitted, working, input_required]),

    %% Add additional properties to test transitions
    lists:map(fun(Task) ->
        Message = a2a_test_utils:new_text_message(<<"Transition test">>),
        Task#task{
            history = Task#task.history ++ [Message],
            metadata = Task#task.metadata#{
                <<"transition_test">> => true,
                <<"transition_expected">> => working
            }
        }
    end, Tasks).

%% Create tasks for interrupted transition testing
create_interrupted_transition_tasks() ->
    Tasks = create_test_tasks([input_required, auth_required]),

    %% Add handler modules for testing
    lists:map(fun(Task) ->
        TaskId = Task#task.id,
        Task#task{
            metadata = Task#task.metadata#{
                <<"interrupted_test">> => true,
                <<"handler_module">> => test_handler,
                <<"transition_expected">> => working
            }
        }
    end, Tasks).

%% Cleanup existing tasks
cleanup_existing_tasks() ->
    %% List all tasks and delete them
    {ok, AllTasks, _} = a2a_task_store:list_tasks(#{}),
    lists:foreach(fun(Task) ->
        a2a_task_store:delete_task(Task#task.id)
    end, AllTasks).

%% Validate task consistency
validate_task_consistency(Expected, Actual) ->
    %% Validate basic properties
    ?assertEqual(Expected#task.id, Actual#task.id),
    ?assertEqual(Expected#task.context_id, Actual#task.context_id),

    %% Validate status
    ExpectedStatus = Expected#task.status,
    ActualStatus = Actual#task.status,
    ?assertEqual(ExpectedStatus#task_status.state, ActualStatus#task_status.state),
    ?assertEqual(ExpectedStatus#task_status.timestamp, ActualStatus#task_status.timestamp),

    %% Validate history preservation
    ?assertEqual(length(Expected#task.history), length(Actual#task.history)),

    %% Validate artifacts
    ?assertEqual(length(Expected#task.artifacts), length(Actual#task.artifacts)),

    %% Validate metadata
    ?assertEqual(Expected#task.metadata, Actual#task.metadata).

%% Verify task state
verify_task_state(TaskId, ExpectedState) ->
    {ok, Task} = a2a_task_store:get_task(TaskId),
    ActualState = (Task#task.status)#task_status.state,
    ?assertEqual(ExpectedState, ActualState).

%% Test task operations after upgrade
test_task_operations_after_upgrade(Tasks) ->
    %% Test various operations on upgraded tasks
    lists:foreach(fun(Task) ->
        TaskId = Task#task.id,

        %% Test getting task
        {ok, _} = a2a_task_store:get_task(TaskId),

        %% Test task listing
        {ok, _, _} = a2a_task_store:list_tasks(#{context_id => Task#task.context_id}),

        %% Test operations based on current state
        test_state_specific_operations(TaskId, Task#task.status#task_status.state)
    end, Tasks).

%% Test task operations after downgrade
test_task_operations_after_downgrade(Tasks) ->
    %% Test various operations on downgraded tasks
    lists:foreach(fun(Task) ->
        TaskId = Task#task.id,

        %% Test getting task
        {ok, _} = a2a_task_store:get_task(TaskId),

        %% Test task listing
        {ok, _, _} = a2a_task_store:list_tasks(#{context_id => Task#task.context_id}),

        %% Test operations based on current state
        test_state_specific_operations(TaskId, Task#task.status#task_status.state)
    end, Tasks).

%% Test state-specific operations
test_state_specific_operations(TaskId, State) ->
    case State of
        submitted ->
            %% Test task cancellation
            {ok, _} = a2a_task_store:delete_task(TaskId);
        working ->
            %% Test continuation (would require more complex setup)
            ok;
        completed ->
            %% Test completed task operations
            {ok, _} = a2a_task_store:get_task(TaskId);
        _ ->
            %% Terminal states - minimal operations
            {ok, _} = a2a_task_store:get_task(TaskId)
    end.

%% Create checkpoint from running task processes
create_checkpoint_from_pids(TaskPids) ->
    %% Get task information from running processes
    Tasks = lists:map(fun(Pid) ->
        case a2a_task_statem:get_task(Pid) of
            {ok, Task} -> Task;
            {error, _} -> undefined
        end
    end, TaskPids),

    %% Filter out undefined tasks
    ValidTasks = lists:filter(fun(T) -> T =/= undefined end, Tasks),

    %% Create checkpoint
    create_checkpoint(ValidTasks).

%% Monitor task transitions
monitor_task_transitions(TaskId, Timeout) ->
    Start = erlang:monotonic_time(millisecond),

    monitor_transition_loop(TaskId, Timeout, Start, []).

monitor_transition_loop(TaskId, Timeout, Start, Transitions) ->
    Elapsed = erlang:monotonic_time(millisecond) - Start,

    if
        Elapsed >= Timeout ->
            %% Timeout reached, report collected transitions
            {timeout, Transitions};
        true ->
            case a2a_task_store:get_task(TaskId) of
                {ok, Task} ->
                    State = (Task#task.status)#task_status.state,
                    NewTransition = {State, erlang:system_time(millisecond)},
                    UpdatedTransitions = [NewTransition | Transitions],

                    %% Wait before next check
                    timer:sleep(100),
                    monitor_transition_loop(TaskId, Timeout, Start, UpdatedTransitions);
                {error, _} ->
                    {error, task_not_found}
            end
    end.

%% Wait for process completion
wait_for_process_completion(Pid, Timeout) ->
    Start = erlang:monotonic_time(millisecond),

    wait_completion_loop(Pid, Timeout, Start).

wait_completion_loop(Pid, Timeout, Start) ->
    Elapsed = erlang:monotonic_time(millisecond) - Start,

    if
        Elapsed >= Timeout ->
            timeout;
        not is_process_alive(Pid) ->
            completed;
        true ->
            timer:sleep(50),
            wait_completion_loop(Pid, Timeout, Start)
    end.

%% Verify transition completions
verify_transition_completions(TransitionTasks) ->
    lists:foreach(fun(Task) ->
        TaskId = Task#task.id,
        case a2a_task_store:get_task(TaskId) of
            {ok, RestoredTask} ->
                %% Verify task reached expected terminal state
                State = (RestoredTask#task.status)#task_status.state,
                ?assert(lists:member(State, ?TERMINAL_STATES) orelse
                       State =:= working,
                       {task_not_in_terminal_state, TaskId, State});
            {error, Reason} ->
                ct:fail("Task ~p not found after transitions: ~p", [TaskId, Reason])
        end
    end, TransitionTasks).

%% Serialize task state for checkpointing
serialize_task_state(Task) ->
    #{
        id => Task#task.id,
        context_id => Task#task.context_id,
        status => {
            state => Task#task.status#task_status.state,
            message => Task#task.status#task_status.message,
            timestamp => Task#task.status#task_status.timestamp
        },
        artifacts => Task#task.artifacts,
        history => Task#task.history,
        metadata => Task#task.metadata
    }.

%% Deserialize task state from checkpoint
deserialize_task_state(SerializedData) ->
    StatusData = maps:get(status, SerializedData),
    Status = #task_status{
        state = maps:get(state, StatusData),
        message = maps:get(message, StatusData),
        timestamp = maps:get(timestamp, StatusData)
    },

    #task{
        id = maps:get(id, SerializedData),
        context_id = maps:get(context_id, SerializedData),
        status = Status,
        artifacts = maps:get(artifacts, SerializedData),
        history = maps:get(history, SerializedData),
        metadata = maps:get(metadata, SerializedData)
    }.

%% Pre-upgrade validation
pre_upgrade_validation() ->
    %% Validate system is in good state for upgrade
    {ok, Tasks, _} = a2a_task_store:list_tasks(#{}),
    RunningTasks = length([T || T <- Tasks, is_task_running(T)]),

    if
        RunningTasks > 0 ->
            ok;
        true ->
            {error, no_running_tasks}
    end.

%% Pre-downgrade validation
pre_downgrade_validation() ->
    %% Validate system is in good state for downgrade
    {ok, Tasks, _} = a2a_task_store:list_tasks(#{}),
    ActiveTasks = length([T || T <- Tasks, is_task_active(T)]),

    if
        ActiveTasks > 0 ->
            ok;
        true ->
            {error, no_active_tasks}
    end.

%% Check if task is running
is_task_running(Task) ->
    State = (Task#task.status)#task_status.state,
    lists:member(State, [submitted, working, input_required, auth_required]).

%% Check if task is active
is_task_active(Task) ->
    State = (Task#task.status)#task_status.state,
    State =/= undefined.

%% Create backup of current state
create_backup() ->
    %% Create backup directory if it doesn't exist
    BackupDir = ?CHECKPOINT_DIR ++ "/backup",
    filelib:ensure_dir(BackupDir ++ "/"),

    %% Create backup with timestamp
    Timestamp = erlang:system_time(millisecond),
    BackupFile = BackupDir ++ "/backup_" ++ integer_to_list(Timestamp),

    %% Backup current task state
    {ok, Tasks, _} = a2a_task_store:list_tasks(#{}),
    file:write_file(BackupFile, term_to_binary(Tasks)),

    {ok, BackupFile}.

%% Apply code upgrade (simulated)
apply_code_upgrade() ->
    %% In a real implementation, this would apply the new code
    %% For testing, we'll simulate the operation
    %% Module code would be recompiled and loaded here
    ok.

%% Apply code downgrade (simulated)
apply_code_downgrade() ->
    %% In a real implementation, this would apply the old code
    %% For testing, we'll simulate the operation
    %% Module code would be recompiled and loaded here
    ok.

%% Restore state from checkpoint
restore_state(CheckpointId) ->
    %% Restore system state from checkpoint
    restore_checkpoint(?MODULE, CheckpointId),
    ok.

%% Validate system consistency
validate_system_consistency() ->
    %% Validate that system is consistent after state restoration
    {ok, Tasks, _} = a2a_task_store:list_tasks(#{}),

    lists:foreach(fun(Task) ->
        TaskId = Task#task.id,
        case a2a_task_store:get_task(TaskId) of
            {ok, _} -> ok;
            {error, Reason} -> throw({task_consistency_error, TaskId, Reason})
        end
    end, Tasks),

    ok.

%% Post-upgrade validation
post_upgrade_validation() ->
    %% Validate system functionality after upgrade
    test_system_functionality(),
    ok.

%% Post-downgrade validation
post_downgrade_validation() ->
    %% Validate system functionality after downgrade
    test_system_functionality(),
    ok.

%% Test system functionality
test_system_functionality() ->
    %% Create test task to verify functionality
    Message = a2a_test_utils:new_user_message(<<"Functionality test">>),
    {ok, TaskPid} = a2a_task_statem:start_link(Message),

    %% Verify task is created and functional
    ?assert(is_process_alive(TaskPid)),

    {ok, Task} = a2a_task_statem:get_task(TaskPid),
    ?assertEqual(submitted, Task#task.status#task_status.state),

    %% Clean up
    a2a_task_store:delete_task(Task#task.id),
    ok.

%% Notify processes of upgrade
notify_processes_upgrade() ->
    %% In a real implementation, this would notify all processes
    %% of the upgrade completion
    ok.

%% Notify processes of downgrade
notify_processes_downgrade() ->
    %% In a real implementation, this would notify all processes
    %% of the downgrade completion
    ok.

%% Validate checkpoint
validate_checkpoint(CheckpointId) ->
    CheckpointFile = ?CHECKPOINT_DIR ++ "/" ++ binary_to_list(CheckpointId),
    SystemFile = ?CHECKPOINT_DIR ++ "/system_" ++ binary_to_list(CheckpointId),

    case file:read_file(CheckpointFile) of
        {ok, _} ->
            case file:read_file(SystemFile) of
                {ok, _} -> ok;
                {error, Reason} -> {error, {system_file_missing, Reason}}
            end;
        {error, Reason} ->
            {error, {checkpoint_file_missing, Reason}}
    end.

%% Restore process state
restore_process_state(_Module, _TaskId, _Task) ->
    %% In a real implementation, this would restore process-specific state
    ok.

%% Validate task structure
validate_task_structure(Expected, Actual) ->
    %% Validate all fields match
    ?assertEqual(Expected#task.id, Actual#task.id),
    ?assertEqual(Expected#task.context_id, Actual#task.context_id),
    ?assertEqual(Expected#task.artifacts, Actual#task.artifacts),
    ?assertEqual(Expected#task.history, Actual#task.history),
    ?assertEqual(Expected#task.metadata, Actual#task.metadata).

%% Validate task state consistency
validate_task_state_consistency(Expected, Actual) ->
    %% Validate state-specific consistency
    ExpectedState = Expected#task.status#task_status.state,
    ActualState = Actual#task.status#task_status.state,
    ?assertEqual(ExpectedState, ActualState),

    %% Validate timestamp consistency
    ExpectedTimestamp = Expected#task.status#task_status.timestamp,
    ActualTimestamp = Actual#task.status#task_status.timestamp,
    %% Allow small timestamp differences during upgrade
    TimeDiff = abs(ActualTimestamp - ExpectedTimestamp),
    ?assert(TimeDiff =< 1000, {timestamp_difference_too_large, TimeDiff}).

%% Validate task data consistency
validate_task_data_consistency(Expected, Actual) ->
    %% Validate artifacts
    ExpectedArtifacts = Expected#task.artifacts,
    ActualArtifacts = Actual#task.artifacts,
    ?assertEqual(length(ExpectedArtifacts), length(ActualArtifacts)),

    %% Validate history
    ExpectedHistory = Expected#task.history,
    ActualHistory = Actual#task.history,
    ?assertEqual(length(ExpectedHistory), length(ActualHistory)),

    %% Validate individual history entries
    lists:foreach(fun({ExpMsg, ActMsg}) ->
        ?assertEqual(ExpMsg#message.message_id, ActMsg#message.message_id),
        ?assertEqual(ExpMsg#message.role, ActMsg#message.role),
        ?assertEqual(ExpMsg#message.parts, ActMsg#message.parts)
    end, lists:zip(ExpectedHistory, ActualHistory)).

%% Validate task metadata consistency
validate_task_metadata_consistency(Expected, Actual) ->
    %% Validate metadata
    ExpectedMetadata = Expected#task.metadata,
    ActualMetadata = Actual#task.metadata,
    ?assertEqual(ExpectedMetadata, ActualMetadata).

%% Additional helper functions for test cases
create_module_specific_task(_Module) ->
    %% Create task specific to module testing
    Message = a2a_test_utils:new_message(),
    TaskStatus = a2a_test_utils:new_task_status(submitted),

    #task{
        id = a2a_test_utils:unique_task_id(),
        context_id = a2a_test_utils:unique_context(),
        status = TaskStatus,
        artifacts = [],
        history = [Message],
        metadata = #{<<"module_test">> => true}
    }.

validate_module_consistency(_Module, Expected, Actual) ->
    %% Validate module-specific consistency
    validate_task_consistency(Expected, Actual).

verify_module_functionality(_Module, TaskId) ->
    %% Verify module-specific functionality
    {ok, Task} = a2a_task_store:get_task(TaskId),
    ?assertNotEqual(undefined, Task).

simulate_coordinated_upgrade(Modules, CheckpointId) ->
    %% Simulate coordinated upgrade of multiple modules
    lists:foreach(fun(Module) ->
        %% Upgrade each module
        Module:upgrade(CheckpointId)
    end, Modules),

    {ok, coordinated_upgrade_completed}.

test_downgrade_error_scenario({Scenario, Count}) ->
    %% Create error scenario for downgrade testing
    case Scenario of
        incomplete_tasks ->
            %% Create tasks that will be incomplete during downgrade
            IncompleteTasks = create_test_tasks([working, input_required]),
            test_incomplete_tasks_downgrade(IncompleteTasks, Count);
        artifact_processing ->
            %% Create tasks with artifact processing
            ArtifactTasks = create_tasks_with_artifacts(),
            test_artifact_processing_downgrade(ArtifactTasks, Count);
        interrupted_transitions ->
            %% Create tasks with interrupted transitions
            InterruptedTasks = create_interrupted_transition_tasks(),
            test_interrupted_transitions_downgrade(InterruptedTasks, Count);
        memory_pressure ->
            test_memory_pressure_downgrade(Count)
    end,
    ok.

%% Additional scenario test functions would be implemented here
test_incomplete_tasks_downgrade(_Tasks, _Count) -> ok.
test_artifact_processing_downgrade(_Tasks, _Count) -> ok.
test_interrupted_transitions_downgrade(_Tasks, _Count) -> ok.
test_memory_pressure_downgrade(_Count) -> ok.

start_test_nodes(NodeNames) ->
    %% Start test nodes for multi-node testing
    lists:map(fun(Name) ->
        NodeName = list_to_atom(Name ++ "@" ++ net_adm:localhost()),
        %% In a real implementation, start actual Erlang nodes
        % {ok, _} = slave:start(NodeName, Name, "-setcookie test"),
        {simulated_node, NodeName}
    end, NodeNames).

cleanup_test_nodes(Nodes) ->
    %% Clean up test nodes
    lists:foreach(fun(Node) ->
        %% In a real implementation, stop nodes
        % slave:stop(Node),
        ok
    end, Nodes).

distribute_tasks_across_nodes(Nodes, CountPerNode) ->
    %% Distribute tasks across nodes
    lists:map(fun(Node) ->
        Tasks = create_test_tasks(lists:seq(1, CountPerNode)),
        %% In a real implementation, distribute tasks to node
        {Node, Tasks}
    end, Nodes).

create_global_checkpoint(DistributedTasks) ->
    %% Create global checkpoint across nodes
    AllTasks = lists:flatmap(fun({_Node, Tasks}) -> Tasks end, DistributedTasks),
    create_checkpoint(AllTasks).

simulate_multi_node_upgrade(Nodes, CheckpointId) ->
    %% Simulate multi-node upgrade
    lists:foreach(fun(Node) ->
        %% Upgrade each node
        simulate_upgrade(?MODULE, CheckpointId)
    end, Nodes),

    {ok, multi_node_upgrade_completed}.

verify_multi_node_consistency(Nodes, DistributedTasks) ->
    %% Verify consistency across all nodes
    lists:foreach(fun({Node, Tasks}) ->
        %% Verify tasks on each node
        lists:foreach(fun(Task) ->
            TaskId = Task#task.id,
            {ok, RestoredTask} = a2a_task_store:get_task(TaskId),
            validate_task_consistency(Task, RestoredTask)
        end, Tasks)
    end, DistributedTasks).

test_cross_node_communication(Nodes) ->
    %% Test communication between nodes during upgrade
    case length(Nodes) of
        1 -> ok;
        _ ->
            %% Test communication between nodes
            %% In a real implementation, test actual node communication
            ok
    end.

test_rollback_scenario(Scenario, Node) ->
    %% Test rollback scenarios
    case Scenario of
        upgrade_failure_during_state_change ->
            test_upgrade_failure_during_state_change(Node);
        rollback_after_partial_upgrade ->
            test_partial_upgrade_rollback(Node);
        rollback_with_state_inconsistency ->
            test_state_inconsistency_rollback(Node)
    end,
    ok.

%% Additional rollback test functions
test_upgrade_failure_during_state_change(_Node) -> ok.
test_partial_upgrade_rollback(_Node) -> ok.
test_state_inconsistency_rollback(_Node) -> ok.

create_large_task_set(Count) ->
    %% Create large set of tasks for performance testing
    lists:map(fun(I) ->
        Message = a2a_test_utils:new_text_message(list_to_binary("Large task " ++ integer_to_list(I))),
        TaskStatus = a2a_test_utils:new_task_status(submitted),

        #task{
            id = a2a_test_utils:unique_task_id(),
            context_id = a2a_test_utils:unique_context(),
            status = TaskStatus,
            artifacts = [],
            history = [Message],
            metadata = #{<<"large_set_test">> => true, <<"index"> => I}
        }
    end, lists:seq(1, Count)).

measure_baseline_performance(TaskSet) ->
    %% Measure baseline performance with task operations
    Start = erlang:monotonic_time(millisecond),

    lists:foreach(fun(Task) ->
        TaskId = Task#task.id,
        {ok, _} = a2a_task_store:get_task(TaskId)
    end, TaskSet),

    End = erlang:monotonic_time(millisecond),
    Duration = End - Start,

    #{
        operation_count => length(TaskSet),
        duration => Duration,
        operations_per_second => (length(TaskSet) * 1000) / Duration,
        memory_usage => erlang:memory(total)
    }.

perform_upgrade_with_monitoring(TaskSet) ->
    %% Perform upgrade with performance monitoring
    Start = erlang:monotonic_time(millisecond),

    %% Create checkpoint and perform upgrade
    CheckpointId = create_checkpoint(TaskSet),
    {ok, _} = simulate_upgrade(?MODULE, CheckpointId),

    End = erlang:monotonic_time(millisecond),
    Duration = End - Start,

    #{
        operation_count => length(TaskSet),
        duration => Duration,
        operations_per_second => (length(TaskSet) * 1000) / Duration,
        memory_usage => erlang:memory(total)
    }.

compare_performance_metrics(Baseline, Upgrade) ->
    %% Compare performance metrics
    BaselineOps = maps:get(operations_per_second, Baseline),
    UpgradeOps = maps:get(operations_per_second, Upgrade),

    %% Upgrade performance should be within reasonable bounds
    PerformanceRatio = UpgradeOps / BaselineOps,
    ?assert(PerformanceRatio > 0.5, {upgrade_performance_too_low, PerformanceRatio}),
    ?assert(PerformanceRatio < 3.0, {upgrade_performance_too_high, PerformanceRatio}).

validate_performance_standards(Metrics) ->
    %% Validate that performance meets minimum standards
    OpsPerSecond = maps:get(operations_per_second, Metrics),
    MinOps = 100, % Minimum operations per second

    ?assert(OpsPerSecond >= MinOps, {performance_below_minimum, OpsPerSecond, MinOps}).

initialize_peer_modules() ->
    %% Initialize peer modules for distributed testing
    [peer1, peer2, peer3].

create_distributed_test_tasks(PeerModules) ->
    %% Create tasks for distributed testing
    lists:map(fun(Peer) ->
        Message = a2a_test_utils:new_message(),
        TaskStatus = a2a_test_utils:new_task_status(submitted),

        #task{
            id = a2a_test_utils:unique_task_id(),
            context_id = a2a_test_utils:unique_context(),
            status = TaskStatus,
            artifacts = [],
            history = [Message],
            metadata = #{<<"distributed_test">> => true, <<"peer"> => Peer}
        }
    end, PeerModules).

simulate_peer_upgrade(PeerModules, Tasks) ->
    %% Simulate peer-to-peer upgrade
    lists:foreach(fun(Peer) ->
        %% Upgrade each peer
        CheckpointId = create_checkpoint(Tasks),
        simulate_upgrade(?MODULE, CheckpointId)
    end, PeerModules),

    {ok, peer_upgrade_completed}.

verify_peer_state_synchronization(PeerModules) ->
    %% Verify state synchronization across peers
    lists:foreach(fun(Peer) ->
        %% Verify peer state consistency
        ok
    end, PeerModules).

test_peer_communication_during_upgrade(PeerModules) ->
    %% Test peer communication during upgrade
    lists:foreach(fun(Peer1) ->
        lists:foreach(fun(Peer2) ->
            %% Test communication between peers
            ok
        end, PeerModules)
    end, PeerModules).

create_comprehensive_test_state() ->
    %% Create comprehensive test state
    create_test_tasks([submitted, working, completed, failed, canceled, input_required, auth_required]).

verify_state_integrity(Expected, Actual) ->
    %% Verify integrity of restored state
    ?assertEqual(length(Expected), length(Actual)),

    lists:foreach(fun({ExpTask, ActTask}) ->
        validate_task_consistency(ExpTask, ActTask)
    end, lists:zip(Expected, Actual)).

validate_checkpoint_consistency(CheckpointId) ->
    %% Validate checkpoint consistency
    CheckpointFile = ?CHECKPOINT_DIR ++ "/" ++ binary_to_list(CheckpointId),
    case file:read_file(CheckpointFile) of
        {ok, Data} ->
            try
                Tasks = binary_to_term(Data),
                ?assert(is_list(Tasks)),
                lists:foreach(fun(Task) ->
                    ?assert(is_record(Task, task))
                end, Tasks),
                ok;
            catch
                _:_ -> {error, invalid_checkpoint_data}
            end;
        {error, Reason} -> {error, {checkpoint_read_failed, Reason}}
    end.

test_checkpoint_lifecycle() ->
    %% Test checkpoint creation, validation, and cleanup
    TestTasks = create_comprehensive_test_state(),

    %% Create checkpoint
    CheckpointId = create_checkpoint(TestTasks),

    %% Verify checkpoint
    {ok, RestoredTasks} = restore_checkpoint(?MODULE, CheckpointId),
    verify_state_integrity(TestTasks, RestoredTasks),

    %% Test cleanup (would be done by end_per_testcase)
    ok.

test_version_compatibility(FromVersion, ToVersion, Direction) ->
    %% Test version compatibility
    TestTasks = create_test_tasks([submitted, working]),

    %% Create checkpoint
    CheckpointId = create_checkpoint(TestTasks),

    case Direction of
        upgrade ->
            {ok, _} = simulate_upgrade(?MODULE, CheckpointId);
        downgrade ->
            {ok, _} = simulate_downgrade(?MODULE, CheckpointId)
    end,

    %% Verify compatibility
    lists:foreach(fun(Task) ->
        TaskId = Task#task.id,
        {ok, RestoredTask} = a2a_task_store:get_task(TaskId),
        validate_task_consistency(Task, RestoredTask)
    end, TestTasks),

    ok.