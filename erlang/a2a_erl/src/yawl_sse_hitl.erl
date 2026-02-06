%%%-------------------------------------------------------------------
%%% @doc
%%% SSE Event Module for Real-Time Human-in-the-Loop
%%%
%%% This module provides Server-Sent Events (SSE) support for
%%% real-time communication during human-in-the-loop workflows.
%%% Integrates with Cowboy for streaming events to web clients.
%%%
%%% @end
%%%-------------------------------------------------------------------

-module(yawl_sse_hitl).
-author("A2A Team").

-behaviour(gen_server).

%% API exports
-export([
    start_link/0,
    start_link/1,

    %% SSE Streams
    create_approval_stream/1,
    send_approval_event/3,
    close_stream/1,

    %% Event Broadcasting
    broadcast_approval_request/2,
    broadcast_decision/2,

    %% Client Management
    register_client/2,
    unregister_client/1,
    get_active_streams/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-include("yawl_types.hrl").

%%====================================================================
%% Records
%%====================================================================

-record(state, {
    streams = #{} :: map(),  %% StreamId -> {Pid, MonitorRef}
    clients = #{} :: map(), %% ClientId -> StreamId
    events = #{} :: map()    %% ApprovalId -> [Event]
}).

-record(sse_event, {
    id :: binary(),
    event :: binary(),
    data :: map(),
    retry :: integer()
}).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Start the SSE server.
-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Start with options.
-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Options) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Options], []).

%% @doc Create a new SSE stream for approval updates.
-spec create_approval_stream(binary()) -> {ok, binary(), pid()}.
create_approval_stream(ApprovalId) ->
    gen_server:call(?MODULE, {create_stream, ApprovalId}, infinity).

%% @doc Send an event to an approval stream.
-spec send_approval_event(binary(), binary(), map()) -> ok.
send_approval_event(ApprovalId, EventType, Data) ->
    gen_server:cast(?MODULE, {send_event, ApprovalId, EventType, Data}).

%% @doc Close a stream.
-spec close_stream(binary()) -> ok.
close_stream(StreamId) ->
    gen_server:cast(?MODULE, {close_stream, StreamId}).

%% @doc Broadcast approval request to all connected clients.
-spec broadcast_approval_request(binary(), map()) -> ok.
broadcast_approval_request(ApprovalId, RequestData) ->
    gen_server:cast(?MODULE, {broadcast, approval_request, ApprovalId, RequestData}).

%% @doc Broadcast decision to all connected clients.
-spec broadcast_decision(binary(), map()) -> ok.
broadcast_decision(ApprovalId, DecisionData) ->
    gen_server:cast(?MODULE, {broadcast, decision, ApprovalId, DecisionData}).

%% @doc Register a client for a stream.
-spec register_client(binary(), pid()) -> {ok, binary()}.
register_client(ApprovalId, ClientPid) ->
    gen_server:call(?MODULE, {register_client, ApprovalId, ClientPid}, infinity).

%% @doc Unregister a client.
-spec unregister_client(binary()) -> ok.
unregister_client(ClientId) ->
    gen_server:cast(?MODULE, {unregister_client, ClientId}).

%% @doc Get all active streams.
-spec get_active_streams() -> {ok, [binary()]}.
get_active_streams() ->
    gen_server:call(?MODULE, get_streams, infinity).

%%====================================================================
%% gen_server Callbacks
%%====================================================================

