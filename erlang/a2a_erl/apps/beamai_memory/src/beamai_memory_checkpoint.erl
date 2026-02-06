%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Memory Checkpoint Manager
%%%
%%% Provides checkpoint-based state snapshot and recovery for the
%%% BeamAI memory system. Checkpoints capture the full state of
%%% specified namespaces in the memory store at a point in time,
%%% enabling rollback on failure.
%%%
%%% Features:
%%%   - Create named checkpoints on demand
%%%   - Auto-checkpoint at configurable intervals
%%%   - Restore full namespace state from any checkpoint
%%%   - List and manage checkpoint history
%%%   - Configurable maximum checkpoint retention
%%%
%%% Checkpoints are stored internally in an ETS table keyed by
%%% checkpoint name. Each checkpoint contains a snapshot of all
%%% key-value pairs and their metadata for the captured namespaces.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_memory_checkpoint).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    create/2,
    create/3,
    restore/1,
    list/0,
    delete/1,
    auto_checkpoint/2,
    get/1,
    stop_auto_checkpoint/1
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
-define(CHECKPOINT_TABLE, beamai_checkpoints).
-define(MAX_CHECKPOINTS, 50).

-record(checkpoint, {
    name          :: binary(),
    namespaces    :: [atom()],
    data          :: map(),         %% #{Namespace => [{Key, Value, Meta}, ...]}
    created_at    :: integer(),
    metadata      :: map()
}).

