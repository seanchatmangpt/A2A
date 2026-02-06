%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Mnesia Adapter
%%%
%%% Adapter module that exposes Mnesia tables through the BeamAI
%%% memory interface. This allows BeamAI components to interact with
%%% Mnesia-backed data using the same get/put/delete/transaction API
%%% as the beamai_memory_store, while preserving Mnesia's transaction
%%% semantics and disc persistence.
%%%
%%% The adapter manages a dedicated Mnesia table (beamai_mnesia_kv)
%%% that provides a generic key-value store backed by Mnesia disc
%%% copies. It also provides pass-through access to existing YAWL
%%% Mnesia tables.
%%%
%%% Table mapping:
%%%   - Namespace 'generic' -> beamai_mnesia_kv table
%%%   - Namespace 'workflows' -> yawl_workflow_persist table
%%%   - Namespace 'workitems' -> yawl_workitem_persist table
%%%   - Namespace 'resources' -> yawl_resource_persist table
%%%   - Namespace 'checkpoints' -> yawl_checkpoint table
%%%   - Namespace 'history' -> yawl_execution_history table
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_mnesia_adapter).

-behaviour(gen_server).

-include("yawl_schema.hrl").

%% API
-export([
    start_link/0,
    start_link/1,
    init_tables/0,
    get/2,
    put/3,
    put/4,
    delete/2,
    list_keys/1,
    transaction/1,
    clear/1,
    table_info/0,
    ensure_started/0
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
-define(KV_TABLE, beamai_mnesia_kv).

%% Generic key-value record for the beamai_mnesia_kv table
-record(beamai_mnesia_kv, {
    key        :: {atom(), term()},   %% {Namespace, Key}
    value      :: term(),
    metadata   :: map(),
    created_at :: integer(),
    updated_at :: integer()
}).

-record(state, {
    tables_ready :: boolean(),
    table_list   :: [atom()]
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the Mnesia adapter.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the Mnesia adapter with options.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%% @doc Initialize BeamAI-specific Mnesia tables.
%% Creates the beamai_mnesia_kv table if it does not already exist.
%% Does not modify existing YAWL tables.
-spec init_tables() -> ok | {error, term()}.
init_tables() ->
    gen_server:call(?SERVER, init_tables, 30000).

%% @doc Get a value by namespace and key from Mnesia.
-spec get(atom(), term()) -> {ok, term()} | {error, not_found | term()}.
get(Namespace, Key) ->
    gen_server:call(?SERVER, {get, Namespace, Key}).

%% @doc Put a value into Mnesia by namespace and key.
-spec put(atom(), term(), term()) -> ok | {error, term()}.
put(Namespace, Key, Value) ->
    put(Namespace, Key, Value, #{}).

%% @doc Put a value with metadata.
-spec put(atom(), term(), term(), map()) -> ok | {error, term()}.
put(Namespace, Key, Value, Metadata) ->
    gen_server:call(?SERVER, {put, Namespace, Key, Value, Metadata}).

%% @doc Delete a key from a namespace in Mnesia.
-spec delete(atom(), term()) -> ok | {error, term()}.
delete(Namespace, Key) ->
    gen_server:call(?SERVER, {delete, Namespace, Key}).

%% @doc List all keys in a namespace.
-spec list_keys(atom()) -> {ok, [term()]} | {error, term()}.
list_keys(Namespace) ->
    gen_server:call(?SERVER, {list_keys, Namespace}, 15000).

%% @doc Execute a function within a Mnesia transaction.
%% The function receives no arguments and should use mnesia operations
%% directly. Returns the transaction result.
-spec transaction(fun(() -> term())) -> {ok, term()} | {error, term()}.
transaction(Fun) ->
    gen_server:call(?SERVER, {transaction, Fun}, 30000).

%% @doc Clear all entries in a namespace.
-spec clear(atom()) -> ok | {error, term()}.
clear(Namespace) ->
    gen_server:call(?SERVER, {clear, Namespace}, 30000).

%% @doc Get information about all managed Mnesia tables.
-spec table_info() -> map().
table_info() ->
    gen_server:call(?SERVER, table_info).

%% @doc Ensure Mnesia is started and tables are available.
-spec ensure_started() -> ok | {error, term()}.
ensure_started() ->
    gen_server:call(?SERVER, ensure_started, 15000).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init(_Opts) ->
    %% Ensure Mnesia is running
    case mnesia:start() of
        ok -> ok;
        {error, {already_started, _}} -> ok
    end,

    State = #state{
        tables_ready = false,
        table_list = [
            ?KV_TABLE,
            yawl_workflow_persist,
            yawl_workitem_persist,
            yawl_resource_persist,
            yawl_checkpoint,
            yawl_execution_history
        ]
    },

    %% Try to initialize tables
    NewState = case do_init_tables() of
        ok ->
            logger:info("BeamAI Mnesia Adapter initialized, tables ready"),
            State#state{tables_ready = true};
        {error, Reason} ->
            logger:warning("BeamAI Mnesia Adapter: table init deferred: ~p", [Reason]),
            %% Schedule retry
            erlang:send_after(5000, self(), retry_init),
            State
    end,

    {ok, NewState}.

%% @private
handle_call(init_tables, _From, State) ->
    case do_init_tables() of
        ok ->
            {reply, ok, State#state{tables_ready = true}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({get, Namespace, Key}, _From, State) ->
    Reply = do_get(Namespace, Key),
    {reply, Reply, State};

handle_call({put, Namespace, Key, Value, Metadata}, _From, State) ->
    Reply = do_put(Namespace, Key, Value, Metadata),
    {reply, Reply, State};

handle_call({delete, Namespace, Key}, _From, State) ->
    Reply = do_delete(Namespace, Key),
    {reply, Reply, State};

handle_call({list_keys, Namespace}, _From, State) ->
    Reply = do_list_keys(Namespace),
    {reply, Reply, State};

handle_call({transaction, Fun}, _From, State) ->
    Reply = do_transaction(Fun),
    {reply, Reply, State};

handle_call({clear, Namespace}, _From, State) ->
    Reply = do_clear(Namespace),
    {reply, Reply, State};

handle_call(table_info, _From, State) ->
    Reply = do_table_info(State),
    {reply, Reply, State};

handle_call(ensure_started, _From, State) ->
    case State#state.tables_ready of
        true ->
            {reply, ok, State};
        false ->
            case do_init_tables() of
                ok ->
                    {reply, ok, State#state{tables_ready = true}};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(retry_init, State) ->
    case State#state.tables_ready of
        true ->
            {noreply, State};
        false ->
            case do_init_tables() of
                ok ->
                    logger:info("BeamAI Mnesia Adapter: tables initialized on retry"),
                    {noreply, State#state{tables_ready = true}};
                {error, _} ->
                    erlang:send_after(5000, self(), retry_init),
                    {noreply, State}
            end
    end;

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal: Table Initialization
%%====================================================================

%% @private Create the beamai_mnesia_kv table if it does not exist.
do_init_tables() ->
    try
        case mnesia:create_table(?KV_TABLE, [
            {attributes, record_info(fields, beamai_mnesia_kv)},
            {index, []},
            {type, set},
            {disc_copies, [node()]}
        ]) of
            {atomic, ok} ->
                ok;
            {aborted, {already_exists, ?KV_TABLE}} ->
                ok;
            {aborted, Reason} ->
                {error, Reason}
        end
    catch
        _:Error ->
            {error, Error}
    end.

%%====================================================================
%% Internal: Get Operations
%%====================================================================

%% @private Read from the appropriate table based on namespace.
do_get(generic, Key) ->
    do_kv_get(generic, Key);
do_get(workflows, Key) ->
    Trans = fun() ->
        case mnesia:read(yawl_workflow_persist, Key) of
            [Record] -> {ok, Record};
            [] -> {error, not_found}
        end
    end,
    run_transaction(Trans);
do_get(workitems, Key) ->
    Trans = fun() ->
        case mnesia:read(yawl_workitem_persist, Key) of
            [Record] -> {ok, Record};
            [] -> {error, not_found}
        end
    end,
    run_transaction(Trans);
do_get(resources, Key) ->
    Trans = fun() ->
        case mnesia:read(yawl_resource_persist, Key) of
            [Record] -> {ok, Record};
            [] -> {error, not_found}
        end
    end,
    run_transaction(Trans);
do_get(checkpoints, Key) ->
    Trans = fun() ->
        case mnesia:read(yawl_checkpoint, Key) of
            [Record] -> {ok, Record};
            [] -> {error, not_found}
        end
    end,
    run_transaction(Trans);
do_get(history, Key) ->
    Trans = fun() ->
        case mnesia:read(yawl_execution_history, Key) of
            Records when is_list(Records), length(Records) > 0 ->
                {ok, Records};
            [] ->
                {error, not_found}
        end
    end,
    run_transaction(Trans);
do_get(Namespace, Key) ->
    %% Default: use the KV table with compound key
    do_kv_get(Namespace, Key).

%% @private Get from the generic KV table.
do_kv_get(Namespace, Key) ->
    CompoundKey = {Namespace, Key},
    Trans = fun() ->
        case mnesia:read(?KV_TABLE, CompoundKey) of
            [#beamai_mnesia_kv{value = Value}] -> {ok, Value};
            [] -> {error, not_found}
        end
    end,
    run_transaction(Trans).

%%====================================================================
%% Internal: Put Operations
%%====================================================================

%% @private Write to the appropriate table based on namespace.
do_put(generic, Key, Value, Metadata) ->
    do_kv_put(generic, Key, Value, Metadata);
do_put(workflows, _Key, Value, _Metadata) when is_record(Value, yawl_workflow_persist) ->
    Trans = fun() -> mnesia:write(Value) end,
    case run_transaction(Trans) of
        {ok, ok} -> ok;
        {error, Reason} -> {error, Reason}
    end;
do_put(workitems, _Key, Value, _Metadata) when is_record(Value, yawl_workitem_persist) ->
    Trans = fun() -> mnesia:write(Value) end,
    case run_transaction(Trans) of
        {ok, ok} -> ok;
        {error, Reason} -> {error, Reason}
    end;
do_put(resources, _Key, Value, _Metadata) when is_record(Value, yawl_resource_persist) ->
    Trans = fun() -> mnesia:write(Value) end,
    case run_transaction(Trans) of
        {ok, ok} -> ok;
        {error, Reason} -> {error, Reason}
    end;
do_put(checkpoints, _Key, Value, _Metadata) when is_record(Value, yawl_checkpoint) ->
    Trans = fun() -> mnesia:write(Value) end,
    case run_transaction(Trans) of
        {ok, ok} -> ok;
        {error, Reason} -> {error, Reason}
    end;
do_put(Namespace, Key, Value, Metadata) ->
    %% Default: store in the generic KV table
    do_kv_put(Namespace, Key, Value, Metadata).

%% @private Put into the generic KV table.
do_kv_put(Namespace, Key, Value, Metadata) ->
    CompoundKey = {Namespace, Key},
    Now = erlang:system_time(millisecond),

    %% Preserve created_at from existing record if available
    CreatedAt = case do_kv_get(Namespace, Key) of
        {ok, _} ->
            Trans = fun() ->
                case mnesia:read(?KV_TABLE, CompoundKey) of
                    [#beamai_mnesia_kv{created_at = CA}] -> CA;
                    [] -> Now
                end
            end,
            case run_transaction(Trans) of
                {ok, CA} -> CA;
                _ -> Now
            end;
        _ ->
            Now
    end,

    Record = #beamai_mnesia_kv{
        key = CompoundKey,
        value = Value,
        metadata = Metadata,
        created_at = CreatedAt,
        updated_at = Now
    },

    WriteTrans = fun() -> mnesia:write(Record) end,
    case run_transaction(WriteTrans) of
        {ok, ok} -> ok;
        {error, Reason} -> {error, Reason}
    end.

%%====================================================================
%% Internal: Delete Operations
%%====================================================================

%% @private Delete from the appropriate table.
do_delete(generic, Key) ->
    do_kv_delete(generic, Key);
do_delete(workflows, Key) ->
    Trans = fun() -> mnesia:delete({yawl_workflow_persist, Key}) end,
    case run_transaction(Trans) of
        {ok, ok} -> ok;
        {error, Reason} -> {error, Reason}
    end;
do_delete(workitems, Key) ->
    Trans = fun() -> mnesia:delete({yawl_workitem_persist, Key}) end,
    case run_transaction(Trans) of
        {ok, ok} -> ok;
        {error, Reason} -> {error, Reason}
    end;
do_delete(resources, Key) ->
    Trans = fun() -> mnesia:delete({yawl_resource_persist, Key}) end,
    case run_transaction(Trans) of
        {ok, ok} -> ok;
        {error, Reason} -> {error, Reason}
    end;
do_delete(checkpoints, Key) ->
    Trans = fun() -> mnesia:delete({yawl_checkpoint, Key}) end,
    case run_transaction(Trans) of
        {ok, ok} -> ok;
        {error, Reason} -> {error, Reason}
    end;
do_delete(Namespace, Key) ->
    do_kv_delete(Namespace, Key).

%% @private Delete from the generic KV table.
do_kv_delete(Namespace, Key) ->
    CompoundKey = {Namespace, Key},
    Trans = fun() -> mnesia:delete({?KV_TABLE, CompoundKey}) end,
    case run_transaction(Trans) of
        {ok, ok} -> ok;
        {error, Reason} -> {error, Reason}
    end.

%%====================================================================
%% Internal: List and Clear Operations
%%====================================================================

%% @private List keys in a namespace.
do_list_keys(generic) ->
    do_kv_list_keys(generic);
do_list_keys(workflows) ->
    Trans = fun() ->
        mnesia:all_keys(yawl_workflow_persist)
    end,
    run_transaction(Trans);
do_list_keys(workitems) ->
    Trans = fun() ->
        mnesia:all_keys(yawl_workitem_persist)
    end,
    run_transaction(Trans);
do_list_keys(resources) ->
    Trans = fun() ->
        mnesia:all_keys(yawl_resource_persist)
    end,
    run_transaction(Trans);
do_list_keys(checkpoints) ->
    Trans = fun() ->
        mnesia:all_keys(yawl_checkpoint)
    end,
    run_transaction(Trans);
do_list_keys(Namespace) ->
    do_kv_list_keys(Namespace).

%% @private List keys from the generic KV table for a namespace.
do_kv_list_keys(Namespace) ->
    Trans = fun() ->
        AllKeys = mnesia:all_keys(?KV_TABLE),
        [K || {Ns, K} <- AllKeys, Ns =:= Namespace]
    end,
    run_transaction(Trans).

%% @private Clear all entries in a namespace.
do_clear(generic) ->
    do_kv_clear(generic);
do_clear(workflows) ->
    Trans = fun() ->
        Keys = mnesia:all_keys(yawl_workflow_persist),
        lists:foreach(fun(K) ->
            mnesia:delete({yawl_workflow_persist, K})
        end, Keys),
        ok
    end,
    case run_transaction(Trans) of
        {ok, ok} -> ok;
        {error, Reason} -> {error, Reason}
    end;
do_clear(Namespace) ->
    do_kv_clear(Namespace).

%% @private Clear entries from the generic KV table for a namespace.
do_kv_clear(Namespace) ->
    Trans = fun() ->
        AllKeys = mnesia:all_keys(?KV_TABLE),
        NsKeys = [{Namespace, K} || {Ns, K} <- AllKeys, Ns =:= Namespace],
        lists:foreach(fun(CK) ->
            mnesia:delete({?KV_TABLE, CK})
        end, NsKeys),
        ok
    end,
    case run_transaction(Trans) of
        {ok, ok} -> ok;
        {error, Reason} -> {error, Reason}
    end.

%%====================================================================
%% Internal: Transaction and Table Info
%%====================================================================

%% @private Execute a function in a Mnesia transaction.
do_transaction(Fun) ->
    run_transaction(Fun).

%% @private Run a function in a Mnesia transaction and unwrap the result.
run_transaction(Fun) ->
    case mnesia:transaction(Fun) of
        {atomic, Result} -> {ok, Result};
        {aborted, Reason} -> {error, Reason}
    end.

%% @private Get table info.
do_table_info(State) ->
    TableInfo = lists:foldl(fun(Table, Acc) ->
        Info = try
            #{
                size => mnesia:table_info(Table, size),
                memory_words => mnesia:table_info(Table, memory),
                type => mnesia:table_info(Table, type),
                storage_type => mnesia:table_info(Table, storage_type),
                status => ready
            }
        catch
            _:_ -> #{status => unavailable}
        end,
        maps:put(Table, Info, Acc)
    end, #{}, State#state.table_list),

    #{
        tables_ready => State#state.tables_ready,
        tables => TableInfo
    }.
