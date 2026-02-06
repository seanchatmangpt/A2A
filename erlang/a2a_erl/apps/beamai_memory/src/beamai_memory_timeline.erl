%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Memory Timeline
%%%
%%% Provides timeline tracking for time-travel debugging of the
%%% BeamAI memory system. Every state change (put, delete) in the
%%% memory store can be recorded as a timeline event, enabling:
%%%
%%%   - Point-in-time queries: "What was the value of X at time T?"
%%%   - Range queries: "Show all changes to namespace N between T1 and T2"
%%%   - Replay: Re-apply a sequence of changes from a point in time
%%%   - Audit trail: Full history of all memory mutations
%%%
%%% Timeline events are stored in an ordered_set ETS table keyed by
%%% {Timestamp, Sequence} for guaranteed ordering even when multiple
%%% events share the same millisecond timestamp.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_memory_timeline).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    record/3,
    record/4,
    at/2,
    range/3,
    replay/2,
    replay/3,
    current/1,
    history/1,
    history/2,
    prune/1
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

-define(SERVER, ?MODULE).
-define(TIMELINE_TABLE, beamai_timeline).
-define(MAX_TIMELINE_SIZE, 100000).
-define(PRUNE_CHECK_INTERVAL, 120000). %% 2 minutes

-record(timeline_event, {
    key            :: {integer(), integer()},  %% {Timestamp, Sequence}
    namespace      :: atom(),
    entry_key      :: term(),
    operation      :: put | delete | clear,
    old_value      :: term() | undefined,
    new_value      :: term() | undefined,
    metadata       :: map()
}).

