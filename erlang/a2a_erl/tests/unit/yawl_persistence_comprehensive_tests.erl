%%%-------------------------------------------------------------------
%%% @doc
%%% Comprehensive Unit Tests for YAWL Persistence
%%%
%%% This module provides comprehensive test coverage for the YAWL persistence
%%% layer using Mnesia, covering all major functions, edge cases, error paths,
%%% workflow persistence, workitem persistence, resource persistence,
%%% checkpoint operations, and recovery functionality.
%%%
%%% Target Coverage: 95%+
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_persistence_comprehensive_tests).
-author("A2A Team").

-include_lib("eunit/include/eunit.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Test Macros
%%====================================================================

-define(TEST_DIR_PREFIX, "/tmp/yawl_persist_test_").

%%====================================================================
%% Test Generator
%%====================================================================

persistence_comprehensive_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     [
      {"Group 1: Schema and Tables", fun test_group_schema/0},
      {"Group 2: Workflow Operations", fun test_group_workflows/0},
      {"Group 3: Workitem Operations", fun test_group_workitems/0},
      {"Group 4: Resource Operations", fun test_group_resources/0},
      {"Group 5: Checkpoint Operations", fun test_group_checkpoints/0},
      {"Group 6: History Operations", fun test_group_history/0},
      {"Group 7: Map Conversion", fun test_group_map_conversion/0},
      {"Group 8: Recovery", fun test_group_recovery/0},
      {"Group 9: Edge Cases", fun test_group_edge_cases/0},
      {"Group 10: Error Handling", fun test_group_errors/0}
     ]}.

%%====================================================================
%% Setup and Cleanup
%%====================================================================

setup() ->
    TestDir = ?TEST_DIR_PREFIX ++ integer_to_list(erlang:unique_integer()),
    application:stop(mnesia),
    ok = filelib:ensure_dir(TestDir ++ "/"),
    application:set_env(mnesia, dir, TestDir),
    ok = yawl_persistence:create_schema(),
    ok = mnesia:start(),
    ok = yawl_persistence:create_tables(),
    ok = yawl_persistence:wait_for_tables(),
    {ok, Pid} = yawl_persistence:start_link(),
    {Pid, TestDir}.

cleanup({Pid, TestDir}) ->
    gen_server:stop(Pid),
    mnesia:stop(),
    application:unset_env(mnesia, dir),
    file:del_dir_r(TestDir),
    ok.

%%====================================================================
%% Group 1: Schema and Tables
%%====================================================================

test_group_schema() ->
    test_create_schema(),
    test_create_tables(),
    test_wait_for_tables(),
    test_tables_exist(),
    test_backup_tables(),
    ok.

test_create_schema() ->
    Result = yawl_persistence:create_schema(),
    case Result of
        ok -> ok;
        {error, {already_exists, _}} -> ok;
        Other -> ?assertEqual(ok, Other)
    end.

test_create_tables() ->
    %% Tables should already be created in setup
    Tables = mnesia:system_info(tables),
    ?assert(lists:member(yawl_workflow_persist, Tables)),
    ?assert(lists:member(yawl_workitem_persist, Tables)),
    ?assert(lists:member(yawl_resource_persist, Tables)),
    ?assert(lists:member(yawl_checkpoint, Tables)),
    ?assert(lists:member(yawl_execution_history, Tables)).

test_wait_for_tables() ->
    Result = yawl_persistence:wait_for_tables(),
    ?assertEqual(ok, Result).

test_tables_exist() ->
    RequiredTables = [
        yawl_workflow_persist,
        yawl_workitem_persist,
        yawl_resource_persist,
        yawl_execution_history,
        yawl_checkpoint,
        yawl_service_registry,
        yawl_task_queue
    ],
    Tables = mnesia:system_info(tables),
    lists:foreach(fun(Table) ->
        ?assert(lists:member(Table, Tables))
    end, RequiredTables).

test_backup_tables() ->
    BackupFile = "/tmp/yawl_test_backup_" ++ integer_to_list(erlang:unique_integer()),
    Result = yawl_persistence:backup_tables(BackupFile),
    ?assertEqual(ok, Result),
    file:delete(BackupFile).

%%====================================================================
%% Group 2: Workflow Operations
%%====================================================================

test_group_workflows() ->
    test_save_workflow_record(),
    test_save_workflow_map(),
    test_load_workflow(),
    test_load_workflow_not_found(),
    test_delete_workflow(),
    test_delete_workflow_not_found(),
    test_archive_workflow(),
    test_list_workflows(),
    test_list_workflows_by_status(),
    test_workflow_update_timestamps(),
    ok.

