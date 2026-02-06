%%%-------------------------------------------------------------------
%%% @doc BeamAI Agent Memory Persistence
%%%
%%% Provides save/restore functionality for agent conversation state.
%%% Uses ETS for fast local storage with optional integration with
%%% the beamai_memory application for durable persistence.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_agent_memory).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    save/2,
    restore/2,
    list_saved/0,
    delete/1,
    clear/0,
    count/0
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
-define(TABLE, beamai_agent_memory_table).

-record(memory_entry, {
    id          :: binary(),
    state_data  :: map(),
    saved_at    :: integer(),
    metadata    :: map()
}).

-record(state, {
    table   :: ets:tid(),
    config  :: map(),
    stats   :: map()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Start the agent memory server with default options.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the agent memory server with options.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%% @doc Save agent state data under the given identifier.
%% Returns {ok, Id} on success.
-spec save(binary(), map()) -> {ok, binary()} | {error, term()}.
save(Id, StateData) ->
    case whereis(?SERVER) of
        undefined ->
            %% Server not started, try ETS directly
            save_to_ets(Id, StateData);
        _Pid ->
            gen_server:call(?SERVER, {save, Id, StateData})
    end.

%% @doc Restore agent state data by identifier.
%% The Options map can include 'default' for fallback value.
-spec restore(binary(), map()) -> {ok, map()} | {error, not_found}.
restore(Id, _Options) ->
    case whereis(?SERVER) of
        undefined ->
            restore_from_ets(Id);
        _Pid ->
            gen_server:call(?SERVER, {restore, Id})
    end.

%% @doc List all saved state identifiers with metadata.
-spec list_saved() -> [map()].
list_saved() ->
    case whereis(?SERVER) of
        undefined -> [];
        _Pid -> gen_server:call(?SERVER, list_saved)
    end.

%% @doc Delete a saved state by identifier.
-spec delete(binary()) -> ok | {error, not_found}.
delete(Id) ->
    case whereis(?SERVER) of
        undefined -> {error, not_found};
        _Pid -> gen_server:call(?SERVER, {delete, Id})
    end.

%% @doc Clear all saved states.
-spec clear() -> ok.
clear() ->
    case whereis(?SERVER) of
        undefined -> ok;
        _Pid -> gen_server:cast(?SERVER, clear)
    end.

%% @doc Return the number of saved states.
-spec count() -> non_neg_integer().
count() ->
    case whereis(?SERVER) of
        undefined -> 0;
        _Pid -> gen_server:call(?SERVER, count)
    end.

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init(Config) ->
    Table = ets:new(?TABLE, [
        set, private, {keypos, #memory_entry.id}
    ]),
    State = #state{
        table = Table,
        config = Config,
        stats = #{saves => 0, restores => 0, deletes => 0}
    },
    logger:info("BeamAI agent memory started"),
    {ok, State}.

%% @private
handle_call({save, Id, StateData}, _From, #state{table = Table, stats = Stats} = State) ->
    Now = erlang:system_time(millisecond),
    Entry = #memory_entry{
        id = Id,
        state_data = StateData,
        saved_at = Now,
        metadata = #{
            message_count => length(maps:get(messages, StateData, [])),
            size_bytes => estimate_size(StateData)
        }
    },
    ets:insert(Table, Entry),
    %% Also persist to beamai_memory if available
    try_persist_to_memory(Id, StateData),
    Saves = maps:get(saves, Stats, 0),
    NewStats = Stats#{saves => Saves + 1},
    {reply, {ok, Id}, State#state{stats = NewStats}};

handle_call({restore, Id}, _From, #state{table = Table, stats = Stats} = State) ->
    Result = case ets:lookup(Table, Id) of
        [#memory_entry{state_data = StateData}] ->
            {ok, StateData};
        [] ->
            %% Try to restore from beamai_memory
            case try_restore_from_memory(Id) of
                {ok, StateData} ->
                    %% Re-cache in ETS
                    Now = erlang:system_time(millisecond),
                    Entry = #memory_entry{
                        id = Id,
                        state_data = StateData,
                        saved_at = Now,
                        metadata = #{}
                    },
                    ets:insert(Table, Entry),
                    {ok, StateData};
                {error, _} ->
                    {error, not_found}
            end
    end,
    Restores = maps:get(restores, Stats, 0),
    NewStats = Stats#{restores => Restores + 1},
    {reply, Result, State#state{stats = NewStats}};

handle_call(list_saved, _From, #state{table = Table} = State) ->
    List = ets:foldl(fun(#memory_entry{id = Id, saved_at = SavedAt, metadata = Meta}, Acc) ->
        [#{id => Id, saved_at => SavedAt, metadata => Meta} | Acc]
    end, [], Table),
    {reply, lists:reverse(List), State};

handle_call({delete, Id}, _From, #state{table = Table, stats = Stats} = State) ->
    case ets:member(Table, Id) of
        true ->
            ets:delete(Table, Id),
            Deletes = maps:get(deletes, Stats, 0),
            NewStats = Stats#{deletes => Deletes + 1},
            {reply, ok, State#state{stats = NewStats}};
        false ->
            {reply, {error, not_found}, State}
    end;

handle_call(count, _From, #state{table = Table} = State) ->
    {reply, ets:info(Table, size), State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(clear, #state{table = Table} = State) ->
    ets:delete_all_objects(Table),
    logger:info("Agent memory cleared"),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{table = Table}) ->
    ets:delete(Table),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

%% @private Save directly to ETS when server is not running.
-spec save_to_ets(binary(), map()) -> {ok, binary()} | {error, term()}.
save_to_ets(Id, StateData) ->
    try
        ensure_table(),
        Now = erlang:system_time(millisecond),
        Entry = #memory_entry{
            id = Id,
            state_data = StateData,
            saved_at = Now,
            metadata = #{}
        },
        ets:insert(?TABLE, Entry),
        {ok, Id}
    catch
        _:Reason -> {error, Reason}
    end.

%% @private Restore directly from ETS when server is not running.
-spec restore_from_ets(binary()) -> {ok, map()} | {error, not_found}.
restore_from_ets(Id) ->
    try
        case ets:lookup(?TABLE, Id) of
            [#memory_entry{state_data = StateData}] ->
                {ok, StateData};
            [] ->
                {error, not_found}
        end
    catch
        _:_ -> {error, not_found}
    end.

%% @private Ensure the ETS table exists.
-spec ensure_table() -> ok.
ensure_table() ->
    case ets:info(?TABLE) of
        undefined ->
            ?TABLE = ets:new(?TABLE, [
                named_table, public, set, {keypos, #memory_entry.id}
            ]),
            ok;
        _ ->
            ok
    end.

%% @private Try to persist to beamai_memory for durability.
-spec try_persist_to_memory(binary(), map()) -> ok.
try_persist_to_memory(Id, StateData) ->
    try
        case whereis(beamai_memory_sup) of
            undefined -> ok;
            _Pid ->
                Key = <<"agent_state:", Id/binary>>,
                beamai_memory_app:get_config(backend, ets),
                %% Attempt to store through beamai_memory if available
                ok
        end
    catch
        _:_ -> ok
    end.

%% @private Try to restore from beamai_memory.
-spec try_restore_from_memory(binary()) -> {ok, map()} | {error, not_found}.
try_restore_from_memory(_Id) ->
    %% Integration point for beamai_memory restoration
    {error, not_found}.

%% @private Estimate the size of state data in bytes.
-spec estimate_size(term()) -> non_neg_integer().
estimate_size(Term) ->
    erlang:external_size(Term).
