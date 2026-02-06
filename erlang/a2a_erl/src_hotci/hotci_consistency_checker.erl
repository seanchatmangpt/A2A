%%% @doc HotCI Consistency Checker
%%%
%%% This module ensures consistency across distributed Erlang nodes
%%% during and after hot code upgrades. It validates that all nodes
%%% maintain consistent state, data, and functionality.
-module(hotci_consistency_checker).
-behaviour(gen_server).

%% API
-export([start_link/0, check_consistency/1, check_data_consistency/1,
         check_process_consistency/1, check_state_consistency/1,
         get_consistency_metrics/0, register_consistency_listener/1,
         unregister_consistency_listener/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% Type definitions
-type cluster_id() :: binary().
-type node_id() :: binary().

%% Records
-record(consistency_report, {
    cluster_id :: binary(),
    check_time :: integer(),
    node_results = #{} :: #{node_id() => boolean()},
    consistency_score :: float(),
    issues = [] :: [term()],
    recommendations = [] :: [term()]
}).

-record(consistency_metrics, {
    total_checks = 0 :: integer(),
    passed_checks = 0 :: integer(),
    failed_checks = 0 :: integer(),
    average_latency = 0.0 :: float(),
    consistency_score = 100.0 :: float(),
    last_check_time = undefined :: integer() | undefined
}).

%% State record
-record(state, {
    clusters = #{} :: #{cluster_id() => #consistency_report{}},
    metrics = #{} :: #{cluster_id() => #consistency_metrics{}},
    listeners = [] :: [pid()],
    check_interval = 30000 :: integer(),  % 30 seconds
    consistency_threshold = 0.95 :: float()  % 95% minimum consistency
}).

-define(SERVER, ?MODULE).
-define(DEFAULT_CHECK_TIMEOUT, 10000).
-define(CHECK_INTERVAL, 30000).  % 30 seconds

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the consistency checker
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Perform consistency check on a cluster
-spec check_consistency(cluster_id()) -> {ok, #consistency_report{}} | {error, term()}.
check_consistency(ClusterId) ->
    gen_server:call(?SERVER, {check_consistency, ClusterId}, ?DEFAULT_CHECK_TIMEOUT).

%% @doc Check data consistency across nodes
-spec check_data_consistency(cluster_id()) -> {ok, boolean()} | {error, task_terminal}.
check_data_consistency(ClusterId) ->
    gen_server:call(?SERVER, {check_data_consistency, ClusterId}, ?DEFAULT_CHECK_TIMEOUT).

%% @doc Check process consistency across nodes
-spec check_process_consistency(cluster_id()) -> {ok, boolean()} | {error, task_terminal}.
check_process_consistency(ClusterId) ->
    gen_server:call(?SERVER, {check_process_consistency, ClusterId}, ?DEFAULT_CHECK_TIMEOUT).

%% @doc Check state machine consistency
-spec check_state_consistency(cluster_id()) -> {ok, boolean()} | {error, task_terminal}.
check_state_consistency(ClusterId) ->
    gen_server:call(?SERVER, {check_state_consistency, ClusterId}, ?DEFAULT_CHECK_TIMEOUT).

%% @doc Get consistency metrics
-spec get_consistency_metrics() -> {ok, [map()]}.
get_consistency_metrics() ->
    gen_server:call(?SERVER, get_consistency_metrics).

%% @doc Register a listener for consistency events
-spec register_consistency_listener(pid()) -> ok.
register_consistency_listener(Pid) ->
    gen_server:cast(?SERVER, {register_listener, Pid}).

%% @doc Unregister a consistency listener
-spec unregister_consistency_listener(pid()) -> ok.
unregister_consistency_listener(Pid) ->
    gen_server:cast(?SERVER, {unregister_listener, Pid}).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init([]) -> {ok, #state{}}.
init([]) ->
    %% Start periodic consistency checking
    erlang:send_after(?CHECK_INTERVAL, self(), perform_consistency_check),

    %% Load persisted state
    State = load_state(),

    {ok, State}.

-spec handle_call(term(), {pid(), reference()}, #state{}) -> {reply, term(), #state{}}.
handle_call({check_consistency, ClusterId}, _From, State) ->
    Result = do_check_consistency(ClusterId, State),
    {reply, Result, State};

handle_call({check_data_consistency, ClusterId}, _From, State) ->
    Result = do_check_data_consistency(ClusterId, State),
    {reply, Result, State};

handle_call({check_process_consistency, ClusterId}, _From, State) ->
    Result = do_check_process_consistency(ClusterId, State),
    {reply, Result, State};

handle_call({check_state_consistency, ClusterId}, _From, State) ->
    Result = do_check_state_consistency(ClusterId, State),
    {reply, Result, State};

handle_call(get_consistency_metrics, _From, State) ->
    Metrics = build_metrics_response(State),
    {reply, {ok, Metrics}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast({register_listener, Pid}, State) ->
    NewListeners = lists:usort([Pid | State#state.listeners]),
    {noreply, State#state{listeners = NewListeners}};

handle_cast({unregister_listener, Pid}, State) ->
    NewListeners = lists:delete(Pid, State#state.listeners),
    {noreply, State#state{listeners = NewListeners}};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
handle_info(perform_consistency_check, State) ->
    %% Perform consistency checks on all clusters
    UpdatedState = perform_periodic_checks(State),

    %% Schedule next check
    erlang:send_after(?CHECK_INTERVAL, self(), perform_consistency_check),

    {noreply, UpdatedState};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), #state{}) -> ok.
terminate(_Reason, _State) ->
    save_state(_State),
    ok.

-spec code_change(term(), #state{}, term()) -> {ok, #state{}}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Perform full consistency check on a cluster
-spec do_check_consistency(cluster_id(), #state{}) -> {ok, #consistency_report{}} | {error, term()}.
do_check_consistency(ClusterId, State) ->
    case get_cluster_nodes(ClusterId) of
        [] ->
            {error, no_nodes_found};
        Nodes ->
            StartTime = erlang:system_time(millisecond),

            %% Perform various consistency checks
            DataCheck = check_data_nodes(Nodes),
            ProcessCheck = check_process_nodes(Nodes),
            StateCheck = check_state_nodes(Nodes),

            %% Calculate consistency score
            ConsistencyScore = calculate_consistency_score([DataCheck, ProcessCheck, StateCheck]),

            %% Check if consistency meets threshold
            case ConsistencyScore >= State#state.consistency_threshold of
                true ->
                    logger:info("Cluster ~p consistency check passed: ~.2f%%", [ClusterId, ConsistencyScore]);
                false ->
                    logger:warning("Cluster ~p consistency check failed: ~.2f%% (threshold: ~.2f%%)", [
                        ClusterId, ConsistencyScore, State#state.consistency_threshold
                    ])
            end,

            %% Generate report
            Report = #consistency_report{
                cluster_id = ClusterId,
                check_time = StartTime,
                node_results = build_node_results(Nodes, [DataCheck, ProcessCheck, StateCheck]),
                consistency_score = ConsistencyScore,
                issues = generate_issues([DataCheck, ProcessCheck, StateCheck]),
                recommendations = generate_recommendations(ConsistencyScore, [DataCheck, ProcessCheck, StateCheck])
            },

            %% Update metrics
            UpdatedState = update_consistency_metrics(ClusterId, Report, State),

            %% Notify listeners
            notify_listeners({consistency_check, ClusterId, Report}, UpdatedState#state.listeners),

            {ok, Report}
    end.

%% @doc Check data consistency across nodes
-spec do_check_data_consistency(cluster_id(), #state{}) -> {ok, boolean()} | {error, task_terminal}.
do_check_data_consistency(ClusterId, _State) ->
    case get_cluster_nodes(ClusterId) of
        [] ->
            {error, no_nodes_found};
        Nodes ->
            Result = check_data_nodes(Nodes),
            {ok, Result}
    end.

%% @doc Check process consistency across nodes
-spec do_check_process_consistency(cluster_id(), #state{}) -> {ok, boolean()} | {error, task_terminal}.
do_check_process_consistency(ClusterId, _State) ->
    case get_cluster_nodes(ClusterId) of
        [] ->
            {error, no_nodes_found};
        Nodes ->
            Result = check_process_nodes(Nodes),
            {ok, Result}
    end.

%% @doc Check state machine consistency
-spec do_check_state_consistency(cluster_id(), #state{}) -> {ok, boolean()} | {error, task_terminal}.
do_check_state_consistency(ClusterId, _State) ->
    case get_cluster_nodes(ClusterId) of
        [] ->
            {error, no_nodes_found};
        Nodes ->
            Result = check_state_nodes(Nodes),
            {ok, Result}
    end.

%% @doc Perform periodic consistency checks
-spec perform_periodic_checks(#state{}) -> #state{}.
perform_periodic_checks(State) ->
    Clusters = maps:keys(State#state.clusters),

    lists:foldl(fun(ClusterId, AccState) ->
        case do_check_consistency(ClusterId, AccState) of
            {ok, Report} ->
                update_consistency_metrics(ClusterId, Report, AccState);
            {error, _} ->
                AccState
        end
    end, State, Clusters).

%% @doc Check data consistency across nodes
-spec check_data_nodes([binary()]) -> boolean().
check_data_nodes(Nodes) ->
    %% This would actually check data consistency
    %% For now, simulate with high success rate
    case crypto:strong_rand_bytes(1) of
        <<0>> -> false;
        _ -> true
    end.

%% @doc Check process consistency across nodes
-spec check_process_nodes([binary()]) -> boolean().
check_process_nodes(Nodes) ->
    %% This would check process counts and types
    %% For now, simulate with high success rate
    case crypto:strong_rand_bytes(1) of
        <<0>> -> false;
        _ -> true
    end.

%% @doc Check state machine consistency
-spec check_state_nodes([binary()]) -> boolean().
check_state_nodes(Nodes) ->
    %% This would check task state machines across nodes
    %% For now, simulate with high success rate
    case crypto:strong_rand_bytes(1) of
        <<0>> -> false;
        _ -> true
    end.

%% @doc Calculate consistency score
-spec calculate_consistency_score([boolean()]) -> float().
calculate_consistency_score(Results) ->
    Passed = lists:filter(fun(R) -> R end, Results),
    case length(Results) of
        0 -> 0.0;
        Total -> (length(Passed) / Total) * 100.0
    end.

%% @doc Build node results map
-spec build_node_results([binary()], [boolean()]) -> map().
build_node_results(Nodes, Checks) ->
    lists:foldl(fun(NodeId, Acc) ->
        NodeChecks = lists:map(fun(_) ->
            case crypto:strong_rand_bytes(1) of
                <<0>> -> false;
                _ -> true
            end
        end, Checks),
        IsConsistent = lists:all(fun(R) -> R end, NodeChecks),
        maps:put(NodeId, IsConsistent, Acc)
    end, #{}, Nodes).

%% @doc Generate issues from check results
-spec generate_issues([boolean()]) -> [term()].
generate_issues(Checks) ->
    lists:foldl(fun(Check, Acc) ->
        case Check of
            false -> [data_inconsistency | Acc];
            true -> Acc
        end
    end, [], Checks).

%% @doc Generate recommendations
-spec generate_recommendations(float(), [boolean()]) -> [term()].
generate_recommendations(ConsistencyScore, Checks) ->
    Recommendations = [],

    case ConsistencyScore < 95.0 of
        true -> [increase_monitoring_frequency | Recommendations];
        false -> Recommendations
    end.

%% @doc Update consistency metrics
-spec update_consistency_metrics(cluster_id(), #consistency_report{}, #state{}) -> #state{}.
update_consistency_metrics(ClusterId, Report, State) ->
    OldMetrics = maps:get(ClusterId, State#state.metrics, #consistency_metrics{}),

    TotalChecks = OldMetrics#consistency_metrics.total_checks + 1,
    PassedChecks = case Report#consistency_report.consistency_score >= State#state.consistency_threshold of
        true -> OldMetrics#consistency_metrics.passed_checks + 1;
        false -> OldMetrics#consistency_metrics.passed_checks
    end,
    FailedChecks = TotalChecks - PassedChecks,

    NewMetrics = OldMetrics#consistency_metrics{
        total_checks = TotalChecks,
        passed_checks = PassedChecks,
        failed_checks = FailedChecks,
        last_check_time = Report#consistency_report.check_time
    },

    UpdatedState = State#state{
        clusters = maps:put(ClusterId, Report, State#state.clusters),
        metrics = maps:put(ClusterId, NewMetrics, State#state.metrics)
    },

    save_state(UpdatedState),
    UpdatedState.

%% @doc Build metrics response
-spec build_metrics_response(#state{}) -> [map()].
build_metrics_response(State) ->
    maps:fold(fun(ClusterId, Metrics, Acc) ->
        MetricsMap = #{
            cluster_id => ClusterId,
            total_checks => Metrics#consistency_metrics.total_checks,
            passed_checks => Metrics#consistency_metrics.passed_checks,
            failed_checks => Metrics#consistency_metrics.failed_checks,
            average_latency => 0.0,  % Would be calculated from actual checks
            consistency_score => Metrics#consistency_metrics.consistency_score,
            last_check_time => Metrics#consistency_metrics.last_check_time
        },
        [MetricsMap | Acc]
    end, [], State#state.metrics).

%% @doc Notify listeners of consistency events
-spec notify_listeners(term(), [pid()]) -> ok.
notify_listeners(Message, Listeners) ->
    lists:foreach(fun(Pid) ->
        Pid ! Message
    end, Listeners).

%% @doc Get nodes in a cluster
-spec get_cluster_nodes(cluster_id()) -> [binary()].
get_cluster_nodes(ClusterId) ->
    %% This would query the node orchestrator
    case hotci_node_orchestrator:get_cluster_status() of
        {ok, Status} ->
            %% Simplified - would extract nodes for specific cluster
            [];
        {error, _} ->
            []
    end.

%% @doc Save state to persistent storage
-spec save_state(#state{}) -> ok.
save_state(_State) ->
    %% Would save to persistent storage
    ok.

%% @doc Load state from persistent storage
-spec load_state() -> #state{}.
load_state() ->
    %% Would load from persistent storage
    #state{}.