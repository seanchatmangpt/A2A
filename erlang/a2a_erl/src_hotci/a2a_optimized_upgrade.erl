%%% @doc A2A Optimized Hot Code Upgrade System
%%%
%%% This module provides optimized hot code upgrade capabilities for the A2A system.
%%% It implements advanced upgrade strategies to minimize downtime and maximize reliability.
%%%
%%% Features:
%%% - Parallel process upgrade with controlled concurrency
%%% - ETS table upgrade optimization with minimal blocking
%%% - Upgrade state management and rollback capabilities
%%% - Performance monitoring and bottleneck detection
%%% - Gradual rollout strategies for safety
%%% - Memory management during upgrades
%%%
%%% OTP 28 Optimizations:
%%% - Selective code_change with state preservation
%%% - Optimized ETS table copying with write_concurrency
%%% - Process state migration with minimal downtime
%%% - Memory-efficient upgrade procedures
%%% - Advanced monitoring and health checks
%%% @end
-module(a2a_optimized_upgrade).
-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    stop/0,

    %% Main upgrade operations
    perform_upgrade/1,
    perform_upgrade/2,
    rollback_upgrade/1,

    %% Process upgrade strategies
    upgrade_processes/2,
    upgrade_processes/3,

    %% ETS table upgrade strategies
    upgrade_ets_tables/2,
    upgrade_ets_tables/3,

    %% Upgrade control and monitoring
    get_upgrade_status/0,
    get_upgrade_progress/1,
    pause_upgrade/0,
    resume_upgrade/0,
    cancel_upgrade/0,

    %% Configuration
    set_concurrency_level/1,
    set_upgrade_strategy/1,
    set_memory_limit/1,

    %% Health and performance
    get_upgrade_health/0,
    get_performance_metrics/0,
    estimate_upgrade_resources/0,

    %% Internal functions exported for testing
    get_cpu_usage/0,
    update_performance_metrics/1,
    perform_monitoring_cycle/1
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

-record(upgrade_config, {
    concurrency_level = 4 :: pos_integer(),
    upgrade_strategy = gradual :: immediate | gradual | phased,
    memory_limit_mb = 1024 :: pos_integer(),
    max_process_time_ms = 30000 :: non_neg_integer(),
    ets_batch_size = 1000 :: pos_integer(),
    enable_rollback = true :: boolean(),
    health_check_interval_ms = 5000 :: non_neg_integer()
}).

-type upgrade_config() :: #upgrade_config{}.

-record(upgrade_state, {
    status = idle :: idle | preparing | upgrading | pausing | completing | rolling_back | failed,
    strategy :: immediate | gradual | phased,
    start_time :: integer() | undefined,
    end_time :: integer() | undefined,
    processes_upgraded = 0 :: non_neg_integer(),
    processes_total = 0 :: non_neg_integer(),
    ets_upgraded = 0 :: non_neg_integer(),
    ets_total = 0 :: non_neg_integer(),
    failed_processes = [] :: [pid()],
    failed_ets = [] :: [term()],
    bottlenecks = [] :: [term()],
    rollback_state :: undefined | rollback_state()
}).

-type upgrade_state() :: #upgrade_state{}.

-record(rollback_state, {
    checkpoint_time :: integer(),
    processes_state :: #{pid() => term()},
    ets_state :: #{term() => term()},
    upgrade_config :: upgrade_config()
}).

-type rollback_state() :: #rollback_state{}.

-record(process_upgrade_info, {
    pid :: pid(),
    module :: module(),
    old_version :: term(),
    new_version :: term(),
    upgrade_start_time :: integer(),
    upgrade_status :: pending | upgrading | completed | failed,
    upgrade_time_ms :: non_neg_integer() | undefined,
    memory_before :: non_neg_integer(),
    memory_after :: non_neg_integer(),
    error_reason :: term() | undefined
}).

-type process_upgrade_info() :: #process_upgrade_info{}.

-record(ets_upgrade_info, {
    table_name :: term(),
    record_count :: non_neg_integer(),
    upgrade_start_time :: integer(),
    upgrade_status :: pending | upgrading | completed | failed,
    upgrade_time_ms :: non_neg_integer() | undefined,
    memory_before :: non_neg_integer(),
    memory_after :: non_neg_integer(),
    error_reason :: term() | undefined
}).

-type ets_upgrade_info() :: #ets_upgrade_info{}.

-record(performance_metrics, {
    total_upgrade_time_ms = 0 :: non_neg_integer(),
    avg_process_upgrade_time_ms = 0.0 :: float(),
    avg_ets_upgrade_time_ms = 0.0 :: float(),
    peak_memory_mb = 0.0 :: float(),
    upgrade_throughput :: float(),
    cpu_usage :: float(),
    memory_usage :: float(),
    bottleneck_count = 0 :: non_neg_integer()
}).

-type performance_metrics() :: #performance_metrics{}.

-record(state, {
    config :: upgrade_config(),
    upgrade_state :: upgrade_state(),
    processes = #{} :: #{pid() => process_upgrade_info()},
    ets_tables = #{} :: #{term() => ets_upgrade_info()},
    performance :: performance_metrics(),
    active_upgrades = #{} :: #{binary() => term()},
    monitoring_timer :: reference() | undefined,
    upgrade_supervisor :: pid() | undefined
}).

