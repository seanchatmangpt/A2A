%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL-A2A Task Bridge
%%%
%%% This module provides bidirectional integration between YAWL workflows
%%% and A2A tasks. It enables:
%%%
%%% - YAWL workflow tasks to be executed as A2A tasks
%%% - A2A tasks to be tracked within YAWL workflows
%%% - State synchronization between YAWL and A2A
%%% - Event notification for state changes
%%% - Checkpoint/recovery coordination
%%%
%%% ## Bidirectional Mapping
%%%
%%% YAWL -> A2A:
%%% - YAWL workitems become A2A tasks
%%% - YAWL workflow state maps to A2A task state
%%% - YAWL resources become A2A task metadata
%%%
%%% A2A -> YAWL:
%%% - A2A task completion updates YAWL workitems
%%% - A2A task failures trigger YAWL error handling
%%% - A2A artifacts become YAWL workflow data
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_a2a_bridge).
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

%% API exports - YAWL to A2A mapping
-export([
    create_a2a_task_from_workitem/1,
    create_a2a_task_from_workitem/2,
    sync_workitem_to_a2a_task/2,
    complete_workitem_from_a2a_task/2,
    fail_workitem_from_a2a_task/3
]).

%% API exports - A2A to YAWL mapping
-export([
    create_workflow_from_a2a_task/2,
    link_a2a_task_to_workflow/3,
    get_a2a_task_for_workitem/1,
    get_workflow_for_a2a_task/1
]).

%% API exports - State mapping
-export([
    map_yawl_state_to_a2a/1,
    map_a2a_state_to_yawl/1,
    is_terminal_state/1
]).

%% API exports - Event subscription
-export([
    subscribe_to_workitem_events/1,
    subscribe_to_task_events/1,
    unsubscribe_from_events/1,
    publish_event/2
]).

%% API exports - Checkpoint integration
-export([
    create_checkpoint/2,
    restore_from_checkpoint/2,
    get_checkpoint_state/1
]).

