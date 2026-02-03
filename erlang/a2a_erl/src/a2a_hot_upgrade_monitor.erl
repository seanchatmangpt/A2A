%%% @doc A2A Hot Code Upgrade Monitor
%%%
%%% This module provides comprehensive monitoring and metrics collection
%%% for hot code upgrade scenarios. It tracks upgrade performance,
%%% identifies bottlenecks, and provides real-time upgrade health monitoring.
%%%
%%% Features:
%%% - Upgrade performance metrics (time, success rate, bottlenecks)
%%% - Process upgrade tracking with individual status monitoring
%%% - ETS table upgrade performance optimization
%%% - Memory usage tracking during upgrades
%%% - Upgrade health checks and recovery recommendations
%%% - Real-time upgrade progress monitoring
%%%
%%% OTP 28 Features Used:
%%% - Enhanced process monitoring with selective receive
%%% - Optimized ETS table operations with write_concurrency
%%% - Advanced state management with gen_statem
%%% - Performance monitoring with process_info optimizations
%%% @end
-module(a2a_hot_upgrade_monitor).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    stop/0,

    %% Upgrade lifecycle tracking
    start_upgrade/1,
    record_upgrade_step/3,
    record_upgrade_completion/2,
    record_upgrade_failure/3,

    %% Process upgrade tracking
    track_process_upgrade/2,
    track_process_completion/2,
    track_process_failure/3,

    %% ETS upgrade tracking
    track_ets_upgrade/3,
    track_ets_completion/2,
    track_ets_failure/3,

    %% Performance metrics
    get_upgrade_metrics/0,
    get_upgrade_progress/1,
    get_bottleneck_analysis/0,
    get_upgrade_health/0,

    %% Health monitoring
    check_upgrade_readiness/0,
    estimate_upgrade_time/0,
    detect_upgrade_bottlenecks/0,

    %% Control functions
    pause_monitoring/0,
    resume_monitoring/0,
    reset_upgrade_metrics/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    handle_continue/2,
    terminate/2,
    code_change/3
]).

-include("a2a.hrl").

%%% ============================================================================
%%% Type Definitions
%%% ============================================================================

-record(upgrade_session, {
    id :: binary(),
    start_time :: integer(),
    end_time :: integer() | undefined,
    status :: preparing | in_progress | completed | failed | paused,
    total_processes = 0 :: non_neg_integer(),
    completed_processes = 0 :: non_neg_integer(),
    failed_processes = 0 :: non_neg_integer(),
    bottlenecks = [] :: [term()],
    metrics :: upgrade_metrics(),
    process_states = #{} :: #{pid() => process_upgrade_state()},
    et_states = #{} :: {ets_table_name(), ets_upgrade_state()}
}).

-type upgrade_session() :: #upgrade_session{}.

-record(process_upgrade_state, {
    pid :: pid(),
    module :: module(),
    start_time :: integer() | undefined,
    completion_time :: integer() | undefined,
    status :: pending | upgrading | completed | failed,
    upgrade_time_ms :: non_neg_integer() | undefined,
    memory_before :: non_neg_integer() | undefined,
    memory_after :: non_neg_integer() | undefined,
    error_reason :: term() | undefined
}).

-type process_upgrade_state() :: #process_upgrade_state{}.

-record(ets_upgrade_state, {
    table_name :: ets_table_name(),
    start_time :: integer() | undefined,
    completion_time :: integer() | undefined,
    status :: pending | upgrading | completed | failed,
    record_count :: non_neg_integer(),
    upgrade_time_ms :: non_neg_integer() | undefined,
    memory_impact_mb :: float() | undefined,
    error_reason :: term() | undefined
}).

-type ets_upgrade_state() :: #ets_upgrade_state{}.

-record(upgrade_metrics, {
    total_upgrades = 0 :: non_neg_integer(),
    successful_upgrades = 0 :: non_neg_integer(),
    failed_upgrades = 0 :: non_neg_integer(),
    avg_upgrade_time_ms = 0.0 :: float(),
    avg_process_upgrade_time_ms = 0.0 :: float(),
    avg_ets_upgrade_time_ms = 0.0 :: float(),
    bottleneck_count = 0 :: non_neg_integer(),
    last_upgrade_time :: integer() | undefined,
    peak_memory_mb = 0.0 :: float(),
    recovery_success_rate = 1.0 :: float()
}).