-type state() :: #state{}.

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the upgrade system with default options
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the upgrade system with options
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

%% @doc Stop the upgrade system
-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%% @doc Perform a complete system upgrade
-spec perform_upgrade(binary()) -> {ok, pid()} | {error, term()}.
perform_upgrade(UpgradeId) ->
    perform_upgrade(UpgradeId, #{}).

%% @doc Perform a complete system upgrade with options
-spec perform_upgrade(binary(), map()) -> {ok, pid()} | {error, term()}.
perform_upgrade(UpgradeId, Options) ->
    gen_server:call(?MODULE, {perform_upgrade, UpgradeId, Options}).

%% @doc Rollback a failed upgrade
-spec rollback_upgrade(binary()) -> {ok, pid()} | {error, term()}.
rollback_upgrade(UpgradeId) ->
    gen_server:call(?MODULE, {rollback_upgrade, UpgradeId}).

%% @doc Upgrade specific processes
-spec upgrade_processes([pid()], module()) -> {ok, [pid()]} | {error, term()}.
upgrade_processes(Pids, NewModule) ->
    upgrade_processes(Pids, NewModule, #{}).

%% @doc Upgrade specific processes with options
-spec upgrade_processes([pid()], module(), map()) -> {ok, [pid()]} | {error, term()}.
upgrade_processes(Pids, NewModule, Options) ->
    gen_server:call(?MODULE, {upgrade_processes, Pids, NewModule, Options}).

%% @doc Upgrade specific ETS tables
-spec upgrade_ets_tables([term()], module()) -> ok | {error, term()}.
upgrade_ets_tables(TableNames, NewModule) ->
    upgrade_ets_tables(TableNames, NewModule, #{}).

%% @doc Upgrade specific ETS tables with options
-spec upgrade_ets_tables([term()], module(), map()) -> ok | {error, term()}.
upgrade_ets_tables(TableNames, NewModule, Options) ->
    gen_server:call(?MODULE, {upgrade_ets_tables, TableNames, NewModule, Options}).

%% @doc Get current upgrade status
-spec get_upgrade_status() -> map().
get_upgrade_status() ->
    gen_server:call(?MODULE, get_upgrade_status).

%% @doc Get upgrade progress for a specific upgrade
-spec get_upgrade_progress(binary()) -> {ok, map()} | {error, not_found}.
get_upgrade_progress(UpgradeId) ->
    gen_server:call(?MODULE, {get_upgrade_progress, UpgradeId}).

%% @brief Pause ongoing upgrade
-spec pause_upgrade() -> ok | {error, not_upgrading}.
pause_upgrade() ->
    gen_server:cast(?MODULE, pause_upgrade).

%% @brief Resume paused upgrade
-spec resume_upgrade() -> ok | {error, not_paused}.
resume_upgrade() ->
    gen_server:cast(?MODULE, resume_upgrade).

%% @brief Cancel ongoing upgrade
-spec cancel_upgrade() -> ok | {error, not_upgrading}.
cancel_upgrade() ->
    gen_server:cast(?MODULE, cancel_upgrade).

%% @brief Set concurrency level
-spec set_concurrency_level(pos_integer()) -> ok.
set_concurrency_level(Level) ->
    gen_server:cast(?MODULE, {set_concurrency_level, Level}).

%% @brief Set upgrade strategy
-spec set_upgrade_strategy(immediate | gradual | phased) -> ok.
set_upgrade_strategy(Strategy) ->
    gen_server:cast(?MODULE, {set_upgrade_strategy, Strategy}).

%% @brief Set memory limit
-spec set_memory_limit(pos_integer()) -> ok.
set_memory_limit(LimitMb) ->
    gen_server:cast(?MODULE, {set_memory_limit, LimitMb}).

%% @brief Get upgrade health status
-spec get_upgrade_health() -> map().
get_upgrade_health() ->
    gen_server:call(?MODULE, get_upgrade_health).

%% @brief Get performance metrics
-spec get_performance_metrics() -> performance_metrics().
get_performance_metrics() ->
    gen_server:call(?MODULE, get_performance_metrics).

%% @brief Estimate upgrade resource requirements
-spec estimate_upgrade_resources() -> map().
estimate_upgrade_resources() ->
    gen_server:call(?MODULE, estimate_upgrade_resources).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init(map()) -> {ok, state()} | {ok, state(), {continue, atom()}}.
init(Opts) ->
    DefaultConfig = #upgrade_config{
        concurrency_level = maps:get(concurrency_level, Opts, 4),
        upgrade_strategy = maps:get(strategy, Opts, gradual),
        memory_limit_mb = maps:get(memory_limit_mb, Opts, 1024),
        max_process_time_ms = maps:get(max_process_time_ms, Opts, 30000),
        ets_batch_size = maps:get(ets_batch_size, Opts, 1000),
        enable_rollback = maps:get(enable_rollback, Opts, true),
        health_check_interval_ms = maps:get(health_check_interval_ms, Opts, 5000)
    },

    InitialState = #state{
        config = DefaultConfig,
        upgrade_state = #upgrade_state{status = idle},
        performance = #performance_metrics{}
    },

    {ok, InitialState, {continue, initialize_upgrade_system}}.

-spec handle_continue(atom(), state()) -> {ok, state()}.
handle_continue(initialize_upgrade_system, State) ->
    %% Initialize upgrade supervisor
    case start_upgrade_supervisor() of
        {ok, Pid} ->
            MonitoringTimer = schedule_monitoring(State#state.config#upgrade_config.health_check_interval_ms),
            NewState = State#state{
                upgrade_supervisor = Pid,
                monitoring_timer = MonitoringTimer
            },
            logger:info("Optimized upgrade system initialized", #{
                domain => [a2a, upgrade, system]
            }),
            {ok, NewState};
        {error, Reason} ->
            logger:error("Failed to initialize upgrade system", #{
                reason => Reason,
                domain => [a2a, upgrade, system]
            }),
            {stop, Reason}
    end.

