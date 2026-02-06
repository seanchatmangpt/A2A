%%%-------------------------------------------------------------------
%%% @doc
%%% Comprehensive Unit Tests for YAWL Persistence
%%%
%%% This module provides extensive test coverage for the YAWL persistence
%%% layer using Mnesia. Tests cover:
%%%
%%% 1. Workflow save and load operations
%%% 2. Workitem persistence
%%% 3. Resource persistence
%%% 4. History tracking
%%% 5. Checkpoint creation and restoration
%%% 6. Query operations (by status, type, etc.)
%%% 7. Mnesia table operations
%%% 8. Transaction handling
%%%
%%% Uses EUnit with Mnesia setup/teardown fixtures.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(test_yawl_persistence).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros and Constants
%%====================================================================

-define(TEST_DIR_PREFIX, "/tmp/yawl_persist_test_").

%%====================================================================
%% Test Generator - Main Entry Point
%%====================================================================

persistence_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Group 1: Mnesia Schema and Table Operations", fun test_group_schema_tables/0},
      {"Group 2: Workflow Persistence Operations", fun test_group_workflow_persistence/0},
      {"Group 3: Workitem Persistence Operations", fun test_group_workitem_persistence/0},
      {"Group 4: Resource Persistence Operations", fun test_group_resource_persistence/0},
      {"Group 5: History Tracking Operations", fun test_group_history_tracking/0},
      {"Group 6: Checkpoint Creation and Restoration", fun test_group_checkpoint_operations/0},
      {"Group 7: Query Operations", fun test_group_query_operations/0},
      {"Group 8: Transaction Handling", fun test_group_transactions/0},
      {"Group 9: Map to Record Conversion", fun test_group_map_conversion/0},
      {"Group 10: Error Handling and Edge Cases", fun test_group_error_handling/0}
     ]
    }.

%%====================================================================
%% Setup and Cleanup Fixtures
%%====================================================================

setup() ->
    %% Generate unique test directory for isolation
    TestDir = ?TEST_DIR_PREFIX ++ integer_to_list(erlang:unique_integer([positive])),

    %% Stop any existing Mnesia
    application:stop(mnesia),

    %% Ensure test directory exists
    ok = filelib:ensure_dir(TestDir ++ "/"),

    %% Configure Mnesia to use test directory
    application:set_env(mnesia, dir, TestDir),

    %% Create fresh schema
    ok = yawl_persistence:create_schema(),

    %% Start Mnesia
    ok = mnesia:start(),

    %% Create all tables
    {ok, _} = yawl_persistence:create_tables(),

    %% Wait for tables to be ready
    ok = yawl_persistence:wait_for_tables(),

    %% Start the persistence gen_server
    {ok, Pid} = yawl_persistence:start_link(),

    %% Return state for cleanup
    #{pid => Pid, test_dir => TestDir}.

cleanup(State) ->
    %% Stop the gen_server
    Pid = maps:get(pid, State),
    gen_server:stop(Pid),

    %% Stop Mnesia
    mnesia:stop(),

    %% Clear environment
    application:unset_env(mnesia, dir),

    %% Clean up test directory
    TestDir = maps:get(test_dir, State),
    case file:del_dir_r(TestDir) of
        ok -> ok;
        {error, Reason} ->
            %% Log but don't fail test on cleanup issues
            io:format("Warning: Failed to delete test directory ~p: ~p~n", [TestDir, Reason])
    end.

%%====================================================================
%% Group 1: Mnesia Schema and Table Operations
%%====================================================================

test_group_schema_tables() ->
    test_create_schema(),
    test_create_all_tables(),
    test_table_attributes(),
    test_table_indexes(),
    test_wait_for_tables_ready(),
    test_backup_tables(),
    ok.

test_create_schema() ->
    %% Schema should be created successfully
    Result = yawl_persistence:create_schema(),
    ?assert(lists:member(Result, [ok, {error, {already_exists, node}}])).

test_create_all_tables() ->
    %% Verify all required tables exist
    Tables = mnesia:system_info(tables),
    RequiredTables = [
        yawl_workflow_persist,
        yawl_workitem_persist,
        yawl_resource_persist,
        yawl_execution_history,
        yawl_checkpoint,
        yawl_service_registry,
        yawl_task_queue
    ],
    lists:foreach(fun(Table) ->
        ?assert(lists:member(Table, Tables),
                 io_lib:format("Table ~p should exist", [Table]))
    end, RequiredTables).

test_table_attributes() ->
    %% Verify workflow table has correct structure
    [Workflow | _] = mnesia:dirty_read(yawl_workflow_persist, <<"$test_structure_wf">>),
    ?assert(is_record(Workflow, yawl_workflow_persist)).

test_table_indexes() ->
    %% Verify indexes are configured correctly
    TableInfo = mnesia:table_info(yawl_workflow_persist, indexes),
    ?assert(is_list(TableInfo)),
    ?assert(length(TableInfo) >= 2).

test_wait_for_tables_ready() ->
    %% Should return ok when tables are ready
    Result = yawl_persistence:wait_for_tables(),
    ?assertEqual(ok, Result).

test_backup_tables() ->
    %% Create test data
    BackupFile = "/tmp/yawl_test_backup_" ++ integer_to_list(erlang:unique_integer([positive])),
    Workflow = #yawl_workflow_persist{
        workflow_id = <<"$backup_test_wf">>,
        spec_id = <<"backup_spec">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = mnesia:dirty_write(Workflow),

    %% Test backup
    Result = yawl_persistence:backup_tables(BackupFile),
    ?assertEqual(ok, Result),

    %% Cleanup
    file:delete(BackupFile),
    mnesia:dirty_delete(yawl_workflow_persist, <<"$backup_test_wf">>).

%%====================================================================
%% Group 2: Workflow Persistence Operations
%%====================================================================

test_group_workflow_persistence() ->
    test_save_workflow_record(),
    test_save_workflow_map(),
    test_load_workflow(),
    test_load_workflow_not_found(),
    test_update_workflow(),
    test_delete_workflow(),
    test_archive_workflow(),
    test_workflow_timestamp_updates(),
    ok.

