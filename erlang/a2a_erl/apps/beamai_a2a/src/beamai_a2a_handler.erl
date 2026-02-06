%%%-------------------------------------------------------------------
%%% @doc BeamAI A2A Request Handler
%%%
%%% Dispatches JSON-RPC method calls to the appropriate internal
%%% functions, bridging between the BeamAI A2A server and the
%%% existing a2a_erl task infrastructure (a2a_task_statem,
%%% a2a_task_store, a2a_push_notifier).
%%%
%%% Supported methods:
%%%   tasks/send                  - Send a message / create a task
%%%   tasks/get                   - Get task state
%%%   tasks/cancel                - Cancel a running task
%%%   tasks/sendSubscribe         - Send and subscribe to updates
%%%   tasks/resubscribe           - Resubscribe to a task
%%%   tasks/pushNotification/set  - Register push notifications
%%%   tasks/pushNotification/get  - Get push notification config
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_a2a_handler).

-include("a2a.hrl").

%% API
-export([
    handle/3,
    handle_send/3,
    handle_get/2,
    handle_cancel/2,
    handle_subscribe/3,
    handle_resubscribe/3,
    handle_push_set/2,
    handle_push_get/2
]).

%%====================================================================
%% Main dispatch
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Dispatch a JSON-RPC request to the appropriate handler.
%%
%% `Method' is the JSON-RPC method string.
%% `Params' is the params map from the request.
%% `Context' is the middleware-enriched context map.
%%
%% Returns `{ok, Result}' on success, or `{error, ErrorMap}' for
%% JSON-RPC error responses.
%% @end
%%--------------------------------------------------------------------
-spec handle(binary(), map(), map()) ->
    {ok, term()} | {error, map()} | {subscribe, pid(), binary()}.
handle(<<"tasks/send">>, Params, Context) ->
    handle_send(Params, Context, false);
handle(<<"tasks/get">>, Params, Context) ->
    handle_get(Params, Context);
handle(<<"tasks/cancel">>, Params, Context) ->
    handle_cancel(Params, Context);
handle(<<"tasks/sendSubscribe">>, Params, Context) ->
    handle_subscribe(Params, Context, send);
handle(<<"tasks/resubscribe">>, Params, Context) ->
    handle_resubscribe(Params, Context, resub);
handle(<<"tasks/pushNotification/set">>, Params, Context) ->
    handle_push_set(Params, Context);
handle(<<"tasks/pushNotification/get">>, Params, Context) ->
    handle_push_get(Params, Context);
handle(Method, _Params, _Context) ->
    {error, beamai_a2a_jsonrpc:method_not_found(Method)}.