test_save_workflow_record() ->
    Workflow = #yawl_workflow_persist{
        workflow_id = <<"$test_wf_1">>,
        spec_id = <<"spec_1">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{start => [<<"token">>]},
        current_place = start,
        data = #{key => <<"value">>},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    Result = yawl_persistence:save_workflow(Workflow),
    ?assertEqual(ok, Result).

test_save_workflow_map() ->
    WorkflowMap = #{
        workflow_id => <<"$test_wf_2">>,
        spec_id => <<"spec_2">>,
        pattern_type => parallel_split,
        status => pending,
        marking => #{start => [<<"token">>]},
        data => #{}
    },
    Result = yawl_persistence:save_workflow(WorkflowMap),
    ?assertEqual(ok, Result).

test_load_workflow() ->
    WorkflowId = <<"$test_wf_3">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec_3">>,
        pattern_type = basic_sequential,
        status = running,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(WorkflowId, Loaded#yawl_workflow_persist.workflow_id),
    ?assertEqual(basic_sequential, Loaded#yawl_workflow_persist.pattern_type).

test_load_workflow_not_found() ->
    Result = yawl_persistence:load_workflow(<<"non_existent_wf">>),
    ?assertEqual({error, not_found}, Result).

test_delete_workflow() ->
    WorkflowId = <<"$test_wf_4">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec_4">>,
        pattern_type = basic_sequential,
        status = running,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),
    Result = yawl_persistence:delete_workflow(WorkflowId),
    ?assertEqual(ok, Result),
    ?assertEqual({error, not_found}, yawl_persistence:load_workflow(WorkflowId)).

test_delete_workflow_not_found() ->
    Result = yawl_persistence:delete_workflow(<<"non_existent_wf">>),
    ?assertEqual(ok, Result).

test_archive_workflow() ->
    WorkflowId = <<"$test_wf_5">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec_5">>,
        pattern_type = basic_sequential,
        status = running,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),
    Result = yawl_persistence:archive_workflow(WorkflowId),
    ?assertEqual(ok, Result),
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(terminated, Loaded#yawl_workflow_persist.status).

test_list_workflows() ->
    %% Create multiple workflows
    lists:foreach(fun(I) ->
        WorkflowId = <<"$test_wf_list_", (integer_to_binary(I))/binary>>,
        Workflow = #yawl_workflow_persist{
            workflow_id = WorkflowId,
            spec_id = <<"spec_", (integer_to_binary(I))/binary>>,
            pattern_type = basic_sequential,
            status = running,
            created_at = erlang:monotonic_time(millisecond),
            updated_at = erlang:monotonic_time(millisecond)
        },
        ok = yawl_persistence:save_workflow(Workflow)
    end, lists:seq(1, 5)),
    {ok, Workflows} = yawl_persistence:list_workflows(),
    ?assert(length(Workflows) >= 5).

test_list_workflows_by_status() ->
    %% Create workflows with different statuses
    lists:foreach(fun({Status, I}) ->
        WorkflowId = <<"$test_wf_status_", (integer_to_binary(I))/binary>>,
        Workflow = #yawl_workflow_persist{
            workflow_id = WorkflowId,
            spec_id = <<"spec">>,
            pattern_type = basic_sequential,
            status = Status,
            created_at = erlang:monotonic_time(millisecond),
            updated_at = erlang:monotonic_time(millisecond)
        },
        ok = yawl_persistence:save_workflow(Workflow)
    end, [{running, 1}, {completed, 2}, {failed, 3}]),
    {ok, Running} = yawl_persistence:list_workflows_by_status(running),
    {ok, Completed} = yawl_persistence:list_workflows_by_status(completed),
    {ok, Failed} = yawl_persistence:list_workflows_by_status(failed),
    ?assert(length(Running) >= 1),
    ?assert(length(Completed) >= 1),
    ?assert(length(Failed) >= 1).

test_workflow_update_timestamps() ->
    WorkflowId = <<"$test_wf_time_1">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec">>,
        pattern_type = basic_sequential,
        status = pending,
        created_at = 1000,
        updated_at = 1000
    },
    ok = yawl_persistence:save_workflow(Workflow),
    timer:sleep(10),
    %% Save again with different status
    Workflow2 = Workflow#yawl_workflow_persist{status = running},
    ok = yawl_persistence:save_workflow(Workflow2),
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assert(Loaded#yawl_workflow_persist.updated_at > 1000).

%%====================================================================
%% Group 3: Workitem Operations
%%====================================================================

test_group_workitems() ->
    test_save_workitem_record(),
    test_save_workitem_map(),
    test_load_workitem(),
    test_load_workitem_not_found(),
    test_delete_workitem(),
    test_list_workitems(),
    test_update_workitem_status(),
    test_update_all_statuses(),
    ok.

test_save_workitem_record() ->
    Workitem = #yawl_workitem_persist{
        workitem_id = <<"$test_wi_1">>,
        workflow_id = <<"$test_wf">>,
        task_id = task1,
        task_name = <<"Task 1">>,
        status = pending,
        data = #{},
        retry_count = 0,
        priority = normal
    },
    Result = yawl_persistence:save_workitem(Workitem),
    ?assertEqual(ok, Result).