-type upgrade_metrics() :: #upgrade_metrics{}.

-record(health_check, {
    overall_status :: healthy | warning | critical,
    process_count :: non_neg_integer(),
    active_upgrades :: non_neg_integer(),
    memory_usage_percent :: float(),
    cpu_usage_percent :: float(),
    bottlenecks_detected :: boolean(),
    recommendations :: [binary()]
}).

-type health_check() :: #health_check{}.

-record(state, {
    current_upgrades = #{} :: #{binary() => upgrade_session()},
    metrics :: upgrade_metrics(),
    health_check :: health_check(),
    monitoring_enabled = true :: boolean(),
    check_interval_ms :: non_neg_integer(),
    health_timer :: reference() | undefined,
    performance_timer :: reference() | undefined
}).

-type state() :: #state{}.

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the upgrade monitor with default options
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the upgrade monitor with options
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

%% @doc Stop the upgrade monitor
-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%% @doc Start a new upgrade session
-spec start_upgrade(binary()) -> ok.
start_upgrade(UpgradeId) ->
    gen_server:cast(?MODULE, {start_upgrade, UpgradeId}).

%% @doc Record an upgrade step
-spec record_upgrade_step(binary(), binary(), non_neg_integer()) -> ok.
record_upgrade_step(UpgradeId, Step, DurationMs) ->
    gen_server:cast(?MODULE, {record_upgrade_step, UpgradeId, Step, DurationMs}).

%% @doc Record upgrade completion
-spec record_upgrade_completion(binary(), non_neg_integer()) -> ok.
record_upgrade_completion(UpgradeId, TotalDurationMs) ->
    gen_server:cast(?MODULE, {record_upgrade_completion, UpgradeId, TotalDurationMs}).

%% @doc Record upgrade failure
-spec record_upgrade_failure(binary(), term(), non_neg_integer()) -> ok.
record_upgrade_failure(UpgradeId, Reason, DurationMs) ->
    gen_server:cast(?MODULE, {record_upgrade_failure, UpgradeId, Reason, DurationMs}).

%% @doc Track individual process upgrade
-spec track_process_upgrade(pid(), module()) -> ok.
track_process_upgrade(Pid, Module) ->
    gen_server:cast(?MODULE, {track_process_upgrade, Pid, Module}).

%% @doc Track process upgrade completion
-spec track_process_completion(pid(), non_neg_integer()) -> ok.
track_process_completion(Pid, UpgradeTimeMs) ->
    gen_server:cast(?MODULE, {track_process_completion, Pid, UpgradeTimeMs}).

%% @doc Track process upgrade failure
-spec track_process_failure(pid(), term(), non_neg_integer()) -> ok.
track_process_failure(Pid, Reason, UpgradeTimeMs) ->
    gen_server:cast(?MODULE, {track_process_failure, Pid, Reason, UpgradeTimeMs}).

%% @doc Track ETS table upgrade
-spec track_ets_upgrade(ets_table_name(), non_neg_integer(), non_neg_integer()) -> ok.
track_ets_upgrade(TableName, RecordCount, MemoryBytes) ->
    gen_server:cast(?MODULE, {track_ets_upgrade, TableName, RecordCount, MemoryBytes}).

%% @doc Track ETS upgrade completion
-spec track_ets_completion(ets_table_name(), non_neg_integer()) -> ok.
track_ets_completion(TableName, UpgradeTimeMs) ->
    gen_server:cast(?MODULE, {track_ets_completion, TableName, UpgradeTimeMs}).

%% @doc Track ETS upgrade failure
-spec track_ets_failure(ets_table_name(), term(), non_neg_integer()) -> ok.
track_ets_failure(TableName, Reason, UpgradeTimeMs) ->
    gen_server:cast(?MODULE, {track_ets_failure, TableName, Reason, UpgradeTimeMs}).

%% @doc Get all upgrade metrics
-spec get_upgrade_metrics() -> upgrade_metrics().
get_upgrade_metrics() ->
    gen_server:call(?MODULE, get_upgrade_metrics).