%%====================================================================
%% tasks/send
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Handle tasks/send: create or continue a task.
%%
%% If the message contains a `taskId', the message is sent to the
%% existing task.  Otherwise a new task is created.
%%
%% When `Subscribe' is true (called from tasks/sendSubscribe),
%% returns `{subscribe, Pid, TaskId}' so the caller can set up SSE.
%% @end
%%--------------------------------------------------------------------
-spec handle_send(map(), map(), boolean()) ->
    {ok, map()} | {error, map()} | {subscribe, pid(), binary()}.
handle_send(Params, _Context, Subscribe) ->
    case decode_send_params(Params) of
        {ok, Message, Config} ->
            TaskId = Message#message.task_id,
            Result = case TaskId of
                undefined ->
                    create_new_task(Message, Config);
                _ ->
                    continue_existing_task(TaskId, Message)
            end,
            case {Result, Subscribe} of
                {{ok, Task, Pid}, true} ->
                    {subscribe, Pid, Task#task.id};
                {{ok, Task, _Pid}, false} ->
                    TaskMap = beamai_a2a_convert:task_to_map(Task),
                    {ok, TaskMap};
                {{ok, Task}, false} ->
                    TaskMap = beamai_a2a_convert:task_to_map(Task),
                    {ok, TaskMap};
                {{error, task_not_found}, _} ->
                    {error, beamai_a2a_jsonrpc:task_not_found()};
                {{error, task_terminal}, _} ->
                    {error, beamai_a2a_jsonrpc:task_not_cancelable()};
                {{error, Reason}, _} ->
                    {error, beamai_a2a_jsonrpc:internal_error(
                        beamai_a2a_utils:to_binary(Reason))}
            end;
        {error, Reason} ->
            {error, beamai_a2a_jsonrpc:invalid_params(
                beamai_a2a_utils:to_binary(Reason))}
    end.

%%====================================================================
%% tasks/get
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Handle tasks/get: retrieve current task state.
%% @end
%%--------------------------------------------------------------------
-spec handle_get(map(), map()) -> {ok, map()} | {error, map()}.
handle_get(Params, _Context) ->
    TaskId = maps:get(<<"id">>, Params, undefined),
    HistoryLength = maps:get(<<"historyLength">>, Params, undefined),
    case TaskId of
        undefined ->
            {error, beamai_a2a_jsonrpc:invalid_params(
                <<"Missing required field: id">>)};
        _ ->
            case a2a_task_store:get_task(TaskId) of
                {ok, Task} ->
                    FinalTask = apply_history_limit(Task, HistoryLength),
                    {ok, beamai_a2a_convert:task_to_map(FinalTask)};
                {error, not_found} ->
                    {error, beamai_a2a_jsonrpc:task_not_found(TaskId)}
            end
    end.

%%====================================================================
%% tasks/cancel
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Handle tasks/cancel: cancel a running task.
%% @end
%%--------------------------------------------------------------------
-spec handle_cancel(map(), map()) -> {ok, map()} | {error, map()}.
handle_cancel(Params, _Context) ->
    TaskId = maps:get(<<"id">>, Params, undefined),
    case TaskId of
        undefined ->
            {error, beamai_a2a_jsonrpc:invalid_params(
                <<"Missing required field: id">>)};
        _ ->
            case a2a_task_store:get_task_pid(TaskId) of
                {ok, Pid} ->
                    case a2a_task_statem:cancel_task(Pid) of
                        {ok, Task} ->
                            {ok, beamai_a2a_convert:task_to_map(Task)};
                        {error, task_terminal} ->
                            {error, beamai_a2a_jsonrpc:task_not_cancelable()}
                    end;
                {error, not_found} ->
                    {error, beamai_a2a_jsonrpc:task_not_found(TaskId)}
            end
    end.

%%====================================================================
%% tasks/sendSubscribe
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Handle tasks/sendSubscribe: send a message and subscribe to
%% task updates.
%%
%% Returns `{subscribe, Pid, TaskId}' so the server/cowboy handler
%% can set up an SSE stream.
%% @end
%%--------------------------------------------------------------------
-spec handle_subscribe(map(), map(), atom()) ->
    {subscribe, pid(), binary()} | {error, map()}.
handle_subscribe(Params, Context, _Mode) ->
    case handle_send(Params, Context, true) of
        {subscribe, Pid, TaskId} ->
            {subscribe, Pid, TaskId};
        {ok, _Result} ->
            %% Fallback: get the task pid for subscription
            TaskId = extract_task_id_from_params(Params),
            case a2a_task_store:get_task_pid(TaskId) of
                {ok, Pid} ->
                    {subscribe, Pid, TaskId};
                {error, _} ->
                    {error, beamai_a2a_jsonrpc:task_not_found()}
            end;
        {error, _} = Error ->
            Error
    end.

%%====================================================================
%% tasks/resubscribe
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Handle tasks/resubscribe: resubscribe to an existing task.
%%
%% Used when a client's SSE connection was dropped and they want to
%% reconnect to receive further updates.
%% @end
%%--------------------------------------------------------------------
-spec handle_resubscribe(map(), map(), atom()) ->
    {subscribe, pid(), binary()} | {error, map()}.
