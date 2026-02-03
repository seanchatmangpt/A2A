%%% @doc A2A Task State Machine using gen_statem
%%%
%%% This module implements the Task lifecycle management for the A2A protocol
%%% using OTP 28's gen_statem behavior with state_functions callback mode.
%%%
%%% State Machine:
%%%   submitted -> working -> completed (terminal)
%%%                       \-> failed (terminal)
%%%                       \-> canceled (terminal)
%%%                       \-> rejected (terminal)
%%%                       \-> input_required (interrupted) -> working
%%%                       \-> auth_required (interrupted) -> working
%%%
%%% OTP 28 Features Used:
%%% - gen_statem with state_functions callback mode
%%% - State enter calls for automatic notifications
%%% - Event timeouts and generic timeouts
%%% - Selective receive for message prioritization
%%% - Process aliases for safe message passing
-module(a2a_task_statem).
-behaviour(gen_statem).

-include("a2a.hrl").

%% API
-export([
    start_link/1,
    start_link/2,
    send_message/2,
    send_message/3,
    get_task/1,
    cancel_task/1,
    subscribe/1,
    unsubscribe/2,
    add_artifact/2,
    update_status/2
]).

%% gen_statem callbacks
-export([
    init/1,
    callback_mode/0,
    terminate/3,
    code_change/4
]).

%% State functions
-export([
    submitted/3,
    working/3,
    input_required/3,
    auth_required/3,
    completed/3,
    failed/3,
    canceled/3,
    rejected/3
]).

%%% ============================================================================
%%% Type Definitions
%%% ============================================================================

-type task_id() :: binary().
-type context_id() :: binary().
-type subscriber() :: {pid(), reference()}.

-record(data, {
    task :: task(),
    subscribers = [] :: [subscriber()],
    handler_module :: module() | undefined,
    handler_state :: term(),
    push_configs = [] :: [task_push_notification_config()],
    created_at :: integer(),
    updated_at :: integer()
}).

-type data() :: #data{}.

%%% ============================================================================
%%% API Functions
%%% ============================================================================

%% @doc Start a new task state machine with initial message
-spec start_link(message()) -> {ok, pid()} | {error, term()}.
start_link(Message) ->
    start_link(Message, #{}).

%% @doc Start a new task state machine with initial message and options
-spec start_link(message(), map()) -> {ok, pid()} | {error, term()}.
start_link(Message, Opts) ->
    TaskId = generate_id(),
    ContextId = case Message#message.context_id of
        undefined -> generate_id();
        CId -> CId
    end,
    gen_statem:start_link(?MODULE, {TaskId, ContextId, Message, Opts}, []).

%% @doc Send a message to the task (for multi-turn interactions)
-spec send_message(pid(), message()) -> {ok, task()} | {error, term()}.
send_message(Pid, Message) ->
    send_message(Pid, Message, infinity).

-spec send_message(pid(), message(), timeout()) -> {ok, task()} | {error, term()}.
send_message(Pid, Message, Timeout) ->
    gen_statem:call(Pid, {send_message, Message}, Timeout).

%% @doc Get the current task state
-spec get_task(pid()) -> {ok, task()} | {error, term()}.
get_task(Pid) ->
    gen_statem:call(Pid, get_task).

%% @doc Cancel the task
-spec cancel_task(pid()) -> {ok, task()} | {error, term()}.
cancel_task(Pid) ->
    gen_statem:call(Pid, cancel_task).

%% @doc Subscribe to task updates (returns monitor ref)
-spec subscribe(pid()) -> {ok, reference()} | {error, term()}.
subscribe(Pid) ->
    gen_statem:call(Pid, {subscribe, self()}).

%% @doc Unsubscribe from task updates
-spec unsubscribe(pid(), reference()) -> ok.
unsubscribe(Pid, Ref) ->
    gen_statem:cast(Pid, {unsubscribe, Ref}).

%% @doc Add an artifact to the task (internal use)
-spec add_artifact(pid(), artifact()) -> ok.
add_artifact(Pid, Artifact) ->
    gen_statem:cast(Pid, {add_artifact, Artifact}).

%% @doc Update task status (internal use by handler)
-spec update_status(pid(), atom()) -> ok.
update_status(Pid, NewState) ->
    gen_statem:cast(Pid, {update_status, NewState}).

%%% ============================================================================
%%% gen_statem Callbacks
%%% ============================================================================

-spec callback_mode() -> [atom()].
callback_mode() ->
    [state_functions, state_enter].

-spec init({task_id(), context_id(), message(), map()}) ->
    {ok, atom(), data()} | {stop, term()}.
init({TaskId, ContextId, Message, Opts}) ->
    Now = erlang:system_time(millisecond),

    %% Create initial task
    Task = #task{
        id = TaskId,
        context_id = ContextId,
        status = #task_status{
            state = submitted,
            timestamp = Now
        },
        artifacts = [],
        history = [Message#message{
            context_id = ContextId,
            task_id = TaskId
        }],
        metadata = maps:get(metadata, Opts, #{})
    },

    %% Register with task store
    ok = a2a_task_store:register_task(TaskId, self()),

    %% Get handler module if specified
    HandlerModule = maps:get(handler_module, Opts, undefined),
    HandlerState = case HandlerModule of
        undefined -> undefined;
        Mod ->
            case Mod:init(Task, Message) of
                {ok, HS} -> HS;
                _ -> undefined
            end
    end,

    Data = #data{
        task = Task,
        subscribers = [],
        handler_module = HandlerModule,
        handler_state = HandlerState,
        push_configs = [],
        created_at = Now,
        updated_at = Now
    },

    {ok, submitted, Data}.