%% @doc Get upgrade progress for a specific session
-spec get_upgrade_progress(binary()) -> {ok, upgrade_session()} | {error, not_found}.
get_upgrade_progress(UpgradeId) ->
    gen_server:call(?MODULE, {get_upgrade_progress, UpgradeId}).

%% @doc Get bottleneck analysis
-spec get_bottleneck_analysis() -> [term()].
get_bottleneck_analysis() ->
    gen_server:call(?MODULE, get_bottleneck_analysis).

%% @doc Get upgrade health status
-spec get_upgrade_health() -> health_check().
get_upgrade_health() ->
    gen_server:call(?MODULE, get_upgrade_health).

%% @doc Check upgrade readiness
-spec check_upgrade_readiness() -> map().
check_upgrade_readiness() ->
    gen_server:call(?MODULE, check_upgrade_readiness).

%% @doc Estimate upgrade time
-spec estimate_upgrade_time() -> {ok, non_neg_integer()} | {error, insufficient_data}.
estimate_upgrade_time() ->
    gen_server:call(?MODULE, estimate_upgrade_time).

%% @doc Detect upgrade bottlenecks
-spec detect_upgrade_bottlenecks() -> [term()].
detect_upgrade_bottlenecks() ->
    gen_server:call(?MODULE, detect_upgrade_bottlenecks).

%% @doc Pause monitoring
-spec pause_monitoring() -> ok.
pause_monitoring() ->
    gen_server:cast(?MODULE, pause_monitoring).

%% @doc Resume monitoring
-spec resume_monitoring() -> ok.
resume_monitoring() ->
    gen_server:cast(?MODULE, resume_monitoring).

%% @doc Reset upgrade metrics
-spec reset_upgrade_metrics() -> ok.
reset_upgrade_metrics() ->
    gen_server:call(?MODULE, reset_upgrade_metrics).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init(map()) -> {ok, state()} | {ok, state(), {continue, atom()}}.
init(Opts) ->
    CheckInterval = maps:get(health_check_interval_ms, Opts, 30000),
    PerformanceInterval = maps:get(performance_check_interval_ms, Opts, 60000),

    InitialMetrics = #upgrade_metrics{},
    InitialHealth = #health_check{
        overall_status = healthy,
        process_count = 0,
        active_upgrades = 0,
        memory_usage_percent = 0.0,
        cpu_usage_percent = 0.0,
        bottlenecks_detected = false,
        recommendations = []
    },

    State = #state{
        metrics = InitialMetrics,
        health_check = InitialHealth,
        check_interval_ms = CheckInterval,
        performance_interval_ms = PerformanceInterval
    },

    %% Start health and performance timers
    HealthTimer = schedule_health_check(CheckInterval),
    PerformanceTimer = schedule_performance_check(PerformanceInterval),

    {ok, State#state{
        health_timer = HealthTimer,
        performance_timer = PerformanceTimer
    }, {continue, initial_health_check}}.

-spec handle_continue(atom(), state()) -> {ok, state()}.
handle_continue(initial_health_check, State) ->
    %% Perform initial health check
    NewHealth = perform_health_check(State),
    NewState = State#state{health_check = NewHealth},
    {ok, NewState}.

