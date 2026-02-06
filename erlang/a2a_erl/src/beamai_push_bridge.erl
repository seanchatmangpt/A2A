%%% @doc Bridge for push notifications
%%%
%%% gen_server that registers push endpoints with beamai_a2a_push and
%%% forwards notifications from the legacy a2a_push_notifier. Maintains
%%% a mapping of task/endpoint registrations.
-module(beamai_push_bridge).
-behaviour(gen_server).

-include("a2a.hrl").
-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, register/3, notify/3, unregister/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    registrations = #{} :: #{binary() => [map()]}
}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Register a push endpoint for a task.
%% PushConfig is a map with url, token, and auth fields.
-spec register(binary(), binary(), map()) -> ok | {error, term()}.
register(TaskId, EndpointId, PushConfig) ->
    gen_server:call(?MODULE, {register, TaskId, EndpointId, PushConfig}).

%% @doc Send a notification for a task to all registered endpoints.
-spec notify(binary(), atom(), map()) -> ok.
notify(TaskId, EventType, Data) ->
    gen_server:cast(?MODULE, {notify, TaskId, EventType, Data}).

%% @doc Unregister a push endpoint for a task.
-spec unregister(binary(), binary()) -> ok.
unregister(TaskId, EndpointId) ->
    gen_server:call(?MODULE, {unregister, TaskId, EndpointId}).

%%% gen_server callbacks

init([]) ->
    {ok, #state{}}.

handle_call({register, TaskId, EndpointId, PushConfig}, _From, State) ->
    %% Register with beamai_a2a_push
    BeamaiPushCfg = #{url => maps:get(url, PushConfig, <<>>),
                      token => maps:get(token, PushConfig, undefined),
                      authentication => maps:get(auth, PushConfig, undefined)},
    case ?SAFE_EXEC(beamai_a2a_push:register({TaskId, BeamaiPushCfg})) of
        {ok, _} ->
            Entry = #{endpoint_id => EndpointId,
                      config => PushConfig,
                      registered_at => erlang:system_time(millisecond)},
            Regs = State#state.registrations,
            Existing = maps:get(TaskId, Regs, []),
            %% Replace if endpoint_id already exists
            Filtered = [E || E <- Existing,
                             maps:get(endpoint_id, E) =/= EndpointId],
            NewRegs = Regs#{TaskId => [Entry | Filtered]},
            {reply, ok, State#state{registrations = NewRegs}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

handle_call({unregister, TaskId, EndpointId}, _From, State) ->
    Regs = State#state.registrations,
    Existing = maps:get(TaskId, Regs, []),
    Filtered = [E || E <- Existing,
                     maps:get(endpoint_id, E) =/= EndpointId],
    NewRegs = case Filtered of
        [] -> maps:remove(TaskId, Regs);
        _ -> Regs#{TaskId => Filtered}
    end,
    {reply, ok, State#state{registrations = NewRegs}};

handle_call(_Req, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast({notify, TaskId, EventType, Data}, State) ->
    Regs = State#state.registrations,
    case maps:find(TaskId, Regs) of
        {ok, Endpoints} ->
            TaskData = #{event_type => EventType, data => Data,
                         task_id => TaskId,
                         timestamp => erlang:system_time(millisecond)},
            %% Notify via beamai_a2a_push
            beamai_a2a_push:notify_async(TaskId, TaskData),
            %% Also notify via legacy a2a_push_notifier for each endpoint
            lists:foreach(fun(#{config := Cfg}) ->
                legacy_notify(TaskId, EventType, Data, Cfg)
            end, Endpoints);
        error ->
            ok
    end,
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% Internal

legacy_notify(TaskId, _EventType, Data, Cfg) ->
    Url = maps:get(url, Cfg, <<>>),
    Payload = json:encode(#{task_id => TaskId, data => Data}),
    Headers = build_legacy_headers(Cfg),
    Request = {binary_to_list(Url), Headers, "application/json", Payload},
    spawn(fun() ->
        ?SAFE_EXEC(httpc:request(post, Request, [{timeout, 10000}], []))
    end),
    ok.

build_legacy_headers(Cfg) ->
    Base = [{"Content-Type", "application/json"}],
    case maps:get(token, Cfg, undefined) of
        undefined -> Base;
        Token -> [{"Authorization", "Bearer " ++ binary_to_list(Token)} | Base]
    end.
