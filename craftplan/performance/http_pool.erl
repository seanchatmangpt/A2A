%%% @doc HTTP Connection Pool
%%% Manages connection pooling for API calls to Craftplan backend

-module(http_pool).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([get_connection/1, release_connection/2, with_connection/3]).
-export[pool_stats/0, configure_pool/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(MAX_POOL_SIZE, 50).
-define(MAX_IDLE_TIME, 30000). % 30 seconds
-define(CONNECTION_TIMEOUT, 10000). % 10 seconds

-record(connection, {
    id :: binary(),
    pid :: pid(),
    created :: integer(),
    last_used :: integer(),
    in_use :: boolean()
}).

-record(state, {
    pool :: list(#connection{}),
    max_size :: integer(),
    max_idle :: integer(),
    timeout :: integer(),
    stats :: map()
}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

%% @doc Get a connection from the pool
-spec get_connection(binary()) -> {ok, pid()} | {error, term()}.
get_connection(PoolName) ->
    gen_server:call(?SERVER, {get_connection, PoolName}, ?CONNECTION_TIMEOUT).

%% @doc Release a connection back to the pool
-spec release_connection(binary(), pid()) -> ok.
release_connection(PoolName, Pid) ->
    gen_server:cast(?SERVER, {release_connection, PoolName, Pid}).

%% @doc Execute a function with a connection
-spec with_connection(binary(), function(), term()) -> term().
with_connection(PoolName, Fun, Args) ->
    case get_connection(PoolName) of
        {ok, Conn} ->
            try
                Fun(Conn, Args)
            catch
                Error:Reason ->
                    release_connection(PoolName, Conn),
                    erlang:error(Error, Reason)
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Get pool statistics
-spec pool_stats() -> map().
pool_stats() ->
    gen_server:call(?SERVER, pool_stats).

%% @doc Configure pool parameters
-spec configure_pool(binary(), map()) -> ok.
configure_pool(PoolName, Config) ->
    gen_server:call(?SERVER, {configure_pool, PoolName, Config}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    State = #state{
        pool = [],
        max_size = ?MAX_POOL_SIZE,
        max_idle = ?MAX_IDLE_TIME,
        timeout = ?CONNECTION_TIMEOUT,
        stats = #{
            total_created => 0,
            total_acquired => 0,
            total_released => 0,
            pool_hits => 0,
            pool_misses => 0,
            active_connections => 0
        }
    },

    %% Start connection cleanup timer
    CleanupTimer = erlang:send_after(?MAX_IDLE_TIME, self(), cleanup_idle_connections),

    io:format("HTTP Connection Pool initialized with max size ~p~n", [State#state.max_size]),
    {ok, State#state{stats = State#state.stats#{cleanup_timer => CleanupTimer}}}.

handle_call({get_connection, PoolName}, _From, State) ->
    Now = os:system_time(millisecond),

    case get_available_connection(State#state.pool, PoolName, Now) of
        {ok, Conn} ->
            %% Connection found in pool
            UpdatedConn = Conn#connection{
                in_use = true,
                last_used = Now
            },

            UpdatedPool = replace_connection(State#state.pool, Conn, UpdatedConn),
            UpdatedStats = State#state.stats#{
                total_acquired => State#state.stats.total_acquired + 1,
                pool_hits => State#state.stats.pool_hits + 1,
                active_connections => State#state.stats.active_connections + 1
            },

            io:format("Connection acquired from pool. Active: ~p, Available: ~p~n",
                [UpdatedStats.active_connections, length(UpdatedPool)]),

            {reply, {ok, UpdatedConn#connection.pid}, State#state{pool = UpdatedPool, stats = UpdatedStats}};
        {error, Reason} ->
            %% No available connection, create new one
            case create_new_connection(PoolName, State) of
                {ok, Conn} ->
                    UpdatedStats = State#state.stats#{
                        total_acquired => State#state.stats.total_acquired + 1,
                        pool_misses => State#state.stats.pool_misses + 1,
                        total_created => State#state.stats.total_created + 1,
                        active_connections => State#state.stats.active_connections + 1
                    },

                    io:format("New connection created. Active: ~p, Available: ~p~n",
                        [UpdatedStats.active_connections, State#state.stats.active_connections]),

                    {reply, {ok, Conn#connection.pid}, State#state{stats = UpdatedStats}};
                {error, CreateReason} ->
                    io:format("Failed to create new connection: ~p~n", [CreateReason]),
                    {reply, {error, CreateReason}, State}
            end
    end;

handle_call(pool_stats, _From, State) ->
    Stats = State#state.stats#{
        pool_size => length(State#state.pool),
        max_pool_size => State#state.max_size,
        pool_utilization => calculate_utilization(State)
    },
    {reply, Stats, State};

handle_call({configure_pool, PoolName, Config}, _From, State) ->
    MaxSize = maps:get(max_size, Config, State#state.max_size),
    MaxIdle = maps:get(max_idle, Config, State#state.max_idle),
    Timeout = maps:get(timeout, Config, State#state.timeout),

    NewState = State#state{
        max_size = MaxSize,
        max_idle = MaxIdle,
        timeout = Timeout
    },

    io:format("Pool ~s configured: max_size=~p, max_idle=~p, timeout=~p~n",
        [PoolName, MaxSize, MaxIdle, Timeout]),

    {reply, ok, NewState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast({release_connection, PoolName, Pid}, State) ->
    Now = os:system_time(millisecond),

    case find_connection(State#state.pool, Pid) of
        {ok, Conn} ->
            %% Mark connection as available
            ReleasedConn = Conn#connection{
                in_use = false,
                last_used = Now
            },

            UpdatedPool = replace_connection(State#state.pool, Conn, ReleasedConn),
            UpdatedStats = State#state.stats#{
                total_released => State#state.stats.total_released + 1,
                active_connections => max(State#state.stats.active_connections - 1, 0)
            },

            io:format("Connection released. Active: ~p, Available: ~p~n",
                [UpdatedStats.active_connections, length(UpdatedPool)]),

            {noreply, State#state{pool = UpdatedPool, stats = UpdatedStats}};
        {error, not_found} ->
            io:format("Attempted to release unknown connection: ~p~n", [Pid]),
            {noreply, State}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(cleanup_idle_connections, State) ->
    Now = os:system_time(millisecond),
    MaxAge = State#state.max_idle,

    {Active, Idle, Removed} = cleanup_connections(State#state.pool, Now, MaxAge),

    case Removed > 0 of
        true ->
            io:format("Cleanup removed ~p idle connections. Active: ~p, Idle: ~p~n",
                [Removed, Active, Idle]),
            %% Restart cleanup timer
            CleanupTimer = erlang:send_after(?MAX_IDLE_TIME, self(), cleanup_idle_connections),
            {noreply, State#state{pool = Active ++ Idle, stats = State#state.stats#{cleanup_timer => CleanupTimer}}};
        false ->
            %% Restart cleanup timer
            CleanupTimer = erlang:send_after(?MAX_IDLE_TIME, self(), cleanup_idle_connections),
            {noreply, State#state{stats = State#state.stats#{cleanup_timer => CleanupTimer}}}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    %% Close all connections
    lists:foreach(fun(Conn) ->
        try
            close_connection(Conn#connection.pid)
        catch
            _:_ -> ok
        end
    end, State#state.pool),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

get_available_connection([], _PoolName, _Now) ->
    {error, no_connections_available};

get_available_connection([Conn | Rest], PoolName, Now) ->
    case Conn#connection.in_use of
        false ->
            %% Check if connection is still alive
            case is_connection_alive(Conn#connection.pid) of
                true ->
                    {ok, Conn};
                false ->
                    %% Remove dead connection and continue searching
                    get_available_connection(Rest, PoolName, Now)
            end;
        true ->
            get_available_connection(Rest, PoolName, Now)
    end.

create_new_connection(PoolName, State) ->
    case State#state.stats.active_connections < State#state.max_size of
        true ->
            case start_connection(PoolName) of
                {ok, Pid} ->
                    Conn = #connection{
                        id = generate_connection_id(),
                        pid = Pid,
                        created = os:system_time(millisecond),
                        last_used = os:system_time(millisecond),
                        in_use = false
                    },
                    {ok, Conn};
                {error, Reason} ->
                    {error, Reason}
            end;
        false ->
            {error, pool_full}
    end.

start_connection(PoolName) ->
    %% Start HTTP connection process
    case http_client:start_link(PoolName) of
        {ok, Pid} ->
            {ok, Pid};
        {error, Reason} ->
            {error, Reason}
    end.

replace_connection(Pool, OldConn, NewConn) ->
    lists:map(fun(C) ->
        if
            C#connection.id =:= OldConn#connection.id ->
                NewConn;
            true ->
                C
        end
    end, Pool).

find_connection([], _Pid) ->
    {error, not_found};

find_connection([Conn | Rest], Pid) ->
    case Conn#connection.pid =:= Pid of
        true ->
            {ok, Conn};
        false ->
            find_connection(Rest, Pid)
    end.

cleanup_connections(Pool, Now, MaxAge) ->
    cleanup_connections(Pool, Now, MaxAge, [], [], 0).

cleanup_connections([], _Now, _MaxAge, Active, Idle, Removed) ->
    {Active, Idle, Removed};

cleanup_connections([Conn | Rest], Now, MaxAge, Active, Idle, Removed) ->
    case Conn#connection.in_use of
        true ->
            cleanup_connections(Rest, Now, MaxAge, [Conn | Active], Idle, Removed);
        false ->
            Age = Now - Conn#connection.last_used,
            if
                Age > MaxAge ->
                    %% Remove old connection
                    close_connection(Conn#connection.pid),
                    cleanup_connections(Rest, Now, MaxAge, Active, Idle, Removed + 1);
                true ->
                    keep_alive_connection(Conn#connection.pid),
                    cleanup_connections(Rest, Now, MaxAge, Active, [Conn | Idle], Removed)
            end
    end.

is_connection_alive(Pid) ->
    case is_process_alive(Pid) of
        true ->
            case process_info(Pid, status) of
                {status, waiting} -> true;
                {status, runnable} -> true;
                {status, runnable} -> true;
                _ -> false
            end;
        false ->
            false
    end.

close_connection(Pid) ->
    try
        http_client:stop(Pid)
    catch
        _:_ -> ok
    end.

keep_alive_connection(Pid) ->
    try
        http_client:ping(Pid)
    catch
        _:_ -> ok
    end.

generate_connection_id() ->
    Timestamp = os:system_time(millisecond),
    Random = rand:uniform(1000000),
    iolist_to_binary(io_lib:format("conn_~p_~p", [Timestamp, Random])).

calculate_utilization(State) ->
    case State#state.max_size > 0 of
        true ->
            (State#state.stats.active_connections / State#state.max_size) * 100;
        false ->
            0
    end.