terminate(_Reason, _State, #data{task = Task}) ->
    a2a_task_store:unregister_task(Task#task.id),
    ok.

code_change(_OldVsn, State, Data, _Extra) ->
    {ok, State, Data}.

%%% ============================================================================
%%% State: submitted
%%% Initial state after task creation
%%% ============================================================================

submitted(enter, _OldState, Data) ->
    %% Notify subscribers of state entry
    notify_subscribers({state_changed, submitted}, Data),
    %% Auto-transition to working state
    {keep_state, Data, [{state_timeout, 0, start_work}]};

submitted(state_timeout, start_work, Data) ->
    {next_state, working, Data};

submitted({call, From}, get_task, Data) ->
    {keep_state, Data, [{reply, From, {ok, Data#data.task}}]};

submitted({call, From}, cancel_task, Data) ->
    NewData = transition_to_canceled(Data, <<"Task canceled before starting">>),
    {next_state, canceled, NewData, [{reply, From, {ok, NewData#data.task}}]};

submitted({call, From}, {subscribe, Pid}, Data) ->
    {NewData, Ref} = add_subscriber(Pid, Data),
    {keep_state, NewData, [{reply, From, {ok, Ref}}]};

submitted(cast, {unsubscribe, Ref}, Data) ->
    NewData = remove_subscriber(Ref, Data),
    {keep_state, NewData};

submitted(EventType, Event, Data) ->
    handle_common_event(EventType, Event, submitted, Data).

%%% ============================================================================
%%% State: working
%%% Task is actively being processed
%%% ============================================================================

working(enter, _OldState, Data) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,
    NewStatus = #task_status{
        state = working,
        timestamp = Now
    },
    NewTask = Task#task{status = NewStatus},
    NewData = Data#data{
        task = NewTask,
        updated_at = Now
    },

    %% Notify subscribers
    notify_subscribers({state_changed, working}, NewData),
    notify_push_notifications(NewData),

    %% Store task update
    ok = a2a_task_store:update_task(NewTask),

    %% Start processing if handler is defined
    case NewData#data.handler_module of
        undefined ->
            {keep_state, NewData};
        Module ->
            %% Spawn async handler to process the task
            Self = self(),
            spawn_link(fun() ->
                process_with_handler(Self, Module, NewData#data.handler_state, NewTask)
            end),
            {keep_state, NewData}
    end;

working({call, From}, {send_message, Message}, Data) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,

    %% Add message to history
    UpdatedMessage = Message#message{
        context_id = Task#task.context_id,
        task_id = Task#task.id
    },
    NewHistory = Task#task.history ++ [UpdatedMessage],
    NewTask = Task#task{history = NewHistory},

    NewData = Data#data{
        task = NewTask,
        updated_at = Now
    },

    %% Notify handler of new message
    case Data#data.handler_module of
        undefined -> ok;
        Module ->
            Self = self(),
            spawn_link(fun() ->
                handle_message_with_handler(Self, Module, Data#data.handler_state, UpdatedMessage)
            end)
    end,

    ok = a2a_task_store:update_task(NewTask),
    {keep_state, NewData, [{reply, From, {ok, NewTask}}]};

working({call, From}, get_task, Data) ->
    {keep_state, Data, [{reply, From, {ok, Data#data.task}}]};

working({call, From}, cancel_task, Data) ->
    NewData = transition_to_canceled(Data, <<"Task canceled by user">>),
    {next_state, canceled, NewData, [{reply, From, {ok, NewData#data.task}}]};

working({call, From}, {subscribe, Pid}, Data) ->
    {NewData, Ref} = add_subscriber(Pid, Data),
    {keep_state, NewData, [{reply, From, {ok, Ref}}]};

working(cast, {unsubscribe, Ref}, Data) ->
    NewData = remove_subscriber(Ref, Data),
    {keep_state, NewData};

working(cast, {add_artifact, Artifact}, Data) ->
    NewData = add_artifact_internal(Artifact, Data),
    %% Notify subscribers of artifact update
    Event = #task_artifact_update_event{
        task_id = (Data#data.task)#task.id,
        context_id = (Data#data.task)#task.context_id,
        artifact = Artifact,
        append = false,
        last_chunk = true
    },
    notify_subscribers({artifact_update, Event}, NewData),
    {keep_state, NewData};

working(cast, {update_status, NewState}, Data) ->
    case NewState of
        completed -> {next_state, completed, Data};
        failed -> {next_state, failed, Data};
        canceled -> {next_state, canceled, Data};
        rejected -> {next_state, rejected, Data};
        input_required -> {next_state, input_required, Data};
        auth_required -> {next_state, auth_required, Data};
        _ -> {keep_state, Data}
    end;

working(cast, {handler_result, Result}, Data) ->
    handle_handler_result(Result, Data);

working(info, {'DOWN', _Ref, process, _Pid, _Reason}, Data) ->
    %% Handler process died - mark as failed
    {next_state, failed, Data};

working(EventType, Event, Data) ->
    handle_common_event(EventType, Event, working, Data).

%%% ============================================================================
%%% State: input_required (interrupted)
%%% Awaiting user input to continue
%%% ============================================================================

input_required(enter, _OldState, Data) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,
    NewStatus = #task_status{
        state = input_required,
        timestamp = Now
    },
    NewTask = Task#task{status = NewStatus},
    NewData = Data#data{
        task = NewTask,
        updated_at = Now
    },

    notify_subscribers({state_changed, input_required}, NewData),
    notify_push_notifications(NewData),
    ok = a2a_task_store:update_task(NewTask),

    {keep_state, NewData};

input_required({call, From}, {send_message, Message}, Data) ->
    %% User provided input, resume processing
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,

    UpdatedMessage = Message#message{
        context_id = Task#task.context_id,
        task_id = Task#task.id
    },
    NewHistory = Task#task.history ++ [UpdatedMessage],
    NewTask = Task#task{history = NewHistory},

    NewData = Data#data{
        task = NewTask,
        updated_at = Now
    },

    ok = a2a_task_store:update_task(NewTask),
    {next_state, working, NewData, [{reply, From, {ok, NewTask}}]};

input_required({call, From}, get_task, Data) ->
    {keep_state, Data, [{reply, From, {ok, Data#data.task}}]};

input_required({call, From}, cancel_task, Data) ->
    NewData = transition_to_canceled(Data, <<"Task canceled while awaiting input">>),
    {next_state, canceled, NewData, [{reply, From, {ok, NewData#data.task}}]};

input_required({call, From}, {subscribe, Pid}, Data) ->
    {NewData, Ref} = add_subscriber(Pid, Data),
    {keep_state, NewData, [{reply, From, {ok, Ref}}]};

input_required(cast, {unsubscribe, Ref}, Data) ->
    NewData = remove_subscriber(Ref, Data),
    {keep_state, NewData};

input_required(EventType, Event, Data) ->
    handle_common_event(EventType, Event, input_required, Data).

%%% ============================================================================
%%% State: auth_required (interrupted)
%%% Awaiting authentication to continue
%%% ============================================================================

auth_required(enter, _OldState, Data) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,
    NewStatus = #task_status{
        state = auth_required,
        timestamp = Now
    },
    NewTask = Task#task{status = NewStatus},
    NewData = Data#data{
        task = NewTask,
        updated_at = Now
    },

    notify_subscribers({state_changed, auth_required}, NewData),
    notify_push_notifications(NewData),
    ok = a2a_task_store:update_task(NewTask),

    {keep_state, NewData};

auth_required({call, From}, {send_message, Message}, Data) ->
    %% Auth provided, resume processing
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,

    UpdatedMessage = Message#message{
        context_id = Task#task.context_id,
        task_id = Task#task.id
    },
    NewHistory = Task#task.history ++ [UpdatedMessage],
    NewTask = Task#task{history = NewHistory},

    NewData = Data#data{
        task = NewTask,
        updated_at = Now
    },

    ok = a2a_task_store:update_task(NewTask),
    {next_state, working, NewData, [{reply, From, {ok, NewTask}}]};

auth_required({call, From}, get_task, Data) ->
    {keep_state, Data, [{reply, From, {ok, Data#data.task}}]};

auth_required({call, From}, cancel_task, Data) ->
    NewData = transition_to_canceled(Data, <<"Task canceled while awaiting auth">>),
    {next_state, canceled, NewData, [{reply, From, {ok, NewData#data.task}}]};

auth_required({call, From}, {subscribe, Pid}, Data) ->
    {NewData, Ref} = add_subscriber(Pid, Data),
    {keep_state, NewData, [{reply, From, {ok, Ref}}]};

auth_required(cast, {unsubscribe, Ref}, Data) ->
    NewData = remove_subscriber(Ref, Data),
    {keep_state, NewData};

auth_required(EventType, Event, Data) ->
    handle_common_event(EventType, Event, auth_required, Data).

%%% ============================================================================
%%% Terminal States
%%% ============================================================================

%% completed - Task finished successfully
completed(enter, _OldState, Data) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,
    NewStatus = #task_status{
        state = completed,
        timestamp = Now
    },
    NewTask = Task#task{status = NewStatus},
    NewData = Data#data{
        task = NewTask,
        updated_at = Now
    },

    notify_subscribers({state_changed, completed}, NewData),
    notify_push_notifications(NewData),
    ok = a2a_task_store:update_task(NewTask),

    %% Schedule process termination after a delay (allow final reads)
    {keep_state, NewData, [{state_timeout, 300000, cleanup}]};

completed(state_timeout, cleanup, _Data) ->
    {stop, normal};

completed({call, From}, get_task, Data) ->
    {keep_state, Data, [{reply, From, {ok, Data#data.task}}]};

completed({call, From}, {subscribe, _Pid}, Data) ->
    %% Cannot subscribe to terminal state tasks
    {keep_state, Data, [{reply, From, {error, task_terminal}}]};

completed({call, From}, cancel_task, Data) ->
    %% Cannot cancel completed task
    {keep_state, Data, [{reply, From, {error, task_terminal}}]};

completed({call, From}, {send_message, _Message}, Data) ->
    %% Cannot send messages to completed task
    {keep_state, Data, [{reply, From, {error, task_terminal}}]};

completed(EventType, Event, Data) ->
    handle_common_event(EventType, Event, completed, Data).

%% failed - Task encountered an error
failed(enter, _OldState, Data) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,
    NewStatus = #task_status{
        state = failed,
        timestamp = Now
    },
    NewTask = Task#task{status = NewStatus},
    NewData = Data#data{
        task = NewTask,
        updated_at = Now
    },

    notify_subscribers({state_changed, failed}, NewData),
    notify_push_notifications(NewData),
    ok = a2a_task_store:update_task(NewTask),

    {keep_state, NewData, [{state_timeout, 300000, cleanup}]};

failed(state_timeout, cleanup, _Data) ->
    {stop, normal};

failed({call, From}, get_task, Data) ->
    {keep_state, Data, [{reply, From, {ok, Data#data.task}}]};

failed({call, From}, _Request, Data) ->
    {keep_state, Data, [{reply, From, {error, task_terminal}}]};

failed(EventType, Event, Data) ->
    handle_common_event(EventType, Event, failed, Data).

%% canceled - Task was canceled
canceled(enter, _OldState, Data) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,
    NewStatus = #task_status{
        state = canceled,
        timestamp = Now
    },
    NewTask = Task#task{status = NewStatus},
    NewData = Data#data{
        task = NewTask,
        updated_at = Now
    },

    notify_subscribers({state_changed, canceled}, NewData),
    notify_push_notifications(NewData),
    ok = a2a_task_store:update_task(NewTask),

    {keep_state, NewData, [{state_timeout, 300000, cleanup}]};

canceled(state_timeout, cleanup, _Data) ->
    {stop, normal};

canceled({call, From}, get_task, Data) ->
    {keep_state, Data, [{reply, From, {ok, Data#data.task}}]};

canceled({call, From}, _Request, Data) ->
    {keep_state, Data, [{reply, From, {error, task_terminal}}]};

canceled(EventType, Event, Data) ->
    handle_common_event(EventType, Event, canceled, Data).

%% rejected - Agent declined the task
rejected(enter, _OldState, Data) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,
    NewStatus = #task_status{
        state = rejected,
        timestamp = Now
    },
    NewTask = Task#task{status = NewStatus},
    NewData = Data#data{
        task = NewTask,
        updated_at = Now
    },

    notify_subscribers({state_changed, rejected}, NewData),
    notify_push_notifications(NewData),
    ok = a2a_task_store:update_task(NewTask),

    {keep_state, NewData, [{state_timeout, 300000, cleanup}]};

rejected(state_timeout, cleanup, _Data) ->
    {stop, normal};

rejected({call, From}, get_task, Data) ->
    {keep_state, Data, [{reply, From, {ok, Data#data.task}}]};

rejected({call, From}, _Request, Data) ->
    {keep_state, Data, [{reply, From, {error, task_terminal}}]};

rejected(EventType, Event, Data) ->
    handle_common_event(EventType, Event, rejected, Data).

%%% ============================================================================
%%% Internal Functions
%%% ============================================================================

%% Generate a UUID-like identifier
-spec generate_id() -> binary().
generate_id() ->
    %% OTP 28 has crypto:strong_rand_bytes
    Bytes = crypto:strong_rand_bytes(16),
    Hex = binary:encode_hex(Bytes),
    <<A:8/binary, B:4/binary, C:4/binary, D:4/binary, E:12/binary>> = Hex,
    <<A/binary, "-", B/binary, "-", C/binary, "-", D/binary, "-", E/binary>>.

%% Add a subscriber and return the monitor ref
-spec add_subscriber(pid(), data()) -> {data(), reference()}.
add_subscriber(Pid, Data) ->
    Ref = erlang:monitor(process, Pid),
    NewSubscribers = [{Pid, Ref} | Data#data.subscribers],
    {Data#data{subscribers = NewSubscribers}, Ref}.

%% Remove a subscriber by ref
-spec remove_subscriber(reference(), data()) -> data().
remove_subscriber(Ref, Data) ->
    erlang:demonitor(Ref, [flush]),
    NewSubscribers = lists:keydelete(Ref, 2, Data#data.subscribers),
    Data#data{subscribers = NewSubscribers}.

%% Notify all subscribers of an event
-spec notify_subscribers(term(), data()) -> ok.
notify_subscribers(Event, #data{subscribers = Subscribers, task = Task}) ->
    TaskId = Task#task.id,
    lists:foreach(fun({Pid, _Ref}) ->
        Pid ! {a2a_task_event, TaskId, Event}
    end, Subscribers),
    ok.

%% Send push notifications
-spec notify_push_notifications(data()) -> ok.
notify_push_notifications(#data{push_configs = Configs, task = Task}) ->
    lists:foreach(fun(Config) ->
        spawn(fun() ->
            a2a_push_notifier:notify(Config, Task)
        end)
    end, Configs),
    ok.

%% Transition to canceled state
-spec transition_to_canceled(data(), binary()) -> data().
transition_to_canceled(Data, Reason) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,

    %% Add cancellation message to history
    CancelMessage = #message{
        message_id = generate_id(),
        context_id = Task#task.context_id,
        task_id = Task#task.id,
        role = agent,
        parts = [#part{content = {text, Reason}}]
    },

    NewHistory = Task#task.history ++ [CancelMessage],
    NewTask = Task#task{history = NewHistory},

    Data#data{
        task = NewTask,
        updated_at = Now
    }.

%% Add artifact to task
-spec add_artifact_internal(artifact(), data()) -> data().
add_artifact_internal(Artifact, Data) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,
    NewArtifacts = Task#task.artifacts ++ [Artifact],
    NewTask = Task#task{artifacts = NewArtifacts},
    ok = a2a_task_store:update_task(NewTask),
    Data#data{
        task = NewTask,
        updated_at = Now
    }.

%% Handle common events across states
-spec handle_common_event(atom(), term(), atom(), data()) -> term().
handle_common_event(info, {'DOWN', Ref, process, Pid, _Reason}, _State, Data) ->
    %% Subscriber died, remove from list
    case lists:keyfind(Ref, 2, Data#data.subscribers) of
        {Pid, Ref} ->
            NewData = remove_subscriber(Ref, Data),
            {keep_state, NewData};
        false ->
            {keep_state, Data}
    end;

handle_common_event(cast, {add_push_config, Config}, _State, Data) ->
    NewConfigs = [Config | Data#data.push_configs],
    {keep_state, Data#data{push_configs = NewConfigs}};

handle_common_event(cast, {remove_push_config, ConfigId}, _State, Data) ->
    NewConfigs = lists:filter(
        fun(C) -> C#task_push_notification_config.id =/= ConfigId end,
        Data#data.push_configs
    ),
    {keep_state, Data#data{push_configs = NewConfigs}};

handle_common_event(_EventType, _Event, _State, Data) ->
    {keep_state, Data}.

%% Process task with handler module
-spec process_with_handler(pid(), module(), term(), task()) -> ok.
process_with_handler(TaskPid, Module, HandlerState, Task) ->
    try
        case Module:process(Task, HandlerState) of
            {ok, Result} ->
                gen_statem:cast(TaskPid, {handler_result, {ok, Result}});
            {error, Reason} ->
                gen_statem:cast(TaskPid, {handler_result, {error, Reason}});
            {input_required, Prompt} ->
                gen_statem:cast(TaskPid, {handler_result, {input_required, Prompt}});
            {auth_required, Details} ->
                gen_statem:cast(TaskPid, {handler_result, {auth_required, Details}})
        end
    catch
        _:Error:Stacktrace ->
            logger:error("Handler error: ~p~n~p", [Error, Stacktrace]),
            gen_statem:cast(TaskPid, {handler_result, {error, Error}})
    end,
    ok.

%% Handle message with handler module
-spec handle_message_with_handler(pid(), module(), term(), message()) -> ok.
handle_message_with_handler(TaskPid, Module, HandlerState, Message) ->
    try
        case Module:handle_message(Message, HandlerState) of
            {ok, Result} ->
                gen_statem:cast(TaskPid, {handler_result, {ok, Result}});
            {continue, _NewState} ->
                ok;
            {error, Reason} ->
                gen_statem:cast(TaskPid, {handler_result, {error, Reason}})
        end
    catch
        _:Error:Stacktrace ->
            logger:error("Handler message error: ~p~n~p", [Error, Stacktrace]),
            gen_statem:cast(TaskPid, {handler_result, {error, Error}})
    end,
    ok.

%% Handle handler results
-spec handle_handler_result({ok, term()} | {error, term()} |
                            {input_required, term()} | {auth_required, term()},
                            data()) -> term().
handle_handler_result({ok, Result}, Data) ->
    %% Handler completed successfully
    case Result of
        #{artifacts := Artifacts} ->
            %% Add artifacts and complete
            NewData = lists:foldl(fun add_artifact_internal/2, Data, Artifacts),
            {next_state, completed, NewData};
        _ ->
            {next_state, completed, Data}
    end;

handle_handler_result({error, Reason}, Data) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,

    %% Add error message to status
    ErrorMsg = #message{
        message_id = generate_id(),
        context_id = Task#task.context_id,
        task_id = Task#task.id,
        role = agent,
        parts = [#part{content = {text, iolist_to_binary(io_lib:format("~p", [Reason]))}}]
    },

    NewStatus = #task_status{
        state = failed,
        message = ErrorMsg,
        timestamp = Now
    },

    NewTask = Task#task{status = NewStatus},
    NewData = Data#data{task = NewTask, updated_at = Now},

    {next_state, failed, NewData};

handle_handler_result({input_required, Prompt}, Data) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,

    %% Add prompt message
    PromptMsg = #message{
        message_id = generate_id(),
        context_id = Task#task.context_id,
        task_id = Task#task.id,
        role = agent,
        parts = [#part{content = {text, Prompt}}]
    },

    NewStatus = #task_status{
        state = input_required,
        message = PromptMsg,
        timestamp = Now
    },

    NewTask = Task#task{status = NewStatus},
    NewData = Data#data{task = NewTask, updated_at = Now},

    {next_state, input_required, NewData};

handle_handler_result({auth_required, Details}, Data) ->
    Now = erlang:system_time(millisecond),
    Task = Data#data.task,

    %% Add auth request message
    AuthMsg = #message{
        message_id = generate_id(),
        context_id = Task#task.context_id,
        task_id = Task#task.id,
        role = agent,
        parts = [#part{content = {data, Details}}]
    },

    NewStatus = #task_status{
        state = auth_required,
        message = AuthMsg,
        timestamp = Now
    },

    NewTask = Task#task{status = NewStatus},
    NewData = Data#data{task = NewTask, updated_at = Now},

    {next_state, auth_required, NewData}.
