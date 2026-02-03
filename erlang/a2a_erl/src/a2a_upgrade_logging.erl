%%% @doc HotCI Upgrade Logging System
%%%
%%% This module provides comprehensive logging specifically for HotCI (Hot Code Upgrade)
%%% environments. It implements structured logging with contextual information,
%%% log rotation, and performance-conscious logging for high-frequency events.
%%%
%%% Features:
%%% - Structured logging with JSON format
%%% - Context-aware logging (upgrade context, tenant info, etc.)
%%% - Log levels and filtering
%%% - Log rotation and retention policies
%%% - Performance-optimized logging
%%% - Audit trail for upgrade operations
%%% - Log aggregation and search capabilities
%%% - Integration with external logging systems
%%%
%%% @end
-module(a2a_upgrade_logging).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    stop/0,

    %% Logging functions
    log_info/2,
    log_info/3,
    log_warning/2,
    log_warning/3,
    log_error/2,
    log_error/3,
    log_debug/2,
    log_debug/3,

    %% Upgrade-specific logging
    log_upgrade_start/2,
    log_upgrade_end/3,
    log_upgrade_step/4,
    log_upgrade_step/5,
    log_upgrade_rollback/3,

    %% Performance logging
    log_performance_metric/3,
    log_performance_metric/4,
    log_bottleneck/2,
    log_bottleneck/3,

    %% Audit logging
    log_audit_event/3,
    log_audit_event/4,
    log_security_event/3,

    %% Query functions
    get_upgrade_logs/1,
    get_logs_by_severity/2,
    get_performance_logs/1,
    get_audit_trail/1,
    search_logs/2,

    %% Configuration
    set_log_level/1,
    set_retention_policy/2,
    set_log_rotation/2,
    add_log_filter/2,
    remove_log_filter/2,

    %% Integration
    enable_external_logging/2,
    disable_external_logging/1,
    set_elasticsearch_endpoint/2
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

-define(LOG_LEVELS, [debug, info, warning, error, critical, audit, security]).
-define(DEFAULT_LOG_FORMAT, json).
-define(DEFAULT_RETENTION_DAYS, 30).
-define(DEFAULT_ROTATION_SIZE, 10485760). % 10MB

-record(log_entry, {
    timestamp :: integer(),
    level :: atom(),
    message :: binary(),
    details :: map(),
    upgrade_id :: binary() | undefined,
    tenant :: binary() | undefined,
    module :: binary(),
    function :: binary(),
    line :: integer(),
    pid :: pid(),
    trace_id :: binary() | undefined,
    span_id :: binary() | undefined,
    metadata :: map()
}).

-type log_entry() :: #log_entry{}.

-record(log_config, {
    log_level :: atom(),
    log_format :: atom(),
    retention_days :: integer(),
    rotation_size :: integer(),
    external_logging_enabled :: boolean(),
    external_endpoint :: binary(),
    log_filters :: [function()],
    enable_performance_logging :: boolean(),
    enable_audit_logging :: boolean(),
    enable_security_logging :: boolean()
}).

-type log_config() :: #log_config{}.

-record(log_rotation_state, {
    current_file :: file:filename_all(),
    current_size :: integer(),
    rotation_count :: integer(),
    last_rotation :: integer()
}).

-type log_rotation_state() :: #log_rotation_state{}.

-record(state, {
    logs :: [log_entry()],
    config :: log_config(),
    rotation_state :: log_rotation_state(),
    performance_metrics :: map(),
    audit_trail :: [map()],
    log_files :: [file:filename_all()],
    last_cleanup :: integer()
}).

-type state() :: #state{}.

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the logging system with default options
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the logging system with options
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

%% @doc Stop the logging system
-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%%% ============================================================================
%%% Logging Functions
%%% ============================================================================