handle_resubscribe(Params, _Context, _Mode) ->
    TaskId = maps:get(<<"id">>, Params, undefined),
    case TaskId of
        undefined ->
            {error, beamai_a2a_jsonrpc:invalid_params(
                <<"Missing required field: id">>)};
        _ ->
            case a2a_task_store:get_task(TaskId) of
                {ok, Task} ->
                    State = (Task#task.status)#task_status.state,
                    case beamai_a2a_types:is_terminal(State) of
                        true ->
                            {error, beamai_a2a_jsonrpc:unsupported_operation()};
                        false ->
                            case a2a_task_store:get_task_pid(TaskId) of
                                {ok, Pid} ->
                                    {subscribe, Pid, TaskId};
                                {error, not_found} ->
                                    {error, beamai_a2a_jsonrpc:task_not_found(TaskId)}
                            end
                    end;
                {error, not_found} ->
                    {error, beamai_a2a_jsonrpc:task_not_found(TaskId)}
            end
    end.

%%====================================================================
%% tasks/pushNotification/set
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Handle tasks/pushNotification/set: register a push endpoint.
%% @end
%%--------------------------------------------------------------------
-spec handle_push_set(map(), map()) -> {ok, map()} | {error, map()}.
handle_push_set(Params, _Context) ->
    TaskId = maps:get(<<"id">>, Params,
                      maps:get(<<"taskId">>, Params, undefined)),
    PushConfig = maps:get(<<"pushNotificationConfig">>, Params, #{}),
    case TaskId of
        undefined ->
            {error, beamai_a2a_jsonrpc:invalid_params(
                <<"Missing required field: id">>)};
        _ ->
            ConfigId = maps:get(<<"id">>, PushConfig,
                                beamai_a2a_utils:generate_id()),
            case beamai_a2a_push:register(TaskId, ConfigId, PushConfig) of
                ok ->
                    {ok, #{
                        <<"id">>     => ConfigId,
                        <<"taskId">> => TaskId
                    }};
                {error, Reason} ->
                    {error, beamai_a2a_jsonrpc:invalid_params(
                        beamai_a2a_utils:to_binary(Reason))}
            end
    end.

%%====================================================================
%% tasks/pushNotification/get
%%====================================================================

%%--------------------------------------------------------------------
%% @doc Handle tasks/pushNotification/get: retrieve push config.
%% @end
%%--------------------------------------------------------------------
-spec handle_push_get(map(), map()) -> {ok, map()} | {error, map()}.
handle_push_get(Params, _Context) ->
    TaskId = maps:get(<<"id">>, Params,
                      maps:get(<<"taskId">>, Params, undefined)),
    case TaskId of
        undefined ->
            {error, beamai_a2a_jsonrpc:invalid_params(
                <<"Missing required field: id">>)};
        _ ->
            case beamai_a2a_push:get_config(TaskId) of
                {ok, Configs} ->
                    {ok, #{
                        <<"taskId">>  => TaskId,
                        <<"configs">> => Configs
                    }}
            end
    end.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Decode the params for a tasks/send request into a Message
%% record and optional configuration.
-spec decode_send_params(map()) ->
    {ok, #message{}, #send_message_configuration{} | undefined} |
    {error, term()}.
decode_send_params(Params) ->
    case maps:get(<<"message">>, Params, undefined) of
        undefined ->
            {error, missing_message};
        MessageMap ->
            case a2a_json:decode_message(MessageMap) of
                {ok, Message} ->
                    Config = case maps:get(<<"configuration">>, Params,
                                           undefined) of
                        undefined -> undefined;
                        CMap -> decode_config(CMap)
                    end,
                    {ok, Message, Config};
                {error, Reason} ->
                    {error, Reason}
            end
    end.

%% @doc Decode send message configuration from a map.
-spec decode_config(map()) -> #send_message_configuration{}.
decode_config(CMap) ->
    #send_message_configuration{
        accepted_output_modes =
            maps:get(<<"acceptedOutputModes">>, CMap, []),
        push_notification_config =
            case maps:get(<<"pushNotificationConfig">>, CMap, undefined) of
                undefined -> undefined;
                PMap -> decode_push_config(PMap)
            end,
        history_length =
            maps:get(<<"historyLength">>, CMap, undefined),
        blocking =
            maps:get(<<"blocking">>, CMap, false)
    }.