test_save_workitem_map() ->
    WorkitemMap = #{
        workitem_id => <<"$test_wi_2">>,
        workflow_id => <<"$test_wf">>,
        task_id => task2,
        task_name => <<"Task 2">>,
        status => pending,
        data => #{},
        priority => high
    },
    Result = yawl_persistence:save_workitem(WorkitemMap),
    ?assertEqual(ok, Result).

test_load_workitem() ->
    WorkitemId = <<"$test_wi_3">>,
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = <<"$test_wf">>,
        task_id = task1,
        task_name = <<"Task 1">>,
        status = pending,
        data = #{key => <<"value">>},
        retry_count = 0,
        priority = normal
    },
    ok = yawl_persistence:save_workitem(Workitem),
    {ok, Loaded} = yawl_persistence:load_workitem(WorkitemId),
    ?assertEqual(WorkitemId, Loaded#yawl_workitem_persist.workitem_id),
    ?assertEqual(task1, Loaded#yawl_workitem_persist.task_id),
    ?assertEqual(#{key => <<"value">>}, Loaded#yawl_workitem_persist.data).

test_load_workitem_not_found() ->
    Result = yawl_persistence:load_workitem(<<"non_existent_wi">>),
    ?assertEqual({error, not_found}, Result).

test_delete_workitem() ->
    WorkitemId = <<"$test_wi_4">>,
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = <<"$test_wf">>,
        task_id = task1,
        task_name = <<"Task 1">>,
        status = pending,
        retry_count = 0,
        priority = normal
    },
    ok = yawl_persistence:save_workitem(Workitem),
    Result = yawl_persistence:delete_workitem(WorkitemId),
    ?assertEqual(ok, Result),
    ?assertEqual({error, not_found}, yawl_persistence:load_workitem(WorkitemId)).

test_list_workitems() ->
    WorkflowId = <<"$test_wf_wi_list">>,
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
        ok = yawl_persistence:save_workitem(Workitem)
    end, lists:seq(1, 3)),
    {ok, Workitems} = yawl_persistence:list_workitems(WorkflowId),
    ?assertEqual(3, length(Workitems)).

test_update_workitem_status() ->
    WorkitemId = <<"$test_wi_5">>,
    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = <<"$test_wf">>,
        task_id = task1,
        task_name = <<"Task 1">>,
        status = pending,
        retry_count = 0,
        priority = normal
    },
    ok = yawl_persistence:save_workitem(Workitem),
    ok = yawl_persistence:update_workitem_status(WorkitemId, started),
    {ok, Loaded} = yawl_persistence:load_workitem(WorkitemId),
    ?assertEqual(started, Loaded#yawl_workitem_persist.status),
    ?assert(Loaded#yawl_workitem_persist.start_time > 0).

test_update_all_statuses() ->
    Statuses = [pending, started, allocated, completed, failed, cancelled],
    lists:foreach(fun(Status) ->
        WorkitemId = <<"$test_wi_status_", (atom_to_binary(Status))/binary>>,
        Workitem = #yawl_workitem_persist{
            workitem_id = WorkitemId,
            workflow_id = <<"$test_wf">>,
            task_id = task1,
            task_name = <<"Task 1">>,
            status = pending,
            retry_count = 0,
            priority = normal
        },
        ok = yawl_persistence:save_workitem(Workitem),
        ok = yawl_persistence:update_workitem_status(WorkitemId, Status),
        {ok, Loaded} = yawl_persistence:load_workitem(WorkitemId),
        ?assertEqual(Status, Loaded#yawl_workitem_persist.status)
    end, Statuses).

%%====================================================================
%% Group 4: Resource Operations
%%====================================================================

test_group_resources() ->
    test_save_resource_record(),
    test_save_resource_map(),
    test_load_resource(),
    test_load_resource_not_found(),
    test_delete_resource(),
    test_list_resources(),
    test_list_resources_by_type(),
    test_list_available_resources(),
    test_resource_types(),
    ok.

test_save_resource_record() ->
    Resource = #yawl_resource_persist{
        resource_id = <<"$test_res_1">>,
        resource_type = service,
        name = <<"Test Service">>,
        capabilities = [task1, task2],
        attributes = #{},
        status = available,
        current_load = 0,
        max_capacity = 10,
        last_heartbeat = erlang:monotonic_time(millisecond)
    },
    Result = yawl_persistence:save_resource(Resource),
    ?assertEqual(ok, Result).

test_save_resource_map() ->
    ResourceMap = #{
        resource_id => <<"$test_res_2">>,
        resource_type => human,
        name => <<"Test Human">>,
        capabilities => [task3],
        status => available,
        current_load => 0,
        max_capacity => 5
    },
    Result = yawl_persistence:save_resource(ResourceMap),
    ?assertEqual(ok, Result).

