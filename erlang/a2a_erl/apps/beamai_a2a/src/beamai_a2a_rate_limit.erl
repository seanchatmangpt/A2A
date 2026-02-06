%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A Rate Limiter
%%%
%%% Implements per-client rate limiting using the token-bucket
%%% algorithm.  State is kept in an ETS table for lock-free reads
%%% and atomic updates.
%%%
%%% Each client (identified by a binary key -- typically an IP or
%%% API key) has a bucket with configurable capacity and refill rate.
%%% Method-specific overrides are supported.
%%%
%%% Usage:
%%%   beamai_a2a_rate_limit:start_link().
%%%   beamai_a2a_rate_limit:configure(#{
%%%       default_capacity => 100,
%%%       default_refill_rate => 10,  %% tokens per second
%%%       methods => #{
%%%           <<"tasks/send">> => #{capacity => 20, refill_rate => 5}
%%%       }
%%%   }).
%%%   case beamai_a2a_rate_limit:check(ClientId, Method) of
%%%       allow -> handle_request(...);
%%%       {deny, RetryAfterMs} -> return_429(RetryAfterMs)
%%%   end.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_rate_limit).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    check/2,
    allow/1,
    configure/1,
    configure/2,
    reset/1,
    reset_all/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2
]).

-define(TABLE, beamai_a2a_rate_limit_buckets).
-define(SERVER, ?MODULE).

%% Default configuration
-define(DEFAULT_CAPACITY, 100).
-define(DEFAULT_REFILL_RATE, 10).  %% tokens per second

-record(state, {
    config :: map()
}).

%% Bucket record stored in ETS:
%% {Key, Tokens :: float(), LastRefill :: integer(), Capacity :: integer(), RefillRate :: number()}
-type bucket_key() :: {binary(), binary() | default}.

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Start the rate limiter with default configuration.
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%%--------------------------------------------------------------------
%% @doc Start the rate limiter with the given configuration.
%%
%% Config keys:
%%   `default_capacity'   - max tokens in a bucket (default 100)
%%   `default_refill_rate' - tokens added per second (default 10)
%%   `methods'            - map of method-name to #{capacity, refill_rate}
%% @end
%%--------------------------------------------------------------------
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []).

%%--------------------------------------------------------------------
%% @doc Check whether a request from `ClientId' for `Method' is
%% allowed.
%%
%% Returns `allow' if a token is available and consumed, or
%% `{deny, RetryAfterMs}' with the number of milliseconds the client
%% should wait.
%% @end
%%--------------------------------------------------------------------
-spec check(binary(), binary()) -> allow | {deny, non_neg_integer()}.
check(ClientId, Method) ->
    Key = {ClientId, Method},
    Now = erlang:monotonic_time(millisecond),
    case ets:lookup(?TABLE, Key) of
        [{Key, Tokens, LastRefill, Capacity, RefillRate}] ->
            consume_token(Key, Tokens, LastRefill, Capacity, RefillRate, Now);
        [] ->
            %% First request from this client/method pair - create bucket
            {Capacity, RefillRate} = get_limits(Method),
            %% Consume one token from a fresh bucket
            NewTokens = Capacity - 1,
            ets:insert(?TABLE, {Key, float(NewTokens), Now, Capacity, RefillRate}),
            allow
    end.

