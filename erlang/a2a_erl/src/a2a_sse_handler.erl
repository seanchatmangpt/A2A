%%% @doc A2A Server-Sent Events (SSE) Handler
%%%
%%% This module implements SSE streaming for the A2A protocol.
%%% Provides real-time task updates using chunked HTTP responses.
%%%
%%% SSE Format:
%%% data: {"result": {...}}
%%% \n\n
%%%
%%% Uses Cowboy's loop handler for long-lived connections.
-module(a2a_sse_handler).
-behaviour(cowboy_loop).

-include("a2a.hrl").

%% Cowboy loop handler callbacks
-export([
    init/2,
    info/3,
    terminate/3
]).

-record(state, {
    req :: cowboy_req:req(),
    task_id :: binary() | undefined,
    task_pid :: pid() | undefined,
    monitor_ref :: reference() | undefined,
    subscription_ref :: reference() | undefined,
    mode :: stream | subscribe
}).

%%% ============================================================================
%%% Cowboy Loop Handler Callbacks
%%% ============================================================================

init(Req0, _Opts) ->
    Path = cowboy_req:path(Req0),
    Method = cowboy_req:method(Req0),

    case {Method, Path} of
        {<<"POST">>, <<"/message:stream">>} ->
            init_stream_message(Req0);
        {<<"GET">>, <<"/tasks/", Rest/binary>>} ->
            case binary:match(Rest, <<":subscribe">>) of
                {Pos, _} ->
                    TaskId = binary:part(Rest, 0, Pos),
                    init_subscribe(Req0, TaskId);
                nomatch ->
                    error_response(Req0, 404, <<"Not found">>)
            end;
        _ ->
            error_response(Req0, 404, <<"Not found">>)
    end.

%% Handle SSE events from task state machine
info({a2a_task_event, TaskId, Event}, Req, #state{task_id = TaskId} = State) ->
    case Event of
        {state_changed, NewState} ->
            %% Send status update event
            Task = get_task_from_pid(State#state.task_pid),
            StatusEvent = #task_status_update_event{
                task_id = TaskId,
                context_id = Task#task.context_id,
                status = Task#task.status
            },
            StreamResp = #stream_response{
                payload = {status_update, StatusEvent}
            },
            send_sse_event(Req, StreamResp),

            %% Check if terminal state
            case lists:member(NewState, ?TERMINAL_STATES) of
                true ->
                    %% Close connection after terminal state
                    {stop, Req, State};
                false ->
                    {ok, Req, State}
            end;

        {artifact_update, ArtifactEvent} ->
            StreamResp = #stream_response{
                payload = {artifact_update, ArtifactEvent}
            },
            send_sse_event(Req, StreamResp),
            {ok, Req, State};

        _ ->
            {ok, Req, State}
    end;