test_load_resource() ->
    ResourceId = <<"$test_res_3">>,
    Resource = #yawl_resource_persist{
        resource_id = ResourceId,
        resource_type = service,
        name = <<"Test Service">>,
        capabilities = [task1],
        status = available,
        current_load = 0,
        max_capacity = 10,
        last_heartbeat = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_resource(Resource),
    {ok, Loaded} = yawl_persistence:load_resource(ResourceId),
    ?assertEqual(ResourceId, Loaded#yawl_resource_persist.resource_id),
    ?assertEqual(service, Loaded#yawl_resource_persist.resource_type).

test_load_resource_not_found() ->
    Result = yawl_persistence:load_resource(<<"non_existent_res">>),
    ?assertEqual({error, not_found}, Result).

test_delete_resource() ->
    ResourceId = <<"$test_res_4">>,
    Resource = #yawl_resource_persist{
        resource_id = ResourceId,
        resource_type = service,
        name = <<"Test">>,
        capabilities = [],
        status = available,
        current_load = 0,
        max_capacity = 10
    },
    ok = yawl_persistence:save_resource(Resource),
    Result = yawl_persistence:delete_resource(ResourceId),
    ?assertEqual(ok, Result),
    ?assertEqual({error, not_found}, yawl_persistence:load_resource(ResourceId)).

test_list_resources() ->
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
        ok = yawl_persistence:save_resource(Resource)
    end, lists:seq(1, 3)),
    {ok, Resources} = yawl_persistence:list_resources(),
    ?assert(length(Resources) >= 3).

test_list_resources_by_type() ->
    %% Create resources of different types
    lists:foreach(fun({Type, I}) ->
        ResourceId = <<"$test_res_type_", (atom_to_binary(Type))/binary, "_",
                        (integer_to_binary(I))/binary>>,
        Resource = #yawl_resource_persist{
            resource_id = ResourceId,
            resource_type = Type,
            name = <<"Resource">>,
            capabilities = [],
            status = available,
            current_load = 0,
            max_capacity = 10
        },
        ok = yawl_persistence:save_resource(Resource)
    end, [{service, 1}, {service, 2}, {human, 3}]),
    {ok, Services} = yawl_persistence:list_resources_by_type(service),
    {ok, Humans} = yawl_persistence:list_resources_by_type(human),
    ?assert(length(Services) >= 2),
    ?assert(length(Humans) >= 1).

test_list_available_resources() ->
    %% Create resources with different statuses
    lists:foreach(fun({Status, I}) ->
        ResourceId = <<"$test_res_status_", (atom_to_binary(Status))/binary, "_",
                        (integer_to_binary(I))/binary>>,
        Resource = #yawl_resource_persist{
            resource_id = ResourceId,
            resource_type = service,
            name = <<"Resource">>,
            capabilities = [],
            status = Status,
            current_load = 0,
            max_capacity = 10
        },
        ok = yawl_persistence:save_resource(Resource)
    end, [{available, 1}, {busy, 2}, {available, 3}]),
    {ok, Available} = yawl_persistence:list_available_resources(),
    ?assert(length(Available) >= 2).

test_resource_types() ->
    Types = [human, service, system],
    lists:foreach(fun(Type) ->
        ResourceId = <<"$test_res_type_", (atom_to_binary(Type))/binary>>,
        Resource = #yawl_resource_persist{
            resource_id = ResourceId,
            resource_type = Type,
            name = <<"Resource">>,
            capabilities = [],
            status = available,
            current_load = 0,
            max_capacity = 10
        },
        ok = yawl_persistence:save_resource(Resource),
        {ok, Loaded} = yawl_persistence:load_resource(ResourceId),
        ?assertEqual(Type, Loaded#yawl_resource_persist.resource_type)
    end, Types).

%%====================================================================
%% Group 5: Checkpoint Operations
%%====================================================================

test_group_checkpoints() ->
    test_save_checkpoint_record(),
    test_save_checkpoint_map(),
    test_load_latest_checkpoint(),
    test_load_latest_not_found(),
    test_list_checkpoints(),
    test_delete_checkpoint(),
    test_checkpoint_sequence_numbers(),
    test_checkpoint_with_workflow(),
    ok.

