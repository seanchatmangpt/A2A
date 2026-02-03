%%% @doc HotCI Metrics Collector
%%%
%%% This module collects metrics during hot code upgrades and provides
 comprehensive analytics for upgrade performance and system health.
-module(hotci_metrics_collector).
-behaviour(gen_server).

%% API
-export([start_link/0, record_metric/2, get_metrics/1, get_upgrade_summary/1,
         start_metric_session/1, end_metric_session/1, export_metrics/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% Records
-record.metric, {
    timestamp :: integer(),
    cluster_id :: binary(),
    node_id :: binary(),
    metric_type :: atom(),
    value :: number(),
    unit :: binary(),
    metadata = #{} :: map()
}.

-record.metric_session, {
    id :: binary(),
    cluster_id :: binary(),
    start_time :: integer(),
    end_time :: integer() | undefined,
    status :: 'active' | 'completed' | 'failed',
    metrics = [] :: [record(metric)]
}.

-record.upgrade_summary, {
    cluster_id :: binary(),
    upgrade_version :: binary(),
    total_nodes :: integer(),
    successful_upgrades :: integer(),
    failed_upgrades :: integer(),
    total_duration :: integer(),
    average_upgrade_time :: float(),
    consistency_score :: float(),
    rollback_occurred :: boolean(),
    failures = [] :: [term()]
}.

%% State record
-record.state, {
    sessions = #{} :: map(),         #{binary() => #metric_session{}},
    metrics = [] :: [record(metric)],
    upgrade_summaries = [] :: [record(upgrade_summary)],
    current_session :: binary() | undefined
}.

-define(SERVER, ?MODULE).
-define(METRIC_TYPES, [
    cpu_usage,
    memory_usage,
    message_queue_length,
    process_count,
    ets_table_count,
    network_io,
    disk_io,
    upgrade_progress,
    consistency_score,
    health_status
]).

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the metrics collector
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%% @doc Record a metric
-spec record_metric(binary(), map()) -> ok.
record_metric(ClusterId, MetricMap) ->
    gen_server:cast(?SERVER, {record_metric, ClusterId, MetricMap}).

%% @doc Get metrics for a cluster or session
-spec get_metrics(binary()) -> {ok, [record(metric)]} | {error, term()}.
get_metrics(ClusterId) ->
    gen_server:call(?SERVER, {get_metrics, ClusterId}).

%% @doc Get upgrade summary
-spec get_upgrade_summary(binary()) -> {ok, record(upgrade_summary)} | {error, term()}.
get_upgrade_summary(ClusterId) ->
    gen_server:call(?SERVER, {get_upgrade_summary, ClusterId}).

%% @doc Start a metric collection session
-spec start_metric_session(binary()) -> {ok, binary()} | {error, term()}.
start_metric_session(ClusterId) ->
    gen_server:call(?SERVER, {start_metric_session, ClusterId}).

%% @doc End a metric collection session
-spec end_metric_session(binary()) -> ok | {error, term()}.
end_metric_session(SessionId) ->
    gen_server:call(?SERVER, {end_metric_session, SessionId}).

%% @doc Export metrics in various formats
-spec export_metrics(binary()) -> {ok, binary()} | {error, term()}.
export_metrics(Format) when Format =:= json; Format =:= prometheus; Format =:= csv ->
    gen_server:call(?SERVER, {export_metrics, Format}).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init([]) -> {ok, #state{}}.
init([]) ->
    %% Start periodic metric collection
    erlang:send_after(5000, self(), collect_periodic_metrics),

    %% Load persisted metrics
    State = load_state(),

    {ok, State}.

-spec handle_call(term(), {pid(), reference()}, #state{}) -> {reply, term(), #state{}}.
handle_call({get_metrics, ClusterId}, _From, State) ->
    Metrics = filter_metrics_by_cluster(ClusterId, State#state.metrics),
    {reply, {ok, Metrics}, State};

handle_call({get_upgrade_summary, ClusterId}, _From, State) ->
    case get_upgrade_summary_for_cluster(ClusterId, State) of
        {ok, Summary} ->
            {reply, {ok, Summary}, State};
        {error, not_found} ->
            {reply, {error, not_found}, State}
    end;

handle_call({start_metric_session, ClusterId}, _From, State) ->
    SessionId = generate_session_id(),
    Session = #metric_session{
        id = SessionId,
        cluster_id = ClusterId,
        start_time = erlang:system_time(millisecond),
        status = active
    },

    NewState = State#state{
        sessions = maps:put(SessionId, Session, State#state.sessions),
        current_session = SessionId
    },

    {reply, {ok, SessionId}, NewState};

handle_call({end_metric_session, SessionId}, _From, State) ->
    case maps:get(SessionId, State#state.sessions, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Session ->
            UpdatedSession = Session#metric_session{
                end_time = erlang:system_time(millisecond),
                status = completed
            },

            %% Generate upgrade summary if this was an upgrade session
            Summary = generate_upgrade_summary(SessionId, UpdatedSession, State),

            NewState = State#state{
                sessions = maps:put(SessionId, UpdatedSession, State#state.sessions),
                metrics = lists:append(Session#metric_session.metrics, State#state.metrics),
                current_session = undefined,
                upgrade_summaries = case Summary of
                    undefined -> State#state.upgrade_summaries;
                    _ -> [Summary | State#state.upgrade_summaries]
                end
            },

            save_state(NewState),
            {reply, ok, NewState}
    end;

handle_call({export_metrics, Format}, _From, State) ->
    case export_metrics_format(Format, State) of
        {ok, Exported} ->
            {reply, {ok, Exported}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

-spec handle_cast(term(), #state{}) -> {noreply, #state{}}.
handle_cast({record_metric, ClusterId, MetricMap}, State) ->
    Metric = create_metric_record(ClusterId, MetricMap),
    NewMetrics = [Metric | State#state.metrics],

    %% Update current session if active
    UpdatedState = case State#state.current_session of
        undefined ->
            State#state{metrics = NewMetrics};
        SessionId ->
            case maps:get(SessionId, State#state.sessions, undefined) of
                undefined ->
                    State#state{metrics = NewMetrics};
                Session ->
                    UpdatedSession = Session#metric_session{
                        metrics = [Metric | Session#metric_session.metrics]
                    },
                    State#state{
                        sessions = maps:put(SessionId, UpdatedSession, State#state.sessions),
                        metrics = NewMetrics
                    }
            end
    end,

    save_state(UpdatedState),
    {noreply, UpdatedState};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), #state{}) -> {noreply, #state{}}.
handle_info(collect_periodic_metrics, State) ->
    %% Collect metrics from all clusters
    UpdatedState = collect_periodic_metrics(State),

    %% Schedule next collection
    erlang:send_after(5000, self(), collect_periodic_metrics),

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

%% @doc Record a metric
-spec create_metric_record(binary(), map()) -> record(metric).
create_metric_record(ClusterId, MetricMap) ->
    #metric{
        timestamp = erlang:system_time(millisecond),
        cluster_id = ClusterId,
        node_id = maps:get(node_id, MetricMap, <<"unknown">>),
        metric_type = maps:get(type, MetricMap, unknown),
        value = maps:get(value, MetricMap, 0.0),
        unit = maps:get(unit, MetricMap, <<"unitless">>),
        metadata = maps:get(metadata, MetricMap, #{})
    }.

%% @doc Collect periodic metrics from all clusters
-spec collect_periodic_metrics(#state{}) -> #state{}.
collect_periodic_metrics(State) ->
    Clusters = get_active_clusters(),

    lists:foldl(fun(ClusterId, AccState) ->
        collect_metrics_for_cluster(ClusterId, AccState)
    end, State, Clusters).

%% @doc Collect metrics for a specific cluster
-spec collect_metrics_for_cluster(binary(), #state{}) -> #state{}.
collect_metrics_for_cluster(ClusterId, State) ->
    %% Collect various metrics
    Metrics = [
        collect_cpu_metrics(ClusterId),
        collect_memory_metrics(ClusterId),
        collect_process_metrics(ClusterId),
        collect_network_metrics(ClusterId),
        collect_storage_metrics(ClusterId),
        collect_health_metrics(ClusterId)
    ],

    %% Record each metric
    lists:foldl(fun(MetricMap, AccState) ->
        handle_cast({record_metric, ClusterId, MetricMap}, AccState)
    end, State, Metrics).

%% @doc Collect CPU metrics
-spec collect_cpu_metrics(binary()) -> map().
collect_cpu_metrics(ClusterId) ->
    #{
        node_id => ClusterId,
        type => cpu_usage,
        value => get_cpu_usage(ClusterId),
        unit => <<"percent">>,
        metadata => #{}
    }.

%% @doc Collect memory metrics
-spec collect_memory_metrics(binary()) -> map().
collect_memory_metrics(ClusterId) ->
    #{
        node_id => ClusterId,
        type => memory_usage,
        value => get_memory_usage(ClusterId),
        unit => <<"bytes">>,
        metadata => #{}
    }.

%% @doc Collect process metrics
-spec collect_process_metrics(binary()) -> map().
collect_process_metrics(ClusterId) ->
    #{
        node_id => ClusterId,
        type => process_count,
        value => get_process_count(ClusterId),
        unit => <<"count">>,
        metadata => #{}
    }.

%% @doc Collect network metrics
-spec collect_network_metrics(binary()) -> map().
collect_network_metrics(ClusterId) ->
    #{
        node_id => ClusterId,
        type => network_io,
        value => get_network_io(ClusterId),
        unit => <<"bytes_per_second">>,
        metadata => #{}
    }.

%% @doc Collect storage metrics
-spec collect_storage_metrics(binary()) -> map().
collect_storage_metrics(ClusterId) ->
    #{
        node_id => ClusterId,
        type => disk_io,
        value => get_disk_io(ClusterId),
        unit => <<"bytes_per_second">>,
        metadata => #{}
    }.

%% @doc Collect health metrics
-spec collect_health_metrics(binary()) -> map().
collect_health_metrics(ClusterId) ->
    #{
        node_id => ClusterId,
        type => health_status,
        value => get_health_status(ClusterId),
        unit => <<"boolean">>,
        metadata => #{}
    }.

%% @doc Filter metrics by cluster
-spec filter_metrics_by_cluster(binary(), [record(metric)]) -> [record(metric)].
filter_metrics_by_cluster(ClusterId, Metrics) ->
    lists:filter(fun(Metric) ->
        Metric#metric.cluster_id =:= ClusterId
    end, Metrics).

%% @doc Get upgrade summary for a cluster
-spec get_upgrade_summary_for_cluster(binary(), #state{}) -> {ok, record(upgrade_summary)} | {error, term()}.
get_upgrade_summary_for_cluster(ClusterId, State) ->
    case lists:filter(fun(Summary) ->
        Summary#upgrade_summary.cluster_id =:= ClusterId
    end, State#state.upgrade_summaries) of
        [Summary] -> {ok, Summary};
        [] -> {error, not_found}
    end.

%% @doc Generate upgrade summary from session
-spec generate_upgrade_summary(binary(), #metric_session{}, #state{}) -> record(upgrade_summary) | undefined.
generate_upgrade_summary(SessionId, Session, _State) ->
    %% Extract upgrade-related metrics
    UpgradeMetrics = lists:filter(fun(Metric) ->
        Metric#metric.metric_type =:= upgrade_progress
    end, Session#metric_session.metrics),

    case UpgradeMetrics of
        [] ->
            undefined;
        _ ->
            TotalNodes = length(lists:usort(lists:map(fun(M) -> M#metric.node_id end, UpgradeMetrics))),
            SuccessfulUpgrades = length(lists:filter(fun(M) -> M#metric.value >= 100.0 end, UpgradeMetrics)),
            FailedUpgrades = TotalNodes - SuccessfulUpgrades,
            TotalDuration = Session#metric_session.end_time - Session#metric_session.start_time,
            AverageUpgradeTime = TotalDuration / TotalNodes,
            ConsistencyScore = calculate_consistency_from_metrics(UpgradeMetrics),

            #upgrade_summary{
                cluster_id = Session#metric_session.cluster_id,
                upgrade_version = get_upgrade_version_from_metrics(UpgradeMetrics),
                total_nodes = TotalNodes,
                successful_upgrades = SuccessfulUpgrades,
                failed_upgrades = FailedUpgrades,
                total_duration = TotalDuration,
                average_upgrade_time = AverageUpgradeTime,
                consistency_score = ConsistencyScore,
                rollback_occurred = false,  % Would be tracked during actual upgrade
                failures = []  % Would collect actual failures
            }
    end.

%% @doc Export metrics in specified format
-spec export_metrics_format(binary(), #state{}) -> {ok, binary()} | {error, term()}.
export_metrics_format(json, State) ->
    MetricsData = build_metrics_data(State),
    {ok, jiffy:encode(MetricsData)};

export_metrics_format(prometheus, State) ->
    PrometheusData = build_prometheus_data(State),
    {ok, PrometheusData};

export_metrics_format(csv, State) ->
    CsvData = build_csv_data(State),
    {ok, CsvData}.

%% @doc Build metrics data structure
-spec build_metrics_data(#state{}) -> map().
build_metrics_data(State) ->
    #{
        clusters => build_clusters_data(State),
        sessions => build_sessions_data(State),
        upgrade_summaries => build_summaries_data(State)
    }.

%% @doc Get active clusters
-spec get_active_clusters() -> [binary()].
get_active_clusters() ->
    %% This would query the node orchestrator for active clusters
    [].  % Simplified

%% @doc Simulated metric collection functions
-spec get_cpu_usage(binary()) -> float().
get_cpu_usage(_ClusterId) ->
    25.5 + math:random() * 10.0.

-spec get_memory_usage(binary()) -> integer().
get_memory_usage(_ClusterId) ->
    1024 * 1024 * 1024 + trunc(math:random() * 1024 * 1024 * 512).

-spec get_process_count(binary()) -> integer().
get_process_count(_ClusterId) ->
    100 + trunc(math:random() * 50).

-spec get_network_io(binary()) -> float().
get_network_io(_ClusterId) ->
    1024.0 + math:random() * 512.0.

-spec get_disk_io(binary()) -> float().
get_disk_io(_ClusterId) ->
    2048.0 + math:random() * 1024.0.

-spec get_health_status(binary()) -> float().
get_health_status(_ClusterId) ->
    1.0.

-spec get_upgrade_version_from_metrics([record(metric)]) -> binary().
get_upgrade_version_from_metrics(_Metrics) ->
    <<"2.0.0">>.  % Would extract from actual metrics

-spec calculate_consistency_from_metrics([record(metric)]) -> float().
calculate_consistency_from_metrics(_Metrics) ->
    95.5 + math:random() * 4.5.

%% @doc Generate unique session ID
-spec generate_session_id() -> binary().
generate_session_id() ->
    Now = erlang:system_time(millisecond),
    <<"session_", (integer_to_binary(Now))/binary>>.

%% @doc Build clusters data for export
-spec build_clusters_data(#state{}) -> map().
build_clusters_data(State) ->
    %% This would build structured cluster data
    #{}.  % Simplified

%% @doc Build sessions data for export
-spec build_sessions_data(#state{}) -> map().
build_sessions_data(State) ->
    maps:map(fun(_SessionId, Session) ->
        #{
            cluster_id => Session#metric_session.cluster_id,
            start_time => Session#metric_session.start_time,
            end_time => Session#metric_session.end_time,
            status => Session#metric_session.status,
            metrics_count => length(Session#metric_session.metrics)
        }
    end, State#state.sessions).

%% @doc Build summaries data for export
-spec build_summaries_data(#state{}) -> map().
build_summaries_data(State) ->
    lists:map(fun(Summary) ->
        #{
            cluster_id => Summary#upgrade_summary.cluster_id,
            upgrade_version => Summary#upgrade_summary.upgrade_version,
            total_nodes => Summary#upgrade_summary.total_nodes,
            successful_upgrades => Summary#upgrade_summary.successful_upgrades,
            failed_upgrades => Summary#upgrade_summary.failed_upgrades,
            total_duration => Summary#upgrade_summary.total_duration,
            average_upgrade_time => Summary#upgrade_summary.average_upgrade_time,
            consistency_score => Summary#upgrade_summary.consistency_score,
            rollback_occurred => Summary#upgrade_summary.rollback_occurred
        }
    end, State#state.upgrade_summaries).

%% @doc Build Prometheus format data
-spec build_prometheus_data(#state{}) -> binary().
build_prometheus_data(_State) ->
    %% This would build Prometheus metrics format
    <<>>.  % Simplified

%% @doc Build CSV format data
-spec build_csv_data(#state{}) -> binary().
build_csv_data(_State) ->
    %% This would build CSV format
    <<>>.  % Simplified

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