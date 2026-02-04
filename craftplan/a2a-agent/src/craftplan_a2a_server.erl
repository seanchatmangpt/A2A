%%% @doc Craftplan A2A Server
%%% Implements A2A protocol for agent-to-agent collaboration

-module(craftplan_a2a_server).
-behaviour(gen_server).

%% API
-export([start_link/0, stop/0]).
-export([submit_task/2, get_task/1, cancel_task/1, send_message/2]).
-export([list_tasks/0, get_status/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include("a2a.hrl").

-define(SERVER, ?MODULE).
-define(DEFAULT_PORT, 8080).

-record(state, {
    port :: integer(),
    agent_id :: binary(),
    tasks :: map(),  #{task_id() => task()}
    sse_clients :: map(),  #{client_id() => pid()}
    metrics :: map()
}).

-record(task, {
    id :: binary(),
    status :: submitted | working | input_required | auth_required | completed | failed | canceled,
    task_type :: binary(),
    created_at :: integer(),
    updated_at :: integer(),
    artifacts :: list(map()),
    messages :: list(map()),
    state :: term()
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
    gen_server:call(?SERVER, {submit_task, TaskType, Params}).

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
    gen_server:call(?SERVER, {send_message, TaskId, Message}).

%% @doc List all tasks
-spec list_tasks() -> {ok, [task()]}.
list_tasks() ->
    gen_server:call(?SERVER, list_tasks).

%% @doc Get agent status
-spec get_status() -> map().
get_status() ->
    gen_server:call(?SERVER, get_status).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init([]) ->
    Port = application:get_env(craftplan_a2a, port, ?DEFAULT_PORT),
    AgentID = <<"craftplan-erp-agent">>,

    %% Start Cowboy HTTP server
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/a2a", ?MODULE, []},
            {"/a2a/tasks/:taskid", ?MODULE, []},
            {"/sse", ?MODULE, []},
            {"/health", ?MODULE, []},
            {"/.well-known/agent-card", ?MODULE, []}
        ]}
    ]),

    {ok, _} = cowboy:start_clear(a2a_http,
        [{port, Port}],
        #{env => #{dispatch => Dispatch}}
    ),

    io:format("Craftplan A2A Server listening on port ~p~n", [Port]),
    io:format("Agent ID: ~s~n", [AgentID]),

    State = #state{
        port = Port,
        agent_id = AgentID,
        tasks = #{},
        sse_clients = #{},
        metrics => #{tasks_submitted => 0, tasks_completed => 0}
    },

    {ok, State}.

