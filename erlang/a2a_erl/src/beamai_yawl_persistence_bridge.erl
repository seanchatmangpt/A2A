%%%-------------------------------------------------------------------
%%% @doc
%%% YAWL-BeamAI Persistence Bridge
%%%
%%% Bridges the YAWL Mnesia persistence layer (yawl_persistence) to
%%% the BeamAI memory/checkpoint system. This module:
%%%
%%% - Syncs YAWL workflow state to BeamAI memory context
%%% - Supports workflow checkpoint/restore via BeamAI checkpointer
%%% - Enables time-travel debugging using a checkpoint timeline
%%% - Provides unified state query across both persistence layers
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(beamai_yawl_persistence_bridge).
-behaviour(gen_server).

-include("../include/yawl_types.hrl").
-include("../include/yawl_schema.hrl").

%% API
-export([
    start_link/0,
    checkpoint/1,
    restore/1,
    get_timeline/1,
    sync_to_memory/2
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
-define(MAX_CHECKPOINTS_PER_WORKFLOW, 100).

-record(checkpoint_entry, {
    checkpoint_id :: binary(),
    workflow_id :: binary(),
    sequence_num :: pos_integer(),
    yawl_state :: map(),
    beamai_context :: map(),
    marking :: map(),
    data :: map(),
    timestamp :: integer(),
    metadata :: map()
}).

-record(state, {
    %% workflow_id => [checkpoint_entry] (most recent first)
    timelines = #{} :: #{binary() => [#checkpoint_entry{}]},
    %% workflow_id => latest sequence number
    sequence_counters = #{} :: #{binary() => pos_integer()},
    %% workflow_id => beamai memory context
    memory_cache = #{} :: #{binary() => map()},
    %% Configuration
    max_checkpoints :: pos_integer(),
    auto_checkpoint :: boolean()
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the persistence bridge server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Create a checkpoint of the current workflow state.
%% Captures both YAWL persistence state and BeamAI memory context.
-spec checkpoint(binary()) -> {ok, binary()} | {error, term()}.
checkpoint(WorkflowId) ->
    gen_server:call(?SERVER, {checkpoint, WorkflowId}).

%% @doc Restore a workflow to a previous checkpoint.
%% Can accept a checkpoint_id or #{workflow_id, sequence_num}.
-spec restore(binary() | map()) -> {ok, map()} | {error, term()}.
restore(CheckpointSpec) ->
    gen_server:call(?SERVER, {restore, CheckpointSpec}, 15000).

%% @doc Get the checkpoint timeline for a workflow.
%% Returns a list of checkpoint summaries in chronological order.
-spec get_timeline(binary()) -> {ok, [map()]} | {error, term()}.
get_timeline(WorkflowId) ->
    gen_server:call(?SERVER, {get_timeline, WorkflowId}).

%% @doc Sync YAWL workflow data to BeamAI memory context.
%% MemoryKey is a namespace within the BeamAI memory for this data.
-spec sync_to_memory(binary(), binary()) -> ok | {error, term()}.
sync_to_memory(WorkflowId, MemoryKey) ->
    gen_server:call(?SERVER, {sync_to_memory, WorkflowId, MemoryKey}).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init([]) ->
    process_flag(trap_exit, true),
    logger:info("YAWL-BeamAI persistence bridge started"),
    {ok, #state{
        max_checkpoints = ?MAX_CHECKPOINTS_PER_WORKFLOW,
        auto_checkpoint = true
    }}.

%% @private
handle_call({checkpoint, WorkflowId}, _From, State) ->
    #state{timelines = Timelines, sequence_counters = Counters} = State,
    %% Get current sequence number
    SeqNum = maps:get(WorkflowId, Counters, 0) + 1,
    %% Capture YAWL state
    YawlState = capture_yawl_state(WorkflowId),
    %% Capture BeamAI context
    BeamAIContext = capture_beamai_context(WorkflowId),
    %% Build the checkpoint entry
    CheckpointId = generate_checkpoint_id(WorkflowId, SeqNum),
    Entry = #checkpoint_entry{
        checkpoint_id = CheckpointId,
        workflow_id = WorkflowId,
        sequence_num = SeqNum,
        yawl_state = YawlState,
        beamai_context = BeamAIContext,
        marking = maps:get(marking, YawlState, #{}),
        data = maps:get(data, YawlState, #{}),
        timestamp = erlang:system_time(millisecond),
        metadata = #{
            yawl_status => maps:get(status, YawlState, unknown),
            has_beamai_context => map_size(BeamAIContext) > 0
        }
    },
    %% Persist to YAWL Mnesia if available
    persist_checkpoint_to_mnesia(Entry),
    %% Update the timeline
    ExistingTimeline = maps:get(WorkflowId, Timelines, []),
    TrimmedTimeline = trim_timeline([Entry | ExistingTimeline],
                                    State#state.max_checkpoints),
    NewTimelines = Timelines#{WorkflowId => TrimmedTimeline},
    NewCounters = Counters#{WorkflowId => SeqNum},
    NewState = State#state{timelines = NewTimelines, sequence_counters = NewCounters},
    logger:info("Checkpoint ~s created for workflow ~s (seq ~p)",
                [CheckpointId, WorkflowId, SeqNum]),
    {reply, {ok, CheckpointId}, NewState};

handle_call({restore, CheckpointId}, _From, State) when is_binary(CheckpointId) ->
    %% Find the checkpoint by ID across all timelines
    case find_checkpoint_by_id(CheckpointId, State#state.timelines) of
        {ok, Entry} ->
            Result = do_restore(Entry),
            {reply, Result, State};
        error ->
            %% Try loading from Mnesia
            case load_checkpoint_from_mnesia(CheckpointId) of
                {ok, Entry} ->
                    Result = do_restore(Entry),
                    {reply, Result, State};
                _ ->
                    {reply, {error, checkpoint_not_found}, State}
            end
    end;
handle_call({restore, #{workflow_id := WorkflowId, sequence_num := SeqNum}},
            _From, State) ->
    #state{timelines = Timelines} = State,
    case maps:find(WorkflowId, Timelines) of
        {ok, Timeline} ->
            case find_by_sequence(SeqNum, Timeline) of
                {ok, Entry} ->
                    Result = do_restore(Entry),
                    {reply, Result, State};
                error ->
                    {reply, {error, sequence_not_found}, State}
            end;
        error ->
            {reply, {error, workflow_not_found}, State}
    end;

handle_call({get_timeline, WorkflowId}, _From, State) ->
    #state{timelines = Timelines} = State,
    case maps:find(WorkflowId, Timelines) of
        {ok, Timeline} ->
            %% Return in chronological order (oldest first)
            Summaries = lists:reverse(lists:map(
                fun checkpoint_to_summary/1, Timeline
            )),
            {reply, {ok, Summaries}, State};
        error ->
            %% Try loading from Mnesia
            case load_timeline_from_mnesia(WorkflowId) of
                {ok, Summaries} ->
                    {reply, {ok, Summaries}, State};
                _ ->
                    {reply, {ok, []}, State}
            end
    end;

handle_call({sync_to_memory, WorkflowId, MemoryKey}, _From, State) ->
    #state{memory_cache = Cache} = State,
    %% Fetch current YAWL workflow state
    YawlState = capture_yawl_state(WorkflowId),
    %% Build BeamAI memory entry
    MemoryEntry = #{
        key => MemoryKey,
        workflow_id => WorkflowId,
        status => maps:get(status, YawlState, unknown),
        marking => maps:get(marking, YawlState, #{}),
        data => maps:get(data, YawlState, #{}),
        synced_at => erlang:system_time(millisecond)
    },
    %% Push to BeamAI kernel context if available
    push_to_beamai_memory(WorkflowId, MemoryKey, MemoryEntry),
    %% Update local cache
    WorkflowCache = maps:get(WorkflowId, Cache, #{}),
    NewWorkflowCache = WorkflowCache#{MemoryKey => MemoryEntry},
    NewCache = Cache#{WorkflowId => NewWorkflowCache},
    NewState = State#state{memory_cache = NewCache},
    {reply, ok, NewState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({yawl_event, workflow_state_changed, EventData}, State) ->
    %% Auto-checkpoint on state changes if enabled
    case State#state.auto_checkpoint of
        true ->
            WorkflowId = maps:get(workflow_id, EventData, undefined),
            case WorkflowId of
                undefined -> {noreply, State};
                _ ->
                    %% Async checkpoint to avoid blocking
                    gen_server:cast(self(), {auto_checkpoint, WorkflowId}),
                    {noreply, State}
            end;
        false ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%%%===================================================================
%%% Internal Functions - State Capture
%%%===================================================================

%% @private Capture the current YAWL workflow state.
-spec capture_yawl_state(binary()) -> map().
capture_yawl_state(WorkflowId) ->
    %% Try the workflow instance manager first
    InstanceState = case whereis(yawl_workflow_instance) of
        undefined -> #{};
        _Pid ->
            try
                case yawl_workflow_instance:get_state(WorkflowId) of
                    {ok, S} -> S;
                    _ -> #{}
                end
            catch _:_ -> #{}
            end
    end,
    %% Try persistence layer for additional data
    PersistState = case whereis(yawl_persistence) of
        undefined -> #{};
        _Pid2 ->
            try
                case yawl_persistence:load_workflow(WorkflowId) of
                    {ok, WF} -> workflow_persist_to_map(WF);
                    _ -> #{}
                end
            catch _:_ -> #{}
            end
    end,
    %% Merge with instance state taking precedence (more current)
    maps:merge(PersistState, InstanceState).

%% @private Capture the current BeamAI context for a workflow.
-spec capture_beamai_context(binary()) -> map().
capture_beamai_context(WorkflowId) ->
    case whereis(beamai_kernel) of
        undefined -> #{};
        _Pid ->
            try
                Ctx = beamai:context(beamai_kernel),
                %% Extract workflow-specific context
                maps:get(WorkflowId, Ctx, maps:with(
                    [kernel_name, started_at, default_llm], Ctx
                ))
            catch _:_ -> #{}
            end
    end.

%% @private Convert a yawl_workflow_persist record to a map.
-spec workflow_persist_to_map(#yawl_workflow_persist{}) -> map().
workflow_persist_to_map(#yawl_workflow_persist{} = WF) ->
    #{
        workflow_id => WF#yawl_workflow_persist.workflow_id,
        spec_id => WF#yawl_workflow_persist.spec_id,
        pattern_type => WF#yawl_workflow_persist.pattern_type,
        status => WF#yawl_workflow_persist.status,
        marking => WF#yawl_workflow_persist.marking,
        current_place => WF#yawl_workflow_persist.current_place,
        data => WF#yawl_workflow_persist.data,
        parent_workflow_id => WF#yawl_workflow_persist.parent_workflow_id,
        created_at => WF#yawl_workflow_persist.created_at,
        updated_at => WF#yawl_workflow_persist.updated_at
    };
workflow_persist_to_map(_) -> #{}.

%%%===================================================================
%%% Internal Functions - Checkpoint Operations
%%%===================================================================

%% @private Persist a checkpoint entry to Mnesia.
-spec persist_checkpoint_to_mnesia(#checkpoint_entry{}) -> ok.
persist_checkpoint_to_mnesia(Entry) ->
    case whereis(yawl_persistence) of
        undefined -> ok;
        _Pid ->
            try
                MnesiaRecord = #yawl_checkpoint{
                    checkpoint_id = Entry#checkpoint_entry.checkpoint_id,
                    workflow_id = Entry#checkpoint_entry.workflow_id,
                    checkpoint_state = #{
                        yawl_state => Entry#checkpoint_entry.yawl_state,
                        beamai_context => Entry#checkpoint_entry.beamai_context
                    },
                    marking = Entry#checkpoint_entry.marking,
                    data = Entry#checkpoint_entry.data,
                    timestamp = Entry#checkpoint_entry.timestamp,
                    sequence_num = Entry#checkpoint_entry.sequence_num
                },
                yawl_persistence:save_checkpoint(MnesiaRecord)
            catch
                _:_ -> ok
            end
    end.

%% @private Load a checkpoint from Mnesia.
-spec load_checkpoint_from_mnesia(binary()) ->
    {ok, #checkpoint_entry{}} | {error, term()}.
load_checkpoint_from_mnesia(CheckpointId) ->
    case whereis(yawl_persistence) of
        undefined -> {error, persistence_unavailable};
        _Pid ->
            try
                case yawl_persistence:load_checkpoint(CheckpointId) of
                    {ok, #yawl_checkpoint{} = CP} ->
                        CpState = CP#yawl_checkpoint.checkpoint_state,
                        Entry = #checkpoint_entry{
                            checkpoint_id = CP#yawl_checkpoint.checkpoint_id,
                            workflow_id = CP#yawl_checkpoint.workflow_id,
                            sequence_num = CP#yawl_checkpoint.sequence_num,
                            yawl_state = maps:get(yawl_state, CpState, #{}),
                            beamai_context = maps:get(beamai_context, CpState, #{}),
                            marking = CP#yawl_checkpoint.marking,
                            data = CP#yawl_checkpoint.data,
                            timestamp = CP#yawl_checkpoint.timestamp,
                            metadata = #{}
                        },
                        {ok, Entry};
                    _ ->
                        {error, not_found}
                end
            catch
                _:Err -> {error, Err}
            end
    end.

%% @private Load timeline from Mnesia for a workflow.
-spec load_timeline_from_mnesia(binary()) -> {ok, [map()]} | {error, term()}.
load_timeline_from_mnesia(WorkflowId) ->
    case whereis(yawl_persistence) of
        undefined -> {error, persistence_unavailable};
        _Pid ->
            try
                case yawl_persistence:list_checkpoints(WorkflowId) of
                    {ok, Checkpoints} ->
                        Summaries = lists:map(fun(CP) ->
                            #{
                                checkpoint_id => CP#yawl_checkpoint.checkpoint_id,
                                workflow_id => CP#yawl_checkpoint.workflow_id,
                                sequence_num => CP#yawl_checkpoint.sequence_num,
                                timestamp => CP#yawl_checkpoint.timestamp,
                                has_marking => map_size(CP#yawl_checkpoint.marking) > 0
                            }
                        end, Checkpoints),
                        {ok, Summaries};
                    _ ->
                        {ok, []}
                end
            catch
                _:_ -> {ok, []}
            end
    end.

%% @private Restore workflow state from a checkpoint entry.
-spec do_restore(#checkpoint_entry{}) -> {ok, map()} | {error, term()}.
do_restore(#checkpoint_entry{} = Entry) ->
    WorkflowId = Entry#checkpoint_entry.workflow_id,
    YawlState = Entry#checkpoint_entry.yawl_state,
    BeamAIContext = Entry#checkpoint_entry.beamai_context,
    %% Restore YAWL state
    YawlResult = restore_yawl_state(WorkflowId, YawlState),
    %% Restore BeamAI context
    BeamAIResult = restore_beamai_context(WorkflowId, BeamAIContext),
    {ok, #{
        checkpoint_id => Entry#checkpoint_entry.checkpoint_id,
        sequence_num => Entry#checkpoint_entry.sequence_num,
        timestamp => Entry#checkpoint_entry.timestamp,
        yawl_restored => YawlResult,
        beamai_restored => BeamAIResult,
        restored_at => erlang:system_time(millisecond)
    }}.

%% @private Restore YAWL workflow state.
-spec restore_yawl_state(binary(), map()) -> ok | {error, term()}.
restore_yawl_state(WorkflowId, YawlState) ->
    case whereis(yawl_workflow_instance) of
        undefined -> {error, instance_manager_unavailable};
        _Pid ->
            try
                Data = maps:get(data, YawlState, #{}),
                yawl_workflow_instance:update_data(WorkflowId, Data),
                ok
            catch
                _:Err -> {error, Err}
            end
    end.

%% @private Restore BeamAI context.
-spec restore_beamai_context(binary(), map()) -> ok | {error, term()}.
restore_beamai_context(_WorkflowId, Context) when map_size(Context) =:= 0 ->
    ok;
restore_beamai_context(WorkflowId, _Context) ->
    %% Push restored context to BeamAI kernel
    case whereis(beamai_yawl_bridge) of
        undefined -> ok;
        _Pid ->
            try
                beamai_yawl_bridge:sync_state(WorkflowId, beamai_to_yawl),
                ok
            catch _:_ -> ok
            end
    end.

%%%===================================================================
%%% Internal Functions - Memory Sync
%%%===================================================================

%% @private Push workflow data to BeamAI kernel memory/context.
-spec push_to_beamai_memory(binary(), binary(), map()) -> ok.
push_to_beamai_memory(WorkflowId, MemoryKey, MemoryEntry) ->
    case whereis(beamai_yawl_bridge) of
        undefined -> ok;
        _Pid ->
            try
                case beamai_yawl_bridge:get_workflow_agent(WorkflowId) of
                    {ok, AgentPid} ->
                        AgentPid ! {memory_update, MemoryKey, MemoryEntry};
                    _ -> ok
                end
            catch _:_ -> ok
            end
    end.

%%%===================================================================
%%% Internal Functions - Utilities
%%%===================================================================

%% @private Find a checkpoint by ID across all timelines.
-spec find_checkpoint_by_id(binary(), map()) ->
    {ok, #checkpoint_entry{}} | error.
find_checkpoint_by_id(CheckpointId, Timelines) ->
    maps:fold(fun(_WfId, Timeline, Acc) ->
        case Acc of
            {ok, _} -> Acc;
            error ->
                case lists:search(
                    fun(E) -> E#checkpoint_entry.checkpoint_id =:= CheckpointId end,
                    Timeline
                ) of
                    {value, Entry} -> {ok, Entry};
                    false -> error
                end
        end
    end, error, Timelines).

%% @private Find a checkpoint by sequence number.
-spec find_by_sequence(pos_integer(), [#checkpoint_entry{}]) ->
    {ok, #checkpoint_entry{}} | error.
find_by_sequence(SeqNum, Timeline) ->
    case lists:search(
        fun(E) -> E#checkpoint_entry.sequence_num =:= SeqNum end,
        Timeline
    ) of
        {value, Entry} -> {ok, Entry};
        false -> error
    end.

%% @private Convert a checkpoint entry to a summary map.
-spec checkpoint_to_summary(#checkpoint_entry{}) -> map().
checkpoint_to_summary(#checkpoint_entry{} = E) ->
    #{
        checkpoint_id => E#checkpoint_entry.checkpoint_id,
        workflow_id => E#checkpoint_entry.workflow_id,
        sequence_num => E#checkpoint_entry.sequence_num,
        timestamp => E#checkpoint_entry.timestamp,
        yawl_status => maps:get(status, E#checkpoint_entry.yawl_state, unknown),
        has_beamai_context => map_size(E#checkpoint_entry.beamai_context) > 0,
        has_marking => map_size(E#checkpoint_entry.marking) > 0,
        metadata => E#checkpoint_entry.metadata
    }.

%% @private Trim timeline to maximum size.
-spec trim_timeline([#checkpoint_entry{}], pos_integer()) -> [#checkpoint_entry{}].
trim_timeline(Timeline, MaxSize) when length(Timeline) > MaxSize ->
    lists:sublist(Timeline, MaxSize);
trim_timeline(Timeline, _MaxSize) ->
    Timeline.

%% @private Generate a checkpoint identifier.
-spec generate_checkpoint_id(binary(), pos_integer()) -> binary().
generate_checkpoint_id(WorkflowId, SeqNum) ->
    SeqBin = integer_to_binary(SeqNum),
    Ts = integer_to_binary(erlang:system_time(millisecond)),
    <<"cp_", WorkflowId/binary, "_", SeqBin/binary, "_", Ts/binary>>.