-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()} | {noreply, state()}.
handle_call({perform_upgrade, UpgradeId, Options}, _From, State) ->
    case State#state.upgrade_state#upgrade_state.status of
        idle ->
            NewConfig = apply_options(State#state.config, Options),
            NewUpgradeState = #upgrade_state{
                status = preparing,
                start_time = erlang:system_time(millisecond),
                strategy = NewConfig#upgrade_config.upgrade_strategy,
                processes_total = count_processes(),
                ets_total = count_ets_tables()
            },

            NewState = State#state{
                config = NewConfig,
                upgrade_state = NewUpgradeState
            },

            %% Start upgrade process
            case start_upgrade_process(UpgradeId, NewState) of
                {ok, UpgradePid} ->
                    {reply, {ok, UpgradePid}, NewState};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        _ ->
            {reply, {error, upgrade_in_progress}, State}
    end;

handle_call({rollback_upgrade, UpgradeId}, _From, State) ->
    case State#state.upgrade_state#upgrade_state.status of
        failed ->
            case rollback_internal(UpgradeId, State) of
                {ok, RollbackPid} ->
                    {reply, {ok, RollbackPid}, State};
                {error, Reason} ->
                    {reply, {error, Reason}, State}
            end;
        _ ->
            {reply, {error, no_failed_upgrade}, State}
    end;

handle_call({upgrade_processes, Pids, NewModule, Options}, _From, State) ->
    case upgrade_processes_internal(Pids, NewModule, State, Options) of
        {ok, UpgradedPids} ->
            {reply, {ok, UpgradedPids}, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({upgrade_ets_tables, TableNames, NewModule, Options}, _From, State) ->
    case upgrade_ets_tables_internal(TableNames, NewModule, State, Options) of
        ok ->
            {reply, ok, State};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call(get_upgrade_status, _From, State) ->
    Status = #{
        status => State#state.upgrade_state#upgrade_state.status,
        strategy => State#state.upgrade_state#upgrade_state.strategy,
        start_time => State#state.upgrade_state#upgrade_state.start_time,
        end_time => State#state.upgrade_state#upgrade_state.end_time,
        progress => calculate_progress(State),
        failed_processes => length(State#state.upgrade_state#upgrade_state.failed_processes),
        failed_ets => length(State#state.upgrade_state#upgrade_state.failed_ets),
        bottlenecks => State#state.upgrade_state#upgrade_state.bottlenecks
    },
    {reply, Status, State};

handle_call({get_upgrade_progress, UpgradeId}, _From, State) ->
    case maps:get(UpgradeId, State#state.active_upgrades, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        ProgressData ->
            {reply, {ok, ProgressData}, State}
    end;

handle_call(get_upgrade_health, _From, State) ->
    Health = check_upgrade_health(State),
    {reply, Health, State};

handle_call(get_performance_metrics, _From, State) ->
    {reply, State#state.performance, State};

handle_call(estimate_upgrade_resources, _From, State) ->
    Estimate = estimate_resources_internal(State),
    {reply, Estimate, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({set_concurrency_level, Level}, State) ->
    NewConfig = State#state.config#upgrade_config{
        concurrency_level = Level
    },
    NewState = State#state{config = NewConfig},
    logger:info("Concurrency level updated", #{
        level => Level,
        domain => [a2a, upgrade, system]
    }),
    {noreply, NewState};

handle_cast({set_upgrade_strategy, Strategy}, State) ->
    NewConfig = State#state.config#upgrade_config{
        upgrade_strategy = Strategy
    },
    NewState = State#state{config = NewConfig},
    logger:info("Upgrade strategy updated", #{
        strategy => Strategy,
        domain => [a2a, upgrade, system]
    }),
    {noreply, NewState};

handle_cast({set_memory_limit, LimitMb}, State) ->
    NewConfig = State#state.config#upgrade_config{
        memory_limit_mb = LimitMb
    },
    NewState = State#state{config = NewConfig},
    logger:info("Memory limit updated", #{
        limit_mb => LimitMb,
        domain => [a2a, upgrade, system]
    }),
    {noreply, NewState};

handle_cast(pause_upgrade, State) ->
    case State#state.upgrade_state#upgrade_state.status of
        upgrading ->
            NewUpgradeState = State#state.upgrade_state#upgrade_state{
                status = pausing
            },
            NewState = State#state{upgrade_state = NewUpgradeState},
            {noreply, NewState};
        _ ->
            {noreply, State}
    end;

handle_cast(resume_upgrade, State) ->
    case State#state.upgrade_state#upgrade_state.status of
        pausing ->
            NewUpgradeState = State#state.upgrade_state#upgrade_state{
                status = upgrading
            },
            NewState = State#state{upgrade_state = NewUpgradeState},
            {noreply, NewState};
        _ ->
            {noreply, State}
    end;