handle_call({submit_task, TaskType, Params}, _From, State) ->
    TaskId = generate_task_id(),
    Task = #task{
        id = TaskId,
        status = submitted,
        task_type = TaskType,
        created_at = os:system_time(millisecond),
        updated_at = os:system_time(millisecond),
        artifacts = [],
        messages = [],
        state = #{params => Params}
    },

    %% Start task handler
    {ok, TaskPid} = craftplan_task_handler:start(TaskId, TaskType, Params),

    NewTasks = maps:put(TaskId, Task#task{state = #{handler => TaskPid}}, State#state.tasks),
    NewMetrics = State#state.metrics#{tasks_submitted => State#state.metrics.tasks_submitted + 1},

    %% Notify SSE clients
    broadcast_task_event(TaskId, <<"created">>, Task),

    {reply, {ok, TaskId}, State#state{tasks = NewTasks, metrics = NewMetrics}};

handle_call({get_task, TaskId}, _From, State) ->
    case maps:get(TaskId, State#state.tasks, undefined) of
        undefined -> {reply, {error, not_found}, State};
        Task -> {reply, {ok, Task}, State}
    end;

handle_call({cancel_task, TaskId}, _From, State) ->
    case maps:get(TaskId, State#state.tasks, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        #task{state = #{handler := Pid}} = Task ->
            craftplan_task_handler:cancel(Pid),
            NewTask = Task#task{status = canceled, updated_at = os:system_time(millisecond)},
            NewTasks = maps:put(TaskId, NewTask, State#state.tasks),
            broadcast_task_event(TaskId, <<"canceled">>, NewTask),
            {reply, ok, State#state{tasks = NewTasks}}
    end;

handle_call({send_message, TaskId, Message}, _From, State) ->
    case maps:get(TaskId, State#state.tasks, undefined) of
        undefined ->
            {reply, {error, not_found}, State};
        #task{state = #{handler := Pid}} = Task ->
            craftplan_task_handler:send_message(Pid, Message),
            {reply, ok, State}
    end;

handle_call(list_tasks, _From, State) ->
    TaskList = maps:values(State#state.tasks),
    {reply, {ok, TaskList}, State};

handle_call(get_status, _From, State) ->
    Status = #{
        <<"agent_id">> => State#state.agent_id,
        <<"status">> => <<"running">>,
        <<"tasks">> => maps:size(State#state.tasks),
        <<"metrics">> => State#state.metrics,
        <<"timestamp">> => os:system_time(millisecond)
    },
    {reply, Status, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({task_update, TaskId, Update}, State) ->
    case maps:get(TaskId, State#state.tasks, undefined) of
        undefined ->
            {noreply, State};
        Task ->
            NewTask = apply_task_update(Task, Update),
            NewTasks = maps:put(TaskId, NewTask, State#state.tasks),
            NewMetrics = case NewTask#task.status of
                completed -> State#state.metrics#{tasks_completed => State#state.metrics.tasks_completed + 1};
                failed -> State#state.metrics#{tasks_failed => maps:get(tasks_failed, State#state.metrics, 0) + 1};
                _ -> State#state.metrics
            end,
            broadcast_task_event(TaskId, status_to_event(NewTask#task.status), NewTask),
            {noreply, State#state{tasks = NewTasks, metrics = NewMetrics}}
    end;

handle_info({sse_subscribe, Pid}, State) ->
    ClientId = generate_client_id(),
    NewClients = maps:put(ClientId, Pid, State#state.sse_clients),
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

%% Generate unique task ID
generate_task_id() ->
    Timestamp = os:system_time(millisecond),
    Random = rand:uniform(1000000),
    iolist_to_binary(io_lib:format("task_~p_~p", [Timestamp, Random])).

%% Generate client ID
generate_client_id() ->
    Timestamp = os:system_time(millisecond),
    Random = rand:uniform(1000000),
    iolist_to_binary(io_lib:format("client_~p_~p", [Timestamp, Random])).

%% Apply task update
apply_task_update(Task, Update) ->
    NewStatus = maps:get(<<"status">>, Update, Task#task.status),
    NewArtifacts = maps:get(<<"artifacts">>, Update, Task#task.artifacts),
    NewMessages = maps:get(<<"messages">>, Update, Task#task.messages),

    Status = case NewStatus of
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
        status = Status,
        artifacts = NewArtifacts,
        messages = NewMessages,
        updated_at = os:system_time(millisecond)
    }.

%% Convert status to SSE event type
status_to_event(submitted) -> <<"task_created">>;
status_to_event(working) -> <<"task_working">>;
status_to_event(input_required) -> <<"task_input_required">>;
status_to_event(auth_required) -> <<"task_auth_required">>;
status_to_event(completed) -> <<"task_completed">>;
status_to_event(failed) -> <<"task_failed">>;
status_to_event(canceled) -> <<"task_canceled">>.

%% Broadcast task event to SSE clients
broadcast_task_event(TaskId, EventType, Task) ->
    Event = #{
        <<"event">> => EventType,
        <<"task_id">> => TaskId,
        <<"status">> => atom_to_binary(Task#task.status),
        <<"artifacts">> => Task#task.artifacts,
        <<"timestamp">> => os:system_time(millisecond)
    },
    %% Send to all SSE clients
    gen_server:cast(?MODULE, {broadcast, Event}).

%% Cowboy handler implementation (simplified - would normally be in separate module)
init(Req0, State) ->
    {ok, Req0, State}.

handle(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),

    Result = case {Method, Path} of
        {<<"POST">>, <<"/a2a">>} ->
            handle_a2a_request(Req0);
        {<<"GET">>, <<"/a2a/tasks/", TaskId/binary>>} ->
            handle_get_task(Req0, TaskId);
        {<<"GET">>, <<"/sse">>} ->
            handle_sse(Req0);
        {<<"GET">>, <<"/health">>} ->
            handle_health(Req0);
        _ ->
            cowboy_req:reply(404, Req0)
    end,
    {ok, Result, State}.

%% Handle A2A JSON-RPC request
handle_a2a_request(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Request = jiffy:decode(Body, [return_maps]),

    Response = case Request of
        #{<<"jsonrpc">> := <<"2.0">>, <<"method">> := <<"task.submit">>,
          <<"params">> => Params, <<"id">> := Id} ->
            TaskType = maps:get(<<"task_type">>, Params),
            TaskParams = maps:get(<<"params">>, Params, #{}),
            case submit_task(TaskType, TaskParams) of
                {ok, TaskId} ->
                    #{<<"jsonrpc">> => <<"2.0">>,
                      <<"result">> => #{<<"task_id">> => TaskId},
                      <<"id">> => Id};
                {error, Reason} ->
                    a2a_error(Id, Reason)
            end;

        #{<<"jsonrpc">> := <<"2.0">>, <<"method">> := <<"task.get">>,
          <<"params">> => Params, <<"id">> := Id} ->
            TaskId = maps:get(<<"task_id">>, Params),
            case get_task(TaskId) of
                {ok, Task} ->
                    #{<<"jsonrpc">> => <<"2.0">>,
                      <<"result">> => task_to_map(Task),
                      <<"id">> => Id};
                {error, not_found} ->
                    a2a_error(Id, task_not_found)
            end;

        _ ->
            a2a_error(maps.get(<<"id">>, Request, null), method_not_found)
    end,

    RespBody = jiffy:encode(Response),
    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, RespBody, Req1).

%% Handle get task request
handle_get_task(Req0, TaskId) ->
    case get_task(TaskId) of
        {ok, Task} ->
            Body = jiffy:encode(task_to_map(Task)),
            cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Body, Req0);
        {error, not_found} ->
            cowboy_req:reply(404, Req0)
    end.

%% Handle SSE connection
handle_sse(Req0) ->
    {ok, Pid} = craftplan_sse_handler:start(Req0),
    %% Notify server about new client
    ?MODULE ! {sse_subscribe, Pid},
    %% This returns immediately; the actual SSE loop runs in the handler
    {loop, Req0, Pid}.

%% Handle health check
handle_health(Req0) ->
    Health = #{
        <<"status">> => <<"healthy">>,
        <<"agent_id">> => <<"craftplan-erp-agent">>,
        <<"version">> => <<"1.0.0">>,
        <<"timestamp">> => os:system_time(millisecond)
    },
    Body = jiffy:encode(Health),
    cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Body, Req0).

%% Build A2A error response
a2a_error(Id, Code) ->
    #{<<"jsonrpc">> => <<"2.0">>,
      <<"error">> => #{
          <<"code">> => error_code(Code),
          <<"message">> => error_message(Code)
      },
      <<"id">> => Id}.

error_code(task_not_found) -> -32001;
error_code(method_not_found) -> -32601;
error_code(invalid_params) -> -32602;
error_code(_) -> -32000.

error_message(task_not_found) -> <<"Task not found">>;
error_message(method_not_found) -> <<"Method not found">>;
error_message(invalid_params) -> <<"Invalid parameters">>;
error_message(_) -> <<"Internal error">>.

%% Convert task record to map for JSON response
task_to_map(#task{} = Task) ->
    #{
        <<"task_id">> => Task#task.id,
        <<"status">> => atom_to_binary(Task#task.status),
        <<"task_type">> => Task#task.task_type,
        <<"created_at">> => Task#task.created_at,
        <<"updated_at">> => Task#task.updated_at,
        <<"artifacts">> => Task#task.artifacts,
        <<"messages">> => Task#task.messages
    }.
