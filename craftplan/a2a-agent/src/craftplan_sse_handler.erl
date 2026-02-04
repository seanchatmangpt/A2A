%%% @doc Craftplan SSE Handler
%%% Handles Server-Sent Events for real-time task updates

-module(craftplan_sse_handler).

%% API
-export([start/1, send_event/3]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include("a2a.hrl").

-record(state, {
    req :: cowboy_req:req(),
    client_id :: binary()
}).

%%====================================================================
%% API
%%====================================================================

start(Req0) ->
    proc_lib:start_link(?MODULE, init, [Req0]).

send_event(Pid, Event, Data) ->
    gen_server:cast(Pid, {send_event, Event, Data}).

%%====================================================================
%% gen_server callbacks (via proc_lib)
%%====================================================================

init(Req0) ->
    proc_lib:init_ack({ok, self()}),
    gen_server:enter_loop(?MODULE, [], #state{
        req = set_sse_headers(Req0),
        client_id = generate_client_id()
    }).

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast({send_event, Event, Data}, State) ->
    Req = send_sse_event(State#state.req, Event, Data),
    {noreply, State#state{req = Req}};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({timeout, _Ref, heartbeat}, State) ->
    %% Send heartbeat comment to keep connection alive
    Req = cowboy_req:chunk(<<":heartbeat\n\n">>, State#state.req),
    erlang:start_timer(30000, self(), heartbeat),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Internal Functions
%%====================================================================

%% Set SSE headers
set_sse_headers(Req0) ->
    Req1 = cowboy_req:stream_reply(200, #{
        <<"content-type">> => <<"text/event-stream">>,
        <<"cache-control">> => <<"no-cache">>,
        <<"connection">> => <<"keep-alive">>,
        <<"x-accel-buffering">> => <<"no">>
    }, Req0),
    %% Send initial comment
    cowboy_req:chunk(": craftplan-sse-connected\n\n", Req1),
    Req1.

%% Send SSE event
send_sse_event(Req0, Event, Data) ->
    EventJson = jiffy:encode(Data),
    EventChunk = [
        <<"event: ">>, Event, <<"\n">>,
        <<"data: ">>, EventJson, <<"\n\n">>
    ],
    cowboy_req:chunk(iolist_to_binary(EventChunk), Req0).

%% Generate client ID
generate_client_id() ->
    Timestamp = os:system_time(millisecond),
    Random = rand:uniform(1000000),
    iolist_to_binary(io_lib:format("sse_~p_~p", [Timestamp, Random])).
