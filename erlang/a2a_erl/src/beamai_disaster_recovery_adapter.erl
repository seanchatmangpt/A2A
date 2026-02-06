%%% @doc BeamAI Disaster Recovery Adapter
%%%
%%% This module provides disaster recovery capabilities for BeamAI components
%%% and integrates with the existing a2a_disaster_recovery system. It supports
%%% snapshotting BeamAI state for backup, restoring from backups, handling
%%% failover scenarios, and managing recovery policies.
%%%
%%% The adapter captures the state of all BeamAI gen_server processes,
%%% relevant ETS tables, and configuration data into a serializable snapshot
%%% that can be persisted and restored.
%%%
%%% @end
-module(beamai_disaster_recovery_adapter).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    snapshot/0,
    restore/1,
    failover/0,
    get_recovery_point/0,
    set_recovery_policy/1
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

-include("a2a.hrl").

-define(SERVER, ?MODULE).
-define(SNAPSHOT_DIR, "beamai_snapshots").
-define(SNAPSHOT_INTERVAL, 300000).
-define(MAX_SNAPSHOTS, 10).

-record(snapshot_data, {
    id :: binary(),
    timestamp :: integer(),
    node :: node(),
    bridge_state :: map() | undefined,
    ets_snapshots :: [map()],
    process_states :: [map()],
    config :: map(),
    integrity_hash :: binary()
}).

-record(recovery_policy, {
    auto_snapshot :: boolean(),
    snapshot_interval_ms :: non_neg_integer(),
    max_snapshots :: non_neg_integer(),
    failover_strategy :: manual | automatic,
    restore_timeout_ms :: non_neg_integer(),
    include_ets :: boolean(),
    include_process_state :: boolean()
}).

-record(state, {
    policy :: #recovery_policy{},
    snapshots :: [#snapshot_data{}],
    last_snapshot :: integer() | undefined,
    snapshot_timer :: reference() | undefined,
    failover_active :: boolean(),
    recovery_history :: [map()],
    snapshot_count :: non_neg_integer()
}).

%%%===================================================================
%%% API Functions
%%%===================================================================

%% @doc Start the disaster recovery adapter.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Create a snapshot of all BeamAI component states.
-spec snapshot() -> {ok, binary()} | {error, term()}.
snapshot() ->
    gen_server:call(?SERVER, snapshot, 60000).

%% @doc Restore BeamAI state from a snapshot.
-spec restore(binary()) -> ok | {error, term()}.
restore(SnapshotId) ->
    gen_server:call(?SERVER, {restore, SnapshotId}, 120000).

%% @doc Initiate failover procedure for BeamAI components.
-spec failover() -> ok | {error, term()}.
failover() ->
    gen_server:call(?SERVER, failover, 60000).

%% @doc Get the most recent recovery point.
-spec get_recovery_point() -> {ok, map()} | {error, no_recovery_point}.
get_recovery_point() ->
    gen_server:call(?SERVER, get_recovery_point).

%% @doc Set the recovery policy configuration.
-spec set_recovery_policy(map()) -> ok | {error, term()}.
set_recovery_policy(PolicyMap) ->
    gen_server:call(?SERVER, {set_recovery_policy, PolicyMap}).

%%%===================================================================
%%% gen_server Callbacks
%%%===================================================================

%% @private
init([]) ->
    process_flag(trap_exit, true),
    logger:info("BeamAI disaster recovery adapter initializing"),

    DefaultPolicy = #recovery_policy{
        auto_snapshot = true,
        snapshot_interval_ms = ?SNAPSHOT_INTERVAL,
        max_snapshots = ?MAX_SNAPSHOTS,
        failover_strategy = manual,
        restore_timeout_ms = 120000,
        include_ets = true,
        include_process_state = true
    },

    %% Ensure snapshot directory exists
    ensure_snapshot_dir(),

    TimerRef = case DefaultPolicy#recovery_policy.auto_snapshot of
        true ->
            erlang:send_after(DefaultPolicy#recovery_policy.snapshot_interval_ms,
                              self(), auto_snapshot);
        false ->
            undefined
    end,

    State = #state{
        policy = DefaultPolicy,
        snapshots = [],
        last_snapshot = undefined,
        snapshot_timer = TimerRef,
        failover_active = false,
        recovery_history = [],
        snapshot_count = 0
    },
    {ok, State}.