%% Handle process down (task process died)
info({'DOWN', Ref, process, _Pid, Reason}, Req, #state{monitor_ref = Ref} = State) ->
    logger:warning("Task process died: ~p", [Reason]),
    %% Send error event
    ErrorData = #{
        <<"error">> => <<"Task process terminated">>,
        <<"reason">> => iolist_to_binary(io_lib:format("~p", [Reason]))
    },
    send_sse_data(Req, json:encode(#{<<"error">> => ErrorData})),
    {stop, Req, State};

%% Handle timeout - send keepalive
info(keepalive, Req, State) ->
    %% Send SSE comment as keepalive
    send_sse_comment(Req, <<"keepalive">>),
    schedule_keepalive(),
    {ok, Req, State};

info(_Info, Req, State) ->
    {ok, Req, State}.

terminate(_Reason, _Req, #state{subscription_ref = SubRef, task_pid = Pid}) ->
    %% Unsubscribe from task updates
    case SubRef of
        undefined -> ok;
        Ref when is_pid(Pid) ->
            a2a_task_statem:unsubscribe(Pid, Ref);
        _ -> ok
    end,
    ok.

%%% ============================================================================
%%% Initialization Functions
%%% ============================================================================

%% Initialize streaming message (POST /message:stream)
init_stream_message(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),

    case a2a_json:decode_jsonrpc_request(Body) of
        {ok, #jsonrpc_request{method = <<"message/stream">>, params = Params}} ->
            case a2a_json:decode_send_message_request(Params) of
                {ok, SendReq} ->
                    Message = SendReq#send_message_request.message,

                    %% Create task
                    case create_streaming_task(Message) of
                        {ok, TaskPid, Task} ->
                            start_sse_stream(Req1, Task, TaskPid, stream);
                        {error, Reason} ->
                            error_response(Req1, 400, Reason)
                    end;
                {error, _} ->
                    error_response(Req1, 400, <<"Invalid params">>)
            end;
        {ok, #jsonrpc_request{}} ->
            error_response(Req1, 400, <<"Method not found">>);
        {error, _} ->
            error_response(Req1, 400, <<"Parse error">>)
    end.

%% Initialize subscription (GET /tasks/{id}:subscribe)
init_subscribe(Req0, TaskId) ->
    case a2a_task_store:get_task(TaskId) of
        {ok, Task} ->
            State = (Task#task.status)#task_status.state,
            case lists:member(State, ?TERMINAL_STATES) of
                true ->
                    error_response(Req0, 400, <<"Cannot subscribe to terminal task">>);
                false ->
                    case a2a_task_store:get_task_pid(TaskId) of
                        {ok, Pid} ->
                            start_sse_stream(Req0, Task, Pid, subscribe);
                        {error, not_found} ->
                            error_response(Req0, 404, <<"Task not found">>)
                    end
            end;
        {error, not_found} ->
            error_response(Req0, 404, <<"Task not found">>)
    end.

%% Start the SSE stream
start_sse_stream(Req0, Task, TaskPid, Mode) ->
    %% Subscribe to task updates
    {ok, SubRef} = a2a_task_statem:subscribe(TaskPid),

    %% Monitor the task process
    MonRef = erlang:monitor(process, TaskPid),

    %% Start SSE response
    Headers = #{
        <<"content-type">> => <<"text/event-stream">>,
        <<"cache-control">> => <<"no-cache">>,
        <<"connection">> => <<"keep-alive">>,
        <<"access-control-allow-origin">> => <<"*">>
    },
    Req = cowboy_req:stream_reply(200, Headers, Req0),

    %% Send initial task state
    StreamResp = #stream_response{payload = {task, Task}},
    send_sse_event(Req, StreamResp),

    %% Schedule keepalive
    schedule_keepalive(),

    State = #state{
        req = Req,
        task_id = Task#task.id,
        task_pid = TaskPid,
        monitor_ref = MonRef,
        subscription_ref = SubRef,
        mode = Mode
    },

    {cowboy_loop, Req, State}.

%%% ============================================================================
%%% SSE Event Functions
%%% ============================================================================

%% Send SSE event with JSON data
send_sse_event(Req, StreamResp) ->
    JsonMap = a2a_json:encode_stream_response(StreamResp),
    Data = json:encode(#{<<"result">> => JsonMap}),
    send_sse_data(Req, Data).

%% Send raw SSE data
send_sse_data(Req, Data) ->
    %% SSE format: "data: <json>\n\n"
    Chunk = [<<"data: ">>, Data, <<"\n\n">>],
    cowboy_req:stream_body(iolist_to_binary(Chunk), nofin, Req).

%% Send SSE comment (for keepalive)
send_sse_comment(Req, Comment) ->
    Chunk = [<<": ">>, Comment, <<"\n\n">>],
    cowboy_req:stream_body(iolist_to_binary(Chunk), nofin, Req).

%% Schedule keepalive timer (every 30 seconds)
schedule_keepalive() ->
    erlang:send_after(30000, self(), keepalive).

%%% ============================================================================
%%% Helper Functions
%%% ============================================================================

%% Create task for streaming
create_streaming_task(Message) ->
    Opts = #{},
    case a2a_task_statem:start_link(Message, Opts) of
        {ok, Pid} ->
            case a2a_task_statem:get_task(Pid) of
                {ok, Task} -> {ok, Pid, Task};
                Error -> Error
            end;
        Error ->
            Error
    end.

%% Get task from pid
get_task_from_pid(Pid) ->
    case a2a_task_statem:get_task(Pid) of
        {ok, Task} -> Task;
        _ ->
            %% Return a minimal valid task record
            #task{
                id = <<>>,
                context_id = <<>>,
                status = #task_status{
                    state = pending,
                    timestamp = 0
                }
            }
    end.

%% Send error response and stop
error_response(Req0, StatusCode, Message) ->
    Body = json:encode(#{
        <<"jsonrpc">> => <<"2.0">>,
        <<"error">> => #{
            <<"code">> => -32600,
            <<"message">> => Message
        },
        <<"id">> => null
    }),
    Req = cowboy_req:reply(StatusCode, #{
        <<"content-type">> => <<"application/json">>
    }, Body, Req0),
    %% Return a valid state that will terminate immediately
    {stop, {normal, Req}, #state{
        req = Req,
        mode = stream
    }}.