%% @brief Log info message with details
-spec log_info(binary(), map()) -> ok.
log_info(Message, Details) ->
    log_info(Message, Details, #{}).

%% @brief Log info message with details and context
-spec log_info(binary(), map(), map()) -> ok.
log_info(Message, Details, Context) ->
    gen_server:cast(?MODULE, {log, info, Message, Details, Context}).

%% @brief Log warning message
-spec log_warning(binary(), map()) -> ok.
log_warning(Message, Details) ->
    log_warning(Message, Details, #{}).

%% @brief Log warning message with context
-spec log_warning(binary(), map(), map()) -> ok.
log_warning(Message, Details, Context) ->
    gen_server:cast(?MODULE, {log, warning, Message, Details, Context}).

%% @brief Log error message
-spec log_error(binary(), map()) -> ok.
log_error(Message, Details) ->
    log_error(Message, Details, #{}).

%% @brief Log error message with context
-spec log_error(binary(), map(), map()) -> ok.
log_error(Message, Details, Context) ->
    gen_server:cast(?MODULE, {log, error, Message, Details, Context}).

%% @brief Log debug message
-spec log_debug(binary(), map()) -> ok.
log_debug(Message, Details) ->
    log_debug(Message, Details, #{}).

%% @brief Log debug message with context
-spec log_debug(binary(), map(), map()) -> ok.
log_debug(Message, Details, Context) ->
    gen_server:cast(?MODULE, {log, debug, Message, Details, Context}).

%%% ============================================================================
%%% Upgrade-Specific Logging
%%% ============================================================================

%% @brief Log upgrade start
-spec log_upgrade_start(binary(), map()) -> ok.
log_upgrade_start(UpgradeId, Details) ->
    Context = #{
        upgrade_id => UpgradeId,
        event_type => upgrade_start,
        trigger => maps:get(trigger, Details, unknown)
    },
    log_info(<<"HotCI upgrade started">>, Details, Context).

%% @brief Log upgrade end
-spec log_upgrade_end(binary(), binary(), map()) -> ok.
log_upgrade_end(UpgradeId, Result, Details) ->
    Context = #{
        upgrade_id => UpgradeId,
        event_type => upgrade_end,
        result => Result
    },
    Message = case Result of
        completed -> <<"HotCI upgrade completed successfully">>;
        _ -> <<"HotCI upgrade failed">>
    end,
    log_info(Message, Details, Context).

%% @brief Log upgrade step
-spec log_upgrade_step(binary(), binary(), binary(), map()) -> ok.
log_upgrade_step(UpgradeId, StepId, Status, Details) ->
    log_upgrade_step(UpgradeId, StepId, Status, Details, #{}).

%% @brief Log upgrade step with context
-spec log_upgrade_step(binary(), binary(), binary(), map(), map()) -> ok.
log_upgrade_step(UpgradeId, StepId, Status, Details, Context) ->
    LogDetails = maps:merge(#{
        upgrade_id => UpgradeId,
        step_id => StepId,
        step_status => Status,
        duration_ms => maps:get(duration_ms, Details, 0)
    }, Details),

    EventContext = maps:merge(#{
        upgrade_id => UpgradeId,
        step_id => StepId,
        event_type => upgrade_step
    }, Context),

    Message = case Status of
        completed -> <<"Upgrade step completed">>;
        failed -> <<"Upgrade step failed">>;
        started -> <<"Upgrade step started">>;
        _ -> <<"Upgrade step status updated">>
    end,

    log_info(Message, LogDetails, EventContext).

%% @brief Log upgrade rollback
-spec log_upgrade_rollback(binary(), binary(), map()) -> ok.
log_upgrade_rollback(UpgradeId, Reason, Details) ->
    Context = #{
        upgrade_id => UpgradeId,
        event_type => upgrade_rollback,
        trigger => Reason
    },
    Message = <<"HotCI upgrade rollback initiated">>,
    log_warning(Message, Details, Context).

%%% ============================================================================
%%% Performance Logging
%%% ============================================================================

%% @brief Log performance metric
-spec log_performance_metric(binary(), integer(), map()) -> ok.
log_performance_metric(Name, Value, Details) ->
    log_performance_metric(Name, Value, Details, #{}).

%% @brief Log performance metric with context
-spec log_performance_metric(binary(), integer(), map(), map()) -> ok.
log_performance_metric(Name, Value, Details, Context) ->
    PerformanceData = #{
        metric_name => Name,
        value => Value,
        timestamp => erlang:system_time(millisecond),
        unit => maps:get(unit, Details, undefined),
        threshold => maps:get(threshold, Details, undefined),
        status => case maps:get(threshold, Details, undefined) of
            undefined -> normal;
            Threshold when Value > Threshold -> exceeded;
            _ -> normal
        end
    },

    gen_server:cast(?MODULE, {log_performance, PerformanceData, Context}).

%% @brief Log bottleneck detection
-spec log_bottleneck(binary(), map()) -> ok.
log_bottleneck(Component, Details) ->
    log_bottleneck(Component, Details, #{}).

%% @brief Log bottleneck with context
-spec log_bottleneck(binary(), map(), map()) -> ok.
log_bottleneck(Component, Details, Context) ->
    BottleneckData = #{
        component => Component,
        severity => maps:get(severity, Details, medium),
        impact => maps:get(impact, Details, medium),
        duration_ms => maps:get(duration_ms, Details, 0),
        suggestion => maps:get(suggestion, Details, undefined)
    },

    Message = <<"[BOTTLENECK] Detected in component: ", Component/binary>>,
    log_warning(Message, BottleneckData, Context).

