%%% @doc A2A Telemetry and Metrics Module
%%%
%%% This module provides comprehensive telemetry collection and metrics reporting
%%% for the A2A protocol implementation. It uses OTP 28's logger:metadata and
%%% provides built-in metrics without external dependencies.
%%%
%%% Features:
%%% - Task lifecycle metrics (creation, state transitions, completion)
%%% - Message processing metrics (counters, latencies)
%%% - HTTP request metrics (endpoints, status codes, response times)
%%% - SSE connection metrics (active connections, messages sent)
%%% - Push notification metrics (success/failure rates)
%%% - System health metrics (process counts, memory usage)
%%%
%%% Metrics are reported through:
%%% - Logger metadata (for structured logging)
%%% - ETS tables (for real-time queries)
%%% - Periodic snapshots (for historical analysis)
%%%
%%% @end
-module(a2a_metrics).

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start_link/1,
    stop/0,

    %% Task metrics
    task_created/1,
    task_state_changed/3,
    task_completed/2,
    task_failed/2,
    task_canceled/1,
    task_rejected/1,

    %% Message metrics
    message_received/1,
    message_processed/2,
    message_processing_error/2,

    %% HTTP metrics
    http_request/4,
    http_response/5,

    %% SSE metrics
    sse_connection_opened/1,
    sse_connection_closed/2,
    sse_event_sent/2,

    %% Push notification metrics
    push_notification_sent/2,
    push_notification_failed/3,

    %% System metrics
    record_system_metrics/0,

    %% Query metrics
    get_task_metrics/0,
    get_message_metrics/0,
    get_http_metrics/0,
    get_sse_metrics/0,
    get_push_metrics/0,
    get_system_metrics/0,
    get_all_metrics/0,
    get_metric/1,

    %% Reset metrics
    reset_metrics/0,
    reset_metric/1
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

-record(task_metrics, {
    total_created = 0 :: non_neg_integer(),
    active = 0 :: non_neg_integer(),
    completed = 0 :: non_neg_integer(),
    failed = 0 :: non_neg_integer(),
    canceled = 0 :: non_neg_integer(),
    rejected = 0 :: non_neg_integer(),
    state_transitions = 0 :: non_neg_integer(),
    avg_processing_time_ms = 0 :: float(),
    last_updated :: integer() | undefined
}).

-type task_metrics() :: #task_metrics{}.

-record(message_metrics, {
    total_received = 0 :: non_neg_integer(),
    total_processed = 0 :: non_neg_integer(),
    total_errors = 0 :: non_neg_integer(),
    avg_processing_time_ms = 0 :: float(),
    last_error_reason :: binary() | undefined,
    last_updated :: integer() | undefined
}).

-type message_metrics() :: #message_metrics{}.

-record(http_metrics, {
    total_requests = 0 :: non_neg_integer(),
    successful_responses = 0 :: non_neg_integer(),
    error_responses = 0 :: non_neg_integer(),
    avg_response_time_ms = 0 :: float(),
    endpoints = #{} :: map(),  % #{binary() => #{count => integer(), avg_time => float()}}
    status_codes = #{} :: map(), % #{integer() => integer()}
    last_updated :: integer() | undefined
}).

-type http_metrics() :: #http_metrics{}.

-record(sse_metrics, {
    total_connections = 0 :: non_neg_integer(),
    active_connections = 0 :: non_neg_integer(),
    total_events_sent = 0 :: non_neg_integer(),
    avg_connection_duration_ms = 0 :: float(),
    last_updated :: integer() | undefined
}).

-type sse_metrics() :: #sse_metrics{}.

-record(push_metrics, {
    total_sent = 0 :: non_neg_integer(),
    total_failed = 0 :: non_neg_integer(),
    success_rate = 1.0 :: float(),
    avg_send_time_ms = 0 :: float(),
    last_error_reason :: term() | undefined,
    last_updated :: integer() | undefined
}).

-type push_metrics() :: #push_metrics{}.

-record(system_metrics, {
    process_count = 0 :: non_neg_integer(),
    memory_used_mb = 0 :: float(),
    total_run_time_ms = 0 :: non_neg_integer(),
    task_table_size = 0 :: non_neg_integer(),
    last_updated :: integer() | undefined
}).

-type system_metrics() :: #system_metrics{}.

