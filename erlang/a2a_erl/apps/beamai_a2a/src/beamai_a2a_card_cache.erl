%%%-------------------------------------------------------------------
%%% @doc BeamAI Agent Card Cache
%%%
%%% Caches remote agent cards after discovery using ETS. Provides
%%% TTL-based expiry and background refresh of cached cards.
%%% This cache is used to store agent cards discovered from remote
%%% agents so that repeated lookups are fast.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_card_cache).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    get/1,
    put/2,
    put/3,
    invalidate/1,
    clear/0,
    size/0,
    list_keys/0
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
-define(CACHE_TABLE, beamai_card_cache).
-define(DEFAULT_TTL_MS, 600000).      %% 10 minutes
-define(CLEANUP_INTERVAL_MS, 60000).  %% 1 minute
-define(REFRESH_AHEAD_MS, 30000).     %% 30 seconds before expiry

-record(cache_entry, {
    key         :: binary(),
    card        :: map(),
    inserted_at :: integer(),
    expires_at  :: integer(),
    ttl_ms      :: pos_integer(),
    url         :: binary() | undefined,
    refresh_count :: non_neg_integer()
}).

-record(state, {
    table       :: ets:tid(),
    default_ttl :: pos_integer(),
    cleanup_ref :: reference() | undefined,
    refresh_enabled :: boolean(),
    stats       :: map()
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Start the card cache with default settings.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the card cache with custom configuration.
%% Options: default_ttl, refresh_enabled
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%% @doc Look up a cached agent card by its URL or identifier.
%% Returns {ok, Card} if found and not expired, or {error, not_found}.
-spec get(binary()) -> {ok, map()} | {error, not_found | expired}.
get(Key) ->
    gen_server:call(?SERVER, {get, Key}).

%% @doc Cache an agent card with the default TTL.
-spec put(binary(), map()) -> ok.
put(Key, Card) ->
    put(Key, Card, #{}).

%% @doc Cache an agent card with options.
%% Options: ttl_ms, url (source URL for background refresh)
-spec put(binary(), map(), map()) -> ok.
put(Key, Card, Opts) ->
    gen_server:call(?SERVER, {put, Key, Card, Opts}).

%% @doc Remove a specific entry from the cache.
-spec invalidate(binary()) -> ok.
invalidate(Key) ->
    gen_server:cast(?SERVER, {invalidate, Key}).

%% @doc Remove all entries from the cache.
-spec clear() -> ok.
clear() ->
    gen_server:cast(?SERVER, clear).

%% @doc Return the number of entries in the cache.
-spec size() -> non_neg_integer().
size() ->
    gen_server:call(?SERVER, size).

%% @doc List all cached keys.
-spec list_keys() -> [binary()].
list_keys() ->
    gen_server:call(?SERVER, list_keys).

%%====================================================================
%% gen_server callbacks
%%====================================================================

%% @private
init(Opts) ->
    Table = ets:new(?CACHE_TABLE, [
        set, private, {keypos, #cache_entry.key}
    ]),
    DefaultTtl = maps:get(default_ttl, Opts, ?DEFAULT_TTL_MS),
    RefreshEnabled = maps:get(refresh_enabled, Opts, true),

    %% Schedule periodic cleanup
    CleanupRef = erlang:send_after(?CLEANUP_INTERVAL_MS, self(), cleanup),

    State = #state{
        table = Table,
        default_ttl = DefaultTtl,
        cleanup_ref = CleanupRef,
        refresh_enabled = RefreshEnabled,
        stats = #{
            hits => 0,
            misses => 0,
            expirations => 0,
            refreshes => 0
        }
    },
    logger:info("BeamAI card cache started (TTL=~pms, refresh=~p)",
                [DefaultTtl, RefreshEnabled]),
    {ok, State}.

%% @private
handle_call({get, Key}, _From, #state{table = Table, stats = Stats} = State) ->
    Now = erlang:system_time(millisecond),
    case ets:lookup(Table, Key) of
        [#cache_entry{card = Card, expires_at = Expires}] when Now < Expires ->
            %% Cache hit - check if we should trigger background refresh
            maybe_schedule_refresh(Key, Expires, Now, State),
            Hits = maps:get(hits, Stats, 0),
            NewStats = Stats#{hits => Hits + 1},
            {reply, {ok, Card}, State#state{stats = NewStats}};
        [#cache_entry{}] ->
            %% Expired entry
            ets:delete(Table, Key),
            Misses = maps:get(misses, Stats, 0),
            Exps = maps:get(expirations, Stats, 0),
            NewStats = Stats#{misses => Misses + 1, expirations => Exps + 1},
            {reply, {error, expired}, State#state{stats = NewStats}};
        [] ->
            Misses = maps:get(misses, Stats, 0),
            NewStats = Stats#{misses => Misses + 1},
            {reply, {error, not_found}, State#state{stats = NewStats}}
    end;

handle_call({put, Key, Card, Opts}, _From, #state{table = Table, default_ttl = DefaultTtl} = State) ->
    Now = erlang:system_time(millisecond),
    TtlMs = maps:get(ttl_ms, Opts, DefaultTtl),
    Url = maps:get(url, Opts, undefined),
    Entry = #cache_entry{
        key = Key,
        card = Card,
        inserted_at = Now,
        expires_at = Now + TtlMs,
        ttl_ms = TtlMs,
        url = Url,
        refresh_count = 0
    },
    ets:insert(Table, Entry),
    {reply, ok, State};

handle_call(size, _From, #state{table = Table} = State) ->
    {reply, ets:info(Table, size), State};

handle_call(list_keys, _From, #state{table = Table} = State) ->
    Keys = ets:foldl(
        fun(#cache_entry{key = K}, Acc) -> [K | Acc] end,
        [],
        Table
    ),
    {reply, lists:reverse(Keys), State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({invalidate, Key}, #state{table = Table} = State) ->
    ets:delete(Table, Key),
    {noreply, State};

handle_cast(clear, #state{table = Table} = State) ->
    ets:delete_all_objects(Table),
    logger:info("Agent card cache cleared"),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(cleanup, #state{table = Table} = State) ->
    %% Remove all expired entries
    Now = erlang:system_time(millisecond),
    ExpiredKeys = ets:foldl(
        fun(#cache_entry{key = K, expires_at = Exp}, Acc) ->
            case Now >= Exp of
                true -> [K | Acc];
                false -> Acc
            end
        end,
        [],
        Table
    ),
    lists:foreach(fun(K) -> ets:delete(Table, K) end, ExpiredKeys),
    case length(ExpiredKeys) > 0 of
        true ->
            logger:debug("Card cache cleanup: removed ~p expired entries",
                         [length(ExpiredKeys)]);
        false ->
            ok
    end,
    %% Schedule next cleanup
    CleanupRef = erlang:send_after(?CLEANUP_INTERVAL_MS, self(), cleanup),
    {noreply, State#state{cleanup_ref = CleanupRef}};

handle_info({refresh_card, Key}, #state{table = Table, stats = Stats} = State) ->
    case ets:lookup(Table, Key) of
        [#cache_entry{url = Url, ttl_ms = TtlMs, refresh_count = Count} = Entry]
          when Url =/= undefined ->
            %% Attempt to refresh the card from the source URL
            case fetch_remote_card(Url) of
                {ok, NewCard} ->
                    Now = erlang:system_time(millisecond),
                    NewEntry = Entry#cache_entry{
                        card = NewCard,
                        inserted_at = Now,
                        expires_at = Now + TtlMs,
                        refresh_count = Count + 1
                    },
                    ets:insert(Table, NewEntry),
                    Refreshes = maps:get(refreshes, Stats, 0),
                    NewStats = Stats#{refreshes => Refreshes + 1},
                    logger:debug("Card cache refreshed: ~s (count=~p)", [Key, Count + 1]),
                    {noreply, State#state{stats = NewStats}};
                {error, _Reason} ->
                    %% Refresh failed, keep existing entry
                    {noreply, State}
            end;
        _ ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, #state{table = Table, cleanup_ref = Ref}) ->
    case Ref of
        undefined -> ok;
        _ -> erlang:cancel_timer(Ref)
    end,
    ets:delete(Table),
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

%% @private Schedule a background refresh if the entry is about to expire.
-spec maybe_schedule_refresh(binary(), integer(), integer(), #state{}) -> ok.
maybe_schedule_refresh(Key, Expires, Now, #state{refresh_enabled = true}) ->
    TimeToExpiry = Expires - Now,
    case TimeToExpiry =< ?REFRESH_AHEAD_MS of
        true ->
            %% Entry is about to expire, schedule refresh
            self() ! {refresh_card, Key},
            ok;
        false ->
            ok
    end;
maybe_schedule_refresh(_Key, _Expires, _Now, _State) ->
    ok.

%% @private Fetch a remote agent card from its well-known URL.
-spec fetch_remote_card(binary()) -> {ok, map()} | {error, term()}.
fetch_remote_card(Url) ->
    CardUrl = case binary:match(Url, <<".well-known/agent-card.json">>) of
        nomatch ->
            %% Append the well-known path
            BaseUrl = binary:replace(Url, <<"/">>, <<>>, [global, {scope, {byte_size(Url) - 1, 1}}]),
            <<BaseUrl/binary, "/.well-known/agent-card.json">>;
        _ ->
            Url
    end,
    try
        case beamai_http_client:get(CardUrl) of
            {ok, 200, _Headers, Body} when is_map(Body) ->
                {ok, Body};
            {ok, 200, _Headers, Body} when is_binary(Body) ->
                {ok, jsx:decode(Body, [return_maps])};
            {ok, Status, _Headers, _Body} ->
                {error, {http_status, Status}};
            {error, Reason} ->
                {error, Reason}
        end
    catch
        Class:Reason2:_Stack ->
            {error, {Class, Reason2}}
    end.