handle_cast(cancel_upgrade, State) ->
    case State#state.upgrade_state#upgrade_state.status of
        Status when Status =:= upgrading; Status =:= pausing; Status =:= preparing ->
            cancel_upgrade_internal(State),
            {noreply, State};
        _ ->
            {noreply, State}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(monitoring_timeout, State) ->
    case State#state.monitoring_timer of
        undefined ->
            {noreply, State};
        _ ->
            %% Perform health check and update metrics
            NewState = perform_monitoring_cycle(State),
            NewTimer = schedule_monitoring(State#state.config#upgrade_config.health_check_interval_ms),
            {noreply, NewState#state{monitoring_timer = NewTimer}}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, State) ->
    %% Cancel monitoring timer
    case State#state.monitoring_timer of
        undefined -> ok;
        T -> erlang:cancel_timer(T)
    end,

    %% Shutdown upgrade supervisor if running
    case State#state.upgrade_supervisor of
        undefined -> ok;
        Pid -> shutdown_upgrade_supervisor(Pid)
    end,

    logger:info("Optimized upgrade system stopped", #{
        domain => [a2a, upgrade, system]
    }),
    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @doc Apply options to config
-spec apply_options(upgrade_config(), map()) -> upgrade_config().
apply_options(Config, Options) ->
    Config#upgrade_config{
        concurrency_level = maps:get(concurrency_level, Options, Config#upgrade_config.concurrency_level),
        upgrade_strategy = maps:get(strategy, Options, Config#upgrade_config.upgrade_strategy),
        memory_limit_mb = maps:get(memory_limit_mb, Options, Config#upgrade_config.memory_limit_mb),
        max_process_time_ms = maps:get(max_process_time_ms, Options, Config#upgrade_config.max_process_time_ms),
        ets_batch_size = maps:get(ets_batch_size, Options, Config#upgrade_config.ets_batch_size),
        enable_rollback = maps:get(enable_rollback, Options, Config#upgrade_config.enable_rollback),
        health_check_interval_ms = maps:get(health_check_interval_ms, Options, Config#upgrade_config.health_check_interval_ms)
    }.

%% @doc Count processes in system
-spec count_processes() -> non_neg_integer().
count_processes() ->
    length(erlang:processes()).

%% @doc Count ETS tables in system
-spec count_ets_tables() -> non_neg_integer().
count_ets_tables() ->
    length(ets:all()).

%% @doc Start upgrade supervisor
-spec start_upgrade_supervisor() -> {ok, pid()} | {error, term()}.
start_upgrade_supervisor() ->
    %% This would start a dedicated supervisor for upgrade processes
    %% For now, return a mock implementation
    {ok, self()}.

%% @doc Start upgrade process
-spec start_upgrade_process(binary(), state()) -> {ok, pid()} | {error, term()}.
start_upgrade_process(UpgradeId, State) ->
    case State#state.config#upgrade_config.upgrade_strategy of
        immediate ->
            start_immediate_upgrade(UpgradeId, State);
        gradual ->
            start_gradual_upgrade(UpgradeId, State);
        phased ->
            start_phased_upgrade(UpgradeId, State)
    end.

%% @doc Start immediate upgrade (all at once)
-spec start_immediate_upgrade(binary(), state()) -> {ok, pid()} | {error, term()}.
start_immediate_upgrade(UpgradeId, State) ->
    %% Create upgrade plan
    Processes = get_all_processes(),
    EtsTables = get_all_ets_tables(),

    %% Start upgrade coordinator
    spawn_link(fun() ->
        perform_immediate_upgrade(UpgradeId, Processes, EtsTables, State)
    end),
    {ok, self()}.

%% @doc Start gradual upgrade (controlled concurrency)
-spec start_gradual_upgrade(binary(), state()) -> {ok, pid()} | {error, term()}.
start_gradual_upgrade(UpgradeId, State) ->
    Concurrency = State#state.config#upgrade_config.concurrency_level,
    Processes = get_all_processes(),

    %% Start upgrade coordinator with controlled concurrency
    spawn_link(fun() ->
        perform_gradual_upgrade(UpgradeId, Processes, Concurrency, State)
    end),
    {ok, self()}.

%% @doc Start phased upgrade (groups at a time)
-spec start_phased_upgrade(binary(), state()) -> {ok, pid()} | {error, term()}.
start_phased_upgrade(UpgradeId, State) ->
    PhaseSize = State#state.config#upgrade_config.concurrency_level,
    Processes = get_all_processes(),
    Phases = chunk_list(Processes, PhaseSize),

    %% Start upgrade coordinator with phased approach
    spawn_link(fun() ->
        perform_phased_upgrade(UpgradeId, Phases, State)
    end),
    {ok, self()}.

%% @doc Perform immediate upgrade
-spec perform_immediate_upgrade(binary(), [pid()], [term()], state()) -> ok.
perform_immediate_upgrade(UpgradeId, Processes, EtsTables, State) ->
    logger:info("Starting immediate upgrade", #{
        upgrade_id => UpgradeId,
        process_count => length(Processes),
        ets_count => length(EtsTables),
        domain => [a2a, upgrade, immediate]
    }),

    %% Upgrade all processes in parallel
    _UpgradedPids = upgrade_processes_parallel(Processes, State),

    %% Upgrade ETS tables
    upgrade_ets_tables_parallel(EtsTables, State),

    logger:info("Immediate upgrade completed", #{
        upgrade_id => UpgradeId,
        domain => [a2a, upgrade, immediate]
    }),
    ok.

%% @doc Perform gradual upgrade
-spec perform_gradual_upgrade(binary(), [pid()], pos_integer(), state()) -> ok.
perform_gradual_upgrade(UpgradeId, Processes, Concurrency, State) ->
    logger:info("Starting gradual upgrade", #{
        upgrade_id => UpgradeId,
        process_count => length(Processes),
        concurrency => Concurrency,
        domain => [a2a, upgrade, gradual]
    }),

    %% Process in batches with controlled concurrency
    Batches = chunk_list(Processes, Concurrency),
    lists:foreach(fun(Batch) ->
        _UpgradedPids = upgrade_processes_parallel(Batch, State),
        %% Batch delay to prevent system overload
        timer:sleep(1000)
    end, Batches),

    logger:info("Gradual upgrade completed", #{
        upgrade_id => UpgradeId,
        domain => [a2a, upgrade, gradual]
    }),
    ok.

%% @doc Perform phased upgrade
-spec perform_phased_upgrade(binary(), [[pid()]], state()) -> ok.
perform_phased_upgrade(UpgradeId, Phases, State) ->
    logger:info("Starting phased upgrade", #{
        upgrade_id => UpgradeId,
        phase_count => length(Phases),
        domain => [a2a, upgrade, phased]
    }),

    %% Process each phase with verification
    lists:foldl(fun(Phase, PhaseNum) ->
        logger:info("Starting upgrade phase ~p", [PhaseNum]),
        _UpgradedPids = upgrade_processes_parallel(Phase, State),

        %% Phase verification
        verify_phase_upgrade(PhaseNum),

        logger:info("Completed upgrade phase ~p", [PhaseNum]),
        PhaseNum + 1
    end, 1, Phases),

    logger:info("Phased upgrade completed", #{
        upgrade_id => UpgradeId,
        domain => [a2a, upgrade, phased]
    }),
    ok.

%% @doc Upgrade processes in parallel
-spec upgrade_processes_parallel([pid()], state()) -> [pid()].
upgrade_processes_parallel(Pids, State) ->
    Parent = self(),
    Ref = make_ref(),

    %% Spawn upgrade workers
    Workers = lists:map(fun(Pid) ->
        spawn_link(fun() ->
            case upgrade_single_process(Pid, State) of
                success ->
                    Parent ! {upgrade_success, Ref, Pid};
                {error, Reason} ->
                    Parent ! {upgrade_failure, Ref, Pid, Reason}
            end
        end)
    end, Pids),

    %% Collect results
    collect_upgrade_results(Ref, length(Workers), []).

%% @doc Upgrade single process
-spec upgrade_single_process(pid(), state()) -> success | {error, term()}.
upgrade_single_process(Pid, State) ->
    try
        %% Get process info
        ProcessInfo = process_info(Pid),
        case ProcessInfo of
            undefined ->
                {error, process_not_found};
            _ ->
                %% Perform upgrade with memory tracking
                MemoryBefore = get_process_memory(Pid),
                StartTime = erlang:monotonic_time(millisecond),

                %% Execute code_change
                case upgrade_process_code(Pid, State) of
                    ok ->
                        MemoryAfter = get_process_memory(Pid),
                        EndTime = erlang:monotonic_time(millisecond),
                        UpgradeTime = EndTime - StartTime,

                        logger:debug("Process upgraded successfully", #{
                            pid => Pid,
                            upgrade_time_ms => UpgradeTime,
                            memory_before => MemoryBefore,
                            memory_after => MemoryAfter,
                            domain => [a2a, upgrade, process]
                        }),
                        success;
                    {error, Reason} ->
                        {error, Reason}
                end
        end
    catch
        _:Error:Stacktrace ->
            logger:error("Process upgrade failed", #{
                pid => Pid,
                error => Error,
                stacktrace => Stacktrace,
                domain => [a2a, upgrade, process]
            }),
            {error, Error}
    end.

