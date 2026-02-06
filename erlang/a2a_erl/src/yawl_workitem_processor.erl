%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL Work Item Processor
%%%
%%% This module handles the execution of individual work items (tasks)
%%% within a workflow. It supports:
%%%
%%% - Human task allocation with resource manager integration
%%% - Automated service calls with resource manager integration
%%% - Code execution for custom tasks
%%% - Retry policies
%%% - Work item persistence
%%% - Resource lifecycle management
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_workitem_processor).
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

%% API exports
-export([
    execute_task/4,
    execute_human_task/3,
    execute_service_task/4,
    execute_code_task/4,
    get_workitem_status/2,
    cancel_workitem/2,
    retry_workitem/2,
    list_workitems/1
]).

%% Persistence exports
-export([
    save_workitem/1,
    load_workitem/1,
    delete_workitem/1,
    update_workitem_state/2,
    load_workitems_from_mnesia/0
]).

-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    workitems :: #{binary() => #yawl_workitem_persist{}},
    task_queue :: queue:queue(),
    active_executions :: #{binary() => pid()},
    max_concurrent :: pos_integer(),
    retry_config :: map()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the work item processor.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Execute a task (dispatches based on type).
-spec execute_task(binary(), atom(), map(), map()) -> {ok, binary()} | {error, term()}.
execute_task(WorkflowId, TaskId, TaskData, Options) ->
    gen_server:call(?MODULE, {execute_task, WorkflowId, TaskId, TaskData, Options}).

%% @doc Execute a human task.
-spec execute_human_task(binary(), atom(), map()) -> {ok, binary()} | {error, term()}.
execute_human_task(WorkflowId, TaskId, UserData) ->
    gen_server:call(?MODULE, {execute_human_task, WorkflowId, TaskId, UserData}).

%% @doc Execute a service task.
-spec execute_service_task(binary(), atom(), binary(), map()) -> {ok, binary()} | {error, term()}.
execute_service_task(WorkflowId, TaskId, ServiceName, Params) ->
    gen_server:call(?MODULE, {execute_service_task, WorkflowId, TaskId, ServiceName, Params}).

%% @doc Execute a code task.
-spec execute_code_task(binary(), atom(), module(), atom()) -> {ok, binary()} | {error, term()}.
execute_code_task(WorkflowId, TaskId, Module, Function) ->
    gen_server:call(?MODULE, {execute_code_task, WorkflowId, TaskId, Module, Function}).

%% @doc Get the status of a work item.
-spec get_workitem_status(binary(), binary()) -> {ok, workitem_status(), map()} | {error, term()}.
get_workitem_status(WorkflowId, WorkitemId) ->
    gen_server:call(?MODULE, {get_workitem_status, WorkflowId, WorkitemId}).

%% @doc Cancel a work item.
-spec cancel_workitem(binary(), binary()) -> ok | {error, term()}.
cancel_workitem(WorkflowId, WorkitemId) ->
    gen_server:call(?MODULE, {cancel_workitem, WorkflowId, WorkitemId}).

%% @doc Retry a failed work item.
-spec retry_workitem(binary(), binary()) -> ok | {error, term()}.
retry_workitem(WorkflowId, WorkitemId) ->
    gen_server:call(?MODULE, {retry_workitem, WorkflowId, WorkitemId}).

%% @doc List all work items for a workflow.
-spec list_workitems(binary()) -> {ok, [#yawl_workitem_persist{}]}.
list_workitems(WorkflowId) ->
    gen_server:call(?MODULE, {list_workitems, WorkflowId}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    %% Load existing workitems from Mnesia
    case load_workitems_from_mnesia() of
        {ok, ExistingWorkitems} ->
            State = #state{
                workitems = maps:from_list([
                    {WI#yawl_workitem_persist.workitem_id, WI}
                    || WI <- ExistingWorkitems
                ]),
                task_queue = queue:new(),
                active_executions = #{},
                max_concurrent = 50,
                retry_config = #{
                    max_attempts => 3,
                    initial_delay => 1000,
                    max_delay => 30000,
                    backoff_factor => 2.0
                }
            },
            {ok, State};
        {error, Reason} ->
            %% Continue with empty state but log error
            error_logger:error_msg("Failed to load workitems from Mnesia: ~p~n", [Reason]),
            State = #state{
                workitems = #{},
                task_queue = queue:new(),
                active_executions = #{},
                max_concurrent = 50,
                retry_config = #{
                    max_attempts => 3,
                    initial_delay => 1000,
                    max_delay => 30000,
                    backoff_factor => 2.0
                }
            },
            {ok, State}
    end.

