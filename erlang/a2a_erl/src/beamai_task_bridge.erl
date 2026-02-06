%%% @doc BeamAI Task Bridge
%%%
%%% Bridges the existing a2a_task_statem (gen_statem) with beamai_a2a_task
%%% (gen_server). When a task is created through the bridge, both an
%%% a2a_task_statem process and a beamai_a2a_task process are started and
%%% kept in sync.
%%%
%%% This allows the system to maintain backward compatibility with the
%%% existing A2A protocol implementation while providing the BeamAI
%%% framework's map-based task interface.
%%%
%%% The bridge:
%%% - Monitors both processes and cleans up if either dies
%%% - Translates between the A2A record format (#task{}) and BeamAI map format
%%% - Syncs state changes bidirectionally
%%% - Records state transitions in the history tracker
%%% @end
-module(beamai_task_bridge).
-behaviour(gen_server).

-include("a2a.hrl").

%% API
-export([
    start_link/0,
    create_task/1,
    sync_state/2,
    get_unified_task/1,
    translate_to_beamai/1,
    translate_from_beamai/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2
]).

-record(bridge_state, {
    task_map = #{} :: #{binary() => {pid(), pid()}},  %% task_id => {a2a_pid, beamai_pid}
    monitors = #{} :: #{reference() => binary()}       %% monitor_ref => task_id
}).

-define(SERVER, ?MODULE).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the bridge process as a registered gen_server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Create a new task with both A2A and BeamAI representations.
%%
%% The Message is an A2A #message{} record used to initialize the
%% a2a_task_statem process. A corresponding beamai_a2a_task process
%% is also started with the translated map-based data.
%%
%% Returns {ok, TaskId, A2APid, BeamAIPid} on success.
-spec create_task(term()) -> {ok, binary(), pid(), pid()} | {error, term()}.
create_task(Message) ->
    gen_server:call(?SERVER, {create_task, Message}, 10000).

%% @doc Sync a state change from one side to the other.
%%
%% TaskId is the binary task ID; NewStatus is the new status atom.
%% The bridge will propagate the change to both the a2a_task_statem
%% and beamai_a2a_task processes.
-spec sync_state(binary(), atom()) -> ok | {error, term()}.
sync_state(TaskId, NewStatus) ->
    gen_server:call(?SERVER, {sync_state, TaskId, NewStatus}).

%% @doc Get a unified task view combining both A2A and BeamAI data.
%%
%% Returns a map containing the A2A task record (as a map), the BeamAI
%% task map, and a merged view.
-spec get_unified_task(binary()) -> {ok, map()} | {error, term()}.
get_unified_task(TaskId) ->
    gen_server:call(?SERVER, {get_unified_task, TaskId}).

%% @doc Translate an A2A #task{} record into a BeamAI-compatible map.
%% This is a pure function and does not require the bridge process.
-spec translate_to_beamai(term()) -> map().
translate_to_beamai(Task) when is_tuple(Task), element(1, Task) =:= task ->
    #task{
        id = Id,
        context_id = ContextId,
        status = #task_status{state = StatusState, timestamp = Timestamp},
        artifacts = Artifacts,
        history = History,
        metadata = Metadata
    } = Task,

    #{
        id => Id,
        context_id => ContextId,
        status => StatusState,
        artifacts => translate_artifacts_to_beamai(Artifacts),
        messages => translate_messages_to_beamai(History),
        metadata => Metadata,
        status_timestamp => Timestamp,
        created_at => format_timestamp(Timestamp),
        updated_at => format_timestamp(Timestamp)
    };
translate_to_beamai(_) ->
    #{error => invalid_task_record}.

%% @doc Translate a BeamAI task map into an A2A #task{} record.
%% This is a pure function and does not require the bridge process.
-spec translate_from_beamai(map()) -> term().
translate_from_beamai(BeamAITask) when is_map(BeamAITask) ->
    Id = maps:get(id, BeamAITask, undefined),
    ContextId = maps:get(context_id, BeamAITask, undefined),
    Status = maps:get(status, BeamAITask, submitted),
    Artifacts = maps:get(artifacts, BeamAITask, []),
    Messages = maps:get(messages, BeamAITask, []),
    Metadata = maps:get(metadata, BeamAITask, #{}),
    Timestamp = maps:get(status_timestamp, BeamAITask, erlang:system_time(millisecond)),

    #task{
        id = Id,
        context_id = ContextId,
        status = #task_status{
            state = Status,
            timestamp = Timestamp
        },
        artifacts = translate_artifacts_from_beamai(Artifacts),
        history = translate_messages_from_beamai(Messages),
        metadata = Metadata
    };
