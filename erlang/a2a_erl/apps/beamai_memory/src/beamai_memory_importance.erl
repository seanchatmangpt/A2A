%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Memory Importance Scoring
%%%
%%% Calculates and maintains importance scores for memory items based
%%% on multiple signals:
%%%
%%%   - Access frequency: how often an item is read
%%%   - Recency: how recently an item was accessed
%%%   - Explicit marking: items can be pinned/boosted
%%%   - Decay: scores decrease over time following configurable curves
%%%
%%% Importance scores range from 0.0 (unimportant, candidate for
%%% forgetting) to 1.0 (critical, always retained).
%%%
%%% The scoring algorithm combines:
%%%   score = (frequency_weight * freq_score) +
%%%           (recency_weight * recency_score) +
%%%           (explicit_weight * explicit_score)
%%%
%%% Where each component is normalized to [0.0, 1.0].
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_memory_importance).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    score/1,
    score/2,
    update/2,
    get_important/1,
    get_important/2,
    decay/0,
    pin/2,
    unpin/2,
    boost/2,
    boost/3,
    set_weights/1,
    get_scores/1
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
-define(IMPORTANCE_TABLE, beamai_importance).
-define(DEFAULT_DECAY_INTERVAL, 300000). %% 5 minutes

-record(importance_entry, {
    key               :: {atom(), term()},  %% {Namespace, Key}
    base_score        :: float(),
    frequency_score   :: float(),
    recency_score     :: float(),
    explicit_score    :: float(),
    access_count      :: non_neg_integer(),
    last_accessed     :: integer(),
    created_at        :: integer(),
    pinned            :: boolean(),
    boost_until       :: integer() | infinity,
    boost_amount      :: float()
}).

