%%% @doc BeamAI Task History Tracker
%%%
%%% Records all state transitions, message additions, artifact additions,
%%% and other events for audit trail purposes. History is stored per-task
%%% in an ETS table managed by this gen_server.
%%%
%%% Each history entry contains:
%%% - task_id:   the binary task identifier
%%% - event:     an atom describing the event type
%%% - data:      a map of event-specific data
%%% - timestamp: ISO 8601 binary timestamp of when the event was recorded
%%% - seq:       monotonically increasing sequence number per task
%%%
%%% Features:
%%% - Record state transitions, messages, artifacts, and custom events
%%% - Retrieve full history for a task
%%% - Replay history to reconstruct task state at any point in time
%%% - Export history as a list of maps for serialization
%%% @end
-module(beamai_task_history).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    record/3,
    get_history/1,
    replay/1,
    export/1
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
-define(HISTORY_TABLE, beamai_task_history_tab).

-record(history_entry, {
    key :: {binary(), non_neg_integer()},  %% {task_id, sequence_number}
    task_id :: binary(),
    event :: atom(),
    data :: map(),
    timestamp :: binary()
}).

-record(state, {
    sequences = #{} :: #{binary() => non_neg_integer()}  %% task_id => next_seq
}).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the history tracker as a registered gen_server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Record a history event for a task.
%%
%% TaskId: binary task identifier
%% Event:  atom describing the event (e.g., state_changed, message_added,
%%         artifact_added, task_created, task_canceled, process_down)
%% Data:   map of event-specific data (e.g., #{from => working, to => completed})
-spec record(binary(), atom(), map()) -> ok | {error, term()}.
record(TaskId, Event, Data) when is_binary(TaskId), is_atom(Event), is_map(Data) ->
    gen_server:call(?SERVER, {record, TaskId, Event, Data});
record(_, _, _) ->
    {error, invalid_arguments}.

%% @doc Get the full history for a task, ordered by sequence number.
%% Returns a list of history entry maps.
-spec get_history(binary()) -> {ok, [map()]} | {error, term()}.
get_history(TaskId) when is_binary(TaskId) ->
    gen_server:call(?SERVER, {get_history, TaskId});
get_history(_) ->
    {error, invalid_task_id}.

%% @doc Replay the history for a task to reconstruct its state at each point.
%%
%% Returns a list of {seq, event, reconstructed_state} tuples, where
%% reconstructed_state is a map representing the task's status, messages,
%% and artifacts at that point in time.
-spec replay(binary()) -> {ok, [map()]} | {error, term()}.
replay(TaskId) when is_binary(TaskId) ->
    gen_server:call(?SERVER, {replay, TaskId});
replay(_) ->
    {error, invalid_task_id}.

%% @doc Export the history for a task as a serializable list of maps.
%% Each map contains: task_id, seq, event, data, timestamp.
-spec export(binary()) -> {ok, [map()]} | {error, term()}.
export(TaskId) when is_binary(TaskId) ->
    gen_server:call(?SERVER, {export, TaskId});
export(_) ->
    {error, invalid_task_id}.

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init([]) -> {ok, #state{}}.
init([]) ->
    %% Create the ETS table for history entries
    case ets:info(?HISTORY_TABLE) of
        undefined ->
            _ = ets:new(?HISTORY_TABLE, [
                named_table,
                ordered_set,          %% ordered by {task_id, seq}
                public,
                {keypos, #history_entry.key},
                {read_concurrency, true}
            ]);
        _ ->
            ok
    end,
    logger:info("[beamai_task_history] History tracker started"),
    {ok, #state{}}.

handle_call({record, TaskId, Event, Data}, _From, State) ->
    {Seq, NewState} = next_sequence(TaskId, State),
    Timestamp = iso8601_now(),

    Entry = #history_entry{
        key = {TaskId, Seq},
        task_id = TaskId,
        event = Event,
        data = Data,
        timestamp = Timestamp
    },

    ets:insert(?HISTORY_TABLE, Entry),

    logger:debug("[beamai_task_history] Recorded ~p for task ~s (seq=~p)",
                 [Event, TaskId, Seq]),

    {reply, ok, NewState};

handle_call({get_history, TaskId}, _From, State) ->
    Entries = lookup_task_entries(TaskId),
    Maps = lists:map(fun entry_to_map/1, Entries),
    {reply, {ok, Maps}, State};

handle_call({replay, TaskId}, _From, State) ->
    Entries = lookup_task_entries(TaskId),
    ReplaySteps = do_replay(Entries),
    {reply, {ok, ReplaySteps}, State};

handle_call({export, TaskId}, _From, State) ->
    Entries = lookup_task_entries(TaskId),
    ExportMaps = lists:map(fun entry_to_export_map/1, Entries),
    {reply, {ok, ExportMaps}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(Reason, _State) ->
    logger:info("[beamai_task_history] History tracker terminating: ~p", [Reason]),
    ok.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Get the next sequence number for a task and update state.
-spec next_sequence(binary(), #state{}) -> {non_neg_integer(), #state{}}.
next_sequence(TaskId, #state{sequences = Seqs} = State) ->
    Seq = maps:get(TaskId, Seqs, 0),
    NewSeqs = maps:put(TaskId, Seq + 1, Seqs),
    {Seq, State#state{sequences = NewSeqs}}.

%% @doc Look up all history entries for a task, sorted by sequence number.
-spec lookup_task_entries(binary()) -> [#history_entry{}].
lookup_task_entries(TaskId) ->
    %% Use ets:select with a match specification to find all entries for this task.
    %% The ordered_set table keeps entries sorted by {TaskId, Seq}.
    MatchSpec = [{
        #history_entry{
            key = {TaskId, '_'},
            task_id = TaskId,
            event = '_',
            data = '_',
            timestamp = '_'
        },
        [],
        ['$_']
    }],
    ets:select(?HISTORY_TABLE, MatchSpec).

%% @doc Convert a history entry record to a display map.
-spec entry_to_map(#history_entry{}) -> map().
entry_to_map(#history_entry{key = {_TaskId, Seq}, event = Event,
                            data = Data, timestamp = Timestamp}) ->
    #{
        seq => Seq,
        event => Event,
        data => Data,
        timestamp => Timestamp
    }.

%% @doc Convert a history entry to a full export map.
-spec entry_to_export_map(#history_entry{}) -> map().
entry_to_export_map(#history_entry{key = {TaskId, Seq}, event = Event,
                                    data = Data, timestamp = Timestamp}) ->
    #{
        task_id => TaskId,
        seq => Seq,
        event => Event,
        data => Data,
        timestamp => Timestamp
    }.

%% @doc Replay history entries to reconstruct the task state at each step.
%%
%% Starts with an empty initial state and applies each event to produce
%% a snapshot of the task's status, messages, and artifacts at that point.
-spec do_replay([#history_entry{}]) -> [map()].
do_replay(Entries) ->
    InitialState = #{
        status => undefined,
        messages => [],
        artifacts => [],
        metadata => #{}
    },
    {Steps, _FinalState} = lists:foldl(fun(Entry, {Acc, CurrentState}) ->
        NewState = apply_replay_event(Entry, CurrentState),
        Step = #{
            seq => element(2, Entry#history_entry.key),
            event => Entry#history_entry.event,
            timestamp => Entry#history_entry.timestamp,
            data => Entry#history_entry.data,
            reconstructed_state => NewState
        },
        {Acc ++ [Step], NewState}
    end, {[], InitialState}, Entries),
    Steps.

%% @doc Apply a single history event to the current reconstructed state.
-spec apply_replay_event(#history_entry{}, map()) -> map().
apply_replay_event(#history_entry{event = task_created, data = Data}, State) ->
    %% Task was created
    NewStatus = maps:get(initial_status, Data, maps:get(status, Data, submitted)),
    State#{status => NewStatus};

apply_replay_event(#history_entry{event = state_changed, data = Data}, State) ->
    %% Status transitioned
    NewStatus = maps:get(to, Data, maps:get(new_status, Data, undefined)),
    State#{status => NewStatus};

apply_replay_event(#history_entry{event = state_synced, data = Data}, State) ->
    %% Status synced through bridge
    NewStatus = maps:get(new_status, Data, maps:get(status, Data, undefined)),
    case NewStatus of
        undefined -> State;
        _ -> State#{status => NewStatus}
    end;

apply_replay_event(#history_entry{event = message_added, data = Data}, State) ->
    %% Message was added
    Message = maps:get(message, Data, Data),
    Messages = maps:get(messages, State, []),
    State#{messages => Messages ++ [Message]};

apply_replay_event(#history_entry{event = artifact_added, data = Data}, State) ->
    %% Artifact was added
    Artifact = maps:get(artifact, Data, Data),
    Artifacts = maps:get(artifacts, State, []),
    State#{artifacts => Artifacts ++ [Artifact]};

apply_replay_event(#history_entry{event = task_canceled, data = _Data}, State) ->
    State#{status => canceled};

apply_replay_event(#history_entry{event = process_down, data = Data}, State) ->
    %% A process died; record it in metadata
    Metadata = maps:get(metadata, State, #{}),
    State#{metadata => Metadata#{process_down => Data}};

apply_replay_event(#history_entry{event = _OtherEvent, data = Data}, State) ->
    %% For unknown events, merge data into metadata for audit purposes
    Metadata = maps:get(metadata, State, #{}),
    State#{metadata => maps:merge(Metadata, Data)}.

%% @doc Get the current time as an ISO 8601 binary string.
-spec iso8601_now() -> binary().
iso8601_now() ->
    Now = erlang:system_time(second),
    {{Y, Mo, D}, {H, Mi, S}} = calendar:system_time_to_universal_time(Now, second),
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0BZ",
                                   [Y, Mo, D, H, Mi, S])).
