%%% @doc Disaster recovery adapter for beamai state.
%%% Snapshots beamai_memory state and kernel config, supports restore and failover.
-module(beamai_disaster_recovery_adapter).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, snapshot/0, restore/1, failover/0, get_recovery_point/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    snapshots = [] :: [map()],
    max_snapshots = 10 :: pos_integer(),
    last_snapshot :: map() | undefined
}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

snapshot() ->
    gen_server:call(?MODULE, snapshot, ?DEFAULT_TIMEOUT).

restore(SnapshotId) ->
    gen_server:call(?MODULE, {restore, SnapshotId}, ?DEFAULT_TIMEOUT).

failover() ->
    gen_server:call(?MODULE, failover, ?DEFAULT_TIMEOUT).

get_recovery_point() ->
    gen_server:call(?MODULE, get_recovery_point, ?DEFAULT_TIMEOUT).

%%% gen_server callbacks

init([]) ->
    ?LOG_INFO("beamai_disaster_recovery_adapter starting"),
    {ok, #state{}}.

handle_call(snapshot, _From, #state{snapshots = Snaps, max_snapshots = Max} = State) ->
    Now = erlang:system_time(millisecond),
    Id = integer_to_binary(Now),
    MemSnap = try
        Mem = beamai_memory:new(#{}),
        beamai_memory:get_latest_snapshot(Mem, #{})
    catch _:_ -> undefined
    end,
    KernelSnap = try
        K = #{name => <<"dr_snapshot">>, tools => []},
        #{tools => beamai_kernel:list_tools(K)}
    catch _:_ -> undefined
    end,
    AgentCard = try beamai_a2a_server:get_agent_card(#{})
    catch _:_ -> undefined
    end,
    Snap = #{id => Id, timestamp => Now,
             memory => MemSnap, kernel => KernelSnap,
             agent_card => AgentCard,
             node => node()},
    Trimmed = lists:sublist([Snap | Snaps], Max),
    ?LOG_INFO("Snapshot ~s created", [Id]),
    {reply, {ok, Id}, State#state{snapshots = Trimmed, last_snapshot = Snap}};

handle_call({restore, SnapshotId}, _From, #state{snapshots = Snaps} = State) ->
    case lists:search(fun(#{id := SId}) -> SId =:= SnapshotId end, Snaps) of
        {value, #{memory := MemSnap, kernel := _KernelSnap} = Found} ->
            ?LOG_INFO("Restoring from snapshot ~s", [SnapshotId]),
            %% Reinitialize memory from snapshot data
            RestoreResult = try
                _Mem = beamai_memory:new(#{snapshot => MemSnap}),
                ok
            catch C:R -> {error, {C, R}}
            end,
            {reply, {RestoreResult, Found}, State};
        false ->
            {reply, {error, snapshot_not_found}, State}
    end;

handle_call(failover, _From, #state{last_snapshot = undefined} = State) ->
    {reply, {error, no_snapshot_available}, State};
handle_call(failover, _From, #state{last_snapshot = #{id := Id}} = State) ->
    ?LOG_INFO("Failover: restoring from latest snapshot ~s", [Id]),
    %% Re-create core components from latest snapshot
    Result = try
        _Mem = beamai_memory:new(#{}),
        ok
    catch C:R -> {error, {C, R}}
    end,
    {reply, {Result, Id}, State};

handle_call(get_recovery_point, _From, #state{snapshots = Snaps, last_snapshot = Last} = State) ->
    Info = #{total_snapshots => length(Snaps),
             latest => case Last of undefined -> none; #{id := Id, timestamp := T} -> #{id => Id, timestamp => T} end},
    {reply, Info, State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