-record(state, {
    max_checkpoints   :: pos_integer(),
    auto_timers       :: map(),     %% #{Namespace => TimerRef}
    checkpoint_count  :: non_neg_integer()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the checkpoint manager.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Create a named checkpoint capturing the given namespaces.
-spec create(binary(), [atom()]) -> {ok, binary()} | {error, term()}.
create(Name, Namespaces) ->
    create(Name, Namespaces, #{}).

%% @doc Create a named checkpoint with additional metadata.
-spec create(binary(), [atom()], map()) -> {ok, binary()} | {error, term()}.
create(Name, Namespaces, Metadata) ->
    gen_server:call(?SERVER, {create, Name, Namespaces, Metadata}, 30000).

%% @doc Restore memory state from a named checkpoint.
%% This replaces the current data in the checkpointed namespaces
%% with the data from the checkpoint.
-spec restore(binary()) -> ok | {error, not_found | term()}.
restore(Name) ->
    gen_server:call(?SERVER, {restore, Name}, 30000).

%% @doc List all available checkpoints with summary info.
-spec list() -> {ok, [map()]}.
list() ->
    gen_server:call(?SERVER, list_checkpoints).

%% @doc Delete a checkpoint by name.
-spec delete(binary()) -> ok | {error, not_found}.
delete(Name) ->
    gen_server:call(?SERVER, {delete, Name}).

%% @doc Get full checkpoint details by name.
-spec get(binary()) -> {ok, map()} | {error, not_found}.
get(Name) ->
    gen_server:call(?SERVER, {get_checkpoint, Name}).

%% @doc Enable auto-checkpointing for a namespace at the given interval (ms).
-spec auto_checkpoint(atom(), pos_integer()) -> ok.
auto_checkpoint(Namespace, IntervalMs) ->
    gen_server:call(?SERVER, {auto_checkpoint, Namespace, IntervalMs}).

%% @doc Stop auto-checkpointing for a namespace.
-spec stop_auto_checkpoint(atom()) -> ok.
stop_auto_checkpoint(Namespace) ->
    gen_server:call(?SERVER, {stop_auto_checkpoint, Namespace}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    %% Create checkpoint storage table
    case ets:info(?CHECKPOINT_TABLE) of
        undefined ->
            _ = ets:new(?CHECKPOINT_TABLE, [
                named_table,
                set,
                {keypos, #checkpoint.name},
                protected
            ]);
        _ ->
            ok
    end,

    MaxCheckpoints = beamai_memory_app:get_config(max_checkpoints, ?MAX_CHECKPOINTS),

    %% Set up auto-checkpoint if configured
    AutoTimers = case beamai_memory_app:get_config(auto_checkpoint, true) of
        true ->
            Interval = beamai_memory_app:get_config(checkpoint_interval, 60000),
            Ref = erlang:send_after(Interval, self(), {auto_checkpoint_tick, all, Interval}),
            #{all => Ref};
        false ->
            #{}
    end,

    State = #state{
        max_checkpoints = MaxCheckpoints,
        auto_timers = AutoTimers,
        checkpoint_count = 0
    },

    logger:info("BeamAI Checkpoint Manager initialized (max=~p)", [MaxCheckpoints]),
    {ok, State}.

%% @private
handle_call({create, Name, Namespaces, Metadata}, _From, State) ->
    case do_create_checkpoint(Name, Namespaces, Metadata, State) of
        {ok, NewState} ->
            {reply, {ok, Name}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({restore, Name}, _From, State) ->
    Reply = do_restore_checkpoint(Name),
    {reply, Reply, State};

handle_call(list_checkpoints, _From, State) ->
    Reply = do_list_checkpoints(),
    {reply, Reply, State};

handle_call({delete, Name}, _From, State) ->
    case ets:lookup(?CHECKPOINT_TABLE, Name) of
        [_] ->
            ets:delete(?CHECKPOINT_TABLE, Name),
            Count = max(0, State#state.checkpoint_count - 1),
            {reply, ok, State#state{checkpoint_count = Count}};
        [] ->
            {reply, {error, not_found}, State}
    end;

handle_call({get_checkpoint, Name}, _From, State) ->
    Reply = case ets:lookup(?CHECKPOINT_TABLE, Name) of
        [CP] ->
            {ok, checkpoint_to_map(CP)};
        [] ->
            {error, not_found}
    end,
    {reply, Reply, State};

handle_call({auto_checkpoint, Namespace, IntervalMs}, _From, State) ->
    %% Cancel any existing timer for this namespace
    Timers = State#state.auto_timers,
    NewTimers = case maps:find(Namespace, Timers) of
        {ok, OldRef} ->
            erlang:cancel_timer(OldRef),
            maps:remove(Namespace, Timers);
        error ->
            Timers
    end,
    %% Start new timer
    Ref = erlang:send_after(IntervalMs, self(), {auto_checkpoint_tick, Namespace, IntervalMs}),
    {reply, ok, State#state{auto_timers = maps:put(Namespace, Ref, NewTimers)}};

handle_call({stop_auto_checkpoint, Namespace}, _From, State) ->
    Timers = State#state.auto_timers,
    NewTimers = case maps:find(Namespace, Timers) of
        {ok, Ref} ->
            erlang:cancel_timer(Ref),
            maps:remove(Namespace, Timers);
        error ->
            Timers
    end,
    {reply, ok, State#state{auto_timers = NewTimers}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info({auto_checkpoint_tick, NamespaceOrAll, IntervalMs}, State) ->
    %% Determine which namespaces to checkpoint
    Namespaces = case NamespaceOrAll of
        all ->
            get_all_namespaces();
        Ns when is_atom(Ns) ->
            [Ns]
    end,

    Now = erlang:system_time(millisecond),
    Name = <<"auto_", (integer_to_binary(Now))/binary>>,

    NewState = case Namespaces of
        [] ->
            State;
        _ ->
            Meta = #{type => auto, triggered_by => NamespaceOrAll},
            case do_create_checkpoint(Name, Namespaces, Meta, State) of
                {ok, S} -> S;
                {error, _} -> State
            end
    end,

    %% Reschedule
    Ref = erlang:send_after(IntervalMs, self(), {auto_checkpoint_tick, NamespaceOrAll, IntervalMs}),
    Timers = maps:put(NamespaceOrAll, Ref, NewState#state.auto_timers),
    {noreply, NewState#state{auto_timers = Timers}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, State) ->
    %% Cancel all auto-checkpoint timers
    maps:foreach(fun(_Ns, Ref) ->
        erlang:cancel_timer(Ref)
    end, State#state.auto_timers),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private Create a checkpoint, enforcing max checkpoint limit.
do_create_checkpoint(Name, Namespaces, Metadata, State) ->
    try
        %% Snapshot data from the memory store for each namespace
        SnapshotData = lists:foldl(fun(Ns, Acc) ->
            NsData = snapshot_namespace(Ns),
            maps:put(Ns, NsData, Acc)
        end, #{}, Namespaces),

        Now = erlang:system_time(millisecond),

        Checkpoint = #checkpoint{
            name = Name,
            namespaces = Namespaces,
            data = SnapshotData,
            created_at = Now,
            metadata = Metadata
        },

        %% Enforce max checkpoints - remove oldest if at limit
        NewState = maybe_evict_oldest(State),

        ets:insert(?CHECKPOINT_TABLE, Checkpoint),
        Count = NewState#state.checkpoint_count + 1,
        logger:debug("BeamAI Checkpoint created: ~s (~p namespaces, ~p entries)",
                     [Name, length(Namespaces), count_snapshot_entries(SnapshotData)]),
        {ok, NewState#state{checkpoint_count = Count}}
    catch
        _:Reason ->
            logger:error("BeamAI Checkpoint creation failed: ~p", [Reason]),
            {error, Reason}
    end.

%% @private Restore data from a checkpoint into the memory store.
do_restore_checkpoint(Name) ->
    case ets:lookup(?CHECKPOINT_TABLE, Name) of
        [#checkpoint{namespaces = Namespaces, data = SnapshotData}] ->
            try
                %% Clear current data for each namespace and restore from snapshot
                lists:foreach(fun(Ns) ->
                    beamai_memory_store:clear(Ns),
                    NsData = maps:get(Ns, SnapshotData, []),
                    lists:foreach(fun({Key, Value, Meta}) ->
                        TTL = case maps:get(expires_at, Meta, infinity) of
                            infinity -> infinity;
                            ExpiresAt ->
                                Remaining = ExpiresAt - erlang:system_time(millisecond),
                                max(1000, Remaining) %% At least 1 second
                        end,
                        beamai_memory_store:put(Ns, Key, Value, [{ttl, TTL}])
                    end, NsData)
                end, Namespaces),
                logger:info("BeamAI Checkpoint restored: ~s (~p namespaces)", [Name, length(Namespaces)]),
                ok
            catch
                _:Reason ->
                    logger:error("BeamAI Checkpoint restore failed: ~p", [Reason]),
                    {error, Reason}
            end;
        [] ->
            {error, not_found}
    end.

%% @private List all checkpoints as summary maps.
do_list_checkpoints() ->
    All = ets:tab2list(?CHECKPOINT_TABLE),
    Sorted = lists:sort(fun(#checkpoint{created_at = A}, #checkpoint{created_at = B}) ->
        A >= B
    end, All),
    Summaries = lists:map(fun(CP) ->
        #{
            name => CP#checkpoint.name,
            namespaces => CP#checkpoint.namespaces,
            created_at => CP#checkpoint.created_at,
            entry_count => count_snapshot_entries(CP#checkpoint.data),
            metadata => CP#checkpoint.metadata
        }
    end, Sorted),
    {ok, Summaries}.

%% @private Full checkpoint details as a map.
checkpoint_to_map(#checkpoint{} = CP) ->
    #{
        name => CP#checkpoint.name,
        namespaces => CP#checkpoint.namespaces,
        data => CP#checkpoint.data,
        created_at => CP#checkpoint.created_at,
        entry_count => count_snapshot_entries(CP#checkpoint.data),
        metadata => CP#checkpoint.metadata
    }.

%% @private Snapshot all key-value entries for a namespace.
snapshot_namespace(Namespace) ->
    case beamai_memory_store:list(Namespace) of
        {ok, Keys} ->
            lists:filtermap(fun(Key) ->
                case beamai_memory_store:get(Namespace, Key, [{touch, false}]) of
                    {ok, Value} ->
                        %% Also grab metadata from the ETS meta table directly
                        Meta = get_entry_metadata(Namespace, Key),
                        {true, {Key, Value, Meta}};
                    {error, _} ->
                        false
                end
            end, Keys);
        _ ->
            []
    end.

%% @private Get metadata for a key directly from ETS.
get_entry_metadata(Namespace, Key) ->
    CompoundKey = {Namespace, Key},
    case ets:lookup(beamai_memory_meta, CompoundKey) of
        [{CompoundKey, Meta}] -> Meta;
        [] -> #{}
    end.

%% @private Count total entries across all namespaces in a snapshot.
count_snapshot_entries(SnapshotData) ->
    maps:fold(fun(_Ns, Entries, Acc) ->
        Acc + length(Entries)
    end, 0, SnapshotData).

%% @private Evict the oldest checkpoint if we are at the max.
maybe_evict_oldest(State) ->
    case State#state.checkpoint_count >= State#state.max_checkpoints of
        true ->
            %% Find and delete the oldest non-auto checkpoint, or oldest overall
            All = ets:tab2list(?CHECKPOINT_TABLE),
            case All of
                [] ->
                    State;
                _ ->
                    Oldest = lists:foldl(fun(CP, AccOldest) ->
                        case AccOldest of
                            undefined -> CP;
                            _ ->
                                if CP#checkpoint.created_at < AccOldest#checkpoint.created_at ->
                                    CP;
                                true ->
                                    AccOldest
                                end
                        end
                    end, undefined, All),
                    case Oldest of
                        undefined -> State;
                        #checkpoint{name = OldName} ->
                            ets:delete(?CHECKPOINT_TABLE, OldName),
                            State#state{checkpoint_count = max(0, State#state.checkpoint_count - 1)}
                    end
            end;
        false ->
            State
    end.

%% @private Get all namespaces that currently have data.
get_all_namespaces() ->
    %% Scan the data table for distinct namespaces
    Namespaces = ets:foldl(fun({{Ns, _Key}, _Value}, Acc) ->
        case lists:member(Ns, Acc) of
            true -> Acc;
            false -> [Ns | Acc]
        end
    end, [], beamai_memory_data),
    Namespaces.