-record(state, {
    weights       :: map(),
    decay_rate    :: float(),
    decay_timer   :: reference() | undefined,
    decay_interval :: pos_integer()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the importance scoring server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Calculate the current importance score for a key in a namespace.
%% Returns a float between 0.0 and 1.0.
-spec score({atom(), term()}) -> {ok, float()} | {error, not_found}.
score({Namespace, Key}) ->
    gen_server:call(?SERVER, {score, Namespace, Key}).

%% @doc Calculate importance score with explicit namespace and key.
-spec score(atom(), term()) -> {ok, float()} | {error, not_found}.
score(Namespace, Key) ->
    gen_server:call(?SERVER, {score, Namespace, Key}).

%% @doc Update importance metadata when an item is accessed.
%% Action is one of: access, create, modify, delete.
-spec update({atom(), term()}, atom()) -> ok.
update({Namespace, Key}, Action) ->
    gen_server:cast(?SERVER, {update, Namespace, Key, Action}).

%% @doc Get all items in a namespace with importance above the threshold.
%% Uses the default threshold from application config.
-spec get_important(atom()) -> {ok, [{term(), float()}]}.
get_important(Namespace) ->
    Threshold = beamai_memory_app:get_config(importance_threshold, 0.3),
    get_important(Namespace, Threshold).

%% @doc Get items with importance above a custom threshold.
-spec get_important(atom(), float()) -> {ok, [{term(), float()}]}.
get_important(Namespace, Threshold) ->
    gen_server:call(?SERVER, {get_important, Namespace, Threshold}).

%% @doc Apply decay to all importance scores.
%% Called periodically by the decay timer, but can also be triggered manually.
-spec decay() -> ok.
decay() ->
    gen_server:cast(?SERVER, decay).

%% @doc Pin an item so it is always considered important (score = 1.0).
-spec pin(atom(), term()) -> ok.
pin(Namespace, Key) ->
    gen_server:call(?SERVER, {pin, Namespace, Key}).

%% @doc Unpin an item, returning it to normal scoring.
-spec unpin(atom(), term()) -> ok.
unpin(Namespace, Key) ->
    gen_server:call(?SERVER, {unpin, Namespace, Key}).

%% @doc Temporarily boost an item's importance score.
-spec boost(atom(), term()) -> ok.
boost(Namespace, Key) ->
    boost(Namespace, Key, #{}).

%% @doc Boost with options: #{amount => float(), duration_ms => integer()}.
-spec boost(atom(), term(), map()) -> ok.
boost(Namespace, Key, Opts) ->
    gen_server:call(?SERVER, {boost, Namespace, Key, Opts}).

%% @doc Set the scoring weights.
%% Weights map: #{frequency => float(), recency => float(), explicit => float()}.
-spec set_weights(map()) -> ok.
set_weights(Weights) ->
    gen_server:call(?SERVER, {set_weights, Weights}).

%% @doc Get all scores for a namespace as [{Key, Score}].
-spec get_scores(atom()) -> {ok, [{term(), float()}]}.
get_scores(Namespace) ->
    gen_server:call(?SERVER, {get_scores, Namespace}).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    case ets:info(?IMPORTANCE_TABLE) of
        undefined ->
            _ = ets:new(?IMPORTANCE_TABLE, [
                named_table,
                set,
                {keypos, #importance_entry.key},
                protected
            ]);
        _ ->
            ok
    end,

    DefaultWeights = #{
        frequency => 0.3,
        recency => 0.5,
        explicit => 0.2
    },

    DecayInterval = beamai_memory_app:get_config(decay_interval, ?DEFAULT_DECAY_INTERVAL),
    DecayTimer = erlang:send_after(DecayInterval, self(), decay_tick),

    State = #state{
        weights = DefaultWeights,
        decay_rate = 0.05,     %% 5% decay per interval
        decay_timer = DecayTimer,
        decay_interval = DecayInterval
    },

    logger:info("BeamAI Importance Scorer initialized (decay_interval=~pms)", [DecayInterval]),
    {ok, State}.

%% @private
handle_call({score, Namespace, Key}, _From, State) ->
    Reply = do_score(Namespace, Key, State),
    {reply, Reply, State};

handle_call({get_important, Namespace, Threshold}, _From, State) ->
    Reply = do_get_important(Namespace, Threshold, State),
    {reply, Reply, State};

handle_call({pin, Namespace, Key}, _From, State) ->
    do_pin(Namespace, Key),
    {reply, ok, State};

handle_call({unpin, Namespace, Key}, _From, State) ->
    do_unpin(Namespace, Key),
    {reply, ok, State};

handle_call({boost, Namespace, Key, Opts}, _From, State) ->
    do_boost(Namespace, Key, Opts),
    {reply, ok, State};

handle_call({set_weights, Weights}, _From, State) ->
    NewWeights = maps:merge(State#state.weights, Weights),
    {reply, ok, State#state{weights = NewWeights}};

handle_call({get_scores, Namespace}, _From, State) ->
    Reply = do_get_scores(Namespace, State),
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast({update, Namespace, Key, Action}, State) ->
    do_update(Namespace, Key, Action),
    {noreply, State};

handle_cast(decay, State) ->
    do_decay(State),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(decay_tick, State) ->
    do_decay(State),
    DecayTimer = erlang:send_after(State#state.decay_interval, self(), decay_tick),
    {noreply, State#state{decay_timer = DecayTimer}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, State) ->
    case State#state.decay_timer of
        undefined -> ok;
        Ref -> erlang:cancel_timer(Ref)
    end,
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private Calculate composite importance score.
do_score(Namespace, Key, State) ->
    CompoundKey = {Namespace, Key},
    case ets:lookup(?IMPORTANCE_TABLE, CompoundKey) of
        [Entry] ->
            Score = calculate_score(Entry, State),
            {ok, Score};
        [] ->
            %% Try to build from memory store metadata
            case build_entry_from_store(Namespace, Key) of
                {ok, Entry} ->
                    ets:insert(?IMPORTANCE_TABLE, Entry),
                    Score = calculate_score(Entry, State),
                    {ok, Score};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

%% @private Calculate the weighted score from an entry.
calculate_score(Entry, State) ->
    #importance_entry{
        pinned = Pinned,
        boost_until = BoostUntil,
        boost_amount = BoostAmount
    } = Entry,

    %% Pinned items always score 1.0
    case Pinned of
        true ->
            1.0;
        false ->
            Weights = State#state.weights,
            FreqWeight = maps:get(frequency, Weights, 0.3),
            RecWeight = maps:get(recency, Weights, 0.5),
            ExplWeight = maps:get(explicit, Weights, 0.2),

            FreqScore = calculate_frequency_score(Entry),
            RecScore = calculate_recency_score(Entry),
            ExplScore = Entry#importance_entry.explicit_score,

            BaseScore = (FreqWeight * FreqScore) +
                        (RecWeight * RecScore) +
                        (ExplWeight * ExplScore),

            %% Apply boost if active
            Now = erlang:system_time(millisecond),
            BoostedScore = case BoostUntil of
                infinity ->
                    min(1.0, BaseScore + BoostAmount);
                Until when is_integer(Until), Now =< Until ->
                    min(1.0, BaseScore + BoostAmount);
                _ ->
                    BaseScore
            end,

            %% Clamp to [0.0, 1.0]
            max(0.0, min(1.0, BoostedScore))
    end.

%% @private Frequency score: logarithmic scaling of access count.
calculate_frequency_score(#importance_entry{access_count = Count}) ->
    case Count of
        0 -> 0.0;
        N ->
            %% Log scaling: score approaches 1.0 as access count grows
            %% ln(N+1) / ln(101) gives roughly 0.0 to 1.0 for N = 0 to 100
            min(1.0, math:log(N + 1) / math:log(101))
    end.

%% @private Recency score: exponential decay based on time since last access.
calculate_recency_score(#importance_entry{last_accessed = LastAccessed}) ->
    Now = erlang:system_time(millisecond),
    ElapsedMs = max(0, Now - LastAccessed),
    %% Half-life of 1 hour (3600000 ms)
    HalfLifeMs = 3600000,
    math:pow(0.5, ElapsedMs / HalfLifeMs).

%% @private Update importance entry when an item is accessed.
do_update(Namespace, Key, Action) ->
    CompoundKey = {Namespace, Key},
    Now = erlang:system_time(millisecond),

    Entry = case ets:lookup(?IMPORTANCE_TABLE, CompoundKey) of
        [Existing] -> Existing;
        [] ->
            #importance_entry{
                key = CompoundKey,
                base_score = 0.5,
                frequency_score = 0.0,
                recency_score = 1.0,
                explicit_score = 0.0,
                access_count = 0,
                last_accessed = Now,
                created_at = Now,
                pinned = false,
                boost_until = 0,
                boost_amount = 0.0
            }
    end,

    UpdatedEntry = case Action of
        access ->
            Entry#importance_entry{
                access_count = Entry#importance_entry.access_count + 1,
                last_accessed = Now
            };
        create ->
            Entry#importance_entry{
                created_at = Now,
                last_accessed = Now,
                access_count = 1,
                recency_score = 1.0
            };
        modify ->
            Entry#importance_entry{
                access_count = Entry#importance_entry.access_count + 1,
                last_accessed = Now,
                explicit_score = min(1.0, Entry#importance_entry.explicit_score + 0.1)
            };
        delete ->
            Entry#importance_entry{
                explicit_score = 0.0,
                base_score = 0.0
            };
        _ ->
            Entry
    end,

    ets:insert(?IMPORTANCE_TABLE, UpdatedEntry).

%% @private Get all important items above threshold.
do_get_important(Namespace, Threshold, State) ->
    Results = ets:foldl(fun(Entry, Acc) ->
        {Ns, Key} = Entry#importance_entry.key,
        case Ns of
            Namespace ->
                Score = calculate_score(Entry, State),
                case Score >= Threshold of
                    true -> [{Key, Score} | Acc];
                    false -> Acc
                end;
            _ ->
                Acc
        end
    end, [], ?IMPORTANCE_TABLE),

    %% Sort by score descending
    Sorted = lists:sort(fun({_, ScoreA}, {_, ScoreB}) ->
        ScoreA >= ScoreB
    end, Results),

    {ok, Sorted}.

%% @private Get all scores for a namespace.
do_get_scores(Namespace, State) ->
    Results = ets:foldl(fun(Entry, Acc) ->
        {Ns, Key} = Entry#importance_entry.key,
        case Ns of
            Namespace ->
                Score = calculate_score(Entry, State),
                [{Key, Score} | Acc];
            _ ->
                Acc
        end
    end, [], ?IMPORTANCE_TABLE),

    Sorted = lists:sort(fun({_, ScoreA}, {_, ScoreB}) ->
        ScoreA >= ScoreB
    end, Results),

    {ok, Sorted}.

%% @private Apply decay to all scores.
do_decay(State) ->
    DecayRate = State#state.decay_rate,
    Now = erlang:system_time(millisecond),

    ets:foldl(fun(Entry, _) ->
        case Entry#importance_entry.pinned of
            true ->
                ok; %% Pinned items don't decay
            false ->
                %% Decay the explicit score
                NewExplicit = max(0.0, Entry#importance_entry.explicit_score * (1.0 - DecayRate)),
                %% Clear expired boosts
                NewBoostUntil = case Entry#importance_entry.boost_until of
                    infinity -> infinity;
                    Until when is_integer(Until), Now > Until -> 0;
                    Other -> Other
                end,
                NewBoostAmount = case NewBoostUntil of
                    0 -> 0.0;
                    _ -> Entry#importance_entry.boost_amount
                end,
                Updated = Entry#importance_entry{
                    explicit_score = NewExplicit,
                    boost_until = NewBoostUntil,
                    boost_amount = NewBoostAmount
                },
                ets:insert(?IMPORTANCE_TABLE, Updated)
        end
    end, ok, ?IMPORTANCE_TABLE).

%% @private Pin an item.
do_pin(Namespace, Key) ->
    CompoundKey = {Namespace, Key},
    Now = erlang:system_time(millisecond),
    Entry = case ets:lookup(?IMPORTANCE_TABLE, CompoundKey) of
        [Existing] -> Existing;
        [] ->
            #importance_entry{
                key = CompoundKey,
                base_score = 1.0,
                frequency_score = 0.0,
                recency_score = 1.0,
                explicit_score = 1.0,
                access_count = 0,
                last_accessed = Now,
                created_at = Now,
                pinned = false,
                boost_until = 0,
                boost_amount = 0.0
            }
    end,
    ets:insert(?IMPORTANCE_TABLE, Entry#importance_entry{pinned = true}).

%% @private Unpin an item.
do_unpin(Namespace, Key) ->
    CompoundKey = {Namespace, Key},
    case ets:lookup(?IMPORTANCE_TABLE, CompoundKey) of
        [Entry] ->
            ets:insert(?IMPORTANCE_TABLE, Entry#importance_entry{pinned = false});
        [] ->
            ok
    end.

%% @private Boost an item temporarily.
do_boost(Namespace, Key, Opts) ->
    CompoundKey = {Namespace, Key},
    Now = erlang:system_time(millisecond),
    Amount = maps:get(amount, Opts, 0.3),
    DurationMs = maps:get(duration_ms, Opts, 3600000), %% default 1 hour

    BoostUntil = case DurationMs of
        infinity -> infinity;
        Ms -> Now + Ms
    end,

    Entry = case ets:lookup(?IMPORTANCE_TABLE, CompoundKey) of
        [Existing] -> Existing;
        [] ->
            #importance_entry{
                key = CompoundKey,
                base_score = 0.5,
                frequency_score = 0.0,
                recency_score = 1.0,
                explicit_score = 0.0,
                access_count = 0,
                last_accessed = Now,
                created_at = Now,
                pinned = false,
                boost_until = 0,
                boost_amount = 0.0
            }
    end,
    ets:insert(?IMPORTANCE_TABLE, Entry#importance_entry{
        boost_until = BoostUntil,
        boost_amount = Amount
    }).

%% @private Try to build an importance entry from the memory store metadata.
build_entry_from_store(Namespace, Key) ->
    CompoundKey = {Namespace, Key},
    case ets:lookup(beamai_memory_meta, CompoundKey) of
        [{CompoundKey, Meta}] ->
            Now = erlang:system_time(millisecond),
            Entry = #importance_entry{
                key = CompoundKey,
                base_score = 0.5,
                frequency_score = 0.0,
                recency_score = 1.0,
                explicit_score = 0.0,
                access_count = maps:get(access_count, Meta, 0),
                last_accessed = maps:get(last_accessed, Meta, Now),
                created_at = maps:get(created_at, Meta, Now),
                pinned = false,
                boost_until = 0,
                boost_amount = 0.0
            },
            {ok, Entry};
        [] ->
            {error, not_found}
    end.