-record(state, {
    sequence       :: integer(),
    max_size       :: pos_integer(),
    prune_timer    :: reference() | undefined,
    recording      :: boolean()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the timeline tracker.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Record a state change event on the timeline.
%% Operation is one of: put, delete, clear.
-spec record(atom(), term(), put | delete | clear) -> ok.
record(Namespace, EntryKey, Operation) ->
    record(Namespace, EntryKey, Operation, #{}).

%% @doc Record a state change event with values and metadata.
%% Metadata may include: old_value, new_value, and arbitrary fields.
-spec record(atom(), term(), put | delete | clear, map()) -> ok.
record(Namespace, EntryKey, Operation, Metadata) ->
    gen_server:cast(?SERVER, {record, Namespace, EntryKey, Operation, Metadata}).

%% @doc Query the value of a key at a specific point in time.
%% Returns the last known value of the key at or before the given timestamp.
-spec at(atom(), integer()) -> {ok, [{term(), term()}]} | {error, term()}.
at(Namespace, Timestamp) ->
    gen_server:call(?SERVER, {at, Namespace, Timestamp}).

%% @doc Get all timeline events in a time range for a namespace.
-spec range(atom(), integer(), integer()) -> {ok, [map()]}.
range(Namespace, StartTime, EndTime) ->
    gen_server:call(?SERVER, {range, Namespace, StartTime, EndTime}).

%% @doc Replay all changes from a given timestamp to now.
%% Returns the list of operations that would need to be applied.
-spec replay(atom(), integer()) -> {ok, [map()]}.
replay(Namespace, FromTimestamp) ->
    replay(Namespace, FromTimestamp, erlang:system_time(millisecond)).

%% @doc Replay changes within a time range.
-spec replay(atom(), integer(), integer()) -> {ok, [map()]}.
replay(Namespace, FromTimestamp, ToTimestamp) ->
    gen_server:call(?SERVER, {replay, Namespace, FromTimestamp, ToTimestamp}).

%% @doc Get the current (most recent) value for a key from the timeline.
-spec current(atom()) -> {ok, [{term(), term()}]}.
current(Namespace) ->
    gen_server:call(?SERVER, {current, Namespace}).

%% @doc Get the full timeline history for a specific key.
-spec history(atom()) -> {ok, [map()]}.
history(Namespace) ->
    history(Namespace, []).

%% @doc Get timeline history with options.
%% Options: [{key, term()}, {limit, integer()}, {order, asc | desc}]
-spec history(atom(), list()) -> {ok, [map()]}.
history(Namespace, Opts) ->
    gen_server:call(?SERVER, {history, Namespace, Opts}).

%% @doc Prune timeline events older than the given age in milliseconds.
-spec prune(integer()) -> {ok, non_neg_integer()}.
prune(MaxAgeMs) ->
    gen_server:call(?SERVER, {prune, MaxAgeMs}, 30000).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    case ets:info(?TIMELINE_TABLE) of
        undefined ->
            _ = ets:new(?TIMELINE_TABLE, [
                named_table,
                ordered_set,
                {keypos, #timeline_event.key},
                protected
            ]);
        _ ->
            ok
    end,

    PruneTimer = erlang:send_after(?PRUNE_CHECK_INTERVAL, self(), prune_check),

    State = #state{
        sequence = 0,
        max_size = ?MAX_TIMELINE_SIZE,
        prune_timer = PruneTimer,
        recording = true
    },

    logger:info("BeamAI Timeline tracker initialized"),
    {ok, State}.

%% @private
handle_call({at, Namespace, Timestamp}, _From, State) ->
    Reply = do_at(Namespace, Timestamp),
    {reply, Reply, State};

handle_call({range, Namespace, StartTime, EndTime}, _From, State) ->
    Reply = do_range(Namespace, StartTime, EndTime),
    {reply, Reply, State};

handle_call({replay, Namespace, FromTimestamp, ToTimestamp}, _From, State) ->
    Reply = do_replay(Namespace, FromTimestamp, ToTimestamp),
    {reply, Reply, State};

handle_call({current, Namespace}, _From, State) ->
    Reply = do_current(Namespace),
    {reply, Reply, State};

handle_call({history, Namespace, Opts}, _From, State) ->
    Reply = do_history(Namespace, Opts),
    {reply, Reply, State};

handle_call({prune, MaxAgeMs}, _From, State) ->
    Cutoff = erlang:system_time(millisecond) - MaxAgeMs,
    Count = do_prune(Cutoff),
    {reply, {ok, Count}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({record, Namespace, EntryKey, Operation, Metadata}, State) ->
    case State#state.recording of
        true ->
            NewState = do_record(Namespace, EntryKey, Operation, Metadata, State),
            {noreply, NewState};
        false ->
            {noreply, State}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(prune_check, State) ->
    %% Auto-prune if over max size
    Size = ets:info(?TIMELINE_TABLE, size),
    case Size > State#state.max_size of
        true ->
            %% Remove oldest 20% of entries
            PruneCount = Size div 5,
            do_prune_oldest(PruneCount);
        false ->
            ok
    end,
    PruneTimer = erlang:send_after(?PRUNE_CHECK_INTERVAL, self(), prune_check),
    {noreply, State#state{prune_timer = PruneTimer}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, State) ->
    case State#state.prune_timer of
        undefined -> ok;
        Ref -> erlang:cancel_timer(Ref)
    end,
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private Record an event on the timeline.
do_record(Namespace, EntryKey, Operation, Metadata, State) ->
    Now = erlang:system_time(millisecond),
    Seq = State#state.sequence + 1,

    OldValue = maps:get(old_value, Metadata, undefined),
    NewValue = maps:get(new_value, Metadata, undefined),
    CleanMeta = maps:without([old_value, new_value], Metadata),

    Event = #timeline_event{
        key = {Now, Seq},
        namespace = Namespace,
        entry_key = EntryKey,
        operation = Operation,
        old_value = OldValue,
        new_value = NewValue,
        metadata = CleanMeta
    },

    ets:insert(?TIMELINE_TABLE, Event),
    State#state{sequence = Seq}.

%% @private Query values at a specific point in time.
%% Reconstructs state by scanning all events up to the given timestamp.
do_at(Namespace, Timestamp) ->
    %% Collect all events for this namespace up to Timestamp
    Events = collect_events_until(Namespace, Timestamp),

    %% Build a map of key -> latest value
    StateMap = lists:foldl(fun(Event, Acc) ->
        Key = Event#timeline_event.entry_key,
        case Event#timeline_event.operation of
            put ->
                maps:put(Key, Event#timeline_event.new_value, Acc);
            delete ->
                maps:remove(Key, Acc);
            clear ->
                #{}
        end
    end, #{}, Events),

    {ok, maps:to_list(StateMap)}.

%% @private Get all events in a time range.
do_range(Namespace, StartTime, EndTime) ->
    Events = collect_events_in_range(Namespace, StartTime, EndTime),
    Formatted = lists:map(fun event_to_map/1, Events),
    {ok, Formatted}.

%% @private Replay operations in a range (same as range but for application).
do_replay(Namespace, FromTimestamp, ToTimestamp) ->
    Events = collect_events_in_range(Namespace, FromTimestamp, ToTimestamp),
    Operations = lists:map(fun(Event) ->
        #{
            operation => Event#timeline_event.operation,
            namespace => Event#timeline_event.namespace,
            key => Event#timeline_event.entry_key,
            value => Event#timeline_event.new_value,
            timestamp => element(1, Event#timeline_event.key),
            metadata => Event#timeline_event.metadata
        }
    end, Events),
    {ok, Operations}.

%% @private Get the current state of a namespace from timeline.
do_current(Namespace) ->
    Now = erlang:system_time(millisecond),
    do_at(Namespace, Now).

%% @private Get history for a namespace, optionally filtered by key.
do_history(Namespace, Opts) ->
    FilterKey = proplists:get_value(key, Opts, undefined),
    Limit = proplists:get_value(limit, Opts, 100),
    Order = proplists:get_value(order, Opts, desc),

    %% Collect all events for this namespace
    AllEvents = ets:foldl(fun(Event, Acc) ->
        case Event#timeline_event.namespace of
            Namespace ->
                case FilterKey of
                    undefined -> [Event | Acc];
                    _ ->
                        case Event#timeline_event.entry_key of
                            FilterKey -> [Event | Acc];
                            _ -> Acc
                        end
                end;
            _ ->
                Acc
        end
    end, [], ?TIMELINE_TABLE),

    %% Sort by timestamp
    Sorted = case Order of
        desc ->
            lists:sort(fun(A, B) ->
                A#timeline_event.key >= B#timeline_event.key
            end, AllEvents);
        asc ->
            lists:sort(fun(A, B) ->
                A#timeline_event.key =< B#timeline_event.key
            end, AllEvents)
    end,

    %% Apply limit
    Limited = lists:sublist(Sorted, Limit),
    Formatted = lists:map(fun event_to_map/1, Limited),
    {ok, Formatted}.

%% @private Collect all events for a namespace up to a timestamp.
collect_events_until(Namespace, MaxTimestamp) ->
    ets:foldl(fun(Event, Acc) ->
        {Ts, _Seq} = Event#timeline_event.key,
        case Event#timeline_event.namespace =:= Namespace andalso Ts =< MaxTimestamp of
            true -> [Event | Acc];
            false -> Acc
        end
    end, [], ?TIMELINE_TABLE).

%% @private Collect events in a time range for a namespace.
collect_events_in_range(Namespace, StartTime, EndTime) ->
    Events = ets:foldl(fun(Event, Acc) ->
        {Ts, _Seq} = Event#timeline_event.key,
        case Event#timeline_event.namespace =:= Namespace andalso
             Ts >= StartTime andalso Ts =< EndTime of
            true -> [Event | Acc];
            false -> Acc
        end
    end, [], ?TIMELINE_TABLE),
    %% Sort by key ascending for correct replay order
    lists:sort(fun(A, B) ->
        A#timeline_event.key =< B#timeline_event.key
    end, Events).

%% @private Convert a timeline event record to a map.
event_to_map(#timeline_event{} = Event) ->
    {Ts, Seq} = Event#timeline_event.key,
    #{
        timestamp => Ts,
        sequence => Seq,
        namespace => Event#timeline_event.namespace,
        key => Event#timeline_event.entry_key,
        operation => Event#timeline_event.operation,
        old_value => Event#timeline_event.old_value,
        new_value => Event#timeline_event.new_value,
        metadata => Event#timeline_event.metadata
    }.

%% @private Prune events older than cutoff timestamp.
do_prune(CutoffTimestamp) ->
    %% Walk the ordered_set from the beginning
    prune_walk(ets:first(?TIMELINE_TABLE), CutoffTimestamp, 0).

prune_walk('$end_of_table', _Cutoff, Count) ->
    Count;
prune_walk({Ts, _Seq} = Key, Cutoff, Count) when Ts < Cutoff ->
    Next = ets:next(?TIMELINE_TABLE, Key),
    ets:delete(?TIMELINE_TABLE, Key),
    prune_walk(Next, Cutoff, Count + 1);
prune_walk(_, _Cutoff, Count) ->
    Count.

%% @private Prune the oldest N entries from the timeline.
do_prune_oldest(Count) ->
    prune_oldest_walk(ets:first(?TIMELINE_TABLE), Count, 0).

prune_oldest_walk('$end_of_table', _Max, Removed) ->
    Removed;
prune_oldest_walk(_Key, Max, Removed) when Removed >= Max ->
    Removed;
prune_oldest_walk(Key, Max, Removed) ->
    Next = ets:next(?TIMELINE_TABLE, Key),
    ets:delete(?TIMELINE_TABLE, Key),
    prune_oldest_walk(Next, Max, Removed + 1).