-record(metrics, {
    task :: task_metrics(),
    message :: message_metrics(),
    http :: http_metrics(),
    sse :: sse_metrics(),
    push :: push_metrics(),
    system :: system_metrics()
}).

-type metrics() :: #metrics{}.

-record(state, {
    metrics :: metrics(),
    start_time :: integer(),
    snapshot_interval_ms :: non_neg_integer(),
    snapshot_timer :: reference() | undefined
}).

-type state() :: #state{}.

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start the metrics server with default options
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    start_link(#{}).

%% @doc Start the metrics server with options
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Opts, []).

%% @doc Stop the metrics server
-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE).

%%% ============================================================================
%%% Task Metrics
%%% ============================================================================

%% @doc Record task creation
-spec task_created(binary()) -> ok.
task_created(TaskId) ->
    gen_server:cast(?MODULE, {task_created, TaskId}).

%% @doc Record task state transition
-spec task_state_changed(binary(), atom(), atom()) -> ok.
task_state_changed(TaskId, OldState, NewState) ->
    gen_server:cast(?MODULE, {task_state_changed, TaskId, OldState, NewState}).

%% @doc Record task completion
-spec task_completed(binary(), non_neg_integer()) -> ok.
task_completed(TaskId, ProcessingTimeMs) ->
    gen_server:cast(?MODULE, {task_completed, TaskId, ProcessingTimeMs}).

%% @doc Record task failure
-spec task_failed(binary(), term()) -> ok.
task_failed(TaskId, Reason) ->
    gen_server:cast(?MODULE, {task_failed, TaskId, Reason}).

%% @doc Record task cancellation
-spec task_canceled(binary()) -> ok.
task_canceled(TaskId) ->
    gen_server:cast(?MODULE, {task_canceled, TaskId}).

%% @doc Record task rejection
-spec task_rejected(binary()) -> ok.
task_rejected(TaskId) ->
    gen_server:cast(?MODULE, {task_rejected, TaskId}).

%%% ============================================================================
%%% Message Metrics
%%% ============================================================================

%% @doc Record message received
-spec message_received(binary()) -> ok.
message_received(MessageId) ->
    gen_server:cast(?MODULE, {message_received, MessageId}).

%% @doc Record message processed
-spec message_processed(binary(), non_neg_integer()) -> ok.
message_processed(MessageId, ProcessingTimeMs) ->
    gen_server:cast(?MODULE, {message_processed, MessageId, ProcessingTimeMs}).

%% @doc Record message processing error
-spec message_processing_error(binary(), term()) -> ok.
message_processing_error(MessageId, Reason) ->
    gen_server:cast(?MODULE, {message_processing_error, MessageId, Reason}).

%%% ============================================================================
%%% HTTP Metrics
%%% ============================================================================

%% @doc Record HTTP request
-spec http_request(binary(), binary(), binary(), integer()) -> ok.
http_request(Method, Path, UserAgent, RequestSize) ->
    gen_server:cast(?MODULE, {http_request, Method, Path, UserAgent, RequestSize}).

%% @doc Record HTTP response
-spec http_response(binary(), binary(), integer(), non_neg_integer(), non_neg_integer()) -> ok.
http_response(Method, Path, StatusCode, ResponseSize, ResponseTimeMs) ->
    gen_server:cast(?MODULE, {http_response, Method, Path, StatusCode, ResponseSize, ResponseTimeMs}).

%%% ============================================================================
%%% SSE Metrics
%%% ============================================================================

%% @doc Record SSE connection opened
-spec sse_connection_opened(binary()) -> ok.
sse_connection_opened(TaskId) ->
    gen_server:cast(?MODULE, {sse_connection_opened, TaskId}).

%% @doc Record SSE connection closed
-spec sse_connection_closed(binary(), non_neg_integer()) -> ok.
sse_connection_closed(TaskId, DurationMs) ->
    gen_server:cast(?MODULE, {sse_connection_closed, TaskId, DurationMs}).

%% @doc Record SSE event sent
-spec sse_event_sent(binary(), binary()) -> ok.
sse_event_sent(TaskId, EventType) ->
    gen_server:cast(?MODULE, {sse_event_sent, TaskId, EventType}).

%%% ============================================================================
%%% Push Notification Metrics
%%% ============================================================================

