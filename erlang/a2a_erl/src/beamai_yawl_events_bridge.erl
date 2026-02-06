%%%-------------------------------------------------------------------
%%% @doc BeamAI YAWL Events Bridge
%%% gen_server that subscribes to YAWL workflow events, translates
%%% them to beamai format, and forwards beamai events to yawl_a2a_events.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_yawl_events_bridge).
-behaviour(gen_server).

-include_lib("beamai_core/include/beamai_common.hrl").
-include("yawl_types.hrl").
-include("a2a.hrl").

-export([start_link/0, subscribe/2, publish/2,
         forward_yawl_event/1, forward_beamai_event/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    yawl_sub    = undefined :: term(),
    subscribers = #{} :: #{atom() => [pid()]}
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

subscribe(EventType, Pid) ->
    gen_server:call(?MODULE, {subscribe, EventType, Pid}).

publish(EventType, EventData) ->
    gen_server:cast(?MODULE, {publish, EventType, EventData}).

forward_yawl_event(Event) ->
    gen_server:cast(?MODULE, {forward_yawl, Event}).

forward_beamai_event(Event) ->
    gen_server:cast(?MODULE, {forward_beamai, Event}).

init([]) ->
    Sub = case whereis(yawl_a2a_events) of
        undefined -> undefined;
        _Pid      -> catch yawl_a2a_events:subscribe(self())
    end,
    {ok, #state{yawl_sub = Sub}}.

handle_call({subscribe, EventType, Pid}, _From, State) ->
    Existing = maps:get(EventType, State#state.subscribers, []),
    NewSubs = case lists:member(Pid, Existing) of
        true  -> State#state.subscribers;
        false -> maps:put(EventType, [Pid | Existing], State#state.subscribers)
    end,
    {reply, ok, State#state{subscribers = NewSubs}};
handle_call(_Req, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({publish, Type, Data}, State) ->
    notify_subscribers(Type, to_beamai(Type, Data), State),
    {noreply, State};
handle_cast({forward_yawl, Event}, State) ->
    Type = maps:get(type, Event, unknown),
    notify_subscribers(Type, to_beamai(Type, Event), State),
    {noreply, State};
handle_cast({forward_beamai, Event}, State) ->
    YE = to_yawl(Event),
    catch yawl_a2a_events:publish(maps:get(type, YE, unknown), YE),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({yawl_event, Type, Data}, State) ->
    notify_subscribers(Type, to_beamai(Type, Data), State),
    {noreply, State};
handle_info({'DOWN', _Ref, process, Pid, _}, State) ->
    NewSubs = maps:map(fun(_, Pids) -> lists:delete(Pid, Pids) end,
                       State#state.subscribers),
    {noreply, State#state{subscribers = NewSubs}};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% Internal
to_beamai(workitem_created, D) ->
    #{source => yawl, type => tool_registered,
      tool_name => maps:get(task_name, D, <<>>), metadata => D};
to_beamai(workitem_completed, D) ->
    #{source => yawl, type => tool_completed,
      result => maps:get(result, D, #{}), metadata => D};
to_beamai(workitem_failed, D) ->
    #{source => yawl, type => tool_failed,
      error => maps:get(error, D, undefined), metadata => D};
to_beamai(workflow_started, D) ->
    #{source => yawl, type => agent_started, metadata => D};
to_beamai(workflow_completed, D) ->
    #{source => yawl, type => agent_completed, metadata => D};
to_beamai(Type, D) ->
    #{source => yawl, type => Type, metadata => D}.

to_yawl(#{type := tool_completed} = E) ->
    #{type => workitem_completed, result => maps:get(result, E, #{}), source => beamai};
to_yawl(#{type := tool_failed} = E) ->
    #{type => workitem_failed, error => maps:get(error, E, undefined), source => beamai};
to_yawl(#{type := agent_completed}) ->
    #{type => workflow_completed, source => beamai};
to_yawl(E) ->
    #{type => maps:get(type, E, unknown), source => beamai, metadata => E}.

notify_subscribers(Type, Event, State) ->
    Pids = lists:usort(maps:get(Type, State#state.subscribers, []) ++
                       maps:get(all, State#state.subscribers, [])),
    [Pid ! {beamai_event, Type, Event} || Pid <- Pids],
    ok.