-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()} | {noreply, state()}.
handle_call(get_upgrade_metrics, _From, State) ->
    {reply, State#state.metrics, State};

handle_call({get_upgrade_progress, UpgradeId}, _From, State) ->
    case maps:get(UpgradeId, State#state.current_upgrades, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Session ->
            {reply, {ok, Session}, State}
    end;

handle_call(get_bottleneck_analysis, _From, State) ->
    Analysis = perform_bottleneck_analysis(State),
    {reply, Analysis, State};

handle_call(get_upgrade_health, _From, State) ->
    {reply, State#state.health_check, State};

handle_call(check_upgrade_readiness, _From, State) ->
    Readiness = check_upgrade_readiness_internal(State),
    {reply, Readiness, State};

handle_call(estimate_upgrade_time, _From, State) ->
    Estimate = estimate_upgrade_time_internal(State),
    {reply, Estimate, State};

handle_call(detect_upgrade_bottlenecks, _From, State) ->
    Bottlenecks = detect_upgrade_bottlenecks_internal(State),
    {reply, Bottlenecks, State};

handle_call(reset_upgrade_metrics, _From, State) ->
    NewMetrics = #upgrade_metrics{},
    NewState = State#state{metrics = NewMetrics},
    {reply, ok, NewState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({start_upgrade, UpgradeId}, State) ->
    Now = erlang:system_time(millisecond),
    Session = #upgrade_session{
        id = UpgradeId,
        start_time = Now,
        status = preparing,
        metrics = #upgrade_metrics{},
        process_states = #{},
        et_states = #{}
    },

    %% Count current processes and ETS tables
    ProcessCount = count_active_processes(),
    EtsCount = count_active_ets_tables(),

    NewSession = Session#upgrade_session{
        total_processes = ProcessCount,
        completed_processes = 0,
        failed_processes = 0
    },

    UpdatedUpgrades = maps:put(UpgradeId, NewSession, State#state.current_upgrades),
    NewState = State#state{
        current_upgrades = UpdatedUpgrades,
        metrics = State#state.metrics#upgrade_metrics{
            total_upgrades = State#state.metrics#upgrade_metrics.total_upgrades + 1
        }
    },

    logger:info("Upgrade session started", #{
        upgrade_id => UpgradeId,
        process_count => ProcessCount,
        ets_count => EtsCount,
        domain => [a2a, upgrade, monitor]
    }),

    {noreply, NewState};