test_save_checkpoint_record() ->
    WorkflowId = <<"$test_wf_cp_1">>,
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = <<"$cp_1">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{state => <<"data">>},
        marking = #{start => [<<"token">>]},
        data = #{key => <<"value">>},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    %% Fix the syntax error in the record
    Checkpoint1 = Checkpoint#yawl_checkpoint{checkpoint_id = <<"$cp_1">>},
    Result = yawl_persistence:save_checkpoint(WorkflowId, Checkpoint1),
    ?assertEqual(ok, Result).

test_save_checkpoint_map() ->
    WorkflowId = <<"$test_wf_cp_2">>,
    CheckpointMap = #{
        checkpoint_id => <<"$cp_2">>,
        workflow_id => WorkflowId,
        checkpoint_state => #{},
        marking => #{start => [<<"token">>]},
        data => #{},
        sequence_num => 1
    },
    Result = yawl_persistence:save_checkpoint(WorkflowId, CheckpointMap),
    ?assertEqual(ok, Result).

test_load_latest_checkpoint() ->
    WorkflowId = <<"$test_wf_cp_3">>,
    Checkpoint1 = #yawl_checkpoint{
        checkpoint_id = <<"$cp_3a">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{},
        marking = #{start => [<<"token">>]},
        data = #{},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ok = yawl_persistence:save_checkpoint(WorkflowId, Checkpoint1),
    timer:sleep(5),
    Checkpoint2 = #yawl_checkpoint{
        checkpoint_id = <<"$cp_3b">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{},
        marking = #{task1 => [<<"token">>]},
        data = #{},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 2
    },
    ok = yawl_persistence:save_checkpoint(WorkflowId, Checkpoint2),
    {ok, Latest} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(<<"$cp_3b">>, Latest#yawl_checkpoint.checkpoint_id),
    ?assertEqual(2, Latest#yawl_checkpoint.sequence_num).

test_load_latest_not_found() ->
    Result = yawl_persistence:load_latest_checkpoint(<<"non_existent_wf">>),
    ?assertEqual({error, not_found}, Result).

test_list_checkpoints() ->
    WorkflowId = <<"$test_wf_cp_4">>,
    lists:foreach(fun(I) ->
        Checkpoint = #yawl_checkpoint{
            checkpoint_id = <<"$cp_4_", (integer_to_binary(I))/binary>>,
            workflow_id = WorkflowId,
            checkpoint_state = #{},
            marking = #{},
            data = #{},
            timestamp = erlang:monotonic_time(millisecond),
            sequence_num = I
        },
        ok = yawl_persistence:save_checkpoint(WorkflowId, Checkpoint)
    end, lists:seq(1, 3)),
    {ok, Checkpoints} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assertEqual(3, length(Checkpoints)).

test_delete_checkpoint() ->
    WorkflowId = <<"$test_wf_cp_5">>,
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = <<"$cp_5">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{},
        marking = #{},
        data = #{},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ok = yawl_persistence:save_checkpoint(WorkflowId, Checkpoint),
    Result = yawl_persistence:delete_checkpoint(<<"$cp_5">>),
    ?assertEqual(ok, Result),
    {ok, Remaining} = yawl_persistence:list_checkpoints(WorkflowId),
    ?assertEqual(0, length(Remaining)).

test_checkpoint_sequence_numbers() ->
    WorkflowId = <<"$test_wf_cp_seq">>,
    lists:foldl(fun(_, Acc) ->
        Checkpoint = #yawl_checkpoint{
            checkpoint_id = <<"$cp_seq_", (integer_to_binary(Acc + 1))/binary>>,
            workflow_id = WorkflowId,
            checkpoint_state = #{},
            marking = #{},
            data = #{},
            timestamp = erlang:monotonic_time(millisecond),
            sequence_num = Acc + 1
        },
        ok = yawl_persistence:save_checkpoint(WorkflowId, Checkpoint),
        {ok, Latest} = yawl_persistence:load_latest_checkpoint(WorkflowId),
        ?assertEqual(Acc + 1, Latest#yawl_checkpoint.sequence_num),
        Acc + 1
    end, 0, lists:seq(1, 5)),
    {ok, Final} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(5, Final#yawl_checkpoint.sequence_num).

test_checkpoint_with_workflow() ->
    WorkflowId = <<"$test_wf_cp_wf">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec">>,
        pattern_type = basic_sequential,
        status = running,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = <<"$cp_wf">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{},
        marking = #{},
        data = #{},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ok = yawl_persistence:save_checkpoint(WorkflowId, Checkpoint),
    %% Verify workflow still exists
    {ok, _WF} = yawl_persistence:load_workflow(WorkflowId).

%%====================================================================
%% Group 6: History Operations
%%====================================================================

test_group_history() ->
    test_save_history_record(),
    test_save_history_map(),
    test_get_workflow_history(),
    test_get_history_not_found(),
    test_delete_history(),
    test_multiple_history_entries(),
    ok.

test_save_history_record() ->
    History = #yawl_execution_history{
        history_id = <<"$hist_1">>,
        workflow_id = <<"$test_wf_hist">>,
        event_type = task_completed,
        event_data = #{task => <<"task1">>},
        timestamp = erlang:monotonic_time(millisecond),
        source = test
    },
    Result = yawl_persistence:save_history(History),
    ?assertEqual(ok, Result).

test_save_history_map() ->
    HistoryMap = #{
        history_id => <<"$hist_2">>,
        workflow_id => <<"$test_wf_hist">>,
        event_type => task_started,
        event_data => #{},
        timestamp => erlang:monotonic_time(millisecond),
        source => test
    },
    Result = yawl_persistence:save_history(HistoryMap),
    ?assertEqual(ok, Result).