translate_from_beamai(_) ->
    {error, invalid_beamai_task}.

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init([]) -> {ok, #bridge_state{}}.
init([]) ->
    logger:info("[beamai_task_bridge] Bridge started"),
    {ok, #bridge_state{}}.

handle_call({create_task, Message}, _From, State) ->
    case do_create_task(Message, State) of
        {ok, TaskId, A2APid, BeamAIPid, NewState} ->
            %% Record creation in history if the history tracker is running
            record_history(TaskId, task_created, #{
                a2a_pid => A2APid,
                beamai_pid => BeamAIPid
            }),
            {reply, {ok, TaskId, A2APid, BeamAIPid}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({sync_state, TaskId, NewStatus}, _From, State) ->
    case do_sync_state(TaskId, NewStatus, State) of
        {ok, NewState} ->
            record_history(TaskId, state_synced, #{new_status => NewStatus}),
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({get_unified_task, TaskId}, _From, State) ->
    case do_get_unified_task(TaskId, State) of
        {ok, UnifiedTask} ->
            {reply, {ok, UnifiedTask}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', Ref, process, DownPid, Reason}, State) ->
    case maps:get(Ref, State#bridge_state.monitors, undefined) of
        undefined ->
            {noreply, State};
        TaskId ->
            logger:warning("[beamai_task_bridge] Monitored process ~p for task ~s "
                           "died: ~p", [DownPid, TaskId, Reason]),
            NewState = handle_process_down(TaskId, DownPid, Reason, Ref, State),
            record_history(TaskId, process_down, #{
                pid => DownPid,
                reason => Reason
            }),
            {noreply, NewState}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(Reason, #bridge_state{task_map = TaskMap}) ->
    logger:info("[beamai_task_bridge] Bridge terminating: ~p, "
                "tracking ~p tasks", [Reason, maps:size(TaskMap)]),
    ok.

%%% ============================================================================
%%% Internal Functions - Task Creation
%%% ============================================================================

%% @doc Create both an A2A task and a BeamAI task, set up monitors, and store
%% the mapping.
-spec do_create_task(term(), #bridge_state{}) ->
    {ok, binary(), pid(), pid(), #bridge_state{}} | {error, term()}.
do_create_task(Message, State) ->
    try
        %% Start the A2A task via the existing supervisor
        case a2a_task_sup:start_task(Message) of
            {ok, A2APid} ->
                %% Get the task ID from the A2A process
                {ok, A2ATask} = a2a_task_statem:get_task(A2APid),
                TaskId = A2ATask#task.id,

                %% Translate to BeamAI format and start a BeamAI task
                BeamAIOpts = #{
                    id => TaskId,
                    status => (A2ATask#task.status)#task_status.state,
                    messages => translate_messages_to_beamai(A2ATask#task.history),
                    artifacts => translate_artifacts_to_beamai(A2ATask#task.artifacts),
                    metadata => (A2ATask#task.metadata)#{
                        context_id => A2ATask#task.context_id,
                        bridge_managed => true
                    }
                },

                case beamai_a2a_task_sup:start_task(BeamAIOpts) of
                    {ok, BeamAIPid} ->
                        %% Monitor both processes
                        A2ARef = erlang:monitor(process, A2APid),
                        BeamAIRef = erlang:monitor(process, BeamAIPid),

                        %% Update state
                        NewTaskMap = maps:put(TaskId, {A2APid, BeamAIPid},
                                             State#bridge_state.task_map),
                        NewMonitors = maps:merge(
                            State#bridge_state.monitors,
                            #{A2ARef => TaskId, BeamAIRef => TaskId}
                        ),
                        NewState = State#bridge_state{
                            task_map = NewTaskMap,
                            monitors = NewMonitors
                        },

                        logger:info("[beamai_task_bridge] Created bridged task ~s "
                                    "(a2a=~p, beamai=~p)",
                                    [TaskId, A2APid, BeamAIPid]),

                        {ok, TaskId, A2APid, BeamAIPid, NewState};

                    {error, BeamAIReason} ->
                        %% Failed to start BeamAI task -- stop the A2A task
                        logger:error("[beamai_task_bridge] Failed to start BeamAI "
                                     "task: ~p", [BeamAIReason]),
                        a2a_task_sup:stop_task(A2APid),
                        {error, {beamai_start_failed, BeamAIReason}}
                end;

            {error, A2AReason} ->
                logger:error("[beamai_task_bridge] Failed to start A2A task: ~p",
                             [A2AReason]),
                {error, {a2a_start_failed, A2AReason}}
        end
    catch
        Class:Err:Stack ->
            logger:error("[beamai_task_bridge] create_task exception: ~p:~p~n~p",
                         [Class, Err, Stack]),
            {error, {exception, Class, Err}}
    end.

%%% ============================================================================
%%% Internal Functions - State Synchronization
%%% ============================================================================

%% @doc Synchronize a status change to both processes.
-spec do_sync_state(binary(), atom(), #bridge_state{}) ->
    {ok, #bridge_state{}} | {error, term()}.
do_sync_state(TaskId, NewStatus, State) ->
    case maps:get(TaskId, State#bridge_state.task_map, undefined) of
        undefined ->
            {error, {task_not_found, TaskId}};
        {A2APid, BeamAIPid} ->
            %% Update the A2A side (gen_statem)
            A2AResult = try
                a2a_task_statem:update_status(A2APid, NewStatus),
                ok
            catch
                _:A2AErr ->
                    logger:warning("[beamai_task_bridge] A2A sync failed for ~s: ~p",
                                   [TaskId, A2AErr]),
                    {error, {a2a_sync_failed, A2AErr}}
            end,

            %% Update the BeamAI side (gen_server)
            BeamAIResult = try
                beamai_a2a_task:update_status(BeamAIPid, NewStatus)
            catch
                _:BeamAIErr ->
                    logger:warning("[beamai_task_bridge] BeamAI sync failed for ~s: ~p",
                                   [TaskId, BeamAIErr]),
                    {error, {beamai_sync_failed, BeamAIErr}}
            end,

            case {A2AResult, BeamAIResult} of
                {ok, ok} ->
                    logger:info("[beamai_task_bridge] State synced for ~s -> ~p",
                                [TaskId, NewStatus]),
                    {ok, State};
                {ok, {error, _} = Err} ->
                    %% BeamAI side failed but A2A side succeeded
                    logger:warning("[beamai_task_bridge] Partial sync for ~s: "
                                   "BeamAI failed: ~p", [TaskId, Err]),
                    {ok, State};
                {{error, _} = Err, ok} ->
                    %% A2A side failed but BeamAI side succeeded
                    logger:warning("[beamai_task_bridge] Partial sync for ~s: "
                                   "A2A failed: ~p", [TaskId, Err]),
                    {ok, State};
                {{error, _} = E1, {error, _} = E2} ->
                    {error, {both_sync_failed, E1, E2}}
            end
    end.

%%% ============================================================================
%%% Internal Functions - Unified Task View
%%% ============================================================================

%% @doc Build a unified view of the task from both sides.
-spec do_get_unified_task(binary(), #bridge_state{}) ->
    {ok, map()} | {error, term()}.
do_get_unified_task(TaskId, State) ->
    case maps:get(TaskId, State#bridge_state.task_map, undefined) of
        undefined ->
            {error, {task_not_found, TaskId}};
        {A2APid, BeamAIPid} ->
            %% Fetch from both sides
            A2AResult = try
                a2a_task_statem:get_task(A2APid)
            catch
                _:_ -> {error, a2a_unavailable}
            end,

            BeamAIResult = try
                beamai_a2a_task:get(BeamAIPid)
            catch
                _:_ -> {error, beamai_unavailable}
            end,

            case {A2AResult, BeamAIResult} of
                {{ok, A2ATask}, {ok, BeamAITask}} ->
                    Unified = #{
                        task_id => TaskId,
                        a2a => translate_to_beamai(A2ATask),
                        beamai => BeamAITask,
                        a2a_pid => A2APid,
                        beamai_pid => BeamAIPid,
                        merged => merge_task_views(
                            translate_to_beamai(A2ATask), BeamAITask)
                    },
                    {ok, Unified};
                {{ok, A2ATask}, {error, _}} ->
                    %% Only A2A available
                    Translated = translate_to_beamai(A2ATask),
                    Unified = #{
                        task_id => TaskId,
                        a2a => Translated,
                        beamai => unavailable,
                        a2a_pid => A2APid,
                        beamai_pid => BeamAIPid,
                        merged => Translated
                    },
                    {ok, Unified};
                {{error, _}, {ok, BeamAITask}} ->
                    %% Only BeamAI available
                    Unified = #{
                        task_id => TaskId,
                        a2a => unavailable,
                        beamai => BeamAITask,
                        a2a_pid => A2APid,
                        beamai_pid => BeamAIPid,
                        merged => BeamAITask
                    },
                    {ok, Unified};
                {{error, E1}, {error, E2}} ->
                    {error, {both_unavailable, E1, E2}}
            end
    end.

%% @doc Merge the A2A and BeamAI views into a single map.
%% The A2A side is considered authoritative for protocol-level fields;
%% the BeamAI side is authoritative for framework-level metadata.
-spec merge_task_views(map(), map()) -> map().
merge_task_views(A2AMap, BeamAIMap) when is_map(A2AMap), is_map(BeamAIMap) ->
    %% Start with the A2A view as the base
    Base = A2AMap,

    %% Overlay BeamAI-specific fields
    BeamAIMetadata = maps:get(metadata, BeamAIMap, #{}),
    A2AMetadata = maps:get(metadata, Base, #{}),
    MergedMetadata = maps:merge(A2AMetadata, BeamAIMetadata),

    %% Use the more detailed history from BeamAI side if available
    BeamAIHistory = maps:get(history, BeamAIMap, []),
    A2AHistory = maps:get(messages, Base, []),
    History = case length(BeamAIHistory) >= length(A2AHistory) of
        true -> BeamAIHistory;
        false -> A2AHistory
    end,

    Base#{
        metadata => MergedMetadata,
        history => History,
        beamai_status => maps:get(status, BeamAIMap, undefined),
        beamai_updated_at => maps:get(updated_at, BeamAIMap, undefined)
    };
merge_task_views(A2AMap, _) when is_map(A2AMap) ->
    A2AMap;
merge_task_views(_, BeamAIMap) when is_map(BeamAIMap) ->
    BeamAIMap;
merge_task_views(_, _) ->
    #{}.

%%% ============================================================================
%%% Internal Functions - Process Monitoring
%%% ============================================================================

%% @doc Handle the death of a monitored process.
%% If one side dies, attempt to cancel the other side and clean up.
-spec handle_process_down(binary(), pid(), term(), reference(), #bridge_state{}) ->
    #bridge_state{}.
handle_process_down(TaskId, DownPid, _Reason, DownRef, State) ->
    case maps:get(TaskId, State#bridge_state.task_map, undefined) of
        undefined ->
            %% Task already cleaned up, just remove the monitor entry
            NewMonitors = maps:remove(DownRef, State#bridge_state.monitors),
            State#bridge_state{monitors = NewMonitors};

        {A2APid, BeamAIPid} ->
            %% Determine which side died and try to cancel the other
            case DownPid of
                A2APid ->
                    logger:info("[beamai_task_bridge] A2A process died for ~s, "
                                "canceling BeamAI side", [TaskId]),
                    safe_cancel_beamai(BeamAIPid);
                BeamAIPid ->
                    logger:info("[beamai_task_bridge] BeamAI process died for ~s, "
                                "A2A side remains", [TaskId]),
                    %% A2A side is the authoritative one; let it continue
                    ok;
                _ ->
                    ok
            end,

            %% Clean up all monitor refs for this task and remove from task_map
            AllMonitorRefs = [Ref || {Ref, TId} <- maps:to_list(State#bridge_state.monitors),
                                     TId =:= TaskId],
            NewMonitors = maps:without(AllMonitorRefs, State#bridge_state.monitors),
            NewTaskMap = maps:remove(TaskId, State#bridge_state.task_map),

            State#bridge_state{
                task_map = NewTaskMap,
                monitors = NewMonitors
            }
    end.

%% @doc Safely cancel a BeamAI task process.
-spec safe_cancel_beamai(pid()) -> ok.
safe_cancel_beamai(Pid) ->
    try
        beamai_a2a_task:cancel(Pid)
    catch
        _:_ -> ok
    end,
    ok.

%%% ============================================================================
%%% Internal Functions - Translation Helpers
%%% ============================================================================

%% @doc Translate A2A #message{} records to BeamAI map format.
-spec translate_messages_to_beamai(list()) -> list().
translate_messages_to_beamai(Messages) ->
    lists:map(fun translate_message_to_beamai/1, Messages).

-spec translate_message_to_beamai(term()) -> map().
translate_message_to_beamai(Msg) when is_tuple(Msg), element(1, Msg) =:= message ->
    #message{
        message_id = MsgId,
        context_id = CtxId,
        task_id = TaskId,
        role = Role,
        parts = Parts,
        metadata = Meta
    } = Msg,
    #{
        message_id => MsgId,
        context_id => CtxId,
        task_id => TaskId,
        role => Role,
        parts => translate_parts_to_beamai(Parts),
        metadata => Meta
    };
translate_message_to_beamai(Other) ->
    %% Pass through maps or unknown formats
    Other.

%% @doc Translate A2A #part{} records to maps.
-spec translate_parts_to_beamai(list()) -> list().
translate_parts_to_beamai(Parts) ->
    lists:map(fun(Part) when is_tuple(Part), element(1, Part) =:= part ->
        #part{
            content = Content,
            metadata = Meta,
            filename = Filename,
            media_type = MediaType
        } = Part,
        PartMap = #{content => Content, metadata => Meta},
        PartMap2 = case Filename of
            undefined -> PartMap;
            _ -> PartMap#{filename => Filename}
        end,
        case MediaType of
            undefined -> PartMap2;
            _ -> PartMap2#{media_type => MediaType}
        end;
    (Other) ->
        Other
    end, Parts).

%% @doc Translate A2A #artifact{} records to maps.
-spec translate_artifacts_to_beamai(list()) -> list().
translate_artifacts_to_beamai(Artifacts) ->
    lists:map(fun(Art) when is_tuple(Art), element(1, Art) =:= artifact ->
        #artifact{
            artifact_id = ArtId,
            name = Name,
            description = Desc,
            parts = Parts,
            metadata = Meta
        } = Art,
        ArtMap = #{
            artifact_id => ArtId,
            parts => translate_parts_to_beamai(Parts),
            metadata => Meta
        },
        ArtMap2 = case Name of
            undefined -> ArtMap;
            _ -> ArtMap#{name => Name}
        end,
        case Desc of
            undefined -> ArtMap2;
            _ -> ArtMap2#{description => Desc}
        end;
    (Other) ->
        Other
    end, Artifacts).

%% @doc Translate BeamAI message maps to A2A #message{} records.
-spec translate_messages_from_beamai(list()) -> list().
translate_messages_from_beamai(Messages) ->
    lists:map(fun translate_message_from_beamai/1, Messages).

-spec translate_message_from_beamai(map() | term()) -> term().
translate_message_from_beamai(Msg) when is_map(Msg) ->
    #message{
        message_id = maps:get(message_id, Msg, undefined),
        context_id = maps:get(context_id, Msg, undefined),
        task_id = maps:get(task_id, Msg, undefined),
        role = maps:get(role, Msg, user),
        parts = translate_parts_from_beamai(maps:get(parts, Msg, [])),
        metadata = maps:get(metadata, Msg, #{})
    };
translate_message_from_beamai(Other) ->
    Other.

%% @doc Translate BeamAI part maps to A2A #part{} records.
-spec translate_parts_from_beamai(list()) -> list().
translate_parts_from_beamai(Parts) ->
    lists:map(fun(Part) when is_map(Part) ->
        #part{
            content = maps:get(content, Part, {text, <<>>}),
            metadata = maps:get(metadata, Part, #{}),
            filename = maps:get(filename, Part, undefined),
            media_type = maps:get(media_type, Part, undefined)
        };
    (Other) ->
        Other
    end, Parts).

%% @doc Translate BeamAI artifact maps to A2A #artifact{} records.
-spec translate_artifacts_from_beamai(list()) -> list().
translate_artifacts_from_beamai(Artifacts) ->
    lists:map(fun(Art) when is_map(Art) ->
        #artifact{
            artifact_id = maps:get(artifact_id, Art, undefined),
            name = maps:get(name, Art, undefined),
            description = maps:get(description, Art, undefined),
            parts = translate_parts_from_beamai(maps:get(parts, Art, [])),
            metadata = maps:get(metadata, Art, #{})
        };
    (Other) ->
        Other
    end, Artifacts).

%% @doc Format a millisecond timestamp as an ISO 8601 binary.
-spec format_timestamp(integer() | undefined) -> binary() | undefined.
format_timestamp(undefined) ->
    undefined;
format_timestamp(Millis) when is_integer(Millis) ->
    Seconds = Millis div 1000,
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(Seconds, second),
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
                                   [Y, Mo, D, H, Mi, S]));
format_timestamp(_) ->
    undefined.

%% @doc Safely record a history event via beamai_task_history if it is running.
-spec record_history(binary(), atom(), map()) -> ok.
record_history(TaskId, Event, Data) ->
    try
        beamai_task_history:record(TaskId, Event, Data)
    catch
        _:_ -> ok
    end.
