%%%-------------------------------------------------------------------
%%% @doc
%%% BeamAI Memory Forgetting Curves
%%%
%%% Implements forgetting curve algorithms for automatic cleanup of
%%% low-importance memory items. Supports multiple curve models:
%%%
%%%   - Ebbinghaus: R = e^(-t/S) where t is time elapsed and S is
%%%     memory stability. Classic exponential decay model.
%%%   - Linear: R = max(0, 1 - t/L) where L is the total lifetime.
%%%     Simple linear decay to zero.
%%%   - None: No automatic forgetting; items persist indefinitely.
%%%
%%% The forgetting system works in conjunction with the importance
%%% scorer. Items whose combined retention score (forgetting curve
%%% value * importance score) drops below the configured threshold
%%% are candidates for automatic removal.
%%%
%%% Retention policies can be set globally or per-namespace.
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_memory_forgetting).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    should_forget/1,
    should_forget/2,
    apply_curve/1,
    apply_curve/2,
    cleanup/1,
    cleanup/2,
    set_policy/2,
    get_policy/1,
    retention_score/2,
    force_cleanup/0,
    stats/0
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
-define(CLEANUP_INTERVAL, 60000). %% 1 minute

-record(policy, {
    curve          :: ebbinghaus | linear | none,
    threshold      :: float(),          %% Below this -> forget
    stability      :: float(),          %% Ebbinghaus S parameter (ms)
    lifetime_ms    :: integer(),         %% Linear lifetime
    min_age_ms     :: integer(),         %% Don't forget items younger than this
    max_items      :: integer() | infinity,  %% Max items per namespace
    protect_pinned :: boolean()
}).

-record(state, {
    global_policy   :: #policy{},
    ns_policies     :: map(),           %% #{Namespace => #policy{}}
    cleanup_timer   :: reference() | undefined,
    cleanup_stats   :: map()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the forgetting manager.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Check if a specific item should be forgotten.
%% Returns true if the item's retention score is below the threshold.
-spec should_forget({atom(), term()}) -> boolean().
should_forget({Namespace, Key}) ->
    should_forget(Namespace, Key).

%% @doc Check if a specific item should be forgotten.
-spec should_forget(atom(), term()) -> boolean().
should_forget(Namespace, Key) ->
    gen_server:call(?SERVER, {should_forget, Namespace, Key}).

%% @doc Apply the forgetting curve to get the retention value for an item.
%% Returns a float between 0.0 (completely forgotten) and 1.0 (fully retained).
-spec apply_curve({atom(), term()}) -> {ok, float()} | {error, not_found}.
apply_curve({Namespace, Key}) ->
    apply_curve(Namespace, Key).

%% @doc Apply the forgetting curve for a namespace/key.
-spec apply_curve(atom(), term()) -> {ok, float()} | {error, not_found}.
apply_curve(Namespace, Key) ->
    gen_server:call(?SERVER, {apply_curve, Namespace, Key}).

%% @doc Run cleanup on a namespace, removing items below threshold.
-spec cleanup(atom()) -> {ok, non_neg_integer()}.
cleanup(Namespace) ->
    cleanup(Namespace, #{}).

%% @doc Run cleanup with options.
%% Options: #{dry_run => boolean(), threshold => float()}
-spec cleanup(atom(), map()) -> {ok, non_neg_integer()} | {ok, non_neg_integer(), [term()]}.
cleanup(Namespace, Opts) ->
    gen_server:call(?SERVER, {cleanup, Namespace, Opts}, 30000).

%% @doc Set the retention policy for a namespace.
%% Policy map keys: curve, threshold, stability, lifetime_ms, min_age_ms,
%%                  max_items, protect_pinned
-spec set_policy(atom(), map()) -> ok.
set_policy(Namespace, PolicyMap) ->
    gen_server:call(?SERVER, {set_policy, Namespace, PolicyMap}).

%% @doc Get the effective policy for a namespace.
-spec get_policy(atom()) -> {ok, map()}.
get_policy(Namespace) ->
    gen_server:call(?SERVER, {get_policy, Namespace}).

%% @doc Get the combined retention score (curve * importance) for an item.
-spec retention_score(atom(), term()) -> {ok, float()} | {error, not_found}.
retention_score(Namespace, Key) ->
    gen_server:call(?SERVER, {retention_score, Namespace, Key}).

%% @doc Force an immediate cleanup pass across all namespaces.
-spec force_cleanup() -> {ok, non_neg_integer()}.
force_cleanup() ->
    gen_server:call(?SERVER, force_cleanup, 60000).

%% @doc Get cleanup statistics.
-spec stats() -> map().
stats() ->
    gen_server:call(?SERVER, stats).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

%% @private
init([]) ->
    CurveType = beamai_memory_app:get_config(forgetting_policy, ebbinghaus),
    Threshold = beamai_memory_app:get_config(importance_threshold, 0.3),

    GlobalPolicy = #policy{
        curve = CurveType,
        threshold = Threshold,
        stability = 3600000.0,    %% 1 hour default stability
        lifetime_ms = 86400000,   %% 24 hours default lifetime
        min_age_ms = 60000,       %% Don't forget items younger than 1 minute
        max_items = infinity,
        protect_pinned = true
    },

    CleanupTimer = erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup_tick),

    State = #state{
        global_policy = GlobalPolicy,
        ns_policies = #{},
        cleanup_timer = CleanupTimer,
        cleanup_stats = #{
            total_cleaned => 0,
            last_cleanup => 0,
            cleanup_runs => 0
        }
    },

    logger:info("BeamAI Forgetting Manager initialized (curve=~p, threshold=~p)",
                [CurveType, Threshold]),
    {ok, State}.

