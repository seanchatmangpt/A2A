%%% @doc Cache Manager
%%% Multi-level caching system with LRU eviction and TTL support

-module(cache_manager).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([get/3, put/4, delete/3, clear/1, stats/1]).
-export[configure_cache/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_CACHE_SIZE, 10000).
-define(DEFAULT_CACHE_TTL, 300000). % 5 minutes
-define(DEFAULT_LRU_THRESHOLD, 0.1). % 10% free space for LRU
-define(CLEANUP_INTERVAL, 60000). % 1 minute

%% Cache entry with metadata
-record(cache_entry, {
    key :: term(),
    value :: term(),
    created :: integer(),
    accessed :: integer(),
    hits :: integer(),
    size :: integer()
}).

%% Cache configuration
-record(cache_config, {
    name :: binary(),
    max_size :: integer(),
    ttl :: integer(),
    eviction_policy :: lru | lfu | ttl,
    memory_limit :: integer() % bytes
}).

%% Cache state
-record(state, {
    caches :: map(), #{binary() => {#cache_config{}, list(#cache_entry{}), map()}}
}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

%% @doc Get value from cache
-spec get(binary(), term(), term()) -> {ok, term()} | {error, not_found}.
get(CacheName, Key, Default) ->
    case gen_server:call(?SERVER, {get, CacheName, Key}) of
        {ok, Value} ->
            {ok, Value};
        {error, not_found} ->
            case Default of
                {ok, DefaultValue} -> {ok, DefaultValue};
                _ -> {error, not_found}
            end
    end.

%% @doc Put value in cache
-spec put(binary(), term(), term(), integer()) -> ok.
put(CacheName, Key, Value, Ttl) ->
    gen_server:call(?SERVER, {put, CacheName, Key, Value, Ttl}).

%% @doc Delete value from cache
-spec delete(binary(), term(), term()) -> ok.
delete(CacheName, Key, Default) ->
    gen_server:call(?SERVER, {delete, CacheName, Key, Default}).

%% @doc Clear entire cache
-spec clear(binary()) -> ok.
clear(CacheName) ->
    gen_server:call(?SERVER, {clear, CacheName}).

%% @doc Get cache statistics
-spec stats(binary()) -> map().
stats(CacheName) ->
    gen_server:call(?SERVER, {stats, CacheName}).

%% @doc Configure cache parameters
-spec configure_cache(binary(), map()) -> ok.
configure_cache(CacheName, Config) ->
    gen_server:call(?SERVER, {configure_cache, CacheName, Config}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    State = #state{
        caches = #{
            <<"api_cache">> => {create_cache_config(<<"api_cache">>, 5000, ?DEFAULT_CACHE_TTL, lru, 1000000000), [], #{}},
            <<"mcp_cache">> => {create_cache_config(<<"mcp_cache">>, 10000, ?DEFAULT_CACHE_TTL, lfu, 500000000), [], #{}},
            <<"session_cache">> => {create_cache_config(<<"session_cache">>, 1000, 3600000, lru, 100000000), [], #{}}
        }
    },

    %% Start cleanup timer
    CleanupTimer = erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup_caches),

    io:format("Cache Manager initialized with ~p caches~n", [maps:size(State#state.caches)]),
    {ok, State#state{caches = maps:map(fun(_K, {Config, Entries, Stats}) ->
        {Config, Entries, Stats#{cleanup_timer => CleanupTimer}} end, State#state.caches)}};

handle_call({get, CacheName, Key}, _From, State) ->
    case maps:get(CacheName, State#state.caches, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        {Config, Entries, Stats} ->
            case find_entry(Entries, Key) of
                {ok, Entry} ->
                    UpdatedEntry = update_access(Entry),
                    UpdatedEntries = replace_entry(Entries, Entry, UpdatedEntry),
                    UpdatedStats = Stats#{
                        hits => Stats.hits + 1,
                        total_hits => maps:get(total_hits, Stats, 0) + 1
                    },

                    self() ! {update_cache_entry, CacheName, UpdatedEntry},
                    {reply, {ok, UpdatedEntry#cache_entry.value}, State#state{caches = maps:put(CacheName, {Config, UpdatedEntries, UpdatedStats}, State#state.caches)}};
                {error, not_found} ->
                    UpdatedStats = Stats#{
                        misses => Stats.misses + 1,
                        total_misses => maps:get(total_misses, Stats, 0) + 1
                    },
                    {reply, {error, not_found}, State#state{caches = maps:put(CacheName, {Config, Entries, UpdatedStats}, State#state.caches)}}
            end
    end;

handle_call({put, CacheName, Key, Value, Ttl}, _From, State) ->
    case maps:get(CacheName, State#state.caches, undefined) of
        undefined ->
            {reply, {error, cache_not_found}, State};
        {Config, Entries, Stats} ->
            Size = calculate_size(Value),
            Entry = #cache_entry{
                key = Key,
                value = Value,
                created = os:system_time(millisecond),
                accessed = os:system_time(millisecond),
                hits = 0,
                size = Size
            },

            %% Evict if necessary
            {UpdatedEntries, UpdatedStats} = evict_if_needed(Config, Entries, Stats, Size),

            %% Add new entry
            NewEntries = [Entry | UpdatedEntries],
            NewStats = UpdatedStats#{
                total_entries => length(NewEntries),
                total_memory => maps:get(total_memory, UpdatedStats, 0) + Size
            },

            io:format("Cached ~p bytes in ~p~n", [Size, CacheName]),
            {reply, ok, State#state{caches = maps:put(CacheName, {Config, NewEntries, NewStats}, State#state.caches)}}
    end;

handle_call({delete, CacheName, Key, Default}, _From, State) ->
    case maps:get(CacheName, State#state.caches, undefined) of
        undefined ->
            case Default of
                {ok, Value} -> {reply, {ok, Value}, State};
                _ -> {reply, {error, not_found}, State}
            end;
        {Config, Entries, Stats} ->
            case lists:keyfind(Key, #cache_entry.key, Entries) of
                false ->
                    case Default of
                        {ok, Value} -> {reply, {ok, Value}, State};
                        _ -> {reply, {error, not_found}, State}
                    end;
                Entry ->
                    RemovedEntries = lists:keydelete(Key, #cache_entry.key, Entries),
                    RemovedStats = Stats#{
                        total_entries => length(RemovedEntries),
                        total_memory => maps:get(total_memory, Stats, 0) - Entry#cache_entry.size
                    },

                    {reply, {ok, Entry#cache_entry.value}, State#state{caches = maps:put(CacheName, {Config, RemovedEntries, RemovedStats}, State#state.caches)}}
            end
    end;

handle_call({clear, CacheName}, _From, State) ->
    case maps:get(CacheName, State#state.caches, undefined) of
        undefined ->
            {reply, {error, cache_not_found}, State};
        {Config, _Entries, Stats} ->
            NewStats = Stats#{
                total_entries => 0,
                total_memory => 0,
                hits => 0,
                misses => 0
            },

            io:format("Cache ~s cleared~n", [CacheName]),
            {reply, ok, State#state{caches = maps:put(CacheName, {Config, [], NewStats}, State#state.caches)}}
    end;

handle_call({stats, CacheName}, _From, State) ->
    case maps:get(CacheName, State#state.caches, undefined) of
        undefined ->
            {reply, {error, cache_not_found}, State};
        {Config, Entries, Stats} ->
            CacheStats = #{
                config => format_config(Config),
                entries => length(Entries),
                hits => maps:get(hits, Stats, 0),
                misses => maps:get(misses, Stats, 0),
                total_hits => maps:get(total_hits, Stats, 0),
                total_misses => maps:get(total_misses, Stats, 0),
                total_memory => maps:get(total_memory, Stats, 0),
                average_hit_ratio => calculate_hit_ratio(Stats),
                oldest_entry => get_oldest_entry(Entries),
                newest_entry => get_newest_entry(Entries)
            },

            {reply, CacheStats, State}
    end;

handle_call({configure_cache, CacheName, Config}, _From, State) ->
    case maps:get(CacheName, State#state.caches, undefined) of
        undefined ->
            {reply, {error, cache_not_found}, State};
        {Config1, Entries, Stats} ->
            UpdatedConfig = update_config(Config1, Config),

            io:format("Cache ~s reconfigured: ~p~n", [CacheName, Config]),

            {reply, ok, State#state{caches = maps:put(CacheName, {UpdatedConfig, Entries, Stats}, State#state.caches)}}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(cleanup_caches, State) ->
    Now = os:system_time(millisecond),

    UpdatedCaches = maps:map(fun(CacheName, {Config, Entries, Stats}) ->
        {Config, CleanedEntries, CleanedStats} = cleanup_expired_entries(Config, Entries, Stats, Now),

        %% Schedule next cleanup
        CleanupTimer = erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup_caches),

        {Config, CleanedEntries, CleanedStats#{cleanup_timer => CleanupTimer}}
    end, State#state.caches),

    io:format("Cache cleanup completed~n"),
    {noreply, State#state{caches = UpdatedCaches}};

handle_info({update_cache_entry, CacheName, Entry}, State) ->
    case maps:get(CacheName, State#state.caches, undefined) of
        undefined ->
            {noreply, State};
        {Config, Entries, Stats} ->
            %% Update entry in cache
            UpdatedEntries = replace_entry(Entries, find_entry(Entries, Entry#cache_entry.key), Entry),
            {noreply, State#state{caches = maps:put(CacheName, {Config, UpdatedEntries, Stats}, State#state.caches)}}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

create_cache_config(Name, MaxSize, Ttl, EvictionPolicy, MemoryLimit) ->
    #cache_config{
        name = Name,
        max_size = MaxSize,
        ttl = Ttl,
        eviction_policy = EvictionPolicy,
        memory_limit = MemoryLimit
    }.

find_entry([], _Key) ->
    {error, not_found};

find_entry([Entry | Rest], Key) ->
    case Entry#cache_entry.key =:= Key of
        true ->
            {ok, Entry};
        false ->
            find_entry(Rest, Key)
    end.

update_access(Entry) ->
    Entry#cache_entry{
        accessed = os:system_time(millisecond),
        hits = Entry#cache_entry.hits + 1
    }.

replace_entry(Entries, {ok, OldEntry}, NewEntry) ->
    lists:map(fun(E) ->
        if
            E#cache_entry.key =:= OldEntry#cache_entry.key ->
                NewEntry;
            true ->
                E
        end
    end, Entries).

evict_if_needed(Config, Entries, Stats, NewSize) ->
    CurrentSize = length(Entries),
    CurrentMemory = maps:get(total_memory, Stats, 0) + NewSize,
    MaxSize = Config#cache_config.max_size;
    MemoryLimit = Config#cache_config.memory_limit;

    case CurrentSize >= MaxSize orelse CurrentMemory >= MemoryLimit of
        true ->
            %% Evict entries based on policy
            Evicted = case Config#cache_config.eviction_policy of
                lru -> evict_lru(Entries, 1);
                lfu -> evict_lfu(Entries, 1);
                ttl -> evict_ttl(Entries, 1)
            end,

            RemovedMemory = lists:sum([E#cache_entry.size || E <- Evicted]),
            UpdatedEntries = Entries -- Evicted,
            UpdatedStats = Stats#{
                total_entries => length(UpdatedEntries),
                total_memory => CurrentMemory - RemovedMemory,
                evictions => maps:get(evictions, Stats, 0) + length(Evicted)
            },

            io:format("Evicted ~p entries (~p bytes) from cache~n", [length(Evicted), RemovedMemory]),
            {UpdatedEntries, UpdatedStats};
        false ->
            {Entries, Stats}
    end.

evict_lru(Entries, Count) ->
    %% Sort by access time and evict oldest
    Sorted = lists:keysort(#cache_entry.accessed, Entries),
    lists:nthtail(length(Entries) - Count, Sorted).

evict_lfu(Entries, Count) ->
    %% Sort by hits and evict least frequently used
    Sorted = lists:keysort(#cache_entry.hits, Entries),
    lists:nthtail(length(Entries) - Count, Sorted).

evict_ttl(Entries, Count) ->
    Now = os:system_time(millisecond),
    Expired = lists:filter(fun(E) ->
        (Now - E#cache_entry.created) > 3600000 % 1 hour
    end, Entries),
    lists:sublist(Expired, Count).

cleanup_expired_entries(Config, Entries, Stats, Now) ->
    Ttl = Config#cache_config.ttl,

    case Ttl > 0 of
        true ->
            ValidEntries = lists:filter(fun(E) ->
                (Now - E#cache_entry.created) < Ttl
            end, Entries),

            RemovedCount = length(Entries) - length(ValidEntries),
            RemovedMemory = lists:foldl(fun(E, Acc) -> Acc - E#cache_entry.size end, 0, Entries -- ValidEntries),

            UpdatedStats = Stats#{
                total_entries => length(ValidEntries),
                total_memory => maps:get(total_memory, Stats, 0) - RemovedMemory,
                expired => maps:get(expired, Stats, 0) + RemovedCount
            },

            {ValidEntries, UpdatedStats};
        false ->
            {Entries, Stats}
    end.

calculate_size(Value) ->
    term_size(Value).

term_size(Term) ->
    byte_size(term_to_binary(Term)).

calculate_hit_ratio(Stats) ->
    TotalHits = maps:get(total_hits, Stats, 0),
    TotalMisses = maps:get(total_misses, Stats, 0),

    case TotalHits + TotalMisses > 0 of
        true -> TotalHits / (TotalHits + TotalMisses);
        false -> 0.0
    end.

get_oldest_entry(Entries) ->
    case Entries of
        [] -> undefined;
        _ -> lists:min(Entries, #cache_entry.accessed)
    end.

get_newest_entry(Entries) ->
    case Entries of
        [] -> undefined;
        _ -> lists:max(Entries, #cache_entry.accessed)
    end.

format_config(Config) ->
    #{
        name => Config#cache_config.name,
        max_size => Config#cache_config.max_size,
        ttl => Config#cache_config.ttl,
        eviction_policy => atom_to_binary(Config#cache_config.eviction_policy),
        memory_limit => Config#cache_config.memory_limit
    }.

update_config(Config, NewConfig) ->
    #cache_config{
        name = maps:get(name, NewConfig, Config#cache_config.name),
        max_size = maps:get(max_size, NewConfig, Config#cache_config.max_size),
        ttl = maps:get(ttl, NewConfig, Config#cache_config.ttl),
        eviction_policy = maps:get(eviction_policy, NewConfig, Config#cache_config.eviction_policy),
        memory_limit = maps:get(memory_limit, NewConfig, Config#cache_config.memory_limit)
    }.