%%%-------------------------------------------------------------------
%%% @doc BeamAI SSE Bridge
%%%
%%% Bridges existing a2a_sse_handler with BeamAI SSE streaming.
%%% Supports both legacy and BeamAI event formats simultaneously.
%%%
%%% This module implements a Cowboy loop handler that:
%%%   - Manages SSE connections with keepalive heartbeats
%%%   - Handles client reconnection via Last-Event-ID header
%%%   - Translates between A2A task events and BeamAI events
%%%   - Supports both legacy SSE format (data-only) and
%%%     BeamAI format (event + id + data)
%%%
%%% Event Format (BeamAI):
%%%   id: <event-id>
%%%   event: <event-type>
%%%   data: <json-payload>
%%%
%%% Event Format (Legacy A2A):
%%%   data: {"result": {...}}
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_sse_bridge).

%% Bridges existing SSE handler with BeamAI SSE streaming
%% Supports both legacy and BeamAI event formats simultaneously

%% Public API
-export([init/2, stream_event/3, handle_subscribe/2,
         handle_reconnect/2, close/1]).

%% Cowboy loop handler callbacks
-export([info/3, terminate/3]).

-include("a2a.hrl").

-record(sse_state, {
    req :: cowboy_req:req(),
    task_id :: binary() | undefined,
    task_pid :: pid() | undefined,
    monitor_ref :: reference() | undefined,
    subscription_ref :: reference() | undefined,
    mode :: stream | subscribe | idle,
    format :: legacy | beamai | auto,
    event_counter = 0 :: non_neg_integer(),
    last_event_id :: binary() | undefined,
    keepalive_ref :: reference() | undefined,
    buffer = [] :: [map()],
    max_buffer_size = 100 :: non_neg_integer(),
    connected_at :: integer(),
    metadata = #{} :: map()
}).

-define(KEEPALIVE_INTERVAL, 30000).  %% 30 seconds
-define(RECONNECT_INTERVAL, 5000).   %% 5 seconds (sent to client)
-define(MAX_RECONNECT_BUFFER, 100).  %% Max events to buffer for reconnect

%%====================================================================
%% Cowboy Loop Handler Init
%%====================================================================