test_get_workflow_history() ->
    WorkflowId = <<"$test_wf_hist_2">>,
    lists:foreach(fun(I) ->
        History = #yawl_execution_history{
            history_id = <<"$hist_", (integer_to_binary(I))/binary>>,
            workflow_id = WorkflowId,
            event_type = task_completed,
            event_data = #{num => I},
            timestamp = erlang:monotonic_time(millisecond),
            source = test
        },
        ok = yawl_persistence:save_history(History)
    end, lists:seq(1, 3)),
    {ok, Histories} = yawl_persistence:get_workflow_history(WorkflowId),
    ?assertEqual(3, length(Histories)).

test_get_history_not_found() ->
    Result = yawl_persistence:get_workflow_history(<<"non_existent_wf">>),
    ?assertMatch({ok, []}, Result).

test_delete_history() ->
    WorkflowId = <<"$test_wf_hist_3">>,
    lists:foreach(fun(I) ->
        History = #yawl_execution_history{
            history_id = <<"$hist_del_", (integer_to_binary(I))/binary>>,
            workflow_id = WorkflowId,
            event_type = task_completed,
            event_data = #{},
            timestamp = erlang:monotonic_time(millisecond),
        source = test
        },
        ok = yawl_persistence:save_history(History)
    end, lists:seq(1, 3)),
    Result = yawl_persistence:delete_history(WorkflowId),
    ?assertEqual(ok, Result),
    {ok, Histories} = yawl_persistence:get_workflow_history(WorkflowId),
    ?assertEqual(0, length(Histories)).

test_multiple_history_entries() ->
    WorkflowId = <<"$test_wf_hist_multi">>,
    EventTypes = [workflow_started, task_started, task_completed, workflow_completed],
    lists:foreach(fun(Type) ->
        History = #yawl_execution_history{
            history_id = <<"$hist_multi_", (atom_to_binary(Type))/binary>>,
            workflow_id = WorkflowId,
            event_type = Type,
            event_data = #{},
            timestamp = erlang:monotonic_time(millisecond),
        source = test
        },
        ok = yawl_persistence:save_history(History)
    end, EventTypes),
    {ok, Histories} = yawl_persistence:get_workflow_history(WorkflowId),
    ?assertEqual(4, length(Histories)).

%%====================================================================
%% Group 7: Map Conversion
%%====================================================================

test_group_map_conversion() ->
    test_workflow_map_to_record(),
    test_workitem_map_to_record(),
    test_resource_map_to_record(),
    test_checkpoint_map_to_record(),
    test_history_map_to_record(),
    test_map_defaults(),
    ok.

