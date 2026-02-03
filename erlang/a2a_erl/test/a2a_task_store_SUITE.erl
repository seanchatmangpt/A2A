%%% @doc A2A Task Store Test Suite
%%%
%%% Comprehensive Common Test suite for testing the ETS-based task storage.
%%% Tests cover all 4 ETS tables: a2a_tasks, a2a_task_pids, a2a_task_contexts,
%%% and a2a_push_configs.
%%%
%%% OTP 28 features: Tests verify write_concurrency and read_concurrency options.
-module(a2a_task_store_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include("../include/a2a.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases - Table Initialization & Setup
-export([
    test_tables_initialized/1,
    test_table_properties/1
]).

%% Test cases - Task Registration & Lifecycle
-export([
    test_register_task/1,
    test_unregister_task/1,
    test_get_task/1,
    test_get_task_not_found/1
]).

%% Test cases - Task Updates & CRUD
-export([
    test_update_task/1,
    test_delete_task/1,
    test_delete_nonexistent_task/1,
    test_get_task_pid/1
]).

%% Test cases - Task Listing & Filtering
-export([
    test_list_tasks_all/1,
    test_list_tasks_by_context/1,
    test_list_tasks_by_status/1,
    test_list_tasks_with_pagination/1
]).

%% Test cases - Push Notification Config
-export([
    test_add_push_config/1,
    test_get_push_config/1,
    test_list_push_configs/1,
    test_delete_push_config/1
]).

%%% ============================================================================
%%% CT Callbacks
%%% ============================================================================

all() ->
    [
        %% Table Initialization & Setup
        test_tables_initialized,
        test_table_properties,
        %% Task Registration & Lifecycle
        test_register_task,
        test_unregister_task,
        test_get_task,
        test_get_task_not_found,
        %% Task Updates & CRUD
        test_update_task,
        test_delete_task,
        test_delete_nonexistent_task,
        test_get_task_pid,
        %% Task Listing & Filtering
        test_list_tasks_all,
        test_list_tasks_by_context,
        test_list_tasks_by_status,
        test_list_tasks_with_pagination,
        %% Push Notification Config
        test_add_push_config,
        test_get_push_config,
        test_list_push_configs,
        test_delete_push_config
    ].

init_per_suite(Config) ->
    %% Start required applications
    application:ensure_all_started(crypto),

    %% Start the a2a_task_store gen_server
    {ok, _Pid} = a2a_task_store:start_link(),

    Config.

end_per_suite(_Config) ->
    %% Stop the gen_server - tables will be cleaned up
    case whereis(a2a_task_store) of
        undefined -> ok;
        Pid -> gen_server:stop(Pid)
    end,
    ok.

init_per_testcase(_TestCase, Config) ->
    %% Clean up tables before each test
    cleanup_all_tables(),
    Config.

end_per_testcase(_TestCase, _Config) ->
    %% Clean up tables after each test
    cleanup_all_tables(),
    ok.

%%% ============================================================================
%%% Test Cases - Table Initialization & Setup
%%% ============================================================================

%% @doc Verify all 4 ETS tables are created with correct names
test_tables_initialized(_Config) ->
    %% Check that all tables exist
    ?assert(ets:info(a2a_tasks) =/= undefined),
    ?assert(ets:info(a2a_task_pids) =/= undefined),
    ?assert(ets:info(a2a_task_contexts) =/= undefined),
    ?assert(ets:info(a2a_push_configs) =/= undefined),

    %% Verify table info returns proper data
    ?assert(is_integer(ets:info(a2a_tasks, size))),
    ?assert(is_integer(ets:info(a2a_task_pids, size))),
    ?assert(is_integer(ets:info(a2a_task_contexts, size))),
    ?assert(is_integer(ets:info(a2a_push_configs, size))),

    ok.

%% @doc Verify table types and concurrency settings (OTP 28 features)
test_table_properties(_Config) ->
    %% Check a2a_tasks table properties
    ?assertEqual(set, ets:info(a2a_tasks, type)),
    ?assertEqual(public, ets:info(a2a_tasks, protection)),
    ?assertEqual(named_table, ets:info(a2a_tasks, named_table)),
    %% OTP 28: write_concurrency and read_concurrency
    WriteConcurrencyTasks = ets:info(a2a_tasks, write_concurrency),
    ReadConcurrencyTasks = ets:info(a2a_tasks, read_concurrency),
    ?assert(WriteConcurrencyTasks =:= true orelse WriteConcurrencyTasks =:= auto),
    ?assertEqual(true, ReadConcurrencyTasks),

    %% Check a2a_task_pids table properties
    ?assertEqual(set, ets:info(a2a_task_pids, type)),
    ?assertEqual(public, ets:info(a2a_task_pids, protection)),
    ?assertEqual(named_table, ets:info(a2a_task_pids, named_table)),

    %% Check a2a_task_contexts table properties (bag type)
    ?assertEqual(bag, ets:info(a2a_task_contexts, type)),
    ?assertEqual(public, ets:info(a2a_task_contexts, protection)),
    ?assertEqual(named_table, ets:info(a2a_task_contexts, named_table)),

    %% Check a2a_push_configs table properties
    ?assertEqual(set, ets:info(a2a_push_configs, type)),
    ?assertEqual(public, ets:info(a2a_push_configs, protection)),
    ?assertEqual(named_table, ets:info(a2a_push_configs, named_table)),

    ok.

%%% ============================================================================
%%% Test Cases - Task Registration & Lifecycle
%%% ============================================================================

%% @doc Register a task with its gen_statem pid
test_register_task(_Config) ->
    TaskId = <<"task-001">>,
    Pid = spawn(fun() -> timer:sleep(1000) end),

    %% Register the task
    ok = a2a_task_store:register_task(TaskId, Pid),

    %% Verify it's in the PIDS table
    [{TaskId, Pid}] = ets:lookup(a2a_task_pids, TaskId),

    %% Verify we can retrieve it
    {ok, RetrievedPid} = a2a_task_store:get_task_pid(TaskId),
    ?assertEqual(Pid, RetrievedPid),

    ok.

%% @doc Unregister a task (removes from PIDS table)
test_unregister_task(_Config) ->
    TaskId = <<"task-002">>,
    Pid = spawn(fun() -> timer:sleep(1000) end),

    %% Register first
    ok = a2a_task_store:register_task(TaskId, Pid),
    ?assertEqual([{TaskId, Pid}], ets:lookup(a2a_task_pids, TaskId)),

    %% Unregister
    ok = a2a_task_store:unregister_task(TaskId),

    %% Verify removal
    ?assertEqual([], ets:lookup(a2a_task_pids, TaskId)),

    %% Verify get_task_pid returns not_found
    ?assertEqual({error, not_found}, a2a_task_store:get_task_pid(TaskId)),

    ok.

%% @doc Get task by ID after storing it
test_get_task(_Config) ->
    TaskId = <<"task-003">>,
    Task = create_test_task(TaskId, <<"context-001">>, ?TASK_STATE_WORKING),

    %% Store task directly in ETS (bypassing gen_statem for testing)
    ets:insert(a2a_tasks, {TaskId, Task}),

    %% Retrieve using API
    {ok, RetrievedTask} = a2a_task_store:get_task(TaskId),

    %% Verify data integrity
    ?assertEqual(TaskId, RetrievedTask#task.id),
    ?assertEqual(<<"context-001">>, RetrievedTask#task.context_id),
    ?assertEqual(?TASK_STATE_WORKING, (RetrievedTask#task.status)#task_status.state),

    ok.

%% @doc Attempt to get a non-existent task
test_get_task_not_found(_Config) ->
    %% Try to get a task that doesn't exist
    ?assertEqual({error, not_found}, a2a_task_store:get_task(<<"nonexistent-task">>)),

    %% Try with empty binary
    ?assertEqual({error, not_found}, a2a_task_store:get_task(<<>>)),

    ok.

%%% ============================================================================
%%% Test Cases - Task Updates & CRUD
%%% ============================================================================

%% @doc Update task record in store (main and context tables)
test_update_task(_Config) ->
    TaskId = <<"task-004">>,
    ContextId = <<"context-002">>,

    %% Create initial task
    InitialTask = create_test_task(TaskId, ContextId, ?TASK_STATE_SUBMITTED),
    ets:insert(a2a_tasks, {TaskId, InitialTask}),

    %% Update task status
    UpdatedStatus = #task_status{
        state = ?TASK_STATE_WORKING,
        timestamp = erlang:system_time(millisecond)
    },
    UpdatedTask = InitialTask#task{status = UpdatedStatus},

    %% Call update_task
    ok = a2a_task_store:update_task(UpdatedTask),

    %% Verify main table updated
    [{TaskId, RetrievedTask}] = ets:lookup(a2a_tasks, TaskId),
    ?assertEqual(?TASK_STATE_WORKING, (RetrievedTask#task.status)#task_status.state),

    %% Verify context index updated
    ContextMatches = ets:match(a2a_task_contexts, {ContextId, TaskId, '_'}),
    ?assertEqual(1, length(ContextMatches)),

    ok.

%% @doc Delete a task and verify removal from all tables
test_delete_task(_Config) ->
    TaskId = <<"task-005">>,
    ContextId = <<"context-003">>,
    Pid = spawn(fun() -> timer:sleep(1000) end),

    %% Setup: insert into all tables
    Task = create_test_task(TaskId, ContextId, ?TASK_STATE_WORKING),
    ets:insert(a2a_tasks, {TaskId, Task}),
    ets:insert(a2a_task_pids, {TaskId, Pid}),
    ets:insert(a2a_task_contexts, {ContextId, TaskId, 12345}),

    %% Verify setup
    ?assertEqual([{TaskId, Task}], ets:lookup(a2a_tasks, TaskId)),
    ?assertEqual([{TaskId, Pid}], ets:lookup(a2a_task_pids, TaskId)),
    ?assertEqual(1, length(ets:match(a2a_task_contexts, {ContextId, TaskId, '_'}))),

    %% Delete task
    ok = a2a_task_store:delete_task(TaskId),

    %% Verify removal from all tables
    ?assertEqual([], ets:lookup(a2a_tasks, TaskId)),
    ?assertEqual([], ets:lookup(a2a_task_pids, TaskId)),
    ?assertEqual([], ets:match(a2a_task_contexts, {ContextId, TaskId, '_'})),

    %% Verify get returns not_found
    ?assertEqual({error, not_found}, a2a_task_store:get_task(TaskId)),

    ok.

%% @doc Delete a non-existent task (should be idempotent)
test_delete_nonexistent_task(_Config) ->
    %% Delete a task that doesn't exist - should not error
    ok = a2a_task_store:delete_task(<<"nonexistent-task">>),

    %% Verify no side effects
    ?assertEqual(0, ets:info(a2a_tasks, size)),

    %% Try again - still should not error
    ok = a2a_task_store:delete_task(<<"another-nonexistent">>),

    ok.

%% @doc Get task pid with process alive check
test_get_task_pid(_Config) ->
    TaskId = <<"task-006">>,

    %% Test with live process
    LivePid = spawn(fun() -> timer:sleep(1000) end),
    ets:insert(a2a_task_pids, {TaskId, LivePid}),

    {ok, RetrievedPid} = a2a_task_store:get_task_pid(TaskId),
    ?assertEqual(LivePid, RetrievedPid),

    %% Test with dead process
    DeadPid = spawn(fun() -> ok end),
    timer:sleep(10), % Ensure process terminates
    ets:insert(a2a_task_pids, {<<"task-007">>, DeadPid}),

    %% Should return not_found for dead process
    ?assertEqual({error, not_found}, a2a_task_store:get_task_pid(<<"task-007">>)),

    %% Test with non-existent task
    ?assertEqual({error, not_found}, a2a_task_store:get_task_pid(<<"nonexistent-pid-task">>)),

    ok.

%%% ============================================================================
%%% Test Cases - Task Listing & Filtering
%%% ============================================================================

%% @doc List all tasks without filters
test_list_tasks_all(_Config) ->
    %% Create multiple tasks with different timestamps
    Now = erlang:system_time(millisecond),
    Task1 = create_test_task_with_timestamp(<<"task-001">>, <<"ctx-1">>, ?TASK_STATE_WORKING, Now),
    Task2 = create_test_task_with_timestamp(<<"task-002">>, <<"ctx-1">>, ?TASK_STATE_COMPLETED, Now - 1000),
    Task3 = create_test_task_with_timestamp(<<"task-003">>, <<"ctx-2">>, ?TASK_STATE_WORKING, Now - 2000),

    %% Insert tasks
    lists:foreach(fun(T) ->
        TaskId = T#task.id,
        ContextId = T#task.context_id,
        Ts = (T#task.status)#task_status.timestamp,
        ets:insert(a2a_tasks, {TaskId, T}),
        ets:insert(a2a_task_contexts, {ContextId, TaskId, Ts})
    end, [Task1, Task2, Task3]),

    %% List all tasks
    {ok, Tasks, NextToken} = a2a_task_store:list_tasks(#{}),

    %% Should return all 3 tasks sorted by timestamp descending
    ?assertEqual(3, length(Tasks)),
    ?assertEqual(<<>>, NextToken), % No pagination

    %% Verify order (newest first)
    ?assertEqual(<<"task-001">>, (lists:nth(1, Tasks))#task.id),
    ?assertEqual(<<"task-002">>, (lists:nth(2, Tasks))#task.id),
    ?assertEqual(<<"task-003">>, (lists:nth(3, Tasks))#task.id),

    ok.

%% @doc List tasks filtered by context_id
test_list_tasks_by_context(_Config) ->
    Now = erlang:system_time(millisecond),

    %% Create tasks in different contexts
    Task1 = create_test_task_with_timestamp(<<"task-ctx1-a">>, <<"context-1">>, ?TASK_STATE_WORKING, Now),
    Task2 = create_test_task_with_timestamp(<<"task-ctx1-b">>, <<"context-1">>, ?TASK_STATE_COMPLETED, Now - 1000),
    Task3 = create_test_task_with_timestamp(<<"task-ctx2-a">>, <<"context-2">>, ?TASK_STATE_WORKING, Now - 500),

    lists:foreach(fun(T) ->
        TaskId = T#task.id,
        ContextId = T#task.context_id,
        Ts = (T#task.status)#task_status.timestamp,
        ets:insert(a2a_tasks, {TaskId, T}),
        ets:insert(a2a_task_contexts, {ContextId, TaskId, Ts})
    end, [Task1, Task2, Task3]),

    %% List tasks for context-1
    {ok, Context1Tasks, _} = a2a_task_store:list_tasks(#{context_id => <<"context-1">>}),

    %% Should return only 2 tasks from context-1
    ?assertEqual(2, length(Context1Tasks)),
    ?assert(lists:all(fun(T) -> T#task.context_id =:= <<"context-1">> end, Context1Tasks)),

    %% List tasks for context-2
    {ok, Context2Tasks, _} = a2a_task_store:list_tasks(#{context_id => <<"context-2">>}),

    %% Should return only 1 task from context-2
    ?assertEqual(1, length(Context2Tasks)),
    ?assertEqual(<<"task-ctx2-a">>, (lists:nth(1, Context2Tasks))#task.id),

    ok.

%% @doc List tasks filtered by status
test_list_tasks_by_status(_Config) ->
    Now = erlang:system_time(millisecond),

    %% Create tasks with different statuses
    Task1 = create_test_task_with_timestamp(<<"task-working-1">>, <<"ctx-1">>, ?TASK_STATE_WORKING, Now),
    Task2 = create_test_task_with_timestamp(<<"task-working-2">>, <<"ctx-1">>, ?TASK_STATE_WORKING, Now - 1000),
    Task3 = create_test_task_with_timestamp(<<"task-completed-1">>, <<"ctx-1">>, ?TASK_STATE_COMPLETED, Now - 500),
    Task4 = create_test_task_with_timestamp(<<"task-failed-1">>, <<"ctx-1">>, ?TASK_STATE_FAILED, Now - 2000),

    lists:foreach(fun(T) ->
        TaskId = T#task.id,
        ContextId = T#task.context_id,
        Ts = (T#task.status)#task_status.timestamp,
        ets:insert(a2a_tasks, {TaskId, T}),
        ets:insert(a2a_task_contexts, {ContextId, TaskId, Ts})
    end, [Task1, Task2, Task3, Task4]),

    %% List only working tasks
    {ok, WorkingTasks, _} = a2a_task_store:list_tasks(#{status => ?TASK_STATE_WORKING}),

    ?assertEqual(2, length(WorkingTasks)),
    ?assert(lists:all(fun(T) ->
        (T#task.status)#task_status.state =:= ?TASK_STATE_WORKING
    end, WorkingTasks)),

    %% List only completed tasks
    {ok, CompletedTasks, _} = a2a_task_store:list_tasks(#{status => ?TASK_STATE_COMPLETED}),

    ?assertEqual(1, length(CompletedTasks)),
    ?assertEqual(?TASK_STATE_COMPLETED, ((lists:nth(1, CompletedTasks))#task.status)#task_status.state),

    ok.

%% @doc List tasks with pagination
test_list_tasks_with_pagination(_Config) ->
    Now = erlang:system_time(millisecond),

    %% Create 5 tasks
    Tasks = lists:map(fun(N) ->
        TaskId = list_to_binary(io_lib:format("task-~2..0B", [N])),
        create_test_task_with_timestamp(TaskId, <<"ctx-1">>, ?TASK_STATE_WORKING, Now - N * 1000)
    end, lists:seq(1, 5)),

    lists:foreach(fun(T) ->
        TaskId = T#task.id,
        ContextId = T#task.context_id,
        Ts = (T#task.status)#task_status.timestamp,
        ets:insert(a2a_tasks, {TaskId, T}),
        ets:insert(a2a_task_contexts, {ContextId, TaskId, Ts})
    end, Tasks),

    %% First page - 2 items
    {ok, Page1, NextToken1} = a2a_task_store:list_tasks(#{page_size => 2}),
    ?assertEqual(2, length(Page1)),
    ?assertEqual(<<"2">>, NextToken1),

    %% Second page
    {ok, Page2, NextToken2} = a2a_task_store:list_tasks(#{page_size => 2, page_token => NextToken1}),
    ?assertEqual(2, length(Page2)),
    ?assertEqual(<<"4">>, NextToken2),

    %% Third page (1 item)
    {ok, Page3, NextToken3} = a2a_task_store:list_tasks(#{page_size => 2, page_token => NextToken2}),
    ?assertEqual(1, length(Page3)),
    ?assertEqual(<<>>, NextToken3), % Empty token = last page

    %% Verify no duplicates across pages
    AllIds = lists:concat([lists:map(fun(T) -> T#task.id end, P) || P <- [Page1, Page2, Page3]]),
    ?assertEqual(5, length(lists:usort(AllIds))),

    ok.

%%% ============================================================================
%%% Test Cases - Push Notification Config
%%% ============================================================================

%% @doc Add push notification config for a task
test_add_push_config(_Config) ->
    TaskId = <<"task-push-001">>,
    Config = create_test_push_config(<<"config-001">>),

    %% Add config
    ok = a2a_task_store:add_push_config(TaskId, Config),

    %% Verify in table
    [{{TaskId, <<"config-001">>}, RetrievedConfig}] = ets:lookup(a2a_push_configs, {TaskId, <<"config-001">>}),

    ?assertEqual(<<"config-001">>, RetrievedConfig#task_push_notification_config.id),
    ?assertEqual(<<"https://example.com/webhook">>, RetrievedConfig#task_push_notification_config.push_notification_config#push_notification_config.url),

    ok.

%% @doc Get push notification config by task_id and config_id
test_get_push_config(_Config) ->
    TaskId = <<"task-push-002">>,
    ConfigId = <<"config-002">>,
    Config = create_test_push_config(ConfigId),

    %% Add config
    ok = a2a_task_store:add_push_config(TaskId, Config),

    %% Get config
    {ok, RetrievedConfig} = a2a_task_store:get_push_config(TaskId, ConfigId),

    ?assertEqual(ConfigId, RetrievedConfig#task_push_notification_config.id),

    %% Try non-existent config
    ?assertEqual({error, not_found}, a2a_task_store:get_push_config(<<"nonexistent-task">>, <<"nonexistent-config">>)),
    ?assertEqual({error, not_found}, a2a_task_store:get_push_config(TaskId, <<"wrong-config-id">>)),

    ok.

%% @doc List all push notification configs for a task
test_list_push_configs(_Config) ->
    TaskId = <<"task-push-003">>,

    %% Add multiple configs
    Config1 = create_test_push_config(<<"config-001">>),
    Config2 = create_test_push_config(<<"config-002">>),
    Config3 = create_test_push_config(<<"config-003">>),

    ok = a2a_task_store:add_push_config(TaskId, Config1),
    ok = a2a_task_store:add_push_config(TaskId, Config2),
    ok = a2a_task_store:add_push_config(TaskId, Config3),

    %% List configs
    Configs = a2a_task_store:list_push_configs(TaskId),

    ?assertEqual(3, length(Configs)),

    %% Verify all are present
    ConfigIds = [C#task_push_notification_config.id || C <- Configs],
    ?assert(lists:member(<<"config-001">>, ConfigIds)),
    ?assert(lists:member(<<"config-002">>, ConfigIds)),
    ?assert(lists:member(<<"config-003">>, ConfigIds)),

    %% List for non-existent task
    ?assertEqual([], a2a_task_store:list_push_configs(<<"nonexistent-task">>)),

    ok.

%% @doc Delete push notification config
test_delete_push_config(_Config) ->
    TaskId = <<"task-push-004">>,
    ConfigId = <<"config-delete-001">>,
    Config = create_test_push_config(ConfigId),

    %% Add config
    ok = a2a_task_store:add_push_config(TaskId, Config),
    ?assertEqual(1, length(a2a_task_store:list_push_configs(TaskId))),

    %% Delete config
    ok = a2a_task_store:delete_push_config(TaskId, ConfigId),

    %% Verify removal
    ?assertEqual([], a2a_task_store:list_push_configs(TaskId)),
    ?assertEqual({error, not_found}, a2a_task_store:get_push_config(TaskId, ConfigId)),

    %% Delete non-existent config (should not error)
    ok = a2a_task_store:delete_push_config(TaskId, <<"nonexistent-config">>),
    ok = a2a_task_store:delete_push_config(<<"nonexistent-task">>, ConfigId),

    ok.

%%% ============================================================================
%%% Helper Functions
%%% ============================================================================

%% @doc Create a test task record
create_test_task(TaskId, ContextId, State) ->
    Timestamp = erlang:system_time(millisecond),
    create_test_task_with_timestamp(TaskId, ContextId, State, Timestamp).

%% @doc Create a test task with specific timestamp
create_test_task_with_timestamp(TaskId, ContextId, State, Timestamp) ->
    Status = #task_status{
        state = State,
        timestamp = Timestamp
    },
    #task{
        id = TaskId,
        context_id = ContextId,
        status = Status,
        artifacts = [],
        history = [],
        metadata = #{}
    }.

%% @doc Create a test push notification config
create_test_push_config(ConfigId) ->
    PushConfig = #push_notification_config{
        id = ConfigId,
        url = <<"https://example.com/webhook">>,
        token = <<"test-token-123">>
    },
    #task_push_notification_config{
        id = ConfigId,
        task_id = <<"task-for-push">>,
        push_notification_config = PushConfig
    }.

%% @doc Clean up all ETS tables
cleanup_all_tables() ->
    %% Clear all tables
    ets:delete_all_objects(a2a_tasks),
    ets:delete_all_objects(a2a_task_pids),
    ets:delete_all_objects(a2a_task_contexts),
    ets:delete_all_objects(a2a_push_configs),
    ok.
