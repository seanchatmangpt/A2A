%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Process Bridge
%%%
%%% Connects BeamAI's process framework to A2A's task processing
%%% system. This module provides bidirectional state mapping between
%%% A2A task states (submitted, working, completed, ...) and BeamAI
%%% process states (pending, executing, completed, ...), as well as
%%% process orchestration that wraps existing A2A task supervisors
%%% and YAWL workflow instances.
%%%
%%% Responsibilities:
%%% - Map A2A task states to BeamAI process states and vice versa
%%% - Allow YAWL workflows to be executed as BeamAI processes
%%% - Provide process lifecycle management wrapping a2a_task_sup
%%% - Track active processes and their state transitions
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(beamai_process_bridge).
-behaviour(gen_server).

-include("a2a.hrl").
-include("yawl_types.hrl").
-include("yawl_schema.hrl").

%% API
-export([
    start_link/0,
    start_link/1,
    start_process/2,
    stop_process/1,
    get_process_state/1,
    map_a2a_state/1,
    map_beamai_state/1,
    execute_workflow/2,
    list_processes/0,
    get_process_info/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%%%===================================================================
%%% Records
%%%===================================================================

-record(beamai_process, {
    process_id    :: binary(),
    type          :: a2a_task | yawl_workflow | composite,
    a2a_state     :: atom() | undefined,
    beamai_state  :: atom(),
    pid           :: pid() | undefined,
    monitor_ref   :: reference() | undefined,
    workflow_id   :: binary() | undefined,
    task_id       :: binary() | undefined,
    created_at    :: integer(),
    updated_at    :: integer(),
    metadata      :: map()
}).

-record(state, {
    processes     :: #{binary() => #beamai_process{}},
    pid_index     :: #{pid() => binary()},
    config        :: map(),
    metrics       :: map()
}).

-define(SERVER, ?MODULE).

-define(DEFAULT_CONFIG, #{
    max_processes => 10000,
    process_timeout => 600000,
    enable_workflow_bridge => true
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the process bridge with default configuration.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the process bridge with custom configuration.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%% @doc Start a new BeamAI process backed by an A2A task or YAWL workflow.
%% Type is one of: a2a_task | yawl_workflow | composite.
%% Params contains the initialization data for the process.
-spec start_process(atom(), map()) -> {ok, binary()} | {error, term()}.
start_process(Type, Params) ->
    gen_server:call(?SERVER, {start_process, Type, Params}).

%% @doc Stop a running BeamAI process.
-spec stop_process(binary()) -> ok | {error, term()}.
stop_process(ProcessId) ->
    gen_server:call(?SERVER, {stop_process, ProcessId}).

%% @doc Get the current state of a BeamAI process including both
%% the A2A state and the BeamAI state representation.
-spec get_process_state(binary()) -> {ok, map()} | {error, not_found}.
get_process_state(ProcessId) ->
    gen_server:call(?SERVER, {get_process_state, ProcessId}).

%% @doc Map an A2A task state atom to the corresponding BeamAI process state.
-spec map_a2a_state(atom()) -> atom().
map_a2a_state(unspecified)    -> unknown;
map_a2a_state(submitted)      -> pending;
map_a2a_state(working)        -> executing;
map_a2a_state(completed)      -> completed;
map_a2a_state(failed)         -> failed;
map_a2a_state(canceled)       -> cancelled;
map_a2a_state(input_required) -> waiting_input;
map_a2a_state(auth_required)  -> waiting_auth;
map_a2a_state(rejected)       -> rejected;
map_a2a_state(Other)          -> Other.

%% @doc Map a BeamAI process state atom to the corresponding A2A task state.
-spec map_beamai_state(atom()) -> atom().
map_beamai_state(unknown)       -> unspecified;
map_beamai_state(pending)       -> submitted;
map_beamai_state(executing)     -> working;
map_beamai_state(completed)     -> completed;
map_beamai_state(failed)        -> failed;
map_beamai_state(cancelled)     -> canceled;
map_beamai_state(waiting_input) -> input_required;
map_beamai_state(waiting_auth)  -> auth_required;
map_beamai_state(rejected)      -> rejected;
map_beamai_state(Other)         -> Other.

%% @doc Execute a YAWL workflow as a BeamAI process.
%% PatternType is the YAWL pattern to use, WorkflowConfig contains
%% the workflow parameters.
-spec execute_workflow(atom(), map()) -> {ok, binary()} | {error, term()}.
execute_workflow(PatternType, WorkflowConfig) ->
    gen_server:call(?SERVER, {execute_workflow, PatternType, WorkflowConfig}, infinity).

%% @doc List all active BeamAI processes.
-spec list_processes() -> [map()].
list_processes() ->
    gen_server:call(?SERVER, list_processes).

%% @doc Get detailed info about a specific process.
-spec get_process_info(binary()) -> {ok, map()} | {error, not_found}.
get_process_info(ProcessId) ->
    gen_server:call(?SERVER, {get_process_info, ProcessId}).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init(UserConfig) ->
    process_flag(trap_exit, true),
    Config = maps:merge(?DEFAULT_CONFIG, UserConfig),
    State = #state{
        processes = #{},
        pid_index = #{},
        config = Config,
        metrics = #{
            processes_started => 0,
            processes_completed => 0,
            processes_failed => 0,
            workflows_executed => 0
        }
    },
    logger:info("BeamAI process bridge initialized"),
    {ok, State}.

%% @private
handle_call({start_process, Type, Params}, _From, State) ->
    #state{processes = Procs, config = Config, metrics = Metrics} = State,
    MaxProcs = maps:get(max_processes, Config, 10000),
    case map_size(Procs) >= MaxProcs of
        true ->
            {reply, {error, max_processes_reached}, State};
        false ->
            case do_start_process(Type, Params) of
                {ok, Process} ->
                    ProcessId = Process#beamai_process.process_id,
                    NewProcs = maps:put(ProcessId, Process, Procs),
                    NewPidIdx = case Process#beamai_process.pid of
                        undefined -> State#state.pid_index;
                        Pid -> maps:put(Pid, ProcessId, State#state.pid_index)
                    end,
                    Started = maps:get(processes_started, Metrics, 0),
                    NewMetrics = Metrics#{processes_started => Started + 1},
                    NewState = State#state{
                        processes = NewProcs,
                        pid_index = NewPidIdx,
                        metrics = NewMetrics
                    },
                    {reply, {ok, ProcessId}, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;

handle_call({stop_process, ProcessId}, _From, State) ->
    case maps:get(ProcessId, State#state.processes, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Process ->
            do_stop_process(Process),
            NewProcs = maps:remove(ProcessId, State#state.processes),
            NewPidIdx = case Process#beamai_process.pid of
                undefined -> State#state.pid_index;
                Pid -> maps:remove(Pid, State#state.pid_index)
            end,
            NewState = State#state{processes = NewProcs, pid_index = NewPidIdx},
            {reply, ok, NewState}
    end;

handle_call({get_process_state, ProcessId}, _From, State) ->
    case maps:get(ProcessId, State#state.processes, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Process ->
            %% Refresh state from the underlying A2A task if alive
            UpdatedProcess = refresh_process_state(Process),
            NewProcs = maps:put(ProcessId, UpdatedProcess, State#state.processes),
            StateMap = process_to_state_map(UpdatedProcess),
            {reply, {ok, StateMap}, State#state{processes = NewProcs}}
    end;

handle_call({execute_workflow, PatternType, WorkflowConfig}, _From, State) ->
    case do_execute_workflow(PatternType, WorkflowConfig) of
        {ok, Process} ->
            ProcessId = Process#beamai_process.process_id,
            NewProcs = maps:put(ProcessId, Process, State#state.processes),
            NewPidIdx = case Process#beamai_process.pid of
                undefined -> State#state.pid_index;
                Pid -> maps:put(Pid, ProcessId, State#state.pid_index)
            end,
            Metrics = State#state.metrics,
            WfCount = maps:get(workflows_executed, Metrics, 0),
            NewMetrics = Metrics#{workflows_executed => WfCount + 1},
            NewState = State#state{
                processes = NewProcs,
                pid_index = NewPidIdx,
                metrics = NewMetrics
            },
            {reply, {ok, ProcessId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(list_processes, _From, #state{processes = Procs} = State) ->
    List = maps:fold(fun(_Id, Proc, Acc) ->
        [process_to_summary_map(Proc) | Acc]
    end, [], Procs),
    {reply, lists:reverse(List), State};

handle_call({get_process_info, ProcessId}, _From, State) ->
    case maps:get(ProcessId, State#state.processes, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Process ->
            Updated = refresh_process_state(Process),
            NewProcs = maps:put(ProcessId, Updated, State#state.processes),
            Info = process_to_detail_map(Updated),
            {reply, {ok, Info}, State#state{processes = NewProcs}}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({'DOWN', MonRef, process, Pid, Reason}, State) ->
    case maps:get(Pid, State#state.pid_index, undefined) of
        undefined ->
            {noreply, State};
        ProcessId ->
            case maps:get(ProcessId, State#state.processes, undefined) of
                undefined ->
                    NewPidIdx = maps:remove(Pid, State#state.pid_index),
                    {noreply, State#state{pid_index = NewPidIdx}};
                Process ->
                    TerminalState = case Reason of
                        normal -> completed;
                        _ -> failed
                    end,
                    Now = erlang:system_time(millisecond),
                    UpdatedProcess = Process#beamai_process{
                        beamai_state = TerminalState,
                        a2a_state = map_beamai_state(TerminalState),
                        pid = undefined,
                        monitor_ref = undefined,
                        updated_at = Now
                    },
                    Metrics = State#state.metrics,
                    MetricKey = case TerminalState of
                        completed -> processes_completed;
                        _ -> processes_failed
                    end,
                    Count = maps:get(MetricKey, Metrics, 0),
                    NewMetrics = Metrics#{MetricKey => Count + 1},
                    NewProcs = maps:put(ProcessId, UpdatedProcess, State#state.processes),
                    NewPidIdx = maps:remove(Pid, State#state.pid_index),
                    {noreply, State#state{
                        processes = NewProcs,
                        pid_index = NewPidIdx,
                        metrics = NewMetrics
                    }}
            end
    end;

handle_info({'EXIT', Pid, Reason}, State) ->
    %% Handle linked process exits similarly to DOWN
    case maps:get(Pid, State#state.pid_index, undefined) of
        undefined ->
            {noreply, State};
        ProcessId ->
            Now = erlang:system_time(millisecond),
            case maps:get(ProcessId, State#state.processes, undefined) of
                undefined ->
                    {noreply, State};
                Process ->
                    TermState = case Reason of normal -> completed; _ -> failed end,
                    Updated = Process#beamai_process{
                        beamai_state = TermState,
                        a2a_state = map_beamai_state(TermState),
                        pid = undefined,
                        updated_at = Now
                    },
                    NewProcs = maps:put(ProcessId, Updated, State#state.processes),
                    NewPidIdx = maps:remove(Pid, State#state.pid_index),
                    {noreply, State#state{processes = NewProcs, pid_index = NewPidIdx}}
            end
    end;

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{processes = Procs}) ->
    %% Stop all active processes gracefully
    maps:foreach(fun(_Id, Proc) -> do_stop_process(Proc) end, Procs),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%% @private Start a new process of the given type.
-spec do_start_process(atom(), map()) -> {ok, #beamai_process{}} | {error, term()}.
do_start_process(a2a_task, Params) ->
    %% Create an A2A task via the existing task supervisor
    MessageText = maps:get(message, Params, <<"BeamAI process task">>),
    HandlerModule = maps:get(handler_module, Params, undefined),
    MsgId = generate_process_id(),
    Message = #message{
        message_id = MsgId,
        context_id = maps:get(context_id, Params, undefined),
        role = user,
        parts = [#part{content = {text, MessageText}}],
        metadata = maps:get(metadata, Params, #{})
    },
    Opts = case HandlerModule of
        undefined -> #{};
        Mod -> #{handler_module => Mod}
    end,
    case a2a_task_statem:start_link(Message, Opts) of
        {ok, TaskPid} ->
            MonRef = erlang:monitor(process, TaskPid),
            Now = erlang:system_time(millisecond),
            TaskId = case a2a_task_statem:get_task(TaskPid) of
                {ok, T} -> T#task.id;
                _ -> MsgId
            end,
            Process = #beamai_process{
                process_id = generate_process_id(),
                type = a2a_task,
                a2a_state = submitted,
                beamai_state = pending,
                pid = TaskPid,
                monitor_ref = MonRef,
                task_id = TaskId,
                created_at = Now,
                updated_at = Now,
                metadata = maps:get(metadata, Params, #{})
            },
            {ok, Process};
        {error, Reason} ->
            {error, Reason}
    end;

do_start_process(yawl_workflow, Params) ->
    PatternType = maps:get(pattern_type, Params, basic_sequential),
    do_execute_workflow(PatternType, Params);

do_start_process(composite, Params) ->
    %% A composite process that can contain both A2A tasks and workflows
    Now = erlang:system_time(millisecond),
    Process = #beamai_process{
        process_id = generate_process_id(),
        type = composite,
        a2a_state = undefined,
        beamai_state = pending,
        pid = undefined,
        monitor_ref = undefined,
        created_at = Now,
        updated_at = Now,
        metadata = maps:get(metadata, Params, #{})
    },
    {ok, Process};

do_start_process(Unknown, _Params) ->
    {error, {unknown_process_type, Unknown}}.

%% @private Execute a YAWL workflow and wrap it as a BeamAI process.
-spec do_execute_workflow(atom(), map()) -> {ok, #beamai_process{}} | {error, term()}.
do_execute_workflow(PatternType, WorkflowConfig) ->
    try
        case whereis(yawl_orchestrator) of
            undefined ->
                {error, yawl_orchestrator_not_running};
            _OrcPid ->
                Config = #{
                    pattern_type => PatternType,
                    workflow_data => maps:get(workflow_data, WorkflowConfig, #{}),
                    metadata => maps:get(metadata, WorkflowConfig, #{
                        source => beamai_process_bridge
                    })
                },
                case yawl_orchestrator:create_workflow(PatternType, Config) of
                    {ok, WorkflowId} ->
                        Now = erlang:system_time(millisecond),
                        Process = #beamai_process{
                            process_id = generate_process_id(),
                            type = yawl_workflow,
                            a2a_state = submitted,
                            beamai_state = pending,
                            pid = undefined,
                            monitor_ref = undefined,
                            workflow_id = WorkflowId,
                            created_at = Now,
                            updated_at = Now,
                            metadata = maps:get(metadata, WorkflowConfig, #{})
                        },
                        %% Attempt to execute the workflow
                        case yawl_orchestrator:execute_workflow(WorkflowId) of
                            {ok, _Result} ->
                                {ok, Process#beamai_process{
                                    beamai_state = executing,
                                    a2a_state = working
                                }};
                            {error, ExecReason} ->
                                {ok, Process#beamai_process{
                                    beamai_state = failed,
                                    a2a_state = failed,
                                    metadata = (Process#beamai_process.metadata)#{
                                        error => ExecReason
                                    }
                                }}
                        end;
                    {error, Reason} ->
                        {error, Reason}
                end
        end
    catch
        _:Error ->
            {error, {workflow_execution_failed, Error}}
    end.

%% @private Stop a process by terminating its underlying task or workflow.
-spec do_stop_process(#beamai_process{}) -> ok.
do_stop_process(#beamai_process{pid = undefined}) ->
    ok;
do_stop_process(#beamai_process{pid = Pid, monitor_ref = MonRef, type = a2a_task}) ->
    case MonRef of
        undefined -> ok;
        Ref -> erlang:demonitor(Ref, [flush])
    end,
    try a2a_task_statem:cancel_task(Pid)
    catch _:_ -> ok
    end,
    ok;
do_stop_process(#beamai_process{workflow_id = WfId, type = yawl_workflow})
  when WfId =/= undefined ->
    try yawl_orchestrator:cancel_workflow(WfId)
    catch _:_ -> ok
    end,
    ok;
do_stop_process(_) ->
    ok.

%% @private Refresh the state of a process from the underlying system.
-spec refresh_process_state(#beamai_process{}) -> #beamai_process{}.
refresh_process_state(#beamai_process{type = a2a_task, pid = Pid} = Proc)
  when is_pid(Pid) ->
    case is_process_alive(Pid) of
        true ->
            try
                case a2a_task_statem:get_task(Pid) of
                    {ok, Task} ->
                        A2AState = (Task#task.status)#task_status.state,
                        Now = erlang:system_time(millisecond),
                        Proc#beamai_process{
                            a2a_state = A2AState,
                            beamai_state = map_a2a_state(A2AState),
                            task_id = Task#task.id,
                            updated_at = Now
                        };
                    _ ->
                        Proc
                end
            catch
                _:_ -> Proc
            end;
        false ->
            Proc#beamai_process{
                beamai_state = completed,
                pid = undefined,
                updated_at = erlang:system_time(millisecond)
            }
    end;
refresh_process_state(#beamai_process{type = yawl_workflow, workflow_id = WfId} = Proc)
  when WfId =/= undefined ->
    try
        case yawl_orchestrator:get_status(WfId) of
            {ok, WfStatus} ->
                BeamaiState = map_workflow_status(WfStatus),
                A2AState = map_beamai_state(BeamaiState),
                Proc#beamai_process{
                    a2a_state = A2AState,
                    beamai_state = BeamaiState,
                    updated_at = erlang:system_time(millisecond)
                };
            _ ->
                Proc
        end
    catch
        _:_ -> Proc
    end;
refresh_process_state(Proc) ->
    Proc.

%% @private Map YAWL workflow status to BeamAI process state.
-spec map_workflow_status(atom()) -> atom().
map_workflow_status(pending)   -> pending;
map_workflow_status(running)   -> executing;
map_workflow_status(completed) -> completed;
map_workflow_status(failed)    -> failed;
map_workflow_status(cancelled) -> cancelled;
map_workflow_status(Other)     -> Other.

%% @private Convert process record to state map for external consumption.
-spec process_to_state_map(#beamai_process{}) -> map().
process_to_state_map(#beamai_process{} = P) ->
    #{
        process_id => P#beamai_process.process_id,
        a2a_state => P#beamai_process.a2a_state,
        beamai_state => P#beamai_process.beamai_state,
        is_terminal => is_terminal(P#beamai_process.beamai_state),
        is_active => P#beamai_process.pid =/= undefined
    }.

%% @private Convert process to a summary map.
-spec process_to_summary_map(#beamai_process{}) -> map().
process_to_summary_map(#beamai_process{} = P) ->
    #{
        process_id => P#beamai_process.process_id,
        type => P#beamai_process.type,
        beamai_state => P#beamai_process.beamai_state,
        created_at => P#beamai_process.created_at
    }.

%% @private Convert process to a detailed info map.
-spec process_to_detail_map(#beamai_process{}) -> map().
process_to_detail_map(#beamai_process{} = P) ->
    #{
        process_id => P#beamai_process.process_id,
        type => P#beamai_process.type,
        a2a_state => P#beamai_process.a2a_state,
        beamai_state => P#beamai_process.beamai_state,
        is_terminal => is_terminal(P#beamai_process.beamai_state),
        is_active => P#beamai_process.pid =/= undefined,
        workflow_id => P#beamai_process.workflow_id,
        task_id => P#beamai_process.task_id,
        created_at => P#beamai_process.created_at,
        updated_at => P#beamai_process.updated_at,
        metadata => P#beamai_process.metadata
    }.

%% @private Check if a BeamAI state is terminal.
-spec is_terminal(atom()) -> boolean().
is_terminal(completed) -> true;
is_terminal(failed)    -> true;
is_terminal(cancelled) -> true;
is_terminal(rejected)  -> true;
is_terminal(_)         -> false.

%% @private Generate a unique process identifier.
-spec generate_process_id() -> binary().
generate_process_id() ->
    Bytes = crypto:strong_rand_bytes(12),
    Hex = binary:encode_hex(Bytes),
    <<"bproc-", Hex/binary>>.
