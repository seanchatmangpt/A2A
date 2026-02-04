%%% @doc elrmcp Rate Limiter
%%% Implements token bucket rate limiting for request forwarding

-module(elrmcp_rate_limiter).
-behaviour(gen_server).

%% API
-export([start_link/1, stop/0]).
-export([check/1, reset/0, get_status/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_TOKENS, 100).
-define(DEFAULT_REFILL_INTERVAL, 1000).  % 1 second
-define(DEFAULT_TOKENS_PER_REFILL, 10).

-record(state, {
    tokens :: integer(),
    max_tokens :: integer(),
    refill_interval :: integer(),
    tokens_per_refill :: integer(),
    last_refill :: integer(),
    ref_timer :: reference() | undefined
}).

%%====================================================================
%% API
%%====================================================================

%% @doc Start the rate limiter
-spec start_link(integer()) -> {ok, pid()} | {error, term()}.
start_link(MaxTokens) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [MaxTokens], []).

%% @doc Stop the rate limiter
stop() ->
    gen_server:stop(?SERVER).

%% @doc Check if a request is allowed
-spec check(pid()) -> allowed | denied.
check(_Pid) ->
    gen_server:call(?SERVER, check).

%% @doc Reset rate limiter state
reset() ->
    gen_server:call(?SERVER, reset).

%% @doc Get current rate limiter status
get_status() ->
    gen_server:call(?SERVER, get_status).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([MaxTokens]) ->
    State = #state{
        tokens = MaxTokens,
        max_tokens = MaxTokens,
        refill_interval = ?DEFAULT_REFILL_INTERVAL,
        tokens_per_refill = ?DEFAULT_TOKENS_PER_REFILL,
        last_refill = erlang:system_time(millisecond),
        ref_timer = undefined
    },

    %% Start refill timer
    {ok, State1} = schedule_refill(State),

    {ok, State1}.

handle_call(check, _From, State) ->
    State1 = refill_tokens(State),
    case State1#state.tokens > 0 of
        true ->
            NewTokens = State1#state.tokens - 1,
            {reply, allowed, State1#state{tokens = NewTokens}};
        false ->
            {reply, denied, State1}
    end;

handle_call(reset, _From, State) ->
    State1 = State#state{
        tokens = State#state.max_tokens,
        last_refill = erlang:system_time(millisecond)
    },
    {reply, ok, State1};

handle_call(get_status, _From, State) ->
    Status = #{
        tokens => State#state.tokens,
        max_tokens => State#state.max_tokens,
        tokens_per_refill => State#state.tokens_per_refill,
        refill_interval => State#state.refill_interval,
        refill_rate => calculate_refill_rate(State)
    },
    {reply, {ok, Status}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(refill, State) ->
    State1 = refill_tokens(State),
    {ok, State2} = schedule_refill(State1),
    {noreply, State2};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    case State#state.ref_timer of
        undefined ->
            ok;
        Timer ->
            erlang:cancel_timer(Timer)
    end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @refill tokens based on elapsed time
refill_tokens(State) ->
    Now = erlang:system_time(millisecond),
    Elapsed = Now - State#state.last_refill,
    RefillIntervals = Elapsed div State#state.refill_interval,

    TokensToAdd = RefillIntervals * State#state.tokens_per_refill,
    NewTokens = min(State#state.tokens + TokensToAdd, State#state.max_tokens),

    State#state{
        tokens = NewTokens,
        last_refill = Now + (Elapsed rem State#state.refill_interval)
    }.

%% @refill schedule timer
schedule_refill(State) ->
    State#state.ref_timer = erlang:send_after(State#state.refill_interval, self(), refill),
    {ok, State}.

%% @refill calculate refill rate
calculate_refill_rate(State) ->
    State#state.tokens_per_refill / (State#state.refill_interval / 1000).