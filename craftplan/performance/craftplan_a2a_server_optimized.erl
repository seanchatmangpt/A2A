%%% @doc Optimized Craftplan A2A Server
%%% Enhanced with performance monitoring, task queuing, and async processing

-module(craftplan_a2a_server_optimized).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([submit_task/2, get_task/1, cancel_task/1, send_message/2]).
-export([list_tasks/0, get_status/0, get_queue_status/0]).
-export([start_task_processor/0, stop_task_processor/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include("performance.hrl").

-define(SERVER, ?MODULE).
-define(DEFAULT_PORT, 8080).
-define(QUEUE_SIZE, 1000).
-define(MAX_TASK_LIFETIME, 86400000). % 24 hours
-define(TASK_TIMEOUT, 300000). % 5 minutes
-define(MAX_CONCURRENT_TASKS, 50).

-record(state, {
    port :: integer(),
    agent_id :: binary(),
    tasks :: map(),  #{task_id() => task()}
    task_queue :: queue(),
    active_tasks :: set(),
    sse_clients :: map(),  #{client_id() => pid()}
    metrics :: map(),
    cache :: binary(),
    pool :: binary(),
    enabled :: boolean()
}).

-record(task, {
    id :: binary(),
    status :: submitted | working | input_required | auth_required | completed | failed | canceled,
    task_type :: binary(),
    created_at :: integer(),
    updated_at :: integer(),
    priority :: high | normal | low,
    artifacts :: list(map()),
    messages :: list(map()),
    state :: term(),
    retry_count :: integer(),
    timeout :: integer()
}).

-record(queue_item, {
    task_id :: binary(),
    priority :: high | normal | low,
    inserted_at :: integer()
}).

-type task_id() :: binary().
-type task() :: #task{}.

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

%% @doc Submit a new task to the agent
-spec submit_task(binary(), map()) -> {ok, task_id()} | {error, term()}.
submit_task(TaskType, Params) ->
    gen_server:call(?SERVER, {submit_task, TaskType, Params}, 10000).

%% @doc Get task details
-spec get_task(task_id()) -> {ok, task()} | {error, not_found}.
get_task(TaskId) ->
    gen_server:call(?SERVER, {get_task, TaskId}).

%% @doc Cancel a task
-spec cancel_task(task_id()) -> ok | {error, term()}.
cancel_task(TaskId) ->
    gen_server:call(?SERVER, {cancel_task, TaskId}).

%% @doc Send a message related to a task
-spec send_message(task_id(), map()) -> ok | {error, term()}.
send_message(TaskId, Message) ->
    gen_server:call(?SERVER, {send_message, TaskId, Message}, 5000).

%% @doc List all tasks
-spec list_tasks() -> {ok, [task()]}.
list_tasks() ->
    gen_server:call(?SERVER, list_tasks).

%% @doc Get agent status
-spec get_status() -> map().
get_status() ->
    gen_server:call(?SERVER, get_status).

%% @doc Get queue status
-spec get_queue_status() -> map().
get_queue_status() ->
    gen_server:call(?SERVER, get_queue_status).

%% @doc Start task processor
-spec start_task_processor() -> ok.
start_task_processor() ->
    gen_server:call(?SERVER, start_task_processor).

%% @doc Stop task processor
-spec stop_task_processor() -> ok.
stop_task_processor() ->
    gen_server:call(?SERVER, stop_task_processor).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    Port = application:get_env(craftplan_a2a, port, ?DEFAULT_PORT),
    AgentID = <<"craftplan-erp-agent-optimized">>,
    CacheName = <<"a2a_cache">>,
    PoolName = <<"a2a-task-pool">>,

    %% Start components
    {ok, APIClient} = craftplan_api_client:start_link(),
    {ok, MetricsPid} = performance_metrics:start_link(),
    {ok, MonitorPid} = performance_monitor:start_link(),
    {ok, PoolPid} = http_pool:start_link(),
    {ok, CachePid} = cache_manager:start_link(),

    %% Start Cowboy HTTP server
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/a2a", ?MODULE, []},
            {"/a2a/tasks/:taskid", ?MODULE, []},
            {"/a2a/queue", ?MODULE, []},
            {"/a2a/metrics", ?MODULE, []},
            {"/sse", ?MODULE, []},
            {"/health", ?MODULE, []},
            {"/.well-known/agent-card", ?MODULE, []}
        ]}
    ]),

    {ok, _} = cowboy:start_clear(a2a_http,
        [{port, Port}, {num_acceptors, 5}, {max_connections, 5000}],
        #{
            env => #{dispatch => Dispatch},
            middlewares => [cowboy_compress_h, ?MODULE]
        }
    ),

    io:format("Optimized Craftplan A2A Server listening on port ~p~n", [Port]),
    io:format("Task processor enabled with max ~p concurrent tasks~n", [?MAX_CONCURRENT_TASKS]),

    State = #state{
        port = Port,
        agent_id = AgentID,
        tasks = #{},
        task_queue = queue:new(),
        active_tasks = sets:new(),
        sse_clients = #{},
        metrics => #{tasks_submitted => 0, tasks_completed => 0, tasks_failed => 0},
        cache = CacheName,
        pool = PoolName,
        enabled = true
    },

    %% Register performance alerts
    register_a2a_alerts(),

    %% Start task processor
    self() ! start_task_processing,

    {ok, State}.