%% @doc Record push notification sent successfully
-spec push_notification_sent(binary(), non_neg_integer()) -> ok.
push_notification_sent(TaskId, SendTimeMs) ->
    gen_server:cast(?MODULE, {push_notification_sent, TaskId, SendTimeMs}).

%% @doc Record push notification failed
-spec push_notification_failed(binary(), term(), non_neg_integer()) -> ok.
push_notification_failed(TaskId, Reason, AttemptDurationMs) ->
    gen_server:cast(?MODULE, {push_notification_failed, TaskId, Reason, AttemptDurationMs}).

%%% ============================================================================
%%% System Metrics
%%% ============================================================================

%% @doc Record system-level metrics
-spec record_system_metrics() -> ok.
record_system_metrics() ->
    gen_server:cast(?MODULE, record_system_metrics).

%%% ============================================================================
%%% Query Metrics
%%% ============================================================================

%% @doc Get all task metrics
-spec get_task_metrics() -> task_metrics().
get_task_metrics() ->
    gen_server:call(?MODULE, get_task_metrics).

%% @doc Get all message metrics
-spec get_message_metrics() -> message_metrics().
get_message_metrics() ->
    gen_server:call(?MODULE, get_message_metrics).

%% @doc Get all HTTP metrics
-spec get_http_metrics() -> http_metrics().
get_http_metrics() ->
    gen_server:call(?MODULE, get_http_metrics).

%% @doc Get all SSE metrics
-spec get_sse_metrics() -> sse_metrics().
get_sse_metrics() ->
    gen_server:call(?MODULE, get_sse_metrics).

%% @doc Get all push notification metrics
-spec get_push_metrics() -> push_metrics().
get_push_metrics() ->
    gen_server:call(?MODULE, get_push_metrics).

%% @doc Get system metrics
-spec get_system_metrics() -> system_metrics().
get_system_metrics() ->
    gen_server:call(?MODULE, get_system_metrics).

%% @doc Get all metrics
-spec get_all_metrics() -> metrics().
get_all_metrics() ->
    gen_server:call(?MODULE, get_all_metrics).

%% @doc Get a specific metric by name
-spec get_metric(binary()) -> term().
get_metric(MetricName) ->
    gen_server:call(?MODULE, {get_metric, MetricName}).

%%% ============================================================================
%%% Reset Metrics
%%% ============================================================================

%% @doc Reset all metrics
-spec reset_metrics() -> ok.
reset_metrics() ->
    gen_server:call(?MODULE, reset_metrics).

%% @doc Reset a specific metric category
-spec reset_metric(task | message | http | sse | push | system) -> ok.
reset_metric(Category) ->
    gen_server:call(?MODULE, {reset_metric, Category}).

%%% ============================================================================
%%% gen_server Callbacks
%%% ============================================================================