%% @doc Decode a push notification config from a map.
-spec decode_push_config(map()) -> #push_notification_config{}.
decode_push_config(M) ->
    #push_notification_config{
        id = maps:get(<<"id">>, M, undefined),
        url = maps:get(<<"url">>, M),
        token = maps:get(<<"token">>, M, undefined),
        authentication = case maps:get(<<"authentication">>, M, undefined) of
            undefined -> undefined;
            AMap ->
                #authentication_info{
                    scheme = maps:get(<<"scheme">>, AMap, <<"Bearer">>),
                    credentials = maps:get(<<"credentials">>, AMap, undefined)
                }
        end
    }.

%% @doc Create a new task via the existing a2a_task_statem.
-spec create_new_task(#message{}, #send_message_configuration{} | undefined) ->
    {ok, #task{}, pid()} | {error, term()}.
create_new_task(Message, Config) ->
    Opts = case Config of
        undefined -> #{};
        #send_message_configuration{blocking = Blocking} ->
            #{blocking => Blocking}
    end,
    HandlerModule = application:get_env(beamai_a2a, handler_module, undefined),
    Opts2 = case HandlerModule of
        undefined -> Opts;
        Mod -> Opts#{handler_module => Mod}
    end,
    case a2a_task_statem:start_link(Message, Opts2) of
        {ok, Pid} ->
            case a2a_task_statem:get_task(Pid) of
                {ok, Task} ->
                    %% Register push notification if configured
                    maybe_register_push(Task#task.id, Config),
                    {ok, Task, Pid};
                Error -> Error
            end;
        Error -> Error
    end.

%% @doc Continue an existing task with a new message.
-spec continue_existing_task(binary(), #message{}) ->
    {ok, #task{}} | {error, term()}.
continue_existing_task(TaskId, Message) ->
    case a2a_task_store:get_task_pid(TaskId) of
        {ok, Pid} ->
            a2a_task_statem:send_message(Pid, Message);
        {error, not_found} ->
            {error, task_not_found}
    end.

%% @doc Apply a history length limit to a task record.
-spec apply_history_limit(#task{}, integer() | undefined) -> #task{}.
apply_history_limit(Task, undefined) ->
    Task;
apply_history_limit(Task, 0) ->
    Task#task{history = []};
apply_history_limit(Task, N) when is_integer(N), N > 0 ->
    History = Task#task.history,
    Len = length(History),
    case Len =< N of
        true -> Task;
        false -> Task#task{history = lists:nthtail(Len - N, History)}
    end;
apply_history_limit(Task, _) ->
    Task.

%% @doc Register push notification from send config if present.
-spec maybe_register_push(binary(),
                          #send_message_configuration{} | undefined) -> ok.
maybe_register_push(_TaskId, undefined) ->
    ok;
maybe_register_push(_TaskId, #send_message_configuration{
    push_notification_config = undefined}) ->
    ok;
maybe_register_push(TaskId, #send_message_configuration{
    push_notification_config = PNConfig}) ->
    ConfigId = case PNConfig#push_notification_config.id of
        undefined -> beamai_a2a_utils:generate_id();
        Id -> Id
    end,
    PushMap = beamai_a2a_convert:push_config_to_map(PNConfig),
    beamai_a2a_push:register(TaskId, ConfigId, PushMap).

%% @doc Extract a task id from params, checking message.taskId as well.
-spec extract_task_id_from_params(map()) -> binary() | undefined.
extract_task_id_from_params(Params) ->
    case maps:get(<<"id">>, Params, undefined) of
        undefined ->
            case maps:get(<<"message">>, Params, undefined) of
                undefined -> undefined;
                MsgMap -> maps:get(<<"taskId">>, MsgMap, undefined)
            end;
        Id -> Id
    end.
