%%% @doc Bridge between a2a_task_statem and beamai_a2a_task
%%%
%%% Creates BOTH an a2a_task_statem and a beamai_a2a_task process for each
%%% task, monitoring both and syncing state bidirectionally.
-module(beamai_task_bridge).
-behaviour(gen_server).

-include("a2a.hrl").
-include_lib("beamai_core/include/beamai_common.hrl").

%% API
-export([start_link/0, create_task/1, sync_state/2,
         get_unified_task/1, translate_to_beamai/1, translate_from_beamai/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    task_map = #{} :: #{binary() => {pid(), pid()}},
    monitors = #{} :: #{reference() => {binary(), a2a | beamai}}
}).

%%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

create_task(#{message := Msg} = Params) ->
    gen_server:call(?MODULE, {create_task, Params}, ?DEFAULT_TIMEOUT).

sync_state(TaskId, Source) ->
    gen_server:cast(?MODULE, {sync_state, TaskId, Source}).

get_unified_task(TaskId) ->
    gen_server:call(?MODULE, {get_unified_task, TaskId}).

translate_to_beamai(#task{id = Id, context_id = Ctx, status = St, history = Hist,
                          artifacts = Arts, metadata = Meta}) ->
    #{id => Id, context_id => Ctx,
      status => (St#task_status.state),
      history => [msg_to_map(M) || M <- Hist],
      artifacts => [art_to_map(A) || A <- Arts],
      metadata => Meta}.

translate_from_beamai(#{id := Id, context_id := Ctx} = M) ->
    State = maps:get(status, M, submitted),
    Now = erlang:system_time(millisecond),
    #task{id = Id, context_id = Ctx,
          status = #task_status{state = State, timestamp = Now},
          history = [], artifacts = [],
          metadata = maps:get(metadata, M, #{})}.

%%% gen_server callbacks

init([]) ->
    {ok, #state{}}.

handle_call({create_task, #{message := Msg} = Params}, _From, State) ->
    TaskId = maps:get(task_id, Params, generate_id()),
    CtxId = maps:get(context_id, Params, generate_id()),
    Meta = maps:get(metadata, Params, #{}),
    %% Start legacy a2a_task_statem
    A2aResult = a2a_task_statem:start_link(Msg),
    case A2aResult of
        {ok, A2aPid} ->
            %% Start beamai_a2a_task
            BeamaiOpts = #{message => Msg, context_id => CtxId,
                           task_id => TaskId, metadata => Meta},
            case beamai_a2a_task:start_link(BeamaiOpts) of
                {ok, BeamaiPid} ->
                    Ref1 = erlang:monitor(process, A2aPid),
                    Ref2 = erlang:monitor(process, BeamaiPid),
                    Map = (State#state.task_map)#{TaskId => {A2aPid, BeamaiPid}},
                    Mons = (State#state.monitors)#{
                        Ref1 => {TaskId, a2a}, Ref2 => {TaskId, beamai}},
                    {reply, {ok, TaskId},
                     State#state{task_map = Map, monitors = Mons}};
                {error, Reason} ->
                    {reply, {error, {beamai_start_failed, Reason}}, State}
            end;
        {error, Reason} ->
            {reply, {error, {a2a_start_failed, Reason}}, State}
    end;

handle_call({get_unified_task, TaskId}, _From, State) ->
    case maps:find(TaskId, State#state.task_map) of
        {ok, {A2aPid, BeamaiPid}} ->
            A2aTask = case a2a_task_statem:get_task(A2aPid) of
                          {ok, T} -> T;
                          _ -> undefined
                      end,
            BeamaiData = case beamai_a2a_task:get(BeamaiPid) of
                             {ok, D} -> D;
                             _ -> #{}
                         end,
            Unified = merge_tasks(A2aTask, BeamaiData),
            {reply, {ok, Unified}, State};
        error ->
            {reply, {error, not_found}, State}
    end;

handle_call(_Req, _From, State) ->
    {reply, {error, unknown}, State}.

handle_cast({sync_state, TaskId, Source}, State) ->
    case maps:find(TaskId, State#state.task_map) of
        {ok, {A2aPid, BeamaiPid}} ->
            case Source of
                a2a ->
                    case a2a_task_statem:get_task(A2aPid) of
                        {ok, T} ->
                            NewState = (T#task.status)#task_status.state,
                            beamai_a2a_task:update_status(BeamaiPid, NewState);
                        _ -> ok
                    end;
                beamai ->
                    case beamai_a2a_task:get(BeamaiPid) of
                        {ok, #{status := St}} ->
                            a2a_task_statem:update_status(A2aPid, St);
                        _ -> ok
                    end
            end,
            {noreply, State};
        error ->
            {noreply, State}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', Ref, process, _Pid, _Reason}, State) ->
    case maps:find(Ref, State#state.monitors) of
        {ok, {TaskId, _Which}} ->
            Mons = maps:remove(Ref, State#state.monitors),
            Map = maps:remove(TaskId, State#state.task_map),
            {noreply, State#state{task_map = Map, monitors = Mons}};
        error ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% Internal

generate_id() -> binary:encode_hex(crypto:strong_rand_bytes(16)).

msg_to_map(#message{message_id = Id, role = R, parts = Ps}) ->
    #{message_id => Id, role => R, parts => [part_to_map(P) || P <- Ps]}.

part_to_map(#part{content = C, metadata = M}) -> #{content => C, metadata => M}.

art_to_map(#artifact{artifact_id = Id, name = N, parts = Ps}) ->
    #{artifact_id => Id, name => N, parts => [part_to_map(P) || P <- Ps]}.

merge_tasks(undefined, BeamaiData) -> BeamaiData;
merge_tasks(A2aTask, BeamaiData) when is_map(BeamaiData) ->
    maps:merge(translate_to_beamai(A2aTask), maps:with([metadata], BeamaiData)).