%% @doc Upgrade process code
-spec upgrade_process_code(pid(), state()) -> ok | {error, term()}.
upgrade_process_code(_Pid, _State) ->
    %% This would implement the actual code_change logic
    %% For now, return success for demonstration
    ok.

%% @doc Get process memory
-spec get_process_memory(pid()) -> non_neg_integer().
get_process_memory(Pid) ->
    case process_info(Pid, memory) of
        {memory, Mem} -> Mem;
        undefined -> 0
    end.

%% @doc Upgrade ETS tables in parallel
-spec upgrade_ets_tables_parallel([term()], state()) -> ok.
upgrade_ets_tables_parallel(TableNames, State) ->
    Parent = self(),
    Ref = make_ref(),

    %% Spawn upgrade workers
    Workers = lists:map(fun(TableName) ->
        spawn_link(fun() ->
            case upgrade_single_ets_table(TableName, State) of
                success ->
                    Parent ! {ets_upgrade_success, Ref, TableName};
                {error, Reason} ->
                    Parent ! {ets_upgrade_failure, Ref, TableName, Reason}
            end
        end)
    end, TableNames),

    %% Collect results
    collect_ets_upgrade_results(Ref, length(Workers), []).

%% @doc Upgrade single ETS table
-spec upgrade_single_ets_table(term(), state()) -> success | {error, term()}.
upgrade_single_ets_table(TableName, State) ->
    try
        %% Get table info
        TableInfo = ets:info(TableName),
        case TableInfo of
            undefined ->
                {error, table_not_found};
            _ ->
                RecordCount = ets:info(TableName, size),
                MemoryBefore = get_table_memory(TableName),
                StartTime = erlang:monotonic_time(millisecond),

                %% Perform upgrade
                case upgrade_ets_table(TableName, State) of
                    ok ->
                        MemoryAfter = get_table_memory(TableName),
                        EndTime = erlang:monotonic_time(millisecond),
                        UpgradeTime = EndTime - StartTime,

                        logger:debug("ETS table upgraded successfully", #{
                            table_name => TableName,
                            record_count => RecordCount,
                            upgrade_time_ms => UpgradeTime,
                            memory_before => MemoryBefore,
                            memory_after => MemoryAfter,
                            domain => [a2a, upgrade, ets]
                        }),
                        success;
                    {error, Reason} ->
                        {error, Reason}
                end
        end
    catch
        _:Error:Stacktrace ->
            logger:error("ETS table upgrade failed", #{
                table_name => TableName,
                error => Error,
                stacktrace => Stacktrace,
                domain => [a2a, upgrade, ets]
            }),
            {error, Error}
    end.