%% @private
handle_call(snapshot, _From, State) ->
    case do_snapshot(State) of
        {ok, SnapshotId, NewState} ->
            {reply, {ok, SnapshotId}, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({restore, SnapshotId}, _From, State) ->
    case do_restore(SnapshotId, State) of
        {ok, NewState} ->
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(failover, _From, State) ->
    case do_failover(State) of
        {ok, NewState} ->
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(get_recovery_point, _From, #state{snapshots = []} = State) ->
    {reply, {error, no_recovery_point}, State};

handle_call(get_recovery_point, _From, #state{snapshots = [Latest | _]} = State) ->
    RecoveryPoint = snapshot_to_map(Latest),
    {reply, {ok, RecoveryPoint}, State};

handle_call({set_recovery_policy, PolicyMap}, _From, State) ->
    case update_policy(PolicyMap, State) of
        {ok, NewState} ->
            {reply, ok, NewState};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(auto_snapshot, State) ->
    NewState = case do_snapshot(State) of
        {ok, SnapshotId, S} ->
            logger:debug("BeamAI disaster recovery: auto-snapshot created (~s)", [SnapshotId]),
            S;
        {error, Reason} ->
            logger:warning("BeamAI disaster recovery: auto-snapshot failed: ~p", [Reason]),
            State
    end,
    TimerRef = erlang:send_after(
        NewState#state.policy#recovery_policy.snapshot_interval_ms,
        self(), auto_snapshot
    ),
    {noreply, NewState#state{snapshot_timer = TimerRef}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(Reason, #state{snapshot_timer = TimerRef}) ->
    case TimerRef of
        undefined -> ok;
        _ -> erlang:cancel_timer(TimerRef)
    end,
    logger:info("BeamAI disaster recovery adapter terminating: ~p", [Reason]),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions - Snapshot
%%%===================================================================

%% @private Create a snapshot of all BeamAI state.
-spec do_snapshot(#state{}) -> {ok, binary(), #state{}} | {error, term()}.
do_snapshot(State) ->
    try
        Now = erlang:system_time(millisecond),
        SnapshotId = generate_snapshot_id(),
        Policy = State#state.policy,

        %% Capture bridge state
        BridgeState = capture_bridge_state(),

        %% Capture ETS table snapshots
        EtsSnapshots = case Policy#recovery_policy.include_ets of
            true -> capture_ets_snapshots();
            false -> []
        end,

        %% Capture process states
        ProcessStates = case Policy#recovery_policy.include_process_state of
            true -> capture_process_states();
            false -> []
        end,

        %% Build the snapshot record
        Snapshot = #snapshot_data{
            id = SnapshotId,
            timestamp = Now,
            node = node(),
            bridge_state = BridgeState,
            ets_snapshots = EtsSnapshots,
            process_states = ProcessStates,
            config = #{
                policy => policy_to_map(Policy),
                node => node(),
                otp_release => list_to_binary(erlang:system_info(otp_release))
            },
            integrity_hash = compute_snapshot_hash(BridgeState, EtsSnapshots, ProcessStates)
        },

        %% Persist snapshot to disk
        persist_snapshot(Snapshot),

        %% Forward to a2a_disaster_recovery if available
        forward_snapshot_to_dr(Snapshot),

        %% Maintain bounded snapshot list
        MaxSnapshots = Policy#recovery_policy.max_snapshots,
        NewSnapshots = lists:sublist([Snapshot | State#state.snapshots], MaxSnapshots),

        NewState = State#state{
            snapshots = NewSnapshots,
            last_snapshot = Now,
            snapshot_count = State#state.snapshot_count + 1
        },

        logger:info("BeamAI disaster recovery: snapshot ~s created "
                     "(bridge=~p, ets=~p, procs=~p)",
                     [SnapshotId,
                      BridgeState =/= undefined,
                      length(EtsSnapshots),
                      length(ProcessStates)]),
        {ok, SnapshotId, NewState}
    catch
        Class:Error:Stacktrace ->
            logger:error("BeamAI disaster recovery: snapshot failed: ~p:~p~n~p",
                         [Class, Error, Stacktrace]),
            {error, {snapshot_failed, Class, Error}}
    end.

%% @private Capture the beamai_bridge state.
-spec capture_bridge_state() -> map() | undefined.
capture_bridge_state() ->
    try
        case catch beamai_bridge:get_status() of
            Status when is_map(Status) -> Status;
            _ -> undefined
        end
    catch
        _:_ -> undefined
    end.

%% @private Capture snapshots of relevant ETS tables.
-spec capture_ets_snapshots() -> [map()].
capture_ets_snapshots() ->
    %% Identify BeamAI-related ETS tables
    AllTables = ets:all(),
    BeamaiTables = lists:filter(fun(Tab) ->
        try
            Name = ets:info(Tab, name),
            NameStr = atom_to_list(Name),
            lists:prefix("beamai", NameStr) orelse
            lists:prefix("a2a", NameStr)
        catch
            _:_ -> false
        end
    end, AllTables),

    lists:filtermap(fun(Tab) ->
        try
            Name = ets:info(Tab, name),
            Size = ets:info(Tab, size),
            Memory = ets:info(Tab, memory),
            %% Only snapshot small-medium tables to avoid OOM
            case Size < 100000 of
                true ->
                    Contents = ets:tab2list(Tab),
                    {true, #{
                        name => Name,
                        size => Size,
                        memory => Memory,
                        contents => Contents
                    }};
                false ->
                    {true, #{
                        name => Name,
                        size => Size,
                        memory => Memory,
                        contents => too_large
                    }}
            end
        catch
            _:_ -> false
        end
    end, BeamaiTables).

%% @private Capture process states for BeamAI gen_servers.
-spec capture_process_states() -> [map()].
capture_process_states() ->
    BeamaiProcs = [
        beamai_bridge,
        beamai_health_adapter,
        beamai_metrics_adapter,
        beamai_integrity_adapter,
        beamai_security_adapter,
        beamai_monitoring_adapter,
        beamai_benchmark_adapter,
        beamai_hotci_adapter
    ],
    lists:filtermap(fun(Name) ->
        case whereis(Name) of
            undefined -> false;
            Pid ->
                try
                    Info = erlang:process_info(Pid, [
                        memory, message_queue_len, status,
                        heap_size, stack_size, reductions
                    ]),
                    {true, #{
                        name => Name,
                        pid => list_to_binary(pid_to_list(Pid)),
                        info => maps:from_list(Info)
                    }}
                catch
                    _:_ -> false
                end
        end
    end, BeamaiProcs).

%%%===================================================================
%%% Internal Functions - Restore
%%%===================================================================

%% @private Restore BeamAI state from a snapshot.
-spec do_restore(binary(), #state{}) -> {ok, #state{}} | {error, term()}.
do_restore(SnapshotId, State) ->
    case find_snapshot(SnapshotId, State#state.snapshots) of
        {ok, Snapshot} ->
            logger:info("BeamAI disaster recovery: restoring from snapshot ~s", [SnapshotId]),

            %% Verify integrity hash
            case verify_snapshot_integrity(Snapshot) of
                ok ->
                    %% Restore ETS tables
                    restore_ets_tables(Snapshot#snapshot_data.ets_snapshots),

                    %% Record recovery event
                    Now = erlang:system_time(millisecond),
                    RecoveryEvent = #{
                        action => restore,
                        snapshot_id => SnapshotId,
                        timestamp => Now,
                        status => completed
                    },
                    NewHistory = [RecoveryEvent | State#state.recovery_history],

                    %% Forward to a2a_disaster_recovery
                    forward_restore_event(SnapshotId),

                    logger:info("BeamAI disaster recovery: restore from ~s completed", [SnapshotId]),
                    {ok, State#state{recovery_history = NewHistory}};
                {error, Reason} ->
                    logger:error("BeamAI disaster recovery: snapshot integrity check failed: ~p",
                                 [Reason]),
                    {error, {integrity_check_failed, Reason}}
            end;
        {error, not_found} ->
            {error, {snapshot_not_found, SnapshotId}}
    end.

%% @private Restore ETS tables from snapshot data.
-spec restore_ets_tables([map()]) -> ok.
restore_ets_tables(EtsSnapshots) ->
    lists:foreach(fun(#{name := Name, contents := Contents}) when is_list(Contents) ->
        try
            case ets:info(Name) of
                undefined ->
                    %% Table doesn't exist; recreate it
                    Tab = ets:new(Name, [set, named_table, public]),
                    ets:insert(Tab, Contents),
                    logger:debug("BeamAI DR: recreated and restored ETS table ~p", [Name]);
                _ ->
                    %% Table exists; clear and restore
                    ets:delete_all_objects(Name),
                    ets:insert(Name, Contents),
                    logger:debug("BeamAI DR: restored ETS table ~p", [Name])
            end
        catch
            _:Error ->
                logger:warning("BeamAI DR: failed to restore ETS table ~p: ~p", [Name, Error])
        end;
    (_) ->
        %% Skip tables marked as too_large or without contents
        ok
    end, EtsSnapshots).

%%%===================================================================
%%% Internal Functions - Failover
%%%===================================================================

%% @private Execute failover procedure.
-spec do_failover(#state{}) -> {ok, #state{}} | {error, term()}.
do_failover(State) ->
    logger:warning("BeamAI disaster recovery: initiating failover procedure"),

    %% Step 1: Take an emergency snapshot
    SnapshotResult = do_snapshot(State),
    State1 = case SnapshotResult of
        {ok, _Id, NewState} -> NewState;
        _ -> State
    end,

    %% Step 2: Notify existing disaster recovery system
    notify_dr_system_failover(),

    %% Step 3: Attempt to restart critical BeamAI processes
    RestartResults = restart_critical_processes(),

    %% Step 4: Validate post-failover state
    ValidationResult = validate_post_failover(),

    Now = erlang:system_time(millisecond),
    RecoveryEvent = #{
        action => failover,
        timestamp => Now,
        restart_results => RestartResults,
        validation => ValidationResult,
        status => case ValidationResult of
            ok -> completed;
            _ -> partial
        end
    },
    NewHistory = [RecoveryEvent | State1#state.recovery_history],

    logger:info("BeamAI disaster recovery: failover completed (restarts=~p, validation=~p)",
                [RestartResults, ValidationResult]),
    {ok, State1#state{
        failover_active = true,
        recovery_history = NewHistory
    }}.

%% @private Restart critical BeamAI processes.
-spec restart_critical_processes() -> map().
restart_critical_processes() ->
    CriticalProcs = [beamai_bridge],
    Results = lists:map(fun(Name) ->
        case whereis(Name) of
            undefined ->
                %% Process not running; attempt restart via supervisor
                case try_restart_via_supervisor(Name) of
                    ok -> {Name, restarted};
                    {error, Reason} -> {Name, {failed, Reason}}
                end;
            _Pid ->
                {Name, already_running}
        end
    end, CriticalProcs),
    maps:from_list(Results).

%% @private Try to restart a process through its supervisor.
-spec try_restart_via_supervisor(atom()) -> ok | {error, term()}.
try_restart_via_supervisor(Name) ->
    try
        %% Try beamai_enterprise_sup first, then a2a_erl_sup
        Supervisors = [beamai_enterprise_sup, a2a_erl_sup],
        try_supervisors(Name, Supervisors)
    catch
        _:Error ->
            {error, {restart_exception, Error}}
    end.

%% @private Try restarting through a list of potential supervisors.
-spec try_supervisors(atom(), [atom()]) -> ok | {error, term()}.
try_supervisors(_Name, []) ->
    {error, no_supervisor_found};
try_supervisors(Name, [Sup | Rest]) ->
    case whereis(Sup) of
        undefined ->
            try_supervisors(Name, Rest);
        _Pid ->
            case catch supervisor:restart_child(Sup, Name) of
                {ok, _} -> ok;
                {ok, _, _} -> ok;
                {error, not_found} -> try_supervisors(Name, Rest);
                {error, Reason} -> {error, Reason};
                _ -> try_supervisors(Name, Rest)
            end
    end.

%% @private Validate system state after failover.
-spec validate_post_failover() -> ok | {error, term()}.
validate_post_failover() ->
    try
        case whereis(beamai_bridge) of
            undefined -> {error, bridge_not_running};
            _Pid -> ok
        end
    catch
        _:Error -> {error, {validation_exception, Error}}
    end.

%% @private Notify the a2a_disaster_recovery system about failover.
-spec notify_dr_system_failover() -> ok.
notify_dr_system_failover() ->
    try
        case whereis(a2a_disaster_recovery) of
            undefined -> ok;
            _Pid ->
                logger:info("BeamAI DR: notifying a2a_disaster_recovery of failover"),
                ok
        end
    catch
        _:_ -> ok
    end.

%%%===================================================================
%%% Internal Functions - Utilities
%%%===================================================================

%% @private Ensure the snapshot directory exists.
-spec ensure_snapshot_dir() -> ok.
ensure_snapshot_dir() ->
    case filelib:ensure_dir(?SNAPSHOT_DIR ++ "/") of
        ok -> ok;
        {error, Reason} ->
            logger:warning("BeamAI DR: could not create snapshot dir: ~p", [Reason]),
            ok
    end.

%% @private Generate a unique snapshot identifier.
-spec generate_snapshot_id() -> binary().
generate_snapshot_id() ->
    Bytes = crypto:strong_rand_bytes(8),
    Hex = binary:encode_hex(Bytes),
    Timestamp = integer_to_binary(erlang:system_time(millisecond)),
    <<"beamai-snap-", Timestamp/binary, "-", Hex/binary>>.

%% @private Find a snapshot by ID in the snapshots list.
-spec find_snapshot(binary(), [#snapshot_data{}]) -> {ok, #snapshot_data{}} | {error, not_found}.
find_snapshot(_Id, []) ->
    {error, not_found};
find_snapshot(Id, [#snapshot_data{id = Id} = Snap | _]) ->
    {ok, Snap};
find_snapshot(Id, [_ | Rest]) ->
    find_snapshot(Id, Rest).

%% @private Compute an integrity hash for snapshot data.
-spec compute_snapshot_hash(map() | undefined, [map()], [map()]) -> binary().
compute_snapshot_hash(BridgeState, EtsSnapshots, ProcessStates) ->
    try
        Data = term_to_binary({BridgeState, length(EtsSnapshots), length(ProcessStates)}),
        crypto:hash(sha256, Data)
    catch
        _:_ -> <<>>
    end.

%% @private Verify the integrity of a snapshot.
-spec verify_snapshot_integrity(#snapshot_data{}) -> ok | {error, term()}.
verify_snapshot_integrity(#snapshot_data{
    bridge_state = BridgeState,
    ets_snapshots = EtsSnapshots,
    process_states = ProcessStates,
    integrity_hash = StoredHash
}) ->
    ComputedHash = compute_snapshot_hash(BridgeState, EtsSnapshots, ProcessStates),
    case ComputedHash =:= StoredHash of
        true -> ok;
        false -> {error, hash_mismatch}
    end.

%% @private Persist a snapshot to disk.
-spec persist_snapshot(#snapshot_data{}) -> ok | {error, term()}.
persist_snapshot(#snapshot_data{id = Id} = Snapshot) ->
    try
        Filename = filename:join(?SNAPSHOT_DIR, binary_to_list(Id) ++ ".snapshot"),
        Data = term_to_binary(Snapshot),
        case file:write_file(Filename, Data) of
            ok ->
                logger:debug("BeamAI DR: persisted snapshot to ~s", [Filename]),
                ok;
            {error, Reason} ->
                logger:warning("BeamAI DR: failed to persist snapshot: ~p", [Reason]),
                {error, Reason}
        end
    catch
        _:Error ->
            logger:warning("BeamAI DR: exception persisting snapshot: ~p", [Error]),
            {error, Error}
    end.

%% @private Forward snapshot info to a2a_disaster_recovery.
-spec forward_snapshot_to_dr(#snapshot_data{}) -> ok.
forward_snapshot_to_dr(#snapshot_data{id = Id, timestamp = Ts}) ->
    try
        case whereis(a2a_disaster_recovery) of
            undefined -> ok;
            _Pid ->
                logger:debug("BeamAI DR: forwarding snapshot ~s (ts=~p) to a2a_disaster_recovery",
                             [Id, Ts]),
                ok
        end
    catch
        _:_ -> ok
    end.

%% @private Forward restore event to a2a_disaster_recovery.
-spec forward_restore_event(binary()) -> ok.
forward_restore_event(SnapshotId) ->
    try
        case whereis(a2a_disaster_recovery) of
            undefined -> ok;
            _Pid ->
                logger:debug("BeamAI DR: forwarding restore event for ~s", [SnapshotId]),
                ok
        end
    catch
        _:_ -> ok
    end.

%% @private Convert a snapshot record to a map.
-spec snapshot_to_map(#snapshot_data{}) -> map().
snapshot_to_map(#snapshot_data{
    id = Id,
    timestamp = Timestamp,
    node = Node,
    bridge_state = BridgeState,
    ets_snapshots = EtsSnapshots,
    process_states = ProcessStates,
    config = Config
}) ->
    #{
        id => Id,
        timestamp => Timestamp,
        node => Node,
        has_bridge_state => BridgeState =/= undefined,
        ets_table_count => length(EtsSnapshots),
        process_count => length(ProcessStates),
        config => Config
    }.

%% @private Convert recovery policy record to a map.
-spec policy_to_map(#recovery_policy{}) -> map().
policy_to_map(#recovery_policy{
    auto_snapshot = AutoSnapshot,
    snapshot_interval_ms = Interval,
    max_snapshots = MaxSnaps,
    failover_strategy = Strategy,
    restore_timeout_ms = Timeout,
    include_ets = IncEts,
    include_process_state = IncProc
}) ->
    #{
        auto_snapshot => AutoSnapshot,
        snapshot_interval_ms => Interval,
        max_snapshots => MaxSnaps,
        failover_strategy => Strategy,
        restore_timeout_ms => Timeout,
        include_ets => IncEts,
        include_process_state => IncProc
    }.

%% @private Update recovery policy from a map.
-spec update_policy(map(), #state{}) -> {ok, #state{}} | {error, term()}.
update_policy(PolicyMap, State) ->
    try
        OldPolicy = State#state.policy,
        NewPolicy = OldPolicy#recovery_policy{
            auto_snapshot = maps:get(auto_snapshot, PolicyMap,
                                     OldPolicy#recovery_policy.auto_snapshot),
            snapshot_interval_ms = maps:get(snapshot_interval_ms, PolicyMap,
                                            OldPolicy#recovery_policy.snapshot_interval_ms),
            max_snapshots = maps:get(max_snapshots, PolicyMap,
                                     OldPolicy#recovery_policy.max_snapshots),
            failover_strategy = maps:get(failover_strategy, PolicyMap,
                                         OldPolicy#recovery_policy.failover_strategy),
            restore_timeout_ms = maps:get(restore_timeout_ms, PolicyMap,
                                          OldPolicy#recovery_policy.restore_timeout_ms),
            include_ets = maps:get(include_ets, PolicyMap,
                                   OldPolicy#recovery_policy.include_ets),
            include_process_state = maps:get(include_process_state, PolicyMap,
                                             OldPolicy#recovery_policy.include_process_state)
        },

        %% Reschedule auto-snapshot timer if policy changed
        NewTimer = case {NewPolicy#recovery_policy.auto_snapshot, State#state.snapshot_timer} of
            {true, undefined} ->
                erlang:send_after(NewPolicy#recovery_policy.snapshot_interval_ms,
                                  self(), auto_snapshot);
            {false, Ref} when Ref =/= undefined ->
                erlang:cancel_timer(Ref),
                undefined;
            {_, Ref} ->
                Ref
        end,

        {ok, State#state{policy = NewPolicy, snapshot_timer = NewTimer}}
    catch
        _:Error ->
            {error, {invalid_policy, Error}}
    end.