init([]) ->
    {ok, #state{}};
init([Options]) ->
    {ok, #state{}}.

handle_call({create_stream, ApprovalId}, _From, State) ->
    StreamId = generate_id(),
    Self = self(),

    %% Spawn stream handler process
    {Pid, MonitorRef} = spawn_monitor(fun() ->
        stream_loop(Self, StreamId, ApprovalId)
    end),

    {reply, {ok, StreamId, Pid}, State#state{
        streams = maps:put(StreamId, {Pid, MonitorRef}, State#state.streams)
    }};

handle_call({register_client, ApprovalId, ClientPid}, {FromPid, _}, State) ->
    %% Find or create stream for this approval
    case find_stream_for_approval(ApprovalId, State) of
        {ok, StreamId} ->
            ClientId = generate_id(),
            {reply, {ok, ClientId}, State#state{
                clients = maps:put(ClientId, StreamId, State#state.clients)
            }};
        none ->
            %% Create new stream
            {ok, StreamId, _Pid} = handle_call({create_stream, ApprovalId}, {FromPid, none}, State),
            ClientId = generate_id(),
            {reply, {ok, ClientId}, State#state{
                clients = maps:put(ClientId, StreamId, State#state.clients)
            }}
    end;

handle_call(get_streams, _From, State) ->
    Streams = maps:keys(State#state.streams),
    {reply, {ok, Streams}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({send_event, StreamId, EventType, Data}, State) ->
    case maps:get(StreamId, State#state.streams, undefined) of
        {Pid, _Ref} ->
            Event = format_sse_event(EventType, Data),
            Pid ! {send, Event},
            {noreply, State};
        undefined ->
            {noreply, State}
    end;

handle_cast({broadcast, approval_request, ApprovalId, RequestData}, State) ->
    %% Broadcast to all clients listening for this approval
    EventData = RequestData#{
        type => <<"approval_request">>,
        approval_id => ApprovalId,
        timestamp => erlang:monotonic_time(millisecond)
    },
    broadcast_to_approval_streams(ApprovalId, <<"approval_request">>, EventData),
    {noreply, State};

handle_cast({broadcast, decision, ApprovalId, DecisionData}, State) ->
    EventData = DecisionData#{
        type => <<"decision">>,
        approval_id => ApprovalId,
        timestamp => erlang:monotonic_time(millisecond)
    },
    broadcast_to_approval_streams(ApprovalId, <<"decision">>, EventData),
    {noreply, State};

handle_cast({close_stream, StreamId}, State) ->
    case maps:get(StreamId, State#state.streams, undefined) of
        {Pid, Ref} ->
            demonitor(Ref),
            Pid ! close,
            {noreply, State#state{
                streams = maps:remove(StreamId, State#state.streams)
            }};
        undefined ->
            {noreply, State}
    end;

handle_cast({unregister_client, ClientId}, State) ->
    {noreply, State#state{
        clients = maps:remove(ClientId, State#state.clients)
    }};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', Ref, process, _Pid, _Reason}, State) ->
    %% Stream process died, clean up
    Streams = maps:filter(fun(_K, {P, R}) -> {P, R} =/= {undefined, Ref} end, State#state.streams),
    Clients = maps:filter(fun(_K, V) -> not maps:is_key(V, Streams) end, State#state.clients),
    {noreply, State#state{
        streams = Streams,
        clients = Clients
    }};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%====================================================================
%% Stream Loop
%%====================================================================

%% @private
stream_loop(Parent, StreamId, ApprovalId) ->
    receive
        {send, Event} ->
            %% In production, this would send via Cowboy SSE handler
            io:format("SSE [~p/~p]: ~s~n", [StreamId, ApprovalId, Event]),
            stream_loop(Parent, StreamId, ApprovalId);
        close ->
            ok;
        _ ->
            stream_loop(Parent, StreamId, ApprovalId)
    end.

%%====================================================================
%% Private Functions
%%====================================================================

%% @private
format_sse_event(EventType, Data) ->
    EventId = generate_id(),
    DataJson = jiffy:encode(Data),
    io_lib:format("id: ~s~nevent: ~s~ndata: ~s~n~n", [EventId, EventType, DataJson]).

%% @private
find_stream_for_approval(ApprovalId, State) ->
    Streams = maps:to_list(State#state.streams),
    case lists:search(fun({_, {Pid, _}}) ->
        is_process_alive(Pid)
    end, Streams) of
        {value, {StreamId, _}} ->
            {ok, StreamId};
        false ->
            none
    end.

%% @private
broadcast_to_approval_streams(ApprovalId, EventType, Data) ->
    %% Send to all streams listening for this approval
    %% In production, this would use pub/sub or similar
    yawl_sse_hitl:send_approval_event(ApprovalId, EventType, Data).

%% @private
generate_id() ->
    Binary = term_to_binary({node(), erlang:monotonic_time(microsecond), erlang:unique_integer([positive])}),
    list_to_binary(lists:flatten([io_lib:format("~2.16.0B", [B]) || <<B>> <= Binary])).