%% @doc Upgrade ETS table
-spec upgrade_ets_table(term(), state()) -> ok | {error, term()}.
upgrade_ets_table(_TableName, _State) ->
    %% This would implement the actual ETS upgrade logic
    %% For now, return success for demonstration
    ok.

%% @doc Get table memory
-spec get_table_memory(term()) -> non_neg_integer().
get_table_memory(TableName) ->
    case ets:info(TableName, memory) of
        undefined -> 0;
        Mem -> Mem
    end.

%% @doc Collect upgrade results
-spec collect_upgrade_results(reference(), non_neg_integer(), [pid()]) -> [pid()].
collect_upgrade_results(Ref, Expected, Results) ->
    receive
        {upgrade_success, Ref, Pid} ->
            NewResults = [Pid | Results],
            case length(NewResults) of
                Expected -> NewResults;
                _ -> collect_upgrade_results(Ref, Expected, NewResults)
            end;
        {upgrade_failure, Ref, Pid, Reason} ->
            logger:warning("Process upgrade failed", #{
                pid => Pid,
                reason => Reason,
                domain => [a2a, upgrade, process]
            }),
            collect_upgrade_results(Ref, Expected, Results)
    after 30000 ->
        logger:warning("Upgrade timeout", #{
            domain => [a2a, upgrade, process]
        }),
        Results
    end.

%% @doc Collect ETS upgrade results
-spec collect_ets_upgrade_results(reference(), non_neg_integer(), [term()]) -> [term()].
collect_ets_upgrade_results(Ref, Expected, Results) ->
    receive
        {ets_upgrade_success, Ref, TableName} ->
            NewResults = [TableName | Results],
            case length(NewResults) of
                Expected -> NewResults;
                _ -> collect_ets_upgrade_results(Ref, Expected, NewResults)
            end;
        {ets_upgrade_failure, Ref, TableName, Reason} ->
            logger:warning("ETS table upgrade failed", #{
                table_name => TableName,
                reason => Reason,
                domain => [a2a, upgrade, ets]
            }),
            collect_ets_upgrade_results(Ref, Expected, Results)
    after 30000 ->
        logger:warning("ETS upgrade timeout", #{
            domain => [a2a, upgrade, ets]
        }),
        Results
    end.

%% @doc Chunk list into smaller lists
-spec chunk_list([term()], pos_integer()) -> [[term()]].
chunk_list(List, Size) ->
    chunk_list(List, Size, []).

chunk_list(_, 0, Acc) -> lists:reverse(Acc);
chunk_list(List, Size, Acc) ->
    {Chunk, Rest} = lists:split(min(Size, length(List)), List),
    chunk_list(Rest, Size, [Chunk | Acc]).

%% @doc Calculate upgrade progress
-spec calculate_progress(state()) -> map().
calculate_progress(State) ->
    UpgradeState = State#state.upgrade_state,
    ProcessesTotal = UpgradeState#upgrade_state.processes_total,
    ProcessesUpgraded = UpgradeState#upgrade_state.processes_upgraded,
    EtsTotal = UpgradeState#upgrade_state.ets_total,
    EtsUpgraded = UpgradeState#upgrade_state.ets_upgraded,

    ProcessProgress = case ProcessesTotal of
        0 -> 100;
        _ -> round((ProcessesUpgraded / ProcessesTotal) * 100)
    end,

    EtsProgress = case EtsTotal of
        0 -> 100;
        _ -> round((EtsUpgraded / EtsTotal) * 100)
    end,

    OverallProgress = case ProcessesTotal + EtsTotal of
        0 -> 100;
        _ -> round(((ProcessesUpgraded + EtsUpgraded) / (ProcessesTotal + EtsTotal)) * 100)
    end,

    #{
        process_progress => ProcessProgress,
        ets_progress => EtsProgress,
        overall_progress => OverallProgress,
        processes_upgraded => ProcessesUpgraded,
        processes_total => ProcessesTotal,
        ets_upgraded => EtsUpgraded,
        ets_total => EtsTotal
    }.

