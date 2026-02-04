%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Persistence Manager
%%%
%%% This module provides persistent storage for YAWL workflows using
%%% Mnesia. It supports:
%%%
%%% - Workflow state persistence
%%% - Work item persistence
%%% - Resource persistence
%%% - Checkpoint/recovery for workflows
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_persistence).
-author("A2A Team").
-behaviour(gen_server).

%% gen_server callbacks
-export([
    start_link/0,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% API exports - Schema management
-export([
    create_schema/0,
    create_tables/0,
    wait_for_tables/0,
    backup_tables/1
]).

%% API exports - Workflow operations
-export([
    save_workflow/1,
    load_workflow/1,
    delete_workflow/1,
    archive_workflow/1,
    list_workflows/0,
    list_workflows_by_status/1
]).

%% API exports - Work item operations
-export([
    save_workitem/1,
    load_workitem/1,
    delete_workitem/1,
    list_workitems/1,
    update_workitem_status/2
]).

%% API exports - Resource operations
-export([
    save_resource/1,
    load_resource/1,
    delete_resource/1,
    list_resources/0,
    list_resources_by_type/1,
    list_available_resources/0
]).

%% API exports - Checkpoint operations
-export([
    save_checkpoint/2,
    load_latest_checkpoint/1,
    list_checkpoints/1,
    delete_checkpoint/1,
    restore_from_checkpoint/1
]).

%% API exports - History operations
-export([
    save_history/1,
    get_workflow_history/1,
    delete_history/1
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    table_status :: map(),
    backup_interval :: integer() | undefined,
    checkpoint_interval :: integer() | undefined
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the persistence manager.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Create the Mnesia schema on this node.
-spec create_schema() -> ok | {error, term()}.
create_schema() ->
    case mnesia:create_schema([node()]) of
        ok -> ok;
        {error, {already_exists, _}} -> ok;
        Error -> Error
    end.

%% @doc Create all Mnesia tables.
-spec create_tables() -> ok | {error, term()}.
create_tables() ->
    mnesia:start(),
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
        {yawl_resource_persist, [
            {attributes, record_info(fields, yawl_resource_persist)},
            {index, [#yawl_resource_persist.resource_type, #yawl_resource_persist.status]},
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
        ]},
        {yawl_service_registry, [
            {attributes, record_info(fields, yawl_service_registry)},
            {index, [#yawl_service_registry.service_name, #yawl_service_registry.service_type]},
            {type, set},
            {disc_copies, [node()]}
        ]},
        {yawl_task_queue, [
            {attributes, record_info(fields, yawl_task_queue)},
            {index, [#yawl_task_queue.queue_name, #yawl_task_queue.assigned_user]},
            {type, bag},
            {disc_copies, [node()]}
        ]}
    ],

    Results = lists:map(fun({Table, Opts}) ->
        case mnesia:create_table(Table, Opts) of
            {atomic, ok} -> {Table, ok};
            {aborted, {already_exists, Table}} -> {Table, ok};
            {aborted, Reason} -> {Table, {error, Reason}}
        end
    end, Tables),

    case lists:all(fun({_, Result}) -> Result =:= ok end, Results) of
        true -> ok;
        false -> {error, creation_failed}
    end.

%% @doc Wait for all tables to be loaded.
-spec wait_for_tables() -> ok | {timeout, [atom()]} | {error, term()}.
wait_for_tables() ->
    Tables = [
        yawl_workflow_persist,
        yawl_workitem_persist,
        yawl_resource_persist,
        yawl_execution_history,
        yawl_checkpoint,
        yawl_service_registry,
        yawl_task_queue
    ],
    mnesia:wait_for_tables(Tables, 30000).

%% @doc Backup tables to a file.
-spec backup_tables(file:name_all()) -> ok | {error, term()}.
backup_tables(Destination) ->
    case mnesia:backup(Destination) of
        ok -> ok;
        {error, Reason} -> {error, Reason}
    end.

%% @doc Save a workflow.
-spec save_workflow(#yawl_workflow_persist{} | map()) -> ok | {error, term()}.
save_workflow(Workflow) when is_map(Workflow) ->
    Record = map_to_workflow_record(Workflow),
    save_workflow(Record);
save_workflow(#yawl_workflow_persist{} = Workflow) ->
    UpdatedWorkflow = Workflow#yawl_workflow_persist{updated_at = erlang:monotonic_time(millisecond)},
    Trans = fun() -> mnesia:write(UpdatedWorkflow) end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Load a workflow.
-spec load_workflow(binary()) -> {ok, #yawl_workflow_persist{}} | {error, term()}.
load_workflow(WorkflowId) ->
    Trans = fun() ->
        case mnesia:read(yawl_workflow_persist, WorkflowId) of
            [Workflow] -> {ok, Workflow};
            [] -> {error, not_found}
        end
    end,
    case mnesia:transaction(Trans) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Delete a workflow.
-spec delete_workflow(binary()) -> ok | {error, term()}.
delete_workflow(WorkflowId) ->
    Trans = fun() ->
        mnesia:delete(yawl_workflow_persist, WorkflowId, write)
    end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Archive a workflow (move to archive status).
-spec archive_workflow(binary()) -> ok | {error, term()}.
archive_workflow(WorkflowId) ->
    Trans = fun() ->
        case mnesia:read(yawl_workflow_persist, WorkflowId) of
            [Workflow] ->
                Archived = Workflow#yawl_workflow_persist{status = terminated},
                mnesia:write(Archived),
                ok;
            [] -> {error, not_found}
        end
    end,
    case mnesia:transaction(Trans) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc List all workflows.
-spec list_workflows() -> {ok, [#yawl_workflow_persist{}]}.
list_workflows() ->
    Trans = fun() ->
        mnesia:match_object(#yawl_workflow_persist{_ = '_'})
    end,
    case mnesia:transaction(Trans) of
        {atomic, Workflows} -> {ok, Workflows};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc List workflows by status.
-spec list_workflows_by_status(atom()) -> {ok, [#yawl_workflow_persist{}]}.
list_workflows_by_status(Status) ->
    Trans = fun() ->
        mnesia:index_read(yawl_workflow_persist, Status, #yawl_workflow_persist.status)
    end,
    case mnesia:transaction(Trans) of
        {atomic, Workflows} -> {ok, Workflows};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Save a work item.
-spec save_workitem(#yawl_workitem_persist{} | map()) -> ok | {error, term()}.
save_workitem(Workitem) when is_map(Workitem) ->
    Record = map_to_workitem_record(Workitem),
    save_workitem(Record);
save_workitem(#yawl_workitem_persist{} = Workitem) ->
    Trans = fun() -> mnesia:write(Workitem) end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Load a work item.
-spec load_workitem(binary()) -> {ok, #yawl_workitem_persist{}} | {error, term()}.
load_workitem(WorkitemId) ->
    Trans = fun() ->
        case mnesia:read(yawl_workitem_persist, WorkitemId) of
            [Workitem] -> {ok, Workitem};
            [] -> {error, not_found}
        end
    end,
    case mnesia:transaction(Trans) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Delete a work item.
-spec delete_workitem(binary()) -> ok | {error, term()}.
delete_workitem(WorkitemId) ->
    Trans = fun() ->
        mnesia:delete(yawl_workitem_persist, WorkitemId, write)
    end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc List work items for a workflow.
-spec list_workitems(binary()) -> {ok, [#yawl_workitem_persist{}]}.
list_workitems(WorkflowId) ->
    Trans = fun() ->
        mnesia:index_read(yawl_workitem_persist, WorkflowId, #yawl_workitem_persist.workflow_id)
    end,
    case mnesia:transaction(Trans) of
        {atomic, Workitems} -> {ok, Workitems};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Update work item status.
-spec update_workitem_status(binary(), workitem_status()) -> ok | {error, term()}.
update_workitem_status(WorkitemId, Status) ->
    Trans = fun() ->
        case mnesia:read(yawl_workitem_persist, WorkitemId) of
            [Workitem] ->
                Updated = case Status of
                    completed -> Workitem#yawl_workitem_persist{status = Status, completion_time = erlang:monotonic_time(millisecond)};
                    started -> Workitem#yawl_workitem_persist{status = Status, start_time = erlang:monotonic_time(millisecond)};
                    allocated -> Workitem#yawl_workitem_persist{status = Status, allocation_time = erlang:monotonic_time(millisecond)};
                    _ -> Workitem#yawl_workitem_persist{status = Status}
                end,
                mnesia:write(Updated),
                ok;
            [] -> {error, not_found}
        end
    end,
    case mnesia:transaction(Trans) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Save a resource.
-spec save_resource(#yawl_resource_persist{} | map()) -> ok | {error, term()}.
save_resource(Resource) when is_map(Resource) ->
    Record = map_to_resource_record(Resource),
    save_resource(Record);
save_resource(#yawl_resource_persist{} = Resource) ->
    Trans = fun() -> mnesia:write(Resource) end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Load a resource.
-spec load_resource(binary()) -> {ok, #yawl_resource_persist{}} | {error, term()}.
load_resource(ResourceId) ->
    Trans = fun() ->
        case mnesia:read(yawl_resource_persist, ResourceId) of
            [Resource] -> {ok, Resource};
            [] -> {error, not_found}
        end
    end,
    case mnesia:transaction(Trans) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Delete a resource.
-spec delete_resource(binary()) -> ok | {error, term()}.
delete_resource(ResourceId) ->
    Trans = fun() ->
        mnesia:delete(yawl_resource_persist, ResourceId, write)
    end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc List all resources.
-spec list_resources() -> {ok, [#yawl_resource_persist{}]}.
list_resources() ->
    Trans = fun() ->
        mnesia:match_object(#yawl_resource_persist{_ = '_'})
    end,
    case mnesia:transaction(Trans) of
        {atomic, Resources} -> {ok, Resources};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc List resources by type.
-spec list_resources_by_type(resource_type()) -> {ok, [#yawl_resource_persist{}]}.
list_resources_by_type(Type) ->
    Trans = fun() ->
        mnesia:index_read(yawl_resource_persist, Type, #yawl_resource_persist.resource_type)
    end,
    case mnesia:transaction(Trans) of
        {atomic, Resources} -> {ok, Resources};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc List available resources.
-spec list_available_resources() -> {ok, [#yawl_resource_persist{}]}.
list_available_resources() ->
    Trans = fun() ->
        mnesia:index_read(yawl_resource_persist, available, #yawl_resource_persist.status)
    end,
    case mnesia:transaction(Trans) of
        {atomic, Resources} -> {ok, Resources};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Save a checkpoint.
-spec save_checkpoint(binary(), #yawl_checkpoint{} | map()) -> ok | {error, term()}.
save_checkpoint(WorkflowId, Checkpoint) when is_map(Checkpoint) ->
    Record = map_to_checkpoint_record(Checkpoint),
    save_checkpoint(WorkflowId, Record);
save_checkpoint(WorkflowId, #yawl_checkpoint{} = Checkpoint) ->
    %% Update sequence number based on existing checkpoints
    UpdatedCheckpoint = case load_latest_checkpoint(WorkflowId) of
        {ok, Latest} ->
            Checkpoint#yawl_checkpoint{sequence_num = Latest#yawl_checkpoint.sequence_num + 1};
        {error, not_found} ->
            Checkpoint#yawl_checkpoint{sequence_num = 1}
    end,

    Trans = fun() ->
        mnesia:write(UpdatedCheckpoint),
        %% Also save workflow state if available
        case yawl_persistence:load_workflow(WorkflowId) of
            {ok, Workflow} ->
                UpdatedWorkflow = Workflow#yawl_workflow_persist{
                    updated_at = erlang:monotonic_time(millisecond)
                },
                mnesia:write(UpdatedWorkflow);
            {error, not_found} ->
                ok
        end
    end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Load the latest checkpoint for a workflow.
-spec load_latest_checkpoint(binary()) -> {ok, #yawl_checkpoint{}} | {error, term()}.
load_latest_checkpoint(WorkflowId) ->
    Trans = fun() ->
        Checkpoints = mnesia:index_read(yawl_checkpoint, WorkflowId, #yawl_checkpoint.workflow_id),
        case lists:sort(fun(A, B) ->
            A#yawl_checkpoint.sequence_num > B#yawl_checkpoint.sequence_num
        end, Checkpoints) of
            [Latest | _] -> {ok, Latest};
            [] -> {error, not_found}
        end
    end,
    case mnesia:transaction(Trans) of
        {atomic, Result} -> Result;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc List checkpoints for a workflow.
-spec list_checkpoints(binary()) -> {ok, [#yawl_checkpoint{}]}.
list_checkpoints(WorkflowId) ->
    Trans = fun() ->
        mnesia:index_read(yawl_checkpoint, WorkflowId, #yawl_checkpoint.workflow_id)
    end,
    case mnesia:transaction(Trans) of
        {atomic, Checkpoints} -> {ok, Checkpoints};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Delete a checkpoint.
-spec delete_checkpoint(binary()) -> ok | {error, term()}.
delete_checkpoint(CheckpointId) ->
    Trans = fun() ->
        mnesia:delete(yawl_checkpoint, CheckpointId, write)
    end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Restore workflow state from checkpoint.
%%
%% This function loads the latest checkpoint for a workflow and restores
%% the workflow state to that point. It handles both restoring an existing
%% workflow and creating a new one if needed.
%%
%% @param WorkflowId The ID of the workflow to restore
%% @return {ok, #yawl_checkpoint{}} if restoration was successful
%%         {error, no_checkpoint_found} if no checkpoint exists
%%         {error, Reason} if restoration failed
-spec restore_from_checkpoint(binary()) -> {ok, #yawl_checkpoint{}} | {error, term()}.
restore_from_checkpoint(WorkflowId) ->
    case load_latest_checkpoint(WorkflowId) of
        {ok, Checkpoint} ->
            %% Restore workflow data from checkpoint
            case restore_workflow_from_checkpoint(WorkflowId, Checkpoint) of
                ok -> {ok, Checkpoint};
                {error, Reason} -> {error, Reason}
            end;
        {error, not_found} ->
            {error, no_checkpoint_found};
        {error, Reason} ->
            {error, Reason}
    end.

%% @private
restore_workflow_from_checkpoint(WorkflowId, Checkpoint) ->
    Trans = fun() ->
        %% Load existing workflow or create a new one
        case mnesia:read(yawl_workflow_persist, WorkflowId) of
            [ExistingWorkflow] ->
                %% Restore workflow with checkpoint data
                RestoredWorkflow = ExistingWorkflow#yawl_workflow_persist{
                    marking = Checkpoint#yawl_checkpoint.marking,
                    data = Checkpoint#yawl_checkpoint.data,
                    updated_at = erlang:monotonic_time(millisecond),
                    status = running  %% Set to running to indicate restored workflow
                },
                mnesia:write(RestoredWorkflow);
            [] ->
                %% No existing workflow, create one from checkpoint
                NewWorkflow = #yawl_workflow_persist{
                    workflow_id = WorkflowId,
                    spec_id = maps:get(spec_id, Checkpoint#yawl_checkpoint.checkpoint_state, <<>>),
                    pattern_type = maps:get(pattern_type, Checkpoint#yawl_checkpoint.checkpoint_state, basic_sequential),
                    status = running,
                    marking = Checkpoint#yawl_checkpoint.marking,
                    data = Checkpoint#yawl_checkpoint.data,
                    created_at = erlang:monotonic_time(millisecond),
                    updated_at = erlang:monotonic_time(millisecond)
                },
                mnesia:write(NewWorkflow)
        end,

        %% Restore workitems from checkpoint data if present
        case maps:get(workitems, Checkpoint#yawl_checkpoint.checkpoint_state, []) of
            [] -> ok;
            Workitems ->
                lists:foreach(fun(Workitem) ->
                    mnesia:write(Workitem)
                end, Workitems)
        end,

        ok
    end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Save a history event.
-spec save_history(#yawl_execution_history{} | map()) -> ok | {error, term()}.
save_history(History) when is_map(History) ->
    Record = map_to_history_record(History),
    save_history(Record);
save_history(#yawl_execution_history{} = History) ->
    Trans = fun() -> mnesia:write(History) end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Get workflow history.
-spec get_workflow_history(binary()) -> {ok, [#yawl_execution_history{}]}.
get_workflow_history(WorkflowId) ->
    Trans = fun() ->
        mnesia:index_read(yawl_execution_history, WorkflowId, #yawl_execution_history.workflow_id)
    end,
    case mnesia:transaction(Trans) of
        {atomic, History} -> {ok, History};
        {aborted, Reason} -> {error, Reason}
    end.

%% @doc Delete workflow history.
-spec delete_history(binary()) -> ok | {error, term()}.
delete_history(WorkflowId) ->
    Trans = fun() ->
        Histories = mnesia:index_read(yawl_execution_history, WorkflowId, #yawl_execution_history.workflow_id),
        lists:foreach(fun(H) -> mnesia:delete_object(H) end, Histories),
        ok
    end,
    case mnesia:transaction(Trans) of
        {atomic, ok} -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    %% Ensure Mnesia is running and tables exist
    case mnesia:start() of
        ok -> ok;
        {error, {already_started, _}} -> ok
    end,

    %% Create tables if they don't exist
    case create_tables() of
        ok -> ok;
        {error, creation_failed} ->
            %% Tables might already exist, try waiting for them
            case wait_for_tables() of
                ok -> ok;
                {timeout, _} ->
                    %% Critical failure: persistence layer unavailable
                    error_logger:critical_msg("YAWL Persistence: Failed to initialize Mnesia tables. System cannot start without persistence.~n", []),
                    {stop, {shutdown, persistence_unavailable}};
                {error, Reason} ->
                    error_logger:critical_msg("YAWL Persistence: Failed to initialize Mnesia tables: ~p~n", [Reason]),
                    {stop, {shutdown, persistence_unavailable}}
            end
    end,

    State = #state{
        table_status = #{},
        backup_interval = undefined,
        checkpoint_interval = undefined
    },
    {ok, State}.

%% @private
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    %% Perform cleanup on termination
    case mnesia:stop() of
        ok -> ok;
        {error, {not_started, _}} -> ok;
        {error, Reason} ->
            error_logger:error_msg("YAWL Persistence: Failed to stop Mnesia: ~p~n", [Reason])
    end.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Helper Functions
%%====================================================================

%% @private
map_to_workflow_record(Map) ->
    #yawl_workflow_persist{
        workflow_id = maps:get(workflow_id, Map),
        spec_id = maps:get(spec_id, Map, <<>>),
        pattern_type = maps:get(pattern_type, Map, basic_sequential),
        status = maps:get(status, Map, pending),
        marking = maps:get(marking, Map, #{}),
        current_place = maps:get(current_place, Map, undefined),
        data = maps:get(data, Map, #{}),
        parent_workflow_id = maps:get(parent_workflow_id, Map, undefined),
        created_at = maps:get(created_at, Map, erlang:monotonic_time(millisecond)),
        updated_at = maps:get(updated_at, Map, erlang:monotonic_time(millisecond)),
        completed_at = maps:get(completed_at, Map, undefined),
        error = maps:get(error, Map, undefined)
    }.

%% @private
map_to_workitem_record(Map) ->
    #yawl_workitem_persist{
        workitem_id = maps:get(workitem_id, Map),
        workflow_id = maps:get(workflow_id, Map),
        task_id = maps:get(task_id, Map),
        task_name = maps:get(task_name, Map, <<>>),
        status = maps:get(status, Map, pending),
        data = maps:get(data, Map, #{}),
        allocated_to = maps:get(allocated_to, Map, undefined),
        allocation_time = maps:get(allocation_time, Map, undefined),
        start_time = maps:get(start_time, Map, undefined),
        completion_time = maps:get(completion_time, Map, undefined),
        error = maps:get(error, Map, undefined),
        retry_count = maps:get(retry_count, Map, 0),
        priority = maps:get(priority, Map, normal)
    }.

%% @private
map_to_resource_record(Map) ->
    #yawl_resource_persist{
        resource_id = maps:get(resource_id, Map),
        resource_type = maps:get(resource_type, Map, service),
        name = maps:get(name, Map, <<>>),
        capabilities = maps:get(capabilities, Map, []),
        attributes = maps:get(attributes, Map, #{}),
        status = maps:get(status, Map, available),
        current_load = maps:get(current_load, Map, 0),
        max_capacity = maps:get(max_capacity, Map, 10),
        last_heartbeat = maps:get(last_heartbeat, Map, undefined),
        metadata = maps:get(metadata, Map, #{})
    }.

%% @private
map_to_checkpoint_record(Map) ->
    #yawl_checkpoint{
        checkpoint_id = maps:get(checkpoint_id, Map),
        workflow_id = maps:get(workflow_id, Map),
        checkpoint_state = maps:get(checkpoint_state, Map, undefined),
        marking = maps:get(marking, Map, #{}),
        data = maps:get(data, Map, #{}),
        timestamp = maps:get(timestamp, Map, erlang:monotonic_time(millisecond)),
        sequence_num = maps:get(sequence_num, Map, 1)
    }.

%% @private
map_to_history_record(Map) ->
    #yawl_execution_history{
        history_id = maps:get(history_id, Map),
        workflow_id = maps:get(workflow_id, Map),
        workitem_id = maps:get(workitem_id, Map, undefined),
        event_type = maps:get(event_type, Map),
        event_data = maps:get(event_data, Map, #{}),
        timestamp = maps:get(timestamp, Map, erlang:monotonic_time(millisecond)),
        source = maps:get(source, Map, undefined)
    }.