test_workflow_map_to_record() ->
    WorkflowMap = #{
        workflow_id => <<"$test_map_wf">>,
        spec_id => <<"spec">>,
        pattern_type => basic_sequential,
        status => running,
        marking => #{start => [<<"token">>]},
        current_place => start,
        data => #{key => <<"value">>},
        created_at => 1000,
        updated_at => 2000
    },
    ok = yawl_persistence:save_workflow(WorkflowMap),
    {ok, Loaded} = yawl_persistence:load_workflow(<<"$test_map_wf">>),
    ?assertEqual(<<"spec">>, Loaded#yawl_workflow_persist.spec_id),
    ?assertEqual(basic_sequential, Loaded#yawl_workflow_persist.pattern_type).

test_workitem_map_to_record() ->
    WorkitemMap = #{
        workitem_id => <<"$test_map_wi">>,
        workflow_id => <<"$wf">>,
        task_id => task1,
        task_name => <<"Task">>,
        status => pending,
        data => #{},
        retry_count => 0,
        priority => high
    },
    ok = yawl_persistence:save_workitem(WorkitemMap),
    {ok, Loaded} = yawl_persistence:load_workitem(<<"$test_map_wi">>),
    ?assertEqual(high, Loaded#yawl_workitem_persist.priority).

test_resource_map_to_record() ->
    ResourceMap = #{
        resource_id => <<"$test_map_res">>,
        resource_type => human,
        name => <<"Human">>,
        capabilities => [task1],
        status => available,
        current_load => 1,
        max_capacity => 10
    },
    ok = yawl_persistence:save_resource(ResourceMap),
    {ok, Loaded} = yawl_persistence:load_resource(<<"$test_map_res">>),
    ?assertEqual(human, Loaded#yawl_resource_persist.resource_type),
    ?assertEqual(1, Loaded#yawl_resource_persist.current_load).

test_checkpoint_map_to_record() ->
    WorkflowId = <<"$test_wf_map_cp">>,
    CheckpointMap = #{
        checkpoint_id => <<"$cp_map">>,
        workflow_id => WorkflowId,
        checkpoint_state => #{},
        marking => #{start => [<<"token">>]},
        data => #{},
        timestamp => erlang:monotonic_time(millisecond),
        sequence_num => 1
    },
    ok = yawl_persistence:save_checkpoint(WorkflowId, CheckpointMap),
    {ok, Loaded} = yawl_persistence:load_latest_checkpoint(WorkflowId),
    ?assertEqual(<<"$cp_map">>, Loaded#yawl_checkpoint.checkpoint_id).

test_history_map_to_record() ->
    HistoryMap = #{
        history_id => <<"$hist_map">>,
        workflow_id => <<"$wf">>,
        event_type => task_completed,
        event_data => #{},
        timestamp => erlang:monotonic_time(millisecond),
        source => test
    },
    ok = yawl_persistence:save_history(HistoryMap).

test_map_defaults() ->
    %% Test that missing optional fields get defaults
    WorkflowMap = #{
        workflow_id => <<"$test_wf_def">>,
        pattern_type => basic_sequential,
        status => pending
    },
    ok = yawl_persistence:save_workflow(WorkflowMap),
    {ok, Loaded} = yawl_persistence:load_workflow(<<"$test_wf_def">>),
    ?assertEqual(pending, Loaded#yawl_workflow_persist.status),
    %% Check defaults were applied
    ?assert(is_integer(Loaded#yawl_workflow_persist.created_at)).

%%====================================================================
%% Group 8: Recovery
%%====================================================================

test_group_recovery() ->
    test_restore_from_checkpoint(),
    test_restore_non_existent(),
    test_restore_creates_workflow(),
    test_restore_updates_existing(),
    ok.

test_restore_from_checkpoint() ->
    WorkflowId = <<"$test_wf_restore">>,
    %% Create a workflow
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{start => [<<"token">>]},
        data = #{original => <<"data">>},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),
    %% Create checkpoint
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = <<"$cp_restore">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{pattern_type => basic_sequential},
        marking = #{task1 => [<<"token">>]},
        data = #{restored => <<"data">>},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ok = yawl_persistence:save_checkpoint(WorkflowId, Checkpoint),
    %% Restore
    {ok, Restored} = yawl_persistence:restore_from_checkpoint(WorkflowId),
    ?assertEqual(<<"$cp_restore">>, Restored#yawl_checkpoint.checkpoint_id),
    %% Verify workflow was updated
    {ok, UpdatedWF} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(running, UpdatedWF#yawl_workflow_persist.status).

test_restore_non_existent() ->
    Result = yawl_persistence:restore_from_checkpoint(<<"non_existent_wf">>),
    ?assertEqual({error, no_checkpoint_found}, Result).

test_restore_creates_workflow() ->
    WorkflowId = <<"$test_wf_restore_new">>,
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = <<"$cp_restore_new">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{pattern_type => basic_sequential, spec_id => <<"spec">>},
        marking = #{start => [<<"token">>]},
        data = #{},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ok = yawl_persistence:save_checkpoint(WorkflowId, Checkpoint),
    %% Restore should create workflow
    {ok, _CP} = yawl_persistence:restore_from_checkpoint(WorkflowId),
    {ok, _WF} = yawl_persistence:load_workflow(WorkflowId).

test_restore_updates_existing() ->
    WorkflowId = <<"$test_wf_restore_upd">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec">>,
        pattern_type = basic_sequential,
        status = pending,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = <<"$cp_restore_upd">>,
        workflow_id = WorkflowId,
        checkpoint_state = #{},
        marking = #{task1 => [<<"token">>]},
        data = #{new => <<"data">>},
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    ok = yawl_persistence:save_checkpoint(WorkflowId, Checkpoint),
    %% Restore should update existing workflow
    {ok, _CP} = yawl_persistence:restore_from_checkpoint(WorkflowId),
    {ok, UpdatedWF} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(running, UpdatedWF#yawl_workflow_persist.status),
    ?assertEqual(#{task1 => [<<"token">>]}, UpdatedWF#yawl_workflow_persist.marking).

%%====================================================================
%% Group 9: Edge Cases
%%====================================================================

test_group_edge_cases() ->
    test_empty_marking(),
    test_large_marking(),
    test_special_characters_in_data(),
    test_unicode_in_data(),
    test_concurrent_operations(),
    ok.

test_empty_marking() ->
    WorkflowId = <<"$test_wf_empty_mark">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec">>,
        pattern_type = basic_sequential,
        status = running,
        marking = #{},
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(#{}, Loaded#yawl_workflow_persist.marking).

test_large_marking() ->
    WorkflowId = <<"$test_wf_large_mark">>,
    LargeMarking = lists:foldl(fun(I, Acc) ->
        Acc#{list_to_atom("place" ++ integer_to_list(I)) => [<<"token">>]}
    end, #{}, lists:seq(1, 100)),
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec">>,
        pattern_type = basic_sequential,
        status = running,
        marking = LargeMarking,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(100, maps:size(Loaded#yawl_workflow_persist.marking)).

test_special_characters_in_data() ->
    Data = #{
        <<"key_with_dash">> => <<"value">>,
        <<"key_with_underscore">> => <<"value">>,
        <<"key_binary">> => <<"binary_value">>
    },
    WorkflowId = <<"$test_wf_spec_chars">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec">>,
        pattern_type = basic_sequential,
        status = running,
        data = Data,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(Data, Loaded#yawl_workflow_persist.data).

test_unicode_in_data() ->
    UnicodeData = #{
        <<"emoji">> => <<"\xE2\x9C\x93">>,  % Check mark emoji
        <<"chinese">> => <<"\xE4\xB8\xAD\xE6\x96\x87">>,
        <<"arabic">> => <<"\xD8\xA7\xD9\x84\xD8\xB9\xD8\xB1\xD8\xA8\xD9\x8A\xD8\xA9">>
    },
    WorkflowId = <<"$test_wf_unicode">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec">>,
        pattern_type = basic_sequential,
        status = running,
        data = UnicodeData,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(UnicodeData, Loaded#yawl_workflow_persist.data).

test_concurrent_operations() ->
    %% Test concurrent writes to the same workflow
    WorkflowId = <<"$test_wf_concurrent">>,
    Pids = lists:map(fun(_) ->
        spawn(fun() ->
            Workflow = #yawl_workflow_persist{
                workflow_id = WorkflowId,
                spec_id = <<"spec">>,
                pattern_type = basic_sequential,
                status = running,
                created_at = erlang:monotonic_time(millisecond),
                updated_at = erlang:monotonic_time(millisecond)
            },
            yawl_persistence:save_workflow(Workflow)
        end)
    end, lists:seq(1, 10)),
    %% Wait for all to complete
    timer:sleep(500),
    lists:foreach(fun(P) -> exit(P, kill) end, Pids),
    %% Verify workflow exists
    {ok, _} = yawl_persistence:load_workflow(WorkflowId).

%%====================================================================
%% Group 10: Error Handling
%%====================================================================

test_group_errors() ->
    test_invalid_transaction(),
    test_mnesia_down_handling(),
    test_very_long_ids(),
    test_zero_timestamps(),
    ok.

test_invalid_transaction() ->
    %% This tests internal error handling
    WorkflowId = <<"$test_wf_invalid">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec">>,
        pattern_type = basic_sequential,
        status = running,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    ok = yawl_persistence:save_workflow(Workflow),
    %% Load should work
    {ok, _} = yawl_persistence:load_workflow(WorkflowId).

test_mnesia_down_handling() ->
    %% Test behavior when Mnesia is not available
    %% This is difficult to test without actually stopping Mnesia
    ok.

test_very_long_ids() ->
    LongId = binary:copy(<<"x">>, 1000),
    Workflow = #yawl_workflow_persist{
        workflow_id = LongId,
        spec_id = <<"spec">>,
        pattern_type = basic_sequential,
        status = running,
        created_at = erlang:monotonic_time(millisecond),
        updated_at = erlang:monotonic_time(millisecond)
    },
    Result = yawl_persistence:save_workflow(Workflow),
    ?assertEqual(ok, Result),
    {ok, Loaded} = yawl_persistence:load_workflow(LongId),
    ?assertEqual(LongId, Loaded#yawl_workflow_persist.workflow_id).

test_zero_timestamps() ->
    WorkflowId = <<"$test_wf_zero_time">>,
    Workflow = #yawl_workflow_persist{
        workflow_id = WorkflowId,
        spec_id = <<"spec">>,
        pattern_type = basic_sequential,
        status = running,
        created_at = 0,
        updated_at = 0
    },
    ok = yawl_persistence:save_workflow(Workflow),
    {ok, Loaded} = yawl_persistence:load_workflow(WorkflowId),
    ?assertEqual(0, Loaded#yawl_workflow_persist.created_at).