-spec init(map()) -> {ok, state()} | {ok, state(), {continue, atom()}}.
init(Opts) ->
    SnapshotInterval = maps:get(snapshot_interval_ms, Opts, 60000),

    InitialMetrics = #metrics{
        task = #task_metrics{},
        message = #message_metrics{},
        http = #http_metrics{},
        sse = #sse_metrics{},
        push = #push_metrics{},
        system = #system_metrics{}
    },

    State = #state{
        metrics = InitialMetrics,
        start_time = erlang:system_time(millisecond),
        snapshot_interval_ms = SnapshotInterval,
        snapshot_timer = undefined
    },

    %% Schedule periodic snapshot
    Timer = schedule_snapshot(SnapshotInterval),

    %% Record initial system metrics
    {ok, State#state{snapshot_timer = Timer}, {continue, record_initial_metrics}}.

-spec handle_continue(atom(), state()) -> {ok, state()}.
handle_continue(record_initial_metrics, State) ->
    %% Record initial system metrics
    NewState = do_record_system_metrics(State),
    {ok, NewState}.

-spec handle_call(term(), {pid(), term()}, state()) ->
    {reply, term(), state()} | {noreply, state()}.
handle_call(get_task_metrics, _From, State) ->
    #state{metrics = Metrics} = State,
    {reply, Metrics#metrics.task, State};

handle_call(get_message_metrics, _From, State) ->
    #state{metrics = Metrics} = State,
    {reply, Metrics#metrics.message, State};

handle_call(get_http_metrics, _From, State) ->
    #state{metrics = Metrics} = State,
    {reply, Metrics#metrics.http, State};

handle_call(get_sse_metrics, _From, State) ->
    #state{metrics = Metrics} = State,
    {reply, Metrics#metrics.sse, State};

handle_call(get_push_metrics, _From, State) ->
    #state{metrics = Metrics} = State,
    {reply, Metrics#metrics.push, State};

handle_call(get_system_metrics, _From, State) ->
    #state{metrics = Metrics} = State,
    {reply, Metrics#metrics.system, State};

handle_call(get_all_metrics, _From, State) ->
    #state{metrics = Metrics} = State,
    {reply, Metrics, State};

handle_call({get_metric, MetricName}, _From, State) ->
    Value = do_get_metric(MetricName, State),
    {reply, Value, State};

handle_call(reset_metrics, _From, State) ->
    InitialMetrics = #metrics{
        task = #task_metrics{},
        message = #message_metrics{},
        http = #http_metrics{},
        sse = #sse_metrics{},
        push = #push_metrics{},
        system = #system_metrics{}
    },
    NewState = State#state{metrics = InitialMetrics},
    logger:info("Metrics reset", #{domain => [a2a, metrics]}),
    {reply, ok, NewState};

handle_call({reset_metric, Category}, _From, State) ->
    #state{metrics = Metrics} = State,
    NewMetrics = case Category of
        task -> Metrics#metrics{task = #task_metrics{}};
        message -> Metrics#metrics{message = #message_metrics{}};
        http -> Metrics#metrics{http = #http_metrics{}};
        sse -> Metrics#metrics{sse = #sse_metrics{}};
        push -> Metrics#metrics{push = #push_metrics{}};
        system -> Metrics#metrics{system = #system_metrics{}}
    end,
    NewState = State#state{metrics = NewMetrics},
    logger:info("Category metrics reset", #{category => Category, domain => [a2a, metrics]}),
    {reply, ok, NewState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast({task_created, TaskId}, State) ->
    #state{metrics = Metrics} = State,
    TaskMetrics = Metrics#metrics.task,
    NewTaskMetrics = TaskMetrics#task_metrics{
        total_created = TaskMetrics#task_metrics.total_created + 1,
        active = TaskMetrics#task_metrics.active + 1,
        last_updated = erlang:system_time(millisecond)
    },
    logger:debug("Task created", #{
        task_id => TaskId,
        domain => [a2a, metrics, task]
    }),
    {noreply, State#state{metrics = Metrics#metrics{task = NewTaskMetrics}}};

handle_cast({task_state_changed, TaskId, OldState, NewState}, State) ->
    #state{metrics = Metrics} = State,
    TaskMetrics = Metrics#metrics.task,
    NewTaskMetrics = TaskMetrics#task_metrics{
        state_transitions = TaskMetrics#task_metrics.state_transitions + 1,
        last_updated = erlang:system_time(millisecond)
    },
    logger:debug("Task state changed", #{
        task_id => TaskId,
        old_state => OldState,
        new_state => NewState,
        domain => [a2a, metrics, task]
    }),
    {noreply, State#state{metrics = Metrics#metrics{task = NewTaskMetrics}}};

handle_cast({task_completed, TaskId, ProcessingTimeMs}, State) ->
    #state{metrics = Metrics} = State,
    TaskMetrics = Metrics#metrics.task,
    OldAvg = TaskMetrics#task_metrics.avg_processing_time_ms,
    Completed = TaskMetrics#task_metrics.completed + 1,
    NewAvg = update_average(OldAvg, Completed - 1, ProcessingTimeMs),
    NewTaskMetrics = TaskMetrics#task_metrics{
        active = TaskMetrics#task_metrics.active - 1,
        completed = Completed,
        avg_processing_time_ms = NewAvg,
        last_updated = erlang:system_time(millisecond)
    },
    logger:info("Task completed", #{
        task_id => TaskId,
        processing_time_ms => ProcessingTimeMs,
        domain => [a2a, metrics, task]
    }),
    {noreply, State#state{metrics = Metrics#metrics{task = NewTaskMetrics}}};

handle_cast({task_failed, TaskId, Reason}, State) ->
    #state{metrics = Metrics} = State,
    TaskMetrics = Metrics#metrics.task,
    NewTaskMetrics = TaskMetrics#task_metrics{
        active = TaskMetrics#task_metrics.active - 1,
        failed = TaskMetrics#task_metrics.failed + 1,
        last_updated = erlang:system_time(millisecond)
    },
    logger:warning("Task failed", #{
        task_id => TaskId,
        reason => Reason,
        domain => [a2a, metrics, task]
    }),
    {noreply, State#state{metrics = Metrics#metrics{task = NewTaskMetrics}}};

handle_cast({task_canceled, TaskId}, State) ->
    #state{metrics = Metrics} = State,
    TaskMetrics = Metrics#metrics.task,
    NewTaskMetrics = TaskMetrics#task_metrics{
        active = TaskMetrics#task_metrics.active - 1,
        canceled = TaskMetrics#task_metrics.canceled + 1,
        last_updated = erlang:system_time(millisecond)
    },
    logger:info("Task canceled", #{
        task_id => TaskId,
        domain => [a2a, metrics, task]
    }),
    {noreply, State#state{metrics = Metrics#metrics{task = NewTaskMetrics}}};

handle_cast({task_rejected, TaskId}, State) ->
    #state{metrics = Metrics} = State,
    TaskMetrics = Metrics#metrics.task,
    NewTaskMetrics = TaskMetrics#task_metrics{
        active = TaskMetrics#task_metrics.active - 1,
        rejected = TaskMetrics#task_metrics.rejected + 1,
        last_updated = erlang:system_time(millisecond)
    },
    logger:info("Task rejected", #{
        task_id => TaskId,
        domain => [a2a, metrics, task]
    }),
    {noreply, State#state{metrics = Metrics#metrics{task = NewTaskMetrics}}};

handle_cast({message_received, MessageId}, State) ->
    #state{metrics = Metrics} = State,
    MessageMetrics = Metrics#metrics.message,
    NewMessageMetrics = MessageMetrics#message_metrics{
        total_received = MessageMetrics#message_metrics.total_received + 1,
        last_updated = erlang:system_time(millisecond)
    },
    logger:debug("Message received", #{
        message_id => MessageId,
        domain => [a2a, metrics, message]
    }),
    {noreply, State#state{metrics = Metrics#metrics{message = NewMessageMetrics}}};

handle_cast({message_processed, MessageId, ProcessingTimeMs}, State) ->
    #state{metrics = Metrics} = State,
    MessageMetrics = Metrics#metrics.message,
    OldAvg = MessageMetrics#message_metrics.avg_processing_time_ms,
    Processed = MessageMetrics#message_metrics.total_processed + 1,
    NewAvg = update_average(OldAvg, Processed - 1, ProcessingTimeMs),
    NewMessageMetrics = MessageMetrics#message_metrics{
        total_processed = Processed,
        avg_processing_time_ms = NewAvg,
        last_updated = erlang:system_time(millisecond)
    },
    logger:debug("Message processed", #{
        message_id => MessageId,
        processing_time_ms => ProcessingTimeMs,
        domain => [a2a, metrics, message]
    }),
    {noreply, State#state{metrics = Metrics#metrics{message = NewMessageMetrics}}};

handle_cast({message_processing_error, MessageId, Reason}, State) ->
    #state{metrics = Metrics} = State,
    MessageMetrics = Metrics#metrics.message,
    NewMessageMetrics = MessageMetrics#message_metrics{
        total_errors = MessageMetrics#message_metrics.total_errors + 1,
        last_error_reason = format_error_reason(Reason),
        last_updated = erlang:system_time(millisecond)
    },
    logger:warning("Message processing error", #{
        message_id => MessageId,
        reason => Reason,
        domain => [a2a, metrics, message]
    }),
    {noreply, State#state{metrics = Metrics#metrics{message = NewMessageMetrics}}};

handle_cast({http_request, _Method, _Path, _UserAgent, _RequestSize}, State) ->
    #state{metrics = Metrics} = State,
    HttpMetrics = Metrics#metrics.http,
    NewHttpMetrics = HttpMetrics#http_metrics{
        total_requests = HttpMetrics#http_metrics.total_requests + 1,
        last_updated = erlang:system_time(millisecond)
    },
    {noreply, State#state{metrics = Metrics#metrics{http = NewHttpMetrics}}};

handle_cast({http_response, Method, Path, StatusCode, _ResponseSize, ResponseTimeMs}, State) ->
    #state{metrics = Metrics} = State,
    HttpMetrics = Metrics#metrics.http,

    %% Update success/error counts
    {SuccessCount, ErrorCount} = if
        StatusCode >= 200, StatusCode < 300 ->
            {HttpMetrics#http_metrics.successful_responses + 1,
             HttpMetrics#http_metrics.error_responses};
        true ->
            {HttpMetrics#http_metrics.successful_responses,
             HttpMetrics#http_metrics.error_responses + 1}
    end,

    %% Update average response time
    OldAvg = HttpMetrics#http_metrics.avg_response_time_ms,
    TotalResponses = SuccessCount + ErrorCount,
    NewAvg = update_average(OldAvg, TotalResponses - 1, ResponseTimeMs),

    %% Update endpoint stats
    EndpointKey = <<Method/binary, ":", Path/binary>>,
    Endpoints = HttpMetrics#http_metrics.endpoints,
    EndpointStats = maps:get(EndpointKey, Endpoints, #{count => 0, avg_time => 0.0}),
    OldCount = maps:get(count, EndpointStats, 0),
    OldEndpointAvg = maps:get(avg_time, EndpointStats, 0.0),
    NewEndpointAvg = update_average(OldEndpointAvg, OldCount, ResponseTimeMs),
    NewEndpoints = maps:put(EndpointKey, #{
        count => OldCount + 1,
        avg_time => NewEndpointAvg
    }, Endpoints),

    %% Update status code counts
    StatusCodes = HttpMetrics#http_metrics.status_codes,
    NewStatusCodes = maps:put(StatusCode,
        maps:get(StatusCode, StatusCodes, 0) + 1, StatusCodes),

    NewHttpMetrics = HttpMetrics#http_metrics{
        successful_responses = SuccessCount,
        error_responses = ErrorCount,
        avg_response_time_ms = NewAvg,
        endpoints = NewEndpoints,
        status_codes = NewStatusCodes,
        last_updated = erlang:system_time(millisecond)
    },

    logger:debug("HTTP response", #{
        method => Method,
        path => Path,
        status_code => StatusCode,
        response_time_ms => ResponseTimeMs,
        domain => [a2a, metrics, http]
    }),

    {noreply, State#state{metrics = Metrics#metrics{http = NewHttpMetrics}}};

handle_cast({sse_connection_opened, TaskId}, State) ->
    #state{metrics = Metrics} = State,
    SseMetrics = Metrics#metrics.sse,
    NewSseMetrics = SseMetrics#sse_metrics{
        total_connections = SseMetrics#sse_metrics.total_connections + 1,
        active_connections = SseMetrics#sse_metrics.active_connections + 1,
        last_updated = erlang:system_time(millisecond)
    },
    logger:info("SSE connection opened", #{
        task_id => TaskId,
        domain => [a2a, metrics, sse]
    }),
    {noreply, State#state{metrics = Metrics#metrics{sse = NewSseMetrics}}};

handle_cast({sse_connection_closed, TaskId, DurationMs}, State) ->
    #state{metrics = Metrics} = State,
    SseMetrics = Metrics#metrics.sse,
    OldAvg = SseMetrics#sse_metrics.avg_connection_duration_ms,
    TotalClosed = SseMetrics#sse_metrics.total_connections - SseMetrics#sse_metrics.active_connections + 1,
    NewAvg = update_average(OldAvg, TotalClosed - 1, DurationMs),
    NewSseMetrics = SseMetrics#sse_metrics{
        active_connections = SseMetrics#sse_metrics.active_connections - 1,
        avg_connection_duration_ms = NewAvg,
        last_updated = erlang:system_time(millisecond)
    },
    logger:info("SSE connection closed", #{
        task_id => TaskId,
        duration_ms => DurationMs,
        domain => [a2a, metrics, sse]
    }),
    {noreply, State#state{metrics = Metrics#metrics{sse = NewSseMetrics}}};

handle_cast({sse_event_sent, TaskId, EventType}, State) ->
    #state{metrics = Metrics} = State,
    SseMetrics = Metrics#metrics.sse,
    NewSseMetrics = SseMetrics#sse_metrics{
        total_events_sent = SseMetrics#sse_metrics.total_events_sent + 1,
        last_updated = erlang:system_time(millisecond)
    },
    logger:debug("SSE event sent", #{
        task_id => TaskId,
        event_type => EventType,
        domain => [a2a, metrics, sse]
    }),
    {noreply, State#state{metrics = Metrics#metrics{sse = NewSseMetrics}}};

handle_cast({push_notification_sent, TaskId, SendTimeMs}, State) ->
    #state{metrics = Metrics} = State,
    PushMetrics = Metrics#metrics.push,
    OldAvg = PushMetrics#push_metrics.avg_send_time_ms,
    Sent = PushMetrics#push_metrics.total_sent + 1,
    NewAvg = update_average(OldAvg, Sent - 1, SendTimeMs),

    %% Calculate success rate
    Total = Sent + PushMetrics#push_metrics.total_failed,
    SuccessRate = case Total of
        0 -> 1.0;
        _ -> Sent / Total
    end,

    NewPushMetrics = PushMetrics#push_metrics{
        total_sent = Sent,
        success_rate = SuccessRate,
        avg_send_time_ms = NewAvg,
        last_updated = erlang:system_time(millisecond)
    },
    logger:info("Push notification sent", #{
        task_id => TaskId,
        send_time_ms => SendTimeMs,
        domain => [a2a, metrics, push]
    }),
    {noreply, State#state{metrics = Metrics#metrics{push = NewPushMetrics}}};

handle_cast({push_notification_failed, TaskId, Reason, AttemptDurationMs}, State) ->
    #state{metrics = Metrics} = State,
    PushMetrics = Metrics#metrics.push,
    Failed = PushMetrics#push_metrics.total_failed + 1,

    %% Calculate success rate
    Total = PushMetrics#push_metrics.total_sent + Failed,
    SuccessRate = case Total of
        0 -> 1.0;
        _ -> PushMetrics#push_metrics.total_sent / Total
    end,

    NewPushMetrics = PushMetrics#push_metrics{
        total_failed = Failed,
        success_rate = SuccessRate,
        last_error_reason = Reason,
        last_updated = erlang:system_time(millisecond)
    },
    logger:warning("Push notification failed", #{
        task_id => TaskId,
        reason => Reason,
        attempt_duration_ms => AttemptDurationMs,
        domain => [a2a, metrics, push]
    }),
    {noreply, State#state{metrics = Metrics#metrics{push = NewPushMetrics}}};

handle_cast(record_system_metrics, State) ->
    NewState = do_record_system_metrics(State),
    {noreply, NewState};

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(snapshot_timeout, State) ->
    #state{snapshot_interval_ms = Interval} = State,
    %% Record system metrics periodically
    NewState = do_record_system_metrics(State),

    %% Log metrics summary
    log_metrics_summary(NewState),

    %% Reschedule
    Timer = schedule_snapshot(Interval),
    {noreply, NewState#state{snapshot_timer = Timer}};

handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, #state{snapshot_timer = Timer}) ->
    %% Cancel timer if exists
    case Timer of
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

%% @doc Schedule periodic snapshot
-spec schedule_snapshot(non_neg_integer()) -> reference().
schedule_snapshot(Interval) ->
    erlang:send_after(Interval, self(), snapshot_timeout).

%% @doc Record system-level metrics
-spec do_record_system_metrics(state()) -> state().
do_record_system_metrics(State) ->
    #state{metrics = Metrics, start_time = StartTime} = State,

    %% Get process count
    ProcessCount = erlang:system_info(process_count),

    %% Get memory usage (in MB)
    MemoryWords = erlang:memory(total),
    MemoryMB = MemoryWords * erlang:wordsize() / (1024 * 1024),

    %% Get total run time
    TotalRunTime = erlang:system_time(millisecond) - StartTime,

    %% Get task table size
    TaskTableSize = case catch a2a_task_store:task_count() of
        Count when is_integer(Count) -> Count;
        _ -> 0
    end,

    SystemMetrics = #system_metrics{
        process_count = ProcessCount,
        memory_used_mb = MemoryMB,
        total_run_time_ms = TotalRunTime,
        task_table_size = TaskTableSize,
        last_updated = erlang:system_time(millisecond)
    },

    State#state{metrics = Metrics#metrics{system = SystemMetrics}}.

%% @doc Get a specific metric by name
-spec do_get_metric(binary(), state()) -> term().
do_get_metric(<<"task.total_created">>, #state{metrics = M}) ->
    (M#metrics.task)#task_metrics.total_created;
do_get_metric(<<"task.active">>, #state{metrics = M}) ->
    (M#metrics.task)#task_metrics.active;
do_get_metric(<<"task.completed">>, #state{metrics = M}) ->
    (M#metrics.task)#task_metrics.completed;
do_get_metric(<<"task.failed">>, #state{metrics = M}) ->
    (M#metrics.task)#task_metrics.failed;
do_get_metric(<<"task.avg_processing_time_ms">>, #state{metrics = M}) ->
    (M#metrics.task)#task_metrics.avg_processing_time_ms;
do_get_metric(<<"message.total_received">>, #state{metrics = M}) ->
    (M#metrics.message)#message_metrics.total_received;
do_get_metric(<<"message.total_processed">>, #state{metrics = M}) ->
    (M#metrics.message)#message_metrics.total_processed;
do_get_metric(<<"message.avg_processing_time_ms">>, #state{metrics = M}) ->
    (M#metrics.message)#message_metrics.avg_processing_time_ms;
do_get_metric(<<"http.total_requests">>, #state{metrics = M}) ->
    (M#metrics.http)#http_metrics.total_requests;
do_get_metric(<<"http.avg_response_time_ms">>, #state{metrics = M}) ->
    (M#metrics.http)#http_metrics.avg_response_time_ms;
do_get_metric(<<"sse.active_connections">>, #state{metrics = M}) ->
    (M#metrics.sse)#sse_metrics.active_connections;
do_get_metric(<<"push.total_sent">>, #state{metrics = M}) ->
    (M#metrics.push)#push_metrics.total_sent;
do_get_metric(<<"push.success_rate">>, #state{metrics = M}) ->
    (M#metrics.push)#push_metrics.success_rate;
do_get_metric(<<"system.process_count">>, #state{metrics = M}) ->
    (M#metrics.system)#system_metrics.process_count;
do_get_metric(<<"system.memory_used_mb">>, #state{metrics = M}) ->
    (M#metrics.system)#system_metrics.memory_used_mb;
do_get_metric(_, _) ->
    undefined.

%% @doc Update running average
-spec update_average(float(), non_neg_integer(), non_neg_integer()) -> float().
update_average(OldAvg, Count, NewValue) when Count =:= 0 ->
    NewValue * 1.0;
update_average(OldAvg, Count, NewValue) ->
    (OldAvg * Count + NewValue) / (Count + 1).

%% @doc Format error reason for logging
-spec format_error_reason(term()) -> binary().
format_error_reason(Reason) when is_binary(Reason) ->
    Reason;
format_error_reason(Reason) when is_atom(Reason) ->
    atom_to_binary(Reason, utf8);
format_error_reason(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).

%% @doc Log metrics summary
-spec log_metrics_summary(state()) -> ok.
log_metrics_summary(#state{metrics = Metrics}) ->
    Task = Metrics#metrics.task,
    Message = Metrics#metrics.message,
    Http = Metrics#metrics.http,
    Sse = Metrics#metrics.sse,
    Push = Metrics#metrics.push,
    System = Metrics#metrics.system,

    logger:info("Metrics summary", #{
        task => #{
            active => Task#task_metrics.active,
            completed => Task#task_metrics.completed,
            failed => Task#task_metrics.failed,
            avg_processing_time_ms => Task#task_metrics.avg_processing_time_ms
        },
        message => #{
            total_received => Message#message_metrics.total_received,
            total_processed => Message#message_metrics.total_processed,
            avg_processing_time_ms => Message#message_metrics.avg_processing_time_ms
        },
        http => #{
            total_requests => Http#http_metrics.total_requests,
            avg_response_time_ms => Http#http_metrics.avg_response_time_ms
        },
        sse => #{
            active_connections => Sse#sse_metrics.active_connections
        },
        push => #{
            total_sent => Push#push_metrics.total_sent,
            success_rate => Push#push_metrics.success_rate
        },
        system => #{
            process_count => System#system_metrics.process_count,
            memory_used_mb => System#system_metrics.memory_used_mb
        },
        domain => [a2a, metrics]
    }),
    ok.