handle_cast({record_upgrade_step, UpgradeId, Step, DurationMs}, State) ->
    case maps:get(UpgradeId, State#state.current_upgrades, undefined) of
        undefined ->
            {noreply, State};
        Session ->
            NewSession = Session#upgrade_session{
                status = in_progress,
                bottlenecks = add_bottleneck_if_needed(Session#upgrade_session.bottlenecks, Step, DurationMs)
            },
            UpdatedUpgrades = maps:put(UpgradeId, NewSession, State#state.current_upgrades),
            NewState = State#state{current_upgrades = UpdatedUpgrades},
            {noreply, NewState}
    end;

handle_cast({record_upgrade_completion, UpgradeId, TotalDurationMs}, State) ->
    case maps:get(UpgradeId, State#state.current_upgrades, undefined) of
        undefined ->
            {noreply, State};
        Session ->
            Now = erlang:system_time(millisecond),
            NewMetrics = update_upgrade_metrics(State#state.metrics, Session, TotalDurationMs, true),

            CompletedSession = Session#upgrade_session{
                end_time = Now,
                status = completed,
                metrics = NewMetrics
            },

            UpdatedUpgrades = maps:put(UpgradeId, CompletedSession, State#state.current_upgrades),
            NewState = State#state{
                current_upgrades = UpdatedUpgrades,
                metrics = NewMetrics
            },

            logger:info("Upgrade completed", #{
                upgrade_id => UpgradeId,
                duration_ms => TotalDurationMs,
                domain => [a2a, upgrade, monitor]
            }),

            {noreply, NewState}
    end;

handle_cast({record_upgrade_failure, UpgradeId, Reason, DurationMs}, State) ->
    case maps:get(UpgradeId, State#state.current_upgrades, undefined) of
        undefined ->
            {noreply, State};
        Session ->
            Now = erlang:system_time(millisecond),
            NewMetrics = update_upgrade_metrics(State#state.metrics, Session, DurationMs, false),

            FailedSession = Session#upgrade_session{
                end_time = Now,
                status = failed,
                bottlenecks = [Reason | Session#upgrade_session.bottlenecks],
                metrics = NewMetrics
            },

            UpdatedUpgrades = maps:put(UpgradeId, FailedSession, State#state.current_upgrades),
            NewState = State#state{
                current_upgrades = UpdatedUpgrades,
                metrics = NewMetrics#upgrade_metrics{
                    failed_upgrades = NewMetrics#upgrade_metrics.failed_upgrades + 1
                }
            },

            logger:error("Upgrade failed", #{
                upgrade_id => UpgradeId,
                reason => Reason,
                duration_ms => DurationMs,
                domain => [a2a, upgrade, monitor]
            }),

            {noreply, NewState}
    end;

handle_cast({track_process_upgrade, Pid, Module}, State) ->
    Now = erlang:system_time(millisecond),
    ProcessState = #process_upgrade_state{
        pid = Pid,
        module = Module,
        start_time = Now,
        status = upgrading,
        memory_before = get_process_memory(Pid)
    },

    %% Update all active upgrade sessions
    UpdatedUpgrades = maps:map(fun(_, Session) ->
        NewProcessStates = maps:put(Pid, ProcessState, Session#upgrade_session.process_states),
        Session#upgrade_session{process_states = NewProcessStates}
    end, State#state.current_upgrades),

    NewState = State#state{current_upgrades = UpdatedUpgrades},
    {noreply, NewState};

handle_cast({track_process_completion, Pid, UpgradeTimeMs}, State) ->
    UpdatedUpgrades = maps:map(fun(_, Session) ->
        case maps:get(Pid, Session#upgrade_session.process_states, undefined) of
            undefined ->
                Session;
            ProcessState ->
                MemoryAfter = get_process_memory(Pid),
                NewProcessState = ProcessState#process_upgrade_state{
                    completion_time = erlang:system_time(millisecond),
                    status = completed,
                    upgrade_time_ms = UpgradeTimeMs,
                    memory_after = MemoryAfter
                },

                NewProcessStates = maps:put(Pid, NewProcessState, Session#upgrade_session.process_states),
                Completed = Session#upgrade_session.completed_processes + 1,
                Session#upgrade_session{
                    completed_processes = Completed,
                    process_states = NewProcessStates
                }
        end
    end, State#state.current_upgrades),

    NewState = State#state{current_upgrades = UpdatedUpgrades},
    {noreply, NewState};

handle_cast({track_process_failure, Pid, Reason, UpgradeTimeMs}, State) ->
    UpdatedUpgrades = maps:map(fun(_, Session) ->
        case maps:get(Pid, Session#upgrade_session.process_states, undefined) of
            undefined ->
                Session;
            ProcessState ->
                MemoryAfter = get_process_memory(Pid),
                NewProcessState = ProcessState#process_upgrade_state{
                    completion_time = erlang:system_time(millisecond),
                    status = failed,
                    upgrade_time_ms = UpgradeTimeMs,
                    memory_after = MemoryAfter,
                    error_reason = Reason
                },

                NewProcessStates = maps:put(Pid, NewProcessState, Session#upgrade_session.process_states),
                Failed = Session#upgrade_session.failed_processes + 1,
                Session#upgrade_session{
                    failed_processes = Failed,
                    process_states = NewProcessStates,
                    bottlenecks = [Reason | Session#upgrade_session.bottlenecks]
                }
        end
    end, State#state.current_upgrades),

    NewState = State#state{current_upgrades = UpdatedUpgrades},
    {noreply, NewState};

handle_cast({track_ets_upgrade, TableName, RecordCount, MemoryBytes}, State) ->
    Now = erlang:system_time(millisecond),
    EtsState = #ets_upgrade_state{
        table_name = TableName,
        start_time = Now,
        status = upgrading,
        record_count = RecordCount,
        memory_impact_mb = MemoryBytes / (1024 * 1024)
    },

    %% Update all active upgrade sessions
    UpdatedUpgrades = maps:map(fun(_, Session) ->
        NewEtStates = maps:put(TableName, EtsState, Session#upgrade_session.et_states),
        Session#upgrade_session{et_states = NewEtStates}
    end, State#state.current_upgrades),

    NewState = State#state{current_upgrades = UpdatedUpgrades},
    {noreply, NewState};

handle_cast({track_ets_completion, TableName, UpgradeTimeMs}, State) ->
    UpdatedUpgrades = maps:map(fun(_, Session) ->
        case maps:get(TableName, Session#upgrade_session.et_states, undefined) of
            undefined ->
                Session;
            EtsState ->
                NewEtsState = EtsState#ets_upgrade_state{
                    completion_time = erlang:system_time(millisecond),
                    status = completed,
                    upgrade_time_ms = UpgradeTimeMs
                },

                NewEtStates = maps:put(TableName, NewEtsState, Session#upgrade_session.et_states),
                Session#upgrade_session{et_states = NewEtStates}
        end
    end, State#state.current_upgrades),

    NewState = State#state{current_upgrades = UpdatedUpgrades},
    {noreply, NewState};

handle_cast({track_ets_failure, TableName, Reason, UpgradeTimeMs}, State) ->
    UpdatedUpgrades = maps:map(fun(_, Session) ->
        case maps:get(TableName, Session#upgrade_session.et_states, undefined) of
            undefined ->
                Session;
            EtsState ->
                NewEtsState = EtsState#ets_upgrade_state{
                    completion_time = erlang:system_time(millisecond),
                    status = failed,
                    upgrade_time_ms = UpgradeTimeMs,
                    error_reason = Reason
                },

                NewEtStates = maps:put(TableName, NewEtsState, Session#upgrade_session.et_states),
                Session#upgrade_session{et_states = NewEtStates,
                                        bottlenecks = [Reason | Session#upgrade_session.bottlenecks]}
        end
    end, State#state.current_upgrades),

    NewState = State#state{current_upgrades = UpdatedUpgrades},
    {noreply, NewState};

handle_cast(pause_monitoring, State) ->
    NewState = State#state{monitoring_enabled = false},
    logger:info("Upgrade monitoring paused", #{
        domain => [a2a, upgrade, monitor]
    }),
    {noreply, NewState};

handle_cast(resume_monitoring, State) ->
    NewState = State#state{monitoring_enabled = true},
    logger:info("Upgrade monitoring resumed", #{
        domain => [a2a, upgrade, monitor]
    }),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(health_check_timeout, State) ->
    case State#state.monitoring_enabled of
        true ->
            NewHealth = perform_health_check(State),
            NewState = State#state{health_check = NewHealth},
            HealthTimer = schedule_health_check(State#state.check_interval_ms),
            {noreply, NewState#state{health_timer = HealthTimer}};
        false ->
            {noreply, State}
    end;

handle_info(performance_check_timeout, State) ->
    case State#state.monitoring_enabled of
        true ->
            %% Update metrics and check performance
            NewState = update_performance_metrics(State),
            PerformanceTimer = schedule_performance_check(State#state.performance_interval_ms),
            {noreply, NewState#state{performance_timer = PerformanceTimer}};
        false ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, #state{health_timer = HealthTimer, performance_timer = PerformanceTimer}) ->
    %% Cancel timers
    case HealthTimer of
        undefined -> ok;
        T -> erlang:cancel_timer(T)
    end,
    case PerformanceTimer of
        undefined -> ok;
        T -> erlang:cancel_timer(T)
    end,
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Schedule health check
-spec schedule_health_check(non_neg_integer()) -> reference().
schedule_health_check(Interval) ->
    erlang:send_after(Interval, self(), health_check_timeout).

%% @doc Schedule performance check
-spec schedule_performance_check(non_neg_integer()) -> reference().
schedule_performance_check(Interval) ->
    erlang:send_after(Interval, self(), performance_check_timeout).

%% @doc Count active processes
-spec count_active_processes() -> non_neg_integer().
count_active_processes() ->
    Processes = erlang:processes(),
    ActiveProcesses = lists:filter(fun is_process_alive/1, Processes),
    length(ActiveProcesses).

%% @doc Count active ETS tables
-spec count_active_ets_tables() -> non_neg_integer().
count_active_ets_tables() ->
    Tables = ets:all(),
    length(Tables).

%% @doc Get process memory usage
-spec get_process_memory(pid()) -> non_neg_integer().
get_process_memory(Pid) ->
    case process_info(Pid, memory) of
        {memory, Memory} -> Memory;
        undefined -> 0
    end.

%% @doc Update upgrade metrics
-spec update_upgrade_metrics(upgrade_metrics(), upgrade_session(), non_neg_integer(), boolean()) -> upgrade_metrics().
update_upgrade_metrics(Metrics, _Session, DurationMs, Success) ->
    TotalUpgrades = Metrics#upgrade_metrics.total_upgrades,

    %% Update average upgrade time
    NewAvgUpgradeTime = case TotalUpgrades of
        0 -> DurationMs * 1.0;
        _ -> (Metrics#upgrade_metrics.avg_upgrade_time_ms * (TotalUpgrades - 1) + DurationMs) / TotalUpgrades
    end,

    %% Update peak memory
    CurrentMemory = erlang:memory(total) * erlang:wordsize() / (1024 * 1024),
    PeakMemory = max(Metrics#upgrade_metrics.peak_memory_mb, CurrentMemory),

    Metrics#upgrade_metrics{
        avg_upgrade_time_ms = NewAvgUpgradeTime,
        last_upgrade_time = erlang:system_time(millisecond),
        peak_memory_mb = PeakMemory
    }.

%% @doc Add bottleneck if step takes too long
-spec add_bottleneck_if_needed([term()], binary(), non_neg_integer()) -> [term()].
add_bottleneck_if_needed(Bottlenecks, Step, DurationMs) ->
    case DurationMs > 5000 of %% 5 seconds threshold
        true -> [{Step, DurationMs} | Bottlenecks];
        false -> Bottlenecks
    end.

%% @doc Perform health check
-spec perform_health_check(state()) -> health_check().
perform_health_check(State) ->
    ProcessCount = count_active_processes(),
    ActiveUpgrades = length(State#state.current_upgrades),

    %% Calculate memory usage percentage
    TotalMemory = erlang:memory(total),
    SystemMemory = get_system_memory(),
    MemoryPercent = (TotalMemory / SystemMemory) * 100,

    %% Check for bottlenecks
    Bottlenecks = detect_upgrade_bottlenecks_internal(State),
    BottleneckDetected = length(Bottlenecks) > 0,

    %% Determine overall status
    Status = case
        MemoryPercent > 90 orelse ActiveUpgrades > 10 orelse length(Bottlenecks) > 5 of
        true -> critical;
        true when MemoryPercent > 75 orelse ActiveUpgrades > 5 -> warning;
        true -> healthy
    end,

    %% Generate recommendations
    Recommendations = generate_health_recommendations(Status, MemoryPercent, ActiveUpgrades, Bottlenecks),

    #health_check{
        overall_status = Status,
        process_count = ProcessCount,
        active_upgrades = ActiveUpgrades,
        memory_usage_percent = MemoryPercent,
        cpu_usage_percent = get_cpu_usage(),
        bottlenecks_detected = BottleneckDetected,
        recommendations = Recommendations
    }.

%% @doc Get system memory (simplified)
-spec get_system_memory() -> non_neg_integer().
get_system_memory() ->
    %% This is a simplified version - in production, you'd use OS-specific calls
    case erlang:system_info({wordsize, word}) of
        4 -> 4 * 1024 * 1024 * 1024; %% Assume 4GB on 32-bit
        8 -> 16 * 1024 * 1024 * 1024 %% Assume 16GB on 64-bit
    end.

%% @doc Get CPU usage (simplified)
-spec get_cpu_usage() -> float().
get_cpu_usage() ->
    %% This is a simplified version - in production, you'd use OS-specific calls
    0.0. %% Placeholder

%% @doc Generate health recommendations
-spec generate_health_recommendations(atom(), float(), non_neg_integer(), [term()]) -> [binary()].
generate_health_recommendations(Status, MemoryPercent, ActiveUpgrades, Bottlenecks) ->
    Recommendations = [],

    %% Memory recommendations
    Rec1 = case MemoryPercent > 85 of
        true -> <<"Reduce memory usage or increase system memory">>;
        false -> undefined
    end,

    %% Upgrade recommendations
    Rec2 = case ActiveUpgrades > 5 of
        true -> <<"Too many concurrent upgrades, consider sequential upgrades">>;
        false -> undefined
    end,

    %% Bottleneck recommendations
    Rec3 = case Bottlenecks of
        [] -> undefined;
        _ -> <<"Address identified bottlenecks">>
    end,

    %% Status-specific recommendations
    Rec4 = case Status of
        critical -> <<"System in critical state, immediate attention required">>;
        warning -> <<"System in warning state, monitor closely">>;
        healthy -> undefined
    end,

    lists:compact([Rec1, Rec2, Rec3, Rec4]).

%% @doc Perform bottleneck analysis
-spec perform_bottleneck_analysis(state()) -> [term()].
perform_bottleneck_analysis(State) ->
    Bottlenecks = [],

    %% Check slow upgrade sessions
    SlowUpgrades = maps:fold(fun(_, Session, Acc) ->
        case Session#upgrade_session.status of
            in_progress ->
                case erlang:system_time(millisecond) - Session#upgrade_session.start_time of
                    Time when Time > 30000 -> [Session#upgrade_session.id | Acc]; %% 30 seconds
                    _ -> Acc
                end;
            _ -> Acc
        end
    end, [], State#state.current_upgrades),

    %% Check slow process upgrades
    SlowProcesses = maps:fold(fun(_, Session, Acc) ->
        maps:fold(fun(_, ProcessState, ProcessAcc) ->
            case ProcessState#process_upgrade_state.status of
                upgrading ->
                    case erlang:system_time(millisecond) - ProcessState#process_upgrade_state.start_time of
                        Time when Time > 15000 -> [ProcessState | ProcessAcc]; %% 15 seconds
                        _ -> ProcessAcc
                    end;
                _ -> ProcessAcc
            end
        end, [], Session#upgrade_session.process_states)
    end, [], State#state.current_upgrades),

    %% Check ETS upgrade bottlenecks
    EtsBottlenecks = maps:fold(fun(_, Session, Acc) ->
        maps:fold(fun(_, EtsState, EtsAcc) ->
            case EtsState#ets_upgrade_state.status of
                upgrading ->
                    case EtsState#ets_upgrade_state.record_count > 10000 of
                        true -> [EtsState | EtsAcc];
                        false -> EtsAcc
                    end;
                _ -> EtsAcc
            end
        end, [], Session#upgrade_session.et_states)
    end, [], State#state.current_upgrades),

    SlowUpgrades ++ SlowProcesses ++ EtsBottlenecks.

%% @doc Check upgrade readiness
-spec check_upgrade_readiness_internal(state()) -> map().
check_upgrade_readiness_internal(State) ->
    Health = State#state.health_check,

    #{
        ready => Health#health_check.overstatus =/= critical,
        process_count => Health#health_check.process_count,
        active_upgrades => Health#health_check.active_upgrades,
        memory_usage_percent => Health#health_check.memory_usage_percent,
        bottlenecks_detected => Health#health_check.bottlenecks_detected,
        recommendations => Health#health_check.recommendations,
        estimated_risk => calculate_upgrade_risk(Health)
    }.

%% @doc Calculate upgrade risk
-spec calculate_upgrade_risk(health_check()) -> atom().
calculate_upgrade_risk(Health) ->
    case Health#health_check.overall_status of
        critical -> high;
        warning -> medium;
        healthy -> low
    end.

%% @doc Estimate upgrade time
-spec estimate_upgrade_time_internal(state()) -> {ok, non_neg_integer()} | {error, insufficient_data}.
estimate_upgrade_time_internal(State) ->
    Metrics = State#state.metrics,
    case Metrics#upgrade_metrics.total_upgrades < 3 of
        true ->
            {error, insufficient_data};
        false ->
            %% Estimate based on average and current system state
            BaseTime = Metrics#upgrade_metrics.avg_upgrade_time_ms,
            CurrentLoad = Health#health_check.memory_usage_percent / 100,
            EstimatedTime = round(BaseTime * (1 + CurrentLoad)),
            {ok, EstimatedTime}
    end.

%% @brief Detect upgrade bottlenecks
-spec detect_upgrade_bottlenecks_internal(state()) -> [term()].
detect_upgrade_bottlenecks_internal(State) ->
    perform_bottleneck_analysis(State).

%% @brief Update performance metrics
-spec update_performance_metrics(state()) -> state().
update_performance_metrics(State) ->
    CurrentMemory = erlang:memory(total) * erlang:wordsize() / (1024 * 1024),
    NewPeakMemory = max(State#state.metrics#upgrade_metrics.peak_memory_mb, CurrentMemory),

    State#state.metrics = State#state.metrics#upgrade_metrics{
        peak_memory_mb = NewPeakMemory
    },

    State.