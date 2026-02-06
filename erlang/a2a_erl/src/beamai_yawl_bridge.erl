%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL-BeamAI Process Bridge
%%%
%%% Main bridge connecting the YAWL workflow engine to the BeamAI
%%% agent and process system. This module enables:
%%%
%%% - Converting YAWL workflow definitions into BeamAI process defs
%%% - Mapping YAWL work items to BeamAI tool invocations
%%% - Bridging YAWL orchestrator events to BeamAI agent callbacks
%%% - Running YAWL workflows as BeamAI agent tasks
%%% - Bidirectional state synchronization
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(beamai_yawl_bridge).
-behaviour(gen_server).

-include("../include/yawl_types.hrl").
-include("../include/yawl_schema.hrl").

%% API
-export([
    start_link/0,
    register_workflow/2,
    execute_as_agent/2,
    map_workitem_to_tool/1,
    get_workflow_agent/1,
    sync_state/2
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2
]).

-define(SERVER, ?MODULE).

-record(state, {
    workflows = #{} :: #{binary() => map()},      %% workflow_id => definition
    agents = #{} :: #{binary() => pid()},          %% workflow_id => agent_pid
    tool_mappings = #{} :: #{binary() => map()},   %% workitem_type => tool_def
    event_subscribers = [] :: [pid()],
    kernel_ref :: atom() | pid() | undefined
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the YAWL-BeamAI bridge server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Register a YAWL workflow definition for BeamAI integration.
%% Converts the YAWL workflow into a BeamAI process definition
%% and registers all work items as BeamAI tools.
-spec register_workflow(binary(), map()) -> {ok, binary()} | {error, term()}.
register_workflow(WorkflowId, WorkflowDef) ->
    gen_server:call(?SERVER, {register_workflow, WorkflowId, WorkflowDef}).

%% @doc Execute a registered YAWL workflow as a BeamAI agent task.
%% Spawns a BeamAI agent process that drives the YAWL workflow
%% using LLM-based decision-making for choices and routing.
-spec execute_as_agent(binary(), map()) -> {ok, pid(), binary()} | {error, term()}.
execute_as_agent(WorkflowId, InputData) ->
    gen_server:call(?SERVER, {execute_as_agent, WorkflowId, InputData}, 30000).

%% @doc Map a YAWL work item to a BeamAI tool definition.
%% Returns a tool_def map suitable for BeamAI kernel registration.
-spec map_workitem_to_tool(#yawl_workitem_persist{}) -> {ok, map()} | {error, term()}.
map_workitem_to_tool(Workitem) when is_record(Workitem, yawl_workitem_persist) ->
    gen_server:call(?SERVER, {map_workitem_to_tool, Workitem});
map_workitem_to_tool(_) ->
    {error, invalid_workitem}.

%% @doc Get the BeamAI agent pid for a running YAWL workflow.
-spec get_workflow_agent(binary()) -> {ok, pid()} | {error, not_found}.
get_workflow_agent(WorkflowId) ->
    gen_server:call(?SERVER, {get_workflow_agent, WorkflowId}).

%% @doc Synchronize state between a YAWL workflow instance and its
%% BeamAI agent. Direction: yawl_to_beamai | beamai_to_yawl | bidirectional.
-spec sync_state(binary(), atom()) -> ok | {error, term()}.
sync_state(WorkflowId, Direction) ->
    gen_server:call(?SERVER, {sync_state, WorkflowId, Direction}).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init([]) ->
    process_flag(trap_exit, true),
    KernelRef = try_get_kernel(),
    logger:info("YAWL-BeamAI bridge started, kernel=~p", [KernelRef]),
    {ok, #state{kernel_ref = KernelRef}}.

%% @private
handle_call({register_workflow, WorkflowId, WorkflowDef}, _From, State) ->
    #state{workflows = Workflows, tool_mappings = ToolMappings,
           kernel_ref = KernelRef} = State,
    case maps:is_key(WorkflowId, Workflows) of
        true ->
            {reply, {error, already_registered}, State};
        false ->
            %% Convert YAWL tasks to BeamAI tools and register them
            Tasks = maps:get(tasks, WorkflowDef, []),
            {NewToolMappings, ToolDefs} = build_tool_mappings(WorkflowId, Tasks, ToolMappings),
            register_tools_with_kernel(KernelRef, ToolDefs),

            %% Store the enriched workflow definition
            ProcessDef = workflow_to_process_def(WorkflowId, WorkflowDef),
            EnrichedDef = WorkflowDef#{
                process_def => ProcessDef,
                registered_at => erlang:system_time(millisecond)
            },
            NewWorkflows = Workflows#{WorkflowId => EnrichedDef},
            NewState = State#state{
                workflows = NewWorkflows,
                tool_mappings = NewToolMappings
            },
            notify_subscribers({workflow_registered, WorkflowId}, NewState),
            logger:info("Registered YAWL workflow ~s with ~p tasks", [WorkflowId, length(Tasks)]),
            {reply, {ok, WorkflowId}, NewState}
    end;

handle_call({execute_as_agent, WorkflowId, InputData}, _From, State) ->
    #state{workflows = Workflows, agents = Agents, kernel_ref = KernelRef} = State,
    case maps:find(WorkflowId, Workflows) of
        {ok, WorkflowDef} ->
            %% Launch a YAWL workflow instance
            case start_yawl_instance(WorkflowId, WorkflowDef, InputData) of
                {ok, InstanceId} ->
                    %% Spawn an agent process to drive the workflow
                    AgentPid = spawn_link(fun() ->
                        agent_loop(WorkflowId, InstanceId, KernelRef, InputData)
                    end),
                    NewAgents = Agents#{WorkflowId => AgentPid},
                    NewState = State#state{agents = NewAgents},
                    notify_subscribers({agent_started, WorkflowId, AgentPid}, NewState),
                    {reply, {ok, AgentPid, InstanceId}, NewState};
                {error, Reason} ->
                    {reply, {error, {instance_start_failed, Reason}}, State}
            end;
        error ->
            {reply, {error, workflow_not_found}, State}
    end;

handle_call({map_workitem_to_tool, Workitem}, _From, State) ->
    ToolDef = workitem_to_tool_def(Workitem),
    {reply, {ok, ToolDef}, State};

handle_call({get_workflow_agent, WorkflowId}, _From, #state{agents = Agents} = State) ->
    case maps:find(WorkflowId, Agents) of
        {ok, Pid} when is_pid(Pid) ->
            case is_process_alive(Pid) of
                true -> {reply, {ok, Pid}, State};
                false ->
                    NewAgents = maps:remove(WorkflowId, Agents),
                    {reply, {error, not_found}, State#state{agents = NewAgents}}
            end;
        _ ->
            {reply, {error, not_found}, State}
    end;

handle_call({sync_state, WorkflowId, Direction}, _From, State) ->
    #state{workflows = Workflows, agents = Agents} = State,
    case {maps:find(WorkflowId, Workflows), maps:find(WorkflowId, Agents)} of
        {{ok, _WorkflowDef}, {ok, AgentPid}} ->
            Result = do_sync_state(WorkflowId, AgentPid, Direction),
            {reply, Result, State};
        {{ok, _}, error} ->
            {reply, {error, no_agent_running}, State};
        _ ->
            {reply, {error, workflow_not_found}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({'EXIT', Pid, Reason}, #state{agents = Agents} = State) ->
    %% Clean up agents whose processes have exited
    NewAgents = maps:filter(fun(_WfId, APid) -> APid =/= Pid end, Agents),
    case Reason of
        normal -> ok;
        _ -> logger:warning("YAWL-BeamAI agent ~p exited: ~p", [Pid, Reason])
    end,
    {noreply, State#state{agents = NewAgents}};

handle_info({yawl_event, EventType, EventData}, State) ->
    handle_yawl_event(EventType, EventData, State),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{agents = Agents}) ->
    %% Signal all running agent processes to stop
    maps:foreach(fun(_WfId, Pid) ->
        case is_process_alive(Pid) of
            true -> exit(Pid, shutdown);
            false -> ok
        end
    end, Agents),
    ok.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @private Try to obtain a reference to the BeamAI kernel.
-spec try_get_kernel() -> atom() | undefined.
try_get_kernel() ->
    case whereis(beamai_kernel) of
        undefined -> undefined;
        _Pid -> beamai_kernel
    end.

%% @private Build tool mappings and definitions from YAWL tasks.
-spec build_tool_mappings(binary(), list(), map()) -> {map(), [map()]}.
build_tool_mappings(WorkflowId, Tasks, ExistingMappings) ->
    lists:foldl(fun(Task, {MappingsAcc, DefsAcc}) ->
        TaskId = maps:get(task_id, Task, maps:get(id, Task, <<"unknown">>)),
        TaskName = maps:get(name, Task, TaskId),
        ToolName = <<WorkflowId/binary, ".", (ensure_binary(TaskName))/binary>>,
        ToolDef = #{
            name => ToolName,
            function => fun(Args, Ctx) ->
                execute_yawl_task(WorkflowId, TaskId, Args, Ctx)
            end,
            description => maps:get(description, Task, <<"YAWL task: ", (ensure_binary(TaskName))/binary>>),
            parameters => maps:get(input_schema, Task, #{}),
            tags => [<<"yawl">>, <<"workflow">>, ensure_binary(WorkflowId)],
            metadata => #{
                source => yawl,
                workflow_id => WorkflowId,
                task_id => TaskId,
                original_task => Task
            }
        },
        Mapping = #{tool_name => ToolName, tool_def => ToolDef, task => Task},
        {MappingsAcc#{ToolName => Mapping}, [ToolDef | DefsAcc]}
    end, {ExistingMappings, []}, Tasks).

%% @private Register tool definitions with the BeamAI kernel.
-spec register_tools_with_kernel(atom() | pid() | undefined, [map()]) -> ok.
register_tools_with_kernel(undefined, _ToolDefs) ->
    ok;
register_tools_with_kernel(KernelRef, ToolDefs) ->
    try
        beamai:add_tools(KernelRef, ToolDefs)
    catch
        _:Err ->
            logger:warning("Failed to register tools with kernel: ~p", [Err]),
            ok
    end.

%% @private Convert a YAWL workflow definition to a BeamAI process definition.
-spec workflow_to_process_def(binary(), map()) -> map().
workflow_to_process_def(WorkflowId, WorkflowDef) ->
    PatternType = maps:get(pattern_type, WorkflowDef, basic_sequential),
    Tasks = maps:get(tasks, WorkflowDef, []),
    Steps = lists:map(fun(Task) ->
        TaskId = maps:get(task_id, Task, maps:get(id, Task, <<"unknown">>)),
        #{
            step_id => TaskId,
            step_type => task_type_to_step_type(maps:get(type, Task, automatic)),
            input_schema => maps:get(input_schema, Task, #{}),
            output_schema => maps:get(output_schema, Task, #{}),
            config => maps:get(config, Task, #{})
        }
    end, Tasks),
    #{
        process_id => WorkflowId,
        pattern => PatternType,
        steps => Steps,
        metadata => #{
            source => yawl,
            converted_at => erlang:system_time(millisecond)
        }
    }.

%% @private Convert a YAWL task type to a BeamAI step type.
-spec task_type_to_step_type(atom()) -> atom().
task_type_to_step_type(automatic) -> tool_call;
task_type_to_step_type(manual) -> human_input;
task_type_to_step_type(service) -> tool_call;
task_type_to_step_type(human) -> human_input;
task_type_to_step_type(Other) -> Other.

%% @private Convert a work item to a BeamAI tool definition.
-spec workitem_to_tool_def(#yawl_workitem_persist{}) -> map().
workitem_to_tool_def(#yawl_workitem_persist{} = WI) ->
    TaskName = ensure_binary(WI#yawl_workitem_persist.task_name),
    WorkflowId = WI#yawl_workitem_persist.workflow_id,
    WorkitemId = WI#yawl_workitem_persist.workitem_id,
    #{
        name => <<"yawl_workitem.", WorkitemId/binary>>,
        function => fun(Args, _Ctx) ->
            execute_workitem(WorkitemId, Args)
        end,
        description => <<"YAWL work item: ", TaskName/binary>>,
        parameters => maps:get(schema, WI#yawl_workitem_persist.data, #{}),
        tags => [<<"yawl">>, <<"workitem">>],
        metadata => #{
            source => yawl,
            workflow_id => WorkflowId,
            workitem_id => WorkitemId,
            task_name => TaskName,
            priority => WI#yawl_workitem_persist.priority
        }
    }.

%% @private Execute a YAWL task from the BeamAI tool framework.
-spec execute_yawl_task(binary(), term(), map(), map()) -> map().
execute_yawl_task(WorkflowId, TaskId, Args, _Context) ->
    case whereis(yawl_workitem_processor) of
        undefined ->
            #{status => error, reason => workitem_processor_unavailable};
        _Pid ->
            try
                WorkitemId = generate_id(<<"wi">>),
                Workitem = #yawl_workitem_persist{
                    workitem_id = WorkitemId,
                    workflow_id = WorkflowId,
                    task_id = TaskId,
                    task_name = ensure_binary(TaskId),
                    status = pending,
                    data = Args,
                    retry_count = 0,
                    priority = normal
                },
                case yawl_workitem_processor:process_workitem(Workitem) of
                    {ok, Result} ->
                        #{status => completed, result => Result, workitem_id => WorkitemId};
                    {error, Reason} ->
                        #{status => failed, reason => Reason, workitem_id => WorkitemId}
                end
            catch
                _:Err ->
                    #{status => error, reason => Err}
            end
    end.

%% @private Execute a specific work item.
-spec execute_workitem(binary(), map()) -> map().
execute_workitem(WorkitemId, Args) ->
    case whereis(yawl_workitem_processor) of
        undefined ->
            #{status => error, reason => processor_unavailable};
        _Pid ->
            case yawl_workitem_processor:complete_workitem(WorkitemId, Args) of
                ok -> #{status => completed, workitem_id => WorkitemId};
                {error, Reason} -> #{status => failed, reason => Reason}
            end
    end.

%% @private Start a YAWL workflow instance.
-spec start_yawl_instance(binary(), map(), map()) -> {ok, binary()} | {error, term()}.
start_yawl_instance(WorkflowId, WorkflowDef, InputData) ->
    case whereis(yawl_orchestrator) of
        undefined ->
            %% Create a local instance ID if orchestrator is not running
            InstanceId = generate_id(<<"inst">>),
            {ok, InstanceId};
        _Pid ->
            SpecId = maps:get(spec_id, WorkflowDef, WorkflowId),
            case yawl_orchestrator:start_workflow(SpecId, InputData) of
                {ok, InstanceId} -> {ok, InstanceId};
                {error, Reason} -> {error, Reason}
            end
    end.

%% @private Main agent loop that drives a YAWL workflow via BeamAI.
-spec agent_loop(binary(), binary(), atom() | pid() | undefined, map()) -> ok.
agent_loop(WorkflowId, InstanceId, KernelRef, InputData) ->
    %% Fetch current workflow state
    WorkflowState = get_yawl_state(InstanceId),
    Status = maps:get(status, WorkflowState, running),
    case Status of
        completed ->
            logger:info("YAWL-BeamAI agent for ~s completed", [WorkflowId]),
            ok;
        failed ->
            logger:error("YAWL-BeamAI agent for ~s failed", [WorkflowId]),
            ok;
        cancelled ->
            logger:info("YAWL-BeamAI agent for ~s cancelled", [WorkflowId]),
            ok;
        _ ->
            %% Get the next pending work items
            PendingItems = maps:get(pending_items, WorkflowState, []),
            process_pending_items(WorkflowId, InstanceId, KernelRef, PendingItems, InputData),
            %% Short sleep to avoid tight looping
            timer:sleep(100),
            agent_loop(WorkflowId, InstanceId, KernelRef, InputData)
    end.

%% @private Process pending work items via the BeamAI kernel.
-spec process_pending_items(binary(), binary(), atom() | pid() | undefined, list(), map()) -> ok.
process_pending_items(_WorkflowId, _InstanceId, _KernelRef, [], _InputData) ->
    ok;
process_pending_items(WorkflowId, InstanceId, KernelRef, [Item | Rest], InputData) ->
    ToolName = <<WorkflowId/binary, ".", (ensure_binary(maps:get(task_id, Item, <<"unknown">>)))/binary>>,
    TaskData = maps:merge(InputData, maps:get(data, Item, #{})),
    Context = #{
        workflow_id => WorkflowId,
        instance_id => InstanceId,
        item => Item
    },
    case KernelRef of
        undefined ->
            %% Direct execution without kernel
            execute_yawl_task(WorkflowId, maps:get(task_id, Item, <<"unknown">>), TaskData, Context);
        _ ->
            try
                beamai:invoke_tool(KernelRef, ToolName, TaskData, Context)
            catch
                _:Err ->
                    logger:warning("Tool invocation failed for ~s: ~p", [ToolName, Err])
            end
    end,
    process_pending_items(WorkflowId, InstanceId, KernelRef, Rest, InputData).

%% @private Get current YAWL workflow state.
-spec get_yawl_state(binary()) -> map().
get_yawl_state(InstanceId) ->
    case whereis(yawl_workflow_instance) of
        undefined ->
            #{status => unknown, pending_items => []};
        _Pid ->
            try
                case yawl_workflow_instance:get_state(InstanceId) of
                    {ok, WfState} -> WfState;
                    _ -> #{status => unknown, pending_items => []}
                end
            catch
                _:_ -> #{status => unknown, pending_items => []}
            end
    end.

%% @private Synchronize state between YAWL and BeamAI.
-spec do_sync_state(binary(), pid(), atom()) -> ok | {error, term()}.
do_sync_state(WorkflowId, AgentPid, Direction) ->
    case Direction of
        yawl_to_beamai ->
            YawlState = get_yawl_state(WorkflowId),
            AgentPid ! {sync_from_yawl, YawlState},
            ok;
        beamai_to_yawl ->
            AgentPid ! {request_state, self()},
            receive
                {agent_state, AgentState} ->
                    apply_beamai_state_to_yawl(WorkflowId, AgentState)
            after 5000 ->
                {error, sync_timeout}
            end;
        bidirectional ->
            case do_sync_state(WorkflowId, AgentPid, yawl_to_beamai) of
                ok -> do_sync_state(WorkflowId, AgentPid, beamai_to_yawl);
                Error -> Error
            end;
        _ ->
            {error, {invalid_direction, Direction}}
    end.

%% @private Apply BeamAI agent state back to the YAWL instance.
-spec apply_beamai_state_to_yawl(binary(), map()) -> ok | {error, term()}.
apply_beamai_state_to_yawl(WorkflowId, AgentState) ->
    case whereis(yawl_workflow_instance) of
        undefined -> {error, instance_manager_unavailable};
        _Pid ->
            Data = maps:get(data, AgentState, #{}),
            try
                yawl_workflow_instance:update_data(WorkflowId, Data),
                ok
            catch
                _:Err -> {error, Err}
            end
    end.

%% @private Forward a YAWL event to any active BeamAI agents.
-spec handle_yawl_event(atom(), map(), #state{}) -> ok.
handle_yawl_event(EventType, EventData, #state{agents = Agents}) ->
    WorkflowId = maps:get(workflow_id, EventData, undefined),
    case WorkflowId of
        undefined -> ok;
        _ ->
            case maps:find(WorkflowId, Agents) of
                {ok, AgentPid} ->
                    AgentPid ! {yawl_event, EventType, EventData};
                error ->
                    ok
            end
    end.

%% @private Notify event subscribers.
-spec notify_subscribers(term(), #state{}) -> ok.
notify_subscribers(Event, #state{event_subscribers = Subs}) ->
    lists:foreach(fun(Pid) ->
        case is_process_alive(Pid) of
            true -> Pid ! {beamai_yawl_bridge_event, Event};
            false -> ok
        end
    end, Subs).

%% @private Generate a unique identifier with a given prefix.
-spec generate_id(binary()) -> binary().
generate_id(Prefix) ->
    Rand = integer_to_binary(erlang:unique_integer([positive, monotonic])),
    Ts = integer_to_binary(erlang:system_time(millisecond)),
    <<Prefix/binary, "_", Ts/binary, "_", Rand/binary>>.

%% @private Ensure a value is a binary.
-spec ensure_binary(term()) -> binary().
ensure_binary(V) when is_binary(V) -> V;
ensure_binary(V) when is_atom(V) -> atom_to_binary(V, utf8);
ensure_binary(V) when is_list(V) -> list_to_binary(V);
ensure_binary(V) -> iolist_to_binary(io_lib:format("~p", [V])).
