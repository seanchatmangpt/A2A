%%% @doc SSE bridge between legacy a2a_sse_handler and beamai SSE format
%%%
%%% Cowboy loop handler that upgrades to SSE and streams events from both
%%% the legacy a2a_task_statem event format and the beamai_a2a_server format.
%%% Uses beamai_a2a_types for state binary conversions.
-module(beamai_sse_bridge).
-behaviour(cowboy_loop).

-include("a2a.hrl").
-include_lib("beamai_core/include/beamai_common.hrl").

-export([init/2, info/3, terminate/3, stream_event/3]).

-record(state, {
    task_id :: binary() | undefined,
    task_pid :: pid() | undefined,
    sub_ref :: reference() | undefined,
    mon_ref :: reference() | undefined,
    format :: legacy | beamai | both
}).

%%% Cowboy loop handler callbacks

init(Req0, Opts) ->
    TaskId = cowboy_req:binding(task_id, Req0),
    Format = proplists:get_value(format, Opts, both),
    case resolve_task(TaskId) of
        {ok, Pid} ->
            {ok, SubRef} = a2a_task_statem:subscribe(Pid),
            MonRef = erlang:monitor(process, Pid),
            Headers = #{
                <<"content-type">> => <<"text/event-stream">>,
                <<"cache-control">> => <<"no-cache">>,
                <<"connection">> => <<"keep-alive">>,
                <<"access-control-allow-origin">> => <<"*">>
            },
            Req = cowboy_req:stream_reply(200, Headers, Req0),
            schedule_keepalive(),
            {cowboy_loop, Req,
             #state{task_id = TaskId, task_pid = Pid,
                    sub_ref = SubRef, mon_ref = MonRef,
                    format = Format}};
        {error, _Reason} ->
            Body = json:encode(#{<<"error">> => <<"task_not_found">>}),
            Req = cowboy_req:reply(404,
                      #{<<"content-type">> => <<"application/json">>},
                      Body, Req0),
            {ok, Req, #state{format = Format}}
    end.

info({a2a_task_event, TaskId, Event}, Req,
     #state{task_id = TaskId, format = Fmt} = State) ->
    case Event of
        {state_changed, NewState} ->
            StateBin = beamai_a2a_types:task_state_to_binary(NewState),
            Payload = #{<<"type">> => <<"status">>,
                        <<"taskId">> => TaskId,
                        <<"state">> => StateBin},
            send_event(Req, Fmt, <<"task.status">>, Payload),
            case beamai_a2a_types:is_terminal_state(NewState) of
                true -> {stop, Req, State};
                false -> {ok, Req, State}
            end;
        {artifact_update, ArtEvent} ->
            Payload = #{<<"type">> => <<"artifact">>,
                        <<"taskId">> => TaskId,
                        <<"artifact">> => format_artifact_event(ArtEvent)},
            send_event(Req, Fmt, <<"task.artifact">>, Payload),
            {ok, Req, State};
        _ ->
            {ok, Req, State}
    end;

info({'DOWN', Ref, process, _Pid, Reason}, Req,
     #state{mon_ref = Ref} = State) ->
    ErrPayload = #{<<"type">> => <<"error">>,
                   <<"reason">> => iolist_to_binary(
                       io_lib:format("~p", [Reason]))},
    send_event(Req, State#state.format, <<"task.error">>, ErrPayload),
    {stop, Req, State};

info(keepalive, Req, State) ->
    cowboy_req:stream_body(<<": keepalive\n\n">>, nofin, Req),
    schedule_keepalive(),
    {ok, Req, State};

info(_Info, Req, State) ->
    {ok, Req, State}.

terminate(_Reason, _Req, #state{sub_ref = SubRef, task_pid = Pid}) ->
    case SubRef of
        undefined -> ok;
        Ref when is_pid(Pid) ->
            a2a_task_statem:unsubscribe(Pid, Ref);
        _ -> ok
    end,
    ok.

%% @doc Public helper to format and send an SSE event.
-spec stream_event(cowboy_req:req(), binary(), map()) -> ok.
stream_event(Req, EventType, Data) ->
    send_event(Req, both, EventType, Data).

%%% Internal

resolve_task(TaskId) ->
    a2a_task_store:get_task_pid(TaskId).

send_event(Req, Fmt, EventType, Data) ->
    Json = json:encode(Data),
    Chunk = case Fmt of
        legacy ->
            [<<"data: ">>, Json, <<"\n\n">>];
        beamai ->
            [<<"event: ">>, EventType, <<"\ndata: ">>, Json, <<"\n\n">>];
        both ->
            [<<"event: ">>, EventType, <<"\ndata: ">>, Json, <<"\n\n">>]
    end,
    cowboy_req:stream_body(iolist_to_binary(Chunk), nofin, Req).

format_artifact_event(#task_artifact_update_event{artifact = Art}) ->
    #{artifact_id => Art#artifact.artifact_id,
      name => Art#artifact.name};
format_artifact_event(ArtMap) when is_map(ArtMap) ->
    ArtMap.

schedule_keepalive() ->
    erlang:send_after(30000, self(), keepalive).