handle_call({submit_task, TaskType, Params}, _From, State) ->
    Start = os:system_time(microsecond),
    TaskId = generate_task_id(),

    %% Determine task priority
    Priority = determine_priority(TaskType, Params),

    Task = #task{
        id = TaskId,
        status = submitted,
        task_type = TaskType,
        created_at = os:system_time(millisecond),
        updated_at = os:system_time(millisecond),
        priority = Priority,
        artifacts = [],
        messages = [],
        state => #{params => Params},
        retry_count = 0,
        timeout = maps:get(timeout, Params, ?TASK_TIMEOUT)
    },

    %% Add to task queue
    QueueItem = #queue_item{
        task_id = TaskId,
        priority = Priority,
        inserted_at = os:system_time(millisecond)
    },

    NewQueue = queue:in(QueueItem, State#state.task_queue),
    NewTasks = maps:put(TaskId, Task, State#state.tasks),
    NewMetrics = State#state.metrics#{
        tasks_submitted => State#state.metrics.tasks_submitted + 1,
        queue_size => queue:len(NewQueue)
    },

    performance_metrics:increment_counter(<<"a2a.tasks_submitted">>, 1),
    performance_metrics:increment_counter(<<"a2a.tasks_submitted." ++ binary_to_list(TaskType)>>, 1),
    performance_metrics:record_timing(<<"a2a.task_submission">>, os:system_time(microsecond) - Start, #{type => TaskType}),

    %% Notify SSE clients
    broadcast_task_event(TaskId, <<"queued">>, Task),

    io:format("Task ~p submitted with priority ~p~n", [TaskId, Priority]),

    {reply, {ok, TaskId}, State#state{task_queue = NewQueue, tasks = NewTasks, metrics = NewMetrics}};

handle_call({get_task, TaskId}, _From, State) ->
    case maps:get(TaskId, State#state.tasks, undefined) of
        undefined -> {reply, {error, not_found}, State};
        Task -> {reply, {ok, Task}, State}
    end;

handle_call({cancel_task, TaskId}, _From, State) ->
    case maps:get(TaskId, State#state.tasks, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Task ->
            NewTask = cancel_task_state(Task),
            NewTasks = maps:put(TaskId, NewTask, State#state.tasks),

            %% Remove from queue if queued
            NewQueue = remove_from_queue(State#state.task_queue, TaskId),

            %% If active, cancel the task handler
            case sets:is_element(TaskId, State#state.active_tasks) of
                true ->
                    craftplan_task_handler:cancel(TaskId);
                false ->
                    ok
            end,

            broadcast_task_event(TaskId, <<"canceled">>, NewTask),

            performance_metrics:increment_counter(<<"a2a.tasks_canceled">>, 1),

            {reply, ok, State#state{task_queue = NewQueue, tasks = NewTasks}}
    end;

handle_call({send_message, TaskId, Message}, _From, State) ->
    case maps:get(TaskId, State#state.tasks, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        Task ->
            case sets:is_element(TaskId, State#state.active_tasks) of
                true ->
                    craftplan_task_handler:send_message(TaskId, Message),
                    NewTask = Task#task{messages = [Message | Task#task.messages], updated_at = os:system_time(millisecond)},
                    NewTasks = maps:put(TaskId, NewTask, State#state.tasks),
                    {reply, ok, State#state{tasks = NewTasks}};
                false ->
                    {reply, {error, task_not_active}, State}
            end
    end;

handle_call(list_tasks, _From, State) ->
    TaskList = maps:values(State#state.tasks),
    {reply, {ok, TaskList}, State};

handle_call(get_status, _From, State) ->
    Status = #{
        <<"agent_id">> => State#state.agent_id,
        <<"status">> => <<"running">>,
        <<"tasks">> => maps:size(State#state.tasks),
        <<"active_tasks">> => sets:size(State#state.active_tasks),
        <<"queue_size">> => queue:len(State#state.task_queue),
        <<"metrics">> => State#state.metrics,
        <<"timestamp">> => os:system_time(millisecond)
    },
    {reply, Status, State};

handle_call(get_queue_status, _From, State) ->
    QueueStats = #{
        <<"queue_size">> => queue:len(State#state.task_queue),
        <<"active_tasks">> => sets:size(State#state.active_tasks),
        <<"max_concurrent">> => ?MAX_CONCURRENT_TASKS,
        <<"queue_status">> => get_queue_breakdown(State#state.task_queue),
        <<"active_breakdown">> => get_active_breakdown(State#state.active_tasks, State#state.tasks)
    },
    {reply, QueueStats, State};

handle_call(start_task_processor, _From, State) ->
    %% Start task processing timer
    Timer = erlang:send_after(100, self(), process_next_task),

    NewState = State#state{
        metrics = State#state.metrics#{processor_enabled => true}
    },

    io:format("Task processor started~n"),
    {reply, ok, NewState#state{metrics = NewState#state.metrics#{processor_timer => Timer}}};

handle_call(stop_task_processor, _From, State) ->
    case State#state.metrics of
        #{processor_timer := Timer} ->
            erlang:cancel_timer(Timer);
        _ ->
            ok
    end,

    NewState = State#state{
        metrics = State#state.metrics#{processor_enabled => false}
    },

    io:format("Task processor stopped~n"),
    {reply, ok, NewState};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(start_task_processing, State) ->
    %% Start task processor
    self() ! process_next_task,
    {noreply, State};

handle_info(process_next_task, State) ->
    %% Check if we can start more tasks
    case can_start_more_tasks(State) of
        true ->
            process_next_task_from_queue(State);
        false ->
            ok
    end,

    %% Schedule next processing
    case State#state.metrics of
        #{processor_enabled := true} ->
            Timer = erlang:send_after(100, self(), process_next_task),
            {noreply, State#state{metrics = State#state.metrics#{processor_timer => Timer}};
        _ ->
            {noreply, State}
    end;

handle_info({task_update, TaskId, Update}, State) ->
    case maps:get(TaskId, State#state.tasks, undefined) of
        undefined ->
            {noreply, State};
        Task ->
            NewTask = apply_task_update(Task, Update),
            NewTasks = maps:put(TaskId, NewTask, State#state.tasks),

            %% Remove from active tasks if completed
            case NewTask#task.status of
                completed ->
                    NewActiveTasks = sets:del_element(TaskId, State#state.active_tasks),
                    broadcast_task_event(TaskId, <<"completed">>, NewTask),
                    performance_metrics:increment_counter(<<"a2a.tasks_completed">>, 1);
                failed ->
                    NewActiveTasks = sets:del_element(TaskId, State#state.active_tasks),
                    broadcast_task_event(TaskId, <<"failed">>, NewTask),
                    performance_metrics:increment_counter(<<"a2a.tasks_failed">>, 1);
                _ ->
                    NewActiveTasks = State#state.active_tasks
            end,

            UpdatedMetrics = case NewTask#task.status of
                completed -> State#state.metrics#{tasks_completed => State#state.metrics.tasks_completed + 1};
                failed -> State#state.metrics#{tasks_failed => State#state.metrics.tasks_failed + 1};
                _ -> State#state.metrics
            end,

            {noreply, State#state{tasks = NewTasks, active_tasks = NewActiveTasks, metrics = UpdatedMetrics}}
    end;

handle_info({sse_subscribe, Pid}, State) ->
    ClientId = generate_client_id(),
    NewClients = maps:put(ClientId, Pid, State#state.sse_clients),

    %% Send current status to new client
    send_current_status(Pid, State),

    io:format("SSE client subscribed: ~p~n", [ClientId]),
    {noreply, State#state{sse_clients = NewClients}};

handle_info({sse_unsubscribe, Pid}, State) ->
    NewClients = maps:filter(fun(_, V) -> V =/= Pid end, State#state.sse_clients),
    {noreply, State#state{sse_clients = NewClients}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

process_next_task_from_queue(State) ->
    case queue:out(State#state.task_queue) of
        {{value, QueueItem}, NewQueue} ->
            TaskId = QueueItem#queue_item.task_id,
            case maps:get(TaskId, State#state.tasks, undefined) of
                undefined ->
                    %% Task was removed, continue processing
                    self() ! process_next_task,
                    {noreply, State#state{task_queue = NewQueue}};
                Task ->
                    start_task_execution(Task, State)
            end;
        {empty, _} ->
            %% No more tasks in queue
            {noreply, State}
    end.

start_task_execution(Task, State) ->
    TaskId = Task#task.id,
    TaskType = Task#task.task_type,
    Params = Task#task.state.params,

    Start = os:system_time(microsecond),

    case craftplan_task_handler:start(TaskId, TaskType, Params) of
        {ok, TaskPid} ->
            NewTask = Task#task{status = working, state => #{params => Params, handler => TaskPid}},
            NewTasks = maps:put(TaskId, NewTask, State#state.tasks),
            NewActiveTasks = sets:add_element(TaskId, State#state.active_tasks),

            performance_metrics:record_timing(<<"a2a.task_start">>, os:system_time(microsecond) - Start, #{type => TaskType}),
            performance_metrics:increment_counter(<<"a2a.tasks_active">>, 1),

            broadcast_task_event(TaskId, <<"started">>, NewTask),
            {noreply, State#state{tasks = NewTasks, active_tasks = NewActiveTasks, task_queue = queue:out_r(State#state.task_queue)}};
        {error, Reason} ->
            %% Task failed to start, retry if possible
            case Task#task.retry_count < 3 of
                true ->
                    RetryTask = Task#task{retry_count = Task#task.retry_count + 1},
                    retry_task(RetryTask, State);
                false ->
                    FailedTask = Task#task{status = failed},
                    NewTasks = maps:put(TaskId, FailedTask, State#state.tasks),
                    broadcast_task_event(TaskId, <<"failed">>, FailedTask),
                    performance_metrics:increment_counter(<<"a2a.tasks_failed">>, 1),
                    {noreply, State#state{tasks = NewTasks}}
            end
    end.

retry_task(Task, State) ->
    TaskId = Task#task.id,
    QueueItem = #queue_item{
        task_id = TaskId,
        priority = Task#task.priority,
        inserted_at = os:system_time(millisecond)
    },

    NewQueue = queue:in(QueueItem, State#state.task_queue),
    NewTasks = maps:put(TaskId, Task#task{status = submitted}, State#state.tasks),

    broadcast_task_event(TaskId, <<"retry">>, Task),
    io:format("Retrying task ~p (~p/3)~n", [TaskId, Task#task.retry_count]),

    {noreply, State#state{task_queue = NewQueue, tasks = NewTasks}}.

can_start_more_tasks(State) ->
    sets:size(State#state.active_tasks) < ?MAX_CONCURRENT_TASKS andalso
    not queue:is_empty(State#state.task_queue).

remove_from_queue(Queue, TaskId) ->
    QueueItems = queue:to_list(Queue),
    Filtered = [Item || Item <- QueueItems, Item#queue_item.task_id =/= TaskId],
    queue:from_list(Filtered).

determine_priority(TaskType, Params) ->
    case TaskType of
        <<"order_management">> when maps:get(<<"operation">>, Params, <<"create">>) =:= <<"create">> -> high;
        <<"production_planning">> when maps:get(<<"operation">>, Params, <<"create">>) =:= <<"create">> -> high;
        <<"shipping">> when maps:get(<<"operation">>, Params, <<"create">>) =:= <<"create">> -> high;
        _ -> normal
    end.

cancel_task_state(Task) ->
    Task#task{
        status = canceled,
        updated_at = os:system_time(millisecond)
    }.

apply_task_update(Task, Update) ->
    NewStatus = case maps:get(<<"status">>, Update, Task#task.status) of
        <<"submitted">> -> submitted;
        <<"working">> -> working;
        <<"input_required">> -> input_required;
        <<"auth_required">> -> auth_required;
        <<"completed">> -> completed;
        <<"failed">> -> failed;
        <<"canceled">> -> canceled;
        _ -> Task#task.status
    end,

    Task#task{
        status = NewStatus,
        artifacts = maps:get(<<"artifacts">>, Update, Task#task.artifacts),
        messages = maps:get(<<"messages">>, Update, Task#task.messages),
        updated_at = os:system_time(millisecond)
    }.

get_queue_breakdown(Queue) ->
    Items = queue:to_list(Queue),
    lists:foldl(fun(Item, Acc) ->
        Priority = Item#queue_item.priority,
        Acc#{Priority => maps:get(Priority, Acc, 0) + 1}
    end, #{high => 0, normal => 0, low => 0}, Items).

get_active_breakdown(ActiveSet, Tasks) ->
    TasksSet = sets:to_list(ActiveSet),
    lists:foldl(fun(TaskId, Acc) ->
        case maps:get(TaskId, Tasks, undefined) of
            undefined -> Acc;
            Task ->
                Type = Task#task.task_type,
                Acc#{Type => maps:get(Type, Acc, 0) + 1}
        end
    end, #{}, TasksSet).

send_current_status(Pid, State) ->
    Status = #{
        <<"type">> => <<"status">>,
        <<"data">> => #{
            <<"agent_id">> => State#state.agent_id,
            <<"tasks_total">> => maps:size(State#state.tasks),
            <<"active_tasks">> => sets:size(State#state.active_tasks),
            <<"queue_size">> => queue:len(State#state.task_queue),
            <<"metrics">> => State#state.metrics
        }
    },

    try
        craftplan_sse_handler:send_event(Pid, Status)
    catch
        _:_ -> ok
    end.

broadcast_task_event(TaskId, EventType, Task) ->
    Event = #{
        <<"event">> => EventType,
        <<"task_id">> => TaskId,
        <<"status">> => atom_to_binary(Task#task.status),
        <<"task_type">> => Task#task.task_type,
        <<"priority">> => atom_to_binary(Task#task.priority),
        <<"artifacts">> => Task#task.artifacts,
        <<"timestamp">> => os:system_time(millisecond)
    },

    %% Send to all SSE clients
    gen_server:cast(?MODULE, {broadcast, Event}).

generate_task_id() ->
    Timestamp = os:system_time(millisecond),
    Random = rand:uniform(1000000),
    iolist_to_binary(io_lib:format("task_~p_~p", [Timestamp, Random])).

generate_client_id() ->
    Timestamp = os:system_time(millisecond),
    Random = rand:uniform(1000000),
    iolist_to_binary(io_lib:format("client_~p_~p", [Timestamp, Random])).

register_a2a_alerts() ->
    %% Register A2A performance alerts
    performance_monitor:register_alert(<<"high_task_queue">>, <<"a2a.queue_size">>, #{
        type => threshold,
        operator => '>',
        value => 500,
        duration => 300000,
        enabled => true
    }),

    performance_monitor:register_alert(<<"high_error_rate">>, <<"a2a.task_error_rate">>, #{
        type => threshold,
        operator => '>',
        value => 0.05,
        duration => 300000,
        enabled => true
    }),

    performance_monitor:register_alert(<<"high_latency">>, <<"a2a.avg_task_time">>, #{
        type => threshold,
        operator => '>',
        value => 1000,
        duration => 300000,
        enabled => true
    }),

    ok.