%% API exports - Resource allocation coordination
-export([
    allocate_resource_for_task/2,
    release_resource_for_task/2,
    get_task_resource/1,
    sync_resource_state/2
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").
-include("a2a.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    %% YAWL workitem -> A2A task mapping
    workitem_to_task :: #{binary() => binary()},
    %% A2A task -> YAWL workflow mapping
    task_to_workflow :: #{binary() => binary()},
    %% Event subscribers
    subscribers :: #{binary() => [pid()]},
    %% Checkpoint state
    checkpoints :: #{binary() => #yawl_checkpoint{}},
    %% Resource allocations
    resource_allocations :: #{binary() => binary()}
}).

-record(mapping, {
    workitem_id :: binary(),
    task_id :: binary(),
    workflow_id :: binary(),
    created_at :: integer(),
    updated_at :: integer(),
    state :: map()
}).

-type state() :: #state{}.
-type mapping() :: #mapping{}.

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the bridge.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Create an A2A task from a YAWL workitem.
-spec create_a2a_task_from_workitem(#yawl_workitem_persist{}) ->
    {ok, binary(), pid()} | {error, term()}.
create_a2a_task_from_workitem(Workitem) ->
    create_a2a_task_from_workitem(Workitem, #{}).

%% @doc Create an A2A task from a YAWL workitem with options.
-spec create_a2a_task_from_workitem(#yawl_workitem_persist{}, map()) ->
    {ok, binary(), pid()} | {error, term()}.
create_a2a_task_from_workitem(Workitem, Options) ->
    gen_server:call(?MODULE, {create_a2a_task, Workitem, Options}).

%% @doc Sync YAWL workitem state to A2A task.
-spec sync_workitem_to_a2a_task(binary(), binary()) -> ok | {error, term()}.
sync_workitem_to_a2a_task(WorkitemId, TaskId) ->
    gen_server:call(?MODULE, {sync_workitem, WorkitemId, TaskId}).

%% @doc Complete a workitem when A2A task completes.
-spec complete_workitem_from_a2a_task(binary(), binary()) -> ok | {error, term()}.
complete_workitem_from_a2a_task(TaskId, Result) ->
    gen_server:call(?MODULE, {complete_from_a2a, TaskId, Result}).

%% @doc Fail a workitem when A2A task fails.
-spec fail_workitem_from_a2a_task(binary(), binary(), term()) -> ok | {error, term()}.
fail_workitem_from_a2a_task(TaskId, WorkitemId, Reason) ->
    gen_server:call(?MODULE, {fail_from_a2a, TaskId, WorkitemId, Reason}).

%% @doc Create a YAWL workflow from an A2A task.
-spec create_workflow_from_a2a_task(binary(), atom()) -> {ok, binary()} | {error, term()}.
create_workflow_from_a2a_task(TaskId, PatternType) ->
    gen_server:call(?MODULE, {create_workflow, TaskId, PatternType}).

%% @doc Link an A2A task to a YAWL workflow.
-spec link_a2a_task_to_workflow(binary(), binary(), binary()) -> ok | {error, term()}.
link_a2a_task_to_workflow(TaskId, WorkflowId, WorkitemId) ->
    gen_server:call(?MODULE, {link_task, TaskId, WorkflowId, WorkitemId}).

%% @doc Get the A2A task ID for a workitem.
-spec get_a2a_task_for_workitem(binary()) -> {ok, binary()} | {error, not_found}.
get_a2a_task_for_workitem(WorkitemId) ->
    gen_server:call(?MODULE, {get_task_for_workitem, WorkitemId}).

%% @doc Get the YAWL workflow ID for an A2A task.
-spec get_workflow_for_a2a_task(binary()) -> {ok, binary()} | {error, not_found}.
get_workflow_for_a2a_task(TaskId) ->
    gen_server:call(?MODULE, {get_workflow_for_task, TaskId}).

%% @doc Map YAWL state to A2A state.
-spec map_yawl_state_to_a2a(workitem_status()) -> atom().
map_yawl_state_to_a2a(pending) -> ?TASK_STATE_SUBMITTED;
map_yawl_state_to_a2a(allocated) -> ?TASK_STATE_SUBMITTED;
map_yawl_state_to_a2a(started) -> ?TASK_STATE_WORKING;
map_yawl_state_to_a2a(completed) -> ?TASK_STATE_COMPLETED;
map_yawl_state_to_a2a(failed) -> ?TASK_STATE_FAILED;
map_yawl_state_to_a2a(cancelled) -> ?TASK_STATE_CANCELED;
map_yawl_state_to_a2a(_) -> ?TASK_STATE_SUBMITTED.

%% @doc Map A2A state to YAWL state.
-spec map_a2a_state_to_yawl(atom()) -> workitem_status().
map_a2a_state_to_yawl(?TASK_STATE_SUBMITTED) -> pending;
map_a2a_state_to_yawl(?TASK_STATE_WORKING) -> started;
map_a2a_state_to_yawl(?TASK_STATE_COMPLETED) -> completed;
map_a2a_state_to_yawl(?TASK_STATE_FAILED) -> failed;
map_a2a_state_to_yawl(?TASK_STATE_CANCELED) -> cancelled;
map_a2a_state_to_yawl(?TASK_STATE_INPUT_REQUIRED) -> started;
map_a2a_state_to_yawl(?TASK_STATE_AUTH_REQUIRED) -> started;
map_a2a_state_to_yawl(?TASK_STATE_REJECTED) -> cancelled;
map_a2a_state_to_yawl(_) -> pending.

%% @doc Check if a state is terminal.
-spec is_terminal_state(atom()) -> boolean().
is_terminal_state(State) ->
    lists:member(State, [?TASK_STATE_COMPLETED, ?TASK_STATE_FAILED,
                         ?TASK_STATE_CANCELED, ?TASK_STATE_REJECTED]).

%% @doc Subscribe to workitem events.
-spec subscribe_to_workitem_events(binary()) -> {ok, reference()} | {error, term()}.
subscribe_to_workitem_events(WorkitemId) ->
    gen_server:call(?MODULE, {subscribe, WorkitemId, self()}).

%% @doc Subscribe to task events.
-spec subscribe_to_task_events(binary()) -> {ok, reference()} | {error, term()}.
subscribe_to_task_events(TaskId) ->
    gen_server:call(?MODULE, {subscribe, TaskId, self()}).

%% @doc Unsubscribe from events.
-spec unsubscribe_from_events(reference()) -> ok.
unsubscribe_from_events(Ref) ->
    gen_server:cast(?MODULE, {unsubscribe, Ref}).

%% @doc Publish an event to subscribers.
-spec publish_event(binary(), term()) -> ok.
publish_event(EntityId, Event) ->
    gen_server:cast(?MODULE, {publish_event, EntityId, Event}).

%% @doc Create a checkpoint for an entity.
-spec create_checkpoint(binary(), binary()) -> {ok, binary()} | {error, term()}.
create_checkpoint(WorkflowId, CheckpointData) ->
    gen_server:call(?MODULE, {create_checkpoint, WorkflowId, CheckpointData}).

%% @doc Restore from a checkpoint.
-spec restore_from_checkpoint(binary(), binary()) -> {ok, map()} | {error, term()}.
restore_from_checkpoint(WorkflowId, CheckpointId) ->
    gen_server:call(?MODULE, {restore_checkpoint, WorkflowId, CheckpointId}).

%% @doc Get checkpoint state.
-spec get_checkpoint_state(binary()) -> {ok, map()} | {error, not_found}.
get_checkpoint_state(CheckpointId) ->
    gen_server:call(?MODULE, {get_checkpoint_state, CheckpointId}).

%% @doc Allocate a resource for a task.
-spec allocate_resource_for_task(binary(), [atom()]) ->
    {ok, binary()} | {error, term()}.
allocate_resource_for_task(TaskId, Capabilities) ->
    gen_server:call(?MODULE, {allocate_resource, TaskId, Capabilities}).

%% @doc Release a resource for a task.
-spec release_resource_for_task(binary(), binary()) -> ok | {error, term()}.
release_resource_for_task(TaskId, ResourceId) ->
    gen_server:call(?MODULE, {release_resource, TaskId, ResourceId}).

%% @doc Get the resource allocated to a task.
-spec get_task_resource(binary()) -> {ok, binary()} | {error, not_found}.
get_task_resource(TaskId) ->
    gen_server:call(?MODULE, {get_task_resource, TaskId}).

%% @doc Sync resource state between YAWL and A2A.
-spec sync_resource_state(binary(), map()) -> ok | {error, term()}.
sync_resource_state(ResourceId, State) ->
    gen_server:call(?MODULE, {sync_resource_state, ResourceId, State}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    %% Load existing mappings from persistence
    State = #state{
        workitem_to_task = #{},
        task_to_workflow = #{},
        subscribers = #{},
        checkpoints = #{},
        resource_allocations = #{}
    },
    {ok, State}.

%% @private
handle_call({create_a2a_task, Workitem, Options}, _From, State) ->
    WorkitemId = Workitem#yawl_workitem_persist.workitem_id,
    case maps:get(WorkitemId, State#state.workitem_to_task, undefined) of
        undefined ->
            case do_create_a2a_task(Workitem, Options) of
                {ok, TaskId, TaskPid} ->
                    NewWorkitemMap = maps:put(WorkitemId, TaskId, State#state.workitem_to_task),
                    NewTaskMap = maps:put(TaskId, Workitem#yawl_workitem_persist.workflow_id,
                                         State#state.task_to_workflow),
                    NewState = State#state{
                        workitem_to_task = NewWorkitemMap,
                        task_to_workflow = NewTaskMap
                    },
                    %% Publish event
                    publish_event(WorkitemId, {task_created, TaskId}),
                    {reply, {ok, TaskId, TaskPid}, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        TaskId ->
            %% Task already exists, return it
            case a2a_task_store:get_task_pid(TaskId) of
                {ok, Pid} -> {reply, {ok, TaskId, Pid}, State};
                {error, _} ->
                    %% Stale mapping, remove and recreate
                    NewState = State#state{
                        workitem_to_task = maps:remove(WorkitemId, State#state.workitem_to_task)
                    },
                    handle_call({create_a2a_task, Workitem, Options}, _From, NewState)
            end
    end;

handle_call({sync_workitem, WorkitemId, TaskId}, _From, State) ->
    case yawl_persistence:load_workitem(WorkitemId) of
        {ok, Workitem} ->
            A2AState = map_yawl_state_to_a2a(Workitem#yawl_workitem_persist.status),
            case a2a_task_store:get_task(TaskId) of
                {ok, Task} ->
                    case (Task#task.status)#task_status.state of
                        A2AState ->
                            {reply, ok, State};
                        _ ->
                            %% Update task state to match workitem
                            NewStatus = #task_status{
                                state = A2AState,
                                timestamp = erlang:monotonic_time(millisecond)
                            },
                            UpdatedTask = Task#task{status = NewStatus},
                            ok = a2a_task_store:update_task(UpdatedTask),
                            publish_event(WorkitemId, {state_synced, A2AState}),
                            {reply, ok, State}
                    end;
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({complete_from_a2a, TaskId, Result}, _From, State) ->
    case maps:get(TaskId, State#state.task_to_workflow, undefined) of
        undefined ->
            {reply, {error, task_not_mapped}, State};
        WorkflowId ->
            case find_workitem_for_task(TaskId, WorkflowId) of
                {ok, WorkitemId} ->
                    case yawl_persistence:load_workitem(WorkitemId) of
                        {ok, Workitem} ->
                            CompletedWorkitem = Workitem#yawl_workitem_persist{
                                status = completed,
                                completion_time = erlang:monotonic_time(millisecond),
                                data = maps:merge(Workitem#yawl_workitem_persist.data, Result)
                            },
                            case yawl_persistence:save_workitem(CompletedWorkitem) of
                                ok ->
                                    %% Update workflow instance if running
                                    notify_workflow_completion(WorkflowId, WorkitemId, Result),
                                    publish_event(WorkitemId, {workitem_completed, Result}),
                                    {reply, ok, State};
                                {error, Reason} ->
                                    {reply, {error, Reason}, State}
                            end;
                        {error, Reason} ->
                            {reply, {error, Reason}, State}
                    end;
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;

handle_call({fail_from_a2a, TaskId, WorkitemId, Reason}, _From, State) ->
    case yawl_persistence:load_workitem(WorkitemId) of
        {ok, Workitem} ->
            FailedWorkitem = Workitem#yawl_workitem_persist{
                status = failed,
                completion_time = erlang:monotonic_time(millisecond),
                error = Reason
            },
            case yawl_persistence:save_workitem(FailedWorkitem) of
                ok ->
                    %% Update workflow instance
                    WorkflowId = Workitem#yawl_workitem_persist.workflow_id,
                    notify_workflow_failure(WorkflowId, WorkitemId, Reason),
                    publish_event(WorkitemId, {workitem_failed, Reason}),
                    {reply, ok, State};
                {error, PersistReason} ->
                    {reply, {error, PersistReason}, State}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({create_workflow, TaskId, PatternType}, _From, State) ->
    case a2a_task_store:get_task(TaskId) of
        {ok, Task} ->
            Config = #{
                pattern_type => PatternType,
                workflow_data => #{
                    task_id => TaskId,
                    context_id => Task#task.context_id
                },
                metadata => #{
                    a2a_task_id => TaskId,
                    created_from => a2a_task
                }
            },
            case yawl_orchestrator:create_workflow(PatternType, Config) of
                {ok, WorkflowId} ->
                    NewTaskMap = maps:put(TaskId, WorkflowId, State#state.task_to_workflow),
                    NewState = State#state{task_to_workflow = NewTaskMap},
                    {reply, {ok, WorkflowId}, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({link_task, TaskId, WorkflowId, WorkitemId}, _From, State) ->
    NewTaskMap = maps:put(TaskId, WorkflowId, State#state.task_to_workflow),
    NewWorkitemMap = maps:put(WorkitemId, TaskId, State#state.workitem_to_task),
    NewState = State#state{
        task_to_workflow = NewTaskMap,
        workitem_to_task = NewWorkitemMap
    },
    {reply, ok, NewState};

handle_call({get_task_for_workitem, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.workitem_to_task, undefined) of
        undefined -> {reply, {error, not_found}, State};
        TaskId -> {reply, {ok, TaskId}, State}
    end;

handle_call({get_workflow_for_task, TaskId}, _From, State) ->
    case maps:get(TaskId, State#state.task_to_workflow, undefined) of
        undefined -> {reply, {error, not_found}, State};
        WorkflowId -> {reply, {ok, WorkflowId}, State}
    end;

handle_call({subscribe, EntityId, Pid}, _From, State) ->
    Ref = erlang:monitor(process, Pid),
    Subscribers = maps:get(EntityId, State#state.subscribers, []),
    NewSubscribers = maps:put(EntityId, [{Pid, Ref} | Subscribers], State#state.subscribers),
    NewState = State#state{subscribers = NewSubscribers},
    {reply, {ok, Ref}, NewState};

handle_call({create_checkpoint, WorkflowId, CheckpointData}, _From, State) ->
    CheckpointId = <<WorkflowId/binary, "_ckpt_",
                     (integer_to_binary(erlang:monotonic_time(millisecond)))/binary>>,
    Checkpoint = #yawl_checkpoint{
        checkpoint_id = CheckpointId,
        workflow_id = WorkflowId,
        checkpoint_state = CheckpointData,
        marking = maps:get(marking, CheckpointData, #{}),
        data = maps:get(data, CheckpointData, #{}),
        timestamp = erlang:monotonic_time(millisecond),
        sequence_num = 1
    },
    case yawl_persistence:save_checkpoint(WorkflowId, Checkpoint) of
        ok ->
            NewCheckpoints = maps:put(CheckpointId, Checkpoint, State#state.checkpoints),
            NewState = State#state{checkpoints = NewCheckpoints},
            publish_event(WorkflowId, {checkpoint_created, CheckpointId}),
            {reply, {ok, CheckpointId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({restore_checkpoint, WorkflowId, CheckpointId}, _From, State) ->
    case maps:get(CheckpointId, State#state.checkpoints,
                  yawl_persistence:load_latest_checkpoint(WorkflowId)) of
        #yawl_checkpoint{} = Checkpoint ->
            CheckpointState = maps:from_list([
                {marking, Checkpoint#yawl_checkpoint.marking},
                {data, Checkpoint#yawl_checkpoint.data},
                {state, Checkpoint#yawl_checkpoint.checkpoint_state}
            ]),
            publish_event(WorkflowId, {checkpoint_restored, CheckpointId}),
            {reply, {ok, CheckpointState}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State};
        undefined ->
            {reply, {error, not_found}, State}
    end;

handle_call({get_checkpoint_state, CheckpointId}, _From, State) ->
    case maps:get(CheckpointId, State#state.checkpoints, undefined) of
        undefined ->
            case yawl_persistence:load_latest_checkpoint(CheckpointId) of
                {ok, Checkpoint} ->
                    StateMap = #{
                        workflow_id => Checkpoint#yawl_checkpoint.workflow_id,
                        marking => Checkpoint#yawl_checkpoint.marking,
                        data => Checkpoint#yawl_checkpoint.data,
                        timestamp => Checkpoint#yawl_checkpoint.timestamp
                    },
                    {reply, {ok, StateMap}, State};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        Checkpoint ->
            StateMap = #{
                workflow_id => Checkpoint#yawl_checkpoint.workflow_id,
                marking => Checkpoint#yawl_checkpoint.marking,
                data => Checkpoint#yawl_checkpoint.data,
                timestamp => Checkpoint#yawl_checkpoint.timestamp
            },
            {reply, {ok, StateMap}, State}
    end;

handle_call({allocate_resource, TaskId, Capabilities}, _From, State) ->
    case yawl_resource_manager:allocate_resource(TaskId, Capabilities) of
        {ok, ResourceId, _Resource} ->
            NewAllocations = maps:put(TaskId, ResourceId, State#state.resource_allocations),
            NewState = State#state{resource_allocations = NewAllocations},
            publish_event(TaskId, {resource_allocated, ResourceId}),
            {reply, {ok, ResourceId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({release_resource, TaskId, ResourceId}, _From, State) ->
    case yawl_resource_manager:release_resource(TaskId, ResourceId) of
        ok ->
            NewAllocations = maps:remove(TaskId, State#state.resource_allocations),
            NewState = State#state{resource_allocations = NewAllocations},
            publish_event(TaskId, {resource_released, ResourceId}),
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({get_task_resource, TaskId}, _From, State) ->
    case maps:get(TaskId, State#state.resource_allocations, undefined) of
        undefined -> {reply, {error, not_found}, State};
        ResourceId -> {reply, {ok, ResourceId}, State}
    end;

handle_call({sync_resource_state, ResourceId, ResourceState}, _From, State) ->
    Status = maps_get(status, ResourceState, available),
    Load = maps_get(load, ResourceState, 0),
    case yawl_resource_manager:update_resource_status(ResourceId, Status) of
        ok ->
            case yawl_resource_manager:update_resource_load(ResourceId, Load) of
                ok ->
                    {reply, ok, State};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({unsubscribe, Ref}, State) ->
    %% Find and remove the subscription
    NewSubscribers = maps:map(fun(_EntityId, Subs) ->
        lists:keydelete(Ref, 2, Subs)
    end, State#state.subscribers),
    {noreply, State#state{subscribers = NewSubscribers}};

handle_cast({publish_event, EntityId, Event}, State) ->
    Subscribers = maps:get(EntityId, State#state.subscribers, []),
    lists:foreach(fun({Pid, _Ref}) ->
        Pid ! {yawl_a2a_event, EntityId, Event}
    end, Subscribers),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({'DOWN', Ref, process, _Pid, _Reason}, State) ->
    %% Remove subscriber with monitor ref
    NewSubscribers = maps:map(fun(_EntityId, Subs) ->
        lists:keydelete(Ref, 2, Subs)
    end, State#state.subscribers),
    {noreply, State#state{subscribers = NewSubscribers}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private
do_create_a2a_task(Workitem, Options) ->
    %% Create A2A message from workitem data
    WorkitemData = Workitem#yawl_workitem_persist.data,
    TaskName = Workitem#yawl_workitem_persist.task_name,

    Message = #message{
        message_id = generate_id(),
        context_id = maps_get(context_id, WorkitemData, generate_id()),
        task_id = Workitem#yawl_workitem_persist.workitem_id,
        role = user,
        parts = [#part{
            content = {text, maps_get(description, WorkitemData, <<TaskName/binary>>)}
        }],
        metadata = #{
            workitem_id => Workitem#yawl_workitem_persist.workitem_id,
            workflow_id => Workitem#yawl_workitem_persist.workflow_id,
            task_id => Workitem#yawl_workitem_persist.task_id
        }
    },

    %% Start A2A task
    TaskOpts = maps_merge2(#{
        handler_module => maps_get(handler_module, Options, undefined),
        metadata => #{
            yawl_workitem => Workitem#yawl_workitem_persist.workitem_id,
            yawl_workflow => Workitem#yawl_workitem_persist.workflow_id
        }
    }, Options),

    case a2a_task_sup:start_task(Message, TaskOpts) of
        {ok, TaskPid} ->
            TaskId = get_task_id_from_pid(TaskPid),
            {ok, TaskId, TaskPid};
        {error, Reason} ->
            {error, Reason}
    end.

%% @private
find_workitem_for_task(TaskId, WorkflowId) ->
    case yawl_persistence:list_workitems(WorkflowId) of
        {ok, Workitems} ->
            case lists:search(fun(W) ->
                case maps_get(a2a_task_id, W#yawl_workitem_persist.data, undefined) of
                    TaskId -> true;
                    _ -> false
                end
            end, Workitems) of
                {value, Workitem} -> {ok, Workitem#yawl_workitem_persist.workitem_id};
                false -> {error, workitem_not_found}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @private
notify_workflow_completion(WorkflowId, WorkitemId, Result) ->
    case whereis(yawl_orchestrator) of
        undefined -> ok;
        _Pid ->
            try
                %% Get workflow instance and notify it of task completion
                case yawl_orchestrator:get_status(WorkflowId) of
                    {ok, running} ->
                        %% Find the workflow instance process
                        case get_workflow_instance_pid(WorkflowId) of
                            {ok, WfPid} ->
                                yawl_workflow_instance:complete_task(WfPid,
                                    list_to_existing_atom(binary_to_list(WorkitemId)), Result);
                            _ -> ok
                        end;
                    _ -> ok
                end
            catch
                _:_ -> ok
            end
    end.

%% @private
notify_workflow_failure(WorkflowId, WorkitemId, Reason) ->
    case whereis(yawl_orchestrator) of
        undefined -> ok;
        _Pid ->
            try
                case get_workflow_instance_pid(WorkflowId) of
                    {ok, WfPid} ->
                        %% Update workflow state to reflect failure
                        yawl_persistence:update_workitem_status(WorkitemId, failed);
                    _ -> ok
                end
            catch
                _:_ -> ok
            end
    end.

%% @private
get_workflow_instance_pid(WorkflowId) ->
    %% Try to get the workflow instance from supervisor
    case supervisor:which_children(yawl_workflow_instance_sup) of
        Children ->
            case lists:search(fun({Id, _Pid, _Type, _Modules}) ->
                Id =:= WorkflowId
            end, Children) of
                {value, {_Id, Pid, _Type, _Modules}} when is_pid(Pid) -> {ok, Pid};
                _ -> {error, not_found}
            end;
        _ ->
            {error, not_found}
    end.

%% @private
get_task_id_from_pid(Pid) ->
    %% Get task ID from process info or registry
    case a2a_task_statem:get_task(Pid) of
        {ok, Task} -> Task#task.id;
        _ -> generate_id()
    end.

%% @private
generate_id() ->
    Bytes = crypto:strong_rand_bytes(16),
    Hex = binary:encode_hex(Bytes),
    <<A:8/binary, B:4/binary, C:4/binary, D:4/binary, E:12/binary>> = Hex,
    <<A/binary, "-", B/binary, "-", C/binary, "-", D/binary, "-", E/binary>>.

%% @private
maps_get(Key, Map, Default) ->
    case maps:find(Key, Map) of
        {ok, Value} -> Value;
        error -> Default
    end.

%% @private
maps_merge(Lists) when is_list(Lists) ->
    lists:foldl(fun maps:merge/2, #{}, Lists).

%% @private
maps_merge2(Map1, Map2) when is_map(Map1), is_map(Map2) ->
    maps:merge(Map1, Map2).