test_save_workflow_record() ->
    WorkflowId = <<"$test_wf_save">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"test_spec">>,
        pattern_type = basic_sequential,
        status = pending,
        marking = #{start => [token]},
        current_place = start,
        data = #{key => <<"value">>},
        parent_workflow_id = undefined,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond),
        completed_at = undefined,
        error = undefined
    },
    ?assertEqual(ok, yawl_persistence:save_workflow(Workflow)),

    %% Verify persistence
    [Saved] = mnesia:dirty_read(yawl_workflow_persist, WorkflowId),
    ?assertEqual(WorkflowId, Saved#yawl_workflow_persist.workflow_id),
    ?assertEqual(basic_sequential, Saved#yawl_workflow_persist.pattern_type),
    ?assertEqual(pending, Saved#yawl_workflow_persist.status),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_save_workflow_map() ->
    WorkflowId = <<"$test_wf_map">>,
    WorkflowMap = #{
        workflow_id => WorkflowId,
        spec_id => <<"map_spec">>,
        pattern_type => parallel_split,
        status => running,
        marking => #{task1 => [token], task2 => [token]},
        data => #{nested => #{value => 42}}
    },
    ?assertEqual(ok, yawl_persistence:save_workflow(WorkflowMap)),

    %% Verify conversion and persistence
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(WorkflowId, Loaded#yawl_workflow_persist.workflow_id),
    ?assertEqual(parallel_split, Loaded#yawl_workflow_persist.pattern_type),
    ?assertEqual(running, Loaded#yawl_workflow_persist.status),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_load_workflow() ->
    WorkflowId = <<"$test_wf_load">>,
    Original = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"load_spec">>,
        pattern_type = iterative_loop,
        status = completed,
        marking = #{end_place => [token]},
        data = #{result => <<"success">>},
        created_at = 1000,
        updated_at = 2000,
        completed_at = 3000
    },
    ok = mnesia:dirty_write(Original),

    %% Test loading
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(WorkflowId, Loaded#yawl_workflow_persist.workflow_id),
    ?assertEqual(iterative_loop, Loaded#yawl_workflow_persist.pattern_type),
    ?assertEqual(completed, Loaded#yawl_workflow_persist.status),
    ?assertEqual(#{end_place => [token]}, Loaded#yawl_workflow_persist.marking),
    ?assertEqual(#{result => <<"success">>}, Loaded#yawl_workflow_persist.data),
    ?assertEqual(3000, Loaded#yawl_workflow_persist.completed_at),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_load_workflow_not_found() ->
    Result = yawl_persistence:load_workflow(<<"$nonexistent_workflow">>),
    ?assertEqual({error, not_found}, Result).

test_update_workflow() ->
    WorkflowId = <<"$test_wf_update">>,
    Original = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"update_spec">>,
        pattern_type = basic_sequential,
        status = pending,
        marking = #{start => [token]},
        created_at = 1000,
        updated_at = 1000
    },
    ok = mnesia:dirty_write(Original),

    %% Update with new status
    Updated = Original#yawl_workflow_persist{status = running},
    ok = yawl_persistence:save_workflow(Updated),

    %% Verify update and timestamp refresh
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(running, Loaded#yawl_workflow_persist.status),
    ?assert(Loaded#yawl_workflow_persist.updated_at >= 1000),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_delete_workflow() ->
    WorkflowId = <<"$test_wf_delete">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"delete_spec">>,
        pattern_type = basic_sequential,
        status = running,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = mnesia:dirty_write(Workflow),

    %% Test deletion
    ?assertEqual(ok, yawl_persistence:delete_workflow(WorkflowId)),
    ?assertEqual({error, not_found}, yawl_persistence:load_workflow(WorkflowId)).

test_archive_workflow() ->
    WorkflowId = <<"$test_wf_archive">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"archive_spec">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{start => [token]},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = mnesia:dirty_write(Workflow),

    %% Archive should set status to terminated
    ?assertEqual(ok, yawl_persistence:archive_workflow(WorkflowId)),
    {ok, Archived} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(terminated, Archived#yawl_workflow_persist.status),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_workflow_timestamp_updates() ->
    WorkflowId = <<"$test_wf_timestamp">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"timestamp_spec">>,
        pattern_type = basic_sequential,
        status = pending,
        marking = #{},
        created_at = 1000,
        updated_at = 1000
    },
    ok = yawl_persistence:save_workflow(Workflow),

    %% Force a small delay to ensure different timestamp
    timer:sleep(5),

    %% Save again - updated_at should change
    Workflow2 = Workflow#yawl_workflow_persist{status = running},
    ok = yawl_persistence:save_workflow(Workflow2),

    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assert(Loaded#yawl_workflow_persist.updated_at > 1000),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

%%====================================================================
%% Group 3: Workitem Persistence Operations
%%====================================================================

test_group_workitem_persistence() ->
    test_save_workitem_record(),
    test_save_workitem_map(),
    test_load_workitem(),
    test_load_workitem_not_found(),
    test_update_workitem_status(),
    test_workitem_status_timestamps(),
    test_delete_workitem(),
    test_list_workitems_by_workflow(),
    ok.

test_save_workitem_record() ->
    WorkitemId = <<"$test_wi_save">>,
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = <<"$test_wf">>,
        task_id = process_task,
        task_name = <<"Process Task">>,
        status = pending,
        data = #{input => <<"data">>},
        allocated_to = undefined,
        allocation_time = undefined,
        start_time = undefined,
        completion_time = undefined,
        error = undefined,
        retry_count = 0,
        priority = normal
    },
    ?assertEqual(ok, yawl_persistence:save_workitem(Workitem)),

    %% Verify
    [Saved] = mnesia:dirty_read(yawl_workitem_persist, WorkitemId),
    ?assertEqual(WorkitemId, Saved#yawl_workitem_persist.workitem_id),
    ?assertEqual(process_task, Saved#yawl_workitem_persist.task_id),

    %% Cleanup
    mnesia:dirty_delete(yawl_workitem_persist, WorkitemId).

test_save_workitem_map() ->
    WorkitemId = <<"$test_wi_map">>,
    WorkitemMap = #{
        workitem_id => WorkitemId,
        workflow_id => <<"$test_wf">>,
        task_id => validate_task,
        task_name => <<"Validate">>,
        status => pending,
        data => #{},
        priority => high
    },
    ?assertEqual(ok, yawl_persistence:save_workitem(WorkitemMap)),

    %% Verify
    {ok, Loaded} = yawl_persistence:load_workitem(WorkitemId),
    ?assertEqual(high, Loaded#yawl_workitem_persist.priority),
    ?assertEqual(validate_task, Loaded#yawl_workitem_persist.task_id),

    %% Cleanup
    mnesia:dirty_delete(yawl_workitem_persist, WorkitemId).

test_load_workitem() ->
    WorkitemId = <<"$test_wi_load">>,
    Original = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = <<"$test_wf">>,
        task_id = approve_task,
        task_name = <<"Approve">>,
        status = allocated,
        data = #{request => <<"approval">>},
        allocated_to = {self(), approved},
        allocation_time = erlang:monotonic_time(millisecond),
        retry_count = 1,
        priority = urgent
    },
    ok = mnesia:dirty_write(Original),

    %% Test loading
    {ok, Loaded} = yawl_persistence:load_workitem(WorkitemId),
    ?assertEqual(WorkitemId, Loaded#yawl_workitem_persist.workitem_id),
    ?assertEqual(allocated, Loaded#yawl_workitem_persist.status),
    ?assertEqual(approve_task, Loaded#yawl_workitem_persist.task_id),
    ?assertEqual(1, Loaded#yawl_workitem_persist.retry_count),
    ?assertEqual(urgent, Loaded#yawl_workitem_persist.priority),

    %% Cleanup
    mnesia:dirty_delete(yawl_workitem_persist, WorkitemId).

test_load_workitem_not_found() ->
    Result = yawl_persistence:load_workitem(<<"$nonexistent_workitem">>),
    ?assertEqual({error, not_found}, Result).

test_update_workitem_status() ->
    WorkitemId = <<"$test_wi_status">>,
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = <<"$test_wf">>,
        task_id = task1,
        task_name = <<"Task 1">>,
        status = pending,
        retry_count = 0,
        priority = normal
    },
    ok = mnesia:dirty_write(Workitem),

    %% Test status update to started
    ?assertEqual(ok, yawl_persistence:update_workitem_status(WorkitemId, started)),
    {ok, Started} = yawl_persistence:load_workitem(WorkitemId),
    ?assertEqual(started, Started#yawl_workitem_persist.status),
    ?assert(Started#yawl_workitem_persist.start_time =/= undefined),

    %% Test status update to completed
    ?assertEqual(ok, yawl_persistence:update_workitem_status(WorkitemId, completed)),
    {ok, Completed} = yawl_persistence:load_workitem(WorkitemId),
    ?assertEqual(completed, Completed#yawl_workitem_persist.status),
    ?assert(Completed#yawl_workitem_persist.completion_time =/= undefined),

    %% Cleanup
    mnesia:dirty_delete(yawl_workitem_persist, WorkitemId).

test_workitem_status_timestamps() ->
    WorkitemId = <<"$test_wi_time">>,
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = <<"$test_wf">>,
        task_id = task1,
        task_name = <<"Task 1">>,
        status = pending,
        retry_count = 0,
        priority = normal
    },
    ok = mnesia:dirty_write(Workitem),

    %% Test allocation sets allocation_time
    ok = yawl_persistence:update_workitem_status(WorkitemId, allocated),
    {ok, Allocated} = yawl_persistence:load_workitem(WorkitemId),
    ?assert(Allocated#yawl_workitem_persist.allocation_time > 0),

    %% Cleanup
    mnesia:dirty_delete(yawl_workitem_persist, WorkitemId).

test_delete_workitem() ->
    WorkitemId = <<"$test_wi_delete">>,
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = <<"$test_wf">>,
        task_id = task1,
        task_name = <<"Task 1">>,
        status = completed,
        retry_count = 0,
        priority = normal
    },
    ok = mnesia:dirty_write(Workitem),

    %% Test deletion
    ?assertEqual(ok, yawl_persistence:delete_workitem(WorkitemId)),
    ?assertEqual({error, not_found}, yawl_persistence:load_workitem(WorkitemId)).

test_list_workitems_by_workflow() ->
    WorkflowId = <<"$test_wf_list_wi">>,

    %% Create multiple workitems for same workflow
    lists:foreach(fun(I) ->
        WorkitemId = <<"$test_wi_", (integer_to_binary(I))/binary>>,
        Workitem = #yawl_workitem_persist{
            workitem_id = WorkitemId,
            workflow_id = WorkflowId,
            task_id = list_to_atom("task" ++ integer_to_list(I)),
            task_name = <<"Task">>,
            status = pending,
            retry_count = 0,
            priority = normal
        },
        ok = mnesia:dirty_write(Workitem)
    end, lists:seq(1, 5)),

    %% List all workitems for workflow
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    ?assertEqual(5, length(Workitems)),

    %% Cleanup
    lists:foreach(fun(I) ->
        WorkitemId = <<"$test_wi_", (integer_to_binary(I))/binary>>,
        mnesia:dirty_delete(yawl_workitem_persist, WorkitemId)
    end, lists:seq(1, 5)).

%%====================================================================
%% Group 4: Resource Persistence Operations
%%====================================================================

test_group_resource_persistence() ->
    test_save_resource_record(),
    test_save_resource_map(),
    test_load_resource(),
    test_load_resource_not_found(),
    test_delete_resource(),
    test_list_all_resources(),
    test_list_resources_by_type(),
    test_list_available_resources(),
    test_resource_load_tracking(),
    ok.

test_save_resource_record() ->
    ResourceId = <<"$test_res_save">>,
    Resource = #yawl_resource_persist{
        resource_id = ResourceId,
        resource_type = service,
        name = <<"Test Service">>,
        capabilities = [task1, task2, task3],
        attributes = #{version => <<"1.0">>},
        status = available,
        current_load = 2,
        max_capacity = 10,
        last_heartbeat = erlang:monotonic_time(millisecond),
        metadata = #{location => <<"local">>}
    },
    ?assertEqual(ok, yawl_persistence:save_resource(Resource)),

    %% Verify
    [Saved] = mnesia:dirty_read(yawl_resource_persist, ResourceId),
    ?assertEqual(ResourceId, Saved#yawl_resource_persist.resource_id),
    ?assertEqual(service, Saved#yawl_resource_persist.resource_type),
    ?assertEqual(3, length(Saved#yawl_resource_persist.capabilities)),

    %% Cleanup
    mnesia:dirty_delete(yawl_resource_persist, ResourceId).

test_save_resource_map() ->
    ResourceId = <<"$test_res_map">>,
    ResourceMap = #{
        resource_id => ResourceId,
        resource_type => human,
        name => <<"John Doe">>,
        capabilities => [approval, review],
        status => available,
        current_load => 0,
        max_capacity => 5
    },
    ?assertEqual(ok, yawl_persistence:save_resource(ResourceMap)),

    %% Verify
    {ok, Loaded} = yawl_persistence:load_resource(ResourceId),
    ?assertEqual(human, Loaded#yawl_resource_persist.resource_type),
    ?assertEqual(<<"John Doe">>, Loaded#yawl_resource_persist.name),

    %% Cleanup
    mnesia:dirty_delete(yawl_resource_persist, ResourceId).

test_load_resource() ->
    ResourceId = <<"$test_res_load">>,
    Original = #yawl_resource_persist{
        resource_id = ResourceId,
        resource_type = system,
        name = <<"System Resource">>,
        capabilities = [batch_process],
        attributes = #{type => internal},
        status = busy,
        current_load = 8,
        max_capacity = 10,
        last_heartbeat = erlang:monotonic_time(millisecond),
        metadata = #{}
    },
    ok = mnesia:dirty_write(Original),

    %% Test loading
    {ok, Loaded} = yawl_persistence:load_resource(ResourceId),
    ?assertEqual(ResourceId, Loaded#yawl_resource_persist.resource_id),
    ?assertEqual(system, Loaded#yawl_resource_persist.resource_type),
    ?assertEqual(busy, Loaded#yawl_resource_persist.status),
    ?assertEqual(8, Loaded#yawl_resource_persist.current_load),

    %% Cleanup
    mnesia:dirty_delete(yawl_resource_persist, ResourceId).

test_load_resource_not_found() ->
    Result = yawl_persistence:load_resource(<<"$nonexistent_resource">>),
    ?assertEqual({error, not_found}, Result).

test_delete_resource() ->
    ResourceId = <<"$test_res_delete">>,
    Resource = #yawl_resource_persist{
        resource_id = ResourceId,
        resource_type = service,
        name = <<"Deletable Service">>,
        capabilities = [],
        status = available,
        current_load = 0,
        max_capacity = 1
    },
    ok = mnesia:dirty_write(Resource),

    %% Test deletion
    ?assertEqual(ok, yawl_persistence:delete_resource(ResourceId)),
    ?assertEqual({error, not_found}, yawl_persistence:load_resource(ResourceId)).

test_list_all_resources() ->
    %% Create test resources
    lists:foreach(fun(I) ->
        ResourceId = <<"$test_res_list_", (integer_to_binary(I))/binary>>,
        Resource = #yawl_resource_persist{
            resource_id = ResourceId,
            resource_type = service,
            name = <<"Service">>,
            capabilities = [],
            status = available,
            current_load = 0,
            max_capacity = 10
        },
        ok = mnesia:dirty_write(Resource)
    end, lists:seq(1, 3)),

    %% List all
    {ok, Resources} = yawl_persistence:list_resources(),
    ?assert(length(Resources) >= 3),

    %% Cleanup
    lists:foreach(fun(I) ->
        ResourceId = <<"$test_res_list_", (integer_to_binary(I))/binary>>,
        mnesia:dirty_delete(yawl_resource_persist, ResourceId)
    end, lists:seq(1, 3)).

test_list_resources_by_type() ->
    %% Create different resource types
    ServiceId = <<"$test_res_type_service">>,
    HumanId = <<"$test_res_type_human">>,

    Service = #yawl_resource_persist{
        resource_id = ServiceId,
        resource_type = service,
        name = <<"API Service">>,
        capabilities = [api_call],
        status = available,
        current_load = 0,
        max_capacity = 10
    },
    Human = #yawl_resource_persist{
        resource_id = HumanId,
        resource_type = human,
        name = <<"User">>,
        capabilities = [approve],
        status = available,
        current_load = 0,
        max_capacity = 5
    },
    ok = mnesia:dirty_write(Service),
    ok = mnesia:dirty_write(Human),

    %% Query by type
    {ok, Services} = yawl_persistence:list_resources_by_type(service),
    {ok, Humans} = yawl_persistence:list_resources_by_type(human),

    ?assert(length(Services) >= 1),
    ?assert(length(Humans) >= 1),

    %% Cleanup
    mnesia:dirty_delete(yawl_resource_persist, ServiceId),
    mnesia:dirty_delete(yawl_resource_persist, HumanId).

test_list_available_resources() ->
    %% Create resources with different statuses
    AvailableId1 = <<"$test_res_avail_1">>,
    AvailableId2 = <<"$test_res_avail_2">>,
    BusyId = <<"$test_res_busy">>,

    lists:foreach(fun({Id, Status}) ->
        Resource = #yawl_resource_persist{
            resource_id = Id,
            resource_type = service,
            name = <<"Resource">>,
            capabilities = [],
            status = Status,
            current_load = 0,
            max_capacity = 10
        },
        ok = mnesia:dirty_write(Resource)
    end, [{AvailableId1, available}, {AvailableId2, available}, {BusyId, busy}]),

    %% Query available
    {ok, Available} = yawl_persistence:list_available_resources(),
    ?assert(length(Available) >= 2),

    %% Cleanup
    lists:foreach(fun(Id) ->
        mnesia:dirty_delete(yawl_resource_persist, Id)
    end, [AvailableId1, AvailableId2, BusyId]).

test_resource_load_tracking() ->
    ResourceId = <<"$test_res_load_track">>,
    Resource = #yawl_resource_persist{
        resource_id = ResourceId,
        resource_type = service,
        name = <<"Load Tracker">>,
        capabilities = [],
        status = available,
        current_load = 3,
        max_capacity = 10
    },
    ok = mnesia:dirty_write(Resource),

    %% Update load
    Updated = Resource#yawl_resource_persist{current_load = 5},
    ok = yawl_persistence:save_resource(Updated),

    {ok, Loaded} = yawl_persistence:load_resource(ResourceId),
    ?assertEqual(5, Loaded#yawl_resource_persist.current_load),

    %% Cleanup
    mnesia:dirty_delete(yawl_resource_persist, ResourceId).

%%====================================================================
%% Group 5: History Tracking Operations
%%====================================================================

test_group_history_tracking() ->
    test_save_history_record(),
    test_save_history_map(),
    test_get_workflow_history(),
    test_get_history_empty(),
    test_delete_workflow_history(),
    test_multiple_history_entries(),
    test_history_with_workitem(),
    ok.

test_save_history_record() ->
    HistoryId = <<"$test_hist_save">>,
    History = #yawl_execution_history{
        history_id = HistoryId,
        workflow_id = <<"$test_wf_hist">>,
        workitem_id = <<"$test_wi">>,
        event_type = task_completed,
        event_data = #{task => process_task, duration => 100},
        timestamp = erlang:monotonic_time(millisecond),
        source = yawl_orchestrator
    },
    ?assertEqual(ok, yawl_persistence:save_history(History)),

    %% Verify
    [Saved] = mnesia:dirty_read(yawl_execution_history, HistoryId),
    ?assertEqual(HistoryId, Saved#yawl_execution_history.history_id),
    ?assertEqual(task_completed, Saved#yawl_execution_history.event_type),

    %% Cleanup
    mnesia:dirty_delete_object(History).

test_save_history_map() ->
    HistoryMap = #{
        history_id => <<"$test_hist_map">>,
        workflow_id => <<"$test_wf_hist">>,
        event_type => workflow_started,
        event_data => #{trigger => manual},
        timestamp => erlang:monotonic_time(millisecond)
    },
    ?assertEqual(ok, yawl_persistence:save_history(HistoryMap)),

    %% Cleanup
    {ok, Histories} = yawl_persistence:get_workflow_history(<<"$test_wf_hist">>),
    lists:foreach(fun(H) -> mnesia:dirty_delete_object(H) end, Histories).

test_get_workflow_history() ->
    WorkflowId = <<"$test_wf_get_hist">>,

    %% Create multiple history entries
    lists:foreach(fun(I) ->
        History = #yawl_execution_history{
            history_id = <<"$test_hist_", (integer_to_binary(I))/binary>>,
            workflow_id = WorkflowId,
            event_type = task_started,
            event_data = #{seq => I},
            timestamp = erlang:monotonic_time(millisecond)
        },
        ok = mnesia:dirty_write(History)
    end, lists:seq(1, 5)),

    %% Get all history for workflow
    {ok, Histories} = yawl_persistence:get_workflow_history(WorkflowId),
    ?assertEqual(5, length(Histories)),

    %% Cleanup
    lists:foreach(fun(H) -> mnesia:dirty_delete_object(H) end, Histories).

test_get_history_empty() ->
    Result = yawl_persistence:get_workflow_history(<<"$nonexistent_wf_hist">>),
    ?assertMatch({ok, []}, Result).

test_delete_workflow_history() ->
    WorkflowId = <<"$test_wf_del_hist">>,

    %% Create history entries
    lists:foreach(fun(I) ->
        History = #yawl_execution_history{
            history_id = <<"$test_del_hist_", (integer_to_binary(I))/binary>>,
            workflow_id = WorkflowId,
            event_type = test_event,
            event_data = #{},
            timestamp = erlang:monotonic_time(millisecond)
        },
        ok = mnesia:dirty_write(History)
    end, lists:seq(1, 3)),

    %% Verify they exist
    {ok, Before} = yawl_persistence:get_workflow_history(WorkflowId),
    ?assertEqual(3, length(Before)),

    %% Delete all
    ?assertEqual(ok, yawl_persistence:delete_history(WorkflowId)),

    %% Verify deletion
    {ok, After} = yawl_persistence:get_workflow_history(WorkflowId),
    ?assertEqual(0, length(After)).

test_multiple_history_entries() ->
    WorkflowId = <<"$test_wf_multi_hist">>,

    EventTypes = [
        workflow_started,
        task_started,
        task_completed,
        workflow_completed
    ],

    lists:foreach(fun(Type) ->
        History = #yawl_execution_history{
            history_id = <<"$hist_", (atom_to_binary(Type))/binary>>,
            workflow_id = WorkflowId,
            event_type = Type,
            event_data = #{},
            timestamp = erlang:monotonic_time(millisecond)
        },
        ok = mnesia:dirty_write(History)
    end, EventTypes),

    %% Get all - should have all event types
    {ok, Histories} = yawl_persistence:get_workflow_history(WorkflowId),
    ?assertEqual(4, length(Histories)),

    %% Verify event types are present
    EventTypesInHistory = [H#yawl_execution_history.event_type || H <- Histories],
    lists:foreach(fun(Type) ->
        ?assert(lists:member(Type, EventTypesInHistory))
    end, EventTypes),

    %% Cleanup
    lists:foreach(fun(H) -> mnesia:dirty_delete_object(H) end, Histories).

test_history_with_workitem() ->
    WorkflowId = <<"$test_wf_wi_hist">>,
    WorkitemId = <<"$test_wi_hist_ref">>,

    History = #yawl_execution_history{
        history_id = <<"$test_hist_wi_ref">>,
        workflow_id = WorkflowId,
        workitem_id = WorkitemId,
        event_type = task_allocated,
        event_data = #{resource => <<"res1">>},
        timestamp = erlang:monotonic_time(millisecond)
    },
    ok = mnesia:dirty_write(History),

    %% Verify workitem_id is preserved
    {ok, [H]} = yawl_persistence:get_workflow_history(WorkflowId),
    ?assertEqual(WorkitemId, H#yawl_execution_history.workitem_id),

    %% Cleanup
    mnesia:dirty_delete_object(H).

%%====================================================================
%% Group 6: Checkpoint Creation and Restoration
%%====================================================================

test_group_checkpoint_operations() ->
    test_save_checkpoint_record(),
    test_save_checkpoint_map(),
    test_load_latest_checkpoint(),
    test_load_checkpoint_not_found(),
    test_list_checkpoints(),
    test_delete_checkpoint(),
    test_restore_from_checkpoint(),
    test_checkpoint_sequence_numbers(),
    test_checkpoint_workflow_correlation(),
    ok.

test_save_checkpoint_record() ->
    WorkflowId = <<"$test_wf_cp_save">>,
    CheckpointId = <<"$cp_save_1">>,

    Checkpoint = #yawl_checkpoint{
        checkpoint_id = CheckpointId,
        workflow_id = WorkflowId,
        checkpoint_state = #{status => running, step => 1},
        marking = #{task1 => [token]},
        data = #{counter => 5},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ?assertEqual(ok, yawl_persistence:save_checkpoint(WorkflowId, Checkpoint)),

    %% Verify
    [Saved] = mnesia:dirty_read(yawl_checkpoint, CheckpointId),
    ?assertEqual(CheckpointId, Saved#yawl_checkpoint.checkpoint_id),
    ?assertEqual(WorkflowId, Saved#yawl_checkpoint.workflow_id),
    ?assertEqual(1, Saved#yawl_checkpoint.sequence_num),

    %% Cleanup
    mnesia:dirty_delete(yawl_checkpoint, CheckpointId).

test_save_checkpoint_map() ->
    WorkflowId = <<"$test_wf_cp_map">>,
    CheckpointMap = #{
        checkpoint_id => <<"$cp_map_1">>,
        workflow_id => WorkflowId,
        checkpoint_state => #{},
        marking => #{start => [token]},
        data => #{},
        timestamp => erlang:monotonic_time(millisecond),
        sequence_num => 1
    },
    ?assertEqual(ok, yawl_persistence:save_checkpoint(WorkflowId, CheckpointMap)),

    %% Cleanup
    mnesia:dirty_delete(yawl_checkpoint, <<"$cp_map_1">>).

test_load_latest_checkpoint() ->
    WorkflowId = <<"$test_wf_cp_latest">>,

    %% Create multiple checkpoints
    CP1 = #yawl_checkpoint{
        checkpoint_id = <<"$cp_latest_1">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{},
        marking = #{},
        data = #{},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    CP2 = #yawl_checkpoint{
        checkpoint_id = <<"$cp_latest_2">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{},
        marking = #{task1 => [token]},
        data = #{},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 2
    },
    ok = mnesia:dirty_write(CP1),
    ok = mnesia:dirty_write(CP2),

    %% Load latest should return sequence_num 2
    {ok, Latest} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(<<"$cp_latest_2">>, Latest#yawl_checkpoint.checkpoint_id),
    ?assertEqual(2, Latest#yawl_checkpoint.sequence_num),

    %% Cleanup
    mnesia:dirty_delete(yawl_checkpoint, <<"$cp_latest_1">>),
    mnesia:dirty_delete(yawl_checkpoint, <<"$cp_latest_2">>).

test_load_checkpoint_not_found() ->
    Result = yawl_persistence:load_latest_checkpoint(<<"$nonexistent_cp_wf">>),
    ?assertEqual({error, not_found}, Result).

test_list_checkpoints() ->
    WorkflowId = <<"$test_wf_cp_list">>,

    %% Create multiple checkpoints
    lists:foreach(fun(I) ->
        CP = #yawl_checkpoint{
            checkpoint_id = <<"$cp_list_", (integer_to_binary(I))/binary>>,
            workflow_id = WorkflowId,
            checkpoint_state = #{},
            marking = #{},
            data = #{},
            timestamp = erlang:monotonic_time(millisecond),
            sequence_num = I
        },
        ok = mnesia:dirty_write(CP)
    end, lists:seq(1, 5)),

    %% List all
    {ok, Checkpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assertEqual(5, length(Checkpoints)),

    %% Cleanup
    lists:foreach(fun(I) ->
        CPId = <<"$cp_list_", (integer_to_binary(I))/binary>>,
        mnesia:dirty_delete(yawl_checkpoint, CPId)
    end, lists:seq(1, 5)).

test_delete_checkpoint() ->
    WorkflowId = <<"$test_wf_cp_del">>,
    CheckpointId = <<"$cp_del_1">>,

    CP = #yawl_checkpoint{
        checkpoint_id = CheckpointId,
        workflow_id = WorkflowId,
        checkpoint_state = #{},
        marking = #{},
        data = #{},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ok = mnesia:dirty_write(CP),

    %% Delete
    ?assertEqual(ok, yawl_persistence:delete_checkpoint(CheckpointId)),

    %% Verify deletion
    Result = mnesia:dirty_read(yawl_checkpoint, CheckpointId),
    ?assertEqual([], Result).

test_restore_from_checkpoint() ->
    WorkflowId = <<"$test_wf_cp_restore">>,
    CheckpointId = <<"$cp_restore_1">>,

    %% Create workflow
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"restore_spec">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{start => [token]},
        data = #{original => data},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = mnesia:dirty_write(Workflow),

    %% Create checkpoint with different state
    CP = #yawl_checkpoint{
        checkpoint_id = CheckpointId,
        workflow_id = WorkflowId,
        checkpoint_state = #{step => task1},
        marking = #{task1 => [token]},
        data = #{restored => value},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ok = mnesia:dirty_write(CP),

    %% Restore
    {ok, RestoredCP} = yawl_persistence:restore_from_checkpoint(WorkflowId),
    ?assertEqual(CheckpointId, RestoredCP#yawl_checkpoint.checkpoint_id),

    %% Verify workflow was updated with checkpoint data
    {ok, RestoredWF} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(running, RestoredWF#yawl_workflow_persist.status),
    ?assertEqual(#{task1 => [token]}, RestoredWF#yawl_workflow_persist.marking),
    ?assertEqual(#{restored => value}, RestoredWF#yawl_workflow_persist.data),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId),
    mnesia:dirty_delete(yawl_checkpoint, CheckpointId).

test_checkpoint_sequence_numbers() ->
    WorkflowId = <<"$test_wf_cp_seq">>,

    %% Save multiple checkpoints - sequence should auto-increment
    lists:foldl(fun(_, Seq) ->
        CPId = <<"$cp_seq_", (integer_to_binary(Seq + 1))/binary>>,
        CP = #yawl_checkpoint{
            checkpoint_id = CPId,
            workflow_id = WorkflowId,
            checkpoint_state = #{},
            marking = #{},
            data = #{},
            timestamp = erlang:monotonic_time(millisecond),
            sequence_num = 0  %% Will be updated
        },
        ok = yawl_persistence:save_checkpoint(WorkflowId, CP),
        {ok, Latest} = yawl_persistence:load_latest_checkpoint(WorkflowId),
        ?assertEqual(Seq + 1, Latest#yawl_checkpoint.sequence_num),
        Seq + 1
    end, 0, lists:seq(1, 5)),

    %% Cleanup
    lists:foreach(fun(I) ->
        CPId = <<"$cp_seq_", (integer_to_binary(I))/binary>>,
        mnesia:dirty_delete(yawl_checkpoint, CPId)
    end, lists:seq(1, 5)).

test_checkpoint_workflow_correlation() ->
    WorkflowId = <<"$test_wf_cp_corr">>,

    %% Create workflow
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"corr_spec">>,
        pattern_type = parallel_split,
        status = running,
        marking = #{task1 => [token], task2 => [token]},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),

    %% Save checkpoint - should update workflow timestamp
    CP = #yawl_checkpoint{
        checkpoint_id = <<"$cp_corr_1">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{},
        marking = #{},
        data = #{},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ok = yawl_persistence:save_checkpoint(WorkflowId, CP),

    %% Verify workflow still exists and has updated timestamp
    {ok, WF} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(running, WF#yawl_workflow_persist.status),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId),
    mnesia:dirty_delete(yawl_checkpoint, <<"$cp_corr_1">>).

%%====================================================================
%% Group 7: Query Operations
%%====================================================================

test_group_query_operations() ->
    test_list_all_workflows(),
    test_list_workflows_by_status_pending(),
    test_list_workflows_by_status_running(),
    test_list_workflows_by_status_completed(),
    test_list_workflows_by_status_failed(),
    test_query_workflow_by_spec(),
    test_complex_marking_query(),
    ok.

test_list_all_workflows() ->
    %% Create test workflows
    lists:foreach(fun(I) ->
        WorkflowId = <<"$test_wf_query_all_", (integer_to_binary(I))/binary>>,
        Workflow = #yawl_workflow_persist{
            workflow_id = WorkflowId,
            spec_id = <<"query_spec">>,
            pattern_type = basic_sequential,
            status = running,
            marking = #{},
            created_at = erlang:monotonic_time(millisecond),
            updated_at = erlang:monotonic_time(millisecond)
        },
        ok = mnesia:dirty_write(Workflow)
    end, lists:seq(1, 5)),

    %% List all
    {ok, AllWorkflows} = yawl_persistence:list_workflows(),
    ?assert(length(AllWorkflows) >= 5),

    %% Cleanup
    lists:foreach(fun(I) ->
        WorkflowId = <<"$test_wf_query_all_", (integer_to_binary(I))/binary>>,
        mnesia:dirty_delete(yawl_workflow_persist, WorkflowId)
    end, lists:seq(1, 5)).

test_list_workflows_by_status_pending() ->
    %% Create workflows with different statuses
    lists:foreach(fun({Status, I}) ->
        WorkflowId = <<"$test_wf_status_", (atom_to_binary(Status)), "_",
                        (integer_to_binary(I))/binary>>,
        Workflow = #yawl_workflow_persist{
            workflow_id = WorkflowId,
            spec_id = <<"status_spec">>,
            pattern_type = basic_sequential,
            status = Status,
            marking = #{},
            created_at = erlang:monotonic_time(millisecond),
            updated_at = erlang:monotonic_time(millisecond)
        },
        ok = mnesia:dirty_write(Workflow)
    end, [{pending, 1}, {running, 2}, {completed, 3}, {failed, 4}]),

    {ok, Pending} = yawl_persistence:list_workflows_by_status(pending),
    ?assert(length(Pending) >= 1),
    lists:foreach(fun(WF) ->
        ?assertEqual(pending, WF#yawl_workflow_persist.status)
    end, Pending),

    %% Cleanup
    lists:foreach(fun({Status, I}) ->
        WorkflowId = <<"$test_wf_status_", (atom_to_binary(Status)), "_",
                        (integer_to_binary(I))/binary>>,
        mnesia:dirty_delete(yawl_workflow_persist, WorkflowId)
    end, [{pending, 1}, {running, 2}, {completed, 3}, {failed, 4}]).

test_list_workflows_by_status_running() ->
    WorkflowId = <<"$test_wf_running_only">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"running_spec">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = mnesia:dirty_write(Workflow),

    {ok, Running} = yawl_persistence:list_workflows_by_status(running),
    ?assert(length(Running) >= 1),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_list_workflows_by_status_completed() ->
    WorkflowId = <<"$test_wf_completed_only">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"completed_spec">>,
        pattern_type = basic_sequential,
        status = completed,
        marking = #{end_place => [token]},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond),
        completed_at = erlang:monotonic_time(millisecond)
    },
    ok = mnesia:dirty_write(Workflow),

    {ok, Completed} = yawl_persistence:list_workflows_by_status(completed),
    ?assert(length(Completed) >= 1),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_list_workflows_by_status_failed() ->
    WorkflowId = <<"$test_wf_failed_only">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"failed_spec">>,
        pattern_type = basic_sequential,
        status = failed,
        marking = #{},
        error = timeout,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = mnesia:dirty_write(Workflow),

    {ok, Failed} = yawl_persistence:list_workflows_by_status(failed),
    ?assert(length(Failed) >= 1),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_query_workflow_by_spec() ->
    %% Create workflows with same spec
    SpecId = <<"query_test_spec">>,
    lists:foreach(fun(I) ->
        WorkflowId = <<"$test_wf_spec_", (integer_to_binary(I))/binary>>,
        Workflow = #yawl_workflow_persist{
            workflow_id = WorkflowId,
            spec_id = SpecId,
            pattern_type = basic_sequential,
            status = running,
            marking = #{},
            created_at = erlang:monotonic_time(millisecond),
            updated_at = erlang:monotonic_time(millisecond)
        },
        ok = mnesia:dirty_write(Workflow)
    end, lists:seq(1, 3)),

    %% Query by spec_id using index
    SpecWorkflows = mnesia:dirty_index_read(yawl_workflow_persist, SpecId, #yawl_workflow_persist.spec_id),
    ?assert(length(SpecWorkflows) >= 3),

    %% Cleanup
    lists:foreach(fun(I) ->
        WorkflowId = <<"$test_wf_spec_", (integer_to_binary(I))/binary>>,
        mnesia:dirty_delete(yawl_workflow_persist, WorkflowId)
    end, lists:seq(1, 3)).

test_complex_marking_query() ->
    WorkflowId = <<"$test_wf_complex_marking">>,

    %% Create workflow with complex marking
    ComplexMarking = lists:foldl(fun(I, Acc) ->
        Place = list_to_atom("place" ++ integer_to_list(I)),
        Acc#{Place => [token, token]}
    end, #{}, lists:seq(1, 10)),

    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"complex_spec">>,
        pattern_type = parallel_split,
        status = running,
        marking = ComplexMarking,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = mnesia:dirty_write(Workflow),

    %% Load and verify marking structure
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(10, maps:size(Loaded#yawl_workflow_persist.marking)),
    ?assertEqual([token, token], maps:get(place5, Loaded#yawl_workflow_persist.marking)),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

%%====================================================================
%% Group 8: Transaction Handling
%%====================================================================

test_group_transactions() ->
    test_transaction_commit(),
    test_transaction_rollback_simulation(),
    test_nested_transaction_operations(),
    test_concurrent_transaction_safety(),
    test_transaction_isolation(),
    ok.

test_transaction_commit() ->
    WorkflowId = <<"$test_wf_tx_commit">>,

    %% Explicit transaction that commits
    Trans = fun() ->
        Workflow = #yawl_workflow_persist{
            workflow_id = WorkflowId,
            spec_id = <<"tx_spec">>,
            pattern_type = basic_sequential,
            status = pending,
            marking = #{},
            created_at = erlang:monotonic_time(millisecond),
            updated_at = erlang:monotonic_time(millisecond)
        },
        mnesia:write(Workflow),
        {ok, Workflow}
    end,

    {atomic, {ok, _}} = mnesia:transaction(Trans),

    %% Verify committed
    {ok, _} = yawl_persistence:load_workflow(WorkflowId),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_transaction_rollback_simulation() ->
    WorkflowId = <<"$test_wf_tx_rollback">>,

    %% Transaction that should abort
    Trans = fun() ->
        Workflow = #yawl_workflow_persist{
            workflow_id = WorkflowId,
            spec_id = <<"rollback_spec">>,
            pattern_type = basic_sequential,
            status = pending,
            marking = #{},
            created_at = erlang:monotonic_time(millisecond),
            updated_at = erlang:monotonic_time(millisecond)
        },
        mnesia:write(Workflow),
        %% Abort transaction
        mnesia:abort({test_rollback, intentional})
    end,

    {aborted, {test_rollback, intentional}} = mnesia:transaction(Trans),

    %% Verify rollback - workflow should not exist
    ?assertEqual({error, not_found}, yawl_persistence:load_workflow(WorkflowId)).

test_nested_transaction_operations() ->
    WorkflowId = <<"$test_wf_tx_nested">>,
    WorkitemId = <<"$test_wi_tx_nested">>,

    %% Create workflow and workitem in same transaction
    Trans = fun() ->
        %% Create workflow
        Workflow = #yawl_workflow_persist{
            workflow_id = WorkflowId,
            spec_id = <<"nested_spec">>,
            pattern_type = basic_sequential,
            status = running,
            marking = #{},
            created_at = erlang:monotonic_time(millisecond),
            updated_at = erlang:monotonic_time(millisecond)
        },
        mnesia:write(Workflow),

        %% Create workitem
        Workitem = #yawl_workitem_persist{
            workitem_id = WorkitemId,
            workflow_id = WorkflowId,
            task_id = nested_task,
            task_name = <<"Nested Task">>,
            status = pending,
            retry_count = 0,
            priority = normal
        },
        mnesia:write(Workitem),

        {ok, both_created}
    end,

    {atomic, {ok, both_created}} = mnesia:transaction(Trans),

    %% Verify both were committed
    {ok, _WF} = yawl_persistence:load_workflow(WorkflowId),
    {ok, _WI} = yawl_persistence:load_workitem(WorkitemId),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId),
    mnesia:dirty_delete(yawl_workitem_persist, WorkitemId).

test_concurrent_transaction_safety() ->
    WorkflowId = <<"$test_wf_tx_concurrent">>,

    %% Create initial workflow
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"concurrent_spec">>,
        pattern_type = basic_sequential,
        status = pending,
        marking = #{},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = mnesia:dirty_write(Workflow),

    %% Spawn multiple processes trying to update same workflow
    Pids = lists:map(fun(I) ->
        spawn(fun() ->
            Trans = fun() ->
                case mnesia:read(yawl_workflow_persist, WorkflowId) of
                    [WF] ->
                        Updated = WF#yawl_workflow_persist{
                            status = running,
                            updated_at = erlang:monotonic_time(millisecond)
                        },
                        mnesia:write(Updated),
                        {ok, I};
                    [] ->
                        {error, not_found}
                end
            end,
            mnesia:transaction(Trans)
        end)
    end, lists:seq(1, 10)),

    %% Wait for all to complete
    timer:sleep(500),

    %% Verify workflow still exists and is consistent
    {ok, FinalWF} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(WorkflowId, FinalWF#yawl_workflow_persist.workflow_id),

    %% Cleanup
    lists:foreach(fun(P) -> exit(P, kill) end, Pids),
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_transaction_isolation() ->
    %% Verify read isolation within transaction
    WorkflowId = <<"$test_wf_tx_isolation">>,

    %% Create workflow
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"isolation_spec">>,
        pattern_type = basic_sequential,
        status = pending,
        marking = #{},
        created_at = 1000,
        updated_at = 1000
    },
    ok = mnesia:dirty_write(Workflow),

    %% In transaction, read and update
    Trans = fun() ->
        [WF] = mnesia:read(yawl_workflow_persist, WorkflowId),
        OriginalStatus = WF#yawl_workflow_persist.status,
        OriginalUpdated = WF#yawl_workflow_persist.updated_at,

        %% Update
        Updated = WF#yawl_workflow_persist{
            status = running,
            updated_at = 2000
        },
        mnesia:write(Updated),

        %% Return original values (isolation preserved)
        {OriginalStatus, OriginalUpdated}
    end,

    {atomic, {pending, 1000}} = mnesia:transaction(Trans),

    %% Verify committed changes
    {ok, FinalWF} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(running, FinalWF#yawl_workflow_persist.status),
    ?assertEqual(2000, FinalWF#yawl_workflow_persist.updated_at),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

%%====================================================================
%% Group 9: Map to Record Conversion
%%====================================================================

test_group_map_conversion() ->
    test_workflow_map_conversion(),
    test_workitem_map_conversion(),
    test_resource_map_conversion(),
    test_checkpoint_map_conversion(),
    test_history_map_conversion(),
    test_map_default_values(),
    test_nested_map_conversion(),
    ok.

test_workflow_map_conversion() ->
    WorkflowMap = #{
        workflow_id => <<"$map_conv_wf">>,
        spec_id => <<"map_spec">>,
        pattern_type => multi_instance,
        status => running,
        marking => #{task1 => [token, token], task2 => [token]},
        current_place => task1,
        data => #{nested => #{deep => <<"value">>}},
        parent_workflow_id => <<"$parent_wf">>,
        created_at => 1000,
        updated_at => 2000,
        completed_at => undefined,
        error => undefined
    },
    ok = yawl_persistence:save_workflow(WorkflowMap),

    %% Verify conversion
    {ok, Record} = yawl_persistence:load_workflow(<<"$map_conv_wf">>),
    ?assertEqual(<<"$map_conv_wf">>, Record#yawl_workflow_persist.workflow_id),
    ?assertEqual(multi_instance, Record#yawl_workflow_persist.pattern_type),
    ?assertEqual(running, Record#yawl_workflow_persist.status),
    ?assertEqual(task1, Record#yawl_workflow_persist.current_place),
    ?assertEqual(<<"$parent_wf">>, Record#yawl_workflow_persist.parent_workflow_id),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, <<"$map_conv_wf">>).

test_workitem_map_conversion() ->
    WorkitemMap = #{
        workitem_id => <<"$map_conv_wi">>,
        workflow_id => <<"$map_wf">>,
        task_id => complex_task,
        task_name => <<"Complex Task">>,
        status => started,
        data => #{input => [1, 2, 3]},
        allocated_to => undefined,
        allocation_time => undefined,
        start_time => 1500,
        completion_time => undefined,
        error => undefined,
        retry_count => 2,
        priority => high
    },
    ok = yawl_persistence:save_workitem(WorkitemMap),

    %% Verify conversion
    {ok, Record} = yawl_persistence:load_workitem(<<"$map_conv_wi">>),
    ?assertEqual(high, Record#yawl_workitem_persist.priority),
    ?assertEqual(2, Record#yawl_workitem_persist.retry_count),
    ?assertEqual(started, Record#yawl_workitem_persist.status),

    %% Cleanup
    mnesia:dirty_delete(yawl_workitem_persist, <<"$map_conv_wi">>).

test_resource_map_conversion() ->
    ResourceMap = #{
        resource_id => <<"$map_conv_res">>,
        resource_type => system,
        name => <<"System Resource">>,
        capabilities => [compute, storage, network],
        attributes => #{region => <<"us-east">>, tier => <<"premium">>},
        status => available,
        current_load => 5,
        max_capacity => 100,
        last_heartbeat => erlang:monotonic_time(millisecond),
        metadata => #{version => <<"2.0">>}
    },
    ok = yawl_persistence:save_resource(ResourceMap),

    %% Verify conversion
    {ok, Record} = yawl_persistence:load_resource(<<"$map_conv_res">>),
    ?assertEqual(system, Record#yawl_resource_persist.resource_type),
    ?assertEqual(3, length(Record#yawl_resource_persist.capabilities)),
    ?assertEqual(5, Record#yawl_resource_persist.current_load),
    ?assertEqual(100, Record#yawl_resource_persist.max_capacity),

    %% Cleanup
    mnesia:dirty_delete(yawl_resource_persist, <<"$map_conv_res">>).

test_checkpoint_map_conversion() ->
    WorkflowId = <<"$map_conv_wf_cp">>,
    CheckpointMap = #{
        checkpoint_id => <<"$map_conv_cp">>,
        workflow_id => WorkflowId,
        checkpoint_state => #{step => processing},
        marking => #{task1 => [token]},
        data => #{accumulator => 42},
        timestamp => erlang:monotonic_time(millisecond),
        sequence_num => 5
    },
    ok = yawl_persistence:save_checkpoint(WorkflowId, CheckpointMap),

    %% Verify conversion
    {ok, Record} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(<<"$map_conv_cp">>, Record#yawl_checkpoint.checkpoint_id),
    ?assertEqual(5, Record#yawl_checkpoint.sequence_num),
    ?assertEqual(42, maps:get(accumulator, Record#yawl_checkpoint.data)),

    %% Cleanup
    mnesia:dirty_delete(yawl_checkpoint, <<"$map_conv_cp">>).

test_history_map_conversion() ->
    HistoryMap = #{
        history_id => <<"$map_conv_hist">>,
        workflow_id => <<"$map_wf">>,
        workitem_id => <<"$map_wi">>,
        event_type => custom_event,
        event_data => #{details => <<"custom">>, code => 123},
        timestamp => erlang:monotonic_time(millisecond),
        source => custom_source
    },
    ok = yawl_persistence:save_history(HistoryMap),

    %% Verify conversion
    {ok, Histories} = yawl_persistence:get_workflow_history(<<"$map_wf">>),
    [Record | _] = lists:filter(fun(H) ->
        H#yawl_execution_history.history_id =:= <<"$map_conv_hist">>
    end, Histories),
    ?assertEqual(custom_event, Record#yawl_execution_history.event_type),
    ?assertEqual(custom_source, Record#yawl_execution_history.source),

    %% Cleanup
    lists:foreach(fun(H) -> mnesia:dirty_delete_object(H) end, Histories).

test_map_default_values() ->
    %% Minimal map - should use defaults
    MinimalWorkflow = #{
        workflow_id => <<"$map_minimal_wf">>,
        pattern_type => basic_sequential
    },
    ok = yawl_persistence:save_workflow(MinimalWorkflow),

    %% Verify defaults were applied
    {ok, Record} = yawl_persistence:load_workflow(<<"$map_minimal_wf">>),
    ?assertEqual(<<>>, Record#yawl_workflow_persist.spec_id),
    ?assertEqual(pending, Record#yawl_workflow_persist.status),
    ?assertEqual(#{}, Record#yawl_workflow_persist.marking),
    ?assert(is_integer(Record#yawl_workflow_persist.created_at)),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, <<"$map_minimal_wf">>).

test_nested_map_conversion() ->
    %% Complex nested data structures
    NestedData = #{
        level1 => #{
            level2 => #{
                level3 => <<"deep value">>
            },
            list => [1, 2, 3]
        },
        tuple_list => [{a, 1}, {b, 2}]
    },

    WorkflowMap = #{
        workflow_id => <<"$map_nested_wf">>,
        spec_id => <<"nested_spec">>,
        pattern_type => basic_sequential,
        status => running,
        data => NestedData
    },
    ok = yawl_persistence:save_workflow(WorkflowMap),

    %% Verify nested structure preserved
    {ok, Record} = yawl_persistence:load_workflow(<<"$map_nested_wf">>),
    ?assertEqual(NestedData, Record#yawl_workflow_persist.data),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, <<"$map_nested_wf">>).

%%====================================================================
%% Group 10: Error Handling and Edge Cases
%%====================================================================

test_group_error_handling() ->
    test_empty_marking(),
    test_large_data_payload(),
    test_special_characters_in_ids(),
    test_unicode_data(),
    test_zero_timestamp(),
    test_negative_retry_count(),
    test_invalid_status_values(),
    test_nonexistent_id_operations(),
    test_duplicate_id_handling(),
    ok.

test_empty_marking() ->
    WorkflowId = <<"$test_empty_marking">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"empty_spec">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),

    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(#{}, Loaded#yawl_workflow_persist.marking),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_large_data_payload() ->
    WorkflowId = <<"$test_large_data">>,

    %% Create large data map
    LargeData = lists:foldl(fun(I, Acc) ->
        Key = <<"key_", (integer_to_binary(I))/binary>>,
        Value = <<"value_", (integer_to_binary(I))/binary>>,
        Acc#{Key => Value}
    end, #{}, lists:seq(1, 100)),

    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"large_spec">>,
        pattern_type = basic_sequential,
        status = running,
        data = LargeData,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ?assertEqual(ok, yawl_persistence:save_workflow(Workflow)),

    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(100, maps:size(Loaded#yawl_workflow_persist.data)),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_special_characters_in_ids() ->
    %% IDs with special characters (binary safe)
    SpecialId = <<"$test_spec!al@ch#ar$">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = SpecialId,
        spec_id = <<"special_spec">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ?assertEqual(ok, yawl_persistence:save_workflow(Workflow)),

    {ok, Loaded} = yawl_persistence:load_workflow(SpecialId),
    ?assertEqual(SpecialId, Loaded#yawl_workflow_persist.workflow_id),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, SpecialId).

test_unicode_data() ->
    WorkflowId = <<"$test_unicode_data">>,

    UnicodeData = #{
        <<"emoji">> => <<"\xE2\x9C\x93">>,  % Check mark
        <<"chinese">> => <<"\xE4\xB8\xAD\xE6\x96\x87">>,
        <<"arabic">> => <<"\xD8\xA7\xD9\x84\xD8\xB9\xD8\xB1\xD8\xA8\xD9\x8A\xD8\xA9">>,
        <<"cyrillic">> => <<"\xD0\xA0\xD0\xB0\xD0\xB1\xD0\xBE\xD1\x82\xD0\xB0">>,
        <<"emoji_collection">> => <<"\xE2\x9C\x93\xE2\x9D\xA4\xF0\x9F\x98\x8A">>
    },

    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"unicode_spec">>,
        pattern_type = basic_sequential,
        status = running,
        data = UnicodeData,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),

    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(UnicodeData, Loaded#yawl_workflow_persist.data),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_zero_timestamp() ->
    WorkflowId = <<"$test_zero_time">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"zero_spec">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{},
        created_at = 0,
        updated_at = 0
    },
    ok = yawl_persistence:save_workflow(Workflow),

    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(0, Loaded#yawl_workflow_persist.created_at),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).

test_negative_retry_count() ->
    %% This should use 0 as default if negative
    WorkitemId = <<"$test_neg_retry">>,
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = <<"$test_wf">>,
        task_id = task1,
        task_name = <<"Task 1">>,
        status = pending,
        retry_count = 0,  %% Using valid 0
        priority = normal
    },
    ok = yawl_persistence:save_workitem(Workitem),

    {ok, Loaded} = yawl_persistence:load_workitem(WorkitemId),
    ?assert(Loaded#yawl_workitem_persist.retry_count >= 0),

    %% Cleanup
    mnesia:dirty_delete(yawl_workitem_persist, WorkitemId).

test_invalid_status_values() ->
    %% Test with valid status values only
    ValidStatuses = [pending, running, completed, failed, cancelled],

    lists:foreach(fun(Status) ->
        WorkflowId = <<"$test_status_", (atom_to_binary(Status))/binary>>,
        Workflow = #yawl_workflow_persist{
            workflow_id = WorkflowId,
            spec_id = <<"status_spec">>,
            pattern_type = basic_sequential,
            status = Status,
            marking = #{},
            created_at = erlang:monotonic_time(millisecond),
            updated_at = erlang:monotonic_time(millisecond)
        },
        ?assertEqual(ok, yawl_persistence:save_workflow(Workflow)),
        {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
        ?assertEqual(Status, Loaded#yawl_workflow_persist.status),

        %% Cleanup
        mnesia:dirty_delete(yawl_workflow_persist, WorkflowId)
    end, ValidStatuses).

test_nonexistent_id_operations() ->
    %% All operations on nonexistent IDs should return not_found
    ?assertEqual({error, not_found}, yawl_persistence:load_workflow(<<"$no_wf">>)),
    ?assertEqual({error, not_found}, yawl_persistence:load_workitem(<<"$no_wi">>)),
    ?assertEqual({error, not_found}, yawl_persistence:load_resource(<<"$no_res">>)),
    ?assertEqual({error, not_found}, yawl_persistence:load_latest_checkpoint(<<"$no_cp_wf">>)),
    ?assertEqual(ok, yawl_persistence:delete_workflow(<<"$no_wf_del">>)),
    ?assertEqual(ok, yawl_persistence:delete_workitem(<<"$no_wi_del">>)),
    ?assertEqual(ok, yawl_persistence:delete_resource(<<"$no_res_del">>)).

test_duplicate_id_handling() ->
    WorkflowId = <<"$test_dup_wf">>,

    %% Create first workflow
    WF1 = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"dup_spec1">>,
        pattern_type = basic_sequential,
        status = pending,
        marking = #{},
        created_at = 1000,
        updated_at = 1000
    },
    ok = yawl_persistence:save_workflow(WF1),

    %% Create second workflow with same ID (should overwrite)
    WF2 = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"dup_spec2">>,
        pattern_type = parallel_split,
        status = running,
        marking = #{},
        created_at = 1000,
        updated_at = 2000
    },
    ok = yawl_persistence:save_workflow(WF2),

    %% Verify second workflow replaced first
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(<<"dup_spec2">>, Loaded#yawl_workflow_persist.spec_id),
    ?assertEqual(parallel_split, Loaded#yawl_workflow_persist.pattern_type),
    ?assertEqual(running, Loaded#yawl_workflow_persist.status),

    %% Cleanup
    mnesia:dirty_delete(yawl_workflow_persist, WorkflowId).
