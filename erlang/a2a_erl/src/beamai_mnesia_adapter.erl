%%%-------------------------------------------------------------------
%%% @doc Mnesia Adapter: wraps Mnesia operations in a beamai_memory-
%%% compatible key/value interface.
%%%
%%% Provides get/2, put/3, delete/2 over a dedicated Mnesia table,
%%% plus transaction/1 for atomic multi-operation batches.
%%% init_tables/0 creates the table if it does not exist.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_mnesia_adapter).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, init_tables/0, get/2, put/3, delete/2,
         transaction/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(beamai_kv, {
    key   :: binary(),
    value :: term(),
    ts    :: integer()
}).

-record(state, {
    table :: atom()
}).

-define(TABLE, beamai_kv).

%%====================================================================
%% API
%%====================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec init_tables() -> ok | {error, term()}.
init_tables() ->
    gen_server:call(?MODULE, init_tables).

-spec get(binary(), binary()) -> {ok, term()} | {error, not_found}.
get(Namespace, Key) ->
    gen_server:call(?MODULE, {get, composite_key(Namespace, Key)}).

-spec put(binary(), binary(), term()) -> ok | {error, term()}.
put(Namespace, Key, Value) ->
    gen_server:call(?MODULE, {put, composite_key(Namespace, Key), Value}).

-spec delete(binary(), binary()) -> ok | {error, term()}.
delete(Namespace, Key) ->
    gen_server:call(?MODULE, {delete, composite_key(Namespace, Key)}).

-spec transaction(fun(() -> term())) -> {ok, term()} | {error, term()}.
transaction(Fun) ->
    gen_server:call(?MODULE, {transaction, Fun}, ?DEFAULT_TIMEOUT).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    ?LOG_INFO("beamai_mnesia_adapter started"),
    {ok, #state{table = ?TABLE}}.

handle_call(init_tables, _From, State) ->
    Reply = do_init_tables(),
    {reply, Reply, State};

handle_call({get, CKey}, _From, State) ->
    Reply = do_get(CKey),
    {reply, Reply, State};

handle_call({put, CKey, Value}, _From, State) ->
    Reply = do_put(CKey, Value),
    {reply, Reply, State};

handle_call({delete, CKey}, _From, State) ->
    Reply = do_delete(CKey),
    {reply, Reply, State};

handle_call({transaction, Fun}, _From, State) ->
    Reply = case mnesia:transaction(Fun) of
        {atomic, Result}  -> {ok, Result};
        {aborted, Reason} -> {error, Reason}
    end,
    {reply, Reply, State};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal
%%====================================================================

composite_key(Namespace, Key) ->
    <<Namespace/binary, ":", Key/binary>>.

do_init_tables() ->
    case mnesia:create_table(?TABLE, [
        {attributes, record_info(fields, beamai_kv)},
        {type, set},
        {disc_copies, [node()]}
    ]) of
        {atomic, ok}                       -> ok;
        {aborted, {already_exists, ?TABLE}} -> ok;
        {aborted, Reason}                  -> {error, Reason}
    end.

do_get(CKey) ->
    case mnesia:transaction(fun() -> mnesia:read(?TABLE, CKey) end) of
        {atomic, [#beamai_kv{value = Val}]} -> {ok, Val};
        {atomic, []}                        -> {error, not_found};
        {aborted, Reason}                   -> {error, Reason}
    end.

do_put(CKey, Value) ->
    Record = #beamai_kv{
        key   = CKey,
        value = Value,
        ts    = erlang:system_time(millisecond)
    },
    case mnesia:transaction(fun() -> mnesia:write(Record) end) of
        {atomic, ok}      -> ok;
        {aborted, Reason} -> {error, Reason}
    end.

do_delete(CKey) ->
    case mnesia:transaction(fun() -> mnesia:delete({?TABLE, CKey}) end) of
        {atomic, ok}      -> ok;
        {aborted, Reason} -> {error, Reason}
    end.
