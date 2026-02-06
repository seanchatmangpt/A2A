%%%-------------------------------------------------------------------
%%% @doc Event adapter between A2A tasks and beamai subsystems.
%%% Subscribes to A2A task events (via erlang:monitor) and forwards
%%% to beamai_a2a_push:notify_async/2. Subscribes to beamai events
%%% and forwards to yawl_a2a_events:publish/2.
%%% @end
%%%-------------------------------------------------------------------
-module(beamai_event_adapter).
-behaviour(gen_server).

-export([start_link/0, start_link/1, subscribe/2, unsubscribe/1, publish/2]).
-export([init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

-include_lib("beamai_core/include/beamai_common.hrl").

-define(SERVER, ?MODULE).

-record(sub, {ref :: reference(), pid :: pid(),
              type :: a2a_task | beamai_event, id :: binary()}).

-record(state, {
    subscriptions :: #{reference() => #sub{}},
    task_monitors :: #{pid() => reference()}
}).

%%====================================================================
%% API
%%====================================================================

start_link() -> start_link(#{}).
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

-spec subscribe(a2a_task | beamai_event, pid() | binary()) ->
    {ok, reference()} | {error, term()}.
subscribe(Type, Target) ->
    gen_server:call(?SERVER, {subscribe, Type, Target}, ?DEFAULT_TIMEOUT).

-spec unsubscribe(reference()) -> ok.
unsubscribe(Ref) -> gen_server:cast(?SERVER, {unsubscribe, Ref}).

-spec publish(atom(), map()) -> ok.
publish(EventType, Data) ->
    gen_server:cast(?SERVER, {publish, EventType, Data}).

%%====================================================================
%% gen_server callbacks
%%====================================================================

init(_Opts) ->
    {ok, #state{subscriptions = #{}, task_monitors = #{}}}.

handle_call({subscribe, a2a_task, TaskPid}, _From, State) when is_pid(TaskPid) ->
    #state{subscriptions = Subs, task_monitors = TM} = State,
    Ref = erlang:monitor(process, TaskPid),
    Sub = #sub{ref = Ref, pid = TaskPid, type = a2a_task,
               id = list_to_binary(pid_to_list(TaskPid))},
    {reply, {ok, Ref},
     State#state{subscriptions = Subs#{Ref => Sub},
                 task_monitors = TM#{TaskPid => Ref}}};
handle_call({subscribe, beamai_event, SourceId}, _From, State)
  when is_binary(SourceId) ->
    #state{subscriptions = Subs} = State,
    Ref = make_ref(),
    Sub = #sub{ref = Ref, pid = self(), type = beamai_event, id = SourceId},
    {reply, {ok, Ref}, State#state{subscriptions = Subs#{Ref => Sub}}};
handle_call(_Request, _From, S) ->
    {reply, {error, unknown_request}, S}.

handle_cast({unsubscribe, Ref}, #state{subscriptions = Subs, task_monitors = TM} = S) ->
    case maps:find(Ref, Subs) of
        {ok, #sub{type = a2a_task, pid = Pid}} ->
            erlang:demonitor(Ref, [flush]),
            {noreply, S#state{subscriptions = maps:remove(Ref, Subs),
                              task_monitors = maps:remove(Pid, TM)}};
        {ok, _} ->
            {noreply, S#state{subscriptions = maps:remove(Ref, Subs)}};
        error -> {noreply, S}
    end;
handle_cast({publish, EventType, Data}, S) ->
    forward_to_beamai(Data),
    forward_to_yawl(EventType, Data),
    {noreply, S};
handle_cast(_Msg, S) -> {noreply, S}.

handle_info({'DOWN', Ref, process, Pid, Reason}, State) ->
    #state{subscriptions = Subs, task_monitors = TM} = State,
    case maps:find(Ref, Subs) of
        {ok, #sub{type = a2a_task, id = Id}} ->
            Terminal = case Reason of normal -> completed; _ -> failed end,
            TaskData = #{id => Id, status => #{state => Terminal}},
            forward_to_beamai(TaskData),
            forward_to_yawl(state_changed, TaskData),
            {noreply, State#state{subscriptions = maps:remove(Ref, Subs),
                                  task_monitors = maps:remove(Pid, TM)}};
        _ -> {noreply, State}
    end;
handle_info({a2a_task_event, TaskId, {state_changed, NewState}}, S) ->
    StateBin = beamai_a2a_types:task_state_to_binary(NewState),
    TaskData = #{id => TaskId, status => #{state => NewState}},
    spawn(fun() -> beamai_a2a_push:notify_async(TaskId, TaskData) end),
    forward_to_yawl(state_changed, #{task_id => TaskId, state => StateBin}),
    {noreply, S};
handle_info({yawl_a2a_event, EventType, Data}, S) ->
    forward_to_beamai(Data),
    {noreply, S};
handle_info(_Info, S) -> {noreply, S}.

terminate(_Reason, #state{subscriptions = Subs}) ->
    maps:foreach(fun(Ref, #sub{type = a2a_task}) ->
        erlang:demonitor(Ref, [flush]);
    (_Ref, _Sub) -> ok
    end, Subs),
    ok.

code_change(_OldVsn, S, _Extra) -> {ok, S}.

%%====================================================================
%% Internal
%%====================================================================

forward_to_beamai(Data) ->
    Id = maps:get(task_id, Data, maps:get(id, Data, <<>>)),
    case Id of
        <<>> -> ok;
        _ -> spawn(fun() -> catch beamai_a2a_push:notify_async(Id, Data) end)
    end, ok.

forward_to_yawl(EventType, Data) ->
    spawn(fun() -> catch yawl_a2a_events:publish(EventType, Data) end), ok.