%%% ============================================================================
%%% Audit Logging
%%% ============================================================================

%% @brief Log audit event
-spec log_audit_event(binary(), binary(), map()) -> ok.
log_audit_event(EventType, Actor, Details) ->
    log_audit_event(EventType, Actor, Details, #{}).

%% @brief Log audit event with context
-spec log_audit_event(binary(), binary(), map(), map()) -> ok.
log_audit_event(EventType, Actor, Details, Context) ->
    AuditData = #{
        event_type => EventType,
        actor => Actor,
        timestamp => erlang:system_time(millisecond),
        details => Details,
        success => maps:get(success, Details, true)
    },

    Message = case EventType of
        <<"system.login">> -> <<"System login event">>;
        <<"system.logout">> -> <<"System logout event">>;
        <<"configuration.change">> -> <<"Configuration changed">>;
        _ -> <<"Audit event">>
    end,

    gen_server:cast(?MODULE, {log_audit, AuditData, Context}).

%% @brief Log security event
-spec log_security_event(binary(), binary(), map()) -> ok.
log_security_event(EventType, Actor, Details) ->
    Context = #{
        event_type => security_event,
        severity => maps:get(severity, Details, high)
    },
    Message = <<"[SECURITY] ", EventType/binary>>,
    log_error(Message, Details, Context).

%%% ============================================================================
%%% Query Functions
%%% ============================================================================

%% @brief Get logs for specific upgrade
-spec get_upgrade_logs(binary()) -> [map()].
get_upgrade_logs(UpgradeId) ->
    gen_server:call(?MODULE, {get_logs, upgrade_id, UpgradeId}).

%% @brief Get logs by severity level
-spec get_logs_by_severity(atom(), integer()) -> [map()].
get_logs_by_severity(Severity, Limit) ->
    gen_server:call(?MODULE, {get_logs, severity, Severity, Limit}).

%% @brief Get performance logs
-spec get_performance_logs(integer()) -> [map()].
get_performance_logs(Limit) ->
    gen_server:call(?MODULE, {get_performance_logs, Limit}).

%% @brief Get audit trail
-spec get_audit_trail(binary()) -> [map()].
get_audit_trail(Actor) ->
    gen_server:call(?MODULE, {get_audit_trail, Actor}).

%% @brief Search logs
-spec search_logs(map(), integer()) -> [map()].
search_logs(SearchParams, Limit) ->
    gen_server:call(?MODULE, {search_logs, SearchParams, Limit}).

%%% ============================================================================
%%% Configuration
%%% ============================================================================

%% @brief Set log level
-spec set_log_level(atom()) -> ok.
set_log_level(LogLevel) ->
    gen_server:cast(?MODULE, {set_log_level, LogLevel}).

%% @brief Set retention policy
-spec set_retention_policy(integer(), binary()) -> ok.
set_retention_policy(Days, Unit) ->
    gen_server:cast(?MODULE, {set_retention_policy, Days, Unit}).

%% @brief Set log rotation settings
-spec set_log_rotation(integer(), binary()) -> ok.
set_log_rotation(Size, Unit) ->
    gen_server:cast(?MODULE, {set_log_rotation, Size, Unit}).

%% @brief Add log filter
-spec add_log_filter(function()) -> ok.
add_log_filter(Filter) ->
    gen_server:cast(?MODULE, {add_log_filter, Filter}).

%% @brief Remove log filter
-spec remove_log_filter(function()) -> ok.
remove_log_filter(Filter) ->
    gen_server:cast(?MODULE, {remove_log_filter, Filter}).

%%% ============================================================================
%%% Integration
%%% ============================================================================

%% @brief Enable external logging
-spec enable_external_logging(binary(), map()) -> ok.
enable_external_logging(Endpoint, Config) ->
    gen_server:cast(?MODULE, {enable_external_logging, Endpoint, Config}).

%% @brief Disable external logging
-spec disable_external_logging(binary()) -> ok.
disable_external_logging(Endpoint) ->
    gen_server:cast(?MODULE, {disable_external_logging, Endpoint}).

%% @brief Set Elasticsearch endpoint
-spec set_elasticsearch_endpoint(binary()) -> ok.
set_elasticsearch_endpoint(Endpoint) ->
    gen_server:cast(?MODULE, {set_elasticsearch_endpoint, Endpoint}).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init(map()) -> {ok, state()} | {ok, state(), {continue, atom()}}.