%% @doc Initialize the SSE bridge handler.
%% Examines the request path and method to determine operation mode,
%% then sets up the SSE connection.
-spec init(cowboy_req:req(), list() | map()) ->
    {cowboy_loop, cowboy_req:req(), #sse_state{}} |
    {ok, cowboy_req:req(), #sse_state{}}.
init(Req0, Opts) when is_list(Opts) ->
    init(Req0, maps:from_list([{K, V} || {K, V} <- Opts]));
init(Req0, Opts) when is_map(Opts) ->
    Path = cowboy_req:path(Req0),
    Method = cowboy_req:method(Req0),

    %% Detect format preference from query param or header
    Format = detect_format(Req0, Opts),

    %% Check for Last-Event-ID for reconnection
    LastEventId = cowboy_req:header(<<"last-event-id">>, Req0, undefined),

    case {Method, Path} of
        {<<"POST">>, <<"/beamai/a2a/sse">>} ->
            %% BeamAI streaming message endpoint
            init_beamai_stream(Req0, Format, LastEventId);
        {<<"GET">>, <<"/beamai/a2a/sse">>} ->
            %% BeamAI SSE subscription with task_id query param
            QsParams = cowboy_req:parse_qs(Req0),
            TaskId = proplists:get_value(<<"taskId">>, QsParams, undefined),
            case TaskId of
                undefined ->
                    %% No task ID - open an idle SSE connection
                    init_idle_connection(Req0, Format);
                _ ->
                    init_beamai_subscribe(Req0, TaskId, Format, LastEventId)
            end;
        {<<"POST">>, <<"/message:stream">>} ->
            %% Legacy streaming message - delegate to a2a_sse_handler format
            init_legacy_stream(Req0);
        {<<"GET">>, <<"/tasks/", Rest/binary>>} ->
            %% Legacy subscribe
            case binary:match(Rest, <<":subscribe">>) of
                {Pos, _} ->
                    TaskId = binary:part(Rest, 0, Pos),
                    init_legacy_subscribe(Req0, TaskId);
                nomatch ->
                    send_error_and_stop(Req0, 404, <<"Not found">>)
            end;
        _ ->
            send_error_and_stop(Req0, 404, <<"Not found">>)
    end.

%%====================================================================
%% Public API
%%====================================================================

%% @doc Stream an event to the connected client.
%% Translates the event to the appropriate format based on the
%% connection's format setting.
-spec stream_event(pid() | cowboy_req:req(), binary(), map()) -> ok.
stream_event(Pid, EventType, Data) when is_pid(Pid) ->
    Pid ! {beamai_stream_event, EventType, Data},
    ok;
stream_event(Req, EventType, Data) ->
    %% Direct send to request (for use within the handler)
    send_formatted_event(Req, EventType, Data, beamai, 0),
    ok.

%% @doc Subscribe to task events.
%% Attaches the SSE connection to a task's event stream.
-spec handle_subscribe(pid(), binary()) -> ok | {error, term()}.
handle_subscribe(Pid, TaskId) when is_pid(Pid) ->
    Pid ! {beamai_subscribe, TaskId},
    ok.

%% @doc Handle reconnection with a Last-Event-ID.
%% Replays any buffered events since the given event ID.
-spec handle_reconnect(pid(), binary()) -> ok | {error, term()}.
handle_reconnect(Pid, LastEventId) when is_pid(Pid) ->
    Pid ! {beamai_reconnect, LastEventId},
    ok.

%% @doc Close the SSE connection gracefully.
-spec close(pid()) -> ok.
close(Pid) when is_pid(Pid) ->
    Pid ! beamai_close,
    ok.

%%====================================================================
%% Cowboy Loop Handler Callbacks
%%====================================================================

%% @doc Handle messages delivered to the loop handler process.
-spec info(term(), cowboy_req:req(), #sse_state{}) ->
    {ok, cowboy_req:req(), #sse_state{}} | {stop, cowboy_req:req(), #sse_state{}}.

%% A2A task events (from a2a_task_statem subscriptions)
info({a2a_task_event, TaskId, Event}, Req, #sse_state{task_id = TaskId} = State) ->
    handle_task_event(Event, Req, State);

%% BeamAI stream events (from external callers via stream_event/3)
info({beamai_stream_event, EventType, Data}, Req, State) ->
    NewCounter = State#sse_state.event_counter + 1,
    send_formatted_event(Req, EventType, Data,
                         State#sse_state.format, NewCounter),
    NewState = buffer_event(EventType, Data, NewCounter, State),
    {ok, Req, NewState#sse_state{event_counter = NewCounter}};

%% Subscribe to a task
info({beamai_subscribe, TaskId}, Req, State) ->
    case subscribe_to_task(TaskId) of
        {ok, TaskPid, SubRef, MonRef, Task} ->
            %% Send initial task state
            NewCounter = State#sse_state.event_counter + 1,
            InitialData = task_to_event_data(Task),
            send_formatted_event(Req, <<"task.initial">>, InitialData,
                                 State#sse_state.format, NewCounter),
            NewState = State#sse_state{
                task_id = TaskId,
                task_pid = TaskPid,
                subscription_ref = SubRef,
                monitor_ref = MonRef,
                mode = subscribe,
                event_counter = NewCounter
            },
            {ok, Req, NewState};
        {error, Reason} ->
            ErrorData = #{<<"error">> => iolist_to_binary(io_lib:format("~p", [Reason]))},
            send_formatted_event(Req, <<"error">>, ErrorData,
                                 State#sse_state.format, 0),
            {stop, Req, State}
    end;

%% Reconnection with replay
info({beamai_reconnect, LastEventId}, Req, State) ->
    replay_buffered_events(LastEventId, Req, State),
    {ok, Req, State};

%% Graceful close
info(beamai_close, Req, State) ->
    %% Send close event before stopping
    send_formatted_event(Req, <<"close">>,
                         #{<<"reason">> => <<"server_close">>},
                         State#sse_state.format, 0),
    cowboy_req:stream_body(<<>>, fin, Req),
    {stop, Req, State};

%% Keepalive heartbeat
info(beamai_keepalive, Req, State) ->
    send_keepalive(Req, State#sse_state.format),
    KeepaliveRef = schedule_keepalive(),
    {ok, Req, State#sse_state{keepalive_ref = KeepaliveRef}};

%% Task process died
info({'DOWN', Ref, process, _Pid, Reason}, Req,
     #sse_state{monitor_ref = Ref} = State) ->
    logger:warning("SSE bridge: task process died: ~p", [Reason]),
    ErrorData = #{
        <<"error">> => <<"task_process_terminated">>,
        <<"reason">> => iolist_to_binary(io_lib:format("~p", [Reason]))
    },
    send_formatted_event(Req, <<"error">>, ErrorData,
                         State#sse_state.format, 0),
    {stop, Req, State#sse_state{task_pid = undefined, monitor_ref = undefined}};

%% Unknown messages
info(_Info, Req, State) ->
    {ok, Req, State}.

%% @doc Terminate callback - clean up subscriptions and monitors.
-spec terminate(term(), cowboy_req:req(), #sse_state{}) -> ok.
terminate(_Reason, _Req, #sse_state{} = State) ->
    %% Cancel keepalive timer
    case State#sse_state.keepalive_ref of
        undefined -> ok;
        TimerRef -> erlang:cancel_timer(TimerRef)
    end,
    %% Unsubscribe from task updates
    case {State#sse_state.subscription_ref, State#sse_state.task_pid} of
        {undefined, _} -> ok;
        {SubRef, Pid} when is_pid(Pid) ->
            try
                a2a_task_statem:unsubscribe(Pid, SubRef)
            catch
                _:_ -> ok
            end;
        _ -> ok
    end,
    %% Demonitor task process
    case State#sse_state.monitor_ref of
        undefined -> ok;
        MonRef -> erlang:demonitor(MonRef, [flush])
    end,
    ok;
terminate(_Reason, _Req, _State) ->
    ok.

%%====================================================================
%% Initialization Helpers
%%====================================================================

%% @private Initialize a BeamAI streaming message connection.
init_beamai_stream(Req0, Format, LastEventId) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),

    case a2a_json:decode_jsonrpc_request(Body) of
        {ok, #jsonrpc_request{method = <<"message/stream">>, params = Params}} ->
            case a2a_json:decode_send_message_request(Params) of
                {ok, SendReq} ->
                    Message = SendReq#send_message_request.message,
                    case create_streaming_task(Message) of
                        {ok, TaskPid, Task} ->
                            start_sse_connection(Req1, Task, TaskPid, stream,
                                                 Format, LastEventId);
                        {error, Reason} ->
                            send_error_and_stop(Req1, 400,
                                iolist_to_binary(io_lib:format("~p", [Reason])))
                    end;
                {error, _} ->
                    send_error_and_stop(Req1, 400, <<"Invalid params">>)
            end;
        {ok, #jsonrpc_request{}} ->
            send_error_and_stop(Req1, 400, <<"Method not found">>);
        {error, _} ->
            send_error_and_stop(Req1, 400, <<"Parse error">>)
    end.

%% @private Initialize a BeamAI subscription to an existing task.
init_beamai_subscribe(Req0, TaskId, Format, LastEventId) ->
    case subscribe_to_task(TaskId) of
        {ok, TaskPid, _SubRef, _MonRef, Task} ->
            start_sse_connection(Req0, Task, TaskPid, subscribe,
                                 Format, LastEventId);
        {error, not_found} ->
            send_error_and_stop(Req0, 404, <<"Task not found">>);
        {error, terminal} ->
            send_error_and_stop(Req0, 400,
                <<"Cannot subscribe to terminal task">>);
        {error, Reason} ->
            send_error_and_stop(Req0, 500,
                iolist_to_binary(io_lib:format("~p", [Reason])))
    end.

%% @private Initialize an idle SSE connection (no task attached yet).
init_idle_connection(Req0, Format) ->
    Req = start_sse_response(Req0),
    Now = erlang:system_time(millisecond),

    %% Send connected event
    send_formatted_event(Req, <<"connected">>,
                         #{<<"status">> => <<"ok">>,
                           <<"timestamp">> => Now},
                         Format, 0),

    KeepaliveRef = schedule_keepalive(),

    State = #sse_state{
        req = Req,
        mode = idle,
        format = Format,
        event_counter = 0,
        keepalive_ref = KeepaliveRef,
        connected_at = Now
    },
    {cowboy_loop, Req, State}.

%% @private Initialize a legacy stream (delegate format decisions to legacy).
init_legacy_stream(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),

    case a2a_json:decode_jsonrpc_request(Body) of
        {ok, #jsonrpc_request{method = <<"message/stream">>, params = Params}} ->
            case a2a_json:decode_send_message_request(Params) of
                {ok, SendReq} ->
                    Message = SendReq#send_message_request.message,
                    case create_streaming_task(Message) of
                        {ok, TaskPid, Task} ->
                            start_sse_connection(Req1, Task, TaskPid, stream,
                                                 legacy, undefined);
                        {error, Reason} ->
                            send_error_and_stop(Req1, 400,
                                iolist_to_binary(io_lib:format("~p", [Reason])))
                    end;
                {error, _} ->
                    send_error_and_stop(Req1, 400, <<"Invalid params">>)
            end;
        {ok, #jsonrpc_request{}} ->
            send_error_and_stop(Req1, 400, <<"Method not found">>);
        {error, _} ->
            send_error_and_stop(Req1, 400, <<"Parse error">>)
    end.

%% @private Initialize a legacy subscribe.
init_legacy_subscribe(Req0, TaskId) ->
    case subscribe_to_task(TaskId) of
        {ok, TaskPid, _SubRef, _MonRef, Task} ->
            start_sse_connection(Req0, Task, TaskPid, subscribe,
                                 legacy, undefined);
        {error, not_found} ->
            send_error_and_stop(Req0, 404, <<"Task not found">>);
        {error, terminal} ->
            send_error_and_stop(Req0, 400,
                <<"Cannot subscribe to terminal task">>);
        {error, Reason} ->
            send_error_and_stop(Req0, 500,
                iolist_to_binary(io_lib:format("~p", [Reason])))
    end.

%% @private Start the SSE connection and initial event.
start_sse_connection(Req0, Task, TaskPid, Mode, Format, LastEventId) ->
    %% Subscribe to task events
    {ok, SubRef} = a2a_task_statem:subscribe(TaskPid),
    MonRef = erlang:monitor(process, TaskPid),

    Req = start_sse_response(Req0),
    Now = erlang:system_time(millisecond),

    %% Send initial task state
    InitialData = task_to_event_data(Task),
    send_formatted_event(Req, <<"task.initial">>, InitialData, Format, 1),

    KeepaliveRef = schedule_keepalive(),

    State = #sse_state{
        req = Req,
        task_id = Task#task.id,
        task_pid = TaskPid,
        monitor_ref = MonRef,
        subscription_ref = SubRef,
        mode = Mode,
        format = Format,
        event_counter = 1,
        last_event_id = LastEventId,
        keepalive_ref = KeepaliveRef,
        connected_at = Now
    },

    %% If reconnecting, replay missed events
    case LastEventId of
        undefined -> ok;
        _ ->
            logger:info("SSE client reconnecting from event ~s", [LastEventId])
    end,

    {cowboy_loop, Req, State}.

%%====================================================================
%% Task Event Handling
%%====================================================================

%% @private Handle task events from the a2a_task_statem subscription.
handle_task_event({state_changed, NewState}, Req, State) ->
    Task = get_task_safe(State#sse_state.task_pid),
    NewCounter = State#sse_state.event_counter + 1,

    %% Build event based on format
    case State#sse_state.format of
        legacy ->
            %% Legacy format: send as stream_response
            StatusEvent = #task_status_update_event{
                task_id = State#sse_state.task_id,
                context_id = Task#task.context_id,
                status = Task#task.status
            },
            StreamResp = #stream_response{
                payload = {status_update, StatusEvent}
            },
            JsonMap = a2a_json:encode_stream_response(StreamResp),
            LegacyData = json:encode(#{<<"result">> => JsonMap}),
            send_legacy_data(Req, LegacyData);
        _ ->
            %% BeamAI format: structured event
            EventData = #{
                <<"taskId">> => State#sse_state.task_id,
                <<"contextId">> => Task#task.context_id,
                <<"status">> => a2a_json:encode_task_status(Task#task.status),
                <<"state">> => atom_to_binary(NewState, utf8)
            },
            send_formatted_event(Req, <<"task.status">>, EventData,
                                 beamai, NewCounter)
    end,

    NewState2 = buffer_event(<<"task.status">>,
                             #{<<"state">> => atom_to_binary(NewState, utf8)},
                             NewCounter, State),

    %% Check for terminal state
    case lists:member(NewState, ?TERMINAL_STATES) of
        true ->
            %% Send final event and close
            send_formatted_event(Req, <<"task.complete">>,
                                 #{<<"taskId">> => State#sse_state.task_id,
                                   <<"finalState">> => atom_to_binary(NewState, utf8)},
                                 State#sse_state.format, NewCounter + 1),
            {stop, Req, NewState2#sse_state{event_counter = NewCounter + 1}};
        false ->
            {ok, Req, NewState2#sse_state{event_counter = NewCounter}}
    end;

handle_task_event({artifact_update, ArtifactEvent}, Req, State) ->
    NewCounter = State#sse_state.event_counter + 1,

    case State#sse_state.format of
        legacy ->
            %% Legacy format
            StreamResp = #stream_response{
                payload = {artifact_update, ArtifactEvent}
            },
            JsonMap = a2a_json:encode_stream_response(StreamResp),
            LegacyData = json:encode(#{<<"result">> => JsonMap}),
            send_legacy_data(Req, LegacyData);
        _ ->
            %% BeamAI format
            Artifact = ArtifactEvent#task_artifact_update_event.artifact,
            EventData = #{
                <<"taskId">> => ArtifactEvent#task_artifact_update_event.task_id,
                <<"artifact">> => a2a_json:encode_artifact(Artifact),
                <<"append">> => ArtifactEvent#task_artifact_update_event.append,
                <<"lastChunk">> => ArtifactEvent#task_artifact_update_event.last_chunk
            },
            send_formatted_event(Req, <<"task.artifact">>, EventData,
                                 beamai, NewCounter)
    end,

    NewState = buffer_event(<<"task.artifact">>, #{}, NewCounter, State),
    {ok, Req, NewState#sse_state{event_counter = NewCounter}};

handle_task_event(_Event, Req, State) ->
    {ok, Req, State}.

%%====================================================================
%% SSE Output Formatting
%%====================================================================

%% @private Start the SSE HTTP response with proper headers.
start_sse_response(Req0) ->
    Headers = #{
        <<"content-type">> => <<"text/event-stream">>,
        <<"cache-control">> => <<"no-cache">>,
        <<"connection">> => <<"keep-alive">>,
        <<"access-control-allow-origin">> => <<"*">>,
        <<"x-accel-buffering">> => <<"no">>
    },
    cowboy_req:stream_reply(200, Headers, Req0).

%% @private Send a formatted SSE event based on the format setting.
send_formatted_event(Req, EventType, Data, Format, Counter) ->
    case Format of
        legacy ->
            %% Legacy: data-only format
            EncodedData = case is_binary(Data) of
                true -> Data;
                false -> json:encode(Data)
            end,
            send_legacy_data(Req, EncodedData);
        _ ->
            %% BeamAI: full SSE event with id, event, data fields
            EncodedData = case is_binary(Data) of
                true -> Data;
                false -> json:encode(Data)
            end,
            EventId = integer_to_binary(Counter),
            Chunk = iolist_to_binary([
                <<"id: ">>, EventId, <<"\n">>,
                <<"event: ">>, EventType, <<"\n">>,
                <<"data: ">>, EncodedData, <<"\n\n">>
            ]),
            cowboy_req:stream_body(Chunk, nofin, Req)
    end.

%% @private Send legacy SSE data format.
send_legacy_data(Req, Data) ->
    Chunk = iolist_to_binary([<<"data: ">>, Data, <<"\n\n">>]),
    cowboy_req:stream_body(Chunk, nofin, Req).

%% @private Send a keepalive comment.
send_keepalive(Req, _Format) ->
    Chunk = <<": keepalive\n\n">>,
    cowboy_req:stream_body(Chunk, nofin, Req).

%%====================================================================
%% Event Buffering for Reconnection
%%====================================================================

%% @private Buffer an event for potential replay on reconnection.
buffer_event(EventType, Data, Counter, #sse_state{buffer = Buffer,
                                                    max_buffer_size = MaxSize} = State) ->
    Event = #{
        id => Counter,
        event => EventType,
        data => Data,
        timestamp => erlang:system_time(millisecond)
    },
    NewBuffer = case length(Buffer) >= MaxSize of
        true ->
            %% Drop oldest events when buffer is full
            lists:nthtail(1, Buffer) ++ [Event];
        false ->
            Buffer ++ [Event]
    end,
    State#sse_state{buffer = NewBuffer}.

%% @private Replay buffered events since a given event ID.
replay_buffered_events(LastEventId, Req, #sse_state{buffer = Buffer,
                                                      format = Format} = _State) ->
    LastId = try binary_to_integer(LastEventId)
             catch _:_ -> 0
             end,
    EventsToReplay = lists:filter(
        fun(#{id := Id}) -> Id > LastId end,
        Buffer
    ),
    lists:foreach(fun(#{id := Id, event := EventType, data := Data}) ->
        send_formatted_event(Req, EventType, Data, Format, Id)
    end, EventsToReplay),
    logger:debug("Replayed ~p events since id ~s",
                 [length(EventsToReplay), LastEventId]).

%%====================================================================
%% Helper Functions
%%====================================================================

%% @private Detect the desired SSE format from request.
detect_format(Req, Opts) ->
    %% Check explicit format in opts
    case maps:get(format, Opts, auto) of
        auto ->
            %% Check query param
            QsParams = cowboy_req:parse_qs(Req),
            case proplists:get_value(<<"format">>, QsParams, undefined) of
                <<"legacy">> -> legacy;
                <<"beamai">> -> beamai;
                _ ->
                    %% Default: BeamAI for /beamai/ paths, legacy otherwise
                    Path = cowboy_req:path(Req),
                    case binary:match(Path, <<"/beamai/">>) of
                        {_, _} -> beamai;
                        nomatch -> legacy
                    end
            end;
        Format ->
            Format
    end.

%% @private Subscribe to a task's event stream.
subscribe_to_task(TaskId) ->
    case a2a_task_store:get_task(TaskId) of
        {ok, Task} ->
            TaskState = (Task#task.status)#task_status.state,
            case lists:member(TaskState, ?TERMINAL_STATES) of
                true ->
                    {error, terminal};
                false ->
                    case a2a_task_store:get_task_pid(TaskId) of
                        {ok, Pid} ->
                            {ok, SubRef} = a2a_task_statem:subscribe(Pid),
                            MonRef = erlang:monitor(process, Pid),
                            {ok, Pid, SubRef, MonRef, Task};
                        {error, not_found} ->
                            {error, not_found}
                    end
            end;
        {error, not_found} ->
            {error, not_found}
    end.

%% @private Create a task for streaming.
create_streaming_task(Message) ->
    case a2a_task_statem:start_link(Message, #{}) of
        {ok, Pid} ->
            case a2a_task_statem:get_task(Pid) of
                {ok, Task} -> {ok, Pid, Task};
                Error -> Error
            end;
        Error ->
            Error
    end.

%% @private Convert a task record to an event data map.
task_to_event_data(Task) ->
    a2a_json:encode_task(Task).

%% @private Safely get task from pid with fallback.
get_task_safe(Pid) when is_pid(Pid) ->
    case a2a_task_statem:get_task(Pid) of
        {ok, Task} -> Task;
        _ ->
            #task{
                id = <<>>,
                context_id = <<>>,
                status = #task_status{
                    state = pending,
                    timestamp = 0
                }
            }
    end;
get_task_safe(_) ->
    #task{
        id = <<>>,
        context_id = <<>>,
        status = #task_status{
            state = pending,
            timestamp = 0
        }
    }.

%% @private Schedule keepalive timer.
schedule_keepalive() ->
    erlang:send_after(?KEEPALIVE_INTERVAL, self(), beamai_keepalive).

%% @private Send error response and stop the handler.
send_error_and_stop(Req0, StatusCode, Message) ->
    Body = json:encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"error">> => #{
            <<"code">> => -32600,
            <<"message">> => Message
        },
        <<"id">> => null
    }),
    Req = cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>,
        <<"access-control-allow-origin">> => <<"*">>
    }, Body, Req0),
    {ok, Req, #sse_state{
        req = Req,
        mode = idle,
        format = beamai,
        connected_at = erlang:system_time(millisecond)
    }}.