%%--------------------------------------------------------------------
%% @doc Simple rate check using only the client ID (uses `default'
%% as the method).
%% @end
%%--------------------------------------------------------------------
-spec allow(binary()) -> allow | {deny, non_neg_integer()}.
allow(ClientId) ->
    check(ClientId, <<"default">>).

%%--------------------------------------------------------------------
%% @doc Reconfigure the rate limiter.
%%
%% Accepts the same config map as `start_link/1'. Existing buckets
%% are not retroactively updated; new limits apply on the next
%% request.
%% @end
%%--------------------------------------------------------------------
-spec configure(map()) -> ok.
configure(Config) ->
    gen_server:call(?SERVER, {configure, Config}).

%%--------------------------------------------------------------------
%% @doc Set method-specific limits.
%% @end
%%--------------------------------------------------------------------
-spec configure(binary(), map()) -> ok.
configure(Method, Limits) ->
    gen_server:call(?SERVER, {configure_method, Method, Limits}).

%%--------------------------------------------------------------------
%% @doc Reset the rate limit bucket for a client.
%% @end
%%--------------------------------------------------------------------
-spec reset(binary()) -> ok.
reset(ClientId) ->
    %% Delete all entries for this client
    ets:match_delete(?TABLE, {{ClientId, '_'}, '_', '_', '_', '_'}),
    ok.

%%--------------------------------------------------------------------
%% @doc Reset all rate limit buckets.
%% @end
%%--------------------------------------------------------------------
-spec reset_all() -> ok.
reset_all() ->
    ets:delete_all_objects(?TABLE),
    ok.

%%====================================================================
%% gen_server callbacks
%%====================================================================

init(Config) ->
    ets:new(?TABLE, [
        named_table, public, set,
        {write_concurrency, true},
        {read_concurrency, true}
    ]),
    FullConfig = maps:merge(#{
        default_capacity => ?DEFAULT_CAPACITY,
        default_refill_rate => ?DEFAULT_REFILL_RATE,
        methods => #{}
    }, Config),
    %% Store config in application env for fast access from check/2
    application:set_env(beamai_a2a, rate_limit_config, FullConfig),
    %% Schedule periodic cleanup of stale buckets
    erlang:send_after(60000, self(), cleanup),
    {ok, #state{config = FullConfig}}.

handle_call({configure, NewConfig}, _From, State) ->
    Merged = maps:merge(State#state.config, NewConfig),
    application:set_env(beamai_a2a, rate_limit_config, Merged),
    {reply, ok, State#state{config = Merged}};

handle_call({configure_method, Method, Limits}, _From, State) ->
    Config = State#state.config,
    Methods = maps:get(methods, Config, #{}),
    NewMethods = maps:put(Method, Limits, Methods),
    NewConfig = Config#{methods => NewMethods},
    application:set_env(beamai_a2a, rate_limit_config, NewConfig),
    {reply, ok, State#state{config = NewConfig}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(cleanup, State) ->
    cleanup_stale_buckets(),
    erlang:send_after(60000, self(), cleanup),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Consume a token from the bucket, refilling first.
-spec consume_token(bucket_key(), float(), integer(), integer(),
                    number(), integer()) -> allow | {deny, non_neg_integer()}.
consume_token(Key, OldTokens, LastRefill, Capacity, RefillRate, Now) ->
    %% Calculate tokens to add since last refill
    ElapsedMs = max(0, Now - LastRefill),
    ElapsedSec = ElapsedMs / 1000.0,
    Refilled = OldTokens + (ElapsedSec * RefillRate),
    Tokens = min(float(Capacity), Refilled),
    case Tokens >= 1.0 of
        true ->
            NewTokens = Tokens - 1.0,
            ets:insert(?TABLE, {Key, NewTokens, Now, Capacity, RefillRate}),
            allow;
        false ->
            %% Calculate when the next token will be available
            Deficit = 1.0 - Tokens,
            WaitSec = Deficit / RefillRate,
            RetryAfterMs = max(1, ceil(WaitSec * 1000)),
            %% Update the refill time even on denial (to avoid stale calcs)
            ets:insert(?TABLE, {Key, Tokens, Now, Capacity, RefillRate}),
            {deny, RetryAfterMs}
    end.

%% @doc Get rate limits for a method, falling back to defaults.
-spec get_limits(binary()) -> {integer(), number()}.
get_limits(Method) ->
    Config = application:get_env(beamai_a2a, rate_limit_config, #{}),
    Methods = maps:get(methods, Config, #{}),
    case maps:find(Method, Methods) of
        {ok, MethodConfig} ->
            {maps:get(capacity, MethodConfig,
                      maps:get(default_capacity, Config, ?DEFAULT_CAPACITY)),
             maps:get(refill_rate, MethodConfig,
                      maps:get(default_refill_rate, Config, ?DEFAULT_REFILL_RATE))};
        error ->
            {maps:get(default_capacity, Config, ?DEFAULT_CAPACITY),
             maps:get(default_refill_rate, Config, ?DEFAULT_REFILL_RATE)}
    end.

%% @doc Remove buckets that have been idle for more than 5 minutes.
-spec cleanup_stale_buckets() -> ok.
cleanup_stale_buckets() ->
    Now = erlang:monotonic_time(millisecond),
    StaleThresholdMs = 300000,  %% 5 minutes
    ets:foldl(fun({Key, _Tokens, LastRefill, _Cap, _Rate}, Acc) ->
        case (Now - LastRefill) > StaleThresholdMs of
            true  -> ets:delete(?TABLE, Key);
            false -> ok
        end,
        Acc
    end, ok, ?TABLE).