%% @private
handle_call({should_forget, Namespace, Key}, _From, State) ->
    Reply = do_should_forget(Namespace, Key, State),
    {reply, Reply, State};

handle_call({apply_curve, Namespace, Key}, _From, State) ->
    Reply = do_apply_curve(Namespace, Key, State),
    {reply, Reply, State};

handle_call({cleanup, Namespace, Opts}, _From, State) ->
    {Reply, NewState} = do_cleanup(Namespace, Opts, State),
    {reply, Reply, NewState};

handle_call({set_policy, Namespace, PolicyMap}, _From, State) ->
    Policy = get_effective_policy(Namespace, State),
    NewPolicy = apply_policy_map(Policy, PolicyMap),
    NewPolicies = maps:put(Namespace, NewPolicy, State#state.ns_policies),
    {reply, ok, State#state{ns_policies = NewPolicies}};

handle_call({get_policy, Namespace}, _From, State) ->
    Policy = get_effective_policy(Namespace, State),
    PolicyMap = policy_to_map(Policy),
    {reply, {ok, PolicyMap}, State};

handle_call({retention_score, Namespace, Key}, _From, State) ->
    Reply = do_retention_score(Namespace, Key, State),
    {reply, Reply, State};

handle_call(force_cleanup, _From, State) ->
    {Reply, NewState} = do_force_cleanup(State),
    {reply, Reply, NewState};

handle_call(stats, _From, State) ->
    {reply, State#state.cleanup_stats, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% @private
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @private
handle_info(cleanup_tick, State) ->
    {_, NewState} = do_force_cleanup(State),
    CleanupTimer = erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup_tick),
    {noreply, NewState#state{cleanup_timer = CleanupTimer}};

handle_info(_Info, State) ->
    {noreply, State}.

%% @private
terminate(_Reason, State) ->
    case State#state.cleanup_timer of
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

%% @private Check if an item should be forgotten.
do_should_forget(Namespace, Key, State) ->
    case do_retention_score(Namespace, Key, State) of
        {ok, Score} ->
            Policy = get_effective_policy(Namespace, State),
            %% Check minimum age
            case is_old_enough(Namespace, Key, Policy) of
                true -> Score < Policy#policy.threshold;
                false -> false
            end;
        {error, _} ->
            false
    end.

%% @private Apply the forgetting curve to compute raw retention.
do_apply_curve(Namespace, Key, State) ->
    Policy = get_effective_policy(Namespace, State),
    case get_item_age(Namespace, Key) of
        {ok, AgeMs} ->
            CurveValue = compute_curve(Policy, AgeMs),
            {ok, CurveValue};
        {error, Reason} ->
            {error, Reason}
    end.

%% @private Compute the combined retention score.
do_retention_score(Namespace, Key, State) ->
    Policy = get_effective_policy(Namespace, State),
    case get_item_age(Namespace, Key) of
        {ok, AgeMs} ->
            CurveValue = compute_curve(Policy, AgeMs),
            ImportanceScore = case beamai_memory_importance:score(Namespace, Key) of
                {ok, ImpScore} -> ImpScore;
                {error, _} -> 0.5  %% Default to medium importance
            end,
            %% Combined score: geometric mean of curve and importance
            Combined = math:sqrt(CurveValue * ImportanceScore),
            {ok, Combined};
        {error, Reason} ->
            {error, Reason}
    end.

%% @private Run cleanup on a single namespace.
do_cleanup(Namespace, Opts, State) ->
    DryRun = maps:get(dry_run, Opts, false),
    ThresholdOverride = maps:get(threshold, Opts, undefined),
    Policy = get_effective_policy(Namespace, State),
    Threshold = case ThresholdOverride of
        undefined -> Policy#policy.threshold;
        T -> T
    end,

    %% Get all keys in the namespace
    case beamai_memory_store:list(Namespace) of
        {ok, Keys} ->
            %% Find items to forget
            ToForget = lists:filter(fun(Key) ->
                case Policy#policy.protect_pinned of
                    true ->
                        case beamai_memory_importance:score(Namespace, Key) of
                            {ok, 1.0} -> false; %% Pinned (score = 1.0 from pin)
                            _ -> check_forget_candidate(Namespace, Key, Threshold, Policy, State)
                        end;
                    false ->
                        check_forget_candidate(Namespace, Key, Threshold, Policy, State)
                end
            end, Keys),

            case DryRun of
                true ->
                    {{ok, length(ToForget), ToForget}, State};
                false ->
                    lists:foreach(fun(Key) ->
                        beamai_memory_store:delete(Namespace, Key)
                    end, ToForget),
                    %% Update stats
                    OldStats = State#state.cleanup_stats,
                    TotalCleaned = maps:get(total_cleaned, OldStats, 0),
                    Runs = maps:get(cleanup_runs, OldStats, 0),
                    NewStats = OldStats#{
                        total_cleaned => TotalCleaned + length(ToForget),
                        last_cleanup => erlang:system_time(millisecond),
                        cleanup_runs => Runs + 1
                    },
                    {{ok, length(ToForget)}, State#state{cleanup_stats = NewStats}}
            end;
        _ ->
            {{ok, 0}, State}
    end.

%% @private Force cleanup across all namespaces.
do_force_cleanup(State) ->
    %% Get all namespaces from the data table
    Namespaces = get_all_namespaces(),
    TotalCleaned = lists:foldl(fun(Ns, Acc) ->
        case do_cleanup(Ns, #{}, State) of
            {{ok, Count}, _} -> Acc + Count;
            _ -> Acc
        end
    end, 0, Namespaces),

    OldStats = State#state.cleanup_stats,
    PrevTotal = maps:get(total_cleaned, OldStats, 0),
    Runs = maps:get(cleanup_runs, OldStats, 0),
    NewStats = OldStats#{
        total_cleaned => PrevTotal + TotalCleaned,
        last_cleanup => erlang:system_time(millisecond),
        cleanup_runs => Runs + 1
    },
    {{ok, TotalCleaned}, State#state{cleanup_stats = NewStats}}.

%% @private Check if a single item is a forget candidate.
check_forget_candidate(Namespace, Key, Threshold, Policy, State) ->
    case is_old_enough(Namespace, Key, Policy) of
        true ->
            case do_retention_score(Namespace, Key, State) of
                {ok, Score} -> Score < Threshold;
                {error, _} -> false
            end;
        false ->
            false
    end.

%%====================================================================
%% Internal: Curve Computation
%%====================================================================

%% @private Compute the forgetting curve value for a given age.
compute_curve(#policy{curve = ebbinghaus, stability = S}, AgeMs) ->
    %% Ebbinghaus: R = e^(-t/S)
    math:exp(-AgeMs / S);

compute_curve(#policy{curve = linear, lifetime_ms = L}, AgeMs) ->
    %% Linear: R = max(0, 1 - t/L)
    max(0.0, 1.0 - (AgeMs / L));

compute_curve(#policy{curve = none}, _AgeMs) ->
    1.0.

%%====================================================================
%% Internal: Policy Management
%%====================================================================

%% @private Get the effective policy for a namespace.
get_effective_policy(Namespace, State) ->
    case maps:find(Namespace, State#state.ns_policies) of
        {ok, Policy} -> Policy;
        error -> State#state.global_policy
    end.

%% @private Apply a policy map to a policy record.
apply_policy_map(Policy, Map) ->
    Policy#policy{
        curve = maps:get(curve, Map, Policy#policy.curve),
        threshold = maps:get(threshold, Map, Policy#policy.threshold),
        stability = maps:get(stability, Map, Policy#policy.stability),
        lifetime_ms = maps:get(lifetime_ms, Map, Policy#policy.lifetime_ms),
        min_age_ms = maps:get(min_age_ms, Map, Policy#policy.min_age_ms),
        max_items = maps:get(max_items, Map, Policy#policy.max_items),
        protect_pinned = maps:get(protect_pinned, Map, Policy#policy.protect_pinned)
    }.

%% @private Convert a policy record to a map.
policy_to_map(#policy{} = P) ->
    #{
        curve => P#policy.curve,
        threshold => P#policy.threshold,
        stability => P#policy.stability,
        lifetime_ms => P#policy.lifetime_ms,
        min_age_ms => P#policy.min_age_ms,
        max_items => P#policy.max_items,
        protect_pinned => P#policy.protect_pinned
    }.

%%====================================================================
%% Internal: Helper Functions
%%====================================================================

%% @private Get the age of an item in milliseconds.
get_item_age(Namespace, Key) ->
    CompoundKey = {Namespace, Key},
    case ets:lookup(beamai_memory_meta, CompoundKey) of
        [{CompoundKey, Meta}] ->
            CreatedAt = maps:get(created_at, Meta, erlang:system_time(millisecond)),
            Now = erlang:system_time(millisecond),
            {ok, max(0, Now - CreatedAt)};
        [] ->
            {error, not_found}
    end.

%% @private Check if an item is old enough to be a forgetting candidate.
is_old_enough(Namespace, Key, Policy) ->
    case get_item_age(Namespace, Key) of
        {ok, AgeMs} -> AgeMs >= Policy#policy.min_age_ms;
        {error, _} -> false
    end.

%% @private Get all namespaces from the data table.
get_all_namespaces() ->
    try
        ets:foldl(fun({{Ns, _Key}, _Value}, Acc) ->
            case lists:member(Ns, Acc) of
                true -> Acc;
                false -> [Ns | Acc]
            end
        end, [], beamai_memory_data)
    catch
        _:_ -> []
    end.