%% @private
handle_call({execute_task, WorkflowId, TaskId, TaskData, Options}, _From, State) ->
    TaskType = maps:get(task_type, TaskData, code),
    WorkitemId = generate_workitem_id(WorkflowId, TaskId),

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = WorkflowId,
        task_id = TaskId,
        task_name = maps:get(task_name, TaskData, atom_to_binary(TaskId, utf8)),
        status = pending,
        data = TaskData,
        retry_count = 0,
        priority = maps:get(priority, Options, normal)
    },

    %% Persist the workitem to Mnesia
    case save_workitem(Workitem) of
        ok ->
            NewWorkitems = maps:put(WorkitemId, Workitem, State#state.workitems),
            NewState = State#state{workitems = NewWorkitems},
            case dispatch_workitem(Workitem, NewState) of
                {ok, UpdatedState} ->
                    {reply, {ok, WorkitemId}, UpdatedState};
                {error, Reason} ->
                    {reply, {error, Reason}, NewState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({execute_human_task, WorkflowId, TaskId, UserData}, _From, State) ->
    WorkitemId = generate_workitem_id(WorkflowId, TaskId),

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = WorkflowId,
        task_id = TaskId,
        task_name = maps:get(task_name, UserData, atom_to_binary(TaskId, utf8)),
        status = pending,
        data = UserData,
        retry_count = 0,
        priority = maps:get(priority, UserData, normal)
    },

    %% Persist the workitem to Mnesia
    case save_workitem(Workitem) of
        ok ->
            NewWorkitems = maps:put(WorkitemId, Workitem, State#state.workitems),
            NewState = State#state{workitems = NewWorkitems},
            case allocate_human_task_with_resource_manager(Workitem, NewState) of
                {ok, FinalState} ->
                    {reply, {ok, WorkitemId}, FinalState};
                {error, Reason} ->
                    {reply, {error, Reason}, NewState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({execute_service_task, WorkflowId, TaskId, ServiceName, Params}, _From, State) ->
    WorkitemId = generate_workitem_id(WorkflowId, TaskId),

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = WorkflowId,
        task_id = TaskId,
        task_name = ServiceName,
        status = pending,
        data = #{service_name => ServiceName, params => Params},
        retry_count = 0,
        priority = maps:get(priority, Params, normal)
    },

    %% Persist the workitem to Mnesia
    case save_workitem(Workitem) of
        ok ->
            NewWorkitems = maps:put(WorkitemId, Workitem, State#state.workitems),
            NewState = State#state{workitems = NewWorkitems},
            case execute_service_with_resource_manager(Workitem, NewState) of
                {ok, FinalState} ->
                    {reply, {ok, WorkitemId}, FinalState};
                {error, Reason} ->
                    {reply, {error, Reason}, NewState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({execute_code_task, WorkflowId, TaskId, Module, Function}, _From, State) ->
    WorkitemId = generate_workitem_id(WorkflowId, TaskId),

    Workitem = #yawl_workitem_persist{
        workitem_id = WorkitemId,
        workflow_id = WorkflowId,
        task_id = TaskId,
        task_name = atom_to_binary(TaskId, utf8),
        status = pending,
        data = #{module => Module, function => Function},
        retry_count = 0,
        priority = normal
    },

    %% Persist the workitem to Mnesia
    case save_workitem(Workitem) of
        ok ->
            NewWorkitems = maps:put(WorkitemId, Workitem, State#state.workitems),
            NewState = State#state{workitems = NewWorkitems},
            case execute_code(Workitem, NewState) of
                {ok, FinalState} ->
                    {reply, {ok, WorkitemId}, FinalState};
                {error, Reason} ->
                    {reply, {error, Reason}, NewState}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({get_workitem_status, _WorkflowId, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.workitems, undefined) of
        undefined ->
            {reply, {error, workitem_not_found}, State};
        #yawl_workitem_persist{status = Status, data = Data} = _Workitem ->
            {reply, {ok, Status, Data}, State}
    end;

handle_call({cancel_workitem, WorkflowId, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.workitems, undefined) of
        undefined ->
            {reply, {error, workitem_not_found}, State};
        Workitem ->
            %% Release allocated resources before cancellation
            release_workitem_resources(Workitem),

            %% Cancel active execution if any
            ActiveExecutions = case maps:get(WorkitemId, State#state.active_executions, undefined) of
                undefined -> State#state.active_executions;
                Pid ->
                    exit(Pid, kill),
                    maps:remove(WorkitemId, State#state.active_executions)
            end,

            CancelledWorkitem = Workitem#yawl_workitem_persist{
                status = cancelled,
                completion_time = erlang:monotonic_time(millisecond)
            },

            %% Persist the cancelled workitem
            case save_workitem(CancelledWorkitem) of
                ok ->
                    NewWorkitems = maps:put(WorkitemId, CancelledWorkitem, State#state.workitems),
                    {reply, ok, State#state{workitems = NewWorkitems, active_executions = ActiveExecutions}};
                {error, Reason} ->
                    error_logger:error_msg("Failed to save cancelled workitem: ~p~n", [Reason]),
                    {reply, {error, Reason}, State}
            end
    end;

handle_call({retry_workitem, WorkflowId, WorkitemId}, _From, State) ->
    case maps:get(WorkitemId, State#state.workitems, undefined) of
        undefined ->
            {reply, {error, workitem_not_found}, State};
        #yawl_workitem_persist{status = failed, retry_count = RetryCount} = Workitem ->
            MaxAttempts = maps:get(max_attempts, State#state.retry_config, 3),
            case RetryCount < MaxAttempts of
                true ->
                    NewWorkitem = Workitem#yawl_workitem_persist{
                        status = pending,
                        retry_count = RetryCount + 1
                    },
                    %% Persist the retried workitem
                    case save_workitem(NewWorkitem) of
                        ok ->
                            NewWorkitems = maps:put(WorkitemId, NewWorkitem, State#state.workitems),
                            NewState = State#state{workitems = NewWorkitems},
                            case dispatch_workitem(NewWorkitem, NewState) of
                                {ok, FinalState} ->
                                    {reply, ok, FinalState};
                                {error, Reason} ->
                                    {reply, {error, Reason}, NewState}
                            end;
                        {error, Reason} ->
                            {reply, {error, Reason}, State}
                    end;
                false ->
                    {reply, {error, max_retries_exceeded}, State}
            end;
        _ ->
            {reply, {error, workitem_not_failed}, State}
    end;

handle_call({list_workitems, WorkflowId}, _From, State) ->
    %% Use persistence layer for fresh data
    case yawl_persistence:list_workitems(WorkflowId) of
        {ok, Workitems} ->
            {reply, {ok, Workitems}, State};
        {error, Reason} ->
            %% Fall back to local cache if persistence fails
            error_logger:error_msg("Failed to load workitems from persistence: ~p~n", [Reason]),
            CachedWorkitems = lists:filter(
                fun(#yawl_workitem_persist{workflow_id = WID}) -> WID =:= WorkflowId end,
                maps:values(State#state.workitems)
            ),
            {reply, {ok, CachedWorkitems}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({workitem_complete, WorkitemId, Result}, State) ->
    case maps:get(WorkitemId, State#state.workitems, undefined) of
        undefined ->
            {noreply, State};
        Workitem ->
            %% Release allocated resource if any
            release_workitem_resources(Workitem),

            CompletedWorkitem = Workitem#yawl_workitem_persist{
                status = completed,
                completion_time = erlang:monotonic_time(millisecond),
                data = maps:merge(Workitem#yawl_workitem_persist.data, Result)
            },
            %% Persist the completed workitem
            case save_workitem(CompletedWorkitem) of
                ok ->
                    NewWorkitems = maps:put(WorkitemId, CompletedWorkitem, State#state.workitems),
                    NewExecutions = maps:remove(WorkitemId, State#state.active_executions),
                    {noreply, State#state{workitems = NewWorkitems, active_executions = NewExecutions}};
                {error, Reason} ->
                    error_logger:error_msg("Failed to save completed workitem: ~p~n", [Reason]),
                    %% Keep workitem in state but log error
                    NewWorkitems = maps:put(WorkitemId, CompletedWorkitem, State#state.workitems),
                    NewExecutions = maps:remove(WorkitemId, State#state.active_executions),
                    {noreply, State#state{workitems = NewWorkitems, active_executions = NewExecutions}}
            end
    end;

handle_info({workitem_failed, WorkitemId, Reason}, State) ->
    case maps:get(WorkitemId, State#state.workitems, undefined) of
        undefined ->
            {noreply, State};
        Workitem ->
            %% Release allocated resource if any
            release_workitem_resources(Workitem),

            FailedWorkitem = Workitem#yawl_workitem_persist{
                status = failed,
                completion_time = erlang:monotonic_time(millisecond),
                error = Reason
            },
            %% Persist the failed workitem
            case save_workitem(FailedWorkitem) of
                ok ->
                    NewWorkitems = maps:put(WorkitemId, FailedWorkitem, State#state.workitems),
                    NewExecutions = maps:remove(WorkitemId, State#state.active_executions),
                    {noreply, State#state{workitems = NewWorkitems, active_executions = NewExecutions}};
                {error, PersistReason} ->
                    error_logger:error_msg("Failed to save failed workitem: ~p~n", [PersistReason]),
                    %% Keep workitem in state but log error
                    NewWorkitems = maps:put(WorkitemId, FailedWorkitem, State#state.workitems),
                    NewExecutions = maps:remove(WorkitemId, State#state.active_executions),
                    {noreply, State#state{workitems = NewWorkitems, active_executions = NewExecutions}}
            end
    end;

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
dispatch_workitem(#yawl_workitem_persist{data = Data} = Workitem, State) ->
    TaskType = maps:get(task_type, Data, code),
    case TaskType of
        human -> allocate_human_task_with_resource_manager(Workitem, State);
        service -> execute_service_with_resource_manager(Workitem, State);
        code -> execute_code(Workitem, State);
        _ -> execute_code(Workitem, State)
    end.

%% @private
allocate_human_task_with_resource_manager(Workitem, State) ->
    %% Extract human task requirements from workitem data
    RequiredCapabilities = case maps:get(capabilities, Workitem#yawl_workitem_persist.data, []) of
        [] -> [human_task];  %% Default capability for human tasks
        Caps -> Caps
    end,

    %% Try to allocate a human resource
    case yawl_resource_manager:allocate_resource(
        Workitem#yawl_workitem_persist.workitem_id,
        human,
        RequiredCapabilities
    ) of
        {ok, ResourceId, Resource} ->
            %% Update workitem with allocation information
            AllocatedWorkitem = Workitem#yawl_workitem_persist{
                status = allocated,
                allocated_to = {ResourceId, Resource},
                allocation_time = erlang:monotonic_time(millisecond),
                data = maps:put(
                    allocated_resource,
                    Resource,
                    Workitem#yawl_workitem_persist.data
                )
            },

            %% Persist the allocated workitem
            case save_workitem(AllocatedWorkitem) of
                ok ->
                    %% Notify human task service about allocation
                    case yawl_human_task:notify_allocation(AllocatedWorkitem, ResourceId) of
                        ok ->
                            NewWorkitems = maps:put(
                                Workitem#yawl_workitem_persist.workitem_id,
                                AllocatedWorkitem,
                                State#state.workitems
                            ),
                            %% Track resource allocation in state
                            ActiveAllocations = case State#state.active_executions of
                                undefined -> #{};
                                Execs -> Execs
                            end,
                            UpdatedAllocations = maps:put(
                                Workitem#yawl_workitem_persist.workitem_id,
                                allocated,
                                ActiveAllocations
                            ),

                            {ok, State#state{
                                workitems = NewWorkitems,
                                active_executions = UpdatedAllocations
                            }};
                        {error, NotifyReason} ->
                            error_logger:error_msg(
                                "Failed to notify human task service of allocation: ~p~n",
                                [NotifyReason]
                            ),
                            %% Release resource since notification failed
                            catch yawl_resource_manager:release_resource(
                                Workitem#yawl_workitem_persist.workitem_id
                            ),
                            {error, {notification_failed, NotifyReason}}
                    end;
                {error, PersistReason} ->
                    error_logger:error_msg("Failed to save allocated workitem: ~p~n", [PersistReason]),
                    %% Release resource since persistence failed
                    catch yawl_resource_manager:release_resource(
                        Workitem#yawl_workitem_persist.workitem_id
                    ),
                    {error, {persistence_failed, PersistReason}}
            end;
        {error, no_available_resources} ->
            %% Try fallback to human task service
            case yawl_human_task:allocate_task(Workitem) of
                {ok, AllocatedWorkitem} ->
                    UpdatedWorkitem = AllocatedWorkitem#yawl_workitem_persist{
                        status = allocated,
                        allocation_time = erlang:monotonic_time(millisecond)
                    },
                    case save_workitem(UpdatedWorkitem) of
                        ok ->
                            NewWorkitems = maps:put(
                                Workitem#yawl_workitem_persist.workitem_id,
                                UpdatedWorkitem,
                                State#state.workitems
                            ),
                            {ok, State#state{workitems = NewWorkitems}};
                        {error, PersistReason} ->
                            error_logger:error_msg("Failed to save allocated workitem: ~p~n", [PersistReason]),
                            {error, {persistence_failed, PersistReason}}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @private
execute_service_with_resource_manager(Workitem, State) ->
    %% Extract service requirements from workitem data
    ServiceName = maps:get(service_name, Workitem#yawl_workitem_persist.data, undefined),

    %% Define service capabilities based on service type
    ServiceCapabilities = case ServiceName of
        _ -> [external_service]  %% Default capability for external services
    end,

    %% Try to allocate a service resource
    case yawl_resource_manager:allocate_resource(
        Workitem#yawl_workitem_persist.workitem_id,
        service,
        ServiceCapabilities
    ) of
        {ok, ResourceId, Resource} ->
            %% Update workitem with resource allocation
            AllocatedWorkitem = Workitem#yawl_workitem_persist{
                status = started,
                allocated_to = {ResourceId, Resource},
                start_time = erlang:monotonic_time(millisecond),
                data = maps:put(
                    allocated_resource,
                    Resource,
                    Workitem#yawl_workitem_persist.data
                )
            },

            %% Persist the started workitem
            case save_workitem(AllocatedWorkitem) of
                ok ->
                    %% Track resource allocation in state
                    ActiveAllocations = case State#state.active_executions of
                        undefined -> #{};
                        Execs -> Execs
                    end,
                    UpdatedAllocations = maps:put(
                        Workitem#yawl_workitem_persist.workitem_id,
                        allocated,
                        ActiveAllocations
                    ),

                    %% Execute service with resource monitoring
                    spawn_service_execution(AllocatedWorkitem, ResourceId, State#state{
                        active_executions = UpdatedAllocations
                    });
                {error, PersistReason} ->
                    error_logger:error_msg("Failed to save allocated service workitem: ~p~n", [PersistReason]),
                    %% Release resource since persistence failed
                    catch yawl_resource_manager:release_resource(
                        Workitem#yawl_workitem_persist.workitem_id
                    ),
                    {error, {persistence_failed, PersistReason}}
            end;
        {error, no_available_resources} ->
            %% Direct service call as fallback
            execute_service_direct(Workitem, State);
        {error, Reason} ->
            %% Try direct service call as fallback
            execute_service_direct(Workitem, State)
    end.

%% @private
execute_service_direct(Workitem, State) ->
    %% Get service from registry and call it directly
    ServiceName = maps:get(service_name, Workitem#yawl_workitem_persist.data, undefined),
    Params = maps:get(params, Workitem#yawl_workitem_persist.data, #{}),

    case yawl_service_registry:call_service(ServiceName, Params) of
        {ok, Result} ->
            UpdatedWorkitem = Workitem#yawl_workitem_persist{
                status = completed,
                data = maps:put(result, Result, Workitem#yawl_workitem_persist.data),
                completion_time = erlang:monotonic_time(millisecond)
            },
            %% Persist the completed workitem
            case save_workitem(UpdatedWorkitem) of
                ok ->
                    NewWorkitems = maps:put(
                        Workitem#yawl_workitem_persist.workitem_id,
                        UpdatedWorkitem,
                        State#state.workitems
                    ),
                    {ok, State#state{workitems = NewWorkitems}};
                {error, PersistReason} ->
                    error_logger:error_msg("Failed to save completed workitem: ~p~n", [PersistReason]),
                    {error, {persistence_failed, PersistReason}}
            end;
        {error, Reason} ->
            FailedWorkitem = Workitem#yawl_workitem_persist{
                status = failed,
                error = Reason,
                completion_time = erlang:monotonic_time(millisecond)
            },
            %% Persist the failed workitem
            case save_workitem(FailedWorkitem) of
                ok ->
                    NewWorkitems = maps:put(
                        Workitem#yawl_workitem_persist.workitem_id,
                        FailedWorkitem,
                        State#state.workitems
                    ),
                    {ok, State#state{workitems = NewWorkitems}};
                {error, PersistReason} ->
                    error_logger:error_msg("Failed to save failed workitem: ~p~n", [PersistReason]),
                    {error, {persistence_failed, PersistReason}}
            end
    end.

%% @private
execute_code(Workitem, State) ->
    Module = maps:get(module, Workitem#yawl_workitem_persist.data, undefined),
    Function = maps:get(function, Workitem#yawl_workitem_persist.data, undefined),
    Args = maps:get(args, Workitem#yawl_workitem_persist.data, []),

    spawn_monitor_execution(Workitem, Module, Function, Args),

    %% Update workitem to started status and persist
    StartedWorkitem = Workitem#yawl_workitem_persist{
        status = started,
        start_time = erlang:monotonic_time(millisecond)
    },
    %% Persist the started workitem
    case save_workitem(StartedWorkitem) of
        ok ->
            NewWorkitems = maps:put(
                Workitem#yawl_workitem_persist.workitem_id,
                StartedWorkitem,
                State#state.workitems
            ),
            {ok, State#state{workitems = NewWorkitems}};
        {error, Reason} ->
            error_logger:error_msg("Failed to save started workitem: ~p~n", [Reason]),
            {error, {persistence_failed, Reason}}
    end.

%% @private
spawn_monitor_execution(Workitem, Module, Function, Args) ->
    WorkitemId = Workitem#yawl_workitem_persist.workitem_id,
    ProcessorPid = self(),

    {Pid, _MRef} = spawn_monitor(fun() ->
        try
            Result = apply(Module, Function, Args),
            ProcessorPid ! {workitem_complete, WorkitemId, #{result => Result}}
        catch
            Type:Error:Stacktrace ->
                ProcessorPid ! {workitem_failed, WorkitemId, {Type, Error, Stacktrace}}
        end
    end),

    %% Track active execution
    %% (In a real implementation, we'd update state here)
    ok.

%% @private
spawn_service_execution(Workitem, ResourceId, _State) ->
    WorkitemId = Workitem#yawl_workitem_persist.workitem_id,
    ProcessorPid = self(),

    {_Pid, _MRef} = spawn_monitor(fun() ->
        try
            %% Execute the service with monitoring
            ServiceName = maps:get(service_name, Workitem#yawl_workitem_persist.data),
            Params = maps:get(params, Workitem#yawl_workitem_persist.data, #{}),

            %% Update resource status to processing
            catch yawl_resource_manager:update_resource_status(ResourceId, busy),

            %% Call the service
            case yawl_service_registry:call_service(ServiceName, Params) of
                {ok, Result} ->
                    %% Update resource status to available
                    catch yawl_resource_manager:update_resource_status(ResourceId, available),
                    catch yawl_resource_manager:update_resource_load(ResourceId, 0),

                    %% Notify completion
                    ProcessorPid ! {workitem_complete, WorkitemId, #{result => Result}};
                {error, Reason} ->
                    %% Update resource status and notify failure
                    catch yawl_resource_manager:update_resource_status(ResourceId, available),
                    catch yawl_resource_manager:update_resource_load(ResourceId, 0),

                    ProcessorPid ! {workitem_failed, WorkitemId, Reason}
            end
        catch
            Type:Error:Stacktrace ->
                %% Ensure resource is released on error
                catch yawl_resource_manager:update_resource_status(ResourceId, available),
                catch yawl_resource_manager:update_resource_load(ResourceId, 0),
                catch yawl_resource_manager:release_resource(WorkitemId),

                ProcessorPid ! {workitem_failed, WorkitemId, {Type, Error, Stacktrace}}
        end
    end),

    %% Track the execution
    ok.

%% @private
generate_workitem_id(WorkflowId, TaskId) ->
    Timestamp = erlang:unique_integer([positive, monotonic]),
    <<WorkflowId/binary, "_",
      (atom_to_binary(TaskId, utf8))/binary, "_",
      (integer_to_binary(Timestamp))/binary>>.

%%====================================================================
%% Persistence Functions
%%====================================================================

%% @doc Save a workitem to Mnesia.
-spec save_workitem(#yawl_workitem_persist{}) -> ok | {error, term()}.
save_workitem(#yawl_workitem_persist{} = Workitem) ->
    yawl_persistence:save_workitem(Workitem).

%% @doc Load a workitem from Mnesia.
-spec load_workitem(binary()) -> {ok, #yawl_workitem_persist{}} | {error, term()}.
load_workitem(WorkitemId) ->
    yawl_persistence:load_workitem(WorkitemId).

%% @doc Delete a workitem from Mnesia.
-spec delete_workitem(binary()) -> ok | {error, term()}.
delete_workitem(WorkitemId) ->
    case yawl_persistence:delete_workitem(WorkitemId) of
        ok ->
            %% Remove from local cache if present
            ok;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Load all workitems from Mnesia for recovery.
-spec load_workitems_from_mnesia() -> {ok, [#yawl_workitem_persist{}]} | {error, term()}.
load_workitems_from_mnesia() ->
    %% Use the persistence layer to load all workitems
    case yawl_persistence:list_workitems(<<>>) of
        {ok, Workitems} ->
            %% Filter only workitems that are not completed/failed
            ActiveWorkitems = lists:filter(
                fun(#yawl_workitem_persist{status = Status}) ->
                    lists:member(Status, [pending, allocated, started])
                end,
                Workitems
            ),
            {ok, ActiveWorkitems};
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Update workitem state.
-spec update_workitem_state(binary(), workitem_status()) -> ok | {error, term()}.
update_workitem_state(WorkitemId, NewStatus) ->
    do_update_workitem_state(WorkitemId, NewStatus, #{}).

%% @private implementation of update_workitem_state.
-spec do_update_workitem_state(binary(), workitem_status(), map()) -> {ok, #yawl_workitem_persist{}} | {error, term()}.
do_update_workitem_state(WorkitemId, NewStatus, AdditionalData) ->
    %% First load the current workitem
    case load_workitem(WorkitemId) of
        {ok, CurrentWorkitem} ->
            %% Create updated workitem
            UpdatedWorkitem = CurrentWorkitem#yawl_workitem_persist{
                status = NewStatus
            },
            %% Add timestamp based on status change
            UpdatedWithTime = case NewStatus of
                completed -> UpdatedWorkitem#yawl_workitem_persist{
                    completion_time = erlang:monotonic_time(millisecond),
                    data = maps:merge(UpdatedWorkitem#yawl_workitem_persist.data, AdditionalData)
                };
                started -> UpdatedWorkitem#yawl_workitem_persist{
                    start_time = erlang:monotonic_time(millisecond),
                    data = maps:merge(UpdatedWorkitem#yawl_workitem_persist.data, AdditionalData)
                };
                allocated -> UpdatedWorkitem#yawl_workitem_persist{
                    allocation_time = erlang:monotonic_time(millisecond),
                    data = maps:merge(UpdatedWorkitem#yawl_workitem_persist.data, AdditionalData)
                };
                _ -> UpdatedWorkitem#yawl_workitem_persist{
                    data = maps:merge(UpdatedWorkitem#yawl_workitem_persist.data, AdditionalData)
                }
            end,
            %% Save the updated workitem
            case save_workitem(UpdatedWithTime) of
                ok ->
                    {ok, UpdatedWithTime};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%%====================================================================
%% Resource Management Functions
%%====================================================================

%% @private
release_workitem_resources(#yawl_workitem_persist{workitem_id = WorkitemId} = Workitem) ->
    %% Extract resource information from workitem
    case maps:get(allocated_resource, Workitem#yawl_workitem_persist.data, undefined) of
        undefined ->
            %% No allocated resource, check allocated_to field
            case Workitem#yawl_workitem_persist.allocated_to of
                undefined ->
                    ok;
                {ResourceId, _Resource} ->
                    %% Release resource via resource manager
                    catch yawl_resource_manager:release_resource(WorkitemId, ResourceId);
                _ ->
                    ok
            end;
        ResourceMap ->
            %% Resource was stored in data field, extract ID and release
            ResourceId = maps:get(resource_id, ResourceMap, undefined),
            case ResourceId of
                undefined -> ok;
                _ -> catch yawl_resource_manager:release_resource(WorkitemId, ResourceId)
            end
    end.