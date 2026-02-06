%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Memory Store
%%%
%%% A gen_server providing key-value storage with pluggable backends.
%%% Currently supports:
%%%   - ETS backend (default) for fast in-memory storage
%%%   - SQLite backend for persistent storage
%%%
%%% Features:
%%%   - Namespace support for logical data separation (tasks, workflows, agents)
%%%   - TTL support for automatic expiry of entries
%%%   - Pattern-based search across stored data
%%%   - Metadata tracking (created_at, updated_at, access_count)
%%%
%%% Each stored entry has the structure:
%%%   {Key, Value, Metadata}
%%% where Metadata = #{
%%%     namespace => atom(),
%%%     created_at => integer(),
%%%     updated_at => integer(),
%%%     expires_at => integer() | infinity,
%%%     access_count => non_neg_integer(),
%%%     last_accessed => integer()
%%% }
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_memory_store).

-behaviour(gen_server).

%% API
-export([
    start_link/1,
    get/2,
    get/3,
    put/3,
    put/4,
    delete/2,
    delete/3,
    list/1,
    list/2,
    search/2,
    search/3,
    clear/1,
    clear/0,
    info/0,
    info/1
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
-define(DATA_TABLE, beamai_memory_data).
-define(META_TABLE, beamai_memory_meta).
-define(TTL_TABLE, beamai_memory_ttl).
-define(TTL_CHECK_INTERVAL, 30000). %% 30 seconds

-record(state, {
    backend       :: ets | sqlite,
    sqlite_ref    :: reference() | undefined,
    sqlite_path   :: string(),
    default_ttl   :: integer() | infinity,
    ttl_timer     :: reference() | undefined,
    stats         :: map()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the memory store with the given options.
%% Options:
%%   backend => ets | sqlite
%%   sqlite_db_path => string()
%%   default_ttl => integer() | infinity
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%% @doc Get a value by key from the default namespace.
-spec get(atom(), term()) -> {ok, term()} | {error, not_found | expired}.
get(Namespace, Key) ->
    get(Namespace, Key, []).

%% @doc Get a value by key with options.
%% Options: [{touch, boolean()}] - whether to update access metadata (default: true)
-spec get(atom(), term(), list()) -> {ok, term()} | {error, not_found | expired}.
get(Namespace, Key, Opts) ->
    gen_server:call(?SERVER, {get, Namespace, Key, Opts}).

%% @doc Put a value with key in the given namespace.
-spec put(atom(), term(), term()) -> ok.
put(Namespace, Key, Value) ->
    put(Namespace, Key, Value, []).

%% @doc Put a value with options.
%% Options: [{ttl, integer() | infinity}] - time-to-live in milliseconds
-spec put(atom(), term(), term(), list()) -> ok.
put(Namespace, Key, Value, Opts) ->
    gen_server:call(?SERVER, {put, Namespace, Key, Value, Opts}).

%% @doc Delete a key from the given namespace.
-spec delete(atom(), term()) -> ok.
delete(Namespace, Key) ->
    delete(Namespace, Key, []).

%% @doc Delete a key with options.
-spec delete(atom(), term(), list()) -> ok.
delete(Namespace, Key, Opts) ->
    gen_server:call(?SERVER, {delete, Namespace, Key, Opts}).

%% @doc List all keys in a namespace.
-spec list(atom()) -> {ok, [term()]}.
list(Namespace) ->
    list(Namespace, []).

%% @doc List keys in a namespace with options.
%% Options: [{limit, integer()}, {offset, integer()}]
-spec list(atom(), list()) -> {ok, [term()]}.
list(Namespace, Opts) ->
    gen_server:call(?SERVER, {list, Namespace, Opts}).

%% @doc Search for entries matching a pattern in a namespace.
%% Pattern can be a fun/1 applied to {Key, Value} tuples, or a map
%% of metadata criteria.
-spec search(atom(), term()) -> {ok, [{term(), term()}]}.
search(Namespace, Pattern) ->
    search(Namespace, Pattern, []).

%% @doc Search with options.
%% Options: [{limit, integer()}, {include_metadata, boolean()}]
-spec search(atom(), term(), list()) -> {ok, [{term(), term()}]} | {ok, [{term(), term(), map()}]}.
search(Namespace, Pattern, Opts) ->
    gen_server:call(?SERVER, {search, Namespace, Pattern, Opts}).

%% @doc Clear all entries in a namespace.
-spec clear(atom()) -> ok.
clear(Namespace) ->
    gen_server:call(?SERVER, {clear, Namespace}).

%% @doc Clear all entries across all namespaces.
-spec clear() -> ok.
clear() ->
    gen_server:call(?SERVER, clear_all).

%% @doc Get store information and statistics.
-spec info() -> map().
info() ->
    gen_server:call(?SERVER, info).

%% @doc Get information about a specific namespace.
-spec info(atom()) -> map().
info(Namespace) ->
    gen_server:call(?SERVER, {info, Namespace}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init(Opts) ->
    process_flag(trap_exit, true),
    Backend = maps:get(backend, Opts, ets),
    DefaultTTL = maps:get(default_ttl, Opts, infinity),
    SqlitePath = maps:get(sqlite_db_path, Opts, "beamai_memory.db"),

    State0 = #state{
        backend = Backend,
        sqlite_ref = undefined,
        sqlite_path = SqlitePath,
        default_ttl = DefaultTTL,
        ttl_timer = undefined,
        stats = #{
            puts => 0,
            gets => 0,
            deletes => 0,
            hits => 0,
            misses => 0,
            expirations => 0,
            started_at => erlang:system_time(millisecond)
        }
    },

    State1 = case Backend of
        ets ->
            init_ets_backend(State0);
        sqlite ->
            init_sqlite_backend(State0)
    end,

    %% Start TTL cleanup timer
    TimerRef = erlang:send_after(?TTL_CHECK_INTERVAL, self(), check_ttl),

    logger:info("BeamAI Memory Store initialized (backend=~p)", [Backend]),
    {ok, State1#state{ttl_timer = TimerRef}}.

%% @private
handle_call({get, Namespace, Key, Opts}, _From, State) ->
    {Reply, NewState} = do_get(Namespace, Key, Opts, State),
    {reply, Reply, NewState};

handle_call({put, Namespace, Key, Value, Opts}, _From, State) ->
    {Reply, NewState} = do_put(Namespace, Key, Value, Opts, State),
    {reply, Reply, NewState};

handle_call({delete, Namespace, Key, _Opts}, _From, State) ->
    NewState = do_delete(Namespace, Key, State),
    {reply, ok, NewState};

handle_call({list, Namespace, Opts}, _From, State) ->
    Reply = do_list(Namespace, Opts, State),
    {reply, Reply, State};

handle_call({search, Namespace, Pattern, Opts}, _From, State) ->
    Reply = do_search(Namespace, Pattern, Opts, State),
    {reply, Reply, State};

handle_call({clear, Namespace}, _From, State) ->
    NewState = do_clear(Namespace, State),
    {reply, ok, NewState};

handle_call(clear_all, _From, State) ->
    NewState = do_clear_all(State),
    {reply, ok, NewState};

handle_call(info, _From, State) ->
    Reply = do_info(State),
    {reply, Reply, State};

handle_call({info, Namespace}, _From, State) ->
    Reply = do_info(Namespace, State),
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(check_ttl, State) ->
    NewState = do_check_ttl(State),
    TimerRef = erlang:send_after(?TTL_CHECK_INTERVAL, self(), check_ttl),
    {noreply, NewState#state{ttl_timer = TimerRef}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, State) ->
    case State#state.ttl_timer of
        undefined -> ok;
        Ref -> erlang:cancel_timer(Ref)
    end,
    case State#state.backend of
        sqlite ->
            close_sqlite(State);
        ets ->
            ok
    end,
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal: Backend Initialization
%%====================================================================

%% @private Initialize ETS tables for the ETS backend.
init_ets_backend(State) ->
    %% Clean up existing tables if they exist (safe restart)
    lists:foreach(fun(Table) ->
        case ets:info(Table) of
            undefined -> ok;
            _ -> ets:delete(Table)
        end
    end, [?DATA_TABLE, ?META_TABLE, ?TTL_TABLE]),

    %% Data table: {{Namespace, Key}, Value}
    _ = ets:new(?DATA_TABLE, [
        named_table,
        public,
        set,
        {keypos, 1},
        {write_concurrency, auto},
        {read_concurrency, true}
    ]),

    %% Metadata table: {{Namespace, Key}, MetadataMap}
    _ = ets:new(?META_TABLE, [
        named_table,
        public,
        set,
        {keypos, 1},
        {write_concurrency, auto},
        {read_concurrency, true}
    ]),

    %% TTL index table: {ExpiresAt, Namespace, Key} - ordered_set for efficient scans
    _ = ets:new(?TTL_TABLE, [
        named_table,
        public,
        ordered_set,
        {keypos, 1},
        {write_concurrency, auto}
    ]),

    State.

%% @private Initialize SQLite backend.
%% Uses an ETS table as a write-through cache with SQLite as the durable store.
init_sqlite_backend(State) ->
    %% Also create ETS tables as a cache layer
    State1 = init_ets_backend(State),

    %% Try to open/create the SQLite database
    Path = State#state.sqlite_path,
    case open_sqlite(Path) of
        {ok, Ref} ->
            create_sqlite_tables(Ref),
            load_sqlite_into_ets(Ref),
            State1#state{sqlite_ref = Ref};
        {error, Reason} ->
            logger:warning("BeamAI Memory Store: SQLite init failed (~p), falling back to ETS", [Reason]),
            State1#state{backend = ets}
    end.

%%====================================================================
%% Internal: Get Operations
%%====================================================================

%% @private
do_get(Namespace, Key, Opts, State) ->
    CompoundKey = {Namespace, Key},
    Stats = State#state.stats,
    Gets = maps:get(gets, Stats, 0),
    case ets:lookup(?DATA_TABLE, CompoundKey) of
        [{CompoundKey, Value}] ->
            %% Check if expired
            case is_expired(CompoundKey) of
                true ->
                    do_delete(Namespace, Key, State),
                    NewStats = Stats#{
                        gets => Gets + 1,
                        misses => maps:get(misses, Stats, 0) + 1,
                        expirations => maps:get(expirations, Stats, 0) + 1
                    },
                    {{error, expired}, State#state{stats = NewStats}};
                false ->
                    %% Update access metadata unless touch=false
                    Touch = proplists:get_value(touch, Opts, true),
                    case Touch of
                        true -> touch_metadata(CompoundKey);
                        false -> ok
                    end,
                    NewStats = Stats#{
                        gets => Gets + 1,
                        hits => maps:get(hits, Stats, 0) + 1
                    },
                    {{ok, Value}, State#state{stats = NewStats}}
            end;
        [] ->
            NewStats = Stats#{
                gets => Gets + 1,
                misses => maps:get(misses, Stats, 0) + 1
            },
            {{error, not_found}, State#state{stats = NewStats}}
    end.

%%====================================================================
%% Internal: Put Operations
%%====================================================================

%% @private
do_put(Namespace, Key, Value, Opts, State) ->
    CompoundKey = {Namespace, Key},
    Now = erlang:system_time(millisecond),
    Stats = State#state.stats,

    %% Determine TTL
    TTL = proplists:get_value(ttl, Opts, State#state.default_ttl),
    ExpiresAt = case TTL of
        infinity -> infinity;
        Ms when is_integer(Ms) -> Now + Ms
    end,

    %% Build or update metadata
    OldMeta = case ets:lookup(?META_TABLE, CompoundKey) of
        [{CompoundKey, M}] -> M;
        [] -> #{created_at => Now, access_count => 0}
    end,

    Metadata = OldMeta#{
        namespace => Namespace,
        updated_at => Now,
        expires_at => ExpiresAt,
        last_accessed => Now,
        access_count => maps:get(access_count, OldMeta, 0)
    },

    %% Write to ETS
    ets:insert(?DATA_TABLE, {CompoundKey, Value}),
    ets:insert(?META_TABLE, {CompoundKey, Metadata}),

    %% Update TTL index
    %% First remove any old TTL entry for this key
    remove_ttl_entry(CompoundKey),
    %% Add new TTL entry if not infinity
    case ExpiresAt of
        infinity -> ok;
        Exp -> ets:insert(?TTL_TABLE, {{Exp, Namespace, Key}})
    end,

    %% Write-through to SQLite if applicable
    case State#state.backend of
        sqlite -> sqlite_put(State#state.sqlite_ref, Namespace, Key, Value, Metadata);
        ets -> ok
    end,

    Puts = maps:get(puts, Stats, 0),
    NewStats = Stats#{puts => Puts + 1},
    {ok, State#state{stats = NewStats}}.

%%====================================================================
%% Internal: Delete Operations
%%====================================================================

%% @private
do_delete(Namespace, Key, State) ->
    CompoundKey = {Namespace, Key},
    Stats = State#state.stats,

    ets:delete(?DATA_TABLE, CompoundKey),
    ets:delete(?META_TABLE, CompoundKey),
    remove_ttl_entry(CompoundKey),

    %% Delete from SQLite if applicable
    case State#state.backend of
        sqlite -> sqlite_delete(State#state.sqlite_ref, Namespace, Key);
        ets -> ok
    end,

    Deletes = maps:get(deletes, Stats, 0),
    NewStats = Stats#{deletes => Deletes + 1},
    State#state{stats = NewStats}.

%%====================================================================
%% Internal: List Operations
%%====================================================================

%% @private
do_list(Namespace, Opts, _State) ->
    Limit = proplists:get_value(limit, Opts, 1000),
    Offset = proplists:get_value(offset, Opts, 0),

    %% Match all keys in the namespace
    Pattern = {{Namespace, '$1'}, '_'},
    AllKeys = [K || [K] <- ets:match(?DATA_TABLE, Pattern)],

    %% Apply pagination
    Sorted = lists:sort(AllKeys),
    Paged = case length(Sorted) > Offset of
        true -> lists:sublist(lists:nthtail(Offset, Sorted), Limit);
        false -> []
    end,

    {ok, Paged}.

%%====================================================================
%% Internal: Search Operations
%%====================================================================

%% @private
do_search(Namespace, Pattern, Opts, _State) ->
    Limit = proplists:get_value(limit, Opts, 100),
    IncludeMeta = proplists:get_value(include_metadata, Opts, false),

    %% Get all entries in namespace
    MatchPattern = {{Namespace, '$1'}, '$2'},
    Entries = ets:match(?DATA_TABLE, MatchPattern),

    %% Apply the search pattern
    Filtered = case Pattern of
        Fun when is_function(Fun, 1) ->
            lists:filter(fun([K, V]) -> Fun({K, V}) end, Entries);
        Fun when is_function(Fun, 2) ->
            lists:filter(fun([K, V]) -> Fun(K, V) end, Entries);
        #{} = MetaCriteria ->
            %% Search by metadata criteria
            lists:filter(fun([K, _V]) ->
                CompoundKey = {Namespace, K},
                case ets:lookup(?META_TABLE, CompoundKey) of
                    [{CompoundKey, Meta}] ->
                        matches_criteria(Meta, MetaCriteria);
                    [] ->
                        false
                end
            end, Entries);
        _ ->
            Entries
    end,

    %% Apply limit
    Limited = lists:sublist(Filtered, Limit),

    %% Format results
    Results = case IncludeMeta of
        true ->
            lists:map(fun([K, V]) ->
                CompoundKey = {Namespace, K},
                Meta = case ets:lookup(?META_TABLE, CompoundKey) of
                    [{CompoundKey, M}] -> M;
                    [] -> #{}
                end,
                {K, V, Meta}
            end, Limited);
        false ->
            [{K, V} || [K, V] <- Limited]
    end,

    {ok, Results}.

%%====================================================================
%% Internal: Clear Operations
%%====================================================================

%% @private
do_clear(Namespace, State) ->
    %% Find all keys in namespace and delete them
    DataPattern = {{Namespace, '_'}, '_'},
    ets:match_delete(?DATA_TABLE, DataPattern),

    MetaPattern = {{Namespace, '_'}, '_'},
    ets:match_delete(?META_TABLE, MetaPattern),

    %% Clean TTL entries for this namespace
    clean_ttl_for_namespace(Namespace),

    %% Clear from SQLite if applicable
    case State#state.backend of
        sqlite -> sqlite_clear_namespace(State#state.sqlite_ref, Namespace);
        ets -> ok
    end,

    State.

%% @private
do_clear_all(State) ->
    ets:delete_all_objects(?DATA_TABLE),
    ets:delete_all_objects(?META_TABLE),
    ets:delete_all_objects(?TTL_TABLE),

    case State#state.backend of
        sqlite -> sqlite_clear_all(State#state.sqlite_ref);
        ets -> ok
    end,

    State.

%%====================================================================
%% Internal: Info Operations
%%====================================================================

%% @private
do_info(State) ->
    #{
        backend => State#state.backend,
        default_ttl => State#state.default_ttl,
        total_entries => ets:info(?DATA_TABLE, size),
        memory_bytes => ets:info(?DATA_TABLE, memory) * erlang:system_info(wordsize),
        ttl_entries => ets:info(?TTL_TABLE, size),
        stats => State#state.stats
    }.

%% @private
do_info(Namespace, _State) ->
    %% Count entries in this namespace
    Pattern = {{Namespace, '_'}, '_'},
    Count = length(ets:match(?DATA_TABLE, Pattern)),
    #{
        namespace => Namespace,
        entry_count => Count
    }.

%%====================================================================
%% Internal: TTL Management
%%====================================================================

%% @private Check and expire entries past their TTL.
do_check_ttl(State) ->
    Now = erlang:system_time(millisecond),
    ExpiredKeys = collect_expired_keys(Now),

    lists:foreach(fun({Namespace, Key}) ->
        do_delete(Namespace, Key, State)
    end, ExpiredKeys),

    case length(ExpiredKeys) > 0 of
        true ->
            Stats = State#state.stats,
            Expirations = maps:get(expirations, Stats, 0),
            NewStats = Stats#{expirations => Expirations + length(ExpiredKeys)},
            State#state{stats = NewStats};
        false ->
            State
    end.

%% @private Collect all keys with TTL <= Now from the ordered_set.
collect_expired_keys(Now) ->
    collect_expired_keys(ets:first(?TTL_TABLE), Now, []).

collect_expired_keys('$end_of_table', _Now, Acc) ->
    lists:reverse(Acc);
collect_expired_keys({ExpiresAt, _Ns, _Key} = TTLKey, Now, Acc) when ExpiresAt =< Now ->
    {_, Namespace, Key} = TTLKey,
    ets:delete(?TTL_TABLE, TTLKey),
    Next = ets:next(?TTL_TABLE, TTLKey),
    collect_expired_keys(Next, Now, [{Namespace, Key} | Acc]);
collect_expired_keys(_, _Now, Acc) ->
    %% Remaining entries have not expired yet (ordered_set)
    lists:reverse(Acc).

%% @private Check if a compound key has expired.
is_expired(CompoundKey) ->
    case ets:lookup(?META_TABLE, CompoundKey) of
        [{CompoundKey, Meta}] ->
            case maps:get(expires_at, Meta, infinity) of
                infinity -> false;
                ExpiresAt -> erlang:system_time(millisecond) > ExpiresAt
            end;
        [] ->
            false
    end.

%% @private Update access timestamp and count for a key.
touch_metadata(CompoundKey) ->
    case ets:lookup(?META_TABLE, CompoundKey) of
        [{CompoundKey, Meta}] ->
            Now = erlang:system_time(millisecond),
            Count = maps:get(access_count, Meta, 0),
            NewMeta = Meta#{
                last_accessed => Now,
                access_count => Count + 1
            },
            ets:insert(?META_TABLE, {CompoundKey, NewMeta});
        [] ->
            ok
    end.

%% @private Remove old TTL entry for a key.
remove_ttl_entry({Namespace, Key}) ->
    %% Scan for existing TTL entry for this key
    %% Since we cannot do a reverse lookup easily on ordered_set,
    %% we check the metadata for the old expiry
    case ets:lookup(?META_TABLE, {Namespace, Key}) of
        [{{Namespace, Key}, Meta}] ->
            case maps:get(expires_at, Meta, infinity) of
                infinity -> ok;
                OldExpiry ->
                    ets:delete(?TTL_TABLE, {OldExpiry, Namespace, Key})
            end;
        [] ->
            ok
    end.

%% @private Clean TTL entries for a given namespace.
clean_ttl_for_namespace(Namespace) ->
    %% Walk the entire TTL table and remove entries for this namespace
    clean_ttl_ns(ets:first(?TTL_TABLE), Namespace).

clean_ttl_ns('$end_of_table', _Namespace) ->
    ok;
clean_ttl_ns({_Exp, Ns, _Key} = TTLKey, Namespace) ->
    Next = ets:next(?TTL_TABLE, TTLKey),
    case Ns of
        Namespace -> ets:delete(?TTL_TABLE, TTLKey);
        _ -> ok
    end,
    clean_ttl_ns(Next, Namespace).

%% @private Check if metadata matches search criteria.
matches_criteria(Meta, Criteria) ->
    maps:fold(fun(CritKey, CritVal, Acc) ->
        Acc andalso (maps:get(CritKey, Meta, undefined) =:= CritVal)
    end, true, Criteria).

%%====================================================================
%% Internal: SQLite Operations
%%====================================================================

%% @private Open a SQLite database.
open_sqlite(Path) ->
    try
        case esqlite3:open(Path) of
            {ok, Ref} -> {ok, Ref};
            {error, Reason} -> {error, Reason}
        end
    catch
        error:undef ->
            {error, esqlite_not_available};
        _:Reason ->
            {error, Reason}
    end.

%% @private Close the SQLite connection.
close_sqlite(State) ->
    case State#state.sqlite_ref of
        undefined -> ok;
        Ref ->
            try esqlite3:close(Ref)
            catch _:_ -> ok
            end
    end.

%% @private Create required SQLite tables.
create_sqlite_tables(Ref) ->
    try
        esqlite3:exec(Ref,
            "CREATE TABLE IF NOT EXISTS beamai_memory ("
            "  namespace TEXT NOT NULL,"
            "  key TEXT NOT NULL,"
            "  value BLOB NOT NULL,"
            "  metadata TEXT,"
            "  created_at INTEGER,"
            "  updated_at INTEGER,"
            "  expires_at INTEGER,"
            "  PRIMARY KEY (namespace, key)"
            ");"),
        esqlite3:exec(Ref,
            "CREATE INDEX IF NOT EXISTS idx_beamai_memory_ns "
            "ON beamai_memory(namespace);"),
        esqlite3:exec(Ref,
            "CREATE INDEX IF NOT EXISTS idx_beamai_memory_ttl "
            "ON beamai_memory(expires_at) WHERE expires_at IS NOT NULL;"),
        ok
    catch
        _:Reason ->
            logger:warning("BeamAI Memory Store: SQLite table creation failed: ~p", [Reason]),
            {error, Reason}
    end.

%% @private Load all SQLite data into ETS on startup.
load_sqlite_into_ets(Ref) ->
    try
        case esqlite3:q(Ref, "SELECT namespace, key, value, metadata FROM beamai_memory") of
            Rows when is_list(Rows) ->
                lists:foreach(fun({Ns, K, V, MetaJson}) ->
                    Namespace = binary_to_atom(Ns, utf8),
                    Key = binary_to_term(K),
                    Value = binary_to_term(V),
                    Meta = case MetaJson of
                        null -> #{};
                        _ ->
                            try binary_to_term(MetaJson)
                            catch _:_ -> #{}
                            end
                    end,
                    CompoundKey = {Namespace, Key},
                    ets:insert(?DATA_TABLE, {CompoundKey, Value}),
                    ets:insert(?META_TABLE, {CompoundKey, Meta}),
                    case maps:get(expires_at, Meta, infinity) of
                        infinity -> ok;
                        Exp -> ets:insert(?TTL_TABLE, {{Exp, Namespace, Key}})
                    end
                end, Rows),
                logger:info("BeamAI Memory Store: Loaded ~p entries from SQLite", [length(Rows)]);
            _ ->
                ok
        end
    catch
        _:Reason ->
            logger:warning("BeamAI Memory Store: Failed to load from SQLite: ~p", [Reason])
    end.

%% @private Write-through to SQLite.
sqlite_put(undefined, _Namespace, _Key, _Value, _Metadata) ->
    ok;
sqlite_put(Ref, Namespace, Key, Value, Metadata) ->
    try
        Now = erlang:system_time(millisecond),
        ExpiresAt = maps:get(expires_at, Metadata, infinity),
        ExpVal = case ExpiresAt of infinity -> null; V -> V end,
        esqlite3:exec(Ref,
            "INSERT OR REPLACE INTO beamai_memory "
            "(namespace, key, value, metadata, created_at, updated_at, expires_at) "
            "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            [atom_to_binary(Namespace, utf8),
             term_to_binary(Key),
             term_to_binary(Value),
             term_to_binary(Metadata),
             maps:get(created_at, Metadata, Now),
             Now,
             ExpVal]),
        ok
    catch
        _:Reason ->
            logger:warning("BeamAI Memory Store: SQLite write failed: ~p", [Reason]),
            ok
    end.

%% @private Delete from SQLite.
sqlite_delete(undefined, _Namespace, _Key) ->
    ok;
sqlite_delete(Ref, Namespace, Key) ->
    try
        esqlite3:exec(Ref,
            "DELETE FROM beamai_memory WHERE namespace = ?1 AND key = ?2",
            [atom_to_binary(Namespace, utf8), term_to_binary(Key)]),
        ok
    catch
        _:_ -> ok
    end.

%% @private Clear a namespace from SQLite.
sqlite_clear_namespace(undefined, _Namespace) ->
    ok;
sqlite_clear_namespace(Ref, Namespace) ->
    try
        esqlite3:exec(Ref,
            "DELETE FROM beamai_memory WHERE namespace = ?1",
            [atom_to_binary(Namespace, utf8)]),
        ok
    catch
        _:_ -> ok
    end.

%% @private Clear all data from SQLite.
sqlite_clear_all(undefined) ->
    ok;
sqlite_clear_all(Ref) ->
    try
        esqlite3:exec(Ref, "DELETE FROM beamai_memory"),
        ok
    catch
        _:_ -> ok
    end.