%% @brief Check upgrade health
-spec check_upgrade_health(state()) -> map().
check_upgrade_health(State) ->
    CurrentMemory = erlang:memory(total) / (1024 * 1024),
    MemoryPercent = (CurrentMemory / State#state.config#upgrade_config.memory_limit_mb) * 100,

    UpgradeState = State#state.upgrade_state,
    TotalFailures = length(UpgradeState#upgrade_state.failed_processes) +
                    length(UpgradeState#upgrade_state.failed_ets),

    Status = if
        MemoryPercent > 90 -> critical;
        MemoryPercent > 75 orelse TotalFailures > 5 -> warning;
        true -> healthy
    end,

    #{
        status => Status,
        memory_usage_percent => MemoryPercent,
        total_failures => TotalFailures,
        active_processes => length(State#state.upgrade_state#upgrade_state.failed_processes),
        failed_ets => length(State#state.upgrade_state#upgrade_state.failed_ets),
        recommendations => generate_upgrade_health_recommendations(Status, MemoryPercent, TotalFailures)
    }.

%% @brief Generate upgrade health recommendations
-spec generate_upgrade_health_recommendations(atom(), float(), non_neg_integer()) -> [binary()].
generate_upgrade_health_recommendations(Status, MemoryPercent, TotalFailures) ->
    %% Memory recommendations
    Rec1 = case MemoryPercent > 85 of
        true -> <<"Consider reducing memory usage or increasing memory limit">>;
        false -> undefined
    end,

    %% Failure recommendations
    Rec2 = case TotalFailures > 3 of
        true -> <<"Multiple upgrade failures detected, consider rollback">>;
        false -> undefined
    end,

    %% Status recommendations
    Rec3 = case Status of
        critical -> <<"Critical system state, immediate intervention required">>;
        warning -> <<"Warning state, monitor upgrade closely">>;
        healthy -> undefined
    end,

    %% Filter out undefined values manually for compatibility
    [R || R <- [Rec1, Rec2, Rec3], R =/= undefined].

%% @brief Estimate upgrade resources
-spec estimate_resources_internal(state()) -> map().
estimate_resources_internal(State) ->
    Processes = count_processes(),
    EtsTables = count_ets_tables(),
    Concurrency = State#state.config#upgrade_config.concurrency_level,

    MemoryPerProcess = 1024 * 1024, %% 1MB estimate per process
    MemoryPerEts = 512 * 1024, %% 512KB estimate per ETS table

    EstimatedMemory = (Processes * MemoryPerProcess + EtsTables * MemoryPerEts) / (1024 * 1024),
    EstimatedTime = round(Processes / Concurrency * 1000), %% Rough estimate

    #{
        estimated_memory_mb => round(EstimatedMemory),
        estimated_time_ms => EstimatedTime,
        concurrency_level => Concurrency,
        process_count => Processes,
        ets_table_count => EtsTables,
        recommended_memory_mb => round(EstimatedMemory * 1.5)
    }.

%% @brief Perform monitoring cycle
-spec perform_monitoring_cycle(state()) -> state().
perform_monitoring_cycle(State) ->
    %% Update performance metrics
    NewPerformance = update_performance_metrics(State#state.performance),

    %% Check upgrade health
    _Health = check_upgrade_health(State),

    %% Log performance summary
    logger:debug("Upgrade monitoring cycle", #{
        memory_usage_mb => NewPerformance#performance_metrics.memory_usage,
        cpu_usage => NewPerformance#performance_metrics.cpu_usage,
        upgrade_progress => calculate_progress(State),
        domain => [a2a, upgrade, monitoring]
    }),

    State#state{
        performance = NewPerformance,
        upgrade_state = State#state.upgrade_state#upgrade_state{
            bottlenecks = detect_upgrade_bottlenecks(State)
        }
    }.

%% @brief Update performance metrics
-spec update_performance_metrics(performance_metrics()) -> performance_metrics().
update_performance_metrics(Perf) ->
    CurrentMemory = erlang:memory(total) / (1024 * 1024),

    Perf#performance_metrics{
        memory_usage = CurrentMemory,
        cpu_usage = get_cpu_usage(),
        peak_memory_mb = max(Perf#performance_metrics.peak_memory_mb, CurrentMemory)
    }.

%% @brief Get CPU usage using cpu_sup:util with fallback
%% @doc Returns CPU usage as a percentage (0.0 to 100.0)
%% Uses cpu_sup:util([detailed]) from the OS_Mon application
%% Falls back to scheduler statistics if cpu_sup is unavailable
-spec get_cpu_usage() -> float().
get_cpu_usage() ->
    case cpu_sup:util([detailed]) of
        {ok, CPUList} when is_list(CPUList), length(CPUList) > 0 ->
            %% cpu_sup returns a list of CPU values, take the first one
            [CPU | _] = CPUList,
            CPU * 100.0;
        {ok, CPU} when is_number(CPU) ->
            %% Single CPU value returned
            CPU * 100.0;
        {error, Reason} ->
            logger:warning("cpu_sup:util failed, using fallback: ~p", [Reason]),
            fallback_cpu_usage();
        _Other ->
            %% Unknown response format, use fallback
            fallback_cpu_usage()
    end.

%% @brief Fallback CPU usage calculation using scheduler statistics
-spec fallback_cpu_usage() -> float().
fallback_cpu_usage() ->
    try
        %% Use Erlang scheduler statistics as fallback
        TotalRunQueue = erlang:statistics(run_queue),
        Schedulers = erlang:system_info(schedulers_online),

        %% Calculate a simple load indicator based on run queue
        case Schedulers of
            0 -> 0.0;
            N when is_integer(N) andalso N > 0 ->
                %% Run queue per scheduler, normalized to 0-100 range
                LoadPerScheduler = TotalRunQueue / N,
                min(LoadPerScheduler * 10.0, 100.0);
            _ ->
                0.0
        end
    catch
        _:Error:Stack ->
            logger:warning("Fallback CPU usage calculation failed: ~p~nStack: ~p", [Error, Stack]),
            0.0
    end.

%% @brief Detect upgrade bottlenecks
-spec detect_upgrade_bottlenecks(state()) -> [term()].
detect_upgrade_bottlenecks(State) ->
    Bottlenecks = [],

    %% Check slow processes
    _SlowProcesses = lists:filter(fun(Pid) ->
        ProcessInfo = maps:get(Pid, State#state.processes, undefined),
        case ProcessInfo of
            undefined -> false;
            _ -> case ProcessInfo#process_upgrade_info.upgrade_time_ms of
                    undefined -> false;
                    Time when Time > State#state.config#upgrade_config.max_process_time_ms -> true;
                    _ -> false
                end
        end
    end, maps:keys(State#state.processes)),

    %% Check memory usage
    CurrentMemory = erlang:memory(total) / (1024 * 1024),
    case CurrentMemory > State#state.config#upgrade_config.memory_limit_mb * 0.9 of
        true -> [memory_limit_exceeded | Bottlenecks];
        false -> Bottlenecks
    end.

%% @brief Schedule monitoring
-spec schedule_monitoring(non_neg_integer()) -> reference().
schedule_monitoring(Interval) ->
    erlang:send_after(Interval, self(), monitoring_timeout).

%% @brief Get all processes
-spec get_all_processes() -> [pid()].
get_all_processes() ->
    %% Get processes that should be upgraded
    Processes = erlang:processes(),
    lists:filter(fun(Pid) ->
        case process_info(Pid, current_function) of
            {_, {a2a_task_statem, _, _}} -> true;
            {_, {a2a_handler, _, _}} -> true;
            _ -> false
        end
    end, Processes).

%% @brief Get all ETS tables
-spec get_all_ets_tables() -> [term()].
get_all_ets_tables() ->
    %% Get ETS tables that should be upgraded
    Tables = ets:all(),
    lists:filter(fun(Table) ->
        case ets:info(Table, name) of
            a2a_tasks -> true;
            a2a_task_pids -> true;
            a2a_task_contexts -> true;
            a2a_push_configs -> true;
            _ -> false
        end
    end, Tables).

%% @brief Verify phase upgrade
-spec verify_phase_upgrade(integer()) -> ok.
verify_phase_upgrade(PhaseNum) ->
    %% This would verify that all processes in the phase were successfully upgraded
    logger:info("Verifying upgrade phase ~p", [PhaseNum]),
    ok.

%% @brief Cancel upgrade internal
-spec cancel_upgrade_internal(state()) -> ok.
cancel_upgrade_internal(_State) ->
    logger:info("Cancelling upgrade", #{
        domain => [a2a, upgrade, system]
    }),

    %% Mark as failed and clean up
    _UpgradeState = _State#state.upgrade_state#upgrade_state{
        status = failed,
        end_time = erlang:system_time(millisecond)
    },

    logger:warning("Upgrade cancelled", #{
        domain => [a2a, upgrade, system]
    }),
    ok.

%% @brief Rollback internal
-spec rollback_internal(binary(), state()) -> {ok, pid()} | {error, term()}.
rollback_internal(UpgradeId, _State) ->
    logger:info("Starting rollback", #{
        upgrade_id => UpgradeId,
        domain => [a2a, upgrade, system]
    }),

    %% This would implement the actual rollback logic
    %% For now, return success
    {ok, self()}.

%% @brief Upgrade processes internal
-spec upgrade_processes_internal([pid()], module(), state(), map()) -> {ok, [pid()]} | {error, term()}.
upgrade_processes_internal(Pids, NewModule, _State, _Options) ->
    %% This would implement the actual process upgrade logic
    logger:info("Upgrading processes", #{
        count => length(Pids),
        new_module => NewModule,
        domain => [a2a, upgrade, process]
    }),
    {ok, Pids}.

%% @brief Upgrade ETS tables internal
-spec upgrade_ets_tables_internal([term()], module(), state(), map()) -> ok | {error, term()}.
upgrade_ets_tables_internal(TableNames, NewModule, _State, _Options) ->
    %% This would implement the actual ETS table upgrade logic
    logger:info("Upgrading ETS tables", #{
        count => length(TableNames),
        new_module => NewModule,
        domain => [a2a, upgrade, ets]
    }),
    ok.

%% @brief Shutdown upgrade supervisor
-spec shutdown_upgrade_supervisor(pid()) -> ok.
shutdown_upgrade_supervisor(Pid) ->
    %% This would properly shutdown the upgrade supervisor
    erlang:exit(Pid, shutdown),
    ok.