init(Opts) ->
    LogLevel = maps:get(log_level, Opts, info),
    RetentionDays = maps:get(retention_days, Opts, ?DEFAULT_RETENTION_DAYS),
    RotationSize = maps.get(rotation_size, Opts, ?DEFAULT_ROTATION_SIZE),

    Config = #log_config{
        log_level = LogLevel,
        log_format = maps:get(log_format, Opts, ?DEFAULT_LOG_FORMAT),
        retention_days = RetentionDays,
        rotation_size = RotationSize,
        external_logging_enabled = maps:get(external_logging_enabled, Opts, false),
        external_endpoint = maps:get(external_endpoint, Opts, <<"">>),
        log_filters = [],
        enable_performance_logging = maps:get(enable_performance_logging, Opts, true),
        enable_audit_logging = maps.get(enable_audit_logging, Opts, true),
        enable_security_logging = maps:get(enable_security_logging, Opts, true)
    },

    RotationState = #log_rotation_state{
        current_file = create_log_filename(),
        current_size = 0,
        rotation_count = 0,
        last_rotation = erlang:system_time(millisecond)
    },

    State = #state{
        logs = [],
        config = Config,
        rotation_state = RotationState,
        performance_metrics = #{},
        audit_trail = [],
        log_files = [],
        last_cleanup = erlang:system_time(millisecond)
    },

    %% Start cleanup timer
    Timer = erlang:send_after(3600000, self(), cleanup_old_logs),  % Every hour

    logger:info("Upgrade logging system started", #[
        {log_level, LogLevel},
        {retention_days, RetentionDays},
        {rotation_size, RotationSize},
        {domain, [a2a, upgrade, logging]}
    ]),

    {ok, State#state{cleanup_timer = Timer}, {continue, initialize_logging}}.

-spec handle_continue(atom(), state()) -> {ok, state()}.
handle_continue(initialize_logging, State) ->
    %% Initialize log directory and files
    InitializedState = initialize_log_files(State),

    %% Start performance metrics collection
    NewState = if State#state.config#log_config.enable_performance_logging ->
                    start_performance_collection(InitializedState);
               true ->
                    InitializedState
    end,

    {ok, NewState}.

-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()} | {noreply, state()}.
handle_call({get_logs, upgrade_id, UpgradeId}, _From, State) ->
    UpgradeLogs = lists:filter(fun(Log) ->
        Log#log_entry.upgrade_id == UpgradeId
    end, State#state.logs),

    FormattedLogs = lists:map(fun format_log_entry/1, UpgradeLogs),
    {reply, FormattedLogs, State};

handle_call({get_logs, severity, Severity, Limit}, _From, State) ->
    SeverityLogs = lists:filter(fun(Log) ->
        Log#log_entry.level == Severity
    end, State#state.logs),

    LimitedLogs = lists:sublist(lists:reverse(SeverityLogs), Limit),
    FormattedLogs = lists:map(fun format_log_entry/1, LimitedLogs),
    {reply, FormattedLogs, State};

handle_call({get_performance_logs, Limit}, _From, State) ->
    PerformanceLogs = maps:values(State#state.performance_metrics),
    SortedLogs = lists:sort(fun(L1, L2) ->
        L1#log_entry.timestamp > L2#log_entry.timestamp
    end, PerformanceLogs),

    LimitedLogs = lists:sublist(SortedLogs, Limit),
    FormattedLogs = lists:map(fun format_log_entry/1, LimitedLogs),
    {reply, FormattedLogs, State};

handle_call({get_audit_trail, Actor}, _From, State) ->
    ActorLogs = lists:filter(fun(Log) ->
        maps:get(<<"actor">>, Log#log_entry.details, undefined) == Actor
    end, State#state.audit_trail),

    SortedLogs = lists:sort(fun(L1, L2) ->
        maps:get(<<"timestamp">>, L1, 0) > maps:get(<<"timestamp">>, L2, 0)
    end, ActorLogs),

    {reply, SortedLogs, State};

handle_call({search_logs, SearchParams, Limit}, _From, State) ->
    MatchingLogs = search_logs_by_params(State#state.logs, SearchParams),
    LimitedLogs = lists:sublist(MatchingLogs, Limit),
    FormattedLogs = lists:map(fun format_log_entry/1, LimitedLogs),
    {reply, FormattedLogs, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({log, Level, Message, Details, Context}, State) ->
    %% Check log level filter
    if Level =< State#state.config#log_config.log_level ->
            LogEntry = create_log_entry(Level, Message, Details, Context),
            NewState = write_log(LogEntry, State),

            %% Apply filters
            FilteredState = apply_log_filters(LogEntry, NewState),

            %% Send external logging if enabled
            if State#state.config#log_config.external_logging_enabled ->
                    send_external_log(LogEntry, FilteredState);
               true ->
                    FilteredState
            end;
       true ->
            State
    end;

handle_cast({log_performance, PerformanceData, Context}, State) ->
    if State#state.config#log_config.enable_performance_logging ->
            LogEntry = create_performance_log_entry(PerformanceData, Context),
            NewState = write_log(LogEntry, State),

            %% Update performance metrics
            UpdatedMetrics = update_performance_metrics(PerformanceData, State#state.performance_metrics),

            NewState#state{performance_metrics = UpdatedMetrics};
       true ->
            State
    end;

handle_cast({log_audit, AuditData, Context}, State) ->
    if State#state.config#log_config.enable_audit_logging ->
            AuditLog = create_audit_log_entry(AuditData, Context),
            NewState = write_log(AuditLog, State),

            %% Add to audit trail
            UpdatedAuditTrail = [AuditLog | State#state.audit_trail],

            %% External logging for security events
            case maps:get(<<"event_type">>, AuditData, undefined) of
                <<"security_event">> ->
                    send_external_log(AuditLog, NewState);
                _ ->
                    ok
            end,

            NewState#state{audit_trail = UpdatedAuditTrail};
       true ->
            State
    end;

handle_cast({set_log_level, LogLevel}, State) ->
    logger:info("Log level changed", #[
        {old_level, State#state.config#log_config.log_level},
        {new_level, LogLevel},
        {domain, [a2a, upgrade, logging]}
    ]),

    NewConfig = State#state.config#log_config{log_level = LogLevel},
    {noreply, State#state{config = NewConfig}};

handle_cast({set_retention_policy, Days, _Unit}, State) ->
    logger:info("Retention policy updated", #[
        {days, Days},
        {domain, [a2a, upgrade, logging]}
    ]),

    NewConfig = State#state.config#log_config{retention_days = Days},
    {noreply, State#state{config = NewConfig}};

handle_cast({set_log_rotation, Size, _Unit}, State) ->
    logger:info("Log rotation updated", #[
        {size, Size},
        {domain, [a2a, upgrade, logging]}
    ]),

    NewConfig = State#state.config#log_config{rotation_size = Size},
    {noreply, State#state{config = NewConfig}};

handle_cast({add_log_filter, Filter}, State) ->
    logger:info("Log filter added", #[
        {filter_type, element(1, erlang:fun_info(Filter, name))},
        {domain, [a2a, upgrade, logging]}
    ]),

    NewFilters = [Filter | State#state.config#log_config.log_filters],
    NewConfig = State#state.config#log_config{log_filters = NewFilters},
    {noreply, State#state{config = NewConfig}};

handle_cast({remove_log_filter, Filter}, State) ->
    logger:info("Log filter removed", #[
        {filter_type, element(1, erlang:fun_info(Filter, name))},
        {domain, [a2a, upgrade, logging]}
    ]),

    NewFilters = lists:delete(Filter, State#state.config#log_config.log_filters),
    NewConfig = State#state.config#log_config{log_filters = NewFilters},
    {noreply, State#state{config = NewConfig}};

handle_cast({enable_external_logging, Endpoint, Config}, State) ->
    logger:info("External logging enabled", #[
        {endpoint, Endpoint},
        {domain, [a2a, upgrade, logging]}
    ]),

    NewConfig = State#state.config#log_config{
        external_logging_enabled = true,
        external_endpoint = Endpoint
    },

    {noreply, State#state{config = NewConfig}};

handle_cast({disable_external_logging, Endpoint}, State) ->
    logger:info("External logging disabled", #[
        {endpoint, Endpoint},
        {domain, [a2a, upgrade, logging]}
    ]),

    NewConfig = State#state.config#log_config{
        external_logging_enabled = false
    },

    {noreply, State#state{config = NewConfig}};

handle_cast({set_elasticsearch_endpoint, Endpoint}, State) ->
    logger:info("Elasticsearch endpoint configured", #[
        {endpoint, Endpoint},
        {domain, [a2a, upgrade, logging]}
    ]),

    Config = State#state.config#log_config{external_endpoint = Endpoint},
    {noreply, State#state{config = Config}};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(cleanup_old_logs, State) ->
    CleanupState = cleanup_old_logs(State),

    %% Reschedule
    Timer = erlang:send_after(3600000, self(), cleanup_old_logs),
    {noreply, CleanupState#state{cleanup_timer = Timer}};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, State) ->
    %% Cancel timer if exists
    case State#state.cleanup_timer of
        undefined -> ok;
        T -> erlang:cancel_timer(T)
    end,

    %% Flush all remaining logs
    lists:foreach(fun(Log) ->
        flush_log_to_file(Log, State)
    end, State#state.logs),

    ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% @brief Create log entry
-spec create_log_entry(atom(), binary(), map(), map()) -> log_entry().
create_log_entry(Level, Message, Details, Context) ->
    #log_entry{
        timestamp = erlang:system_time(millisecond),
        level = Level,
        message = Message,
        details = Details,
        upgrade_id = maps:get(upgrade_id, Context, undefined),
        tenant = maps:get(tenant, Context, undefined),
        module = maps:get(module, Context, <<"unknown">>),
        function = maps:get(function, Context, <<"unknown">>),
        line = maps:get(line, Context, 0),
        pid = self(),
        trace_id = maps:get(trace_id, Context, undefined),
        span_id = maps:get(span_id, Context, undefined),
        metadata = maps:remove(upgrade_id, maps:remove(tenant, Context))
    }.

%% @brief Create performance log entry
-spec create_performance_log_entry(map(), map()) -> log_entry().
create_performance_log_entry(PerformanceData, Context) ->
    Details = PerformanceData,
    Message = <<"Performance metric: ", (maps:get(metric_name, Details))/binary>>,

    create_log_entry(info, Message, Details, Context).

%% @brief Create audit log entry
-spec create_audit_log_entry(map(), map()) -> log_entry().
create_audit_log_entry(AuditData, Context) ->
    Details = AuditData,
    EventType = maps:get(event_type, Details, unknown),
    Message = case EventType of
        <<"system.login">> -> <<"System login">>;
        <<"system.logout">> -> <<"System logout">>;
        <<"configuration.change">> -> <<"Configuration changed">>;
        <<"security_event">> -> <<"Security event">>;
        _ -> <<"Audit event">>
    end,

    create_log_entry(audit, Message, Details, Context).

%% @brief Write log entry
-spec write_log(log_entry(), state()) -> state().
write_log(LogEntry, State) ->
    %% Check log rotation
    {RotatedState, LogEntry1} = check_log_rotation(LogEntry, State),

    %% Write to file
    write_log_to_file(LogEntry1, RotatedState),

    %% Keep in memory for querying
    UpdatedLogs = [LogEntry1 | State#state.logs],

    %% Limit in-memory logs to prevent memory issues
    LimitedLogs = case length(UpdatedLogs) > 10000 of
        true -> lists:sublist(UpdatedLogs, 10000);
        false -> UpdatedLogs
    end,

    RotatedState#state{logs = LimitedLogs}.

%% @brief Check and handle log rotation
-spec check_log_rotation(log_entry(), state()) -> {state(), log_entry()}.
check_log_rotation(LogEntry, State) ->
    RotationState = State#state.rotation_state,
    CurrentSize = RotationState#log_rotation_state.current_size,

    if CurrentSize > State#state.config#log_config.rotation_size ->
            RotatedState = rotate_log_file(State),
            NewLogEntry = LogEntry#log_entry{timestamp = erlang:system_time(millisecond)},
            {RotatedState, NewLogEntry};
       true ->
            StateWithUpdatedSize = State#state{
                rotation_state = RotationState#log_rotation_state{
                    current_size = CurrentSize + calculate_log_size(LogEntry)
                }
            },
            {StateWithUpdatedSize, LogEntry}
    end.

%% @brief Calculate log entry size
-spec calculate_log_size(log_entry()) -> integer().
calculate_log_size(LogEntry) ->
    %% Simplified size calculation
    size(LogEntry#log_entry.message) + 1000.

%% @brief Rotate log file
-spec rotate_log_file(state()) -> state().
rotate_log_file(State) ->
    RotationState = State#state.rotation_state,
    CurrentFile = RotationState#log_rotation_state.current_file,
    RotationCount = RotationState#log_rotation_state.rotation_count,

    %% Close current file and create new one
    ArchiveFile = create_archive_filename(CurrentFile, RotationCount),
    file:rename(CurrentFile, ArchiveFile),

    NewRotationState = #log_rotation_state{
        current_file = create_log_filename(),
        current_size = 0,
        rotation_count = RotationCount + 1,
        last_rotation = erlang:system_time(millisecond)
    },

    logger:info("Log file rotated", #[
        {old_file, CurrentFile},
        {new_file, NewRotationState#log_rotation_state.current_file},
        {archive_file, ArchiveFile},
        {domain, [a2a, upgrade, logging]}
    ]),

    State#state{
        rotation_state = NewRotationState,
        log_files = [ArchiveFile | State#state.log_files]
    }.

%% @brief Write log to file
-spec write_log_to_file(log_entry(), state()) -> ok.
write_log_to_file(LogEntry, State) ->
    LogFile = State#state.rotation_state#log_rotation_state.current_file,

    FormattedLog = format_log_entry(LogEntry),

    case file:open(LogFile, [append]) of
        {ok, FileHandle} ->
            file:write(FileHandle, FormattedLog),
            file:close(FileHandle);
        {error, Reason} ->
            logger:error("Failed to write log file", #[
                {file, LogFile},
                {reason, Reason},
                {domain, [a2a, upgrade, logging]}
            ])
    end.

%% @brief Format log entry
-spec format_log_entry(log_entry()) -> binary().
format_log_entry(LogEntry) ->
    case State#state.config#log_config.log_format of
        json -> format_log_json(LogEntry);
        _ -> format_log_text(LogEntry)
    end.

%% @brief Format log entry as JSON
-spec format_log_json(log_entry()) -> binary().
format_log_json(LogEntry) ->
    LogMap = #{
        timestamp => LogEntry#log_entry.timestamp,
        level => atom_to_binary(LogEntry#log_entry.level, utf8),
        message => LogEntry#log_entry.message,
        details => LogEntry#log_entry.details,
        upgrade_id => LogEntry#log_entry.upgrade_id,
        tenant => LogEntry#log_entry.tenant,
        module => LogEntry#log_entry.module,
        function => LogEntry#log_entry.function,
        line => LogEntry#log_entry.line,
        pid => pid_to_list(LogEntry#log_entry.pid),
        trace_id => LogEntry#log_entry.trace_id,
        span_id => LogEntry#log_entry.span_id,
        metadata => LogEntry#log_entry.metadata
    },
    json:encode(LogMap).

%% @brief Format log entry as text
-spec format_log_text(log_entry()) -> binary().
format_log_text(LogEntry) ->
    Timestamp = format_timestamp(LogEntry#log_entry.timestamp),
    Level = atom_to_binary(LogEntry#log_entry.level, utf8),
    Pid = pid_to_list(LogEntry#log_entry.pid),
    Message = LogEntry#log_entry.message,

    iolist_to_binary([
        Timestamp, " [", Level, "] [", Pid, "] ",
        Message, "\n"
    ]).

%% @brief Format timestamp
-spec format_timestamp(integer()) -> binary().
format_timestamp(Timestamp) ->
    {{Year, Month, Day}, {Hour, Minute, Second}} = calendar:now_to_local_time({Timestamp div 1000, Timestamp rem 1000, 0}),
    io_lib:format("~4.10.0B-~2.10.0B-~2.10.0B ~2.10.0B:~2.10.0B:~2.10.0B",
                 [Year, Month, Day, Hour, Minute, Second]).

%% @brief Initialize log files
-spec initialize_log_files(state()) -> state().
initialize_log_files(State) ->
    LogDir = get_log_directory(),
    case file:make_dir(LogDir) of
        ok -> ok;
        {error, eexist} -> ok
    end,

    CurrentFile = create_log_filename(),
    file:write_file(CurrentFile, <<>>),

    RotationState = State#state.rotation_state#log_rotation_state{
        current_file = CurrentFile
    },

    State#state{
        rotation_state = RotationState,
        log_files = [CurrentFile]
    }.

%% @brief Create log directory
-spec get_log_directory() -> file:filename_all().
get_log_directory() ->
    case application:get_env(a2a_erl, log_dir) of
        undefined -> "/var/log/a2a/upgrade_logs";
        {ok, Dir} -> Dir
    end.

%% @brief Create log filename
-spec create_log_filename() -> file:filename_all().
create_log_filename() ->
    LogDir = get_log_directory(),
    Timestamp = format_timestamp(erlang:system_time(millisecond)),
    filename:join(LogDir, "upgrade_" ++ binary_to_list(Timestamp) ++ ".log").

%% @brief Create archive filename
-spec create_archive_filename(file:filename_all(), integer()) -> file:filename_all().
create_archive_filename(OriginalFile, RotationCount) ->
    LogDir = filename:dirname(OriginalFile),
    BaseName = filename:basename(OriginalFile, ".log"),
    ArchiveName = BaseName ++ "_rotation_" ++ integer_to_list(RotationCount) ++ ".log",
    filename:join(LogDir, ArchiveName).

%% @brief Apply log filters
-spec apply_log_filters(log_entry(), state()) -> state().
apply_log_filters(LogEntry, State) ->
    Config = State#state.config,
    Filters = Config#log_config.log_filters,

    Filtered = lists:all(fun(Filter) ->
        case catch Filter(LogEntry) of
            true -> true;
            _ -> false
        end
    end, Filters),

    if Filtered -> State; true -> State end.

%% @brief Send external log
-spec send_external_log(log_entry(), state()) -> state().
send_external_log(LogEntry, State) ->
    Config = State#state.config,
    Endpoint = Config#log_config.external_endpoint,

    case Endpoint of
        undefined -> State;
        _ ->
            LogData = format_log_json(LogEntry),
            %% In production, this would send to external service
            logger:debug("External log sent", #[
                {endpoint, Endpoint},
                {data, LogData},
                {domain, [a2a, upgrade, logging]}
            ]),
            State
    end.

%% @brief Search logs by parameters
-spec search_logs_by_params([log_entry()], map()) -> [log_entry()].
search_logs_by_params(Logs, SearchParams) ->
    lists:filter(fun(Log) ->
        matches_search_params(Log, SearchParams)
    end, Logs).

%% @brief Check if log matches search parameters
-spec matches_search_params(log_entry(), map()) -> boolean().
matches_search_params(Log, SearchParams) ->
    matches_level(Log, SearchParams) andalso
    matches_time_range(Log, SearchParams) andalso
    matches_upgrade_id(Log, SearchParams) andalso
    matches_message(Log, SearchParams).

%% @brief Check log level filter
-spec matches_level(log_entry(), map()) -> boolean().
matches_level(Log, SearchParams) ->
    case maps:get(level, SearchParams, undefined) of
        undefined -> true;
        Level -> Log#log_entry.level == Level
    end.

%% @brief Check time range filter
-spec matches_time_range(log_entry(), map()) -> boolean().
matches_time_range(Log, SearchParams) ->
    Timestamp = Log#log_entry.timestamp,
    case {maps:get(start_time, SearchParams, undefined), maps:get(end_time, SearchParams, undefined)} of
        {undefined, undefined} -> true;
        {Start, undefined} -> Timestamp >= Start;
        {undefined, End} -> Timestamp =< End;
        {Start, End} -> Timestamp >= Start andalso Timestamp =< End
    end.

%% @brief Check upgrade ID filter
-spec matches_upgrade_id(log_entry(), map()) -> boolean().
matches_upgrade_id(Log, SearchParams) ->
    case maps:get(upgrade_id, SearchParams, undefined) of
        undefined -> true;
        UpgradeId -> Log#log_entry.upgrade_id == UpgradeId
    end.

%% @brief Check message filter
-spec matches_message(log_entry(), map()) -> boolean().
matches_message(Log, SearchParams) ->
    case maps:get(message_contains, SearchParams, undefined) of
        undefined -> true;
        Substring -> binary:match(Log#log_entry.message, Substring) /= nomatch
    end.

%% @brief Cleanup old logs
-spec cleanup_old_logs(state()) -> state().
cleanup_old_logs(State) ->
    Config = State#state.config,
    RetentionMs = Config#log_config.retention_days * 24 * 60 * 60 * 1000,
    CutoffTime = erlang:system_time(millisecond) - RetentionMs,

    CleanupNow = case erlang:system_time(millisecond) - State#state.last_cleanup > 86400000 of
        true -> true;
        false -> false
    end,

    if CleanupNow ->
            LogDir = get_log_directory(),
            {ok, Files} = file:list_dir(LogDir),

            OldFiles = lists:filter(fun(File) ->
                case file:read_file_info(filename:join(LogDir, File)) of
                    {ok, Info} -> Info#file_info.mtime < CutoffTime;
                    _ -> false
                end
            end, Files),

            lists:foreach(fun(File) ->
                FilePath = filename:join(LogDir, File),
                file:delete(FilePath)
            end, OldFiles),

            logger:info("Cleaned up old logs", #[
                {files_deleted, length(OldFiles)},
                {domain, [a2a, upgrade, logging]}
            ]),

            State#state{last_cleanup = erlang:system_time(millisecond)};
       true ->
            State
    end.

%% @brief Update performance metrics
-spec update_performance_metrics(map(), map()) -> map().
update_performance_metrics(Metric, Metrics) ->
    MetricName = maps:get(metric_name, Metric),
    Value = maps:get(value, Metric),
    Timestamp = maps:get(timestamp, Metric),

    case maps:get(MetricName, Metrics, undefined) of
        undefined ->
            Metrics#{MetricName => Metric};
        ExistingMetric ->
            %% Keep only recent metrics (last 100)
            UpdatedMetrics = lists:sublist([Metric, ExistingMetric], 100),
            Metrics#{MetricName => UpdatedMetrics}
    end.

%% @brief Start performance collection
-spec start_performance_collection(state()) -> state().
start_performance_collection(State) ->
    logger:info("Started performance metrics collection", #[
        {domain, [a2a, upgrade, logging]}
    ]),
    State.

%% @brief Create log directory
-spec ensure_log_directory_exists() -> ok.
ensure_log_directory_exists() ->
    LogDir = get_log_directory(),
    case file:make_dir(LogDir) of
        ok -> ok;
        {error, eexist} -> ok;
        {error, Reason} ->
            logger:error("Failed to create log directory", #[
                {directory, LogDir},
                {reason, Reason},
                {domain, [a2a, upgrade, logging]}
            ])
    end.